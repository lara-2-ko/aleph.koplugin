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
5-minute look. The daemon is asked without waiting for it
(aleph_local_get.lua): the answer comes a moment later and the bottom line
is drawn again if the level changed, so a daemon that is slow to answer
never holds up a page turn. Without HID Passthrough installed, found out a
few seconds after a book opens, nothing is asked or looked at for that book. Settings: Book margins > Page turner battery (aleph setting
bookends.page_turner, on unless turned off).
]]

local PT = {}

PT.QUICK = 20   -- seconds between looks while no level is known
PT.SLOW = 300   -- seconds between looks once known, or with the daemon down

local state = { level = nil, asked_at = nil, daemon_down = false, ui = nil, hooked = false, task = nil, asking = false, absent = false }

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
    if state.absent then return nil end
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

local function decode(body)
    local data
    for _i, name in ipairs({ "rapidjson", "json" }) do
        local ok, lib = pcall(require, name)
        if ok and type(lib) == "table" and type(lib.decode) == "function" then
            local good, value = pcall(lib.decode, body)
            if good and type(value) == "table" then data = value; break end
        end
    end
    return data
end

-- The daemon's answer (or none): the level kept, and the bottom line drawn
-- again when it changed.
local function answered(body)
    state.asking = false
    local before = state.level
    local data = body and decode(body) or nil
    if not data then
        state.daemon_down = true
        state.level = nil
    else
        state.daemon_down = false
        state.level = PT.lowest(data)
    end
    if state.level ~= before then repaint() end
end

-- Asks the daemon now, without waiting for it: the answer comes to
-- `answered` a moment later.
function PT.ask(ui)
    ui = ui or state.ui
    local hid = hidOf(ui)
    if not hid or state.asking then return end
    state.asked_at = os.time()
    state.asking = true
    local host = type(hid.API_HOST) == "string" and hid.API_HOST or "127.0.0.1"
    local port = tonumber(hid.API_PORT) or 8321
    local ok, err = pcall(function() require("aleph_local_get").get(host, port, "/status", answered) end)
    if not ok then
        state.asking = false
        state.daemon_down = true
        require("aleph_try").report("aleph_page_turner.lua ask", err)
    end
end

-- Any input while a book is open (a page turned by the page turner, or a
-- tap): a quick look when no level is known yet. Without HID Passthrough
-- this returns at its first line.
local Listener = {}
function Listener:onInputEvent()
    if state.absent or state.asking or state.daemon_down then return end
    local ui = state.ui
    if not (ui and ui.document) then return end
    if PT.level(ui) then return end
    if state.asked_at and os.time() - state.asked_at < PT.QUICK then return end
    if not (PT.wanted() and hidOf(ui)) then return end
    PT.ask(ui)
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
    state.level, state.asked_at, state.daemon_down, state.asking, state.absent = nil, nil, false, false, false
    if not state.hooked and UIManager.event_hook then
        local ok = pcall(function() UIManager.event_hook:registerWidget("InputEvent", Listener) end)
        state.hooked = ok
    end
    if state.task then UIManager:unschedule(state.task) end
    state.task = function()
        if not (state.ui and state.ui.document) then return end
        -- Every plugin is loaded by now: without HID Passthrough there is
        -- nothing to ask for this book, on a timer or on input.
        if not hidOf(state.ui) then
            state.absent = true
            return
        end
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
    state = { level = nil, asked_at = nil, daemon_down = false, ui = nil, hooked = state.hooked, task = nil, asking = false, absent = false }
end

return PT
