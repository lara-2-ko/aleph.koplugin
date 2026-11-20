-- Modified for Aleph, 2026-11-07. Unofficial local-only fork. See NOTICE.
--[[--
Read-only access to KOReader's statistics.sqlite3.

One-shot helpers open a short-lived connection; the sweep instead holds a
session for its whole run through openSession(), reusing one connection and its
prepared statements. Every query runs in autocommit and no transaction is ever
opened, so a chunked phase can yield between queries without blocking the
statistics plugin's writes or WAL checkpointing. The statistics plugin owns all
writes to this database.
]]

local DataStorage = require("datastorage")
local lfs = require("libs/libkoreader-lfs")
local SQ3 = require("lua-ljsqlite3/init")
local logger = require("logger")

local unpack = table.unpack or unpack

local StatsReader = {}

local BUSY_TIMEOUT_MS = 1000
-- One cached statement per shape. The event query's shape varies with the
-- number of statistics rows a book has, so the cache is bounded and anything
-- beyond it runs as a transient statement.
local MAX_CACHED_STATEMENTS = 16

local BOOK_BY_MD5_SQL = "SELECT id, title, authors, last_open FROM book WHERE md5 = ?;"
local BOOK_IDS_SQL = "SELECT id FROM book WHERE md5 = ?;"

local function metadataKey(title, authors)
    return (title or "") .. "\0" .. (authors or "")
end

local function applyRow(entry, id, title, authors, last_open)
    if title == "" then title = nil end
    if authors == "" then authors = nil end
    table.insert(entry.ids, id)
    table.insert(entry.rows, {
        id = id,
        title = title,
        authors = authors,
        last_open = last_open,
    })
    if not entry._variant_seen[metadataKey(title, authors)] then
        entry._variant_seen[metadataKey(title, authors)] = true
        entry._variant_count = entry._variant_count + 1
    end
    if last_open > (entry.last_open or 0) then
        entry.last_open = last_open
        if title then entry.title = title end
        if authors then entry.authors = authors end
    end
    if not entry.title and title then entry.title = title end
    if not entry.authors and authors then entry.authors = authors end
end

local function finalizeEntry(entry)
    entry.metadata_ambiguous = (entry._variant_count or 0) > 1
    entry.stats_ambiguous = #entry.ids > 1
    entry._variant_seen = nil
    entry._variant_count = nil
    return entry
end

local function dbPath()
    return DataStorage:getSettingsDir() .. "/statistics.sqlite3"
end

local function openConn()
    local ok, conn = pcall(SQ3.open, dbPath(), "ro")
    if not ok or not conn then
        logger.dbg("Aleph: cannot open statistics.sqlite3:", conn)
        return nil
    end
    pcall(conn.set_busy_timeout, conn, BUSY_TIMEOUT_MS)
    return conn
end

local Session = {}
Session.__index = Session

-- Opens the shared read-only connection. A busy database is the expected
-- transient failure here, so one reopen is attempted before giving up.
function StatsReader.openSession()
    local conn = openConn() or openConn()
    if not conn then return nil, "open_failed" end
    return setmetatable({ conn = conn, statements = {}, statement_count = 0 }, Session)
end

function Session:close()
    for _, stmt in pairs(self.statements) do
        pcall(stmt.close, stmt)
    end
    self.statements = {}
    self.statement_count = 0
    if self.conn then
        pcall(self.conn.close, self.conn)
        self.conn = nil
    end
end

function Session:_reopen()
    self:close()
    self.conn = openConn()
    return self.conn ~= nil
end

function Session:_select(sql, params)
    local stmt = self.statements[sql]
    local transient = false
    if stmt then
        stmt:reset()
    else
        stmt = self.conn:prepare(sql)
        if self.statement_count < MAX_CACHED_STATEMENTS then
            self.statements[sql] = stmt
            self.statement_count = self.statement_count + 1
        else
            transient = true
        end
    end
    if params then
        stmt:bind(unpack(params))
    end
    local res = stmt:resultset("i")
    if transient then pcall(stmt.close, stmt) end
    return res
end

-- Returns the column-major result set, nil when the query matched no rows, or
-- nil plus an error when it failed after one reopen and retry.
function Session:select(sql, params)
    if not self.conn then return nil, "closed" end
    local ok, res = pcall(self._select, self, sql, params)
    if ok then return res end
    logger.dbg("Aleph: statistics query failed, reopening:", res)
    if not self:_reopen() then return nil, "open_failed" end
    local retried, retry_res = pcall(self._select, self, sql, params)
    if retried then return retry_res end
    logger.dbg("Aleph: statistics query failed:", retry_res)
    return nil, "query_failed"
