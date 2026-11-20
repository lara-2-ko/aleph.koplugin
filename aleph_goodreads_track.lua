-- Aleph modification, 2026-11-15: Goodreads tracking of the open book, in a
-- background process so it never holds up the reader. Since 1.2.32 it
-- tracks for Aleph's own Goodreads (aleph_gr.lua), no longer for advokatb's
-- plugin.
--[[--
Asking goodreads.com from KOReader's own process makes the reader wait for
every answer: a second or two on a good connection, 15 to 45 seconds each
time on Wi-Fi that is connected but has no internet, on a page turn. Here
the open book is tracked from a background process:

  a book opens          what Goodreads has for it is read (once a run);
                        Currently reading when it is on no shelf
  pages turn            Track.tick: the percentage, at most one question a
                        minute
  the book closes       the percentage (aleph_gr.lua, Core.close)

`p` is Aleph's Goodreads host (aleph_gr.lua, Core.host): its settings
(sign-in, the book's link and what was last sent), its state for the open
book and its ui. A book Goodreads has on another shelf (Read, Want to read,
one of the reader's own) is not moved: Aleph asks once whether to mark it
Currently reading. Read is not sent from here: it is sent from the book's
status (aleph_gr.lua). After a failure the next try waits 5 minutes, then
10, up to 30; after the sign-in is refused, nothing is asked until it
changes. Nothing is asked without a background process.
]]

local logger = require("logger")
local try = require("aleph_try").call

local Track = {}

Track.MIN_GAP = 60            -- seconds between two automatic questions
Track.WAIT = 100              -- a question is stopped after this long
Track.BACKOFF = { 300, 600, 1200, 1800 }

local job                     -- { pid, started, plan }
local next_at = 0             -- no automatic question before this time
local fails = 0
local checked = {}            -- [file] = true once Goodreads' own state was read this run
local asked = {}              -- [file] = true once the "not Currently reading" question was shown
local auth_stop               -- the cookie that Goodreads refused: nothing is asked until it changes

local function api(p)
    local Api = require("aleph_gr_api")
    Api.settings = p.settings
    return Api
end

local function resultPath()
    return require("datastorage"):getSettingsDir() .. "/aleph_goodreads_job.lua"
end

local File = require("aleph_file")

local function isAuthError(errors)
    for _i, e in ipairs(errors or {}) do
        if e == "session_expired" or e == "no_cookies" or e == "waf_challenge" then return e end
    end
end

-- ------------------------------------------------ in the background process
-- Asks Goodreads what the plan says. Returns what happened: { remote = {
-- shelf, status, review_id, rating }, mismatch, status, percent, errors =
-- { ... }, failed, cookie, user_id, csrf }.
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
    if go and not on_shelf then
        local res = Api:set_status(id, 2, nil, 0)
        -- Aleph modification, 2026-11-19: Goodreads would not shelve the book
        -- under this id (an id from Calibre it does not take): the same title
        -- and author found by a search, when it is on no shelf there.
        if not (res and res.ok) and not isAuthError(r.errors) and plan.title then
            local other = require("aleph_gr").findAnother(Api, id, plan.title, plan.author)
            local st2 = other and Api:get_review_state(other.edition_id)
            if st2 and st2.ok and not st2.shelf then
                local again = Api:set_status(other.edition_id, 2, nil, 0)
                if again and again.ok then
                    r.relinked, r.relinked_from = other, id
                    id, res = other.edition_id, again
                    r.remote = { shelf = false, status = false, review_id = st2.review_id or false, rating = tonumber(st2.rating) or 0 }
                end
            end
        end
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
    -- What Goodreads answered last, when something failed (for crash.log).
    if r.failed then
        pcall(function()
            local a = Api:_get_backend()._last_answer
            if a then r.answer = a.method .. " " .. a.path .. " → HTTP " .. a.code .. ": " .. a.text end
        end)
    end
    -- What Goodreads gave back with the answers, for KOReader's process.
    pcall(function() r.cookie = settings:getCookie() end)
    pcall(function() r.user_id = settings:getUserId() end)
    pcall(function() r.csrf = Api:_get_backend()._csrf_token end)
    Api.quiet, Api.on_error = prev_quiet, prev_on_error
    return r
end

-- ------------------------------------------------------------ the answer

-- Puts the answer in the book's sidecar. Returns "ok", "mismatch", "auth"
-- or "failed" (and the error for "auth").
function Track.apply(p, plan, r)
    local Api = api(p)
    local file = plan.file
    local settings, state = p.settings, p.state
    -- The sign-in as Goodreads last gave it, then the token that goes with it.
    try(function()
        if type(r.cookie) == "string" and r.cookie ~= "" and r.cookie ~= settings:getCookie() then settings:setCookie(r.cookie) end
        if r.user_id and settings:getUserId() ~= r.user_id then settings:setUserId(r.user_id) end
        if type(r.csrf) == "string" then Api:_get_backend()._csrf_token = r.csrf end
    end)
    local UNSET = settings.UNSET
    if r.relinked then try(function() require("aleph_gr").relink(file, r.relinked, r.relinked_from) end) end
    if r.remote then
        checked[file] = true
        local update = { status = r.remote.status ~= false and r.remote.status or UNSET, shelf = r.remote.shelf or UNSET }
        if r.remote.review_id then update.review_id = r.remote.review_id
        elseif not r.remote.shelf then update.review_id = UNSET end
        if (r.remote.rating or 0) > 0 then update.rating = r.remote.rating end
        try(function() settings:updateBookSetting(file, update) end)
    end
    if r.status then
        try(function() settings:updateBookSetting(file, { status = r.status, shelf = Api:shelfForStatus(r.status) }) end)
    end
    if r.percent then
        try(function() settings:updateBookSetting(file, { last_progress = r.percent }) end)
        -- A percentage kept for later while offline is behind this one.
        try(function() settings:removeSync("progress", tostring(plan.id)) end)
    end
    if r.mismatch then
        state.auto_track_paused = true
        return "mismatch"
    end
    local auth = isAuthError(r.errors)
    if auth then return "auth", auth end
    if r.failed then return "failed" end
    return "ok"
end

-- The site has the book on another shelf: asked once per book and run.
local function askTakeOver(p, plan, shelf)
    local file = plan.file
    if asked[file] then return end
    asked[file] = true
    local _ = require("aleph_gettext")
    local T = require("ffi/util").template
    local label = shelf
    try(function() label = api(p):shelfLabel(shelf) or shelf end)
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
    local outcome, detail = "failed", nil
    if r then outcome, detail = Track.apply(p, plan, r) end
    local now = os.time()
    if outcome == "ok" or outcome == "mismatch" then
        fails = 0
        next_at = now + Track.MIN_GAP
    else
        fails = fails + 1
        next_at = now + Track.BACKOFF[math.min(fails, #Track.BACKOFF)]
    end
    local said = outcome
    if outcome == "ok" then
        said = (r.percent and (tostring(r.percent) .. "% sent")) or (r.status == 2 and "marked Currently reading") or "nothing to send"
    elseif outcome == "failed" then
        said = "failed (" .. tostring(why or (r and r.failed) or "no answer") .. (r and r.errors and r.errors[1] and (": "
            .. r.errors[1]) or "") .. "), next try in " .. tostring(next_at - now) .. " s"
            .. (r and r.answer and (" | Goodreads answered " .. r.answer) or "")
    elseif outcome == "auth" then
        said = "sign-in refused (" .. tostring(detail) .. ")"
    elseif outcome == "mismatch" then
        said = "on another shelf on the site (" .. tostring(r.mismatch) .. ")"
    end
    logger.info("Aleph: Goodreads in the background:", said)
    if outcome == "mismatch" then
        askTakeOver(p, plan, r.mismatch)
    elseif outcome == "auth" then
        -- Nothing more is asked until the sign-in changes; said once.
        try(function() auth_stop = p.settings:getCookie() or "" end)
        try(function()
            local _ = require("aleph_gettext")
            require("aleph_toast").show(_("Goodreads no longer accepts the sign-in. Renew it in Aleph's Settings > Library > Goodreads sign-in."), { icon = "info", timeout = 6 })
        end)
    elseif outcome == "ok" then
        -- What waited while offline: the internet is there now.
        try(function() require("aleph_gr").flush() end)
    end
    return outcome
end

-- ------------------------------------------------------------- the question
-- What there is to ask for the open book now, or nil. Reads only the
-- sidecar and the reader's position.
function Track.plan(p, opts)
    opts = opts or {}
    local ui = p.ui
    if not (ui and ui.document) then return nil end
    local file = ui.document.file
    -- Signed in, the book linked and tracked.
    if not p:_canAutoSync(file) then return nil end
    local settings = p.settings
    local current = settings:readBookSetting(file, "status")
    local shelf = settings:readBookSetting(file, "shelf")
    if current == 1 or current == 3 or shelf == "read" then return nil end
    if type(shelf) == "string" and shelf ~= "" and shelf ~= "to-read" and shelf ~= "currently-reading" then
        return nil            -- a shelf of the reader's own: left alone
    end
    local id = settings:readBookSetting(file, "edition_id")
    if not id then return nil end
    local fraction = p:_readingPercent()
    local pct = fraction and fraction * 100 or 0
    -- The end of the book: Read goes with the book's status (aleph_gr.lua).
    if fraction and pct >= 99.5 then return nil end
    local plan = { file = file, id = tostring(id), current = current, take_over = opts.take_over or nil }
    -- The title and author, to find the book again if Goodreads will not
    -- shelve it under this id.
    try(function()
        local props = ui.doc_props or {}
        plan.title = props.title or settings:readBookSetting(file, "title")
        local a = props.authors
        if type(a) == "table" then a = a[1] end
        plan.author = type(a) == "string" and (a:match("^[^\n]+") or a) or settings:readBookSetting(file, "authors")
    end)
    plan.ensure = (opts.ensure or not checked[file]) and true or nil
    local whole = math.floor(pct + 0.5)
    if settings:syncProgressEnabled() and whole >= 1 then
        local last = tonumber(settings:readBookSetting(file, "last_progress"))
        if opts.force or not last or math.abs(last - whole) >= 1 then plan.percent = whole end
    end
    if not plan.ensure and current == 2 and not plan.percent then return nil end
    return plan
end

-- Costs a comparison of two numbers on a page turn; asks at most once a
-- minute, never in KOReader's process. Returns true when a question went.
function Track.tick(p, opts)
    opts = opts or {}
    if job then return false end
    local Core = package.loaded["aleph_gr"]
    if Core and Core.busy() then return false end
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
    local Job = require("aleph_job")
    if not Job.available() then return false end
    local Api, settings = api(p), p.settings
    local out = resultPath()
    os.remove(out)
    local pid = Job.start(function()
        local done, r = pcall(Track.work, Api, settings, plan)
        File.write(out, done and r or { failed = "error", errors = { tostring(r) } })
    end, { optional = true, name = "goodreads" })
    if not pid then
        next_at = now + Track.BACKOFF[1]
        return false
    end
    job = { pid = pid, started = now, plan = plan }
    next_at = now + Track.MIN_GAP
    Job.watch(pid, { every = 2, timeout = Track.WAIT, on_done = function(late)
        local j = job
        if not j then return end
        try(finish, p, j.plan, File.read(out), late and "took too long" or nil)
    end })
    return true
end

function Track.busy() return job ~= nil end

-- For tests.
function Track.reset()
    job, next_at, fails, checked, asked, auth_stop = nil, 0, 0, {}, {}, nil
end

return Track
