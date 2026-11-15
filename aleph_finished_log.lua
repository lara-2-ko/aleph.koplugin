-- Aleph modification, 2026-11-11: a record of the books finished, kept when
-- the book itself is deleted.
--[[--
Aleph counted the books finished this year (the yearly goal, Goal pace,
Finished this year) from the library: books on the device marked Finished.
A reader who deletes each book once it is read (KOReader deletes its sidecar,
with its status, at the same time) saw those counts go down again.

Here every book seen finished is written to a file of its own,
settings/aleph_finished.lua, with what the board needs to show it: title,
authors, series, the day it was finished, rating, format, and the path, date
and size that find its saved cover thumbnail. An entry stays when the book's
file is gone. While the book is still on the device its own status decides:
marking it unread or reading again takes it off the list.

Books are told apart by KOReader's partial MD5 when the sidecar has one
(the same book moved or renamed stays one entry), else by path.
]]

local try = require("aleph_try").call
local Log = {}

local FILE = "/aleph_finished.lua"
local store

local function open()
    if store then return store end
    local DataStorage = require("datastorage")
    local LuaSettings = require("luasettings")
    store = LuaSettings:open(DataStorage:getSettingsDir() .. FILE)
    return store
end

-- For tests: start again from the file (or another store).
function Log._reset(s) store = s end

local function entries()
    local s = open()
    local books = s:readSetting("books")
    if type(books) ~= "table" then books = {}; s:saveSetting("books", books) end
    return books
end

local function keyOf(book)
    if type(book.md5) == "string" and book.md5 ~= "" then return "md5:" .. book.md5 end
    return "path:" .. tostring(book.path)
end
Log.keyOf = keyOf

local function finishedDay(book)
    local day = type(book.finishedOn) == "string" and book.finishedOn:match("^(%d%d%d%d%-%d%d%-%d%d)")
    return day
end

local FIELDS = { "title", "series", "seriesIndex", "rating", "format", "path", "md5", "modified", "size", "pages" }

local function entryOf(book, day)
    local e = { finished = day, authors = {} }
    for _i, k in ipairs(FIELDS) do e[k] = book[k] end
    for i, a in ipairs(book.authors or {}) do e.authors[i] = a end
    return e
end

local function same(a, b)
    if not a then return false end
    for _i, k in ipairs(FIELDS) do if a[k] ~= b[k] then return false end end
    if a.finished ~= b.finished or #(a.authors or {}) ~= #b.authors then return false end
    for i, x in ipairs(b.authors) do if a.authors[i] ~= x then return false end end
    return true
end

-- Brings the record in line with `books` (the library as now scanned):
-- finished books written in, books on the device no longer finished taken
-- out. Entries of books that are gone are kept. Saved only when something
-- changed. Returns whether it did.
function Log.sync(books)
    local list = entries()
    local changed = false
    for _i, b in ipairs(books or {}) do
        local key = keyOf(b)
        local day = b.readStatus == "read" and finishedDay(b)
        if day then
            local e = entryOf(b, day)
            if not same(list[key], e) then list[key] = e; changed = true end
            -- The same book under its path before its MD5 was known.
            local by_path = "path:" .. tostring(b.path)
            if key ~= by_path and list[by_path] then list[by_path] = nil; changed = true end
        elseif list[key] then
            list[key] = nil
            changed = true
        end
    end
    if changed then
        local s = open()
        s:saveSetting("books", list)
        s:flush()
    end
    return changed
end

-- One book changed by hand (its status set in Aleph).
function Log.update(book)
    return Log.sync({ book })
end

