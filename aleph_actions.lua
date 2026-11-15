-- Aleph modification, 2026-11-10: choosing what Aleph's buttons and widgets do.
--[[--
Two things can be set (Settings > Widget actions):

  Quick settings  the buttons of the Quick settings widget, up to five: what
                  each does, its icon and its name. Built from Aleph's own
                  actions (Wi-Fi, Light, Night, Rotate, Sync / Refresh, the
                  library's pages) and every action KOReader and its plugins
                  offer to gestures (the Dispatcher's list), after the idea in
                  Neo QuickSettings (neo_quicksetting.koplugin): any installed
                  plugin that adds a gesture action can be put on a button.
  Widget taps     what a tap on a widget opens, where it has no button of its
                  own under the finger: its usual page, nothing, or any of the
                  same actions.

Actions are strings: "aleph:<kind>" for Aleph's own (a board action),
"ko:<id>" for a KOReader action, "default" and "none" for widget taps.
Settings: aleph.quick_buttons (a list of { action, icon, label }) and
aleph.widget_taps (widget key -> action).
]]

local Prefs = require("aleph_prefs")
local _ = require("gettext")
local try = require("aleph_try").call

local Actions = {}

local MAX_BUTTONS = 5
Actions.MAX_BUTTONS = MAX_BUTTONS

-- Aleph's own actions: id, name, icon, the board action they run.
local ALEPH = {
    { id = "aleph:wifi", label = function() return _("Wi-Fi") end, icon = "wifi", run = { kind = "wifi" } },
    { id = "aleph:frontlight", label = function() return _("Light") end, icon = "sun", run = { kind = "frontlight" } },
    { id = "aleph:night", label = function() return _("Night") end, icon = "moon", run = { kind = "night" } },
    { id = "aleph:rotate", label = function() return _("Rotate") end, icon = "rotate-cw-square", run = { kind = "rotate" } },
    { id = "aleph:refresh", label = function()
        return require("aleph_integrations").syncthing() and _("Sync") or _("Refresh")
    end, icon = "refresh-cw", run = { kind = "refresh" }, sub = function()
        return _("With KOSyncthing+ and Syncery: both e-readers synced in one go; KOSyncthing+ alone: Syncthing; otherwise a library rescan")
    end },
    { id = "aleph:library", label = function() return _("Library") end, icon = "library", run = { kind = "link", link = "library" } },
    { id = "aleph:series", label = function() return _("Series") end, icon = "layers-2", run = { kind = "link", link = "series" } },
    { id = "aleph:authors", label = function() return _("Authors") end, icon = "user-round", run = { kind = "link", link = "authors" } },
    { id = "aleph:collections", label = function() return _("Collections") end, icon = "folder-open", run = { kind = "link", link = "collections" } },
    { id = "aleph:history", label = function() return _("History") end, icon = "calendar-clock", run = { kind = "link", link = "history" } },
    { id = "aleph:search", label = function() return _("Search") end, icon = "search", run = { kind = "link", link = "search" } },
    { id = "aleph:menu", label = function() return _("Aleph menu") end, icon = "menu", run = { kind = "menu" } },
}
local ALEPH_BY_ID = {}
for _i, a in ipairs(ALEPH) do ALEPH_BY_ID[a.id] = a end
Actions.ALEPH = ALEPH

-- The buttons as they were before they could be chosen.
local DEFAULT_BUTTONS = { "aleph:wifi", "aleph:frontlight", "aleph:night", "aleph:rotate", "aleph:refresh" }
Actions.DEFAULT_BUTTONS = DEFAULT_BUTTONS

-- --------------------------------------------------------- KOReader's list
-- KOReader keeps its gesture actions in a local table of its Dispatcher; it
-- is reached the way Neo QuickSettings reaches it, through
-- Dispatcher.registerAction's upvalues. Only plain actions (no value to
-- set) that work outside a book are offered.
local SECTIONS = {
    { "general", function() return _("General") end }, { "device", function() return _("Device") end },
    { "screen", function() return _("Screen and lights") end }, { "filemanager", function() return _("File browser") end },
}

local ko_cache
function Actions.koreader()
    if ko_cache then return ko_cache end
    local out = {}
    try(function()
        local Dispatcher = require("dispatcher")
        try(function() Dispatcher:init() end)
        local list
        local i = 1
        while true do
            local name, value = debug.getupvalue(Dispatcher.registerAction, i)
            if not name then break end
            if name == "settingsList" then list = value end
            i = i + 1
        end
        if type(list) ~= "table" then return end
        for id, def in pairs(list) do
            if type(def) == "table" and def.title and def.category == "none"
                    and (def.condition == nil or def.condition == true)
                    and not def.reader and not def.rolling and not def.paging then
                local section
                for _j, s in ipairs(SECTIONS) do if def[s[1]] then section = s[2](); break end end
                out[#out + 1] = { id = "ko:" .. id, label = tostring(def.title), sub = section }
            end
        end
    end)
    table.sort(out, function(a, b) return a.label:lower() < b.label:lower() end)
    ko_cache = out
    return out
end
-- Plugins register their actions as they load: asked again next time.
function Actions.forget() ko_cache = nil end

-- An action's name, or nil when it is not known (a plugin removed since).
function Actions.label(id)
    if id == "default" then return _("Default") end
    if id == "none" then return _("Nothing") end
    local a = ALEPH_BY_ID[id]
    if a then return a.label() end
    if type(id) == "string" and id:sub(1, 3) == "ko:" then
        for _i, k in ipairs(Actions.koreader()) do
            if k.id == id then return k.label end
        end
    end
    return nil
end

-- A good icon for an action, for a new button.
function Actions.iconFor(id)
    local a = ALEPH_BY_ID[id]
    return a and a.icon or "zap"
end

-- The board action that runs `id`, or nil.
function Actions.boardAction(id)
    local a = ALEPH_BY_ID[id]
    if a then return a.run end
    if type(id) == "string" and id:sub(1, 3) == "ko:" then return { kind = "dispatch", id = id:sub(4) } end
    if id == "none" then return { kind = "noop" } end
    return nil
end

-- --------------------------------------------------------------- settings
local function settings()
    local s = Prefs.table()
    return s
end

-- The Quick settings buttons: { action, icon, label } each, label nil for the
-- action's own name. has_light: whether the device has a frontlight (Light is
-- left out of the defaults without one).
function Actions.buttons(has_light)
    local stored = settings().quick_buttons
    if type(stored) == "table" and #stored > 0 then
        local out = {}
        for _i, b in ipairs(stored) do
            if type(b) == "table" and type(b.action) == "string" and #out < MAX_BUTTONS then
                out[#out + 1] = { action = b.action, icon = b.icon, label = b.label }
            end
        end
        if #out > 0 then return out, true end
    end
    local out = {}
    for _i, id in ipairs(DEFAULT_BUTTONS) do
        if id ~= "aleph:frontlight" or has_light then out[#out + 1] = { action = id } end
    end
    return out, false
end

function Actions.saveButtons(list)
    local s = settings()
    s.quick_buttons = list
    G_reader_settings:saveSetting("aleph", s)
end

function Actions.resetButtons()
    local s = settings()
    s.quick_buttons = nil
    G_reader_settings:saveSetting("aleph", s)
end

-- A button's name and icon as drawn.
function Actions.buttonLabel(b)
    if b.label and b.label ~= "" then return b.label end
    return Actions.label(b.action) or _("Missing")
end
function Actions.buttonIcon(b)
    return b.icon or Actions.iconFor(b.action)
end

-- ------------------------------------------------------------ widget taps
-- A widget's key: its type, and what tells two of a type apart.
function Actions.widgetKey(item)
    local p = item.props or {}
    local extra = p.source or p.link or p.animal
    return extra and (item.type .. ":" .. extra) or item.type
end

function Actions.widgetTap(key)
    local taps = settings().widget_taps
    return type(taps) == "table" and taps[key] or "default"
end

function Actions.setWidgetTap(key, action)
    local s = settings()
    s.widget_taps = type(s.widget_taps) == "table" and s.widget_taps or {}
    s.widget_taps[key] = (action ~= "default") and action or nil
    G_reader_settings:saveSetting("aleph", s)
end

-- What a tap on `item` runs: the chosen action, or `default` (its usual one).
function Actions.tapFor(item, default)
    local chosen = Actions.widgetTap(Actions.widgetKey(item))
    if chosen == "default" then return default end
    return Actions.boardAction(chosen) or default
end

return Actions
