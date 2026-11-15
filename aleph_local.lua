-- Local library adapter. Sidecars and statistics are read-only; only our cache is written.
local lfs = require("libs/libkoreader-lfs")
local DocSettings = require("docsettings")
local Registry = require("document/documentregistry")
local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local util = require("util")
local try = require("aleph_try").call
local _ = require("gettext")
local T = require("ffi/util").template
local Local = {}
Local.__index = Local

local function iso(t) return t and t > 0 and os.date("!%Y-%m-%dT%H:%M:%SZ", t) or nil end

-- Sorts `list` by a key worked out once per entry (not once per comparison,
-- as a key made inside the comparison would be): key(e) returns a string or
-- a number; ties keep a stable order by `tie(e)` when given.
local function sortByKey(list, key, tie)
    local keys, ties = {}, {}
    for _i, e in ipairs(list) do
        keys[e] = key(e)
        if tie then ties[e] = tie(e) end
    end
    table.sort(list, function(a, b)
        local x, y = keys[a], keys[b]
        if x ~= y then return x < y end
        if tie then return ties[a] < ties[b] end
        return false
    end)
    return list
end
Local.sortByKey = sortByKey
local function lowerTitle(e) return e.title:lower() end
local function lowerName(e) return e.name:lower() end
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
        for _i, s in ipairs(kw) do add(s) end
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
    for _i, g in ipairs(book.genres or {}) do
        if g:lower() == wanted then return true end
    end
    return false
end

