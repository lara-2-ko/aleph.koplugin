-- Aleph modification, 2026-11-16: the weather on Home.
--[[--
A Device widget (Customize Home > + Add widget > Device > Weather): the
weather now where you are, today's high and low, and in a wider tile the
next two days.

Kept light, for memory and battery:
  * Nothing of it is loaded until the widget is on Home.
  * It never turns Wi-Fi on. It asks only when Home is drawn with Wi-Fi
    already connected, at most once an hour (after a failure, not again for
    15 minutes); otherwise it shows the last answer, with its time.
  * The asking is done in a background process (aleph_job.lua), so Home
    never waits for the network; the answer is about 1 KB and is kept in
    settings/aleph_weather.lua, so it is there after a restart.
  * No timers: the widget is redrawn when Home is anyway.

The forecast comes from Open-Meteo (open-meteo.com: free, no account, no
key). What is sent is the place's latitude and longitude, rounded to two
decimals (about a kilometre), and the units. The place is found once, by
name, with Open-Meteo's geocoding search, when it is set.

A tap on the widget: Update now, the place, °C or °F.

Settings: aleph.weather = { place, lat, lon, units = "c" | "f" }.
]]

local UIManager = require("ui/uimanager")
local T = require("ffi/util").template
local _ = require("aleph_gettext")

local Weather = {}

Weather.MAX_AGE = 3600      -- an answer older than this is asked again
Weather.RETRY = 900         -- after a failure, not before this
Weather.OLD = 6 * 3600      -- older than this, it is shown as old
Weather.TIMEOUT = 30        -- the background ask is stopped after this

local cache            -- the last answer (read from its file once)
local busy = false     -- a background ask is running
local last_try = 0

-- ------------------------------------------------------------ settings
function Weather.config()
    local c
    pcall(function() c = require("aleph_prefs").get().weather end)
    c = type(c) == "table" and c or {}
    return {
        place = type(c.place) == "string" and c.place or nil,
        lat = tonumber(c.lat), lon = tonumber(c.lon),
        units = c.units == "f" and "f" or "c",
    }
end

local function saveConfig(c)
    require("aleph_prefs").set("weather", { place = c.place, lat = c.lat, lon = c.lon, units = c.units })
end

local function cacheFile()
    return require("datastorage"):getSettingsDir() .. "/aleph_weather.lua"
end

local function readCache()
    if cache == nil then
        local ok, data = pcall(function() return require("aleph_file").read(cacheFile()) end)
        cache = ok and type(data) == "table" and data or false
    end
    return cache or nil
end

-- The answer for the place and units set now (an answer for another place
-- is not shown).
local function currentAnswer(c)
    local a = readCache()
    if not a or not c.lat then return nil end
    if math.abs((tonumber(a.lat) or 999) - c.lat) > 0.01 or math.abs((tonumber(a.lon) or 999) - c.lon) > 0.01 or a.units ~= c.units then
        return nil
    end
    return a
end

-- --------------------------------------------------------- the weather
-- WMO weather codes, as Open-Meteo gives them: words and an icon.
local CODES = {
    [0] = { function() return _.pgettext("Weather", "Clear") end, "sun", "moon" },
    [1] = { function() return _.pgettext("Weather", "Mainly clear") end, "sun", "moon" },
    [2] = { function() return _.pgettext("Weather", "Partly cloudy") end, "cloud-sun", "cloud-moon" },
    [3] = { function() return _.pgettext("Weather", "Overcast") end, "cloud" },
    [45] = { function() return _.pgettext("Weather", "Fog") end, "cloud-fog" },
    [48] = { function() return _.pgettext("Weather", "Fog") end, "cloud-fog" },
    [51] = { function() return _.pgettext("Weather", "Light drizzle") end, "cloud-drizzle" },
    [53] = { function() return _.pgettext("Weather", "Drizzle") end, "cloud-drizzle" },
    [55] = { function() return _.pgettext("Weather", "Heavy drizzle") end, "cloud-drizzle" },
    [56] = { function() return _.pgettext("Weather", "Freezing drizzle") end, "cloud-drizzle" },
    [57] = { function() return _.pgettext("Weather", "Freezing drizzle") end, "cloud-drizzle" },
    [61] = { function() return _.pgettext("Weather", "Light rain") end, "cloud-rain" },
    [63] = { function() return _.pgettext("Weather", "Rain") end, "cloud-rain" },
    [65] = { function() return _.pgettext("Weather", "Heavy rain") end, "cloud-rain" },
    [66] = { function() return _.pgettext("Weather", "Freezing rain") end, "cloud-rain" },
    [67] = { function() return _.pgettext("Weather", "Freezing rain") end, "cloud-rain" },
    [71] = { function() return _.pgettext("Weather", "Light snow") end, "cloud-snow" },
    [73] = { function() return _.pgettext("Weather", "Snow") end, "cloud-snow" },
    [75] = { function() return _.pgettext("Weather", "Heavy snow") end, "cloud-snow" },
    [77] = { function() return _.pgettext("Weather", "Snow grains") end, "cloud-snow" },
    [80] = { function() return _.pgettext("Weather", "Showers") end, "cloud-rain" },
    [81] = { function() return _.pgettext("Weather", "Showers") end, "cloud-rain" },
    [82] = { function() return _.pgettext("Weather", "Heavy showers") end, "cloud-rain" },
    [85] = { function() return _.pgettext("Weather", "Snow showers") end, "cloud-snow" },
    [86] = { function() return _.pgettext("Weather", "Snow showers") end, "cloud-snow" },
    [95] = { function() return _.pgettext("Weather", "Thunderstorm") end, "cloud-lightning" },
    [96] = { function() return _.pgettext("Weather", "Thunderstorm, hail") end, "cloud-lightning" },
    [99] = { function() return _.pgettext("Weather", "Thunderstorm, hail") end, "cloud-lightning" },
}

