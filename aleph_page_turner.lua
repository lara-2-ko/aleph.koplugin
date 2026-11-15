-- Aleph modification, 2026-11-14: the page turner's battery on the bottom
-- line of a book's page.
--[[--
With the BT Manager / HID Passthrough plugin running a Bluetooth page
turner, the bottom line's right-hand slot (aleph_bookends.lua) ends with
" · <bluetooth> 80%": the page turner's battery. Nothing is shown, and no
dot, while no device reports a battery level.

Where the level comes from:
  HID Passthrough's own reading (its _battery), which it takes 2 s after a
  book opens and then every 5 minutes; and Aleph's own look at its daemon
  (GET /status, the lowest battery_level among the devices connected),
  every 5 minutes while a book is open, and, while no level is known, at
  most every 20 seconds as the reader turns pages: a page turner that was
  asleep when the book opened shows its level with the first page it turns,
  instead of 5 minutes later.

When the daemon cannot be reached, Aleph stops asking until the next
5-minute look. Settings: Book margins > Page turner battery (aleph setting
bookends.page_turner, on unless turned off).
]]

local PT = {}

PT.QUICK = 20   -- seconds between looks while no level is known
PT.SLOW = 300   -- seconds between looks once known, or with the daemon down

local state = { level = nil, asked_at = nil, daemon_down = false, ui = nil, hooked = false, task = nil, pending = false }

local function hidOf(ui)
    local p = ui and rawget(ui, "hidpassthrough")
    if type(p) ~= "table" then
        pcall(function() p = require("pluginloader"):getPluginInstance("hidpassthrough") end)
    end
    return type(p) == "table" and p or nil
end
PT.hidOf = hidOf

-- The lowest level among the connected devices that report one, or nil.
function PT.lowest(data)
    local lowest
    if type(data) == "table" and type(data.connections) == "table" then
        for _i, conn in ipairs(data.connections) do
            local level = type(conn) == "table" and tonumber(conn.battery_level)
            if level and (not lowest or level < lowest) then lowest = level end
        end
    end
    return lowest
end

-- Whether the setting is on (default on).
function PT.wanted()
    local ok, on = pcall(function()
        local s = G_reader_settings:readSetting("aleph")
        local b = type(s) == "table" and type(s.bookends) == "table" and s.bookends or {}
        return b.page_turner ~= false
    end)
    return not ok or on
end

-- The level to show, 0-100, or nil.
function PT.level(ui)
    local hid = hidOf(ui)
    if not hid then return nil end
    -- Aleph's own look when it is recent (it also sees a page turner that
    -- went away), else HID Passthrough's.
    local level
    if state.asked_at and os.time() - state.asked_at <= PT.SLOW + 60 then
        level = state.level
    else
        level = tonumber(rawget(hid, "_battery"))
    end
    if not level then return nil end
    return math.max(0, math.min(100, math.floor(level + 0.5)))
end

local function repaint()
    local ui = state.ui
    if not (ui and ui.document) then return end
    pcall(function() require("aleph_bookends").repaint(ui) end)
end

-- Asks the daemon now. Repaints the bottom line when the level changed.
function PT.ask(ui)
    ui = ui or state.ui
    local hid = hidOf(ui)
    state.asked_at = os.time()
    if not (hid and type(hid._httpGetJson) == "function") then return end
    local ok, data, err = pcall(hid._httpGetJson, hid, "/status")
    local before = state.level
    if not ok or not data then
        state.daemon_down = true
        state.level = nil
    else
        state.daemon_down = false
        state.level = PT.lowest(data)
    end
    if state.level ~= before then repaint() end
end

-- Any input while a book is open (a page turned by the page turner, or a
-- tap): a quick look when no level is known yet.
local Listener = {}
function Listener:onInputEvent()
    local ui = state.ui
    if not (ui and ui.document) or state.pending then return end
    if state.daemon_down or PT.level(ui) then return end
    if state.asked_at and os.time() - state.asked_at < PT.QUICK then return end
    if not (PT.wanted() and hidOf(ui)) then return end
    state.pending = true
    local UIManager = require("ui/uimanager")
    UIManager:nextTick(function()
        state.pending = false
        PT.ask(ui)
    end)
end
-- The hook container wraps this; Listener is never closed.
function Listener:onCloseWidget() end

-- A book opened: the 5-minute look starts, and input is listened to.
function PT.attach(ui)
    if not (ui and ui.document) then return end
    -- (HID Passthrough loads after Aleph: whether it is there is looked at
    -- when asking, not now.)
    local UIManager = require("ui/uimanager")
    state.ui = ui
    state.level, state.asked_at, state.daemon_down = nil, nil, false
    if not state.hooked and UIManager.event_hook then
        local ok = pcall(function() UIManager.event_hook:registerWidget("InputEvent", Listener) end)
        state.hooked = ok
    end
    if state.task then UIManager:unschedule(state.task) end
    state.task = function()
        if not (state.ui and state.ui.document) then return end
        if PT.wanted() then
            state.daemon_down = false
            PT.ask(state.ui)
        end
        UIManager:scheduleIn(PT.SLOW, state.task)
    end
    -- First look shortly after HID Passthrough's own (2 s after opening).
    UIManager:scheduleIn(4, state.task)
end

function PT.detach(ui)
    if ui and state.ui ~= ui then return end
    if state.task then
        pcall(function() require("ui/uimanager"):unschedule(state.task) end)
    end
    state.task, state.ui, state.level = nil, nil, nil
end

-- For tests.
function PT._state() return state end
function PT._reset()
    state = { level = nil, asked_at = nil, daemon_down = false, ui = nil, hooked = state.hooked, task = nil, pending = false }
end

return PT
