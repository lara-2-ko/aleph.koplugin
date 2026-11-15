-- Aleph modification, 2026-11-15: dates in KOReader's language.
--[[--
os.date writes month and day names in English whatever KOReader's language.
These take the names from KOReader's own translated tables (datetime) and
the order of the parts from Aleph's catalogue (aleph_gettext), so a date
reads "15 de nov." in Portuguese and "Nov 15" in English.
]]

local _ = require("aleph_gettext")
local function T(fmt, ...)
    local args = { ... }
    return (fmt:gsub("%%(%d)", function(i) local v = args[tonumber(i)]; return v ~= nil and tostring(v) or "" end))
end

local D = {}

local function dt()
    local ok, datetime = pcall(require, "datetime")
    return ok and datetime or {}
end

function D.shortWeekday(t)
    local short = os.date("%a", t)
    local tr = dt().shortDayOfWeekTranslation
    local v = type(tr) == "table" and tr[short]
    return type(v) == "string" and v or short
end

function D.longWeekday(t)
    local short = os.date("%a", t)
    local tr = dt().shortDayOfWeekToLongTranslation
    local v = type(tr) == "table" and tr[short]
    return type(v) == "string" and v or short
end

function D.shortMonth(t)
    local short = os.date("%b", t)
    local tr = dt().shortMonthTranslation
    local v = type(tr) == "table" and tr[short]
    return type(v) == "string" and v or short
end

function D.longMonth(t)
    local long = os.date("%B", t)
    local tr = dt().longMonthTranslation
    local v = type(tr) == "table" and tr[long]
    return type(v) == "string" and v or long
end

local function day(t) return tonumber(os.date("%d", t)) end
local function year(t) return os.date("%Y", t) end

-- "Nov 15"
function D.monthDay(t)
    return T(_.pgettext("Date: short month, day", "%1 %2"), D.shortMonth(t), day(t))
end

-- "Nov 2026"
function D.monthYear(t)
    return T(_.pgettext("Date: short month, year", "%1 %2"), D.shortMonth(t), year(t))
end

-- "Nov 15, 2026"
function D.monthDayYear(t)
    return T(_.pgettext("Date: short month, day, year", "%1 %2, %3"), D.shortMonth(t), day(t), year(t))
end

-- "15 November 2026"
function D.dayMonthYear(t)
    return T(_.pgettext("Date: day, long month, year", "%1 %2 %3"), day(t), D.longMonth(t), year(t))
end

-- "12 Mar 2024"
function D.dayMonthYearShort(t)
    return T(_.pgettext("Date: day, short month, year", "%1 %2 %3"), day(t), D.shortMonth(t), year(t))
end

-- "15 Nov"
function D.dayMonth(t)
    return T(_.pgettext("Date: day, short month", "%1 %2"), day(t), D.shortMonth(t))
end

-- "15 November"
function D.dayLongMonth(t)
    return T(_.pgettext("Date: day, long month", "%1 %2"), day(t), D.longMonth(t))
end

-- "Sun 15 Nov"
function D.weekdayDayMonth(t)
    return T(_.pgettext("Date: short weekday, day, short month", "%1 %2 %3"), D.shortWeekday(t), day(t), D.shortMonth(t))
end

-- A time for "2026-11-15" (noon, so no time zone moves it to another day).
function D.fromISO(iso)
    local y, m, d = tostring(iso or ""):match("^(%d%d%d%d)%-(%d%d)%-(%d%d)")
    if not y then return nil end
    return os.time{ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 }
end

return D
