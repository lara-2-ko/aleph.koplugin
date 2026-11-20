-- Modified for Aleph, 2026-11-07. Unofficial local-only fork. See NOTICE.
--[[--
The data every dashboard widget reads, assembled once per render.

Server data comes from the cached dashboard body (continue reading, goal,
streak, highlight, counts, shelves, and on newer servers the reading year and
a year ago). Device data comes from KOReader itself: statistics.sqlite3 for
today, the week and the finish forecast, the Vocabulary Builder for the word
of the day, and the power device for the frontlight. Local reads are cached
for a couple of minutes and never block on the network.
]]

local Device = require("device")
local NetworkMgr = require("ui/network/manager")
local datetime = require("datetime")
local util = require("util")
local T = require("ffi/util").template
local _ = require("aleph_gettext")

local StatsReader = require("aleph_stats_reader")
local BoardUtil = require("aleph_board_util")
local ChapterMap = require("aleph_chapter_map")
local try = require("aleph_try").call

local BoardData = {}

local DAY = 86400
local LOCAL_TTL = 120
-- The heatmap shows 52 whole weeks, Sunday to Saturday, ending with the week
-- that holds today.
BoardData.HEATMAP_DAYS = 364

local function dayStart(t)
    local d = os.date("*t", t)
    d.hour, d.min, d.sec = 0, 0, 0
    return os.time(d)
end
BoardData.dayStart = dayStart

local function dateKey(t)
    return os.date("%Y-%m-%d", t)
end

-- ---------------------------------------------------------------- words
local Dates = require("aleph_dates")
BoardData.longWeekday = Dates.longWeekday
BoardData.shortWeekday = Dates.shortWeekday
BoardData.longMonth = Dates.longMonth
BoardData.shortMonth = Dates.shortMonth

function BoardData.longDate(t)
    return T(_.pgettext("Date: long weekday, day, long month", "%1, %2 %3"), BoardData.longWeekday(t), tonumber(os.date("%d", t)), BoardData.longMonth(t))
end

function BoardData.greeting(name, t)
    local hour = tonumber(os.date("%H", t)) or 12
    if type(name) ~= "string" or name == "" then
        if hour >= 5 and hour < 12 then return _("Good morning") end
        if hour >= 12 and hour < 18 then return _("Good afternoon") end
        return _("Good evening")
    end
    if hour >= 5 and hour < 12 then return T(_("Good morning, %1"), name) end
    if hour >= 12 and hour < 18 then return T(_("Good afternoon, %1"), name) end
    return T(_("Good evening, %1"), name)
end

function BoardData.formatDuration(min)
    min = math.floor((min or 0) + 0.5)
    if min < 60 then return T(_("%1 min"), min) end
    local h, m = math.floor(min / 60), min % 60
    if m == 0 then return T(_("%1 h"), h) end
    return T(_("%1 h %2 min"), h, m)
end

function BoardData.formatShortDuration(min)
    min = math.floor((min or 0) + 0.5)
    if min < 60 then return T(_("%1m"), min) end
    local h, m = math.floor(min / 60), min % 60
    if m == 0 then return T(_("%1h"), h) end
    return T(_("%1h %2m"), h, m)
end

-- Hours today, "yesterday", a weekday inside a week, then a short date.
function BoardData.relativeDay(iso, now)
    if type(iso) ~= "string" then return nil end
    local t = datetime.stringISO8601ToSeconds and datetime.stringISO8601ToSeconds(iso)
    if not t then return BoardUtil.formatRelativeTime(iso, now) end
    now = now or os.time()
    local delta = now - t
    if delta < 60 then return _("just now") end
    if delta < 3600 then return T(_("%1 min ago"), math.floor(delta / 60)) end
    if delta < DAY then return T(_("%1 h ago"), math.floor(delta / 3600)) end
    local days = math.floor((dayStart(now) - dayStart(t)) / DAY + 0.5)
    if days <= 1 then return _("yesterday") end
    if days < 7 then return BoardData.longWeekday(t) end
    return Dates.monthDay(t)
end

-- "Late September 2025" for a YYYY-MM-DD date.
function BoardData.partOfMonth(date_key)
    if type(date_key) ~= "string" then return nil end
    local y, m, d = date_key:match("^(%d+)-(%d+)-(%d+)")
    if not y then return nil end
    local t = os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 })
    local month, year = BoardData.longMonth(t), tonumber(y)
    local day = tonumber(d)
    if day <= 10 then return T(_("Early %1 %2"), month, year) end
    if day <= 20 then return T(_("Mid %1 %2"), month, year) end
    return T(_("Late %1 %2"), month, year)
end

-- "Aug 2025": when a book was last read, for books set aside a while.
function BoardData.monthYear(iso)
    if type(iso) ~= "string" then return nil end
    local t = datetime.stringISO8601ToSeconds and datetime.stringISO8601ToSeconds(iso)
    if not t then return nil end
    return Dates.monthYear(t)
end

-- Rounded, except that a started book never reads 0% and an unfinished one
-- never reads 100%.
function BoardData.pctLabel(book)
    local p = book and tonumber(book.progressPercentage)
    if not p then return nil end
    if p > 0 and p < 0.5 then return _("<1%") end
    if p < 100 and p >= 99.5 then return "99%" end
    return tostring(math.floor(p + 0.5)) .. "%"
end

-- ------------------------------------------------------- local statistics
local local_cache = { at = 0, day = nil, daily = {} }

function BoardData.localDaily(now)
    now = now or os.time()
    local today = dateKey(now)
    if local_cache.day == today and now - local_cache.at < LOCAL_TTL then
        return local_cache.daily
    end
    local since = dayStart(now) - (BoardData.HEATMAP_DAYS + 7) * DAY
    local daily = StatsReader.getDailySeconds(since) or {}
    local_cache = { at = now, day = today, daily = daily }
    return daily
end

function BoardData.invalidateLocal()
    local_cache = { at = 0, day = nil, daily = {} }
end

