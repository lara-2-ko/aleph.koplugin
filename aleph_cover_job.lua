-- Aleph modification, 2026-11-14: covers made in a background process.
--[[--
Making a book's cover means opening the book, which takes from a fraction of
a second to a few seconds. Done in KOReader's own process, the screen did not
answer for that long, once per book, the first time a library was shown.

Here a few books at a time are handed to a background process (the way
KOReader's own Cover browser makes its covers): it opens each book, writes
the thumbnail to the cache and ends. KOReader's process only looks, a few
times a second, at which thumbnails have arrived.

    CoverJob.supported()            whether background processes can be used
    CoverJob.start(items, listen)   items: { { book = entry, path = book file,
                                    target = thumbnail file, th = height,
                                    visible = on screen now }, ... }
    CoverJob.busy()                 a batch is being made
    CoverJob.listen(fn)             fn("progress" or "done", items) from now on

A book whose thumbnail arrives gets book.cover_path; one whose thumbnail is
not there when the process ends gets book.cover_checked (no cover, not
asked again this session). A process that takes too long (a damaged book)
is stopped. The job belongs to no screen: it carries on when Home closes,
and the Home opened next hears of it.

Where a background process cannot be started, start() returns false and the
caller makes the cover itself, as before.
]]

local Job = {}

local POLL = 0.3
-- How long a batch may take: this, plus this for each book in it.
local BASE_WAIT, WAIT_EACH = 20, 15

local current, listener, poll_task
local disabled = false

local function util()
    local ok, u = pcall(require, "ffi/util")
    return ok and type(u) == "table" and u or nil
end

function Job.supported()
    if disabled then return false end
    local u = util()
    return u ~= nil and type(u.runInSubProcess) == "function" and type(u.isSubProcessDone) == "function"
end

function Job.busy() return current ~= nil end

function Job.listen(fn) listener = fn end
-- Stops telling fn (a screen that closes), unless another took its place.
function Job.unlisten(fn)
    if listener == fn then listener = nil end
end

local function tell(event, items)
    if listener then
        local ok, err = pcall(listener, event, items)
        if not ok then require("aleph_try").report("aleph_cover_job.lua listener", err) end
    end
end

local function exists(path)
    return require("libs/libkoreader-lfs").attributes(path, "mode") == "file"
end

-- Thumbnails that arrived since the last look. True when there were any.
local function collect(items)
    local news = false
    for _i, it in ipairs(items) do
        if not it.done and exists(it.target) then
            it.done = true
            it.book.cover_path = it.target
            news = true
        end
    end
    return news
end

local function poll()
    poll_task = nil
    local job = current
    if not job then return end
    local UIManager = require("ui/uimanager")
    local u = util()
    local ok, done = pcall(u.isSubProcessDone, job.pid)
    if not ok then done = true end
    if not done and os.time() - job.started > job.wait then
        -- Too long: stopped, and collected so no dead process is left behind.
        pcall(function()
            if u.terminateSubProcess then u.terminateSubProcess(job.pid) end
            u.isSubProcessDone(job.pid, true)
        end)
        done = true
    end
    local news = collect(job.items)
    if done then
        current = nil
        for _i, it in ipairs(job.items) do
            if not it.done then it.book.cover_checked = true end
        end
        tell("done", job.items)
        return
    end
    if news then tell("progress", job.items) end
    poll_task = poll
    UIManager:scheduleIn(POLL, poll_task)
end

function Job.start(items, listen)
    if current or not items or #items == 0 or not Job.supported() then return false end
    local u = util()
    local Local = require("aleph_local")
    local work = {}
    for i, it in ipairs(items) do work[i] = { path = it.path, target = it.target, th = it.th } end
    local ok, pid = pcall(u.runInSubProcess, function()
        for _i, w in ipairs(work) do pcall(Local.extractCover, w.path, w.target, w.th) end
    end)
    if not ok or not pid then
        -- Not on this device: the caller makes covers itself from now on.
        disabled = true
        return false
    end
    current = { pid = pid, items = items, started = os.time(), wait = BASE_WAIT + WAIT_EACH * #items }
    if listen then listener = listen end
    poll_task = poll
    require("ui/uimanager"):scheduleIn(POLL, poll_task)
    return true
end

-- For tests.
function Job._reset()
    current, listener, poll_task, disabled = nil, nil, nil, false
end
function Job._poll() return poll() end

return Job
