-- Aleph modification, 2026-11-18: Reading DNA, after BookOrbit's widget.
--[[--
Five traits of how you read, each a score from 0 to 100 with a word, and a
name for the mix ("Rapid Explorer"). The rules are BookOrbit's
(server/src/modules/dashboard/dashboard-widget.calculations.ts,
computeReadingDna, BookOrbit 3.8.0), fed from this device:

  Length    the finished books' average page count, 500 pages = 100
            (Short up to 30, Medium up to 60, Long)
  Variety   genres among the finished books per book, x200
            (Focused, Balanced, Eclectic)
  Rhythm    the share of the last 182 days with any reading
            (Bursty, Moderate, Steady)
  Time      the hour of the day you read most in the last 182 days
            (Night Owl before 6, Early Bird before 12, Afternoon before 18,
            Evening)
  Speed     pages an hour over the last year, 80 = 100
            (Slow Savorer, Steady Pacer, Speed Demon; none without sessions)

Shown once five books are finished, as in BookOrbit. Books come from the
library index (Finished books, their genres and page
counts: Calibre's or KOReader's); reading from KOReader's statistics, read
by the board already for When you read and Reading records.
]]

local _ = require("aleph_gettext")

local DNA = {}

local function clamp(v) return math.max(0, math.min(100, math.floor(v + 0.5))) end

function DNA.lengthScore(avg_pages) return clamp(avg_pages / 500 * 100) end
function DNA.varietyScore(genres, books)
    if books <= 0 then return 0 end
    return clamp(genres / books * 200)
end
function DNA.rhythmScore(ratio) return clamp(ratio * 100) end
function DNA.timeScore(hour) return clamp(hour / 23 * 100) end
function DNA.speedScore(pph) return clamp(pph / 80 * 100) end

-- The words, in English as the rules use them, and as shown.
local WORDS = {
    Short = function() return _.pgettext("Reading DNA", "Short") end,
    Medium = function() return _.pgettext("Reading DNA", "Medium") end,
    Long = function() return _.pgettext("Reading DNA", "Long") end,
    Focused = function() return _.pgettext("Reading DNA", "Focused") end,
    Balanced = function() return _.pgettext("Reading DNA", "Balanced") end,
    Eclectic = function() return _.pgettext("Reading DNA", "Eclectic") end,
    Bursty = function() return _.pgettext("Reading DNA", "Bursty") end,
    Moderate = function() return _.pgettext("Reading DNA", "Moderate") end,
    Steady = function() return _.pgettext("Reading DNA", "Steady") end,
    ["Night Owl"] = function() return _.pgettext("Reading DNA", "Night Owl") end,
    ["Early Bird"] = function() return _.pgettext("Reading DNA", "Early Bird") end,
    Afternoon = function() return _.pgettext("Reading DNA", "Afternoon") end,
    Evening = function() return _.pgettext("Reading DNA", "Evening") end,
    ["Slow Savorer"] = function() return _.pgettext("Reading DNA", "Slow Savorer") end,
    ["Steady Pacer"] = function() return _.pgettext("Reading DNA", "Steady Pacer") end,
    ["Speed Demon"] = function() return _.pgettext("Reading DNA", "Speed Demon") end,
    ["Night Owl Epic Specialist"] = function() return _.pgettext("Reading DNA", "Night Owl Epic Specialist") end,
    ["Steady Eclectic Explorer"] = function() return _.pgettext("Reading DNA", "Steady Eclectic Explorer") end,
    ["Disciplined Genre Hopper"] = function() return _.pgettext("Reading DNA", "Disciplined Genre Hopper") end,
    ["Early Bird Marathon Reader"] = function() return _.pgettext("Reading DNA", "Early Bird Marathon Reader") end,
    ["Rapid Explorer"] = function() return _.pgettext("Reading DNA", "Rapid Explorer") end,
    ["Patient Specialist"] = function() return _.pgettext("Reading DNA", "Patient Specialist") end,
    ["Deep Specialist"] = function() return _.pgettext("Reading DNA", "Deep Specialist") end,
    ["Weekend Binge Reader"] = function() return _.pgettext("Reading DNA", "Weekend Binge Reader") end,
    ["Curious Explorer"] = function() return _.pgettext("Reading DNA", "Curious Explorer") end,
    ["Steady Habit Reader"] = function() return _.pgettext("Reading DNA", "Steady Habit Reader") end,
    ["Avid Reader"] = function() return _.pgettext("Reading DNA", "Avid Reader") end,
}
function DNA.word(key)
    local f = WORDS[key]
    return f and f() or key
end