-- Minutes per day for the heatmap's 52 weeks, oldest first. Account-wide
-- minutes from the server and this device's own statistics are merged by
-- taking the larger per day: the device may hold reading not synced yet, the
-- server holds other devices'. Days after today are nil.
local year_cache = {}
function BoardData.yearMinutes(now)
    now = now or os.time()
    local today = dayStart(now)
    -- The 52 weeks only change with the day or the statistics: kept until then.
    local daily_now = BoardData.localDaily(now)
    if year_cache.today == today and year_cache.daily == daily_now then
        return year_cache.values, year_cache.start, year_cache.today_start
    end
    local dow = tonumber(os.date("%w", now)) -- 0 = Sunday
    local last_saturday = today + (6 - dow) * DAY
    local start = last_saturday - (BoardData.HEATMAP_DAYS - 1) * DAY
    local daily = BoardData.localDaily(now)
    local values = {}
    for i = 1, BoardData.HEATMAP_DAYS do
        local t = start + (i - 1) * DAY + 12 * 3600
        if t > today + DAY then
            values[i] = nil
        else
            local key = dateKey(t)
            local local_min = (daily[key] or 0) / 60
            values[i] = math.floor(local_min + 0.5)
        end
    end
    year_cache = { today = today, daily = daily_now, values = values, start = start + 12 * 3600, today_start = today }
    return values, start + 12 * 3600, today
end

-- When the current book ends at this reader's pace, from its own statistics.
-- The time left is the one KOReader's status bar shows in the book (and
-- Aleph's "time left in book"): pages left in its present layout times its
-- average time per page (StatsReader.getBookPace). The pace is asked again
-- whenever the statistics change (StatsReader remembers it until then).
-- The days the recent pace is spread over: from the day of `first` (the
-- first read in the last two weeks) to today, both counted, 1 to 14.
function BoardData.paceDays(first, now)
    if not first then return 14 end
    local days = math.floor((dayStart(now) - dayStart(first)) / DAY + 0.5) + 1
    return math.max(1, math.min(14, days))
end

function BoardData.forecast(book, md5, now)
    if not book or not md5 then return nil end
    now = now or os.time()
    local pace = StatsReader.getBookPace(md5, 14)
    if not pace or not pace.seconds_per_page or not pace.total_pages or pace.total_pages <= 0 then return nil end
    local progress = (tonumber(book.progressPercentage) or 0) / 100
    -- The page being read is page progress × pages; KOReader counts the
    -- pages after it.
    local pages_left = math.max(0, math.floor(pace.total_pages - pace.total_pages * progress + 0.5))
    local minutes_left = pages_left * pace.seconds_per_page / 60
    -- Average over the last two weeks, at least five minutes a day, so a book
    -- read in one sitting does not forecast as finishing today forever.
    -- Aleph modification, 2026-11-20: over the days since the book was first
    -- read in those two weeks, today included, not always fourteen: a book
    -- started two days ago (half of it read since) was forecast at a
    -- seventh of its pace, two weeks out.
    local days = BoardData.paceDays(pace.recent_first, now)
    local per_day = math.max(5, pace.recent_seconds / 60 / days)
    local days_out = math.max(0, math.ceil(minutes_left / per_day) - 1)
    local finish = dayStart(now) + days_out * DAY + 12 * 3600
    return {
        book = book,
        minutes_left = minutes_left,
        per_day = per_day,
        days_out = days_out,
        finish = finish,
        day = days_out == 0 and _("Today") or (days_out == 1 and _("Tomorrow") or BoardData.longWeekday(finish)),
        short = BoardData.shortWeekday(finish),
        date = Dates.dayMonth(finish),
    }
end

-- When in the day and how long this device reads. Both read the whole recent
-- history, so they are computed only when a widget on screen asks (see
-- BoardData.build) and kept for the day.
local habits_cache = { day = nil }
local function habits(now)
    local today = dateKey(now)
    if habits_cache.day ~= today then habits_cache = { day = today } end
    return habits_cache
end

function BoardData.hours(now)
    now = now or os.time()
    local cache = habits(now)
    if cache.hours == nil then
        cache.hours = StatsReader.getHourMinutes(dayStart(now) - 90 * DAY) or false
    end
    return cache.hours or nil
end

function BoardData.records(now)
    now = now or os.time()
    local cache = habits(now)
    if cache.records == nil then
        local r = StatsReader.getSessionRecords(dayStart(now) - 365 * DAY)
        cache.records = r and {
            sessions = r.sessions,
            longest_min = math.floor(r.longest_seconds / 60 + 0.5),
            avg_min = math.floor(r.average_seconds / 60 + 0.5),
            pages_per_hour = math.floor(r.pages_per_hour + 0.5),
        } or false
    end
    return cache.records or nil
end

function BoardData.invalidateHabits()
    habits_cache = { day = nil }
end

-- ---------------------------------------------------------- vocabulary
local word_cache = { day = nil, word = false }
function BoardData.wordOfTheDay(now)
    now = now or os.time()
    local today = dateKey(now)
    if word_cache.day == today then return word_cache.word or nil end
    local word = false
    local ok_sq, SQ3 = pcall(require, "lua-ljsqlite3/init")
    local path = require("datastorage"):getSettingsDir() .. "/vocabulary_builder.sqlite3"
    if ok_sq and require("libs/libkoreader-lfs").attributes(path, "mode") == "file" then
        local ok, conn = pcall(SQ3.open, path, "ro")
        if ok and conn then
            try(function()
                local count = tonumber(conn:rowexec("SELECT COUNT(*) FROM vocabulary;")) or 0
                if count > 0 then
                    -- Counted in local days, so the word changes at the
                    -- reader's midnight rather than at UTC midnight.
                    local offset = math.floor((dayStart(now) + 12 * 3600) / DAY) % count
                    local stmt = conn:prepare("SELECT v.word, v.prev_context, v.next_context, t.name FROM vocabulary v"
                        .. " LEFT JOIN title t ON t.id = v.title_id ORDER BY v.create_time LIMIT 1 OFFSET ?;")
                    local row = stmt:reset():bind(offset):step()
                    if row then
                        word = {
                            word = row[1],
                            before = row[2] or "",
                            after = row[3] or "",
                            book = row[4],
                        }
                    end
                    stmt:close()
                end
            end)
            pcall(conn.close, conn)
        end
    end
    word_cache = { day = today, word = word }
    return word or nil
