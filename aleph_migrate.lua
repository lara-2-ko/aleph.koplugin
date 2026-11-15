-- Aleph modification, 2026-11-09: carrying everything over from the plugin's
-- old name.
--[[--
Up to 0.1.59 the plugin lived in readingboard.koplugin and kept its things
under "readingboard". From 0.1.60 it is aleph.koplugin and keeps them under
"aleph". Run once at load, before anything reads a setting, this moves over,
without losing anything:

  settings      G_reader_settings "readingboard" → "aleph" (the old entry is
                left, so the old folder still works if put back)
  library       settings/readingboard_index.lua → aleph_index.lua
  cache         cache/readingboard (covers, author portraits, pins' pictures,
                chapter maps, icons) → cache/aleph, renamed, so nothing is
                drawn or downloaded again
  gestures      every gesture bound to a readingboard_* action now runs the
                aleph_* one (KOReader's Gestures plugin data, see `gestures`)
  pins          a book's "readingboard_pins" → "aleph_pins", when the book is
                opened (see `docKey`)

It also notices the old folder still installed beside the new one (both would
hook the same screens) and says, once, to remove it.
]]

local try = require("aleph_try").call
local OLD = "reading" .. "board"
local NEW = "aleph"

local Migrate = {}

local function exists(path)
    local lfs = require("libs/libkoreader-lfs")
    return lfs.attributes(path, "mode") ~= nil
end

-- Settings, index and cache. Safe to run any number of times.
function Migrate.run()
    if Migrate.done then return end
    Migrate.done = true
    try(function()
        local old = G_reader_settings:readSetting(OLD)
        if type(old) == "table" and G_reader_settings:readSetting(NEW) == nil then
            local copy = {}
            for k, v in pairs(old) do copy[k] = v end
            G_reader_settings:saveSetting(NEW, copy)
            G_reader_settings:flush()
        end
    end)
    try(Migrate.names)
    try(function()
        local DataStorage = require("datastorage")
        local settings_dir = DataStorage:getSettingsDir()
        local old_index = settings_dir .. "/" .. OLD .. "_index.lua"
        local new_index = settings_dir .. "/" .. NEW .. "_index.lua"
        if exists(old_index) and not exists(new_index) then os.rename(old_index, new_index) end
        local cache = DataStorage:getDataDir() .. "/cache/"
        if exists(cache .. OLD) and not exists(cache .. NEW) then os.rename(cache .. OLD, cache .. NEW) end
    end)
end

-- 1.1.46: the names left from the projects Aleph grew out of (BookOrbit's
-- "catalog", the Quick Top Bar plugin, Reading Board's "rb") became Aleph's.
-- What is saved under an old name is moved to the new one, once; a value
-- already under the new name is never overwritten. Returns true when
-- something moved.
Migrate.SETTING_NAMES = {
    -- In the "aleph" table.
    catalog_board = "board_layout",
    catalog_board_dust = "board_dust",
    catalog_dashboard_tap_resumes = "board_tap_resumes",
    catalog_recent_searches = "recent_searches",
}
-- The reader option "Background" (a book's own value is kept as
-- copt_<name>, KOReader's default for it under the same key).
Migrate.OPTION_OLD, Migrate.OPTION_NEW = "rb_page_background", "aleph_page_background"

function Migrate.names()
    local moved = false
    local stored = G_reader_settings:readSetting(NEW)
    if type(stored) == "table" then
        for old, new in pairs(Migrate.SETTING_NAMES) do
            if stored[old] ~= nil then
                if stored[new] == nil then stored[new] = stored[old] end
                stored[old] = nil
                moved = true
            end
        end
        if moved then G_reader_settings:saveSetting(NEW, stored) end
    end
    -- The top menu's settings were the Quick Top Bar plugin's own table.
    -- Copied, not moved: that plugin, where it is still installed, keeps its.
    local bar = G_reader_settings:readSetting("quicktopbar")
    if type(bar) == "table" and G_reader_settings:readSetting("aleph_topbar") == nil then
        local copy = {}
        for k, v in pairs(bar) do copy[k] = v end
        G_reader_settings:saveSetting("aleph_topbar", copy)
        moved = true
    end
    local old_default = G_reader_settings:readSetting("copt_" .. Migrate.OPTION_OLD)
    if old_default ~= nil then
        if G_reader_settings:readSetting("copt_" .. Migrate.OPTION_NEW) == nil then
            G_reader_settings:saveSetting("copt_" .. Migrate.OPTION_NEW, old_default)
        end
        G_reader_settings:delSetting("copt_" .. Migrate.OPTION_OLD)
        moved = true
    end
    if moved then G_reader_settings:flush() end
    return moved
end

-- A book's own page background, saved under the option's old name: moved to
-- the new one as the book opens, and given to the reader's options, which
-- were read before this could run. Returns the value moved, or nil.
function Migrate.pageBackground(ui)
    local ds = ui and ui.doc_settings
    if not ds then return nil end
    local old_key, new_key = "copt_" .. Migrate.OPTION_OLD, "copt_" .. Migrate.OPTION_NEW
    local old = ds:readSetting(old_key)
    if old == nil then return nil end
    ds:delSetting(old_key)
    if ds:readSetting(new_key) ~= nil then return nil end
    ds:saveSetting(new_key, old)
    local configurable = ui.document and ui.document.configurable
    if configurable then configurable[Migrate.OPTION_NEW] = old end
    return old
end

-- Actions bound to gestures under a name of their own that changed.
local ACTION_NAMES = { [Migrate.OPTION_OLD] = Migrate.OPTION_NEW }

-- Renames the readingboard_* actions in the Gestures plugin's bindings.
-- Returns how many were moved.
function Migrate.gestureData(data)
    if type(data) ~= "table" then return 0 end
    local moved = 0
    for _section, gestures in pairs(data) do
        if type(gestures) == "table" then
            for _gesture, actions in pairs(gestures) do
                if type(actions) == "table" then
                    local renames = {}
                    for key, value in pairs(actions) do
                        if type(key) == "string" and (key:sub(1, #OLD + 1) == OLD .. "_" or ACTION_NAMES[key]) then
                            renames[key] = value
                        end
                    end
                    for key, value in pairs(renames) do
                        actions[key] = nil
                        actions[ACTION_NAMES[key] or (NEW .. key:sub(#OLD + 1))] = value
                        moved = moved + 1
                    end
                    -- The order of several actions on one gesture.
                    if type(actions.settings) == "table" and type(actions.settings.order) == "table" then
                        for i, key in ipairs(actions.settings.order) do
                            if type(key) == "string" and ACTION_NAMES[key] then
                                actions.settings.order[i] = ACTION_NAMES[key]
                            elseif type(key) == "string" and key:sub(1, #OLD + 1) == OLD .. "_" then
                                actions.settings.order[i] = NEW .. key:sub(#OLD + 1)
                            end
                        end
                    end
                end
            end
        end
    end
    return moved
end

function Migrate.gestures(ui)
    local gestures = ui and ui.gestures
    if type(gestures) ~= "table" then return end
    -- The bindings ("gesture_reader", "gesture_fm": gesture → { action = true })
    -- are gestures.data, or settings_data.data in KOReader versions that keep
    -- settings/gestures.lua open that way; both are looked at.
    local moved = Migrate.gestureData(gestures.data)
    if type(gestures.settings_data) == "table" and gestures.settings_data.data ~= gestures.data then
        moved = moved + Migrate.gestureData(gestures.settings_data.data)
    end
    if moved > 0 then
        gestures.updated = true
        try(function() if gestures.onFlushSettings then gestures:onFlushSettings() end end)
    end
end

-- A book's own setting under the new name, moved over the first time.
function Migrate.docKey(doc_settings, key)
    if not doc_settings then return end
    local value = doc_settings:readSetting(key)
    if value ~= nil then return value end
    local old_key = OLD .. key:sub(#NEW + 1)
    local old = doc_settings:readSetting(old_key)
    if old ~= nil then
        doc_settings:saveSetting(key, old)
        doc_settings:delSetting(old_key)
    end
    return old
end

-- The old folder still installed: say so once a session.
function Migrate.warnOldFolder(ui)
    if Migrate.warned or not ui then return end
    local old = rawget(ui, OLD)
    if type(old) ~= "table" then return end
    Migrate.warned = true
    local UIManager = require("ui/uimanager")
    UIManager:scheduleIn(1, function()
        UIManager:show(require("ui/widget/infomessage"):new{
            text = require("aleph_gettext")("Aleph is now in aleph.koplugin. Please delete the old readingboard.koplugin folder from koreader/plugins and restart KOReader: with both installed, screens are hooked twice."),
        })
    end)
end

return Migrate