function Weather.describe(code, is_day)
    local c = CODES[tonumber(code) or -1]
    if not c then return "", "cloud" end
    local glyph = (is_day == false and c[3]) or c[2]
    return c[1](), glyph
end

local function round(x) return x and math.floor(x + 0.5) or nil end

function Weather.degrees(x)
    if x == nil then return "–" end
    return tostring(round(x)) .. "°"
end

-- ------------------------------------------------------------ asking
local function urlencode(s)
    return (tostring(s):gsub("[^%w%-_%.~]", function(ch) return string.format("%%%02X", ch:byte()) end))
end

-- In the background process: one GET, its body or nil.
local function get(url)
    local ltn12 = require("ltn12")
    local socketutil = require("socketutil")
    local body = {}
    socketutil:set_timeout(10, 20)
    local ok, code = pcall(function()
        local https = require("ssl.https")
        local _r, status = https.request{
            url = url, method = "GET", sink = ltn12.sink.table(body),
            headers = { ["User-Agent"] = "Aleph-KOReader (e-reader home screen; weather)", ["Accept"] = "application/json" },
        }
        return status
    end)
    socketutil:reset_timeout()
    if ok and code == 200 then return table.concat(body) end
    return nil
end

function Weather.forecastURL(c)
    return string.format("https://api.open-meteo.com/v1/forecast?latitude=%.2f&longitude=%.2f"
        .. "&current=temperature_2m,weather_code,is_day&daily=weather_code,temperature_2m_max,temperature_2m_min"
        .. "&timezone=auto&forecast_days=3%s", c.lat, c.lon, c.units == "f" and "&temperature_unit=fahrenheit" or "")
end

-- The part of Open-Meteo's answer the widget shows.
function Weather.parse(body, c, now)
    local ok, data = pcall(function() return require("json").decode(body) end)
    if not ok or type(data) ~= "table" or type(data.current) ~= "table" then return nil end
    local cur, daily = data.current, type(data.daily) == "table" and data.daily or {}
    local days = {}
    for i = 1, 3 do
        local date = daily.time and daily.time[i]
        if date then
            days[i] = {
                date = date,
                code = daily.weather_code and daily.weather_code[i],
                hi = daily.temperature_2m_max and daily.temperature_2m_max[i],
                lo = daily.temperature_2m_min and daily.temperature_2m_min[i],
            }
        end
    end
    return {
        lat = c.lat, lon = c.lon, units = c.units, at = now or os.time(),
        temp = tonumber(cur.temperature_2m), code = tonumber(cur.weather_code), is_day = cur.is_day ~= 0,
        days = days,
    }
end

local function online()
    local ok, on = pcall(function() return require("ui/network/manager"):isConnected() end)
    return ok and on and true or false
end

local function refreshHome(host)
    if host and not host.closed and host.mode == "home" and host.updateItems then
        pcall(host.updateItems, host)
    end
end

