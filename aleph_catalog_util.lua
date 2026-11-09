-- Modified for Aleph, 2026-11-07. Unofficial local-only fork. See NOTICE.
local T = require("ffi/util").template
local _ = require("gettext")
local CatalogUtil = {}
local function parseIsoTimestamp(value)
    if type(value) ~= "string" then return nil end
    local year, month, day, hour, min, sec = value:match("^(%d%d%d%d)-(%d%d)-(%d%d)T(%d%d):(%d%d):(%d%d)")
    if not year then return nil end
    local as_local = os.time({
        year = tonumber(year),
        month = tonumber(month),
        day = tonumber(day),
        hour = tonumber(hour),
        min = tonumber(min),
        sec = tonumber(sec),
    })
    if not as_local then return nil end
    -- The probe table must infer DST exactly like the parsed table above did
    -- (os.date("!*t") pins isdst=false, which skews zones currently in DST by
    -- an hour), so both conversions share the same offset.
    local probe = os.date("!*t")
    probe.isdst = nil
    local offset = os.time() - os.time(probe)
    return as_local + offset
end

-- A coarse relative label for a UTC timestamp: "just now", "12 min ago",
-- "3 h ago", "yesterday", "5 days ago". Nil when the value cannot be parsed.
function CatalogUtil.formatRelativeTime(value, now)
    local timestamp = parseIsoTimestamp(value)
    if not timestamp then return nil end
    now = now or os.time()
    local delta = now - timestamp
    if delta < 0 then delta = 0 end
    if delta < 60 then
        return _("just now")
    end
    if delta < 3600 then
        return T(_("%1 min ago"), math.floor(delta / 60))
    end
    if delta < 86400 then
        return T(_("%1 h ago"), math.floor(delta / 3600))
    end
    local days = math.floor(delta / 86400)
    if days == 1 then
        return _("yesterday")
    end
    return T(_("%1 days ago"), days)
end

function CatalogUtil.readingStreakDays(dashboard, fallback)
    local reading_streak = dashboard and dashboard.readingStreak
    local current_streak = reading_streak and tonumber(reading_streak.currentStreak)
    if current_streak then return current_streak end
    return tonumber(fallback) or 0
end


return CatalogUtil
