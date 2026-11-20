-- Aleph modification, 2026-11-15: background processes, started and watched
-- in one place.
--[[--
Work that would hold up the reader (reading a whole book for X-Ray, asking a
website, making covers, writing the library index) runs in another process:
KOReader's ffi/util runInSubProcess. Seven parts of Aleph each had their own
copy of starting one, looking once in a while for it to end, and stopping
one that takes too long. They share this now.

    local Job = require("aleph_job")
    if not Job.available() then ... end          -- some devices have none
    local pid = Job.start(function() ... end)    -- the work, in the other process; nil if it did not start
    local cancel = Job.watch(pid, {
        every = 1,            -- seconds between looks (1 unless given)
        timeout = 240,        -- stopped after this long, if given
        on_tick = function() end,                 -- at each look that finds it still running
        on_done = function(late) end,             -- once: late is true when it was stopped for taking too long
    })
    Job.finished(pid)         -- whether it has ended (an error asking counts as ended)
    Job.stop(pid)             -- ends it now

The process shares nothing with KOReader once started: it hands its result
back in a file (aleph_file.lua), read in on_done. Job.watch looks from
KOReader's own loop, so on_done runs there; cancel() stops the looking (not
the process).
]]

local Job = {}

local function util()
    local ok, u = pcall(require, "ffi/util")
    if ok and type(u) == "table" and type(u.runInSubProcess) == "function" and type(u.isSubProcessDone) == "function" then
        return u
    end
end
Job.util = util

function Job.available() return util() ~= nil end

-- opts.optional: work that can wait (the weather, Collections from Calibre,
-- Goodreads in the background): not started while memory is low
-- (aleph_mem.lua), returning nil, "low memory".
function Job.start(fn, opts)
    local u = util()
    if not u then return nil end
    if opts and opts.optional then
        local Mem = require("aleph_mem")
        if Mem.low() then
            pcall(function() require("logger").info("Aleph: background work put off, memory low:", Mem.describe(), opts.name or "") end)
            return nil, "low memory"
        end
    end
    local ok, pid = pcall(u.runInSubProcess, fn)
    -- Aleph modification, 2026-11-19 (1.2.51): each one in crash.log, with
    -- the memory left as it starts (a process of its own costs memory).
    if ok and pid then
        pcall(function()
            -- Without a name, the file that started it ("aleph_xr_ai", say).
            local name = opts and opts.name
            if not name then
                local info = debug.getinfo(4, "S")
                name = info and info.short_src and info.short_src:match("([%w_]+)%.lua$") or "?"
            end
            require("logger").info("Aleph: background job started:", name, "-", require("aleph_mem").describe(), "left")
        end)
    end
    return ok and pid or nil
end

function Job.finished(pid)
    local u = util()
    if not u then return true end
    local ok, done = pcall(u.isSubProcessDone, pid)
    return not ok or done and true or false
end

function Job.stop(pid)
    local u = util()
    if not (u and pid) then return end
    pcall(function()
        if u.terminateSubProcess then u.terminateSubProcess(pid) end
        u.isSubProcessDone(pid, true)
    end)
end

function Job.watch(pid, o)
    o = o or {}
    local UIManager = require("ui/uimanager")
    local every = o.every or 1
    local started = os.time()
    local cancelled = false
    local poll
    poll = function()
        if cancelled then return end
        local over = Job.finished(pid)
        local late = false
        if not over and o.timeout and os.time() - started > o.timeout then
            Job.stop(pid)
            over, late = true, true
        end
        if not over then
            if o.on_tick then pcall(o.on_tick) end
            if not cancelled then UIManager:scheduleIn(every, poll) end
            return
        end
        cancelled = true
        if o.on_done then
            local ok, err = pcall(o.on_done, late)
            if not ok then require("aleph_try").report("background job's result", err) end
        end
    end
    UIManager:scheduleIn(every, poll)
    return function() cancelled = true end
end

return Job
