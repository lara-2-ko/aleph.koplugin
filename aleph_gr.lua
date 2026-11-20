-- Aleph modification, 2026-11-18: Goodreads inside Aleph, in place of
-- advokatb's Goodreads plugin.
--[[--
Aleph keeps Goodreads up to date itself, with that plugin's Goodreads code
taken in (aleph_gr_api, aleph_gr_legacy, aleph_gr_parser, aleph_gr_ids,
aleph_gr_settings; MIT). It uses the plugin's own files, so nothing has to
be moved when the plugin is turned off: the sign-in and settings in
settings/goodreads_settings.lua, each book's link in its sidecar under
"goodreads", and the plugin's list of things waiting to be sent.

While the plugin is still on, Aleph sends nothing on its own (two of them
sending would send twice): each time KOReader starts, a warning says that
Goodreads is part of Aleph now and offers to turn the plugin off (as
Plugin management does, then a restart); Settings > Library offers it too.
Aleph no longer works through the plugin in any way.

What is sent, always in a background process (the reader never waits):

  a book opens        linked by the Goodreads id in the book (Calibre's
                      metadata.opf or the EPUB's), else its ISBN, when it
                      is not linked yet; then Currently reading, if
                      Goodreads does not have it on another shelf (asked
                      first, as before: aleph_goodreads_track.lua)
  pages turn          the percentage, at most once a minute
  the book closes     the percentage
  status changes      Finished -> Read (with the day and the stars),
  (book page, Home,   Reading -> Currently reading, On hold -> Did not
  KOReader's own      finish (when the account has that shelf), Unread ->
  status)             Want to read (only for a book Goodreads does not have)
  stars change        sent for a book that is Read on Goodreads

Every status is checked against Goodreads first. A book Goodreads has as
Read is never shelved or dated again (Goodreads counts that as another
reading, "Read 2 times", which the plugin did when a book was finished:
once from the end of the book, again from the status change) and is never
moved off Read automatically. Books are sent only when linked and tracked
(the book's own switch, else "Track every book").

Without internet, changes wait in the list and go when Goodreads answers
again (Wi-Fi is never turned on for this). One that fails five times is
kept aside as failed; Settings can try those again or drop them.
]]

local logger = require("logger")
local try = require("aleph_try").call
local Prefs = require("aleph_prefs")

local Core = {}

Core.MAX_ATTEMPTS = 5
Core.BATCH = 5
Core.WAIT = 120

local host                    -- Aleph's Goodreads state (see Core.host)
local job                     -- { pid, ops }
local again = false
local recent = {}             -- [file .. status] = time: the same change once

local function api()
    local Api = require("aleph_gr_api")
    Api.settings = Core.host().settings
    return Api
end

local function resultPath()
    return require("datastorage"):getSettingsDir() .. "/aleph_goodreads_sync.lua"
end

-- ------------------------------------------------------------- the host
-- Shared by the sign-in (aleph_goodreads.lua), Send to Goodreads
-- (aleph_goodreads_send.lua) and the tracking of the open book
-- (aleph_goodreads_track.lua): the settings (aleph_gr_settings.lua, on the
-- plugin's file), the open book's ui and its state.
local Host = {}
Host.__index = Host

function Core.host()
    if host then return host end
    local GS = require("aleph_gr_settings")
    local path = require("datastorage"):getSettingsDir() .. "/goodreads_settings.lua"
    host = setmetatable({ state = {}, ui = nil, settings = GS:new(path, nil) }, Host)
    return host
end

function Host:_hasSession()
    local ok, yes = pcall(function() return self.settings:hasCookie() end)
    return ok and yes or false
end

function Host:_canAutoSync(file)
    if not file or not self:_hasSession() then return false end
    if not self.settings:readBookSetting(file, "edition_id") then return false end
    return self.settings:fileSyncEnabled(file)
end

function Host:_readingPercent()
    local ui = self.ui
    if not (ui and ui.document) then return nil end
    local pct
    try(function() pct = tonumber(ui.doc_settings:readSetting("percent_finished")) end)
    if not pct and self.state.page then
        try(function()
            local total = ui.document:getPageCount()
            if total and total > 0 then pct = self.state.page / total end
        end)
    end
    return pct
end

function Host:onCookiesSaved()
    Core.reset()
    return Core.flush()
end

-- ------------------------------------------------- the plugin, still on?
-- advokatb's plugin: named "goodreads", with a settings object that keeps
-- the cookie under "session_cookie" (other Goodreads plugins differ).
function Core.isAdvokat(p)
    if type(p) ~= "table" then return false end
    local s = p.settings
    return type(s) == "table" and type(s.setCookie) == "function" and type(s.getCookie) == "function"
        and s.KEY_COOKIE == "session_cookie"
end

-- Whether advokatb's plugin is running now (the file browser's or the
-- reader's instance).
function Core.pluginOn(ui)
    local found = false
    local list = {}
    try(function() list = require("aleph_plugins").hosts(ui) end)
    if #list == 0 and ui then list = { ui } end
    for _i, h in ipairs(list) do
        try(function() if Core.isAdvokat(rawget(h, "goodreads") or h.goodreads) then found = true end end)
    end
    if not found then
        try(function() found = Core.isAdvokat(require("pluginloader"):getPluginInstance("goodreads")) end)
    end
    return found
end

-- Aleph sends on its own only with the plugin off (and its switch on): two
-- of them sending would send twice.
function Core.enabled(ui)
    if Prefs.get().goodreads_own == false then return false end
    return not Core.pluginOn(ui)
end

-- Turns the plugin off as KOReader's Plugin management does; it stops at
-- the next start.
function Core.disablePlugin()
    local list = G_reader_settings:readSetting("plugins_disabled") or {}
    list.goodreads = true
    G_reader_settings:saveSetting("plugins_disabled", list)
    try(function() G_reader_settings:flush() end)
    logger.info("Aleph: the Goodreads plugin is turned off; Aleph sends to Goodreads from the next start")
end

-- The question to turn it off, then to restart (Settings, and the warning).
function Core.askDisablePlugin(text)
    local _ = require("aleph_gettext")
    require("aleph_confirm").show{
        -- Only its own buttons close it: a stray tap (a page turn) does not.
        modal = true,
        title = _("Goodreads is now part of Aleph"),
        text = text or _("Aleph now keeps Goodreads up to date itself, with the plugin's sign-in, settings and book links. With both on, things could be sent twice.\n\nTurn the Goodreads plugin off? It stops when KOReader starts again. It can be turned back on in Tools → Plugin management."),
        ok_label = _("Turn off"), cancel_label = _("Later"),
        on_ok = function()
            Core.disablePlugin()
            local UIManager = require("ui/uimanager")
            if UIManager.askForRestart then
                UIManager:askForRestart(_("KOReader needs to restart to turn the Goodreads plugin off."))
            else
                try(function() require("aleph_toast").show(_("Restart KOReader to turn the Goodreads plugin off."), { icon = "info", timeout = 6 }) end)
            end
        end,
    }
end

-- Once each time KOReader starts, while advokatb's plugin is on: Goodreads
-- is in Aleph now, turn the plugin off. Asked a moment after the file
-- browser or a book is ready (the plugin's instance exists by then).
local warned = false
function Core.warnPlugin(ui)
    if warned then return false end
    if not Core.pluginOn(ui) then return false end
    warned = true
    logger.info("Aleph: advokatb's Goodreads plugin is on; Aleph's own Goodreads waits until it is off")
    local _ = require("aleph_gettext")
    Core.askDisablePlugin(_("The Goodreads plugin by advokatb is on. Goodreads is part of Aleph now and uses the plugin's sign-in, settings and book links, so the plugin is no longer needed.\n\nWhile it is on, Aleph sends nothing to Goodreads on its own, so nothing is sent twice. Turn the plugin off? It stops when KOReader starts again."))
    return true
end

-- ---------------------------------------------------------- what to send
local CODE_FOR = { read = 1, reading = 2, on_hold = 3, unread = 0,
    complete = 1, abandoned = 3, new = 0 }

-- The stars the sidecar has for `file`, for Goodreads (1–5), or 0.
local function starsOf(file, stars)
    local h = Core.host()
    if not h.settings:syncRatingEnabled() then return 0 end
    local r = tonumber(stars)
    if not r then try(function() r = h.settings:getKoreaderRating(file) end) end
    r = tonumber(r)
    if not r or r < 0.5 then return 0 end
    return math.max(1, math.min(5, math.floor(r + 0.5)))
end

-- The day a status is about: "YYYY-MM-DD" -> {year, month, day}.
local function dayOf(s)
    if type(s) ~= "string" then return nil end
    local y, m, d = s:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)")
    if y then return { year = tonumber(y), month = tonumber(m), day = tonumber(d) } end
    return nil
end

-- Puts a status change of `file` on the list to send. status: Aleph's
-- (read, reading, on_hold, unread) or KOReader's (complete, reading,
-- abandoned, new). opts: rating (stars), finishedOn ("YYYY-MM-DD").
-- Returns true when something was put on the list.
function Core.statusChanged(file, status, opts, ui)
    opts = opts or {}
    if not file or not Core.enabled(ui) then return false end
    local code = CODE_FOR[status]
    if code == nil then return false end
    local h = Core.host()
    local S = h.settings
    if not h:_hasSession() then return false end
    local id = S:readBookSetting(file, "edition_id")
    if not id or not S:fileSyncEnabled(file) then return false end
    local shelf = require("aleph_gr_api"):shelfForStatus(code)
    if code == 3 and not S:hasExclusiveShelf("did-not-finish") then return false end
    -- What Aleph knows Goodreads has already: nothing to send.
    local had = S:readBookSetting(file, "shelf")
    if had == shelf then
        if code == 1 then return Core.ratingChanged(file, opts.rating, ui) end
        return false
    end
    -- The same change heard twice (Aleph's own and KOReader's): once.
    local key = file .. "|" .. tostring(code)
    if recent[key] and os.time() - recent[key] < 120 then return false end
    recent[key] = os.time()
    local op = { operation = "status", book_id = tostring(id), file = file, status = code, shelf = shelf,
        title = S:readBookSetting(file, "title"), author = S:readBookSetting(file, "authors") }
    if code == 1 then
        op.rating = starsOf(file, opts.rating)
        op.date = dayOf(opts.finishedOn) or os.date("*t")
        op.date = { year = op.date.year, month = op.date.month, day = op.date.day }
    end
    S:enqueueSync(op)
    logger.info("Aleph: Goodreads: to send", shelf, "for", tostring(op.title or id))
    Core.flush()
    return true
end

-- Stars changed: sent for a book that is Read (Goodreads moves a rated
-- book to Read, so a book on another shelf is not rated from here).
function Core.ratingChanged(file, stars, ui)
    if not file or not Core.enabled(ui) then return false end
    local h = Core.host()
    local S = h.settings
    if not h:_hasSession() then return false end
    local id = S:readBookSetting(file, "edition_id")
    if not id or not S:fileSyncEnabled(file) or S:readBookSetting(file, "shelf") ~= "read" then return false end
    local r = starsOf(file, stars)
    if r < 1 or tonumber(S:readBookSetting(file, "rating")) == r then return false end
    S:enqueueSync({ operation = "rating", book_id = tostring(id), file = file, rating = r,
        title = S:readBookSetting(file, "title") })
    Core.flush()
    return true
end

-- The percentage of a book closed without internet, sent later.
function Core.queueProgress(file, pct)
    local S = Core.host().settings
    local id = S:readBookSetting(file, "edition_id")
    if not id or not pct then return end
    S:enqueueSync({ operation = "progress", book_id = tostring(id), file = file, percent = pct,
        title = S:readBookSetting(file, "title"), author = S:readBookSetting(file, "authors") })
end

local function isAuth(err)
    return err == "session_expired" or err == "no_cookies" or err == "waf_challenge"
end

-- Aleph modification, 2026-11-19: another Goodreads book of the same title
-- and author as `title` / `author`, found by a search, for a book the id
-- `id` cannot be shelved under; or nil. The title must match (up to a
-- subtitle) and, when an author is known, one of the author's names.
local function norm(str)
    return (tostring(str or ""):lower():gsub("[%p%s]+", " "):gsub("^ ", ""):gsub(" $", ""))
end
function Core.findAnother(Api, id, title, author)
    local main = norm((tostring(title or ""):gsub("%s*[:%(%[].*$", "")))
    if main == "" or main:match("^goodreads ") then return nil end
    local names = {}
    for word in norm(author):gmatch("%S+") do
        if #word >= 3 then names[#names + 1] = word end
    end
    local list = Api:search(main .. (#names > 0 and (" " .. names[#names]) or ""))
    for _i, b in ipairs(type(list) == "table" and list or {}) do
        local t = norm(b.title)
        if tostring(b.edition_id) ~= tostring(id) and (t == main or t:sub(1, #main + 1) == main .. " ") then
            local by = #names == 0
            local them = " " .. norm(b.authors) .. " "
            for _j, word in ipairs(names) do
                if them:find(" " .. word .. " ", 1, true) then by = true end
            end
            if by then return b end
        end
    end
    return nil
end

-- ------------------------------------------- in the background process
-- Runs a list of operations with Goodreads' answers checked first.
-- Returns { results = { [i] = { ok, done, remote, update, error } },
-- cookie, user_id, csrf, shelves }.
function Core.work(Api, settings, ops)
    local out = { results = {} }
    local backend = Api:_get_backend()
    for i, op in ipairs(ops) do
        local r = {}
        out.results[i] = r
        -- One try with Goodreads book `id`, whose state is `st`.
        local function attempt(id, st)
            r.remote = { shelf = st.shelf or false, status = st.status or false, rating = tonumber(st.rating) or 0,
                review_id = st.review_id or false }
            local update = {}
            r.update = update
            if op.operation == "rating" then
                if st.shelf ~= "read" then r.ok, r.done = true, "not-read"; return end
                if (tonumber(st.rating) or 0) == op.rating then r.ok, r.done = true, "already"; update.rating = op.rating; return end
                local res = Api:set_rating(id, op.rating)
                if res and res.ok then r.ok, r.done = true, "rated"; update.rating = op.rating
                else r.error = res and res.error_text or "rating" end
                return
            end
            if op.operation == "progress" then
                if st.shelf == "read" or st.shelf == "did-not-finish" then r.ok, r.done = true, "not-reading"; return end
                if st.shelf ~= "currently-reading" then
                    if st.shelf then r.ok, r.done = true, "other-shelf"; return end
                    local s2 = Api:set_status(id, 2, nil, 0)
                    if not (s2 and s2.ok) then r.error = "status"; return end
                    update.status, update.shelf = 2, "currently-reading"
                end
                local res = Api:set_progress(id, op.percent)
                if res and res.ok then r.ok, r.done = true, "progress"; update.last_progress = tonumber(res.percent) or op.percent
                else r.error = res and (res.error_text or res.error) or "progress" end
                return
            end
            if op.operation ~= "status" then r.ok, r.done = true, "skipped"; return end
            local target = op.shelf
            if st.shelf == target then
                -- There already. A Read book gets its stars only: shelving or
                -- dating it again would be another reading.
                update.status, update.shelf = op.status, target
                if target == "read" and (op.rating or 0) >= 1 and (tonumber(st.rating) or 0) ~= op.rating then
                    local res = Api:set_rating(id, op.rating)
                    if res and res.ok then update.rating = op.rating end
                end
                r.ok, r.done = true, "already"
                return
            end
            if st.shelf == "read" then r.ok, r.done = true, "kept-read"; return end
            if target == "to-read" and st.shelf then r.ok, r.done = true, "kept"; return end
            if target == "read" then
                local res = backend:_add_to_shelf(id, "read", "")
                if not (res and res.ok) then r.error = res and res.error_text or "status"; return end
                update.status, update.shelf = 1, "read"
                if (st.session_count or 0) == 0 then
                    local d = backend:set_date_finished(id, op.date)
                    if d and d.ok and d.date_read then update.date_read = d.date_read end
                end
                if (op.rating or 0) >= 1 then
                    local rr = Api:set_rating(id, op.rating)
                    if rr and rr.ok then update.rating = op.rating end
                end
                r.ok, r.done = true, "read"
                return
            end
            local res = Api:set_status(id, op.status, nil, 0, target)
            if res and res.ok then r.ok, r.done = true, target; update.status, update.shelf = op.status, target
            else r.error = res and res.error_text or "status" end
        end
        local ok, err = pcall(function()
            local st = Api:get_review_state(op.book_id)
            if not (st and st.ok) then r.error = "state"; return end
            attempt(op.book_id, st)
            -- Aleph modification, 2026-11-19: a book Goodreads will not shelve
            -- under the id it is linked to (an id from Calibre that is not
            -- one Goodreads takes): the same title and author found by a
            -- search, and tried again with that.
            if r.ok or isAuth(r.error) or (op.operation ~= "status" and op.operation ~= "progress") then return end
            local other = Core.findAnother(Api, op.book_id, op.title, op.author)
            if not other then return end
            local st2 = Api:get_review_state(other.edition_id)
            if not (st2 and st2.ok) then return end
            local first = r.error
            for k in pairs(r) do r[k] = nil end
            attempt(other.edition_id, st2)
            if r.ok then
                r.relinked, r.relinked_from = other, op.book_id
            else
                r.error = tostring(first) .. "; " .. tostring(other.edition_id) .. ": " .. tostring(r.error)
            end
        end)
        if not ok then r.error = tostring(err) end
        -- What Goodreads answered last, for crash.log.
        if not r.ok then
            pcall(function()
                local a = backend._last_answer
                if a then r.answer = a.method .. " " .. a.path .. " → HTTP " .. a.code .. ": " .. a.text end
            end)
        end
    end
    pcall(function() out.cookie = settings:getCookie() end)
    pcall(function() out.user_id = settings:getUserId() end)
    pcall(function() out.csrf = backend._csrf_token end)
    pcall(function() out.shelves = settings:readSetting(settings.KEY_EXCLUSIVE_SHELVES) end)
    return out
end

-- A book linked again to the Goodreads book found in place of `from`
-- (which Goodreads would not shelve): `from` is kept as unshelvable, so
-- Send to Goodreads does not go back to it from the id in Calibre.
function Core.relink(file, data, from)
    local h = Core.host()
    local Send = require("aleph_goodreads_send")
    Send.forgetLink(h, file)
    Send.saveLink(h, file, data)
    try(function() h.settings:updateBookSetting(file, { unshelvable = tostring(from) }) end)
    logger.info("Aleph: Goodreads: relinked", tostring(data.title), "to", tostring(data.edition_id), "(Goodreads would not shelve", tostring(from) .. ")")
end

-- -------------------------------------------------------- the answers
-- Keeps what the background process learned (the sign-in as Goodreads last
-- gave it, the token, the account's shelves).
function Core.absorb(out)
    local S = Core.host().settings
    try(function()
        if type(out.cookie) == "string" and out.cookie ~= "" and out.cookie ~= S:getCookie() then S:setCookie(out.cookie) end
        if out.user_id and S:getUserId() ~= out.user_id then S:setUserId(out.user_id) end
        if type(out.shelves) == "table" and #out.shelves > 0 then S:setExclusiveShelves(out.shelves) end
        local backend = require("aleph_gr_api"):_get_backend()
        if type(out.csrf) == "string" then backend._csrf_token = out.csrf end
    end)
end

function Core.apply(ops, out)
    local S = Core.host().settings
    local UNSET = S.UNSET
    local sent, auth = 0, false
    Core.absorb(out)
    for i, op in ipairs(ops) do
        local r = out.results and out.results[i] or { error = "no answer" }
        if r.ok then
            S:removeSync(op.operation, op.book_id)
            if r.relinked and op.file then Core.relink(op.file, r.relinked, r.relinked_from) end
            local update = r.update or {}
            if r.remote and not update.shelf then
                update.shelf = r.remote.shelf or UNSET
                update.status = r.remote.status ~= false and r.remote.status or UNSET
            end
            if r.remote and r.remote.review_id then update.review_id = r.remote.review_id end
            if r.remote and (r.remote.rating or 0) > 0 and not update.rating then update.rating = r.remote.rating end
            if op.file and next(update) then try(function() S:updateBookSetting(op.file, update) end) end
            if r.done == "read" or r.done == "rated" or r.done == "currently-reading" or r.done == "did-not-finish"
                or r.done == "to-read" then sent = sent + 1 end
            logger.info("Aleph: Goodreads:", op.operation, tostring(op.title or op.book_id), "->", tostring(r.done))
        else
            if isAuth(r.error) then auth = true end
            local attempts = (tonumber(op.attempts) or 0) + 1
            if attempts >= Core.MAX_ATTEMPTS then S:markSyncFailed(op.operation, op.book_id, r.error)
            else S:bumpSyncAttempt(op.operation, op.book_id) end
            logger.warn("Aleph: Goodreads:", op.operation, tostring(op.title or op.book_id), "not sent:", tostring(r.error),
                r.answer and ("| Goodreads answered " .. r.answer) or "")
        end
    end
    return sent, auth
end

-- ------------------------------------------------------------- sending
function Core.busy() return job ~= nil end

local function online()
    local yes = false
    try(function() yes = require("ui/network/manager"):isConnected() and true or false end)
    return yes
end

-- Sends what is waiting, a few at a time, in a background process.
function Core.flush()
    if job then again = true; return false end
    if not Core.enabled() then return false end
    local h = Core.host()
    if not h:_hasSession() or not online() then return false end
    local Track = package.loaded["aleph_goodreads_track"]
    if Track and Track.busy() then
        require("ui/uimanager"):scheduleIn(5, function() Core.flush() end)
        return false
    end
    local ops = {}
    -- Status first (as the plugin did), then progress and stars.
    for _i, op in ipairs(h.settings:getSyncQueue()) do
        if not op.failed and (op.operation == "status" or op.operation == "remove") and #ops < Core.BATCH then ops[#ops + 1] = op end
    end
    for _i, op in ipairs(h.settings:getSyncQueue()) do
        if not op.failed and (op.operation == "progress" or op.operation == "rating") and #ops < Core.BATCH then ops[#ops + 1] = op end
    end
    if #ops == 0 then return false end
    local Job = require("aleph_job")
    if not Job.available() then return false end
    local Api, settings = api(), h.settings
    local out = resultPath()
    os.remove(out)
    local File = require("aleph_file")
    local pid = Job.start(function()
        local done, r = pcall(Core.work, Api, settings, ops)
        File.write(out, done and r or { results = {}, error = tostring(r) })
    end, { optional = true, name = "goodreads" })
    if not pid then return false end
    job = { pid = pid, ops = ops }
    Job.watch(pid, { every = 2, timeout = Core.WAIT, on_done = function()
        local j = job
        job = nil
        local r = File.read(out) or { results = {} }
        os.remove(out)
        local sent, auth = Core.apply(j.ops, r)
        if sent > 0 then
            try(function()
                local _ = require("aleph_gettext")
                require("aleph_toast").show(_("Sent to Goodreads"), { icon = "check" })
            end)
        end
        if auth then
            try(function()
                local _ = require("aleph_gettext")
                require("aleph_toast").show(_("Goodreads no longer accepts the sign-in. Renew it in Aleph's Settings > Library > Goodreads sign-in."), { icon = "info", timeout = 6 })
            end)
            return
        end
        local left = 0
        for _i, op in ipairs(h.settings:getSyncQueue()) do if not op.failed then left = left + 1 end end
        if again or (left > 0 and sent + #j.ops > 0 and not (r.results[1] and r.results[1].error)) then
            again = false
            require("ui/uimanager"):scheduleIn(3, function() Core.flush() end)
        end
    end })
    return true
end

-- --------------------------------------------------------------- linking
-- The Goodreads book for a book with its id or ISBN written in it, or nil
-- (no search by title: that is chosen by hand, from the book's page).
function Core.findSure(book, Api, Ids)
    local Send = require("aleph_goodreads_send")
    local gr_id, isbn = Send.identifiers(book, Ids)
    if gr_id then
        local data = Api:get_book(gr_id)
        if data then return data end
    end
    if isbn then
        local list = Api:search(isbn)
        if list and list[1] then return list[1] end
    end
    return nil
end

local linking = {}
function Core.autolink(ui)
    local h = Core.host()
    local S = h.settings
    local file = ui and ui.document and ui.document.file
    if not file or linking[file] or not h:_hasSession() or not online() then return false end
    if S:readBookSetting(file, "edition_id") then return false end
    if not (S:autoLinkByGoodreadsId() or S:autoLinkByIsbn()) then return false end
    local Job = require("aleph_job")
    if not Job.available() or job then return false end
    linking[file] = true
    local book = { path = file }
    try(function()
        local props = ui.doc_props or (ui.doc_settings and ui.doc_settings:readSetting("doc_props")) or {}
        book.title = props.title
    end)
    local Api, Ids = api(), require("aleph_gr_ids")
    local out = resultPath() .. ".link"
    os.remove(out)
    local File = require("aleph_file")
    local pid = Job.start(function()
        local done, data = pcall(Core.findSure, book, Api, Ids)
        local okc, cookie = pcall(function() return S:getCookie() end)
        File.write(out, { data = done and data or nil, cookie = okc and cookie or nil })
    end, { optional = true, name = "goodreads link" })
    if not pid then linking[file] = nil; return false end
    Job.watch(pid, { every = 2, timeout = 60, on_done = function()
        local r = File.read(out) or {}
        os.remove(out)
        if type(r.cookie) == "string" and r.cookie ~= "" and r.cookie ~= S:getCookie() then try(function() S:setCookie(r.cookie) end) end
        if type(r.data) ~= "table" or not r.data.edition_id then return end
        if S:readBookSetting(file, "edition_id") then return end
        require("aleph_goodreads_send").saveLink(h, file, r.data)
        logger.info("Aleph: Goodreads: linked", tostring(r.data.title), r.data.edition_id)
        -- What Goodreads has for it, and Currently reading when it is the
        -- open book and tracked.
        if h.ui and h.ui.document and h.ui.document.file == file then
            local Track = require("aleph_goodreads_track")
            try(Track.tick, h, { ensure = true })
        end
    end })
    return true
end

-- --------------------------------------------------------- the reader
-- A book opened (Board:onReaderReady).
function Core.open(ui)
    if not (ui and ui.document) or not Core.enabled(ui) then return end
    local h = Core.host()
    h.ui = ui
    h.settings.ui = ui            -- the open book's sidecar is read from memory
    h.state = { page = nil }
    try(function() h.state.page = ui:getCurrentPage() end)
    if not h:_hasSession() then return end
    local UIManager = require("ui/uimanager")
    UIManager:scheduleIn(3, function()
        if not (h.ui == ui and ui.document) then return end
        if not h.settings:readBookSetting(ui.document.file, "edition_id") then
            Core.autolink(ui)
        else
            try(require("aleph_goodreads_track").tick, h, { ensure = true })
        end
        Core.flush()
    end)
end

-- A page turned: a comparison of two numbers, a question at most once a
-- minute.
function Core.page(ui, page)
    local h = host
    if not h or h.ui ~= ui then return end
    h.state.page = page
    if job then return end
    try(require("aleph_goodreads_track").tick, h)
end

-- The book closes (Board:onCloseDocument): its percentage, now or later.
function Core.close(ui)
    local h = host
    if not h or h.ui ~= ui then return end
    local file = ui.document and ui.document.file
    if file and h:_canAutoSync(file) then
        local Track = require("aleph_goodreads_track")
        if online() then
            try(Track.tick, h, { force = true })
        else
            try(function()
                local plan = Track.plan(h, { force = true })
                if plan and plan.percent then Core.queueProgress(file, plan.percent) end
            end)
        end
    end
    h.ui = nil
    h.settings.ui = nil
    h.state = {}
end

-- KOReader changed a book's status or stars (DocSettingsItemsChanged).
function Core.docChanged(ui, file, doc_settings)
    if type(doc_settings) ~= "table" or type(doc_settings.summary) ~= "table" then return end
    local summary = doc_settings.summary
    if summary.status then Core.statusChanged(file, summary.status, { rating = summary.rating, finishedOn = summary.modified }, ui) end
    if summary.rating then Core.ratingChanged(file, summary.rating, ui) end
end

-- ------------------------------------------------- the reader's sheet
-- The reader sheet's Goodreads button: this book on Goodreads, send now,
-- track it or not.
function Core.readerMenu(ui)
    local _ = require("aleph_gettext")
    local T = require("ffi/util").template
    local Confirm = require("aleph_confirm")
    local h = Core.host()
    local S = h.settings
    local file = ui and ui.document and ui.document.file
    if not file then return end
    if not h:_hasSession() then
        return Confirm.show{
            title = _("Goodreads"),
            text = _("Goodreads is not signed in. Send the sign-in from your computer first (Settings → Library → Goodreads sign-in)."),
            ok_label = _("Open"), cancel_label = _("Close"),
            on_ok = function() require("aleph_goodreads").open(ui) end,
        }
    end
    if not S:readBookSetting(file, "edition_id") then
        return Confirm.show{
            title = _("Goodreads"),
            text = _("This book is not linked to Goodreads yet. Its page in Aleph finds it: ⋯ → Send to Goodreads."),
            ok_label = _("Book page"), cancel_label = _("Close"),
            on_ok = function() try(function() require("aleph_topbar_book").showDetails(ui) end) end,
        }
    end
    local Api = require("aleph_gr_api")
    local Track = require("aleph_goodreads_track")
    local tracked = S:fileSyncEnabled(file)
    local shelf = S:readBookSetting(file, "shelf")
    local lines = { T(_("Goodreads book: %1"), tostring(S:readBookSetting(file, "title") or "?")) }
    lines[#lines + 1] = T(_("On Goodreads: %1"), (type(shelf) == "string" and shelf ~= "") and Api:shelfLabel(shelf) or _("on no shelf"))
    local last = tonumber(S:readBookSetting(file, "last_progress"))
    if last then lines[#lines + 1] = T(_("Progress sent: %1"), tostring(last) .. "%") end
    lines[#lines + 1] = ""
    lines[#lines + 1] = tracked and _("This book is tracked: its progress and status are sent as you read.")
        or _("This book is not tracked: nothing is sent on its own.")
    local function toast(text) try(function() require("aleph_toast").show(text, { icon = "check" }) end) end
    Confirm.show{
        title = _("Goodreads"), text = table.concat(lines, "\n"),
        ok_label = tracked and _("Send progress now") or _("Track this book"),
        cancel_label = _("Close"),
        extra_label = tracked and _("Stop tracking this book") or nil,
        on_ok = function()
            if not tracked then S:updateBookSetting(file, { sync = true }) end
            local started = false
            try(function() started = Track.tick(h, { force = true, ensure = true }) end)
            if started then toast(_("Sending to Goodreads…"))
            elseif not online() then toast(_("No internet: it is sent when Goodreads can be reached"))
            elseif not tracked then toast(_("This book is tracked now")) end
        end,
        on_extra = function()
            S:updateBookSetting(file, { sync = false })
            toast(_("This book is not tracked now"))
        end,
    }
end

-- ---------------------------------------------------------- for Settings
function Core.counts()
    local ok, p, f = pcall(function() return Core.host().settings:queueCounts() end)
    if ok then return p or 0, f or 0 end
    return 0, 0
end

function Core.reset()
    recent, linking = {}, {}
end

-- For tests.
function Core._setHost(h) host = h end
function Core._clear() job, again, recent, linking, warned = nil, false, {}, {}, false end

return Core
