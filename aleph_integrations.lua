-- Silverfish integration for Aleph.
local UIManager = require("ui/uimanager")
local logger = require("logger")
local _ = require("gettext")

local Plugins = require("aleph_plugins")

local Integrations = {}

local function inform(message)
    UIManager:show(require("ui/widget/infomessage"):new{ text = message })
end

local function silverfishModule()
    -- Silverfish registers its live instance on KOReader's Screensaver.
    -- Its own micro-module reads that instance for both drawing and tapping.
    if not require("ui/screensaver").traca_instancia then return nil end
    local ok, card = pcall(require, "traca_bookshelf")
    if ok and type(card) == "table" and type(card.modulo) == "function" then return card.modulo() end
    if not ok then logger.warn("Aleph: Silverfish widget unavailable:", card) end
end

function Integrations.silverfishCard(w, h)
    local card = silverfishModule()
    if card then
        return require("aleph_silverfish"):new{
            width = w, height = h, module = card,
            traca = require("ui/screensaver").traca_instancia,
        }
    end
end

function Integrations.openSilverfish()
    local card = silverfishModule()
    if card then
        return card.on_tap()
    end
    inform(_("Install or enable Silverfish 1.1.0 or newer in KOReader to use this widget."))
end

-- KOSyncthing+ integration. KOReader registers each enabled plugin on the
-- file browser under the plugin's name, so the plugin is there only when it is
-- installed and enabled.
-- KOSyncthing+ (kosyncthing_plus.koplugin): its instance, found the way
-- aleph_plugins.lua finds plugins; else its public API
-- (_G.KOSyncthingPlusAPI, published when it loads); else, when its code is
-- loaded, its gesture actions (toggle_syncthing_server, syncthing_quick_sync)
-- through KOReader's Dispatcher. The methods used are the ones its source has:
-- isRunning, runManualStart, onSyncthingQuickSync, onToggleSyncthingServer.
function Integrations.syncthing(ui)
    local st = Plugins.find("kosyncthing_plus", ui, function(p)
        return type(p.isRunning) == "function" and (type(p.runManualStart) == "function" or type(p.onToggleSyncthingServer) == "function")
    end)
    if st then return st end
    local api = rawget(_G, "KOSyncthingPlusAPI")
    if type(api) == "table" and type(api.control) == "table" and type(api.control.start) == "function" then
        return {
            isRunning = function()
                local ok, running = pcall(function() return api.status and api.status.isRunning() end)
                return ok and running or false
            end,
            runManualStart = function(_self, callback) return api.control.start(callback) end,
            onSyncthingQuickSync = type(api.control.quickSync) == "function" and function() return api.control.quickSync() end or nil,
        }
    end
    if Plugins.loaded("st_api_public") or Plugins.loaded("st_orchestrator") then
        return {
            isRunning = function() return false end,
            runManualStart = function(_self, callback)
                Plugins.dispatch(ui, "toggle_syncthing_server")
                if callback then callback() end
            end,
            onSyncthingQuickSync = function() Plugins.dispatch(ui, "syncthing_quick_sync") end,
            dispatch_only = true,
        }
    end
end

-- Whether a syncthing process exists, by looking at the system's process list.
-- KOSyncthing+'s own isRunning can answer "no" while Syncthing is up (it asks
-- about its own bookkeeping), so the processes are the last word. Kept for a
-- few seconds, so drawing the dashboard does not scan every time.
local scan = { at = 0, found = false }
local function syncthingProcess()
    local now = os.time()
    if now - scan.at < 3 then return scan.found end
    local found = false
    pcall(function()
        local lfs = require("libs/libkoreader-lfs")
        for entry in lfs.dir("/proc") do
            if entry:match("^%d+$") then
                local f = io.open("/proc/" .. entry .. "/comm", "r")
                if f then
                    local name = f:read("*l") or ""
                    f:close()
                    if name:lower():find("syncthing", 1, true) then found = true; break end
                end
            end
        end
    end)
    scan.at, scan.found = now, found
    return found
end

function Integrations.syncthingRunning()
    local st = Integrations.syncthing()
    if not st then return false end
    local ok, running = pcall(st.isRunning, st)
    if ok and running then return true end
    return syncthingProcess()
end

-- After Start Syncthing it takes a moment (Wi-Fi, the process) before it is
-- up: look again a few times so the button lights without waiting for the
-- next redraw. `redraw` is called each time.
-- `redraw` is only called when Syncthing's state has changed since the last
-- look, so the page is not redrawn (and the e-ink screen not flashed) for nothing.
function Integrations.watchSyncthing(redraw)
    scan.at = 0
    local last = Integrations.syncthingRunning()
    for _i, seconds in ipairs({ 3, 6, 10, 15, 25, 40 }) do
        UIManager:scheduleIn(seconds, function()
            scan.at = 0
            local now = Integrations.syncthingRunning()
            if now ~= last then
                last = now
                redraw()
            end
        end)
    end
end

