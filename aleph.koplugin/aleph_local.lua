-- Local library adapter. Sidecars and statistics are read-only; only our cache is written.
local lfs = require("libs/libkoreader-lfs")
local DocSettings = require("docsettings")
local Registry = require("document/documentregistry")
local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local util = require("util")
local Local = {}
Local.__index = Local

local function iso(t) return t and t > 0 and os.date("!%Y-%m-%dT%H:%M:%SZ", t) or nil end
local function names(value)
    if type(value) == "table" then return value end
    local out = {}
    for s in tostring(value or ""):gmatch("[^\n]+") do out[#out+1] = s end
    return out
end
-- Genres come from the book's tags: the keywords KOReader reads from the file
-- (EPUB subjects, which Calibre writes from its Tags column), or else the
-- subjects in a Calibre metadata.opf stored next to the book.
local function unescape(s)
    return (s:gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&quot;", '"'):gsub("&apos;", "'"):gsub("&amp;", "&"))
end
local function bookGenres(props, path)
    local out, seen = {}, {}
    local function add(s)
        s = util.trim(tostring(s or ""))
        local key = s:lower()
        if s ~= "" and not seen[key] then seen[key] = true; out[#out+1] = s end
    end
    local kw = props and props.keywords
    if type(kw) == "table" then
        for _, s in ipairs(kw) do add(s) end
    else
        for s in tostring(kw or ""):gmatch("[^\n;,]+") do add(s) end
    end
    if #out == 0 then
        local dir = path:match("^(.*)/[^/]*$")
        local opf = dir and (dir .. "/metadata.opf")
        if opf and lfs.attributes(opf, "mode") == "file" then
            local f = io.open(opf, "r")
            if f then
                local xml = f:read("*a") or ""
                f:close()
                for s in xml:gmatch("<dc:subject[^>]*>(.-)</dc:subject>") do add(unescape(s)) end
            end
        end
    end
    return out
end
local function hasGenre(book, wanted)
    wanted = wanted:lower()
    for _, g in ipairs(book.genres or {}) do
        if g:lower() == wanted then return true end
    end
    return false
end

function Local.new(settings, ui)
    local cache = LuaSettings:open(DataStorage:getSettingsDir() .. "/aleph_index.lua")
    return setmetatable({settings = settings, ui = ui, cache = cache,
        books = cache:readSetting("books", {}), errors = {}}, Local)
end

-- Where KOReader keeps the book's own settings (its sidecar) and when that
-- file last changed, as one string; "none" when the book has no sidecar.
local function sidecarStamp(path)
    local file
    pcall(function()
        if DocSettings.findSidecarFile then file = DocSettings:findSidecarFile(path)
        elseif DocSettings.getSidecarFile then file = DocSettings:getSidecarFile(path) end
    end)
    if type(file) ~= "string" then return "none" end
    local modified = lfs.attributes(file, "modification")
    return modified and (file .. "@" .. modified) or "none"
end
Local.sidecarStamp = sidecarStamp

-- What a scan compares to tell whether the board needs drawing again.
local function sameBook(a, b)
    return a.title == b.title and a.readStatus == b.readStatus and a.progressPercentage == b.progressPercentage
        and a.rating == b.rating and a.last_open == b.last_open and #(a.highlights or {}) == #(b.highlights or {})
        and a.series == b.series and a.seriesIndex == b.seriesIndex
end
Local.sameBook = sameBook

function Local:readBook(path, attr, history, old)
    local open_here = self.ui and self.ui.document and self.ui.document.file == path
    -- Neither the book nor its sidecar changed since the last scan: the entry
    -- stands as it is (reading a sidecar is the slow part of a scan).
    local stamp = not open_here and sidecarStamp(path) or nil
    if stamp and old and old.sidecar == stamp and old.modified == attr.modification and old.size == attr.size then
        old.last_open = history[path] or 0
        old.lastReadAt = iso(history[path])
        return old
    end
    local ds = open_here and self.ui.doc_settings or DocSettings:open(path)
    local props = ds:readSetting("doc_props")
    local cached = old and old.modified == attr.modification and old.size == attr.size
    if not props or not props.title then
        if cached then props = old.props end
        if not props then
            local Info = require("apps/filemanager/filemanagerbookinfo")
            props = Info.getDocProps({ui = self.ui or {}}, path)
        end
    end
    props = props or {}
    local summary = ds:readSetting("summary", {})
    local progress = tonumber(ds:readSetting("percent_finished")) or 0
    local status = summary.status
    if status == "complete" then status = "read"
    elseif status == "abandoned" then status = "on_hold"
    elseif status == "new" then status = "unread"
    elseif status == "reading" or progress > 0 then status = "reading"
    else status = "unread" end
    local book = { id = path, path = path, title = props.title or path:match("([^/]+)$"),
        authors = names(props.authors), series = props.series, seriesIndex = tonumber(props.series_index),
        props = props, modified = attr.modification, size = attr.size,
        added = old and old.added or os.time(), last_open = history[path] or 0,
        lastReadAt = iso(history[path]), progressPercentage = math.max(0, math.min(100, progress * 100)),
        readStatus = status, rating = tonumber(summary.rating),
        finishedOn = status == "read" and summary.modified or nil,
        format = (path:match("%.([^%.]+)$") or ""):upper(),
        md5 = ds:readSetting("partial_md5_checksum"), highlights = {}, sidecar = stamp }
    local ok_genres, genres = pcall(bookGenres, props, path)
    book.genres = ok_genres and genres or {}
    -- KOReader's current annotation format; legacy highlights remain readable too.
    for _, a in ipairs(ds:readSetting("annotations", {})) do
        if a.pos0 and a.text and a.text ~= "" then
            book.highlights[#book.highlights+1] = {text = a.text, note = a.note, bookId = path,
                bookTitle = book.title, chapter = a.chapter, chapterTitle = a.chapter, datetime = a.datetime}
        end
    end
    if #book.highlights == 0 then
        for _, page in pairs(ds:readSetting("highlight", {})) do
            for _, a in pairs(page) do
                if type(a) == "table" and a.text then
                    book.highlights[#book.highlights+1] = {text = a.text, note = a.note, bookId = path, bookTitle = book.title,
                        chapter = a.chapter, chapterTitle = a.chapter, datetime = a.datetime}
                end
            end
        end
    end
    return book
end

-- Coroutine yields after every directory entry/book, keeping scans cancellable.
-- Build a new index and commit only when the complete scan succeeds.
function Local:scanCoroutine()
    return coroutine.create(function()
        local history, old, seen, result = {}, {}, {}, {}
        local before = {}
        for _, b in ipairs(self.books) do
            old[b.path] = b
            before[b.path] = { title = b.title, readStatus = b.readStatus, progressPercentage = b.progressPercentage,
                rating = b.rating, last_open = b.last_open, highlights = b.highlights, series = b.series, seriesIndex = b.seriesIndex }
        end
        -- changed: the board must be drawn again; dirty: the index file must
        -- be saved (a book read again, e.g. for its new sidecar stamp).
        local changed, dirty = false, false
        for _, h in ipairs(require("readhistory").hist or {}) do history[h.file] = h.time end
        self.errors = {}
        -- Yield to the UI only after ~100 ms of work. Yielding after every entry
        -- cost a 10 ms timer round trip per file, which dominated large scans.
        local slice = os.clock()
        local function tick()
            if os.clock() - slice >= 0.1 then
                coroutine.yield(#result)
                slice = os.clock()
            end
        end
        local function add(path)
            if seen[path] then return end
            seen[path] = true
            local attr = lfs.attributes(path)
            if attr and attr.mode == "file" and Registry:hasProvider(path) and not Registry:isImageFile(path) then
                local ok, book = pcall(self.readBook, self, path, attr, history, old[path])
                if ok then
                    result[#result+1] = book
                    if not changed and not (before[path] and sameBook(before[path], book)) then changed = true end
                    if not old[path] or (book ~= old[path] and book.sidecar ~= old[path].sidecar) then dirty = true end
                else
                    self.errors[#self.errors+1] = path .. ": " .. tostring(book)
                    if old[path] then result[#result+1] = old[path] end
                end
            end
            tick()
        end
        local function walk(dir)
            local ok, iter, obj = pcall(lfs.dir, dir)
            if not ok then error("Cannot read library folder: " .. dir) end
            for name in iter, obj do
                if name:sub(1,1) ~= "." and not name:match("%.sdr$") then
                    local path = dir:gsub("/$", "") .. "/" .. name
                    local mode = lfs.symlinkattributes(path, "mode")
                    if mode == "directory" then walk(path)
                    elseif mode == "file" then add(path) end
                end
                tick()
            end
        end
        for _, dir in ipairs(self.settings.library_roots or {}) do walk(dir) end
        -- History contributes existing books even outside the selected folders.
        for path in pairs(history) do add(path) end
        if #result ~= #self.books then changed = true end
        self.last_scan_changed = changed
        if not changed and #self.errors == 0 then
            -- Same books, same state: the index stands (already sorted) and
            -- nothing is redrawn. Books read again keep their new entries.
            if dirty then
                local fresh = {}
                for _, b in ipairs(result) do fresh[b.path] = b end
                for i, b in ipairs(self.books) do self.books[i] = fresh[b.path] or b end
                self.cache:saveSetting("books", self.books)
                self.cache:flush()
            end
            return #result
        end
        table.sort(result, function(a,b) return a.title:lower() < b.title:lower() end)
        self.books = result
        self._group_cache = nil
        self.cache:saveSetting("books", result)
        self.cache:flush()
        return #result
    end)
end

-- KOReader's own collections (the ones File manager > Collections edits).
-- Newer KOReader keeps a collection as {path = item}, older as a list of items.
local function readCollections()
    local ok, RC = pcall(require, "readcollection")
    if not ok or type(RC) ~= "table" then return {} end
    if type(RC.coll) ~= "table" or next(RC.coll) == nil then
        if type(RC._read) == "function" then pcall(RC._read, RC) end
    end
    return type(RC.coll) == "table" and RC.coll or {}
end
local function collectionPaths(name)
    local set = {}
    local coll = readCollections()[name]
    for key, item in pairs(type(coll) == "table" and coll or {}) do
        local path = type(key) == "string" and key or (type(item) == "table" and item.file)
        if path then set[path] = true end
    end
    return set
end

-- How KOReader names a collection on screen ("favorites" is shown as Favorites).
local function collectionTitle(name)
    local ok, RC = pcall(require, "readcollection")
    if ok and type(RC) == "table" then
        if RC.getCollectionTitle then
            local ok2, title = pcall(RC.getCollectionTitle, RC, name)
            if ok2 and type(title) == "string" and title ~= "" then return title end
        end
        if name == RC.default_collection_name then return require("gettext")("Favorites") end
    end
    return name
end
function Local:collectionTitle(name) return collectionTitle(name) end

-- Every collection with how many of the indexed books it holds.
function Local:collections()
    local result = {}
    for name in pairs(readCollections()) do
        local set, count = collectionPaths(name), 0
        for _, b in ipairs(self.books) do if set[b.path] then count = count + 1 end end
        result[#result+1] = {name = name, title = collectionTitle(name), count = count}
    end
    table.sort(result, function(a, b) return a.title:lower() < b.title:lower() end)
    return result
end

-- The collections without counting their books: cheap enough for every draw.
function Local:collectionList()
    local result = {}
    for name in pairs(readCollections()) do result[#result+1] = {name = name, title = collectionTitle(name)} end
    table.sort(result, function(a, b) return a.title:lower() < b.title:lower() end)
    return result
end

-- The set of collection names a book is in.
function Local:collectionsOf(book)
    local out = {}
    for name in pairs(readCollections()) do
        if collectionPaths(name)[book.path] then out[name] = true end
    end
    return out
end

-- Puts a book in a collection or takes it out, through KOReader's own
-- collections so the file browser shows the same.
function Local:setInCollection(book, name, member)
    local ok, RC = pcall(require, "readcollection")
    if not ok or type(RC) ~= "table" then error("KOReader's collections are not available") end
    readCollections()
    if member then
        if not RC.addItem then error("This KOReader cannot add to collections") end
        RC:addItem(book.path, name)
    else
        if not RC.removeItem then error("This KOReader cannot remove from collections") end
        RC:removeItem(book.path, name)
    end
    -- KOReader's versions differ on whether the change is written by itself;
    -- writing it again does no harm.
    if not pcall(RC.write, RC, {[name] = true}) then pcall(RC.write, RC, name) end
end

-- For a set of books: how many of them are in each collection, by name.
function Local:collectionCounts(books)
    local counts = {}
    for name in pairs(readCollections()) do
        local set, n = collectionPaths(name), 0
        for _, b in ipairs(books) do if set[b.path] then n = n + 1 end end
        counts[name] = n
    end
    return counts
end

-- Puts many books in a collection or takes them out, writing it once.
function Local:setManyInCollection(books, name, member)
    local ok, RC = pcall(require, "readcollection")
    if not ok or type(RC) ~= "table" then error("KOReader's collections are not available") end
    readCollections()
    local fn = member and RC.addItem or RC.removeItem
    if not fn then error("This KOReader cannot change collections") end
    for _, book in ipairs(books) do fn(RC, book.path, name) end
    if not pcall(RC.write, RC, {[name] = true}) then pcall(RC.write, RC, name) end
end

function Local:createCollection(name)
    local ok, RC = pcall(require, "readcollection")
    if not ok or type(RC) ~= "table" or not RC.addCollection then error("KOReader's collections are not available") end
    readCollections()
    if RC.coll and RC.coll[name] then return end
    RC:addCollection(name)
end

-- Every file format in the library with its number of books.
function Local:formats()
    local counts, result = {}, {}
    for _, b in ipairs(self.books) do
        if b.format and b.format ~= "" then counts[b.format] = (counts[b.format] or 0) + 1 end
    end
    for name, count in pairs(counts) do result[#result+1] = {name = name, count = count} end
    table.sort(result, function(a, b) return a.name < b.name end)
    return result
end

-- What a search looks through, lower-cased, kept per book (weakly, so a
-- book dropped from the index takes it along) and redone when the title,
-- authors or series change.
local search_cache = setmetatable({}, { __mode = "k" })
local function searchText(b)
    local hit = search_cache[b]
    if hit and hit.title == b.title and hit.authors == b.authors and hit.series == b.series then return hit.text end
    local text = (b.title .. " " .. table.concat(b.authors or {}, "\n") .. " " .. (b.series or "")):lower()
    search_cache[b] = { title = b.title, authors = b.authors, series = b.series, text = text }
    return text
end

local function authorOf(b, name)
    for _, a in ipairs(b.authors or {}) do
        if a == name then return true end
    end
    return false
end

-- Orders that read newest or biggest first unless `params.order` flips them.
local DESCENDING = {recently_added = true, last_read = true, recently_read = true, progress = true}

function Local:query(params)
    params = params or {}
    local out = {}
    local q = tostring(params.search or ""):lower()
    local members = params.collection and collectionPaths(params.collection) or nil
    local status = params.read_status or params.readStatus
    -- The cheap tests first; the joined and lower-cased text only for a search
    -- or an author filter, and the search text kept per book between queries
    -- (not in the index file).
    for _, b in ipairs(self.books) do
        local match = (not params.ids or params.ids[b.id])
            and (not members or members[b.path])
            and (not status or status == "all" or b.readStatus == status)
            and (not params.series or b.series == params.series)
            and (not params.format or b.format == params.format)
            and (not params.author or authorOf(b, params.author))
            and (q == "" or searchText(b):find(q, 1, true))
            and (not params.genre or hasGenre(b, params.genre))
        if match then out[#out+1] = b end
    end
    local sort = params.sort or "title"
    local descending = DESCENDING[sort] or false
    if params.order == "desc" then descending = true elseif params.order == "asc" then descending = false end
    local function key(b)
        if sort == "recently_added" then return b.added
        elseif sort == "last_read" or sort == "recently_read" then return b.last_open
        elseif sort == "progress" then return b.progressPercentage
        elseif sort == "author" then return table.concat(b.authors or {}, ", "):lower() .. "\1" .. b.title:lower()
        elseif sort == "series" then
            -- By series, then volume; books outside a series come last.
            return (b.series and b.series:lower() or "\255") .. "\1" .. string.format("%09.2f", b.seriesIndex or 0) .. "\1" .. b.title:lower()
        end
        return b.title:lower()
    end
    local keys = {}
    for _, b in ipairs(out) do keys[b] = key(b) end
    table.sort(out, function(a, b)
        local x, y = keys[a], keys[b]
        if x == y then return a.path < b.path end
        if descending then return x > y end
        return x < y
    end)
    return out
end

-- Authors or series as list entries: how many books, how many read or being
-- read, a few books to show as covers, and for a series who wrote it and the
-- state of each book in order. `sort` is "name", "name_desc" or "books". The
-- lists are built once per index and kept until the books change.
function Local:groupEntries(kind, sort)
    sort = sort or "name"
    local cache = self._group_cache
    if not cache or cache.books ~= self.books or cache.count ~= #self.books then
        cache = { books = self.books, count = #self.books }
        self._group_cache = cache
    end
    local key = kind .. ":" .. sort
    if cache[key] then return cache[key] end
    local ListData = require("aleph_list_data")
    local by_name = cache[kind .. ":*"]
    if not by_name then
        local map, list = {}, {}
        for _, b in ipairs(self.books) do
            local names = kind == "authors" and b.authors or { b.series }
            for _, name in ipairs(names) do
                if name and name ~= "" then
                    local e = map[name]
                    if not e then
                        e = { title = name, books = {}, letter = ListData.letterOf(name) }
                        map[name] = e
                        list[#list + 1] = e
                    end
                    e.books[#e.books + 1] = b
                end
            end
        end
        for _, e in ipairs(list) do
            local books = e.books
            table.sort(books, function(a, b)
                if kind == "authors" then
                    local sa, sb = (a.series or ""):lower(), (b.series or ""):lower()
                    if sa ~= sb then return sa < sb end
                end
                local ia, ib = tonumber(a.seriesIndex) or 1e9, tonumber(b.seriesIndex) or 1e9
                if ia ~= ib then return ia < ib end
                return a.title:lower() < b.title:lower()
            end)
            e.count, e.readingCount, e.finishedCount = #books, 0, 0
            e.previewBooks = {}
            e.memberStates = {}
            local who, who_seen, series_count = {}, {}, {}
            for i, b in ipairs(books) do
                local state = ListData.stateOf(b)
                if state == "finished" then e.finishedCount = e.finishedCount + 1; e.memberStates[i] = "finished"
                elseif state == "reading" then e.readingCount = e.readingCount + 1; e.memberStates[i] = "reading"
                else e.memberStates[i] = "unread" end
                if i <= 3 then e.previewBooks[i] = b end
                local first = b.authors and b.authors[1]
                if first and not who_seen[first] then who_seen[first] = true; who[#who + 1] = first end
                if b.series and b.series ~= "" then series_count[b.series] = (series_count[b.series] or 0) + 1 end
            end
            if kind == "series" then e.authorNames = who
            else
                -- The series an author has the most books in, for the line under the name.
                local best, best_n
                for name, n in pairs(series_count) do
                    if not best_n or n > best_n or (n == best_n and name < best) then best, best_n = name, n end
                end
                e.seriesName = best
            end
        end
        table.sort(list, function(a, b) return a.title:lower() < b.title:lower() end)
        cache[kind .. ":*"] = list
        by_name = list
    end
    local out = {}
    for i, e in ipairs(by_name) do out[i] = e end
    if sort == "name_desc" then
        for i = 1, math.floor(#out / 2) do out[i], out[#out - i + 1] = out[#out - i + 1], out[i] end
    elseif sort == "books" then
        table.sort(out, function(a, b)
            if a.count ~= b.count then return a.count > b.count end
            return a.title:lower() < b.title:lower()
        end)
    end
    cache[key] = out
    return out
end

function Local:groups(kind)
    local counts, result = {}, {}
    for _, b in ipairs(self.books) do
        for _, name in ipairs(kind == "authors" and b.authors or {b.series}) do
            if name and name ~= "" then counts[name] = (counts[name] or 0) + 1 end
        end
    end
    for name,count in pairs(counts) do result[#result+1] = {name = name, count = count} end
    table.sort(result, function(a,b) return a.name:lower() < b.name:lower() end)
    return result
end

-- Changes a book's summary (rating, status) in KOReader's own sidecar, the same
-- place the file browser and the reader keep it. A book open in the reader is
-- changed through the reader's settings so closing it does not undo the change.
function Local:saveSummary(book, change)
    local DocSettings = require("docsettings")
    local open = self.ui and self.ui.document and self.ui.document.file == book.path and self.ui.doc_settings
    local ds = open or DocSettings:open(book.path)
    local summary = ds:readSetting("summary", {})
    change(summary)
    ds:saveSetting("summary", summary)
    ds:flush()
    -- The file browser keeps a copy of each book's status.
    pcall(function() require("ui/widget/booklist").setBookInfoCacheProperty(book.path, "status", summary.status) end)
    self._group_cache = nil
    return summary
end

function Local:setRating(book, rating)
    self:saveSummary(book, function(summary) summary.rating = rating end)
    book.rating = rating
end

local STATUS_IN_SIDECAR = { unread = "new", reading = "reading", read = "complete", on_hold = "abandoned" }
function Local:setStatus(book, status)
    local summary = self:saveSummary(book, function(summary)
        summary.status = STATUS_IN_SIDECAR[status]
        if status == "read" then summary.modified = os.date("%Y-%m-%d") end
    end)
    book.readStatus = status
    book.finishedOn = status == "read" and summary.modified or nil
end

-- Up to `limit` books sharing genres with `book`, best match first. Books of
-- the same series are left out (the series has its own link).
function Local:similar(book, limit)
    local mine, scored = {}, {}
    for _, g in ipairs(book.genres or {}) do mine[g:lower()] = true end
    if next(mine) == nil then return {} end
    for _, b in ipairs(self.books) do
        if b.id ~= book.id and not (book.series and b.series == book.series) then
            local score = 0
            for _, g in ipairs(b.genres or {}) do
                if mine[g:lower()] then score = score + 1 end
            end
            if score > 0 then scored[#scored+1] = {book = b, score = score} end
        end
    end
    table.sort(scored, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return a.book.title:lower() < b.book.title:lower()
    end)
    local out = {}
    for i = 1, math.min(limit or 5, #scored) do out[i] = scored[i].book end
    return out
end

-- Every genre (tag) in the library with the number of books that have it.
function Local:genres()
    local counts, names, result = {}, {}, {}
    for _, b in ipairs(self.books) do
        for _, g in ipairs(b.genres or {}) do
            local key = g:lower()
            counts[key] = (counts[key] or 0) + 1
            names[key] = names[key] or g
        end
    end
    for key, count in pairs(counts) do result[#result+1] = {name = names[key], count = count} end
    table.sort(result, function(a, b) return a.name:lower() < b.name:lower() end)
    return result
end

function Local:dashboard()
    local reading = self:query{read_status = "reading", sort = "last_read"}
    local unread = self:query{read_status = "unread"}
    local finished = self:query{read_status = "read", sort = "last_read"}
    local year, done, highlights = os.date("%Y"), {}, {}
    for _, b in ipairs(finished) do
        if type(b.finishedOn) == "string" and b.finishedOn:sub(1,4) == year then done[#done+1] = b end
    end
    for _, b in ipairs(self.books) do
        for _, h in ipairs(b.highlights or {}) do highlights[#highlights+1] = h end
    end
    local random = {}
    for _, b in ipairs(self.books) do random[#random+1] = b end
    for i = #random,2,-1 do local j = math.random(i); random[i],random[j] = random[j],random[i] end
    local next_books, active = {}, {}
    for _, b in ipairs(reading) do if b.series then active[b.series] = b.seriesIndex or 0 end end
    for series, index in pairs(active) do
        for _, b in ipairs(self:query{series = series, sort = "series"}) do
            if b.readStatus == "unread" and (b.seriesIndex or 0) > index then next_books[#next_books+1] = b; break end
        end
    end
    local daily = require("aleph_stats_reader").getDailySeconds(0) or {}
    local dates, longest, run, prev = {}, 0, 0, nil
    for day, seconds in pairs(daily) do if seconds > 0 then dates[#dates+1] = day end end
    table.sort(dates)
    local function previous(day)
        local y,m,d = day:match("(%d+)-(%d+)-(%d+)")
        return os.date("%Y-%m-%d", os.time{year=y,month=m,day=d-1,hour=12})
    end
    for _, day in ipairs(dates) do
        run = prev == previous(day) and run + 1 or 1
        longest = math.max(longest,run); prev = day
    end
    local day, current = os.date("%Y-%m-%d"), 0
    if not daily[day] or daily[day] <= 0 then day = previous(day) end
    while (daily[day] or 0) > 0 do current = current+1; day = previous(day) end
    local authors, series = self:groups("authors"), self:groups("series")
    local function labels(groups) local a = {}; for _, g in ipairs(groups) do a[#a+1]=g.name end; return a end
    return {displayName = self.settings.display_name, generatedAt = iso(os.time()),
        totalBooks = #self.books, continueReading = reading, discover = random,
        finishedThisYear = done, readingGoal = {year=tonumber(year), goalBooks=self.settings.year_goal or 12, completedBooks=#done},
        readingStreak = {currentStreak=current, longestStreak=longest},
        highlightOfTheDay = #highlights > 0 and highlights[(tonumber(os.date("%j"))-1) % #highlights+1] or nil,
        browseCounts = {authors=#authors,series=#series,inProgress=#reading,libraries=#(self.settings.library_roots or {}),
            collections=#self:collectionList()},
        boardNames = {authors=labels(authors),series=labels(series),collections=(function()
            local t = {}
            for _, c in ipairs(self:collectionList()) do t[#t+1] = c.title end
            return t
        end)()},
        boardShelves = { ["random"]=random, ["recently-added"]=self:query{sort="recently_added"},
            ["in-progress"]=reading, ["want-to-read"]=unread, ["unopened"]=unread,
            ["pick-back-up"]=reading, ["up-next-in-series"]=next_books, ["finished"]=done } }
end

-- Covers are stored as thumbnails no taller than this, so writing, reading and
-- decoding them is far cheaper than with full-size cover images.
local function thumbHeight()
    local h = require("device").screen:getHeight()
    return math.max(360, math.min(720, math.floor(h * 0.4)))
end

-- A cover already on disk (a custom cover or a saved thumbnail), without
-- opening the book; nil when none was made yet.
function Local.cachedCover(book)
    if book.cover_path and lfs.attributes(book.cover_path,"mode") == "file" then return book.cover_path end
    local ok, custom = pcall(function() return DocSettings:findCustomCoverFile(book.path) end)
    if ok and custom then return custom end
    if not (book.modified and book.size) then return nil end
    local path = DataStorage:getDataDir() .. "/cache/aleph/thumbs/"
        .. require("ffi/sha2").md5(book.path .. ":" .. book.modified .. ":" .. book.size .. ":" .. thumbHeight()) .. ".png"
    if lfs.attributes(path,"mode") == "file" then return path end
end

function Local:cover(book)
    if book.cover_path and lfs.attributes(book.cover_path,"mode") == "file" then return book.cover_path end
    if book.cover_checked then return nil end
    book.cover_checked = true
    local custom = DocSettings:findCustomCoverFile(book.path)
    if custom then book.cover_path = custom; return custom end
    local dir = DataStorage:getDataDir() .. "/cache/aleph/thumbs"
    util.makePath(dir)
    local th = thumbHeight()
    local key = require("ffi/sha2").md5(book.path .. ":" .. book.modified .. ":" .. book.size .. ":" .. th)
    local path = dir .. "/" .. key .. ".png"
    if lfs.attributes(path,"mode") == "file" then book.cover_path=path; return path end
    local bb
    local ok = pcall(function()
        bb = require("apps/filemanager/filemanagerbookinfo"):getCoverImage(nil, book.path)
        if bb and bb:getHeight() > th then
            local nw = math.max(1, math.floor(bb:getWidth() * th / bb:getHeight() + 0.5))
            -- true: the full-size original is released as it is scaled.
            bb = require("ui/renderimage"):scaleBlitBuffer(bb, nw, th, true)
        end
        if bb then bb:writePNG(path) end
    end)
    if bb then bb:free() end
    if ok and lfs.attributes(path,"mode") == "file" then book.cover_path=path; return path end
end

return Local