end

function Session:book(md5)
    if type(md5) ~= "string" or not md5:match("^%x+$") then return nil end
    local res = self:select(BOOK_BY_MD5_SQL, { md5 })
    if not res then return nil end
    local book = { ids = {}, rows = {}, last_open = 0, _variant_seen = {}, _variant_count = 0 }
    for i = 1, #res[1] do
        applyRow(book, tonumber(res[1][i]), res[2][i], res[3][i], tonumber(res[4][i]) or 0)
    end
    if #book.ids == 0 then return nil end
    return finalizeEntry(book)
end

function Session:bookIds(md5)
    if type(md5) ~= "string" or not md5:match("^%x+$") then return {} end
    local ids = {}
    local res = self:select(BOOK_IDS_SQL, { md5 })
    if res then
        for i = 1, #res[1] do
            table.insert(ids, tonumber(res[1][i]))
        end
    end
    return ids
end

-- Seconds read per local day since `since`, in one grouped query. Each event
-- is capped at a day so a reader left open overnight does not count as hours.
function Session:dailySeconds(since)
    local by_day = {}
    local res = self:select(
        "SELECT date(start_time, 'unixepoch', 'localtime'), COALESCE(SUM(MIN(duration, 86400)), 0)"
            .. " FROM page_stat_data WHERE start_time >= ? GROUP BY 1;",
        { since })
    if res then
        for i = 1, #res[1] do
            by_day[res[1][i]] = tonumber(res[2][i]) or 0
        end
    end
    return by_day
end

-- Aleph modification, 2026-11-18: pages read since each of two times (a
-- page counted once per book however often it was turned to), for the
-- Monthly challenge and Year projection widgets.
function Session:pagesSince(a, b)
    local first = math.min(a, b)
    local res = self:select(
        "SELECT COUNT(DISTINCT CASE WHEN start_time >= ? THEN id_book || ':' || page END),"
            .. " COUNT(DISTINCT CASE WHEN start_time >= ? THEN id_book || ':' || page END)"
            .. " FROM page_stat_data WHERE start_time >= ?;",
        { a, b, first })
    if not res then return { 0, 0 } end
    return { tonumber(res[1][1]) or 0, tonumber(res[2][1]) or 0 }
end

-- Minutes read in each local hour of the day since `since`, as 24 values for
-- hours 0 to 23. Each event is capped at ten minutes, as for pace.
function Session:hourMinutes(since)
    local minutes = {}
    for i = 1, 24 do minutes[i] = 0 end
    local res = self:select(
        "SELECT CAST(strftime('%H', start_time, 'unixepoch', 'localtime') AS INTEGER), COALESCE(SUM(MIN(duration, 600)), 0)"
            .. " FROM page_stat_data WHERE start_time >= ? GROUP BY 1;",
        { since })
    if res then
        for i = 1, #res[1] do
            local hour = tonumber(res[1][i])
            if hour and hour >= 0 and hour < 24 then
                minutes[hour + 1] = math.floor((tonumber(res[2][i]) or 0) / 60 + 0.5)
            end
        end
    end
    return minutes
end

-- Aleph modification, 2026-11-20: all the time read on this device, for the
-- Hours read widget: seconds in all and since `year_start`, the books read
-- in and when the first page was turned. Each page capped at ten minutes,
-- as for When you read, so a book left open does not count as hours.
function Session:totalTime(year_start)
    local res = self:select(
        "SELECT COALESCE(SUM(MIN(duration, 600)), 0),"
            .. " COALESCE(SUM(CASE WHEN start_time >= ? THEN MIN(duration, 600) ELSE 0 END), 0),"
            .. " COUNT(DISTINCT id_book), MIN(start_time) FROM page_stat_data;",
        { year_start })
    if not res then return nil end
    return {
        seconds = tonumber(res[1][1]) or 0,
        year_seconds = tonumber(res[2][1]) or 0,
        books = tonumber(res[3][1]) or 0,
        first = tonumber(res[4][1]),
    }
end