local function lengthLabel(s) return s <= 30 and "Short" or s <= 60 and "Medium" or "Long" end
local function varietyLabel(s) return s <= 30 and "Focused" or s <= 60 and "Balanced" or "Eclectic" end
local function rhythmLabel(s) return s <= 30 and "Bursty" or s <= 60 and "Moderate" or "Steady" end
local function timeLabel(h) return h < 6 and "Night Owl" or h < 12 and "Early Bird" or h < 18 and "Afternoon" or "Evening" end
local function speedLabel(s) return s <= 30 and "Slow Savorer" or s <= 60 and "Steady Pacer" or "Speed Demon" end

-- BookOrbit's archetypes, the first that matches.
local ARCHETYPES = {
    { function(t) return t.length > 60 and t.variety <= 30 and t.time_label == "Night Owl" end, "Night Owl Epic Specialist" },
    { function(t) return t.length > 60 and t.variety > 60 and t.rhythm > 60 end, "Steady Eclectic Explorer" },
    { function(t) return t.variety > 60 and t.rhythm > 60 end, "Disciplined Genre Hopper" },
    { function(t) return t.length > 60 and t.time_label == "Early Bird" end, "Early Bird Marathon Reader" },
    { function(t) return t.speed ~= nil and t.speed <= 30 and t.length > 60 end, "Slow Savorer" },
    { function(t) return t.speed ~= nil and t.speed > 60 and t.variety > 60 end, "Rapid Explorer" },
    { function(t) return t.speed ~= nil and t.speed > 60 and t.rhythm <= 30 end, "Speed Demon" },
    { function(t) return t.speed ~= nil and t.speed <= 30 and t.variety <= 30 end, "Patient Specialist" },
    { function(t) return t.variety <= 30 end, "Deep Specialist" },
    { function(t) return t.rhythm <= 30 end, "Weekend Binge Reader" },
    { function(t) return t.variety > 60 end, "Curious Explorer" },
    { function(t) return t.rhythm > 60 end, "Steady Habit Reader" },
}

-- avg_pages, genres (distinct), books (finished), ratio (days read / days),
-- peak_hour (0-23), pph (pages an hour, or nil).
function DNA.compute(avg_pages, genres, books, ratio, peak_hour, pph)
    local t = {
        length = DNA.lengthScore(avg_pages or 0),
        variety = DNA.varietyScore(genres or 0, books or 0),
        rhythm = DNA.rhythmScore(ratio or 0),
        time = DNA.timeScore(peak_hour or 12),
        time_label = timeLabel(peak_hour or 12),
        speed = pph and DNA.speedScore(pph) or nil,
    }
    local archetype = "Avid Reader"
    for _i, a in ipairs(ARCHETYPES) do
        if a[1](t) then archetype = a[2]; break end
    end
    return {
        archetype = archetype,
        books = books or 0,
        rows = {
            { key = "length", score = t.length, label = lengthLabel(t.length) },
            { key = "variety", score = t.variety, label = varietyLabel(t.variety) },
            { key = "rhythm", score = t.rhythm, label = rhythmLabel(t.rhythm) },
            { key = "time", score = t.time, label = t.time_label },
            { key = "speed", score = t.speed or 0, label = t.speed and speedLabel(t.speed) or nil },
        },
    }
end

-- The finished books' part, from the library index: { books, avg_pages,
-- genres }. Books without a page count are left out of the average.
function DNA.fromBooks(finished)
    local n, pages, counted, seen, genres = 0, 0, 0, {}, 0
    for _i, b in ipairs(finished or {}) do
        n = n + 1
        local p = tonumber(b.pages) or tonumber(b.koreader_pages)
        if p and p > 0 then pages, counted = pages + p, counted + 1 end
        for _j, g in ipairs(type(b.genres) == "table" and b.genres or {}) do
            local key = tostring(g):lower()
            if not seen[key] then seen[key] = true; genres = genres + 1 end
        end
    end
    return { books = n, avg_pages = counted > 0 and pages / counted or 0, genres = genres }
end

-- The share of the last `days` days of the heatmap with any reading.
function DNA.ratio(heatmap, days)
    days = days or 182
    local today = 0
    for i = 1, 400 do if heatmap and heatmap[i] ~= nil then today = i end end
    if today == 0 then return 0 end
    local read, counted = 0, 0
    for i = math.max(1, today - days + 1), today do
        counted = counted + 1
        if (heatmap[i] or 0) > 0 then read = read + 1 end
    end
    return counted > 0 and read / counted or 0
end

-- The hour with most minutes (0-23), or nil when nothing was read.
function DNA.peakHour(minutes)
    local best, best_m = nil, 0
    for i = 1, 24 do
        local m = minutes and minutes[i] or 0
        if m > best_m then best, best_m = i - 1, m end
    end
    return best
end

return DNA