-- KOSyncthing+ > Start Syncthing. KOSyncthing+ has a call that only starts
-- (runManualStart: asks to download the binary on first use, waits for Wi-Fi,
-- starts the daemon and reports "Syncthing started" or what went wrong, all
-- by itself). Its toggle, which the menu entry uses, stops Syncthing when it
-- thinks it is running, so it is never used here: a button called Start must
-- never stop it. When the plugin says Syncthing is already running, nothing is
-- done.
local function note(text)
    local ok = pcall(function() require("aleph_toast").show(text) end)
    if not ok then inform(text) end
end

function Integrations.startSyncthing(done)
    local st = Integrations.syncthing()
    if not st then return false end
    local function finished()
        if done then pcall(done) end
    end
    -- Running (by KOSyncthing+'s word or by the process list): sync now.
    if Integrations.syncthingRunning() then
        if type(st.onSyncthingQuickSync) == "function" then
            local ok, err = pcall(st.onSyncthingQuickSync, st)
            if ok then
                note(_("Syncing now…"))
            else
                logger.warn("Aleph: Syncthing quick sync failed:", err)
                note(_("Syncthing is running."))
            end
        else
            note(_("Syncthing is running."))
        end
        finished()
        return true
    end
    -- KOSyncthing+ ignores a second start while the first is under way.
    if st._starting or st._stopping then
        note(st._starting and _("Syncthing is already starting.") or _("Syncthing is stopping."))
        return true
    end
    note(_("Starting Syncthing…"))
    local ok, err
    if type(st.runManualStart) == "function" then
        ok, err = pcall(st.runManualStart, st, finished)
    else
        local api = rawget(_G, "KOSyncthingPlusAPI")
        if type(api) == "table" and type(api.control) == "table" and type(api.control.start) == "function" then
            ok, err = pcall(api.control.start, finished)
        else
            -- Not running (checked above), so the toggle starts it.
            ok, err = pcall(st.onToggleSyncthingServer, st, finished)
        end
    end
    if not ok then
        logger.warn("Aleph: Syncthing start failed:", err)
        inform(_("Could not start Syncthing.") .. "\n" .. tostring(err))
    end
    return true
end

-- Reading insights (readinginsights.koplugin). A tap on a Statistics widget
-- opens the matching view of it, the same ones its Tools menu opens:
--   streak    Reading calendar   (onShowReadingStreakPopup)
--   habits    Reading habits     (onShowReadingHeatmapPopup)
--   insights  Reading insights   (onShowReadingInsightsPopup)
--   records   Records            (onShowReadingRecordsPopup)
-- Found the way Reading log finds plugins (its D.hasPlugin): on the file
-- browser's or the reader's instance, by name. When that fails its gesture
-- action is tried through KOReader's Dispatcher (Reading log's D.dispatch),
-- with the file browser or reader listening for the length of the call (the
-- board is the window on top, and KOReader sends an action's event to the
-- top window first). Without Reading insights, KOReader's own Reading
-- statistics windows open instead: the calendar, or Reading progress.
local INSIGHTS = {
    streak = { "onShowReadingStreakPopup", "reading_streak_popup", "calendar" },
    habits = { "onShowReadingHeatmapPopup", "reading_heatmap_popup", "calendar" },
    insights = { "onShowReadingInsightsPopup", "reading_insights_popup", "progress" },
    records = { "onShowReadingRecordsPopup", "reading_records_popup", "progress" },
    shelf = { "onShowReadingShelfPopup", "reading_shelf_popup", "progress" },
    achievements = { "onShowReadingAchievements", "reading_achievements_popup", "progress" },
}

local hosts = Plugins.hosts
local dispatch = Plugins.dispatch
local function pluginNamed(ui, name)
    return Plugins.find(name, ui)
end

function Integrations.hasInsights(ui)
    return pluginNamed(ui, "readinginsights") ~= nil
end

-- KOReader's Reading statistics: its calendar, or Reading progress.
local function openStatistics(ui, which)
    local stats = pluginNamed(ui, "statistics")
    local method = which == "calendar" and "onShowCalendarView" or "onShowReaderProgress"
    if stats and type(stats[method]) == "function" then
        local ok, err = pcall(stats[method], stats)
        if ok then return true end
        logger.warn("Aleph: statistics view failed:", which, err)
    end
    return dispatch(ui, which == "calendar" and "stats_calendar_view" or "reading_progress") and stats ~= nil
end

function Integrations.openInsights(ui, view)
    local entry = INSIGHTS[view]
    if not entry then return end
    local plugin = pluginNamed(ui, "readinginsights")
    if plugin and type(plugin[entry[1]]) == "function" then
        local ok, err = pcall(plugin[entry[1]], plugin)
        if ok then return true end
        logger.warn("Aleph: Reading insights view failed:", view, err)
    elseif plugin then
        -- Found, but under other method names: its gesture action.
        if dispatch(ui, entry[2]) then return true end
    end
    -- In crash.log, for a report: what was looked for and where.
    logger.info("Aleph: Reading insights", plugin and "found" or "not found", "for", view, "- hosts:", #hosts(ui))
    if openStatistics(ui, entry[3]) then return true end
    inform(_("Turn on Reading insights or KOReader's Reading statistics plugin (Plugin management) to open this from here."))
    return true
end

return Integrations