end

-- ----------------------------------------------------------------- light
-- KOReader reports brightness as a raw device level (0..fl_max; a Kindle has
-- about 24 steps), not a percentage. Everything drawn here uses 0-100, so the
-- level is converted both ways and the bar fills completely at the maximum.
local function lightMax(powerd)
    local m = tonumber(powerd.fl_max)
    return (m and m > 0) and m or 100
end

function BoardData.light()
    if not Device:hasFrontlight() then return nil end
    local powerd = Device:getPowerDevice()
    local max = lightMax(powerd)
    local level = math.max(0, math.min(max, powerd:frontlightIntensity() or 0))
    local light = { brightness = math.floor(level * 100 / max + 0.5), level = level, max = max }
    if powerd.isFrontlightOn then light.on = powerd:isFrontlightOn() and true or false
    else light.on = level > 0 end
    if Device:hasNaturalLight() then
        light.warmth = math.floor((powerd:frontlightWarmth() or 0) + 0.5)
    end
    return light
end

-- Switches the frontlight on or off, keeping its level for the next time.
function BoardData.toggleLight()
    if not Device:hasFrontlight() then return false end
    Device:getPowerDevice():toggleFrontlight()
    return true
end

-- Moves brightness or warmth by delta percent; brightness moves at least one
-- device level so coarse frontlights still respond to every tap.
function BoardData.adjustLight(what, delta)
    if not Device:hasFrontlight() or not tonumber(delta) then return false end
    local powerd = Device:getPowerDevice()
    if what == "warmth" then
        if not Device:hasNaturalLight() then return false end
        local cur = powerd:frontlightWarmth() or 0
        local nxt = math.max(0, math.min(100, cur + delta))
        if nxt == cur then return false end
        powerd:setWarmth(nxt)
        return true
    elseif what == "brightness" then
        local max = lightMax(powerd)
        -- A light that is off reads as 0; raising it switches it on at its
        -- remembered level first, and lowering it does nothing.
        if powerd.isFrontlightOff and powerd:isFrontlightOff() then
            if delta < 0 then return false end
            powerd:turnOnFrontlight()
        end
        local cur = powerd:frontlightIntensity() or 0
        local step = math.floor(math.abs(delta) * max / 100 + 0.5)
        if step < 1 then step = 1 end
        local nxt = math.max(0, math.min(max, cur + (delta < 0 and -step or step)))
        if nxt == cur then return false end
        powerd:setIntensity(nxt)
        return true
    end
    return false
end

-- --------------------------------------------------------------- storage
-- Cached like the local statistics: older KOReader releases measure the disk
-- by running df, and the board is rebuilt on every stepper tap.
local storage_cache = { at = 0 }
function BoardData.storage(dir, now)
    if not dir then return nil end
    now = now or os.time()
    if storage_cache.dir == dir and now - storage_cache.at < LOCAL_TTL then return storage_cache.value end
    local ok, usage = pcall(util.diskUsage, dir)
    local value = nil
    if ok and usage and usage.total and usage.total > 0 then
        value = { free_gb = usage.available / 1024 / 1024 / 1024, total_gb = usage.total / 1024 / 1024 / 1024 }
    end
    storage_cache = { at = now, dir = dir, value = value }
    return value
end

-- ------------------------------------------------------------------ decor
-- Every page this device has turned, how many today, and since when.
local turns_cache = { at = 0 }
function BoardData.pageTurns(now)
    now = now or os.time()
    local today = dateKey(now)
    if turns_cache.day == today and now - turns_cache.at < LOCAL_TTL then return turns_cache.value end
    local r = StatsReader.getPageTurns(dayStart(now))
    local value = nil
    if r then
        value = { total = r.total or 0, today = r.today or 0 }
        if r.first then value.since = Dates.monthYear(r.first) end
    end
    turns_cache = { at = now, day = today, value = value }
    return value
end

-- Minutes read in each of the last twelve calendar months, oldest first,
-- from the year of reading the heatmap draws.
function BoardData.monthTotals(heatmap, heatmap_start, now)
    local sums = {}
    for i = 1, BoardData.HEATMAP_DAYS do
        local v = heatmap and heatmap[i]
        if v and v > 0 then
            local t = os.date("*t", heatmap_start + (i - 1) * DAY)
            local key = t.year * 12 + t.month - 1
            sums[key] = (sums[key] or 0) + v
        end
    end
    local nt = os.date("*t", now)
    local last = nt.year * 12 + nt.month - 1
    local out = {}
    for key = last - 11, last do
        table.insert(out, { month = key % 12 + 1, year = math.floor(key / 12), min = sums[key] or 0 })
    end
    return out
end

-- The month name for a month number, as BoardData.longMonth gives it.
function BoardData.monthName(month, long)
    local t = os.time({ year = 2001, month = month, day = 15, hour = 12 })
    return long and BoardData.longMonth(t) or BoardData.shortMonth(t)
end

-- The moon tonight, from the mean synodic month counted from a known new
-- moon (2000-01-06 18:14 UTC). Good to within about half a day, which is
-- plenty for a picture of it. Drawn as seen from the northern hemisphere.
local SYNODIC = 29.530588853
local NEW_MOON_REF = 947182440
local MOON_PHASES = {
    new = function() return _("New moon") end,
    waxing_crescent = function() return _("Waxing crescent") end,
    first_quarter = function() return _("First quarter") end,
    waxing_gibbous = function() return _("Waxing gibbous") end,
    full = function() return _("Full moon") end,
    waning_gibbous = function() return _("Waning gibbous") end,
    last_quarter = function() return _("Last quarter") end,
    waning_crescent = function() return _("Waning crescent") end,
}
function BoardData.moon(now)
    now = now or os.time()
    local age = ((now - NEW_MOON_REF) / DAY) % SYNODIC
    local p = age / SYNODIC
    local lit = (1 - math.cos(2 * math.pi * p)) / 2
    local phase
    if age < 1.0 or age > 28.5 then phase = "new"
    elseif age < 6.4 then phase = "waxing_crescent"
    elseif age < 8.4 then phase = "first_quarter"
    elseif age < 13.8 then phase = "waxing_gibbous"
    elseif age < 15.8 then phase = "full"
    elseif age < 21.1 then phase = "waning_gibbous"
    elseif age < 23.1 then phase = "last_quarter"
    else phase = "waning_crescent" end
    local to_full = (SYNODIC / 2 - age) % SYNODIC
    local to_new = SYNODIC - age
    local next_full
    if phase == "new" then next_full = true
    elseif phase == "full" then next_full = false
    else next_full = to_full < to_new end
    local when = now + (next_full and to_full or to_new) * DAY
    local day = tonumber(os.date("%d", when))
    return {
        age = age, p = p, lit = lit, phase = phase, name = MOON_PHASES[phase](),
        next = next_full and T(_("Full moon %1 %2 %3"), BoardData.shortWeekday(when), day, BoardData.shortMonth(when))
            or T(_("New moon %1 %2 %3"), BoardData.shortWeekday(when), day, BoardData.shortMonth(when)),
    }
