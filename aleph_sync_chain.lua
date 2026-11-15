-- Aleph modification, 2026-11-11: one tap to sync two e-readers through
-- KOSyncthing+ and Syncery.
--[[--
Both crash logs showed why a book read to 60% on one Kindle stayed at 0% on
the other: Syncthing runs on a Kindle only when started, and the two were
never running at the same time. Syncery's own Sync now asks KOSyncthing+ for
a Quick Sync, which starts Syncthing for about twenty seconds; with the other
Kindle not listening in those seconds nothing crosses, and Syncery gives up
after five tries ("max_retries").

Sync (the Quick settings button, the reader menu's Sync now, or the "Sync
e-readers" action) now runs one chain, shown step by step:

  1. Wi-Fi on.
  2. Syncthing started (KOSyncthing+), and waited for until it answers.
  3. Syncery saves the open book's position and annotations (its Sync now).
  4. Syncthing looks at its folders, and waits for another device of the
     folders to connect: tap Sync on the other e-reader too (up to 3 min).
  5. Waits until the files are exchanged both ways (up to 3 min).
  6. In a book, Syncery looks again for a newer position on the other
     device (its jump offer); on the home screen, Aleph rescans the library.
  7. Syncthing is stopped again if the chain started it.

Everything goes through KOSyncthing+'s public API (_G.KOSyncthingPlusAPI:
control.start/stop, status.isRunning, apiCall to Syncthing's REST API) and
Syncery's own methods (syncNow, checkRemote).
]]

local try = require("aleph_try").call
local Chain = {}

Chain.CONNECT_WAIT = 180
Chain.EXCHANGE_WAIT = 180
Chain.TICK = 2

local function api()
    local a = rawget(_G, "KOSyncthingPlusAPI")
    if type(a) == "table" and type(a.apiCall) == "function" then return a end
    return nil
end
Chain.api = api

local function syncery(ui)
    local found
    try(function()
        found = require("aleph_plugins").find("syncery", ui, function(p) return type(p.syncNow) == "function" end)
    end)
    return found
end
Chain.syncery = syncery

-- Whether the chain can run here: KOSyncthing+ and Syncery both installed.
function Chain.available(ui)
    local s = syncery(ui)
    if not s then return false end
    return (api() ~= nil and s.use_syncthing ~= false) or s.use_cloud == true
end

-- How Syncery is set to carry the data: syncthing (through KOSyncthing+)
-- and/or cloud (Dropbox, WebDAV or FTP, Syncery's own).
function Chain.modes(ui)
    local s = syncery(ui)
    if not s then return false, false end
    local cloud = s.use_cloud == true
    local st = api() ~= nil and (s.use_syncthing == true or not cloud)
    return st, cloud
end
Chain.CLOUD_PEER_WAIT = 20

local function call(endpoint, method, body)
    local a = api()
    if not a then return nil end
    local ok, res = pcall(a.apiCall, endpoint, method or "GET", body)
    if ok and res then return res end
    return nil
end
Chain.call = call

local function isRunning()
    local a = api()
    local ok, yes = pcall(function() return a and a.status and a.status.isRunning() end)
    if ok and yes then return true end
    return call("system/status") ~= nil
end

-- The folders and the other devices they are shared with.
-- Returns my_id, folders { id, label, devices = { id = true } }, names { id = name }.
function Chain.topology()
    local status = call("system/status")
    local my = status and status.myID
    local names = {}
    for _i, d in ipairs(call("config/devices") or {}) do
        if type(d) == "table" and d.deviceID then names[d.deviceID] = d.name ~= "" and d.name or d.deviceID:sub(1, 7) end
    end
    local folders = {}
    for _i, f in ipairs(call("config/folders") or {}) do
        if type(f) == "table" and f.id and not f.paused then
            local devs = {}
            for _j, d in ipairs(f.devices or {}) do
                if d.deviceID and d.deviceID ~= my then devs[d.deviceID] = true end
            end
            folders[#folders + 1] = { id = f.id, label = (f.label and f.label ~= "") and f.label or f.id, devices = devs }
        end
    end
    return my, folders, names
end

-- The other devices connected now: { id = name }.
function Chain.connected(folders, names)
    local conns = call("system/connections")
    local out, any = {}, false
    local wanted = {}
    for _i, f in ipairs(folders or {}) do for id in pairs(f.devices) do wanted[id] = true end end
    for id, c in pairs(type(conns) == "table" and conns.connections or {}) do
        if type(c) == "table" and c.connected and wanted[id] then out[id] = names[id] or id:sub(1, 7); any = true end
    end
    return any and out or nil
end

-- How far the exchange is: done (true when every folder is up to date here
-- and on every connected device), and a percent.
function Chain.progress(folders, peers)
    local total, sum, done = 0, 0, true
    for _i, f in ipairs(folders) do
        local st = call("db/status?folder=" .. f.id)
        if type(st) ~= "table" then return false, 0 end
        local here = (st.state == "idle") and (tonumber(st.needTotalItems) or 0) == 0
        if not here then done = false end
        total = total + 1
        sum = sum + (here and 100 or 50)
        for id in pairs(peers or {}) do
            if f.devices[id] then
                local c = call("db/completion?folder=" .. f.id .. "&device=" .. id)
                local pct = type(c) == "table" and tonumber(c.completion) or 0
                if pct < 100 then done = false end
                total = total + 1
                sum = sum + math.min(100, pct)
            end
        end
    end
    return done, total > 0 and math.floor(sum / total) or 0
end

-- ------------------------------------------------------------ the run
-- ui: the reader or the file browser; o.on_done(ok) after it finishes.
function Chain.run(ui, o)
    o = o or {}
    local _ = require("aleph_gettext")
    local T = require("ffi/util").template
    local UIManager = require("ui/uimanager")
    local logger = require("logger")
    if Chain.running then
        try(function() require("aleph_toast").show(_("Already syncing…")) end)
        return
    end
    local in_book = ui and ui.document ~= nil
    local use_st, use_cloud = Chain.modes(ui)
    local steps = { { id = "wifi", label = _("Wi-Fi") } }
    if use_st then steps[#steps + 1] = { id = "start", label = _("Starting Syncthing") } end
    steps[#steps + 1] = { id = "save", label = _("Saving this e-reader's positions") }
    if use_st then
        steps[#steps + 1] = { id = "peer", label = use_cloud and _("Looking for another device nearby") or _("Looking for your other e-reader") }
        steps[#steps + 1] = { id = "swap", label = _("Exchanging reading data") }
    end
    if use_cloud then steps[#steps + 1] = { id = "cloud", label = _("Sending and receiving through the cloud") } end
    steps[#steps + 1] = { id = "check", label = in_book and _("Looking for a newer position") or _("Updating the library") }
    local state = { at = 1, started_here = false, note = nil, failed = nil, finished = false, cancelled = false }
    Chain.running = true
    local panel
    local function redraw() if panel and not panel.closed then panel:refresh() end end
    local function stepIndex(id) for i, s in ipairs(steps) do if s.id == id then return i end end end
    local function enter(id, note) state.at = stepIndex(id); state.note = note; redraw() end

    local function stopSyncthing()
        if not state.started_here then return end
        state.started_here = false
        try(function() api().control.stop(function() end) end)
    end
    local function finish(ok, msg)
        if state.finished then return end
        state.finished = true
        Chain.running = false
        if not ok then state.failed = msg end
        state.at = ok and (#steps + 1) or state.at
        state.note = ok and msg or nil
        redraw()
        -- Let Syncthing pass the last changes before stopping it.
        UIManager:scheduleIn(ok and 8 or 1, stopSyncthing)
        if ok then
            UIManager:scheduleIn(3, function() if panel and not panel.closed then panel:close() end end)
        end
        if o.on_done then pcall(o.on_done, ok) end
    end

    local my, folders, names, peers
    local t0
    local tick

    local function stepCheck()
        enter("check")
        local s = syncery(ui)
        if in_book and s then
            try(function()
                if type(s.checkRemote) == "function" then s:checkRemote() else s:syncNow() end
            end)
        end
        local who = {}
        for _id, n in pairs(peers or {}) do who[#who + 1] = n end
        table.sort(who)
        if use_cloud then who[#who + 1] = _("the cloud") end
        finish(true, T(_("Synced with %1."), table.concat(who, ", ")))
    end

    -- Syncery's cloud sync runs on its own (with its own progress): waited
    -- for until it is no longer under way.
    local function stepCloud()
        enter("cloud")
        local s = syncery(ui)
        t0 = os.time()
        tick = function()
            if state.finished then return end
            local busy = s and s._sync_all_in_progress
            if not busy and os.time() - t0 >= 3 then return stepCheck() end
            if os.time() - t0 > Chain.EXCHANGE_WAIT then
                return finish(false, _("The cloud sync did not finish in time. Check the connection, and the cloud settings in Syncery."))
            end
            UIManager:scheduleIn(Chain.TICK, tick)
        end
        UIManager:scheduleIn(Chain.TICK, tick)
    end
    local function afterSyncthing()
        if use_cloud then return stepCloud() end
        return stepCheck()
    end

    local function stepSwap()
        enter("swap")
        -- Look at the folders now, so what Syncery just wrote is offered.
        for _i, f in ipairs(folders) do call("db/scan?folder=" .. f.id, "POST") end
        t0 = os.time()
        local quiet = 0
        tick = function()
            if state.finished then return end
            local now_peers = Chain.connected(folders, names)
            if now_peers then peers = now_peers end
            local done, pct = Chain.progress(folders, peers)
            -- Syncthing may have been stopped by another plugin: once more.
            if not isRunning() and not state.restarted then
                state.restarted = true
                try(function() api().control.start(function() end) end)
                state.started_here = true
            end
            state.note = pct .. "%"
            redraw()
            -- Done twice in a row (a scan can start between two looks), and
            -- not in the first seconds (the two still compare their lists).
            if done and os.time() - t0 >= 6 then quiet = quiet + 1 else quiet = 0 end
            if quiet >= 2 then return afterSyncthing() end
            if os.time() - t0 > Chain.EXCHANGE_WAIT then
                return finish(false, _("The exchange did not finish in time. Try again with both e-readers on the same Wi-Fi."))
            end
            UIManager:scheduleIn(Chain.TICK, tick)
        end
        UIManager:scheduleIn(Chain.TICK, tick)
    end

    local function stepPeer()
        my, folders, names = Chain.topology()
        if not my or #folders == 0 then
            if use_cloud then return stepCloud() end
            return finish(false, _("Syncthing has no shared folders yet. Set them up in KOSyncthing+ first."))
        end
        local all = {}
        for _i, f in ipairs(folders) do for id in pairs(f.devices) do all[names[id] or id:sub(1, 7)] = true end end
        local list = {}
        for n in pairs(all) do list[#list + 1] = n end
        table.sort(list)
        enter("peer", T(_("Tap Sync on %1 too."), #list > 0 and table.concat(list, _(" or ")) or _("the other e-reader")))
        t0 = os.time()
        tick = function()
            if state.finished then return end
            -- KOSyncthing+ may stop a Syncthing its own Quick Sync started:
            -- started again, once.
            if not isRunning() then
                if state.restarted then return finish(false, _("Syncthing stopped.")) end
                state.restarted = true
                try(function() api().control.start(function() end) end)
                state.started_here = true
            end
            peers = Chain.connected(folders, names)
            if peers then return stepSwap() end
            -- With the cloud as well, no device nearby is fine.
            if use_cloud and os.time() - t0 > Chain.CLOUD_PEER_WAIT then return stepCloud() end
            if os.time() - t0 > Chain.CONNECT_WAIT then
                return finish(false, _("The other e-reader did not show up. Start Sync on it while this one is waiting, with both on the same Wi-Fi."))
            end
            UIManager:scheduleIn(Chain.TICK, tick)
        end
        UIManager:scheduleIn(Chain.TICK, tick)
    end

    local function stepSave()
        enter("save")
        local s = syncery(ui)
        if s then
            local ok, err = pcall(function() s:syncNow() end)
            if not ok then logger.warn("Aleph: Syncery sync now failed:", err) end
        end
        UIManager:scheduleIn(1.5, use_st and stepPeer or stepCloud)
    end

    local function stepStart()
        enter("start")
        if not isRunning() then
            state.started_here = true
            local ok, err = pcall(function() api().control.start(function() end) end)
            if not ok then return finish(false, T(_("Could not start Syncthing: %1"), tostring(err))) end
        end
        t0 = os.time()
        tick = function()
            if state.finished then return end
            if call("system/status") then return stepSave() end
            if os.time() - t0 > 90 then return finish(false, _("Syncthing did not start. Open KOSyncthing+ to see why.")) end
            UIManager:scheduleIn(Chain.TICK, tick)
        end
        UIManager:scheduleIn(1, tick)
    end

    panel = Chain.panel(steps, state)
    panel.on_close = function()
        if not state.finished then
            state.cancelled = true
            finish(false, _("Stopped."))
        end
    end
    panel:show()

    local NetworkMgr = require("ui/network/manager")
    local first = use_st and stepStart or stepSave
    if NetworkMgr:isConnected() then first()
    elseif use_cloud then
        NetworkMgr:runWhenOnline(function() if not state.finished then first() end end)
    else
        NetworkMgr:runWhenConnected(function() if not state.finished then first() end end)
    end
    return panel, state
end

-- The panel: the steps with a mark each, and Stop / Close.
function Chain.panel(steps, state)
    local _ = require("aleph_gettext")
    local Geom = require("ui/geometry")
    local BoardMetrics = require("aleph_board_metrics")
    local BoardUI = require("aleph_board_ui")
    local MenuUI = require("aleph_menu_ui")
    local Panel = require("aleph_panel")
    local INK, px, floor = BoardMetrics.INK, BoardMetrics.px, math.floor
    return Panel:new{
        dismiss = false,
        build = function(p, sw, sh)
            local w = math.min(px(480), sw - 2 * px(16))
            local pad = px(18)
            local iw = w - 2 * pad
            local items = { BoardUI.text(_("Sync e-readers"), { s = 19, b = true, w = iw }), BoardUI.space(nil, px(12)) }
            for i, s in ipairs(steps) do
                local mark, col, bold
                if state.failed and i == state.at then mark, col, bold = "x", INK.black, true
                elseif i < state.at then mark, col = "check", INK.g3
                elseif i == state.at then mark, col, bold = "clock", INK.black, true
                else mark, col = nil, INK.g5 end
                local icon = mark and BoardUI.icon(mark, px(20), { sw = 2.5 }) or BoardUI.space(px(20), px(20))
                local line = { icon, BoardUI.space(px(10), 1), BoardUI.text(s.label, { s = 15, b = bold, col = col, w = iw - px(30) }) }
                items[#items + 1] = BoardUI.hstack({ w = iw, h = px(30) }, line)
                if i == state.at and state.note and not state.failed then
                    items[#items + 1] = BoardUI.text(state.note, { s = 13, col = INK.g3, w = iw - px(30), lines = 3, data = true })
                    items[#items + 1] = BoardUI.space(nil, px(4))
                end
            end
            if state.failed then
                items[#items + 1] = BoardUI.space(nil, px(8))
                items[#items + 1] = BoardUI.text(state.failed, { s = 14, w = iw, lines = 5 })
            elseif state.at > #steps and state.note then
                items[#items + 1] = BoardUI.space(nil, px(8))
                items[#items + 1] = BoardUI.text(state.note, { s = 15, b = true, w = iw, lines = 3, data = true })
            end
            items[#items + 1] = BoardUI.space(nil, px(16))
            local busy = not state.finished
            items[#items + 1] = MenuUI.pill(busy and _("Stop") or _("Close"),
                { kind = busy and "outline" or "dark", w = iw, h = 48, s = 16, action = { kind = "close" } })
            local content = BoardUI.vstack({ w = w, pad = pad }, items)
            local border = math.max(1, px(1.5))
            local ph = content:getSize().h + 2 * border
            local widget = BoardUI.box({ w = w, h = ph, radius = px(16), bg = INK.white, border = border, border_col = INK.g6 }, content)
            local x, y = floor((sw - w) / 2), math.max(px(8), floor((sh - ph) / 2))
            p.panel_rect = Geom:new{ x = x, y = y, w = w, h = ph }
            return BoardUI.overlay(sw, sh, { { widget = widget, x = x, y = y } })
        end,
        on_action = function(p, action)
            if action.kind == "close" then p:close() end
        end,
    }
end

return Chain
