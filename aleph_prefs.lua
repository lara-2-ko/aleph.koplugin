-- Aleph modification, 2026-11-09: Aleph's own settings, read one way.
--[[--
Aleph keeps its settings in one table, G_reader_settings "aleph". Six screens
each had their own copy of "is the Aleph style on for KOReader's dialogs?";
they ask here now.
]]

local Prefs = {}

-- Aleph's version, shown in Settings and the menu (and _meta.lua).
Prefs.VERSION = "1.0.1"

-- The settings table (an empty one when there is none yet; not saved).
function Prefs.get()
    local stored = G_reader_settings:readSetting("aleph")
    return type(stored) == "table" and stored or {}
end

-- True unless the setting is explicitly off.
function Prefs.on(key)
    return Prefs.get()[key] ~= false
end

-- Settings > Look > KOReader's dialogs in Aleph's style.
function Prefs.styleDialogs()
    return Prefs.on("style_dialogs")
end

return Prefs