-- Asks Open-Meteo in the background; `host` (Home) is redrawn with the
-- answer. False when nothing was started.
function Weather.fetch(host, force)
    local c = Weather.config()
    if busy or not c.lat then return false end
    if not force and os.time() - last_try < Weather.RETRY then return false end
    if not online() then return false end
    local Job = require("aleph_job")
    if not Job.available() then return false end
    busy, last_try = true, os.time()
    local File = require("aleph_file")
    local out = cacheFile() .. ".new"
    os.remove(out)
    local url = Weather.forecastURL(c)
    local pid = Job.start(function()
        local body = get(url)
        local answer = body and Weather.parse(body, c, os.time())
        if answer then File.write(out, answer) end
    end, { optional = true, name = "weather" })
    if not pid then busy = false; return false end
    Job.watch(pid, { every = 0.5, timeout = Weather.TIMEOUT, on_done = function()
        busy = false
        local answer = File.read(out)
        os.remove(out)
        if type(answer) == "table" and answer.temp then
            cache = answer
            pcall(File.write, cacheFile(), answer)
        end
        refreshHome(host)
    end })
    return true
end

-- What the widget draws now, and an ask started when the answer is old.
function Weather.view(host)
    local c = Weather.config()
    if not c.lat then return { setup = true } end
    local a = currentAnswer(c)
    local now = os.time()
    if (not a or now - (tonumber(a.at) or 0) > Weather.MAX_AGE) and host then
        -- After this draw, so Home is on screen first.
        UIManager:nextTick(function() Weather.fetch(host) end)
    end
    if not a then return { place = c.place, none = true, busy = busy, online = online() } end
    local words, glyph = Weather.describe(a.code, a.is_day)
    local today = a.days and a.days[1] or {}
    return {
        place = c.place, temp = a.temp, words = words, glyph = glyph,
        hi = today.hi, lo = today.lo, days = a.days, at = a.at,
        old = now - (tonumber(a.at) or 0) > Weather.OLD,
    }
end

-- What changes the drawing, for the board's picture cache.
function Weather.sig()
    local c = Weather.config()
    local a = currentAnswer(c)
    return table.concat({ tostring(c.place), c.units, tostring(a and a.at), tostring(busy) }, "|")
end