-- Aleph modification, 2026-11-20: each month of a year, for the Time read and
-- Books and pages widgets: seconds read (each page capped at ten minutes, as
-- for Hours read) and pages read (a page counted once per book and month).
-- Two lists of 12, January first.
function Session:monthStats(year_start, year_end)
    local seconds, pages = {}, {}
    for m = 1, 12 do seconds[m], pages[m] = 0, 0 end
    local res = self:select(
        "SELECT CAST(strftime('%m', start_time, 'unixepoch', 'localtime') AS INTEGER),"
            .. " COALESCE(SUM(MIN(duration, 600)), 0), COUNT(DISTINCT id_book || ':' || page)"
            .. " FROM page_stat_data WHERE start_time >= ? AND start_time < ? GROUP BY 1;",
        { year_start, year_end })
    if res then
        for i = 1, #res[1] do
            local m = tonumber(res[1][i])
            if m and m >= 1 and m <= 12 then
                seconds[m] = tonumber(res[2][i]) or 0
                pages[m] = tonumber(res[3][i]) or 0
            end
        end
    end
    return { seconds = seconds, pages = pages }
end

-- Every page turn this device has recorded: the total, the turns since
-- `today_start`, and when the first was. One pass over the table.
function Session:pageTurns(today_start)
    local res = self:select(
        "SELECT COUNT(*), COALESCE(SUM(CASE WHEN start_time >= ? THEN 1 ELSE 0 END), 0), MIN(start_time) FROM page_stat_data;",
        { today_start })
    if not res then return { total = 0, today = 0 } end
    return {
        total = tonumber(res[1][1]) or 0,
        today = tonumber(res[2][1]) or 0,
        first = tonumber(res[3][1]),
    }
end

-- Reading sessions since `since`: page events grouped into a session until a
-- gap of more than ten minutes. Returns the session count, the longest and
-- average session in seconds and the pages turned per hour, or nil when
-- there is no reading. One pass over the period's events.
function Session:sessionRecords(since)
    local res = self:select([[
        WITH ev AS (
            SELECT start_time AS s, MIN(duration, 600) AS d,
                CASE WHEN start_time - LAG(start_time + MIN(duration, 600)) OVER (ORDER BY start_time) <= 600 THEN 0 ELSE 1 END AS brk
            FROM page_stat_data WHERE start_time >= ?
        ), grouped AS (
            SELECT d, SUM(brk) OVER (ORDER BY s ROWS UNBOUNDED PRECEDING) AS g FROM ev
        ), sessions AS (
            SELECT SUM(d) AS secs, COUNT(*) AS pages FROM grouped GROUP BY g
        )
        SELECT COUNT(*), COALESCE(MAX(secs), 0), COALESCE(AVG(secs), 0), COALESCE(SUM(pages), 0), COALESCE(SUM(secs), 0)
        FROM sessions WHERE secs >= 60;]], { since })
    if not res then return nil end
    local count = tonumber(res[1][1]) or 0
    if count == 0 then return nil end
    local total = tonumber(res[5][1]) or 0
    return {
        sessions = count,
        longest_seconds = tonumber(res[2][1]) or 0,
        average_seconds = tonumber(res[3][1]) or 0,
        pages_per_hour = total > 0 and (tonumber(res[4][1]) or 0) * 3600 / total or 0,
    }
end

-- How fast one book is being read: seconds per page from its own events, the
-- page count it was last read at, and seconds read over the last `days` days.
-- KOReader's own longest time counted on one page (its statistics
-- settings, "max_sec"; 120 seconds unless changed).
local function maxSecondsPerPage()
    local max_sec
    pcall(function()
        local st = G_reader_settings:readSetting("statistics")
        max_sec = type(st) == "table" and tonumber(st.max_sec) or nil
    end)
    return (max_sec and max_sec > 0) and max_sec or 120
end
StatsReader.maxSecondsPerPage = maxSecondsPerPage