end

-- Characters for the Glyph of the day, each in a font KOReader ships. A
-- device without the font skips that day's glyph for the next one.
BoardData.GLYPHS = {
    { cp = 0x26, name = function() return _("Ampersand") end, font = "NotoSerif-BoldItalic.ttf", label = "Noto Serif Bold Italic", sample = "Aa Bb Cc Dd" },
    { cp = 0x66F8, name = function() return _("Book, to write") end, font = "NotoSansCJKsc-Regular.otf", label = "Noto Sans CJK SC" },
    { cp = 0xB6, name = function() return _("Pilcrow") end, font = "FreeSerif.ttf", label = "FreeSerif", sample = "Aa Bb Cc Dd" },
    { cp = 0x0639, name = function() return _("Ain") end, font = "NotoNaskhArabic-Regular.ttf", label = "Noto Naskh Arabic" },
    { cp = 0xDF, name = function() return _("Sharp s") end, font = "NotoSerif-Italic.ttf", label = "Noto Serif Italic", sample = "Aa Bb Cc Dd" },
    { cp = 0x0915, name = function() return _("Ka") end, font = "NotoSansDevanagariUI-Bold.ttf", label = "Noto Sans Devanagari" },
    { cp = 0xA7, name = function() return _("Section sign") end, font = "NotoSerif-Regular.ttf", label = "Noto Serif", sample = "Aa Bb Cc Dd" },
    { cp = 0x8AAD, name = function() return _("To read") end, font = "NotoSansCJKsc-Regular.otf", label = "Noto Sans CJK SC" },
    { cp = 0x0985, name = function() return _("A, in Bengali") end, font = "NotoSansBengaliUI-Bold.ttf", label = "Noto Sans Bengali" },
    { cp = 0x40, name = function() return _("At sign") end, font = "NotoSans-Bold.ttf", label = "Noto Sans Bold", sample = "Aa Bb Cc Dd" },
    { cp = 0x05D0, name = function() return _("Alef") end, font = "FreeSerif.ttf", label = "FreeSerif" },
    { cp = 0xF0, name = function() return _("Eth") end, font = "NotoSerif-BoldItalic.ttf", label = "Noto Serif Bold Italic", sample = "Aa Bb Cc Dd" },
    { cp = 0x6587, name = function() return _("Writing") end, font = "NotoSansCJKsc-Regular.otf", label = "Noto Sans CJK SC" },
    { cp = 0x03A9, name = function() return _("Omega") end, font = "NotoSerif-Regular.ttf", label = "Noto Serif", sample = "Aa Bb Cc Dd" },
    { cp = 0x0416, name = function() return _("Zhe") end, font = "NotoSans-Bold.ttf", label = "Noto Sans Bold" },
    { cp = 0x017F, name = function() return _("Long s") end, font = "NotoSerif-Italic.ttf", label = "Noto Serif Italic", sample = "Aa Bb Cc Dd" },
}

-- Today's glyph: one a day, in order, counted in the reader's local days.
-- has(font) says whether this device has a font.
function BoardData.glyphOfTheDay(now, has)
    local day = math.floor((dayStart(now or os.time()) + 12 * 3600) / DAY)
    local n = #BoardData.GLYPHS
    for step = 0, n - 1 do
        local g = BoardData.GLYPHS[(day + step) % n + 1]
        if not has or has(g.font) then return g end
    end
    return nil
end

