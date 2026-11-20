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

Where background processes cannot be used at all, start() returns false,
"unsupported" and the caller makes the covers itself, slowly. Aleph
modification, 2026-11-18: when one could not be started this time (memory
short as KOReader starts, say), it returns false, "failed" and the caller
tries again later: before, background processes were then given up on for
the whole run and every cover was made in KOReader's own process, the
screen waiting for each. Both are written to crash.log.
]]

local Job = {}

local POLL = 0.3
-- How long a batch may take: this, plus this for each book in it.
local BASE_WAIT, WAIT_EACH = 20, 15

local current, listener, stop_watching
local disabled = false

-- Starting and watching the process: aleph_job.lua.
local Jobs = require("aleph_job")

function Job.supported()
    return not disabled and Jobs.available()
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

-- At each look while the covers are being made: those that arrived.
local function looked()
    local job = current
    if job and collect(job.items) then tell("progress", job.items) end
end

-- The process has ended (or was stopped for taking too long, and collected
-- so no dead process is left behind).
local function ended()
    local job = current
    if not job then return end
    collect(job.items)
    current = nil
    for _i, it in ipairs(job.items) do
        if not it.done then it.book.cover_checked = true end
    end
    tell("done", job.items)
end

function Job.start(items, listen)
    if current or not items or #items == 0 then return false, "busy" end
    if not Job.supported() then return false, "unsupported" end
    -- Aleph modification, 2026-11-19 (1.2.51): making covers opens each book
    -- in another process, which can take 100 MB or more; below 80 MB left
    -- the books wait (tried again in half a minute) rather than push the
    -- device out of memory.
    local Mem = require("aleph_mem")
    local ok_low, low = pcall(Mem.low, 80 * 1024)
    if ok_low and low then
        pcall(function() require("logger").info("Aleph: covers wait, memory low:", Mem.describe()) end)
        return false, "low memory"
    end
    local Local = require("aleph_local")
    local work = {}
    for i, it in ipairs(items) do work[i] = { path = it.path, target = it.target, th = it.th } end
    local pid = Jobs.start(function()
        for _i, w in ipairs(work) do pcall(Local.extractCover, w.path, w.target, w.th) end
    end, { name = "covers (" .. #work .. ")" })
    if not pid then
        pcall(function() require("logger").warn("Aleph: covers: the background process could not start; trying again later. Memory:",
            require("aleph_mem").describe()) end)
        return false, "failed"
    end
    current = { pid = pid, items = items, started = os.time(), wait = BASE_WAIT + WAIT_EACH * #items }
    if listen then listener = listen end
    stop_watching = Jobs.watch(pid, { every = POLL, timeout = current.wait, on_tick = looked, on_done = ended })
    return true
end

-- For tests.
function Job._reset()
    if stop_watching then stop_watching() end
    current, listener, stop_watching, disabled = nil, nil, nil, false
end

return Job
