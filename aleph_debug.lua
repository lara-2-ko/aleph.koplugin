-- Aleph modification, 2026-11-14: the troubleshooting log, behind a switch.
--[[--
Some of what Aleph does is worth writing down only when something is being
tracked down: each step of setting up a book as it opens, for one. Written
always, those lines went to KOReader's log (crash.log) on every book opened.

    local Debug = require("aleph_debug")
    Debug.log("reader step", name)     -- written only while the switch is on
    Debug.on()                         -- whether it is

The switch is Settings > About > Troubleshooting log (the setting
aleph.debug_log), off unless turned on. Failures are not behind it: those
are always written (aleph_try.lua, and the warnings beside each step).
]]

local Debug = {}

function Debug.on()
    return require("aleph_prefs").is("debug_log")
end

function Debug.log(...)
    if not Debug.on() then return end
    require("logger").info("Aleph: debug:", ...)
end

return Debug