-- The Chapter line for a book: its stops, where the reader is, and how
-- long to each stop at the pace the finish forecast uses.
function BoardData.chapterLine(book, md5)
    if not book or not md5 then return nil end
    local stops = ChapterMap.stations(ChapterMap.load(md5))
    if not stops then return nil end
    local pos = math.max(0, math.min(100, tonumber(book.progressPercentage) or 0))
    local cur = 1
    for i, stop in ipairs(stops) do
        if stop.pct <= pos then cur = i end
    end
    local per_pct = book.minutes_left and book.minutes_left / math.max(0.1, 100 - pos) or nil
    return {
        book = book,
        stops = stops,
        pos = pos,
        cur = cur,
        next = math.min(cur + 1, #stops),
        per_pct = per_pct,
        end_min = book.minutes_left,
        minutes = function(i)
            if not per_pct then return nil end
            return math.max(1, math.floor((stops[i].pct - pos) * per_pct + 0.5))
        end,
    }
end

-- "About 3 weeks to go" for a number of days, or nil when it is too far
-- off to be worth saying.
function BoardData.etaLabel(days)
    if not days or days ~= days or days <= 0 then return nil end
    if days < 1.5 then return _("About a day to go") end
    if days < 10 then return T(_("About %1 days to go"), math.floor(days + 0.5)) end
    if days < 60 then return T(_("About %1 weeks to go"), math.floor(days / 7 + 0.5)) end
    if days < 730 then return T(_("About %1 months to go"), math.floor(days / 30 + 0.5)) end
    return nil
end

-- When a badge was earned, in days.
function BoardData.earnedLabel(iso, now)
    local t = type(iso) == "string" and datetime.stringISO8601ToSeconds and datetime.stringISO8601ToSeconds(iso)
    if not t then return nil end
    local days = math.floor((dayStart(now) - dayStart(t)) / DAY + 0.5)
    if days <= 0 then return _("Earned today") end
    if days == 1 then return _("Earned yesterday") end
    if days < 7 then return T(_("Earned %1"), BoardData.longWeekday(t)) end
    return T(_("Earned %1 %2"), tonumber(os.date("%d", t)), BoardData.shortMonth(t))
end

-- The Next badge widget's data, from the dashboard's achievements. A server
-- too old to send them leaves the field out; one whose reader turned
-- achievements off sends null. pace gives minutes read a day, books finished
-- a day and pages an hour, for the time-to-go line.
function BoardData.badges(body, now, pace)
    local raw = body and body.achievements
    if raw == nil then return { missing = true } end
    if type(raw) ~= "table" then return { off = true } end
    local function badge(b)
        if type(b) ~= "table" or type(b.name) ~= "string" then return nil end
        return {
            key = b.key, group = b.groupKey, name = b.name, desc = type(b.description) == "string" and b.description or "",
            rarity = b.rarity, icon = b.iconName, threshold = tonumber(b.threshold), progress = tonumber(b.currentProgress),
            awarded_at = type(b.awardedAt) == "string" and b.awardedAt or nil,
        }
    end
    local out = { earned = tonumber(raw.earned) or 0, total = tonumber(raw.total) or 0, next = badge(raw.next), latest = badge(raw.latest) }
    if out.latest then
        out.latest.when = BoardData.earnedLabel(out.latest.awarded_at, now)
        local t = out.latest.awarded_at and datetime.stringISO8601ToSeconds and datetime.stringISO8601ToSeconds(out.latest.awarded_at)
        out.fresh = t ~= nil and now - t < DAY
    end
    local n = out.next
    if n and n.threshold and n.progress and pace then
        local left = n.threshold - n.progress
        local per_day
        if n.group == "hours_read" and pace.minutes_per_day and pace.minutes_per_day > 0 then
            per_day = pace.minutes_per_day / 60
        elseif n.group == "books_finished" and pace.books_per_day and pace.books_per_day > 0 then
            per_day = pace.books_per_day
        elseif n.group == "pages_read" and pace.minutes_per_day and pace.pages_per_hour and pace.pages_per_hour > 0 then
            per_day = pace.minutes_per_day / 60 * pace.pages_per_hour
        end
        if per_day and left > 0 then n.eta = BoardData.etaLabel(left / per_day) end
    end
    return out
end

-- Books on this device that were downloaded and never opened, oldest
-- download first: not in KOReader's history and without a sidecar. Kept
-- for the day and the on-device generation; a scan stops after SCAN_MAX
-- files so a huge library costs a bounded number of file checks.
BoardData.UNOPENED_KEEP = 30
BoardData.UNOPENED_SCAN_MAX = 3000
local unopened_cache = { key = nil, list = {} }

local function openedFiles()
    local files = {}
    local ok, ReadHistory = pcall(require, "readhistory")
    if ok and type(ReadHistory) == "table" and type(ReadHistory.hist) == "table" then
        for _i, item in ipairs(ReadHistory.hist) do
            if type(item) == "table" and item.file then files[item.file] = true end
        end
    end
    return files
end

local function hasSidecar(path)
    local ok, DocSettings = pcall(require, "docsettings")
    if not ok or not DocSettings then return false end
    local found, has = pcall(DocSettings.hasSidecarFile, DocSettings, path)
    return found and has == true
end
BoardData._hasSidecar = hasSidecar

function BoardData.unopened(host, now)
    now = now or os.time()
    local key = tostring(host and host.on_device_generation) .. "|" .. dateKey(now)
    if unopened_cache.key == key then return unopened_cache.list end
    local lfs = require("libs/libkoreader-lfs")
    local opened = openedFiles()
    local list, scanned = {}, 0
    for book_id, path in pairs(host and host.on_device or {}) do
        scanned = scanned + 1
        if scanned > BoardData.UNOPENED_SCAN_MAX then break end
        if type(path) == "string" and not opened[path] then
            local at = lfs.attributes(path, "modification")
            if at and not hasSidecar(path) then
                table.insert(list, { id = book_id, path = path, at = at, size = lfs.attributes(path, "size") or 0 })
            end
        end
    end
    table.sort(list, function(a, b) return a.at < b.at end)
    while #list > BoardData.UNOPENED_KEEP do table.remove(list) end
    unopened_cache = { key = key, list = list }
    return list
end

function BoardData.invalidateUnopened()
    unopened_cache = { key = nil, list = {} }
end

-- The Gathering dust widget's book: one unopened book a day, walking the
-- whole list before any repeats; skip steps past books the reader asked to
-- see past today. A book opened since the list was made is passed over.
function BoardData.dust(host, books, now, skip)
    local list = BoardData.unopened(host, now)
    local by_id = {}
    for _i, b in ipairs(books or {}) do
        if type(b) == "table" and b.id then by_id[b.id] = b end
    end
    local pool, bytes = {}, 0
    for _i, entry in ipairs(list) do
        if by_id[entry.id] then
            table.insert(pool, { book = by_id[entry.id], at = entry.at, path = entry.path })
            bytes = bytes + (entry.size or 0)
        end
    end
    if #pool == 0 then return { count = 0 } end
    local day = math.floor((dayStart(now) + 12 * 3600) / DAY)
    local opened = openedFiles()
    for step = 0, #pool - 1 do
        local entry = pool[(day + (skip or 0) + step) % #pool + 1]
        if not opened[entry.path] and not hasSidecar(entry.path) then
            local days = math.max(0, math.floor((now - entry.at) / DAY))
            return { count = #pool, book = entry.book, days = days, months = math.floor(days / 30),
                total_mb = math.max(1, math.floor(bytes / 1024 / 1024 + 0.5)) }
        end
    end
    return { count = 0 }
end

-- ------------------------------------------------------------------ build
-- host: the screen asking (aleph_browser.lua), for on-device state, covers
-- and settings.
-- context: the dashboard context (body, stale flags).
-- Board books work out "last read" when it is read (see decorate).
local decorate_now = os.time()
local DECORATED = { __index = function(t, k)
    if k == "last_read" then return BoardData.relativeDay(rawget(t, "lastReadAt"), decorate_now) end
end }

-- The time fields of a board's data moved to `now`, for the minute redraw
-- of the clock widgets without building the rest again.
function BoardData.tickTime(d, now)
    now = now or os.time()
    d.now = now
    d.clock = datetime.secondsToHour(now, G_reader_settings:isTrue("twelve_hour_clock"))
    d.weekday = BoardData.longWeekday(now)
    d.day_month = Dates.dayLongMonth(now)
    d.date_long = BoardData.longDate(now)
    return d
end

-- The parts of BoardData.build, each with one job. host is the screen
-- asking (aleph_browser.lua), body the library's dashboard, d the board's
-- data being filled.

-- Board books: decorate(book) for one, decorateAll(list) for a list.
local function boardBooks(host, body, now)
    -- A board book: the library's entry plus what the board shows of it.
    -- Kept between builds for the same dashboard (a copy per book per
    -- refresh was the dearest part of a redraw: the Discover shelf holds the
    -- whole library) and made again when its cover or place changes.
    -- last_read is worked out when read, so it is never stale.
    local memo = rawget(body, "_board_books")
    if not memo then
        memo = setmetatable({}, { __mode = "k" })
        rawset(body, "_board_books", memo)
    end
    decorate_now = now
    local function decorate(book)
        if type(book) ~= "table" then return nil end
        local on_device = host:isOnDevice(book) == true
        local path, state = host:thumbnailDisplay(book)
        local b = memo[book]
        if b and rawget(b, "cover_path") == path and b.cover_state == state and b.on_device == on_device then
            return b
        end
        b = {}
        for k, v in pairs(book) do b[k] = v end
        b.last_read = nil
        b.on_device = on_device
        b.cover_path, b.cover_state = path, state
        setmetatable(b, DECORATED)
        memo[book] = b
        return b
    end
    -- A whole list of board books is kept too, for as long as the host
    -- says nothing it was made from has changed (its boardEpoch: a cover
    -- arrived, the library's entries changed). Several shelves hold the
    -- whole library, and every redraw (every tap on Home) went through each
    -- of them book by book. A host without boardEpoch keeps nothing.
    local epoch = host.boardEpoch and host:boardEpoch() or nil
    local kept = rawget(body, "_board_lists")
    if not kept or kept.epoch ~= epoch or epoch == nil then
        kept = { epoch = epoch, by = setmetatable({}, { __mode = "k" }) }
        rawset(body, "_board_lists", kept)
    end
    local function decorateAll(list)
        if type(list) ~= "table" then return {} end
        local hit = epoch ~= nil and kept.by[list] or nil
        if hit and hit.count == #list then return hit.out end
        local out = {}
        for _i, book in ipairs(list) do
            local b = decorate(book)
            if b then table.insert(out, b) end
        end
        if epoch ~= nil then kept.by[list] = { count = #list, out = out } end
        return out
    end
    return decorate, decorateAll
end

-- This device's reading by day: the year's heatmap, the last seven days
-- and the streak's week.
local function readingWeek(d, body, now)
    d.heatmap, d.heatmap_start, d.today_start = BoardData.yearMinutes(now, body.readingYear)
    local week = {}
    local today_index = nil
    for i = 1, BoardData.HEATMAP_DAYS do
        if d.heatmap[i] ~= nil then today_index = i end
    end
    today_index = today_index or BoardData.HEATMAP_DAYS
    for i = 1, 7 do week[i] = d.heatmap[today_index - 7 + i] or 0 end
    d.week = week
    d.week_initials = {}
    for i = 1, 7 do
        local t = now - (7 - i) * DAY
        d.week_initials[i] = BoardData.shortWeekday(t):sub(1, 1)
    end
    d.today_min = week[7]
    d.week_min = 0
    for _i, v in ipairs(week) do d.week_min = d.week_min + v end
    -- The streak is the server's account streak; a device whose own reading
    -- has not synced yet still counts today.
    if d.streak.current == 0 and d.today_min > 0 then d.streak.current = 1 end
    d.streak_week = {}
    for i = 1, 7 do d.streak_week[i] = (week[i] or 0) > 0 or d.streak.last_seven[i] == true end
    BoardData.goals(d, body, now, today_index)
end

-- Aleph modification, 2026-11-18: the Goals widget's four goals, from the
-- day's minutes, this week's days with reading (from the first day of the
-- week KOReader's statistics calendar uses, Monday unless set), and the
-- books finished this month and this year. goal 0 or nil: off.
function BoardData.weekStart(now)
    local first = 2
    pcall(function()
        local st = G_reader_settings:readSetting("statistics")
        first = tonumber(type(st) == "table" and st.calendar_start_day_of_week) or 2
    end)
    local wday = tonumber(os.date("%w", now)) + 1 -- 1 Sunday .. 7 Saturday
    return (wday - first) % 7                       -- days since the week began
end

function BoardData.goals(d, body, now, today_index)
    local g = type(body.readingGoal) == "table" and body.readingGoal or {}
    local since = BoardData.weekStart(now)
    local days = 0
    -- This week's days in order: true (read), false (not), nil (to come).
    local flags = {}
    for i = 0, since do
        local read = (d.heatmap[(today_index or BoardData.HEATMAP_DAYS) - i] or 0) > 0
        if read then days = days + 1 end
        flags[since - i + 1] = read
    end
    local initials = {}
    for i = 1, 7 do initials[i] = BoardData.shortWeekday(now + (i - 1 - since) * 86400):sub(1, 1) end
    d.goals = {
        day = { done = d.today_min or 0, goal = tonumber(g.dayMinutes) },
        week = { done = days, goal = tonumber(g.weekDays), flags = flags, initials = initials, today = since + 1 },
        month = { done = tonumber(g.monthDone) or 0, goal = tonumber(g.monthBooks) },
        year = { done = tonumber(g.completedBooks) or 0, goal = tonumber(g.goalBooks), year = tonumber(g.year) },
    }
end

local function setFingerprint(d, body, now)
    -- Everything a widget's layout choice can depend on. Widgets remember
    -- their choice per fingerprint (see BoardUI.pick).
    local covers = {}
    for _i, b in ipairs(d.continue_reading) do table.insert(covers, (b.cover_state or "") .. (b.on_device and "d" or "")) end
    d.fingerprint = table.concat({
        tostring(body.generatedAt), tostring(body), tostring(d.online), tostring(d.stale), dateKey(now),
        d.light and (d.light.brightness .. "/" .. tostring(d.light.warmth)) or "-",
        d.today_min, d.week_min, d.streak.current, d.counts.device or 0,
        d.goals and table.concat({ tostring(d.goals.day.goal), d.goals.week.done, tostring(d.goals.week.goal),
            d.goals.month.done, tostring(d.goals.month.goal), d.goals.year.done, tostring(d.goals.year.goal) }, "/") or "-",
        d.word and d.word.word or "-", d.forecast and math.floor(d.forecast.minutes_left) or "-",
        table.concat(covers, ","), tostring(G_reader_settings:isTrue("night_mode")),
        table.concat(d.recent_searches or {}, ","), d.loading and "l" or "",
    }, "|")
end

local function lazyFields(d, host, body, now, lead, lead_md5)
    -- Hours, records and the decor widgets' data cost a pass over the
    -- device's statistics or its files, so they are read only by a widget
    -- that draws them.
    local lazy = {
        hours = function() return BoardData.hours(now) end,
        records = function() return BoardData.records(now) end,
        -- Aleph modification, 2026-11-20: the Hours read widget.
        -- Aleph modification, 2026-11-20: the Time read and Books and pages
        -- widgets: this year month by month (hours and pages from the
        -- statistics, books from the finished books).
        year_months = function()
            local t = os.date("*t", now)
            local y0 = os.time{ year = t.year, month = 1, day = 1, hour = 0 }
            local y1 = os.time{ year = t.year + 1, month = 1, day = 1, hour = 0 }
            local s = StatsReader.getMonthStats(y0, y1)
            if not s then return nil end
            local books = {}
            for m = 1, 12 do books[m] = 0 end
            local prefix = tostring(t.year) .. "-"
            -- The books the yearly goal counts (deleted ones kept on the record too).
            for _i, b in ipairs(body.finishedThisYear or body.finishedBooks or {}) do
                local f = type(b.finishedOn) == "string" and b.finishedOn or ""
                if f:sub(1, 5) == prefix then
                    local m = tonumber(f:sub(6, 7))
                    if m and books[m] then books[m] = books[m] + 1 end
                end
            end
            return { year = t.year, month = t.month, seconds = s.seconds, pages = s.pages, books = books }
        end,
        hours_total = function()
            local t = os.date("*t", now)
            return StatsReader.getTotalTime(os.time{ year = t.year, month = 1, day = 1, hour = 0 })
        end,
        pages = function() return BoardData.pageTurns(now) end,
        months = function() return BoardData.monthTotals(d.heatmap, d.heatmap_start, now) end,
        moon = function() return BoardData.moon(now) end,
        -- Aleph modification, 2026-11-18: Monthly challenge, Reading rhythm,
        -- Year projection, Diversity score (aleph_more_stats.lua).
        challenge = function()
            local More = require("aleph_more_stats")
            local t = os.date("*t", now)
            local month_start = os.time{ year = t.year, month = t.month, day = 1, hour = 0 }
            local month_days = {}
            for day = 1, t.day do
                local key_t = os.time{ year = t.year, month = t.month, day = day, hour = 12 }
                local idx = math.floor((key_t - d.heatmap_start) / 86400 + 0.5) + 1
                month_days[day] = (d.heatmap[idx] or 0) > 0
            end
            local pages = StatsReader.getPagesSince(month_start, dayStart(now) - 29 * DAY)
            -- The month's challenge, kept once chosen.
            local Prefs = require("aleph_prefs")
            local kept = Prefs.get().challenge
            local month = os.date("%Y-%m", now)
            local chosen = type(kept) == "table" and kept.month == month and kept.id or nil
            local c = More.challenge(body.finishedBooks, body.readingBooks, month_days, pages and pages[1] or 0, now, chosen)
            if not chosen then pcall(Prefs.set, "challenge", { month = month, id = c.id }) end
            return c
        end,
        rhythm = function()
            local today = 0
            for i = 1, BoardData.HEATMAP_DAYS + 7 do if d.heatmap[i] ~= nil then today = i end end
            local minutes = {}
            for i = 13, 0, -1 do minutes[#minutes + 1] = today - i >= 1 and (d.heatmap[today - i] or 0) or 0 end
            local r = require("aleph_more_stats").rhythm(minutes)
            r.initials = {}
            for i = 1, 14 do r.initials[i] = BoardData.shortWeekday(now - (14 - i) * DAY):sub(1, 1) end
            return r
        end,
        projection = function()
            local recent_since = dayStart(now) - 29 * DAY
            local recent_day = os.date("%Y-%m-%d", recent_since)
            local books = 0
            for _i, b in ipairs(body.finishedBooks or {}) do
                if type(b.finishedOn) == "string" and b.finishedOn >= recent_day then books = books + 1 end
            end
            local t = os.date("*t", now)
            local pages = StatsReader.getPagesSince(os.time{ year = t.year, month = t.month, day = 1, hour = 0 }, recent_since)
            local today, minutes = 0, 0
            for i = 1, BoardData.HEATMAP_DAYS + 7 do if d.heatmap[i] ~= nil then today = i end end
            for i = math.max(1, today - 29), today do minutes = minutes + (d.heatmap[i] or 0) end
            return require("aleph_more_stats").projection(d.goal.done or 0, books, pages and pages[2] or 0, minutes / 60, now)
        end,
        diversity = function()
            return require("aleph_more_stats").diversity(body.finishedBooks, body.libraryGenres)
        end,
        -- Aleph modification, 2026-11-18: Reading DNA (aleph_dna.lua): the
        -- finished books' part from the library, the rest from the
        -- statistics already read for When you read and Reading records.
        dna = function()
            local DNA = require("aleph_dna")
            local b = type(body.dnaBooks) == "table" and body.dnaBooks or { books = 0, avg_pages = 0, genres = 0 }
            local peak = DNA.peakHour(BoardData.hours(now))
            local records = BoardData.records(now)
            local pph = records and records.sessions and records.sessions > 0 and records.pages_per_hour or nil
            return DNA.compute(b.avg_pages, b.genres, b.books, DNA.ratio(d.heatmap, 182), peak or 12, pph)
        end,
        glyph = function()
            return BoardData.glyphOfTheDay(now, function(font) return require("aleph_board_art").hasFont(font) end)
        end,
        chapters = function() return BoardData.chapterLine(lead, lead_md5) end,
        badges = function()
            local minutes, days = 0, 0
            local today_index = 0
            for i = 1, BoardData.HEATMAP_DAYS do
                if d.heatmap[i] ~= nil then today_index = i end
            end
            for i = math.max(1, today_index - 89), today_index do
                minutes, days = minutes + (d.heatmap[i] or 0), days + 1
            end
            local raw_next = type(body.achievements) == "table" and type(body.achievements.next) == "table" and body.achievements.next or nil
            local records = raw_next and raw_next.groupKey == "pages_read" and BoardData.records(now) or nil
            return BoardData.badges(body, now, {
                minutes_per_day = days > 0 and minutes / days or nil,
                books_per_day = (d.goal.done or 0) > 0 and d.goal.done / math.max(1, d.day_of_year) or nil,
                pages_per_hour = records and records.pages_per_hour or nil,
            })
        end,
        dust = function()
            local state = host.settings and host.settings.board_dust
            local skip = type(state) == "table" and state.day == dateKey(now) and tonumber(state.skip) or 0
            return BoardData.dust(host, d.shelves["unopened"], now, skip)
        end,
        -- The day a book was finished, never when it was last opened: a
        -- reread opens a finished book. A server too old to send the day
        -- never shows the finished pose.
        finished_today = function()
            local today = dateKey(now)
            for _i, book in ipairs(d.shelves["finished"] or {}) do
                if book.finishedOn == today then return book end
            end
            return false
        end,
    }
    return lazy
end

function BoardData.build(host, context, now)
    now = now or os.time()
    context = context or {}
    local body = context.dashboard or {}
    local d = {}
    d.now = now
    d.loading = context.loading == true
    d.unavailable = context.unavailable == true
    d.online = NetworkMgr:isConnected()
    d.stale = context.stale == true
    d.display_name = body.displayName or body.username or (host.settings and host.settings.username)
    d.greeting = BoardData.greeting(d.display_name, now)
    d.date_long = BoardData.longDate(now)
    d.clock = datetime.secondsToHour(now, G_reader_settings:isTrue("twelve_hour_clock"))
    d.weekday = BoardData.longWeekday(now)
    d.day_month = Dates.dayLongMonth(now)
    d.updated = BoardData.relativeDay(body.generatedAt, now)

    local decorate, decorateAll = boardBooks(host, body, now)

    d.continue_reading = decorateAll(body.continueReading)
    local shelves = type(body.boardShelves) == "table" and body.boardShelves or {}
    d.shelves = {}
    for source, books in pairs(shelves) do d.shelves[source] = decorateAll(books) end
    d.shelves["random"] = d.shelves["random"] or decorateAll(body.discover)
    d.shelves["in-progress"] = d.shelves["in-progress"] or decorateAll(body.continueReading)
    -- A server too old to send the list shows the shelf's empty hint.
    d.shelves["finished"] = decorateAll(body.finishedThisYear)

    local counts = type(body.browseCounts) == "table" and body.browseCounts or {}
    d.counts = {
        library = tonumber(body.totalBooks or body.bookCount),
        series = tonumber(counts.series),
        authors = tonumber(counts.authors),
        collections = tonumber(counts.collections),
        scopes = tonumber(counts.smartScopes),
        libraries = tonumber(counts.libraries),
        in_progress = tonumber(counts.inProgress),
        read = tonumber(counts.read),
        device = host:onDeviceCount(),
    }
    d.names = type(body.boardNames) == "table" and body.boardNames or {}
    d.recent_searches = host.settings and host.settings.recent_searches or {}

    local goal = type(body.readingGoal) == "table" and body.readingGoal or {}
    d.goal = {
        books = tonumber(goal.goalBooks),
        done = tonumber(goal.completedBooks) or 0,
        year = tonumber(goal.year) or tonumber(os.date("%Y", now)),
    }
    d.day_of_year = tonumber(os.date("%j", now)) or 1

    local streak = type(body.readingStreak) == "table" and body.readingStreak or {}
    d.streak = {
        current = BoardUtil.readingStreakDays(body, 0),
        longest = tonumber(streak.longestStreak) or 0,
        last_seven = type(streak.lastSevenDays) == "table" and streak.lastSevenDays or {},
    }
    d.highlight = type(body.highlightOfTheDay) == "table" and body.highlightOfTheDay or nil

    readingWeek(d, body, now)

    local year_ago = type(body.yearAgo) == "table" and body.yearAgo or nil
    if year_ago and type(year_ago.book) == "table" then
        d.year_ago = {
            book = decorate(year_ago.book),
            minutes = tonumber(year_ago.minutes) or 0,
            days = tonumber(year_ago.days) or 0,
            stopped_at = tonumber(year_ago.endProgress) and math.floor(tonumber(year_ago.endProgress) + 0.5) or nil,
            when = BoardData.partOfMonth(year_ago.firstDay),
        }
    end

    d.word = BoardData.wordOfTheDay(now)
    d.light = BoardData.light()
    d.storage = BoardData.storage(host.getCurrentDownloadDir and host:getCurrentDownloadDir() or nil, now)

    local lead = d.continue_reading[1]
    local lead_md5 = nil
    if lead and lead.on_device and host.boardBookMd5 then
        lead_md5 = host:boardBookMd5(lead)
        d.forecast = BoardData.forecast(lead, lead_md5, now)
        if d.forecast then lead.minutes_left = d.forecast.minutes_left end
    end
    setFingerprint(d, body, now)
    local lazy = lazyFields(d, host, body, now, lead, lead_md5)
    return setmetatable(d, { __index = function(t, k)
        local fn = lazy[k]
        if fn then
            local ok, v = pcall(fn)
            if not ok then
                require("logger").warn("Aleph: board data", k, "failed:", v)
                v = nil
            end
            v = v or false
            rawset(t, k, v)
            return v
        end
    end })
end

return BoardData