-- The book open in the reader, as it closes: a book finished and deleted
-- straight from the file browser, before Aleph's library saw it finished,
-- is on the record too.
function Log.fromReader(ui)
    local ds = ui and ui.doc_settings
    local file = ui and ui.document and ui.document.file
    if not (ds and file) then return false end
    local summary = ds:readSetting("summary") or {}
    local props = ui.doc_props or ds:readSetting("doc_props") or {}
    local authors = {}
    if type(props.authors) == "table" then authors = props.authors
    elseif type(props.authors) == "string" then
        for a in props.authors:gmatch("[^\n]+") do authors[#authors + 1] = a end
    end
    local book = {
        path = file, md5 = ds:readSetting("partial_md5_checksum"),
        title = (props.title and props.title ~= "" and props.title) or props.display_title or file:match("([^/]+)$"),
        authors = authors, series = props.series, seriesIndex = tonumber(props.series_index),
        rating = tonumber(summary.rating), format = (file:match("%.([^%.]+)$") or ""):upper(),
        readStatus = summary.status == "complete" and "read" or "reading",
        finishedOn = summary.status == "complete" and summary.modified or nil,
    }
    try(function()
        local attr = require("libs/libkoreader-lfs").attributes(file)
        if attr then book.modified, book.size = attr.modification, attr.size end
    end)
    -- Only a finished book is written here; unfinishing is left to the
    -- library scan, which sees every book's status.
    if book.readStatus ~= "read" then return false end
    return Log.update(book)
end

-- The finished books whose file is no longer in the library, as books the
-- board can show: { id, title, authors, finishedOn, removed = true, ... }.
-- present: the library's books.
function Log.removed(present)
    local paths, md5s = {}, {}
    for _i, b in ipairs(present or {}) do
        paths[b.path] = true
        if b.md5 then md5s[b.md5] = true end
    end
    local out = {}
    local idx
    for key, e in pairs(entries()) do
        -- A book imported from Goodreads that is on the device since counts
        -- once, as the device's book.
        local here = false
        if type(e) == "table" and e.source == "goodreads" then
            try(function()
                local Import = require("aleph_goodreads_import")
                if not idx then
                    -- Kept while the library is the same list of books.
                    local c = Log._index_cache
                    if c and c.list == present and c.n == #(present or {}) then idx = c.idx
                    else
                        idx = Import.index(present)
                        Log._index_cache = { list = present, n = #(present or {}), idx = idx }
                    end
                end
                here = Import.find(idx, e) ~= nil
            end)
        end
        if type(e) == "table" and e.finished and not here and not (e.path and paths[e.path]) and not (e.md5 and md5s[e.md5]) then
            local b = {
                id = "finished-log:" .. key, key = key, removed = true,
                title = e.title or (e.path and e.path:match("([^/]+)$")) or "?",
                authors = e.authors or {}, series = e.series, seriesIndex = e.seriesIndex,
                rating = e.rating, format = e.format, pages = e.pages, source = e.source,
                path = e.path, md5 = e.md5, modified = e.modified, size = e.size,
                readStatus = "read", finishedOn = e.finished, progressPercentage = 100,
                genres = {}, highlights = {}, cover_checked = true,
            }
            -- Its cover, if Aleph saved a thumbnail while the book was here.
            try(function() b.cover_path = require("aleph_local").cachedCover(b) end)
            out[#out + 1] = b
        end
    end
    table.sort(out, function(a, b)
        if a.finishedOn ~= b.finishedOn then return a.finishedOn > b.finishedOn end
        return a.title < b.title
    end)
    return out
end

-- Every entry, key -> entry (read only).
function Log.all() return entries() end

-- Books read elsewhere, from Goodreads' export (aleph_goodreads_import.lua):
-- key "goodreads:<id>" -> { finished, title, authors, rating, pages, source }.
-- Written over the same keys when imported again.
function Log.addImported(list)
    local all = entries()
    local n = 0
    for key, e in pairs(list or {}) do
        if type(e) == "table" and e.finished then all[key] = e; n = n + 1 end
    end
    if n > 0 then
        local s = open()
        s:saveSetting("books", all)
        s:flush()
    end
    return n
end

-- Forgets a removed book (from its page: "Remove from the record").
function Log.forget(key)
    local list = entries()
    if list[key] == nil then return false end
    list[key] = nil
    local s = open()
    s:saveSetting("books", list)
    s:flush()
    return true
end

return Log
