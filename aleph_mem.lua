-- Aleph modification, 2026-11-18: how much memory the device has left.
--[[--
A Kindle running KOReader with many plugins can come down to 20 MB or so,
and then everything slows to a crawl (a screen drawn in a minute). Starting
a background process (aleph_job.lua) costs most then, so Aleph's optional
background work (the weather, Collections from Calibre, Goodreads in the
background) waits while memory is low and tries again later; and how much
there is goes into crash.log each time Home is built, to tell what happened.

    Mem.availableKB()   MemAvailable from /proc/meminfo (MemFree + Cached
                        on old kernels), or nil where there is none
    Mem.low()           true below Mem.LOW_KB (50 MB)

Aleph modification, 2026-11-18 (1.2.34): a memory diary in crash.log, to
tell what uses the memory up when the device freezes or KOReader is killed.

    Mem.report(where)   one line: the memory the device has left, what
                        KOReader's process holds (VmRSS) and what of that
                        is Lua's (collectgarbage), each with the change
                        since the last line
    Mem.watch()         a line every 10 minutes while a book is open
    Mem.unwatch()       stops it (the book closed)

Lines are written when a book opens and closes, every 10 minutes while
reading, as the device goes to sleep and wakes up, and when the file
browser is ready. Below 50 MB left the line is a warning.
]]

local Mem = {}

Mem.LOW_KB = 50 * 1024

function Mem.parse(text)
    if type(text) ~= "string" then return nil end
    local avail = tonumber(text:match("MemAvailable:%s*(%d+)"))
    if avail then return avail end
    local free = tonumber(text:match("MemFree:%s*(%d+)"))
    local cached = tonumber(text:match("\nCached:%s*(%d+)")) or 0
    local buffers = tonumber(text:match("Buffers:%s*(%d+)")) or 0
    return free and (free + cached + buffers) or nil
end

function Mem.availableKB()
    local f = io.open("/proc/meminfo", "r")
    if not f then return nil end
    local text = f:read(4096)
    f:close()
    return Mem.parse(text)
end

function Mem.low(limit_kb)
    local kb = Mem.availableKB()
    return kb ~= nil and kb < (limit_kb or Mem.LOW_KB)
end

-- "212 MB" for crash.log.
function Mem.describe()
    local kb = Mem.availableKB()
    return kb and string.format("%d MB", math.floor(kb / 1024 + 0.5)) or "unknown"
end

-- What KOReader's own process holds, in KB (VmRSS in /proc/self/status).
function Mem.processKB()
    local f = io.open("/proc/self/status", "r")
    if not f then return nil end
    local text = f:read("*a")
    f:close()
    return tonumber(type(text) == "string" and text:match("VmRSS:%s*(%d+)") or nil)
end

local last                    -- { avail, rss, lua, time } of the last line

local function mb(kb) return kb and math.floor(kb / 1024 + 0.5) or nil end

local function change(now, before)
    if not (now and before) then return "" end
    local d = mb(now - before)
    if d == 0 then return "" end
    return string.format(" (%s%d)", d > 0 and "+" or "", d)
end

-- The line for crash.log (without "Aleph: "); `where` says what happened.
function Mem.line(where, avail, rss, lua, prev, now)
    local parts = {}
    parts[#parts + 1] = avail and string.format("device has %d MB left%s", mb(avail), change(avail, prev and prev.avail)) or "device: unknown"
    if rss then parts[#parts + 1] = string.format("KOReader uses %d MB%s", mb(rss), change(rss, prev and prev.rss)) end
    if lua then parts[#parts + 1] = string.format("of which Lua %d MB%s", mb(lua), change(lua, prev and prev.lua)) end
    local text = "memory " .. tostring(where) .. ": " .. table.concat(parts, ", ")
    if prev and prev.time and now then
        text = text .. string.format(" — changes since %s", os.date("%H:%M", prev.time))
    end
    return text
end

function Mem.report(where)
    local avail, rss, lua = Mem.availableKB(), Mem.processKB(), collectgarbage("count")
    local now = os.time()
    local text = Mem.line(where, avail, rss, lua, last, now)
    last = { avail = avail, rss = rss, lua = lua, time = now }
    pcall(function()
        local logger = require("logger")
        if avail and avail < Mem.LOW_KB then logger.warn("Aleph: " .. text) else logger.info("Aleph: " .. text) end
    end)
    return text
end

-- Aleph modification, 2026-11-19 (1.2.51): below this, a Home page that has
-- just been built gives back what Lua no longer uses. A crash.log had the
-- device at 38 MB left two Home pages after it started, and frozen for three
-- minutes at the next tap.
Mem.RELIEVE_KB = 120 * 1024

-- The short form for a line: "device has 63 MB left, KOReader uses 300 MB,
-- of which Lua 90 MB".
function Mem.summary()
    local avail, rss, lua = Mem.availableKB(), Mem.processKB(), collectgarbage("count")
    return (Mem.line("now", avail, rss, lua):gsub("^memory now: ", ""))
end

-- When memory is low: a full garbage collection (blitbuffers of widgets no
-- longer shown are freed only then), and Aleph's cover cache down to what is
-- on screen. Returns the KB gained, or nil when memory was not low.
function Mem.relieve(where)
    local before = Mem.availableKB()
    if not before or before >= Mem.RELIEVE_KB then return nil end
    pcall(function() require("aleph_board_ui").trimCoverCache(24, 6 * 1024 * 1024) end)
    collectgarbage("collect")
    collectgarbage("collect")
    local after = Mem.availableKB() or before
    pcall(function()
        require("logger").info(string.format("Aleph: memory low %s: %d MB left, %d MB after freeing what was no longer used",
            tostring(where), mb(before), mb(after)))
    end)
    return after - before
end

Mem.EVERY = 600               -- seconds between two lines while reading

local tick
function Mem.watch()
    local UIManager = require("ui/uimanager")
    if tick then UIManager:unschedule(tick) end
    tick = function()
        Mem.report("while reading")
        UIManager:scheduleIn(Mem.EVERY, tick)
    end
    UIManager:scheduleIn(Mem.EVERY, tick)
end

function Mem.unwatch()
    if not tick then return end
    require("ui/uimanager"):unschedule(tick)
    tick = nil
end

return Mem
