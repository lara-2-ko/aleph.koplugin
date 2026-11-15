-- Aleph modification, 2026-11-15: the Goodreads plugin's automatic tracking,
-- moved to a background process so it never holds up the reader.
--[[--
advokatb's Goodreads plugin (goodreads.koplugin) keeps Goodreads up to date
as you read: "Currently reading" when a book is started, the percentage as
it goes, "Read" at the end. It asks goodreads.com from KOReader's own
process, so the reader waits for every answer: a second or two on a good
connection, 15 to 45 seconds each time on Wi-Fi that is connected but has
no internet, on a page turn.

With Settings > Library > Goodreads > "Track in the background" on, Aleph
answers the plugin's automatic calls in its place:

  the plugin asks                         Aleph
  _maybeAutoTrackProgress (page turns)    Track.tick: at most one question a
  _runPendingEnsure, _refreshRemoteState  minute, asked in a background
    (a book opens, Wi-Fi comes back)      process with the plugin's own
  _sendProgress, not asked by hand        Goodreads code; the answer is put
    (a book closes)                       in the plugin's records afterwards
  _flushQueue (things kept while offline) only once a question has just been
                                          answered, so the internet is there

Everything asked by hand in the plugin's menu is left as it is. What is
sent, to which book, and whether a book is tracked at all stay the plugin's
decisions (its settings, its link to the book, its sign-in). After a failure
the next try waits 5 minutes, then 10, up to 30. Nothing is asked without a
background process: the plugin is then left to do it its own way.

The plugin is changed only in memory, on the copy running for the open book,
and put back when the switch is turned off. A version of the plugin that
does not have the functions named above is left alone (Track.supports).
]]

local logger = require("logger")
local try = require("aleph_try").call
local Prefs = require("aleph_prefs")

local Track = {}

Track.MIN_GAP = 60            -- seconds between two automatic questions
Track.WAIT = 100              -- a question is stopped after this long
Track.BACKOFF = { 300, 600, 1200, 1800 }
Track.FRESH = 180             -- the internet counts as there this long after an answer

local OVERRIDES = { "_maybeAutoTrackProgress", "_runPendingEnsure", "_refreshRemoteState", "_sendProgress", "_flushQueue" }

local job                     -- { pid, started, plan }
local next_at = 0             -- no automatic question before this time
local fails = 0
local last_ok = 0
local checked = {}            -- [file] = true once Goodreads' own state was read this run
local asked = {}              -- [file] = true once the "not Currently reading" question was shown
local auth_stop               -- the cookie that Goodreads refused: nothing is asked until it changes

function Track.enabled() return Prefs.is("goodreads_background") end

local function subprocess()
    local ok, u = pcall(require, "ffi/util")
    if ok and type(u) == "table" and type(u.runInSubProcess) == "function" and type(u.isSubProcessDone) == "function" then
        return u
    end
end

local function api() return package.loaded["goodreads_api"] end

-- Whether this is a Goodreads plugin Aleph knows how to stand in for.
function Track.supports(p)
    if type(p) ~= "table" or type(p.settings) ~= "table" or type(p.state) ~= "table" then return false end
    for _i, name in ipairs(OVERRIDES) do
        if type(p[name]) ~= "function" then return false end
    end
    for _i, name in ipairs({ "_canAutoSync", "_readingPercent" }) do
        if type(p[name]) ~= "function" then return false end
    end
    for _i, name in ipairs({ "readBookSetting", "updateBookSetting", "getCookie", "setCookie" }) do
        if type(p.settings[name]) ~= "function" then return false end
    end
    local Api = api()
    if type(Api) ~= "table" then return false end
    for _i, name in ipairs({ "get_review_state", "set_status", "set_progress", "shelfForStatus" }) do
        if type(Api[name]) ~= "function" then return false end
    end
    return subprocess() ~= nil
end

local function resultPath()
    return require("datastorage"):getSettingsDir() .. "/aleph_goodreads_job.lua"
end

local function readFile(path)
    local fn = loadfile(path)
    if not fn then return nil end
    local ok, value = pcall(fn)
    return ok and type(value) == "table" and value or nil
end

