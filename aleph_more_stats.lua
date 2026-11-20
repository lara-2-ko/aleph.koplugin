-- Aleph modification, 2026-11-18: four more widgets after BookOrbit's.
--[[--
Monthly challenge, Reading rhythm, Year projection and Diversity score,
after BookOrbit 3.8.0's widgets of those names (rules from its
server/src/modules/dashboard/dashboard-widget.calculations.ts and
dashboard-widget.repository.ts), fed from this device: the library index
(finished books with their day, pages, genres, authors, language and
year; books in progress), KOReader's statistics (the year's minutes by
day, and pages read since a time).

  Monthly challenge   one a month, chosen from those that suit how you read
                      (BookOrbit's six), the same all month:
                        Quick Read       finish a book under 200 pages
                                         (when your books average over 250)
                        Genre Explorer   finish a book in a genre you had not
                                         finished before (fewer than 5
                                         genres in the last 6 months)
                        Clear the Backlog  finish a book this month (a book
                                         in progress untouched for 6 months)
                        Streak Builder   read 5 days in a row this month
                                         (not done yet this month)
                        New Voice        finish a book by an author you had
                                         not finished before (an author
                                         with more than 3 finished)
                        Page Turner      read 500 pages this month (always)
  Reading rhythm      the last 14 days: minutes each day, the days with
                      reading, the share of them (consistency), the average
  Year projection     at the last 30 days' pace: books by the end of the
                      year (finished so far plus the rest), pages and hours
                      over a year; up or down against the year's own pace
  Diversity score     the average of four: genres read of the library's,
                      authors per book, the span of release years (100
                      years = 100; only when years are known, from the
                      extra filters), languages (5 = 100). From 3 books.

BookOrbit counts any genre or author of a book finished this month for
Genre Explorer and New Voice; Aleph counts only new ones, as the challenges
say.
]]

local _ = require("aleph_gettext")

local M = {}

local function clamp(v) return math.max(0, math.min(100, math.floor(v + 0.5))) end

local function key(s) return tostring(s or ""):lower() end

-- A stable number from a text (the month): the same challenge all month.
local function seed(str)
    local h = 0
    for i = 1, #str do h = (h * 31 + str:byte(i)) % 2147483647 end
    return h
end

-- ------------------------------------------------------------ challenge
M.CHALLENGES = {
    { id = "short-read", target = 1,
      title = function() return _("Quick Read") end,
      desc = function() return _("Finish a book under 200 pages this month") end },
    { id = "genre-explorer", target = 1,
      title = function() return _("Genre Explorer") end,
      desc = function() return _("Finish a book in a genre new to you this month") end },
    { id = "finish-oldest", target = 1,
      title = function() return _("Clear the Backlog") end,
      desc = function() return _("Finish a book you have been reading for a while") end },
    { id = "streak-builder", target = 5,
      title = function() return _("Streak Builder") end,
      desc = function() return _("Read 5 days in a row this month") end },
    { id = "new-author", target = 1,
      title = function() return _("New Voice") end,
      desc = function() return _("Finish a book by an author new to you this month") end },
    { id = "page-milestone", target = 500,
      title = function() return _("Page Turner") end,
      desc = function() return _("Read 500 pages this month") end },
}
local BY_ID = {}
for _i, c in ipairs(M.CHALLENGES) do BY_ID[c.id] = c end

local function pagesOf(b) return tonumber(b.pages) or tonumber(b.koreader_pages) end

-- The longest run of reading days in `flags` (a list of booleans).
local function longestRun(flags)
    local best, run = 0, 0
    for _i, f in ipairs(flags) do
        if f then run = run + 1; best = math.max(best, run) else run = 0 end
    end
    return best
end

