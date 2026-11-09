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
    pcall(function()
        local old = G_reader_settings:readSetting(OLD)
        if type(old) == "table" and G_reader_settings:readSetting(NEW) == nil then
            local copy = {}
            for k, v in pairs(old) do copy[k] = v end
            G_reader_settings:saveSetting(NEW, copy)
            G_reader_settings:flush()
        end
    end)
    pcall(function()
        local DataStorage = require("datastorage")
        local settings_dir = DataStorage:getSettingsDir()
        local old_index = settings_dir .. "/" .. OLD .. "_index.lua"
        local new_index = settings_dir .. "/" .. NEW .. "_index.lua"
        if exists(old_index) and not exists(new_index) then os.rename(old_index, new_index) end
        local cache = DataStorage:getDataDir() .. "/cache/"
        if exists(cache .. OLD) and not exists(cache .. NEW) then os.rename(cache .. OLD, cache .. NEW) end
    end)
end

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
                        if type(key) == "string" and key:sub(1, #OLD + 1) == OLD .. "_" then
                            renames[key] = value
                        end
                    end
                    for key, value in pairs(renames) do
                        actions[key] = nil
                        actions[NEW .. key:sub(#OLD + 1)] = value
                        moved = moved + 1
                    end
                    -- The order of several actions on one gesture.
                    if type(actions.settings) == "table" and type(actions.settings.order) == "table" then
                        for i, key in ipairs(actions.settings.order) do
                            if type(key) == "string" and key:sub(1, #OLD + 1) == OLD .. "_" then
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
        pcall(function() if gestures.onFlushSettings then gestures:onFlushSettings() end end)
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
            text = "Aleph is now in aleph.koplugin. Please delete the old readingboard.koplugin folder from koreader/plugins and restart KOReader: with both installed, screens are hooked twice.",
        })
    end)
end

return Migrate
