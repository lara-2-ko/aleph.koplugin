-- Aleph modification, 2026-11-09: Aleph's own settings, read one way.
--[[--
Aleph keeps its settings in one table, G_reader_settings "aleph". Six screens
each had their own copy of "is the Aleph style on for KOReader's dialogs?";
they ask here now.
]]

local Prefs = {}

-- Aleph's version, shown in Settings and the menu. It is written in one
-- place, _meta.lua (what KOReader itself reads), and read from there.
local function metaVersion()
    local dir = tostring(debug.getinfo(1, "S").source):match("^@(.*)/[^/]*$") or "."
    local ok, meta = pcall(dofile, dir .. "/_meta.lua")
    return ok and type(meta) == "table" and type(meta.version) == "string" and meta.version or nil
end
Prefs.VERSION = metaVersion() or "?"

-- The settings table, for reading (an empty one when there is none yet; not
-- saved).
function Prefs.get()
    local stored = G_reader_settings and G_reader_settings:readSetting("aleph")
    return type(stored) == "table" and stored or {}
end

-- The settings table, for writing: made and saved when there is none yet,
-- so what is put in it is kept.
function Prefs.table()
    local stored = G_reader_settings:readSetting("aleph")
    if type(stored) ~= "table" then
        stored = {}
        G_reader_settings:saveSetting("aleph", stored)
    end
    return stored
end

-- True unless the setting is explicitly off (features that are on by default).
function Prefs.on(key)
    return Prefs.get()[key] ~= false
end

-- True only when the setting is explicitly on (features off by default).
function Prefs.is(key)
    return Prefs.get()[key] == true
end

-- Sets one setting (nil removes it).
function Prefs.set(key, value)
    local stored = Prefs.table()
    stored[key] = value
    G_reader_settings:saveSetting("aleph", stored)
end

-- Settings > Look > KOReader's dialogs in Aleph's style.
function Prefs.styleDialogs()
    return Prefs.on("style_dialogs")
end

return Prefs