local function dump(value, out)
    local t = type(value)
    if t == "table" then
        out[#out + 1] = "{"
        for k, v in pairs(value) do
            if type(k) == "string" then
                out[#out + 1] = "[" .. string.format("%q", k) .. "]="
                dump(v, out)
                out[#out + 1] = ","
            elseif type(k) == "number" then
                out[#out + 1] = "[" .. tostring(k) .. "]="
                dump(v, out)
                out[#out + 1] = ","
            end
        end
        out[#out + 1] = "}"
    elseif t == "string" then
        out[#out + 1] = string.format("%q", value)
    elseif t == "number" or t == "boolean" then
        out[#out + 1] = tostring(value)
    else
        out[#out + 1] = "nil"
    end
end

local function writeFile(path, value)
    local out = { "return " }
    dump(value, out)
    local f = io.open(path .. ".part", "w")
    if not f then return false end
    f:write(table.concat(out))
    f:close()
    return os.rename(path .. ".part", path) and true or false
end

-- ------------------------------------------------ in the background process
-- Asks Goodreads what the plan says, with the plugin's own code. Returns
-- what happened: { remote = { shelf, status, review_id, rating }, mismatch,
-- status, rating, date_read, percent, errors = { ... }, failed, cookie,
-- user_id, csrf }. Api and settings are the plugin's.
function Track.work(Api, settings, plan)
    local r = { errors = {} }
    local prev_quiet, prev_on_error = Api.quiet, Api.on_error
    Api.quiet = false
    Api.on_error = function(err) r.errors[#r.errors + 1] = tostring(err) end
    local id = plan.id
    local go = true
    local on_shelf = plan.current == 2
    if plan.ensure then
        local st = Api:get_review_state(id)
        if not st or not st.ok then
            r.failed = "state"
            go = false
        else
            r.remote = { shelf = st.shelf or false, status = st.status or false,
                review_id = st.review_id or false, rating = tonumber(st.rating) or 0 }
            on_shelf = st.shelf == "currently-reading"
            if st.shelf and st.shelf ~= "currently-reading" and not plan.take_over then
                -- Something else on the site (Read, Want to read, a shelf of
                -- the reader's own): theirs to decide.
                r.mismatch = st.shelf
                go = false
            end
        end
    end
    if go and plan.want == "finished" then
        local res = Api:set_status(id, 1, nil, plan.rating or 0)
        if res and res.ok then
            r.status = 1
            r.rating = tonumber(res.rating) or plan.rating or 0
            r.date_read = res.date_read
        else
            r.failed = "status"
        end
    elseif go then
        if not on_shelf then
            local res = Api:set_status(id, 2, nil, 0)
            if res and res.ok then r.status = 2 else r.failed = "status"; go = false end
        end
        if go and plan.percent then
            local res = Api:set_progress(id, plan.percent)
            if res and res.error == "not_on_shelf" then
                local again = Api:set_status(id, 2, nil, 0)
                if again and again.ok then
                    r.status = 2
                    res = Api:set_progress(id, plan.percent)
                end
            end
            if res and res.ok then r.percent = tonumber(res.percent) or plan.percent else r.failed = "progress" end
        end
    end
    -- What the plugin would have kept from these answers had it asked itself.
    pcall(function() r.cookie = settings:getCookie() end)
    pcall(function() r.user_id = settings.getUserId and settings:getUserId() or nil end)
    pcall(function()
        local backend = Api._get_backend and Api:_get_backend()
        r.csrf = backend and backend._csrf_token or nil
    end)
    Api.quiet, Api.on_error = prev_quiet, prev_on_error
    return r
end

-- ------------------------------------------------------------ the answer
-- The plugin running for the book open now (KOReader may have reopened it),
-- else the one that asked.
local function livePlugin(p, file)
    local found
    pcall(function()
        local ReaderUI = package.loaded["apps/reader/readerui"]
        local ui = ReaderUI and rawget(ReaderUI, "instance")
        if ui and ui.document and ui.document.file == file and Track.supports(ui.goodreads) then found = ui.goodreads end
    end)
    return found or p
end

local function isAuthError(errors)
    for _i, e in ipairs(errors or {}) do
        if e == "session_expired" or e == "no_cookies" or e == "waf_challenge" then return e end
    end
end

local function unset(p)
    local S = package.loaded["goodreads_settings"]
    return (S and S.UNSET) or p.settings.UNSET
end

-- Puts the answer in the plugin's records. Returns "ok", "mismatch",
-- "auth" or "failed".
function Track.apply(p, plan, r)
    local Api = api()
    local file = plan.file
    p = livePlugin(p, file)
    local settings, state = p.settings, p.state
    local open = p.ui and p.ui.document and p.ui.document.file == file
    -- The sign-in as Goodreads last gave it, then the token that goes with it.
    try(function()
        if type(r.cookie) == "string" and r.cookie ~= "" and r.cookie ~= settings:getCookie() then settings:setCookie(r.cookie) end
        if r.user_id and settings.setUserId and settings.getUserId and settings:getUserId() ~= r.user_id then settings:setUserId(r.user_id) end
        local backend = Api._get_backend and Api:_get_backend()
        if backend and type(r.csrf) == "string" then backend._csrf_token = r.csrf end
    end)
    local UNSET = unset(p)
    if r.remote then
        checked[file] = true
        local update = { status = r.remote.status ~= false and r.remote.status or UNSET, shelf = r.remote.shelf or UNSET }
        if r.remote.review_id then update.review_id = r.remote.review_id
        elseif not r.remote.shelf then update.review_id = UNSET end
        if (r.remote.rating or 0) > 0 then update.rating = r.remote.rating end
        if UNSET ~= nil then try(function() settings:updateBookSetting(file, update) end) end
        if open then
            state.current_status = r.remote.status ~= false and r.remote.status or nil
            state.current_shelf = r.remote.shelf or nil
        end
        state.ensure_remote_pending = false
    end
    if r.status then
        local shelf = Api:shelfForStatus(r.status)
        local update = { status = r.status, shelf = shelf }
        if r.status == 1 then update.rating = r.rating or 0 end
        if r.date_read then update.date_read = r.date_read end
        try(function() settings:updateBookSetting(file, update) end)
        if open then state.current_status, state.current_shelf = r.status, shelf end
        state.ensure_remote_pending = false
    end
    if r.percent then
        try(function() settings:updateBookSetting(file, { last_progress = r.percent }) end)
        -- A percentage kept for later while offline is behind this one.
        try(function() if settings.removeSync then settings:removeSync("progress", tostring(plan.id)) end end)
    end
    state.last_auto_sync_at = os.time()
    if r.mismatch then
        state.auto_track_paused = true
        return "mismatch", p
    end
    local auth = isAuthError(r.errors)
    if auth then return "auth", p, auth end
    if r.failed then return "failed", p end
    return "ok", p
end

-- The site has the book on another shelf: asked once per book and run, as
-- the plugin asks.
local function askTakeOver(p, plan, shelf)
    local file = plan.file
    if asked[file] then return end
    asked[file] = true
    p.state.status_mismatch_shown = true
    local _ = require("aleph_gettext")
    local T = require("ffi/util").template
    local label = shelf
    try(function() label = api():shelfLabel(shelf) or shelf end)
    try(function()
        require("aleph_confirm").show({
            title = _("Goodreads"),
            text = T(_("Goodreads has this book as \"%1\", so your progress is not sent.\n\nMark it Currently reading?"), tostring(label)),
            ok_label = _("Currently reading"), cancel_label = _("Keep as is"),
            on_ok = function()
                if not (p.ui and p.ui.document and p.ui.document.file == file) then return end
                p.state.auto_track_paused = false
                Track.tick(p, { ensure = true, take_over = true })
            end,
        })
    end)
end

local function finish(p, plan, r, why)
    job = nil
    os.remove(resultPath())
    local outcome, live, detail = "failed", p, nil
    if r then outcome, live, detail = Track.apply(p, plan, r) end
    local now = os.time()
    if outcome == "ok" or outcome == "mismatch" then
        fails, last_ok = 0, now
        next_at = now + Track.MIN_GAP
    else
        fails = fails + 1
        next_at = now + Track.BACKOFF[math.min(fails, #Track.BACKOFF)]
    end
    local said = outcome
    if outcome == "ok" then
        said = (r.status == 1 and "marked Read") or (r.percent and (tostring(r.percent) .. "% sent")) or (r.status == 2 and "marked Currently reading") or "nothing to send"
    elseif outcome == "failed" then
        said = "failed (" .. tostring(why or (r and r.failed) or "no answer") .. (r and r.errors and r.errors[1] and (": " .. r.errors[1]) or "") .. "), next try in " .. tostring(next_at - now) .. " s"
    elseif outcome == "auth" then
        said = "sign-in refused (" .. tostring(detail) .. ")"
    elseif outcome == "mismatch" then
        said = "on another shelf on the site (" .. tostring(r.mismatch) .. ")"
    end
    logger.info("Aleph: Goodreads in the background:", said)
    if outcome == "mismatch" then
        askTakeOver(live, plan, r.mismatch)
    elseif outcome == "auth" then
        -- Nothing more is asked until the sign-in changes; said once.
        try(function() auth_stop = live.settings:getCookie() or "" end)
        try(function()
            local _ = require("aleph_gettext")
            require("aleph_toast").show(_("Goodreads no longer accepts the sign-in. Renew it in Aleph's Settings > Library > Goodreads sign-in."), { icon = "info", timeout = 6 })
        end)
    elseif outcome == "ok" then
        -- Things the plugin kept while offline: the internet is there now.
        try(function()
            if live.settings.queueSize and live.settings:queueSize() > 0 and live._flushQueue then live:_flushQueue() end
        end)
    end
    return outcome
end

-- ------------------------------------------------------------- the question
-- What there is to ask for the open book now, or nil. Reads only what the
-- plugin has in memory.
function Track.plan(p, opts)
    opts = opts or {}
    local ui = p.ui
    if not (ui and ui.document) then return nil end
    local file = ui.document.file
    -- The plugin's own conditions: signed in, the book linked, tracking on.
    if not p:_canAutoSync(file, { ensure = true }) then return nil end
    local settings = p.settings
    local current = settings:readBookSetting(file, "status")
    local shelf = settings:readBookSetting(file, "shelf")
    if current == 1 or current == 3 or shelf == "read" then return nil end
    if type(shelf) == "string" and shelf ~= "" and shelf ~= "to-read" and shelf ~= "currently-reading" and shelf ~= "read" then
        return nil            -- a shelf of the reader's own: left alone
    end
    local id = settings:readBookSetting(file, "edition_id")
    if not id then return nil end
    local fraction = p:_readingPercent()
    local pct = fraction and fraction * 100 or 0
    local plan = { file = file, id = tostring(id), current = current, take_over = opts.take_over or nil }
    plan.ensure = (opts.ensure or not checked[file]) and true or nil
    if fraction and pct >= 99.5 then
        plan.want = "finished"
        local rating = 0
        try(function() if p._resolveRating then rating = tonumber(p:_resolveRating(file, 1)) or 0 end end)
        plan.rating = rating
        return plan
    end
    plan.want = "reading"
    local whole = math.floor(pct + 0.5)
    local progress_on = true
    try(function() if settings.syncProgressEnabled then progress_on = settings:syncProgressEnabled() and true or false end end)
    if progress_on and whole >= 1 then
        local last = tonumber(settings:readBookSetting(file, "last_progress"))
        if opts.force or not last or math.abs(last - whole) >= 1 then plan.percent = whole end
    end
    if not plan.ensure and current == 2 and not plan.percent then return nil end
    return plan
end

-- The plugin's automatic calls end here. Costs a comparison of two numbers
-- on a page turn; asks at most once a minute, never in KOReader's process.
function Track.tick(p, opts)
    opts = opts or {}
    if job then return false end
    local now = os.time()
    if now < next_at and not (opts.take_over or (opts.force and fails == 0)) then return false end
    if not (p and p.ui and p.ui.document) then return false end
    if p.state.auto_track_paused and not opts.take_over then return false end
    local ok, plan = pcall(Track.plan, p, opts)
    if not ok then
        logger.warn("Aleph: Goodreads in the background: could not prepare:", plan)
        next_at = now + Track.BACKOFF[1]
        return false
    end
    if not plan then return false end
    if auth_stop then
        local cookie
        try(function() cookie = p.settings:getCookie() or "" end)
        if cookie == auth_stop then return false end
        auth_stop = nil
    end
    local online = false
    try(function() online = require("ui/network/manager"):isConnected() and true or false end)
    if not online then
        next_at = now + Track.MIN_GAP
        return false
    end
    local u = subprocess()
    if not u then return false end
    local Api, settings = api(), p.settings
    local out = resultPath()
    os.remove(out)
    local started, pid = pcall(u.runInSubProcess, function()
        local done, r = pcall(Track.work, Api, settings, plan)
        writeFile(out, done and r or { failed = "error", errors = { tostring(r) } })
    end)
    if not (started and pid) then
        next_at = now + Track.BACKOFF[1]
        return false
    end
    job = { pid = pid, started = now, plan = plan }
    next_at = now + Track.MIN_GAP
    local UIManager = require("ui/uimanager")
    local function poll()
        local j = job
        if not j then return end
        local got, over = pcall(u.isSubProcessDone, j.pid)
        if not got then over = true end
        local late = false
        if not over and os.time() - j.started > Track.WAIT then
            pcall(function()
                if u.terminateSubProcess then u.terminateSubProcess(j.pid) end
                u.isSubProcessDone(j.pid, true)
            end)
            over, late = true, true
        end
        if not over then
            UIManager:scheduleIn(2, poll)
            return
        end
        local r = readFile(out)
        try(finish, p, j.plan, r, late and "took too long" or nil)
    end
    UIManager:scheduleIn(2, poll)
    return true
end

function Track.busy() return job ~= nil end

-- ------------------------------------------------------- in the plugin's place
-- Stands in for the automatic calls of the plugin running for this book
-- (on that copy only; the plugin's files are not touched).
function Track.attach(ui)
    local p = ui and ui.goodreads
    if not p or rawget(p, "_aleph_track") then return p ~= nil and rawget(p, "_aleph_track") == true end
    if not (Track.enabled() and ui.document and require("aleph_goodreads").isTheOne(p) and Track.supports(p)) then return false end
    local own = {}
    for _i, name in ipairs(OVERRIDES) do own[name] = p[name] end
    p._aleph_track = true
    p._maybeAutoTrackProgress = function(self, opts) try(Track.tick, self, opts) end
    p._runPendingEnsure = function(self)
        if not self.state.ensure_remote_pending then return end
        try(Track.tick, self, { ensure = true })
    end
    p._refreshRemoteState = function(self) try(Track.tick, self, { ensure = true }) end
    p._sendProgress = function(self, file, opts)
        if opts and opts.manual then return own._sendProgress(self, file, opts) end
        try(Track.tick, self, { force = opts and opts.force })
        return nil
    end
    p._flushQueue = function(self)
        -- Only when Goodreads has just answered: otherwise this is where the
        -- reader would wait on a connection with no internet behind it.
        if os.time() - last_ok > Track.FRESH then return end
        return own._flushQueue(self)
    end
    logger.info("Aleph: Goodreads tracking goes through the background for this book")
    return true
end

function Track.detach(ui)
    local p = ui and ui.goodreads
    if not p or not rawget(p, "_aleph_track") then return end
    for _i, name in ipairs(OVERRIDES) do p[name] = nil end
    p._aleph_track = nil
end

-- After the switch changes: the open book's plugin follows at once.
function Track.sync(ui)
    if Track.enabled() then return Track.attach(ui) end
    Track.detach(ui)
    return false
end

-- For Settings: "on", "off", "unsupported" (a plugin version Aleph does not
-- know, or a device without background processes) or nil without the plugin.
function Track.status(ui)
    local GR = require("aleph_goodreads")
    local p = GR.plugin(ui)
    if not p then return nil end
    if not Track.supports(p) then return "unsupported" end
    return Track.enabled() and "on" or "off"
end

-- For tests.
function Track.reset()
    job, next_at, fails, last_ok, checked, asked, auth_stop = nil, 0, 0, 0, {}, {}, nil
end
function Track.state() return { next_at = next_at, fails = fails, last_ok = last_ok, auth_stop = auth_stop } end

return Track