-- The library is read from its index file once per session and kept: Home
-- is opened again each time a book closes, and reading the index (every
-- book's description and highlights) was the dearest part of that.
-- Local.new gives the same library each time, for the settings and the
-- reader or file browser now asking.
local shared

function Local.new(settings, ui)
    if shared then
        shared.settings, shared.ui, shared.errors = settings, ui, {}
        return shared
    end
    local cache = LuaSettings:open(DataStorage:getSettingsDir() .. "/aleph_index.lua")
    local books = cache:readSetting("books", {})
    -- "No cover was found" is good for one session only: a cover that could
    -- not be made once is tried again the next time KOReader starts.
    for _i, b in ipairs(books) do b.cover_checked = nil end
    shared = setmetatable({settings = settings, ui = ui, cache = cache,
        books = books, errors = {}, revision = 0}, Local)
    return shared
end

-- The library kept for this session, or nil when none was read yet.
function Local.shared() return shared end

-- Forgets the library kept (unsaved changes are written first): the next
-- Local.new reads the index file again.
function Local.forget()
    if shared and shared._index_dirty then pcall(shared.saveIndex, shared) end
    shared = nil
end

-- The books changed (entries replaced, added or removed): what was made
-- from the old entries is dropped, and whoever keeps a lookup of them
-- (Home's by_id) sees a new revision.
function Local:touch()
    self._group_cache = nil
    self.revision = (self.revision or 0) + 1
end

-- The index file. Writing it means writing every book again, so a change
-- of state (a book read further, a status) only marks it: it is written
-- when KOReader saves its settings (closing a book, going to sleep,
-- leaving), and at once only when books were added or removed. An index
-- that missed a write is put right by the next scan, which reads the changed
-- books again.
--
-- KOReader's own writer (LuaSettings:flush) took about 12 seconds for a
-- library of several hundred books on a Kindle, every time a book closed
-- and when KOReader quit: it sorts every table's keys, checks every table
-- against all the ones around it, indents every line and copies the old
-- file aside first. The index is written here instead: compact, in one go,
-- to a new file put in place of the old one when complete. Where a
-- background process can be started (KOReader's runInSubProcess, as for
-- covers), it is written there, and nobody waits for it at all.

local LUA_KEYWORDS = {}
for w in ("and break do else elseif end false for function goto if in local nil not or repeat return then true until while"):gmatch("%a+") do
    LUA_KEYWORDS[w] = true
end

local function numberText(n)
    if n ~= n then return "0/0" end
    if n == math.huge then return "math.huge" end
    if n == -math.huge then return "-math.huge" end
    if n == math.floor(n) and math.abs(n) < 2^53 then return string.format("%d", n) end
    return string.format("%.17g", n)
end

-- Appends the Lua text of `v` to `out`. Functions, userdata and tables nested
-- deeper than any book entry are left out (written as nil).
local function serialize(v, out, depth)
    local t = type(v)
    if t == "string" then
        out[#out + 1] = string.format("%q", v)
    elseif t == "number" then
        out[#out + 1] = numberText(v)
    elseif t == "boolean" then
        out[#out + 1] = v and "true" or "false"
    elseif t == "table" and depth < 24 then
        out[#out + 1] = "{"
        local n = #v
        for i = 1, n do
            serialize(v[i], out, depth + 1)
            out[#out + 1] = ","
        end
        for k, x in pairs(v) do
            local kt = type(k)
            local is_index = kt == "number" and k >= 1 and k <= n and k == math.floor(k)
            if not is_index then
                local key
                if kt == "string" then
                    if k:match("^[%a_][%w_]*$") and not LUA_KEYWORDS[k] then key = k
                    else key = "[" .. string.format("%q", k) .. "]" end
                elseif kt == "number" then key = "[" .. numberText(k) .. "]"
                elseif kt == "boolean" then key = "[" .. tostring(k) .. "]"
                end
                local xt = type(x)
                if key and (xt == "string" or xt == "number" or xt == "boolean" or xt == "table") then
                    out[#out + 1] = key .. "="
                    serialize(x, out, depth + 1)
                    out[#out + 1] = ",\n"
                end
            end
        end
        out[#out + 1] = "}"
    else
        out[#out + 1] = "nil"
    end
end

-- The whole settings table of the index as Lua text, as LuaSettings reads it.
function Local.indexText(data)
    local out = { "-- Aleph's library index (aleph_local.lua). Made again by a library scan.\nreturn " }
    serialize(data, out, 0)
    out[#out + 1] = "\n"
    return table.concat(out)
end

-- Writes `text` to `file`: to a new file first, put in place of the old one
-- once complete, so a crash or a full disk never leaves half an index.
function Local.writeIndexFile(file, text)
    local tmp = file .. ".new"
    local f, err = io.open(tmp, "wb")
    if not f then return false, err end
    local ok, werr = f:write(text)
    f:close()
    if not ok then os.remove(tmp); return false, werr end
    local renamed, rerr = os.rename(tmp, file)
    if not renamed then os.remove(tmp); return false, rerr end
    return true
end

local writer_pid, writer_again, writer_poll

local function subprocesses()
    local ok, u = pcall(require, "ffi/util")
    if ok and type(u) == "table" and type(u.runInSubProcess) == "function" and type(u.isSubProcessDone) == "function" then
        return u
    end
end

-- Looks, once a second, for the background writer to have finished (so it
-- does not linger as a finished process), then writes again if asked to
-- meanwhile.
local function watchWriter()
    if writer_poll then return end
    local u = subprocesses()
    local ok_ui, UIManager = pcall(require, "ui/uimanager")
    if not (u and ok_ui and UIManager.scheduleIn) then return end
    writer_poll = function()
        if writer_pid and not u.isSubProcessDone(writer_pid) then
            UIManager:scheduleIn(1, writer_poll)
            return
        end
        writer_poll, writer_pid = nil, nil
        if writer_again and shared then
            writer_again = false
            shared:saveIndex()
        end
    end
    UIManager:scheduleIn(1, writer_poll)
end

function Local:saveIndex(opts)
    self.cache:saveSetting("books", self.books)
    self._index_dirty = nil
    local file = self.cache.file
    if type(file) ~= "string" then
        -- Not a file of ours (a test's stand-in): its own writer.
        if self.cache.flush then self.cache:flush() end
        return true
    end
    local u = not (opts and opts.wait) and subprocesses() or nil
    if u then
        if writer_pid and not u.isSubProcessDone(writer_pid) then
            -- One is being written: this one follows when it is done.
            writer_again = true
            watchWriter()
            return true
        end
        local data = self.cache.data
        local pid = u.runInSubProcess(function()
            Local.writeIndexFile(file, Local.indexText(data))
        end)
        if pid then
            writer_pid = pid
            watchWriter()
            return true
        end
    end
    local ok, err = Local.writeIndexFile(file, Local.indexText(self.cache.data))
    if not ok then
        self._index_dirty = true
        require("aleph_try").report("aleph_local.lua saveIndex", err)
    end
    return ok
end
function Local:markDirty()
    self.cache:saveSetting("books", self.books)
    self._index_dirty = true
end
function Local.flushIfDirty()
    if shared and shared._index_dirty then return pcall(shared.saveIndex, shared) end
    return true
end

-- The library folders' own modification times, as one string: a file put
-- straight into one of them, or a new folder in it, changes it.
local function rootStamp(roots)
    local parts = {}
    for _i, dir in ipairs(roots or {}) do
        parts[#parts + 1] = tostring(dir) .. "@" .. tostring(lfs.attributes(dir, "modification") or 0)
    end
    return table.concat(parts, "|")
end

-- Whether the library should be scanned now: never scanned this session,
-- scanned more than Local.SCAN_EVERY seconds ago, or a library folder
-- changed since. In between, the book that closes is read again by itself
-- (Local.refreshClosing), so Home is right without a scan.
Local.SCAN_EVERY = 600
function Local:scanDue(now)
    now = now or os.time()
    if not self.scanned_at then return true end
    if now - self.scanned_at >= Local.SCAN_EVERY or now < self.scanned_at then return true end
    return self.root_stamp ~= rootStamp(self.settings and self.settings.library_roots)
end

-- The metadata set by hand in KOReader (Book information > Set custom):
-- its file, or nil.
local function customFile(path)
    local file
    try(function() file = DocSettings:findCustomMetadataFile(path) end)
    return type(file) == "string" and file or nil
end

-- Where KOReader keeps the book's own settings (its sidecar) and when that
-- file last changed, as one string; "none" when the book has no sidecar.
-- The custom metadata file counts too: editing it changes the book's entry.
local function sidecarStamp(path)
    local file
    try(function()
        if DocSettings.findSidecarFile then file = DocSettings:findSidecarFile(path)
        elseif DocSettings.getSidecarFile then file = DocSettings:getSidecarFile(path) end
    end)
    local stamp = "none"
    if type(file) == "string" then
        local modified = lfs.attributes(file, "modification")
        if modified then stamp = file .. "@" .. modified end
    end
    local custom = customFile(path)
    local custom_mod = custom and lfs.attributes(custom, "modification")
    if custom_mod then stamp = stamp .. "|" .. custom .. "@" .. custom_mod end
    return stamp
end

-- ------------------------------------------------------------ comic books
-- KOReader reads no metadata from comic archives (CBZ and the like), so a
-- comic shows as its file name. Most comic tools write a ComicInfo.xml inside
-- the archive; this reads its title, series, number, writers, genres and
-- summary. Read once per file (kept in the index until the file changes).
local COMIC_FORMATS = { cbz = true, cbr = true, cb7 = true, cbt = true }
Local.COMIC_FORMATS = COMIC_FORMATS

local function xmlField(xml, name)
    local v = xml:match("<" .. name .. "[^>]*>(.-)</" .. name .. ">")
    if not v then return nil end
    v = v:gsub("^%s*<!%[CDATA%[(.-)%]%]>%s*$", "%1")
    v = util.trim(unescape(v))
    return v ~= "" and v or nil
end

local function listOf(...)
    local out, seen = {}, {}
    for _i, value in ipairs({ ... }) do
        for item in tostring(value or ""):gmatch("[^,;]+") do
            item = util.trim(item)
            if item ~= "" and not seen[item:lower()] then seen[item:lower()] = true; out[#out + 1] = item end
        end
    end
    return out
end

-- ComicInfo.xml's text as KOReader-style props (title, authors, series,
-- series_index, keywords, description, language); nil when there is none.
function Local.parseComicInfo(xml)
    if type(xml) ~= "string" or not xml:find("<ComicInfo", 1, true) then return nil end
    local props = {}
    local series = xmlField(xml, "Series")
    local number = xmlField(xml, "Number")
    local volume = xmlField(xml, "Volume")
    props.series = series
    props.series_index = tonumber(number) or tonumber(volume)
    local title = xmlField(xml, "Title")
    if not title and series then
        -- An issue with no title of its own: "Saga #12".
        if number then title = series .. " #" .. number
        elseif volume then title = series .. " " .. volume end
    end
    props.title = title
    local writers = listOf(xmlField(xml, "Writer"))
    if #writers == 0 then writers = listOf(xmlField(xml, "Penciller")) end
    if #writers > 0 then props.authors = table.concat(writers, "\n") end
    local tags = listOf(xmlField(xml, "Genre"), xmlField(xml, "Tags"))
    if #tags > 0 then props.keywords = table.concat(tags, "\n") end
    props.description = xmlField(xml, "Summary")
    props.language = xmlField(xml, "LanguageISO")
    local year = tonumber(xmlField(xml, "Year"))
    if year and year >= 1000 and year <= 2200 then props.year = math.floor(year) end
    if not next(props) then return nil end
    return props
end

-- The ComicInfo.xml inside a comic archive, as props, or false when it has
-- none (so the archive is not opened again).
function Local.comicInfo(path)
    local ok, result = pcall(function()
        local Archiver = require("ffi/archiver")
        local arc = Archiver.Reader:new()
        if not arc:open(path) then return false end
        local key
        for entry in arc:iterate() do
            local name = entry.path:match("([^/\\]+)$") or entry.path
            if entry.mode == "file" and name:lower() == "comicinfo.xml" and entry.size > 0 and entry.size < 1048576 then
                key = entry.path
                break
            end
        end
        local xml = key and arc:extractToMemory(key)
        arc:close()
        return xml and Local.parseComicInfo(xml) or false
    end)
    return ok and result or false
end

-- The page count (Calibre's, else KOReader's) and the release year, for the
-- library's filters. A book's OPF is read once per file (kept in book.opf,
-- false when there is nothing).
-- read: whether to open the book's OPF (Settings > Library > Extra
-- filters); without it, only what is known already is used.
function Local:extraFilters()
    return type(self.settings) == "table" and self.settings.extra_filters == true
end

function Local.fillOpf(book, path, koreader_pages, read)
    if book.opf == nil and read then
        local ok, info = pcall(function() return require("aleph_pages").bookInfo(path) end)
        book.opf = (ok and info and (info.pages or info.year or info.isbn)) and info or false
    end
    local opf = book.opf or {}
    book.koreader_pages = koreader_pages
    book.pages = opf.pages or koreader_pages
    book.year = opf.year or (book.comic and book.comic.year) or nil
end

-- What a book shows: the props KOReader stored for it (or read from it), the
-- gaps filled from a comic's ComicInfo.xml, then the metadata set by hand in
-- KOReader on top, as KOReader's own book information does.
local PROP_KEYS = { "title", "authors", "series", "series_index", "language", "keywords", "description" }
local function blank(v) return v == nil or v == "" end
function Local.mergeProps(base, comic, custom)
    local props = {}
    for k, v in pairs(base or {}) do props[k] = v end
    for _i, k in ipairs(PROP_KEYS) do
        if blank(props[k]) and comic and not blank(comic[k]) then props[k] = comic[k] end
        if custom and not blank(custom[k]) then props[k] = custom[k] end
    end
    if blank(props.title) then props.title = nil end
    return props
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
        -- Entries from before the page count and release year were kept:
        -- read once, and the index saved.
        if old.opf == nil and self:extraFilters() then
            Local.fillOpf(old, path, old.koreader_pages, true)
            old._refreshed = true
        end
        return old
    end
    local ds = open_here and self.ui.doc_settings or DocSettings:open(path)
    local props = ds:readSetting("doc_props")
    local cached = old and old.modified == attr.modification and old.size == attr.size
    if not props or blank(props.title) then
        -- No title stored (a book never opened, or one whose file has none):
        -- the cached entry's, or what KOReader's book information has.
        local fallback = cached and old.props or nil
        if not fallback then
            local Info = require("apps/filemanager/filemanagerbookinfo")
            local ok, got = pcall(Info.getDocProps, {ui = self.ui or {}}, path)
            fallback = ok and got or nil
        end
        if fallback then
            local merged = {}
            for k, v in pairs(fallback) do merged[k] = v end
            for k, v in pairs(props or {}) do if not blank(v) then merged[k] = v end end
            props = merged
        end
    end
    props = props or {}
    -- A comic's ComicInfo.xml, read once per file.
    local ext = (path:match("%.([^%.]+)$") or ""):lower()
    local comic = nil
    if COMIC_FORMATS[ext] then
        if cached and old.comic ~= nil then comic = old.comic else comic = Local.comicInfo(path) end
    end
    local custom = nil
    local custom_path = customFile(path)
    if custom_path then
        try(function() custom = DocSettings.openSettingsFile(custom_path):readSetting("custom_props") end)
        if type(custom) ~= "table" then custom = nil end
    end
    props = Local.mergeProps(props, comic or nil, custom)
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
        props = props, comic = comic, modified = attr.modification, size = attr.size,
        added = old and old.added or os.time(), last_open = history[path] or 0,
        lastReadAt = iso(history[path]), progressPercentage = math.max(0, math.min(100, progress * 100)),
        readStatus = status, rating = Local.ratingOf(summary),
        finishedOn = status == "read" and summary.modified or nil,
        format = (path:match("%.([^%.]+)$") or ""):upper(),
        md5 = ds:readSetting("partial_md5_checksum"), highlights = {}, sidecar = stamp }
    local koreader_pages = tonumber(ds:readSetting("doc_pages"))
    if cached and old.opf ~= nil then book.opf = old.opf end
    Local.fillOpf(book, path, koreader_pages, self:extraFilters())
    if comic and comic.year then book.year = book.year or comic.year end
    local ok_genres, genres = pcall(bookGenres, props, path)
    book.genres = ok_genres and genres or {}
    -- KOReader's current annotation format; legacy highlights remain readable too.
    for _i, a in ipairs(ds:readSetting("annotations", {})) do
        if a.pos0 and a.text and a.text ~= "" then
            book.highlights[#book.highlights+1] = {text = a.text, note = a.note, bookId = path,
                bookTitle = book.title, chapter = a.chapter, chapterTitle = a.chapter, datetime = a.datetime}
        end
    end
    if #book.highlights == 0 then
        for _i, page in pairs(ds:readSetting("highlight", {})) do
            for _i, a in pairs(page) do
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
        local added = false
        for _i, b in ipairs(self.books) do
            old[b.path] = b
            before[b.path] = { title = b.title, readStatus = b.readStatus, progressPercentage = b.progressPercentage,
                rating = b.rating, last_open = b.last_open, highlights = b.highlights, series = b.series, seriesIndex = b.seriesIndex }
        end
        -- changed: the board must be drawn again; dirty: the index file must
        -- be saved (a book read again, e.g. for its new sidecar stamp).
        local changed, dirty = false, false
        for _i, h in ipairs(require("readhistory").hist or {}) do history[h.file] = h.time end
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
                    if not old[path] then added = true end
                    if not old[path] or (book ~= old[path] and book.sidecar ~= old[path].sidecar) then dirty = true end
                    -- An entry read again keeps the cover found for the same file.
                    local was = old[path]
                    if was and book ~= was and was.modified == book.modified and was.size == book.size then
                        book.cover_path = book.cover_path or was.cover_path
                        book.cover_checked = book.cover_checked or was.cover_checked
                    end
                    if book._refreshed then book._refreshed = nil; dirty = true end
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
        for _i, dir in ipairs(self.settings.library_roots or {}) do walk(dir) end
        -- History contributes existing books even outside the selected folders.
        for path in pairs(history) do add(path) end
        -- Books added or removed: the index is written at once (a new book's
        -- details are dear to read again). Otherwise it is only marked.
        local structural = added or #result ~= #self.books
        if #result ~= #self.books then changed = true end
        self.last_scan_changed = changed
        self.scanned_at = os.time()
        self.root_stamp = rootStamp(self.settings.library_roots)
        if not changed and #self.errors == 0 then
            -- Same books, same state: the index stands (already sorted) and
            -- nothing is redrawn. Books read again keep their new entries.
            if dirty then
                local fresh = {}
                for _i, b in ipairs(result) do fresh[b.path] = b end
                for i, b in ipairs(self.books) do self.books[i] = fresh[b.path] or b end
                -- New entries: the lists made from the old ones go.
                self:touch()
                self:markDirty()
            end
            try(require("aleph_finished_log").sync, self.books)
            return #result
        end
        sortByKey(result, lowerTitle)
        self.books = result
        self:touch()
        if structural then self:saveIndex() else self:markDirty() end
        -- Finished books are kept on record, for when their file is deleted.
        try(require("aleph_finished_log").sync, result)
        return #result
    end)
end

-- The book open in the reader, as it closes: its entry is made again from
-- the reader's own settings (the position, status, rating and highlights
-- as they are now), so Home is right the first time it is drawn and no scan
-- of the whole library is needed to find what changed. False when there is
-- nothing to do it with: no library kept, or a book not in it (the scan
-- adds it).
function Local.refreshClosing(ui)
    local lib = shared
    if not lib or not ui or not ui.document or not ui.doc_settings then return false end
    local path = ui.document.file
    if type(path) ~= "string" then return false end
    local index
    for i, b in ipairs(lib.books) do
        if b.path == path then index = i; break end
    end
    if not index then return false end
    local attr = lfs.attributes(path)
    if not attr or attr.mode ~= "file" then return false end
    local old = lib.books[index]
    local history = {}
    for _i, h in ipairs(require("readhistory").hist or {}) do
        if h.file == path then history[path] = h.time; break end
    end
    if not history[path] then history[path] = os.time() end
    local settings_ui = lib.ui
    lib.ui = ui
    local ok, book = pcall(lib.readBook, lib, path, attr, history, old)
    lib.ui = settings_ui
    if not ok or type(book) ~= "table" then return false end
    if book ~= old then
        -- The sidecar as it stands (KOReader has just written it): the next
        -- scan finds the entry up to date.
        book.sidecar = sidecarStamp(path)
        if old.modified == book.modified and old.size == book.size then
            book.cover_path, book.cover_checked = old.cover_path, old.cover_checked
        end
        lib.books[index] = book
    end
    lib:touch()
    lib:markDirty()
    return true
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
        if name == RC.default_collection_name then return _("Favorites") end
    end
    return name
end
function Local:collectionTitle(name) return collectionTitle(name) end

-- Every collection with how many of the indexed books it holds.
function Local:collections()
    local result = {}
    for name in pairs(readCollections()) do
        local set, count = collectionPaths(name), 0
        for _i, b in ipairs(self.books) do if set[b.path] then count = count + 1 end end
        result[#result+1] = {name = name, title = collectionTitle(name), count = count}
    end
    sortByKey(result, lowerTitle)
    return result
end

-- The collections without counting their books: cheap enough for every draw.
function Local:collectionList()
    local result = {}
    for name in pairs(readCollections()) do result[#result+1] = {name = name, title = collectionTitle(name)} end
    sortByKey(result, lowerTitle)
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
        for _i, b in ipairs(books) do if set[b.path] then n = n + 1 end end
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
    for _i, book in ipairs(books) do fn(RC, book.path, name) end
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
    for _i, b in ipairs(self.books) do
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
    for _i, a in ipairs(b.authors or {}) do
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
    for _i, b in ipairs(self.books) do
        local match = (not params.ids or params.ids[b.id])
            and (not members or members[b.path])
            and (not status or status == "all" or b.readStatus == status)
            and (not params.series or b.series == params.series)
            and (not params.format or b.format == params.format)
            and (not params.author or authorOf(b, params.author))
            and (q == "" or searchText(b):find(q, 1, true))
            and (not params.genre or hasGenre(b, params.genre))
            and (not params.language or Local.languageOf(b) == params.language)
            and (not params.pages or Local.inPages(b, params.pages))
            and (not params.released or Local.decadeOf(b) == params.released)
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
        elseif sort == "author_last" then
            -- By the first author's surname ("Le Guin", "King"), then the
            -- whole name, then the title.
            local first = b.authors and b.authors[1] or ""
            return (Local.surnameOf(first) .. " " .. first):lower() .. "\1" .. b.title:lower()
        elseif sort == "series" then
            -- By series, then volume; books outside a series come last.
            return (b.series and b.series:lower() or "\255") .. "\1" .. string.format("%09.2f", b.seriesIndex or 0) .. "\1" .. b.title:lower()
        end
        return b.title:lower()
    end
    local keys = {}
    for _i, b in ipairs(out) do keys[b] = key(b) end
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
-- An author's surname, for sorting by last name: "Collins, Suzanne" and
-- "Suzanne Collins" both give "Collins"; "Martin Luther King Jr." gives
-- "King", "Ursula K. Le Guin" "Le Guin". A single name is its own surname.
local SUFFIXES = { jr = true, sr = true, ii = true, iii = true, iv = true, phd = true, md = true }
local PARTICLES = { le = true, la = true, de = true, du = true, des = true, del = true, della = true, di = true, da = true,
    van = true, von = true, der = true, den = true, ["st."] = true, st = true }
function Local.surnameOf(name)
    name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local before = name:match("^([^,]+),")
    if before and not SUFFIXES[(name:match(",%s*(.-)%.?$") or ""):lower()] then
        return (before:gsub("%s+$", ""))
    end
    local words = {}
    for w in name:gsub(",", " "):gmatch("%S+") do words[#words + 1] = w end
    while #words > 1 and SUFFIXES[words[#words]:lower():gsub("%.", "")] do table.remove(words) end
    local last = #words
    local first = last
    while first > 2 and PARTICLES[words[first - 1]:lower()] do first = first - 1 end
    if last == 0 then return name end
    return table.concat(words, " ", first, last)
end

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
        for _i, b in ipairs(self.books) do
            local names = kind == "authors" and b.authors or { b.series }
            for _i, name in ipairs(names) do
                if name and name ~= "" then
                    local e = map[name]
                    if not e then
                        e = { title = name, books = {}, letter = ListData.letterOf(name) }
                        if kind == "authors" then
                            local last = Local.surnameOf(name)
                            e.last_letter = ListData.letterOf(last)
                            e.last_key = (last .. " " .. name):lower()
                        end
                        map[name] = e
                        list[#list + 1] = e
                    end
                    e.books[#e.books + 1] = b
                end
            end
        end
        -- Each book's lower-cased series and title, once for every list.
        local low = {}
        local function lowOf(b)
            local l = low[b]
            if not l then l = { series = (b.series or ""):lower(), title = b.title:lower() }; low[b] = l end
            return l
        end
        for _i, e in ipairs(list) do
            local books = e.books
            table.sort(books, function(a, b)
                local la, lb = lowOf(a), lowOf(b)
                if kind == "authors" and la.series ~= lb.series then return la.series < lb.series end
                local ia, ib = tonumber(a.seriesIndex) or 1e9, tonumber(b.seriesIndex) or 1e9
                if ia ~= ib then return ia < ib end
                return la.title < lb.title
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
        sortByKey(list, lowerTitle)
        cache[kind .. ":*"] = list
        by_name = list
    end
    local out = {}
    for i, e in ipairs(by_name) do out[i] = e end
    if sort == "last" or sort == "last_desc" then
        -- By surname (authors), then by the whole name.
        sortByKey(out, function(e) return e.last_key or e.title:lower() end, function(e) return e.title end)
        if sort == "last_desc" then
            for i = 1, math.floor(#out / 2) do out[i], out[#out - i + 1] = out[#out - i + 1], out[i] end
        end
    elseif sort == "name_desc" then
        for i = 1, math.floor(#out / 2) do out[i], out[#out - i + 1] = out[#out - i + 1], out[i] end
    elseif sort == "books" then
        -- Most books first, then by name.
        sortByKey(out, function(e) return -e.count end, lowerTitle)
    end
    cache[key] = out
    return out
end

function Local:groups(kind)
    local counts, result = {}, {}
    for _i, b in ipairs(self.books) do
        for _i, name in ipairs(kind == "authors" and b.authors or {b.series}) do
            if name and name ~= "" then counts[name] = (counts[name] or 0) + 1 end
        end
    end
    for name,count in pairs(counts) do result[#result+1] = {name = name, count = count} end
    sortByKey(result, lowerName)
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
    try(function() require("ui/widget/booklist").setBookInfoCacheProperty(book.path, "status", summary.status) end)
    self:touch()
    return summary
end

-- KOReader keeps whole stars (summary.rating, 1 to 5); a half star is kept
-- beside it (summary.aleph_rating), with KOReader's own value the whole
-- stars below it, so KOReader's screens show 4 for 4.5. A rating changed
-- in KOReader since wins over Aleph's half.
function Local.ratingOf(summary)
    if type(summary) ~= "table" then return nil end
    local whole = tonumber(summary.rating)
    local exact = tonumber(summary.aleph_rating)
    if exact and math.floor(exact) == (whole or 0) then return exact end
    return whole
end

function Local:setRating(book, rating)
    rating = tonumber(rating)
    self:saveSummary(book, function(summary)
        if not rating then
            summary.rating, summary.aleph_rating = nil, nil
        else
            local whole = math.floor(rating)
            summary.rating = whole >= 1 and whole or nil
            summary.aleph_rating = (rating ~= whole) and rating or nil
        end
    end)
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
    try(require("aleph_finished_log").update, book)
end

-- Up to `limit` books sharing genres with `book`, best match first. Books of
-- the same series are left out (the series has its own link).
function Local:similar(book, limit)
    local mine, scored = {}, {}
    for _i, g in ipairs(book.genres or {}) do mine[g:lower()] = true end
    if next(mine) == nil then return {} end
    for _i, b in ipairs(self.books) do
        if b.id ~= book.id and not (book.series and b.series == book.series) then
            local score = 0
            for _i, g in ipairs(b.genres or {}) do
                if mine[g:lower()] then score = score + 1 end
            end
            if score > 0 then scored[#scored+1] = {book = b, score = score} end
        end
    end
    sortByKey(scored, function(e) return -e.score end, function(e) return e.book.title:lower() end)
    local out = {}
    for i = 1, math.min(limit or 5, #scored) do out[i] = scored[i].book end
    return out
end

-- Every genre (tag) in the library with the number of books that have it.
-- ------------------------------------------------ language, pages, released
-- A book's language by name ("English" for en, en-US, eng), or nil.
function Local.languageOf(b)
    local code = b.props and b.props.language
    if not code or code == "" then return nil end
    local ok, name = pcall(function() return require("aleph_language").name(code) end)
    return ok and name or code
end

-- Page-count bands for the filter: id, label, lowest, highest.
Local.PAGE_BANDS = {
    { id = "short", label = "Under 200 pages", lo = 1, hi = 199 },
    { id = "medium", label = "200 – 399 pages", lo = 200, hi = 399 },
    { id = "long", label = "400 – 599 pages", lo = 400, hi = 599 },
    { id = "epic", label = "600 pages or more", lo = 600, hi = math.huge },
}
local BAND_BY_ID = {}
for _i, band in ipairs(Local.PAGE_BANDS) do BAND_BY_ID[band.id] = band end
function Local.inPages(b, id)
    local band, n = BAND_BY_ID[id], tonumber(b.pages)
    return band ~= nil and n ~= nil and n >= band.lo and n <= band.hi
end
-- (The labels are translated where they are shown, not in the table above.)
function Local.pageBandLabel(id) return BAND_BY_ID[id] and _(BAND_BY_ID[id].label) or nil end

-- The decade a book came out in (2020 for 2024), or nil.
function Local.decadeOf(b)
    local year = tonumber(b.year)
    if not year then return nil end
    -- Everything before 1900 is one group.
    return year < 1900 and 1890 or (math.floor(year / 10) * 10)
end
function Local.decadeLabel(decade)
    decade = tonumber(decade)
    if not decade then return nil end
    if decade < 1900 then return _("Before 1900") end
    return T(_("%1s"), decade)
end

-- Languages, page bands and decades found in the library, with counts.
function Local:languages()
    local counts, result = {}, {}
    for _i, b in ipairs(self.books) do
        local name = Local.languageOf(b)
        if name then counts[name] = (counts[name] or 0) + 1 end
    end
    for name, count in pairs(counts) do result[#result+1] = {name = name, count = count} end
    -- Most books first, then by name. (Written as "a and b or c" this was
    -- not a valid order: with fewer books, a name earlier in the alphabet
    -- still came first, and table.sort stopped with an error.)
    table.sort(result, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.name < b.name
    end)
    return result
end
function Local:pageBands()
    local result = {}
    for _i, band in ipairs(Local.PAGE_BANDS) do
        local n = 0
        for _i, b in ipairs(self.books) do if Local.inPages(b, band.id) then n = n + 1 end end
        if n > 0 then result[#result+1] = {id = band.id, name = _(band.label), count = n} end
    end
    return result
end
function Local:decades()
    local counts, result = {}, {}
    for _i, b in ipairs(self.books) do
        local d = Local.decadeOf(b)
        if d then counts[d] = (counts[d] or 0) + 1 end
    end
    for d, count in pairs(counts) do result[#result+1] = {decade = d, name = Local.decadeLabel(d), count = count} end
    table.sort(result, function(a, b) return a.decade > b.decade end)
    return result
end

function Local:genres()
    local counts, names, result = {}, {}, {}
    for _i, b in ipairs(self.books) do
        for _i, g in ipairs(b.genres or {}) do
            local key = g:lower()
            counts[key] = (counts[key] or 0) + 1
            names[key] = names[key] or g
        end
    end
    for key, count in pairs(counts) do result[#result+1] = {name = names[key], count = count} end
    sortByKey(result, lowerName)
    return result
end

-- The books Discover (and the "pick a book to start" card) offers: unread
-- ones only (not finished, not being read, not on hold), and in a series
-- only the next one to read: every earlier book of the series on the device
-- must be finished. Earlier books that are not here (read and deleted, or
-- never had) do not hold a series back. Books without a series number are
-- offered as they are. Shuffled.
local function seriesKey(s)
    return type(s) == "string" and s ~= "" and s:lower():gsub("^%s+", ""):gsub("%s+$", "") or nil
end
function Local.discoverable(books)
    -- Per series: the lowest index not yet finished.
    local first_open = {}
    local function note(b, done)
        local key, idx = seriesKey(b.series), tonumber(b.seriesIndex)
        if not key or not idx or done then return end
        if not first_open[key] or idx < first_open[key] then first_open[key] = idx end
    end
    for _i, b in ipairs(books or {}) do note(b, b.readStatus == "read") end
    local out = {}
    for _i, b in ipairs(books or {}) do
        if b.readStatus == "unread" then
            local key, idx = seriesKey(b.series), tonumber(b.seriesIndex)
            if not key or not idx or idx <= (first_open[key] or idx) then out[#out + 1] = b end
        end
    end
    for i = #out, 2, -1 do local j = math.random(i); out[i], out[j] = out[j], out[i] end
    return out
end

-- A number that changes when a book's state that Home's lists depend on
-- changes in place (status, progress, last opened, added, finished day):
-- those changes do not always pass through the scan or saveSummary.
local STATUS_NUM = { unread = 1, reading = 2, read = 3, on_hold = 4 }
local MOD = 2147483647
function Local.stateSignature(books)
    local h = #books % MOD
    for _i, b in ipairs(books) do
        local v = (STATUS_NUM[b.readStatus] or 0)
            + (tonumber(b.last_open) or 0) % 1000003 * 5
            + math.floor((tonumber(b.progressPercentage) or 0) * 100) * 7
            + (tonumber(b.added) or 0) % 1000003 * 11
            + (type(b.finishedOn) == "string" and (tonumber((b.finishedOn:gsub("%D", ""):sub(1, 8))) or 1) or 0) % 1000003 * 13
        h = (h * 31 + v % MOD) % MOD
    end
    return h
end

-- Home's lists that only depend on the books (sorted queries, the next book
-- of each series being read, every highlight, the author and series names),
-- kept until the books change: a scan or a status change (which drop
-- _group_cache) or a change of state in place (stateSignature).
-- Up next in series: for each series with a book already finished (on the
-- device, or finished and deleted since: aleph_finished_log.lua), the first
-- book in series order that is not finished, shown only when it is unread
-- and every earlier book of the series on the device is finished. A series
-- whose next book is being read (or put on hold) shows nothing: that book
-- is in Continue reading, and the one after it waits until it is finished.
-- Books without a series number are left out; earlier books that are not on
-- the device do not hold a series back.
function Local.upNext(books, removed)
    if removed == nil then
        local ok, r = pcall(function() return require("aleph_finished_log").removed(books) end)
        removed = ok and type(r) == "table" and r or {}
    end
    local series, any_read = {}, {}
    for _i, b in ipairs(books or {}) do
        local key, idx = seriesKey(b.series), tonumber(b.seriesIndex)
        if key and idx then
            series[key] = series[key] or {}
            table.insert(series[key], b)
            if b.readStatus == "read" then any_read[key] = true end
        end
    end
    for _i, e in ipairs(removed) do
        local key = seriesKey(e.series)
        if key then any_read[key] = true end
    end
    local out = {}
    for key, list in pairs(series) do
        if any_read[key] then
            sortByKey(list, function(b) return tonumber(b.seriesIndex) end, lowerTitle)
            for _i, b in ipairs(list) do
                if b.readStatus ~= "read" then
                    if b.readStatus == "unread" then out[#out + 1] = b end
                    break
                end
            end
        end
    end
    -- Series with the most recently read first, then by title.
    local last = {}
    for _i, b in ipairs(books or {}) do
        local key = seriesKey(b.series)
        if key and (tonumber(b.last_open) or 0) > (last[key] or 0) then last[key] = tonumber(b.last_open) end
    end
    sortByKey(out, function(b) return -(last[seriesKey(b.series)] or 0) end, lowerTitle)
    return out
end

function Local:dashboardLists()
    local cache = self._group_cache
    if not cache or cache.books ~= self.books or cache.count ~= #self.books then
        cache = { books = self.books, count = #self.books }
        self._group_cache = cache
    end
    local sig = Local.stateSignature(self.books)
    local lists = cache.dashboard
    if lists and lists.sig == sig then return lists end
    local reading = self:query{read_status = "reading", sort = "last_read"}
    local highlights = {}
    for _i, b in ipairs(self.books) do
        for _i, h in ipairs(b.highlights or {}) do highlights[#highlights+1] = h end
    end
    local next_books = Local.upNext(self.books)
    lists = {
        sig = sig, reading = reading,
        unread = self:query{read_status = "unread"},
        finished = self:query{read_status = "read", sort = "last_read"},
        recent = self:query{sort = "recently_added"},
        highlights = highlights, next_books = next_books,
        authors = self:groups("authors"), series = self:groups("series"),
    }
    cache.dashboard = lists
    return lists
end

function Local:dashboard()
    local lists = self:dashboardLists()
    local reading, unread, finished = lists.reading, lists.unread, lists.finished
    local highlights = lists.highlights
    local year, done = os.date("%Y"), {}
    for _i, b in ipairs(finished) do
        if type(b.finishedOn) == "string" and b.finishedOn:sub(1,4) == year then done[#done+1] = b end
    end
    -- Books finished this year and deleted since still count
    -- (aleph_finished_log.lua).
    local ok_log, removed = pcall(function() return require("aleph_finished_log").removed(self.books) end)
    for _i, b in ipairs(ok_log and removed or {}) do
        if b.finishedOn:sub(1,4) == year then done[#done+1] = b end
    end
    -- Discover: unread books, and in a series only the next one to read.
    -- Shuffled again on every refresh, so it is not kept with the lists.
    local random = Local.discoverable(self.books)
    local next_books = lists.next_books
    local daily = require("aleph_stats_reader").getDailySeconds(0) or {}
    local dates, longest, run, prev = {}, 0, 0, nil
    for day, seconds in pairs(daily) do if seconds > 0 then dates[#dates+1] = day end end
    table.sort(dates)
    local function previous(day)
        local y,m,d = day:match("(%d+)-(%d+)-(%d+)")
        return os.date("%Y-%m-%d", os.time{year=y,month=m,day=d-1,hour=12})
    end
    for _i, day in ipairs(dates) do
        run = prev == previous(day) and run + 1 or 1
        longest = math.max(longest,run); prev = day
    end
    local day, current = os.date("%Y-%m-%d"), 0
    if not daily[day] or daily[day] <= 0 then day = previous(day) end
    while (daily[day] or 0) > 0 do current = current+1; day = previous(day) end
    local authors, series = lists.authors, lists.series
    local function labels(groups) local a = {}; for _i, g in ipairs(groups) do a[#a+1]=g.name end; return a end
    return {displayName = self.settings.display_name, generatedAt = iso(os.time()),
        totalBooks = #self.books, continueReading = reading, discover = random,
        finishedThisYear = done, readingGoal = {year=tonumber(year), goalBooks=self.settings.year_goal or 12, completedBooks=#done},
        readingStreak = {currentStreak=current, longestStreak=longest},
        highlightOfTheDay = #highlights > 0 and highlights[(tonumber(os.date("%j"))-1) % #highlights+1] or nil,
        browseCounts = {authors=#authors,series=#series,inProgress=#reading,read=#finished,libraries=#(self.settings.library_roots or {}),
            collections=#self:collectionList()},
        boardNames = {authors=labels(authors),series=labels(series),collections=(function()
            local t = {}
            for _i, c in ipairs(self:collectionList()) do t[#t+1] = c.title end
            return t
        end)()},
        boardShelves = { ["random"]=random, ["recently-added"]=lists.recent,
            ["in-progress"]=reading, ["want-to-read"]=unread, ["unopened"]=unread,
            ["pick-back-up"]=reading, ["up-next-in-series"]=next_books, ["finished"]=done, ["read"]=finished } }
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

-- A cover that takes no work: the one already known, a custom cover, or a
-- thumbnail saved earlier. Returns its path; or nil, then the thumbnail's
-- path and height when one can be made from the book (Local.extractCover).
function Local:coverQuick(book)
    if book.cover_path then
        if lfs.attributes(book.cover_path,"mode") == "file" then return book.cover_path end
        book.cover_path = nil
    end
    local ok_custom, custom = pcall(DocSettings.findCustomCoverFile, DocSettings, book.path)
    if ok_custom and custom then book.cover_path = custom; return custom end
    if not (book.modified and book.size) then return nil end
    local dir = DataStorage:getDataDir() .. "/cache/aleph/thumbs"
    util.makePath(dir)
    local th = thumbHeight()
    local key = require("ffi/sha2").md5(book.path .. ":" .. book.modified .. ":" .. book.size .. ":" .. th)
    local path = dir .. "/" .. key .. ".png"
    if lfs.attributes(path,"mode") == "file" then book.cover_path=path; return path end
    return nil, path, th
end

-- Makes the thumbnail `target` (no taller than th) from the book's own
-- cover: the book is opened for it, the slow part. Takes only paths, so it
-- can run in a background process (aleph_cover_job.lua). The picture is
-- written beside its place and moved there whole, so a half-written file
-- is never taken for a cover. True when the thumbnail is there.
function Local.extractCover(book_path, target, th)
    local bb
    local ok = pcall(function()
        bb = require("apps/filemanager/filemanagerbookinfo"):getCoverImage(nil, book_path)
        if bb and bb:getHeight() > th then
            local nw = math.max(1, math.floor(bb:getWidth() * th / bb:getHeight() + 0.5))
            -- true: the full-size original is released as it is scaled.
            bb = require("ui/renderimage"):scaleBlitBuffer(bb, nw, th, true)
        end
        if bb then
            local part = target .. ".part"
            bb:writePNG(part)
            if lfs.attributes(part,"mode") == "file" then os.rename(part, target) end
        end
    end)
    if bb then pcall(bb.free, bb) end
    return ok and lfs.attributes(target,"mode") == "file" or false
end

-- The book's cover, made now if need be (the screen waits for it). Home
-- makes covers in the background instead (Browser:queueCovers); this is for
-- where that cannot be done.
function Local:cover(book)
    if book.cover_path and lfs.attributes(book.cover_path,"mode") == "file" then return book.cover_path end
    if book.cover_checked then return nil end
    book.cover_checked = true
    local path, target, th = self:coverQuick(book)
    if path then return path end
    if target and Local.extractCover(book.path, target, th) then book.cover_path = target; return target end
end

return Local