-- How fast this book is read, worked out as KOReader's statistics do for the
-- time left in its status bar (ReaderStatistics avg_time): the time on each
-- page of the book's present layout (the page_stat view), each page counted
-- at most max_sec, over the pages read; and the book's page count in that
-- layout. So Home's time left is the one the book shows when it opens.
-- recent_seconds: the reading of the last `days` days, for the finish day.
function Session:bookPace(ids, days)
    if not ids or #ids == 0 then return nil end
    local marks = {}
    for _ = 1, #ids do table.insert(marks, "?") end
    local id_list = table.concat(marks, ",")
    local max_sec = maxSecondsPerPage()
    local seconds, pages, total_pages
    local capped = self:select(
        "SELECT COUNT(*), COALESCE(SUM(durations), 0) FROM (SELECT MIN(SUM(duration), " .. max_sec .. ") AS durations"
            .. " FROM page_stat WHERE id_book IN (" .. id_list .. ") GROUP BY id_book, page);", ids)
    if capped and tonumber(capped[1][1]) then
        pages = tonumber(capped[1][1]) or 0
        seconds = tonumber(capped[2][1]) or 0
        local count = self:select("SELECT MAX(pages) FROM book WHERE id IN (" .. id_list .. ");", ids)
        total_pages = count and tonumber(count[1][1]) or 0
    else
        -- A statistics database without the page_stat view (very old):
        -- the raw events, each counted at most max_sec.
        local totals = self:select(
            "SELECT COALESCE(SUM(MIN(duration, " .. max_sec .. ")), 0), COUNT(DISTINCT page), MAX(total_pages)"
                .. " FROM page_stat_data WHERE id_book IN (" .. id_list .. ");", ids)
        if not totals then return nil end
        seconds = tonumber(totals[1][1]) or 0
        pages = tonumber(totals[2][1]) or 0
        total_pages = tonumber(totals[3][1]) or 0
    end
    local params = {}
    for _, id in ipairs(ids) do table.insert(params, id) end
    table.insert(params, os.time() - (days or 14) * 86400)
    local recent = self:select(
        "SELECT COALESCE(SUM(MIN(duration, 600)), 0), MIN(start_time) FROM page_stat_data WHERE id_book IN ("
            .. id_list .. ") AND start_time >= ?;", params)
    return {
        seconds_per_page = pages > 0 and seconds / pages or nil,
        total_pages = total_pages,
        recent_seconds = recent and tonumber(recent[1][1]) or 0,
        -- Aleph modification, 2026-11-20: when the book was first read in
        -- those days (a book started three days ago has three days of pace).
        recent_first = recent and tonumber(recent[2][1]) or nil,
    }
end

local function withSession(fn)
    local session = StatsReader.openSession()
    if not session then return nil, "open_failed" end
    local ok, result = pcall(fn, session)
    session:close()
    if not ok then
        logger.dbg("Aleph: statistics query failed:", result)
        return nil, "query_failed"
    end
    return result
end

-- Aleph, 2026-11-09: answers kept until KOReader's statistics database
-- changes (its file or its write-ahead log), so opening the board, the
-- streak and the forecast again do not query the whole history again.
local memo = { stamp = nil, results = {}, count = 0 }
local MEMO_MAX = 24

local function dbStamp()
    local path = dbPath()
    local a = lfs.attributes(path) or {}
    local w = lfs.attributes(path .. "-wal") or {}
    return table.concat({ a.modification or 0, a.size or 0, w.modification or 0, w.size or 0 }, ":")
end

local function remembered(key, compute)
    local stamp = dbStamp()
    if memo.stamp ~= stamp then memo = { stamp = stamp, results = {}, count = 0 } end
    local hit = memo.results[key]
    if hit ~= nil then return hit or nil end
    local value = compute()
    if memo.count >= MEMO_MAX then memo.results, memo.count = {}, 0 end
    -- false stands for "asked, nothing there"; a failed query (nil) is not kept.
    if value ~= nil then memo.results[key] = value; memo.count = memo.count + 1 end
    return value
end

function StatsReader.forget()
    memo = { stamp = nil, results = {}, count = 0 }
end

function StatsReader.getDailySeconds(since)
    return remembered("daily:" .. tostring(since), function()
        return withSession(function(session) return session:dailySeconds(since) end)
    end)
end

function StatsReader.getHourMinutes(since)
    return remembered("hours:" .. tostring(since), function()
        return withSession(function(session) return session:hourMinutes(since) end)
    end)
end

function StatsReader.getPageTurns(today_start)
    return remembered("turns:" .. tostring(today_start), function()
        return withSession(function(session) return session:pageTurns(today_start) end)
    end)
end

function StatsReader.getTotalTime(year_start)
    return remembered("total:" .. tostring(year_start), function()
        return withSession(function(session) return session:totalTime(year_start) end)
    end)
end

function StatsReader.getMonthStats(year_start, year_end)
    return remembered("months:" .. tostring(year_start), function()
        return withSession(function(session) return session:monthStats(year_start, year_end) end)
    end)
end

function StatsReader.getPagesSince(a, b)
    return remembered("pages:" .. tostring(a) .. ":" .. tostring(b), function()
        return withSession(function(session) return session:pagesSince(a, b) end)
    end)
end

function StatsReader.getSessionRecords(since)
    return remembered("records:" .. tostring(since), function()
        return withSession(function(session) return session:sessionRecords(since) end)
    end)
end

function StatsReader.getBookPace(md5, days)
    return remembered("pace:" .. tostring(md5) .. ":" .. tostring(days), function()
        return withSession(function(session) return session:bookPace(session:bookIds(md5), days) end)
    end)
end

return StatsReader
