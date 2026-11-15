-- Aleph modification, 2026-11-14: safety nets that say when they catch
-- something.
--[[--
Aleph runs much of its work protected, so that a failure in one part (a
KOReader change, another plugin's API, a file that cannot be read) never
freezes the reader. Those protected calls used to throw the error away.

    local try = require("aleph_try").call
    try(fn, ...)          -- like pcall(fn, ...): returns ok, error

A failure is written to KOReader's log (crash.log) as

    Aleph: aleph_reader_sheet.lua:147 failed: <the error>

naming the file and line of the call. Each place and message is written
once per session (some calls run on every page turn or every minute), and
at most 200 lines in all, so a failure that repeats cannot flood the log.
Try.report(where, err) writes one for a place given by hand.
]]

local Try = {}

local MAX_LINES = 200
local seen = {}
local written = 0

-- "file.lua:123" for the code `level` calls up from here.
local function where(level)
    local info = debug.getinfo(level, "Sl")
    if not info then return "?" end
    local src = tostring(info.short_src or info.source or "?")
    return (src:match("([^/\\]+)$") or src) .. ":" .. tostring(info.currentline or "?")
end

function Try.report(place, err)
    local msg = tostring(err)
    local key = tostring(place) .. "|" .. msg:sub(1, 300)
    if seen[key] then
        seen[key] = seen[key] + 1
        return
    end
    seen[key] = 1
    if written >= MAX_LINES then return end
    written = written + 1
    pcall(function()
        local logger = require("logger")
        logger.warn("Aleph: " .. tostring(place) .. " failed:", msg)
        if written == MAX_LINES then
            logger.warn("Aleph: more failures are not written this session")
        end
    end)
end

-- pcall that reports a failure with the caller's file and line.
function Try.call(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then Try.report(where(3), err) end
    return ok, err
end

-- How often each failure happened this session (for tests and debugging).
function Try.counts()
    return seen
end

function Try._reset()
    seen, written = {}, 0
end

return Try