-- finished: books with finishedOn ("YYYY-MM-DD"), pages, genres, authors.
-- reading: books in progress with last_open. month_days: this month's
-- days so far, true where read. pages_month: pages read this month.
-- now: the time. Returns { id, title, desc, progress, target, done }.
-- chosen: the challenge already chosen for this month (kept, so it does
-- not change as the month goes on), or nil to choose it.
function M.challenge(finished, reading, month_days, pages_month, now, chosen)
    now = now or os.time()
    local month = os.date("%Y-%m", now)
    local six = os.date("%Y-%m-%d", now - 182 * 86400)
    local stale_before = now - 182 * 86400
    local pages_sum, pages_n = 0, 0
    local genres6, genres6_n = {}, 0
    local before_genres, before_authors, author_books = {}, {}, {}
    local month_books = {}
    for _i, b in ipairs(finished or {}) do
        local day = type(b.finishedOn) == "string" and b.finishedOn or ""
        local p = pagesOf(b)
        if p and p > 0 then pages_sum, pages_n = pages_sum + p, pages_n + 1 end
        if day >= six then
            for _j, g in ipairs(b.genres or {}) do
                if not genres6[key(g)] then genres6[key(g)] = true; genres6_n = genres6_n + 1 end
            end
        end
        for _j, a in ipairs(b.authors or {}) do author_books[key(a)] = (author_books[key(a)] or 0) + 1 end
        if day:sub(1, 7) == month then
            month_books[#month_books + 1] = b
        else
            for _j, g in ipairs(b.genres or {}) do before_genres[key(g)] = true end
            for _j, a in ipairs(b.authors or {}) do before_authors[key(a)] = true end
        end
    end
    local top_author = 0
    for _a, n in pairs(author_books) do top_author = math.max(top_author, n) end
    local stale = 0
    for _i, b in ipairs(reading or {}) do
        if (tonumber(b.last_open) or 0) > 0 and b.last_open < stale_before then stale = stale + 1 end
    end
    local streak = longestRun(month_days or {})
    local eligible = {}
    if pages_n > 0 and pages_sum / pages_n > 250 then eligible[#eligible + 1] = "short-read" end
    if genres6_n < 5 then eligible[#eligible + 1] = "genre-explorer" end
    if stale > 0 then eligible[#eligible + 1] = "finish-oldest" end
    if streak < 5 then eligible[#eligible + 1] = "streak-builder" end
    if top_author > 3 then eligible[#eligible + 1] = "new-author" end
    eligible[#eligible + 1] = "page-milestone"
    local id = (chosen and BY_ID[chosen]) and chosen or eligible[seed(month) % #eligible + 1]
    -- Progress this month.
    local current = 0
    if id == "short-read" then
        for _i, b in ipairs(month_books) do
            local p = pagesOf(b)
            if p and p < 200 then current = current + 1 end
        end
    elseif id == "genre-explorer" then
        local new = {}
        for _i, b in ipairs(month_books) do
            for _j, g in ipairs(b.genres or {}) do
                if not before_genres[key(g)] and not new[key(g)] then new[key(g)] = true; current = current + 1 end
            end
        end
    elseif id == "finish-oldest" then
        current = #month_books > 0 and 1 or 0
    elseif id == "streak-builder" then
        current = streak
    elseif id == "new-author" then
        local new = {}
        for _i, b in ipairs(month_books) do
            for _j, a in ipairs(b.authors or {}) do
                if not before_authors[key(a)] and not new[key(a)] then new[key(a)] = true; current = current + 1 end
            end
        end
    else
        current = pages_month or 0
    end
    local c = BY_ID[id]
    return { id = id, title = c.title(), desc = c.desc(), progress = math.min(current, c.target),
        target = c.target, done = current >= c.target }
end

-- --------------------------------------------------------------- rhythm
-- minutes: the last days' minutes, oldest first.
function M.rhythm(minutes)
    local n = #minutes
    if n == 0 then return { days = {}, active = 0, total = 0, percent = 0, avg = 0 } end
    local active, sum = 0, 0
    for _i, m in ipairs(minutes) do
        if m > 0 then active = active + 1 end
        sum = sum + m
    end
    return { days = minutes, active = active, total = n, percent = math.floor(active / n * 100 + 0.5),
        avg = math.floor(sum / n + 0.5) }
end

-- ----------------------------------------------------------- projection
-- ytd: books finished this year; recent_books, recent_pages, recent_hours:
-- the last 30 days'. now: the time.
function M.projection(ytd, recent_books, recent_pages, recent_hours, now)
    now = now or os.time()
    local t = os.date("*t", now)
    local day_of_year = t.yday
    local days_in_year = os.date("*t", os.time{ year = t.year, month = 12, day = 31, hour = 12 }).yday
    local remaining = days_in_year - day_of_year
    local per_day = recent_books / 30
    local books = math.max(ytd, math.floor(ytd + per_day * remaining + 0.5))
    -- Up or down: the last 30 days' pace against the year's so far.
    local year_pace = ytd / math.max(1, day_of_year)
    local trend = "steady"
    if day_of_year > 30 then
        if per_day > year_pace * 1.15 then trend = "up" elseif per_day < year_pace * 0.85 then trend = "down" end
    end
    return {
        books = books,
        pages = math.max(0, math.floor(recent_pages / 30 * days_in_year + 0.5)),
        hours = math.max(0, math.floor(recent_hours / 30 * days_in_year * 10 + 0.5) / 10),
        ytd = ytd, days_left = remaining, trend = trend,
    }
end

-- ------------------------------------------------------------ diversity
local function diversityLabel(score)
    if score <= 30 then return _.pgettext("Diversity", "Deep Specialist") end
    if score <= 55 then return _.pgettext("Diversity", "Comfortable Reader") end
    if score <= 75 then return _.pgettext("Diversity", "Curious Explorer") end
    return _.pgettext("Diversity", "Literary Adventurer")
end

-- finished: the finished books; library_genres: distinct genres in the
-- library. Era is left out of the average when no release year is known.
function M.diversity(finished, library_genres)
    local n = #(finished or {})
    local genres, authors, langs = {}, {}, {}
    local g_n, a_n, l_n = 0, 0, 0
    local lo, hi
    for _i, b in ipairs(finished or {}) do
        for _j, g in ipairs(b.genres or {}) do if not genres[key(g)] then genres[key(g)] = true; g_n = g_n + 1 end end
        for _j, a in ipairs(b.authors or {}) do if not authors[key(a)] then authors[key(a)] = true; a_n = a_n + 1 end end
        local lang = b.props and b.props.language
        if type(lang) == "string" and lang ~= "" then
            local code = key(lang):match("^(%a+)") or key(lang)
            if not langs[code] then langs[code] = true; l_n = l_n + 1 end
        end
        local y = tonumber(b.year)
        if y then lo, hi = math.min(lo or y, y), math.max(hi or y, y) end
    end
    local genre = (library_genres or 0) > 0 and clamp(g_n / library_genres * 100) or 0
    local author = n > 0 and clamp(a_n / n * 100) or 0
    local era = lo and clamp(hi - lo) or nil
    local language = clamp(l_n / 5 * 100)
    local parts = { genre, author, language }
    if era then parts[#parts + 1] = era end
    local sum = 0
    for _i, v in ipairs(parts) do sum = sum + v end
    local score = math.floor(sum / #parts + 0.5)
    return { score = score, label = diversityLabel(score), genre = genre, author = author, era = era,
        language = language, books = n }
end

return M