-- --------------------------------------------------------------- tile
function Weather.tile(ctx, w, hh)
    local BoardMetrics = require("aleph_board_metrics")
    local BoardUI = require("aleph_board_ui")
    local BoardColour = require("aleph_board_colour")
    local Dates = require("aleph_dates")
    local INK = BoardMetrics.INK
    local px, lh1 = BoardMetrics.px, BoardMetrics.lh1
    local text, vstack, hstack, flex, space, icon, pick = BoardUI.text, BoardUI.vstack, BoardUI.hstack, BoardUI.flex, BoardUI.space, BoardUI.icon, BoardUI.pick
    local v = Weather.view(ctx.menu)
    local pad = px(12)
    local iw = w - 2 * pad
    local function glyph(name, size) return icon(name, size, BoardColour.icon(ctx, 2.25)) end
    -- The label row, as on the other tiles: a long place steps down a size
    -- or two before it is cut.
    local function head(label, right)
        local rw = right and right:getSize().w or 0
        local room = right and (iw - rw - px(4)) or iw
        local size = 13
        local lab = text(label, { s = size, b = true })
        while lab:getSize().w > room and size > 11 do
            size = size - 1
            lab = text(label, { s = size, b = true })
        end
        if lab:getSize().w > room then lab = text(label, { s = size, b = true, w = math.max(1, room), data = true }) end
        return BoardUI.spread(iw, lab, right, lh1(13))
    end
    local function note(str)
        return text(str, { s = 13, col = INK.g4, w = iw, lines = 3, data = true })
    end
    if v.setup then
        return vstack({ w = w, h = hh, pad = pad }, {
            head(_("Weather"), glyph("map-pin", px(16))),
            space(nil, px(6)),
            note(_("Tap to choose your town.")),
            flex(0),
        })
    end
    local place = v.place or _("Weather")
    if v.none then
        local why = v.busy and _("Updating…") or (v.online and _("Not updated yet.") or _("Connect to Wi-Fi to see the weather."))
        return vstack({ w = w, h = hh, pad = pad }, {
            head(place, glyph("cloud", px(16))),
            space(nil, px(6)),
            note(why),
            flex(0),
        })
    end
    local hilo = T(_("H %1  L %2"), Weather.degrees(v.hi), Weather.degrees(v.lo))
    local foot = v.old and T(_("Updated %1"), os.date("%H:%M", v.at)) or hilo
    local temp = Weather.degrees(v.temp)
    local function bigSize(room, lo, hi)
        local s = math.max(lo, math.min(hi, math.floor(room / 1.36 / BoardMetrics.get().dp)))
        return s
    end
    -- The next two days, for a wide tile.
    local function nextDays()
        local items = {}
        for i = 2, 3 do
            local d = v.days and v.days[i]
            local t = d and Dates.fromISO(d.date)
            if t then
                local _w, g = Weather.describe(d.code, true)
                items[#items + 1] = hstack({ gap = px(6) }, {
                    text(Dates.shortWeekday(t), { s = 12, b = true }),
                    glyph(g, px(16)),
                    text(Weather.degrees(d.hi) .. " / " .. Weather.degrees(d.lo), { s = 12, col = INK.g4 }),
                })
            end
        end
        return #items > 0 and hstack({ gap = px(16) }, items) or nil
    end
    local variants = {}
    if w >= px(250) then
        -- Wide: a large icon beside the temperature, the words and high/low;
        -- the next two days under them when there is room.
        local function wide(with_days)
            return function()
                local days = with_days and nextDays() or nil
                if with_days and not days then error("no days") end
                local body_h = hh - 2 * pad - lh1(13) - px(6) - (days and (days:getSize().h + px(8)) or 0)
                local isz = math.max(px(28), math.min(body_h, px(64)))
                local cw = iw - isz - px(12)
                local s = bigSize(body_h - lh1(13) - lh1(12), 20, 40)
                while s > 20 and text(temp, { s = s, b = true }):getSize().w > cw do s = s - 2 end
                local col = vstack({ w = cw }, {
                    text(temp, { s = s, b = true, w = cw }),
                    text(v.words, { s = 13, w = cw, data = true }),
                    text(foot, { s = 12, col = INK.g4, w = cw, data = true }),
                })
                return vstack({ w = w, h = hh, pad = pad }, {
                    head(place, nil),
                    flex(px(6)),
                    hstack({ w = iw, gap = px(12) }, { glyph(v.glyph, isz), col }),
                    days and flex(px(8)) or false,
                    days or false,
                    flex(0),
                })
            end
        end
        variants[#variants + 1] = wide(true)
        variants[#variants + 1] = wide(false)
    end
    -- Small: the place with the icon, the temperature, the words, high/low.
    local function small(with_words)
        return function()
            local rest = lh1(12) + (with_words and lh1(12) or 0)
            local s = bigSize(hh - 2 * pad - lh1(13) - rest - px(4), 18, 40)
            while s > 18 and text(temp, { s = s, b = true }):getSize().w > iw do s = s - 2 end
            return vstack({ w = w, h = hh, pad = pad }, {
                head(place, glyph(v.glyph, px(18))),
                flex(0),
                text(temp, { s = s, b = true, w = iw }),
                with_words and text(v.words, { s = 12, w = iw, data = true }) or false,
                text(foot, { s = 11, col = INK.g4, w = iw, data = true }),
            })
        end
    end
    variants[#variants + 1] = small(true)
    variants[#variants + 1] = small(false)
    return pick(variants)
end

-- ----------------------------------------------------- the settings
-- Open-Meteo's places for `name`, in the background; done(list) or
-- done(nil) when it could not ask.
function Weather.searchPlaces(name, done)
    if not online() then return done(nil, "offline") end
    local Job = require("aleph_job")
    local File = require("aleph_file")
    local out = cacheFile() .. ".places"
    os.remove(out)
    local lang = (require("aleph_gettext").language() or "en"):match("^(%a+)") or "en"
    local url = "https://geocoding-api.open-meteo.com/v1/search?count=6&format=json&language=" .. lang .. "&name=" .. urlencode(name)
    local pid = Job.available() and Job.start(function()
        local body = get(url)
        local list = {}
        local ok, data = pcall(function() return require("json").decode(body or "") end)
        if ok and type(data) == "table" and type(data.results) == "table" then
            for _i, r in ipairs(data.results) do
                local parts = { r.name }
                if r.admin1 and r.admin1 ~= r.name then parts[#parts + 1] = r.admin1 end
                if r.country then parts[#parts + 1] = r.country end
                list[#list + 1] = { name = r.name, label = table.concat(parts, ", "), lat = tonumber(r.latitude), lon = tonumber(r.longitude) }
            end
        end
        File.write(out, { list = list, ok = body ~= nil })
    end)
    if not pid then return done(nil, "error") end
    Job.watch(pid, { every = 0.4, timeout = 20, on_done = function()
        local got = File.read(out)
        os.remove(out)
        if type(got) ~= "table" or not got.ok then return done(nil, "error") end
        done(got.list or {})
    end })
end

local function toast(str, glyph)
    pcall(function() require("aleph_toast").show(str, { icon = glyph or "info" }) end)
end

function Weather.setPlace(p, host)
    local c = Weather.config()
    c.place, c.lat, c.lon = p.name, p.lat, p.lon
    saveConfig(c)
    last_try = 0
    refreshHome(host)
    Weather.fetch(host, true)
end

local function choosePlace(host, list, sheet_parent)
    local SheetUI = require("aleph_sheet_ui")
    local MenuUI = require("aleph_menu_ui")
    SheetUI.open{
        name = "aleph_weather_places",
        build = function(sheet, sw, sh)
            return SheetUI.sheet(sheet, sw, sh, function(w)
                local iw = MenuUI.rowsIn(w)
                local rows = {}
                for i, p in ipairs(list) do
                    rows[#rows + 1] = MenuUI.row(iw, { icon = "map-pin", label = p.name, sub = p.label, sub_data = true, chevron = true, action = { kind = "pick", i = i } })
                end
                return { SheetUI.titleRow(w, _("Which place?"), nil), MenuUI.group(w, rows) }
            end, { pop_w = 480 })
        end,
        on_action = function(sheet, action)
            if action.kind ~= "pick" then return end
            local p = list[action.i]
            sheet:close()
            if sheet_parent and not sheet_parent.closed then sheet_parent:close() end
            if p then Weather.setPlace(p, host) end
            return true
        end,
    }
end

local function askPlace(host, parent)
    local c = Weather.config()
    require("aleph_input").prompt{
        title = _("Your town"),
        text = c.place or "",
        hint = _("A town or city"),
        ok_label = _("Search"),
        on_ok = function(name)
            name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
            if name == "" then return end
            toast(T(_("Looking for %1…"), name), "map-pin")
            Weather.searchPlaces(name, function(list, why)
                if not list then
                    return toast(why == "offline" and _("Connect to Wi-Fi to find the place.") or _("The place could not be looked up."), "triangle-alert")
                end
                if #list == 0 then return toast(T(_("No place called %1 was found."), name), "triangle-alert") end
                choosePlace(host, list, parent)
            end)
        end,
    }
end

function Weather.openMenu(host)
    local SheetUI = require("aleph_sheet_ui")
    local MenuUI = require("aleph_menu_ui")
    local c = Weather.config()
    if not c.lat then return askPlace(host, nil) end
    SheetUI.open{
        name = "aleph_weather_menu",
        build = function(sheet, sw, sh)
            return SheetUI.sheet(sheet, sw, sh, function(w)
                local cfg = Weather.config()
                local a = currentAnswer(cfg)
                local iw = MenuUI.rowsIn(w)
                local when = a and T(_("Updated %1"), os.date("%H:%M", a.at)) or _("Not updated yet")
                return {
                    SheetUI.titleRow(w, _("Weather"), cfg.place),
                    MenuUI.group(w, {
                        MenuUI.row(iw, { icon = "refresh-cw", label = _("Update now"), sub = when, chevron = true, action = { kind = "update" } }),
                        MenuUI.row(iw, { icon = "map-pin", label = _("Place"), sub = cfg.place or _("Not set"), sub_data = true, chevron = true, action = { kind = "place" } }),
                    }),
                    MenuUI.segmented(w, { "°C", "°F" }, cfg.units == "f" and 2 or 1, function(i) return { kind = "units", value = i == 2 and "f" or "c" } end),
                    SheetUI.note(w, "info", _("From Open-Meteo, only with Wi-Fi already on, at most once an hour. Only the place's position is sent."), { lines = 3 }),
                }
            end, { pop_w = 480 })
        end,
        on_action = function(sheet, action)
            local k = action.kind
            if k == "update" then
                if not online() then
                    toast(_("Connect to Wi-Fi to update the weather."), "wifi")
                elseif Weather.fetch(host, true) then
                    toast(_("Updating…"), "refresh-cw")
                end
                sheet:close()
            elseif k == "place" then
                askPlace(host, sheet)
            elseif k == "units" then
                local cfg = Weather.config()
                if cfg.units ~= action.value then
                    cfg.units = action.value
                    saveConfig(cfg)
                    last_try = 0
                    sheet:refresh()
                    refreshHome(host)
                    Weather.fetch(host, true)
                end
            end
            return true
        end,
    }
end

-- For tests.
function Weather._reset() cache, busy, last_try = nil, false, 0 end
function Weather._setCache(a) cache = a end

return Weather
