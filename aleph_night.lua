-- Aleph modification, 2026-11-14: a night profile.
--[[--
When KOReader's night mode is turned on, the front light goes to the night
brightness and warmth chosen in Settings > Home > Night profile, and the
text of books KOReader lays out itself (EPUB and the like) is drawn a
little bolder, so light letters on black stay crisp. When night mode is
turned off, the light goes back to what it was before, and the text to its
own weight.

After the "Night Profile" user patch (2-night-profile.lua), made into a
setting: the same switch-over, with its values chosen here. While that
patch is installed (koreader/patches), Aleph's profile stays off, so the
two never act at once.

  settings (Aleph's settings, key "night")
    on          false                       the profile
    light       true                        change the front light
    brightness  15                          night brightness, % of the range
    warmth      70                          night warmth, 0-100 (devices with
                                            warm light)
    remember    true                        brightness or warmth changed while
                                            night mode is on become the night
                                            values
    boost       1                           bolder text: 0 (off), 0.5, 1, 1.5
    auto        false                       night mode on and off by itself
    from, to    21:00, 07:00 (minutes)      when night mode is on
  state (KOReader setting "aleph_night_state")
    day         { intensity, warmth }       the light before night mode

A light that is off stays off: the profile never turns it on.
]]

local Night = {}

Night.DEFAULTS = { on = false, light = true, brightness = 15, warmth = 70, remember = true, boost = 1,
    auto = false, from = 21 * 60, to = 7 * 60 }
Night.TIME_STEP = 15
Night.BOOSTS = { 0, 0.5, 1, 1.5 }
Night.STEP = 5
local STATE_KEY = "aleph_night_state"

local function prefs()
    local ok, Prefs = pcall(require, "aleph_prefs")
    return ok and Prefs or nil
end

local function isNight()
    return G_reader_settings and G_reader_settings:isTrue("night_mode") or false
end
Night.isNight = isNight

-- The user patch this replaces, when installed.
function Night.patchInstalled()
    local found = false
    pcall(function()
        local lfs = require("libs/libkoreader-lfs")
        local dir = require("datastorage"):getDataDir() .. "/patches"
        if lfs.attributes(dir, "mode") ~= "directory" then return end
        for name in lfs.dir(dir) do
            if name:lower():find("night%-profile") and name:match("%.lua$") then found = true; break end
        end
    end)
    return found
end

-- The settings over the defaults (the patch's remembered night light as the
-- starting values, when there is one and nothing was chosen here yet).
function Night.config()
    local P = prefs()
    local saved = P and P.get().night
    local c = {}
    for k, v in pairs(Night.DEFAULTS) do c[k] = v end
    if type(saved) == "table" then
        for k in pairs(Night.DEFAULTS) do
            if saved[k] ~= nil then c[k] = saved[k] end
        end
    end
    c.brightness = math.max(Night.STEP, math.min(100, tonumber(c.brightness) or Night.DEFAULTS.brightness))
    c.warmth = math.max(0, math.min(100, tonumber(c.warmth) or Night.DEFAULTS.warmth))
    local boost_ok = false
    for _i, b in ipairs(Night.BOOSTS) do if b == c.boost then boost_ok = true end end
    if not boost_ok then c.boost = Night.DEFAULTS.boost end
    c.from = math.floor(tonumber(c.from) or Night.DEFAULTS.from) % 1440
    c.to = math.floor(tonumber(c.to) or Night.DEFAULTS.to) % 1440
    return c
end

function Night.save(c)
    local P = prefs()
    if not P then return end
    local out = {}
    for k in pairs(Night.DEFAULTS) do out[k] = c[k] end
    P.set("night", out)
end

-- Whether the profile acts now: on, and the user patch not installed.
function Night.active(c)
    c = c or Night.config()
    return c.on == true and not Night.patchInstalled()
end

-- ------------------------------------------------------------ the light
local function powerd()
    local ok, Device = pcall(require, "device")
    if not ok or not Device:hasFrontlight() then return nil, Device end
    return Device:getPowerDevice(), Device
end

local function hasWarmth()
    local ok, Device = pcall(require, "device")
    return ok and Device.hasNaturalLight and Device:hasNaturalLight() or false
end
Night.hasWarmth = hasWarmth

function Night.readLight()
    local pd, Device = powerd()
    if not pd then return nil end
    local light = {}
    pcall(function() light.intensity = pd:frontlightIntensity() end)
    if Device:hasNaturalLight() then pcall(function() light.warmth = pd:frontlightWarmth() end) end
    return light
end

local function writeLight(light)
    local pd, Device = powerd()
    if not (pd and light) then return end
    if light.intensity then pcall(function() pd:setIntensity(light.intensity) end) end
    if light.warmth and Device:hasNaturalLight() then pcall(function() pd:setWarmth(light.warmth) end) end
    pcall(function()
        local Event = require("ui/event")
        require("ui/uimanager"):broadcastEvent(Event:new("FrontlightStateChanged"))
    end)
end

local function lightOn(pd)
    local ok, on = pcall(function() return pd:isFrontlightOn() end)
    return not (ok and on == false)
end

-- Brightness: % of the device's range <-> its own steps.
function Night.toIntensity(percent, fl_min, fl_max)
    fl_min, fl_max = fl_min or 0, fl_max or 24
    local target = math.floor(fl_min + (fl_max - fl_min) * percent / 100 + 0.5)
    return math.max(fl_min + 1, math.min(fl_max, target))
end
function Night.toPercent(intensity, fl_min, fl_max)
    fl_min, fl_max = fl_min or 0, fl_max or 24
    if fl_max <= fl_min then return Night.DEFAULTS.brightness end
    local p = (intensity - fl_min) * 100 / (fl_max - fl_min)
    return math.max(Night.STEP, math.min(100, math.floor(p / Night.STEP + 0.5) * Night.STEP))
end

function Night.nightLight(c)
    local pd = powerd()
    if not pd then return nil end
    return { intensity = Night.toIntensity(c.brightness, pd.fl_min, pd.fl_max), warmth = hasWarmth() and c.warmth or nil }
end

local function state()
    local s = G_reader_settings:readSetting(STATE_KEY)
    return type(s) == "table" and s or {}
end

-- Night mode turned on (going_night) or off: the light switched over.
function Night.applyLight(going_night, c)
    c = c or Night.config()
    if not c.light then return end
    local pd = powerd()
    if not pd or not lightOn(pd) then return end
    local s = state()
    if going_night then
        s.day = Night.readLight()
        writeLight(Night.nightLight(c))
    else
        if c.remember then
            -- What was set during the night is the night light next time.
            local now = Night.readLight()
            if now and now.intensity then
                c.brightness = Night.toPercent(now.intensity, pd.fl_min, pd.fl_max)
                if now.warmth and hasWarmth() then c.warmth = math.floor(now.warmth + 0.5) end
                Night.save(c)
            end
        end
        if s.day then writeLight(s.day) end
        s.day = nil
    end
    G_reader_settings:saveSetting(STATE_KEY, s)
end

-- A night value changed in Settings while night mode is on: shown at once.
function Night.preview(c)
    c = c or Night.config()
    if not (Night.active(c) and isNight() and c.light) then return end
    local pd = powerd()
    if not pd or not lightOn(pd) then return end
    writeLight(Night.nightLight(c))
end

-- ------------------------------------------------------------ the text
local function documentBoost()
    if not isNight() then return 0 end
    local c = Night.config()
    if not Night.active(c) then return 0 end
    return tonumber(c.boost) or 0
end
Night.documentBoost = documentBoost

-- The open book drawn again with the weight it should have now.
function Night.applyText()
    pcall(function()
        local ReaderUI = require("apps/reader/readerui")
        local ui = ReaderUI.instance
        if not (ui and ui.document and ui.rolling) then return end
        local doc = ui.document
        local base = rawget(doc, "_aleph_night_base_weight")
        if base == nil and doc.configurable then base = doc.configurable.font_base_weight end
        if type(base) ~= "number" then return end
        doc:setFontBaseWeight(base)
        ui:handleEvent(require("ui/event"):new("UpdatePos"))
    end)
end

-- ------------------------------------------------------------ switching
local last_night

local function changed()
    local now = isNight()
    if now == last_night then return end
    last_night = now
    local c = Night.config()
    if not Night.active(c) then return end
    Night.applyLight(now, c)
    Night.applyText()
end
Night.changed = changed

-- Installed once, as Aleph loads. Every way of turning night mode on or off
-- (menu, gesture, top bar, Home) goes through Screen:toggleNightMode; the
-- setting is saved right after, so it is looked at a moment later.
function Night.install()
    if Night._installed then return end
    Night._installed = true
    last_night = isNight()
    -- Night mode by the clock: looked at once KOReader is up.
    pcall(function() require("ui/uimanager"):scheduleIn(3, function() Night.checkSchedule() end) end)
    local ok_dev, Device = pcall(require, "device")
    local Screen = ok_dev and Device.screen
    if Screen and type(Screen.toggleNightMode) == "function" then
        local toggle = Screen.toggleNightMode
        Screen.toggleNightMode = function(self, ...)
            local result = toggle(self, ...)
            pcall(function() require("ui/uimanager"):scheduleIn(0.3, changed) end)
            return result
        end
    end
    -- Bolder text while night mode is on: the weight chosen is kept, and the
    -- boost added on top of it.
    local ok_cre, CreDocument = pcall(require, "document/credocument")
    if ok_cre and type(CreDocument) == "table" and type(CreDocument.setFontBaseWeight) == "function" then
        local set = CreDocument.setFontBaseWeight
        CreDocument.setFontBaseWeight = function(self, weight, ...)
            rawset(self, "_aleph_night_base_weight", weight)
            local boost = type(weight) == "number" and documentBoost() or 0
            if boost ~= 0 then weight = weight + boost end
            return set(self, weight, ...)
        end
    end
end

-- The profile turned on or off in Settings while night mode is on: the
-- light and text switched over at once.
function Night.toggled(now_on)
    if not isNight() then return end
    local c = Night.config()
    if Night.patchInstalled() then return end
    if now_on then
        Night.applyLight(true, c)
    else
        -- Back to the day light, without keeping the night one (the switch
        -- was just turned off: nothing more is saved).
        c.remember = false
        Night.applyLight(false, c)
    end
    Night.applyText()
end

-- "On · 15% · warmth 70 · bolder text" for the settings row.
function Night.summary()
    local _ = require("gettext")
    local T = require("ffi/util").template
    local c = Night.config()
    local auto = c.auto and c.from ~= c.to and T(_("night mode %1–%2"), Night.timeLabel(c.from), Night.timeLabel(c.to)) or nil
    if Night.patchInstalled() then return auto or _("Off while the night-profile patch is installed") end
    if not c.on then return auto or _("Off") end
    local parts = { _("On") }
    if auto then parts[#parts + 1] = auto end
    if c.light then
        parts[#parts + 1] = T(_("light %1%"), c.brightness)
        if hasWarmth() then parts[#parts + 1] = T(_("warmth %1"), c.warmth) end
    end
    if c.boost ~= 0 then parts[#parts + 1] = _("bolder text") end
    return table.concat(parts, " · ")
end

-- ------------------------------------------------------------ by the clock
-- Night mode on from `from` to `to` (minutes after midnight; a period that
-- passes midnight is the usual one). Night mode is set as each period
-- starts (at the minute, on waking from sleep, when KOReader starts); in
-- between, night mode switched by hand stays as it is until the next one.

-- A time today (or `days` later) at `minutes` after midnight.
local function at(now, minutes, days)
    local t = os.date("*t", now)
    return os.time{ year = t.year, month = t.month, day = t.day + (days or 0),
        hour = math.floor(minutes / 60), min = minutes % 60, sec = 0, isdst = nil }
end

-- Whether `now` is in the night period.
function Night.inPeriod(c, now)
    local t = os.date("*t", now)
    local mins = t.hour * 60 + t.min
    if c.from == c.to then return false end
    if c.from < c.to then return mins >= c.from and mins < c.to end
    return mins >= c.from or mins < c.to
end

-- The period `now` is in, named by when it started ("n@<time>" or
-- "d@<time>"), and when the next one starts.
function Night.period(c, now)
    local last, next_at
    for days = -1, 1 do
        for _i, edge in ipairs({ c.from, c.to }) do
            local ts = at(now, edge, days)
            if ts <= now and (not last or ts > last) then last = ts end
            if ts > now and (not next_at or ts < next_at) then next_at = ts end
        end
    end
    local night = Night.inPeriod(c, now)
    return (night and "n@" or "d@") .. tostring(last), night, next_at
end

local timer

-- Night mode set for the period now, if this period has not set it yet.
function Night.checkSchedule(now)
    now = now or os.time()
    local c = Night.config()
    local UIManager = require("ui/uimanager")
    if timer then UIManager:unschedule(timer); timer = nil end
    if not c.auto or c.from == c.to then return end
    local key, night, next_at = Night.period(c, now)
    local s = state()
    if s.period ~= key then
        s.period = key
        G_reader_settings:saveSetting(STATE_KEY, s)
        if night ~= isNight() then
            local Event = require("ui/event")
            UIManager:broadcastEvent(Event:new("SetNightMode", night))
        end
    end
    if next_at then
        timer = function() timer = nil; Night.checkSchedule() end
        UIManager:scheduleIn(math.max(1, next_at - os.time() + 1), timer)
    end
end

-- The schedule changed in Settings: the period now is set again.
function Night.scheduleChanged()
    local s = state()
    s.period = nil
    G_reader_settings:saveSetting(STATE_KEY, s)
    Night.checkSchedule()
end

-- "21:00" (or "9:00 PM" with KOReader's 12-hour clock).
function Night.timeLabel(minutes)
    local ts = at(os.time(), minutes, 0)
    local ok, text = pcall(function()
        return require("datetime").secondsToHour(ts, G_reader_settings:isTrue("twelve_hour_clock"))
    end)
    if ok and text then return text end
    return string.format("%02d:%02d", math.floor(minutes / 60), minutes % 60)
end

-- For tests.
function Night._setLast(v) last_night = v end

return Night
