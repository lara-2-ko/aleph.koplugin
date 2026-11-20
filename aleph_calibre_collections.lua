-- Aleph modification, 2026-11-17: collections from Calibre.
--[[--
A Calibre column named "collections" (#collections) puts each book in
KOReader collections of those names, which are Aleph's collections too.

    Calibre: Preferences > Add your own columns > Lookup name "collections",
    type "Comma separated text, like tags". Fill it in; then polish or send
    the books with their metadata written into the files.

Where the column is found, for each book:
  1. metadata.opf next to the book (a Calibre library folder, Save to disk)
  2. the OPF inside an EPUB (Calibre writes its columns there when it sends,
     saves or polishes a book with its metadata)
  3. metadata.calibre (or .metadata.calibre) in a folder above the book, as
     Calibre's USB driver writes it (KOReader's wireless connection keeps
     only title, authors, tags and series there, so it is 1 and 2 then)

Calibre mirrored, the device's own left alone: a book is put in each of its
collections, and taken out of one again when the column no longer names it
(the book sent again). Only places Aleph made are undone, so books added to
a collection on the device, and collections made there, are never touched.

Light on the device: each book's file is read once, and again only when it
changes (size or time), in a background process when there is one; the
answers are kept in settings/aleph_calibre_collections.lua. It runs after a
library scan and when Home opens, at most once a minute.

Settings > Library > Collections from Calibre (aleph.calibre_collections,
on unless turned off).
]]

local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")

local CC = {}

CC.MIN_GAP = 60          -- seconds between two runs
CC.TIMEOUT = 300         -- the background reading is stopped after this

local running = false
local last_run = 0

-- ------------------------------------------------------------- settings
function CC.enabled()
    local ok, on = pcall(function() return require("aleph_prefs").on("calibre_collections") end)
    return not ok or on
end

local function stateFile()
    return require("datastorage"):getSettingsDir() .. "/aleph_calibre_collections.lua"
end

local function loadState()
    local s = require("aleph_file").read(stateFile())
    if type(s) ~= "table" then s = {} end
    s.books = type(s.books) == "table" and s.books or {}     -- [path] = { m, s, c = { names } }
    s.placed = type(s.placed) == "table" and s.placed or {}  -- [name] = { [path] = true }: what Aleph put there
    return s
end

-- ------------------------------------------------------- the column
local function unescape(s)
    return (s:gsub("&quot;", '"'):gsub("&#34;", '"'):gsub("&apos;", "'"):gsub("&#39;", "'")
        :gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&amp;", "&"))
end

-- Whether a column's lookup name is the collections column.
function CC.isColumn(key)
    key = tostring(key or ""):lower():gsub("^#", "")
    return key == "collections" or key == "collection"
end

local function decode(text)
    local ok, v = pcall(function()
        local ok_rj, rapidjson = pcall(require, "rapidjson")
        if ok_rj and rapidjson and rapidjson.decode then return rapidjson.decode(text) end
        return require("json").decode(text)
    end)
    return ok and v or nil
end

local function trim(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end

-- The names in one column's data (a table, as Calibre writes it: "#value#"
-- a list, or a text of names split as the column splits them).
function CC.namesOf(col)
    if type(col) ~= "table" then return nil end
    local v = col["#value#"]
    local out, seen = {}, {}
    local function add(name)
        name = trim(name)
        if name ~= "" and not seen[name] then seen[name] = true; out[#out + 1] = name end
    end
    if type(v) == "table" then
        for _i, name in ipairs(v) do if type(name) == "string" then add(name) end end
    elseif type(v) == "string" then
        local sep = type(col.is_multiple) == "table" and type(col.is_multiple.ui_to_list) == "string" and col.is_multiple.ui_to_list or ","
        sep = trim(sep) ~= "" and trim(sep) or ","
        local from = 1
        while true do
            local a, b = v:find(sep, from, true)
            if not a then add(v:sub(from)); break end
            add(v:sub(from, a - 1))
            from = b + 1
        end
    elseif v == nil then
        return nil
    end
    table.sort(out)
    return out
end

-- The collections an OPF's text names: a list (empty when the column is
-- there with nothing in it), or nil when the OPF has no such column.
-- isColumn (optional): which column, CC.isColumn unless given (Reading
-- bingo asks for #bingo with it).
function CC.fromOpf(xml, isColumn)
    isColumn = isColumn or CC.isColumn
    if type(xml) ~= "string" or xml == "" then return nil end
    -- OPF 2: <meta name="calibre:user_metadata:#collections" content="{json}"/>
    for tag in xml:gmatch("<[%w_]*:?meta%s[^>]*>") do
        local name = tag:match('name%s*=%s*"calibre:user_metadata:([^"]+)"') or tag:match("name%s*=%s*'calibre:user_metadata:([^']+)'")
        if name and isColumn(name) then
            local content = tag:match('content%s*=%s*"([^"]*)"') or tag:match("content%s*=%s*'([^']*)'")
            local names = content and CC.namesOf(decode(unescape(content)))
            if names then return names end
        end
    end
    -- OPF 3: <meta property="calibre:user_metadata">{json of every column}</meta>
    local blob = xml:match('<[%w_]*:?meta[^>]-property%s*=%s*"calibre:user_metadata"[^>]*>(.-)</[%w_]*:?meta>')
    if blob then
        local all = decode(unescape(blob))
        if type(all) == "table" then
            for key, col in pairs(all) do
                if isColumn(key) then
                    local names = CC.namesOf(col)
                    if names then return names end
                end
            end
        end
    end
    return nil
end

local function readFile(path, limit)
    local f = io.open(path, "r")
    if not f then return nil end
    local data = f:read(limit or "*a")
    f:close()
    return data
end

-- Calibre's USB device file: lpath -> names, read once per file and change.
local device_files = {}
local function deviceIndex(file, isColumn, tag)
    isColumn = isColumn or CC.isColumn
    local mtime = lfs.attributes(file, "modification")
    if not mtime then return nil end
    local cache_key = file .. "|" .. (tag or "collections")
    local hit = device_files[cache_key]
    if hit and hit.mtime == mtime then return hit.map end
    local map = {}
    pcall(function()
        local books
        local ok_rj, rapidjson = pcall(require, "rapidjson")
        if ok_rj and rapidjson.load then books = rapidjson.load(file)
        else books = require("json").decode(readFile(file)) end
        for _i, b in ipairs(books or {}) do
            local um = type(b) == "table" and b.user_metadata
            if type(b.lpath) == "string" and type(um) == "table" then
                for key, col in pairs(um) do
                    if isColumn(key) then
                        local names = CC.namesOf(col)
                        if names then map[b.lpath] = names; break end
                    end
                end
            end
        end
    end)
    device_files[cache_key] = { mtime = mtime, map = map }
    return map
end

local function fromDevice(path, isColumn, tag)
    local dir = path:match("^(.*)/[^/]*$")
    for _level = 1, 8 do
        if not dir or dir == "" then break end
        for _i, name in ipairs({ "metadata.calibre", ".metadata.calibre" }) do
            local file = dir .. "/" .. name
            if lfs.attributes(file, "mode") == "file" then
                local map = deviceIndex(file, isColumn, tag)
                local names = map and map[path:sub(#dir + 2)]
                if names then return names end
            end
        end
        dir = dir:match("^(.*)/[^/]*$")
    end
    return nil
end

-- A book's collections from Calibre: a list, or false when Calibre's column
-- is nowhere for it.
function CC.read(path, isColumn, tag)
    local dir = path:match("^(.*)/[^/]*$") or ""
    local opf = dir .. "/metadata.opf"
    if lfs.attributes(opf, "mode") == "file" then
        local names = CC.fromOpf(readFile(opf, 262144), isColumn)
        if names then return names end
    end
    if path:lower():match("%.epub$") then
        local Pages = require("aleph_pages")
        local names = CC.fromOpf(Pages.epubOpf(path), isColumn)
        if names then return names end
    end
    return fromDevice(path, isColumn, tag) or false
end

-- ------------------------------------------------------------ the sync
local function realpath(path)
    local ok, real = pcall(function() return require("ffi/util").realpath(path) end)
    return ok and real or path
end

local function collections()
    local ok, RC = pcall(require, "readcollection")
    if not ok or type(RC) ~= "table" or not RC.addItem or not RC.removeItem or not RC.addCollection then return nil end
    if type(RC.coll) ~= "table" or next(RC.coll) == nil then
        if type(RC._read) == "function" then pcall(RC._read, RC) end
    end
    if type(RC.coll) ~= "table" then return nil end
    return RC
end

-- Puts the books in their collections and takes them out of the ones
-- Calibre no longer names. state.books holds what was read; paths: the
-- books in the library now. Returns how many places changed.
function CC.apply(state, paths, RC)
    RC = RC or collections()
    if not RC then return 0 end
    local changed, touched = 0, {}
    local wanted = {}         -- [path] = { [name] = true }, for books read
    for _i, path in ipairs(paths) do
        local entry = state.books[path]
        if entry and type(entry.c) == "table" then
            local set = {}
            for _j, name in ipairs(entry.c) do set[name] = true end
            wanted[path] = set
        elseif entry and entry.c == false then
            wanted[path] = {}
        end
    end
    -- Out first: places Aleph made that Calibre no longer names.
    for name, places in pairs(state.placed) do
        for path in pairs(places) do
            local want = wanted[path]
            if want and not want[name] then
                if RC.coll[name] then
                    local real = realpath(path)
                    if RC.coll[name][real] then
                        pcall(RC.removeItem, RC, real, name, true)
                        changed = changed + 1
                        touched[name] = true
                    end
                end
                places[path] = nil
            end
        end
        if next(places) == nil then state.placed[name] = nil end
    end
    -- In: each book in each collection it names.
    for path, want in pairs(wanted) do
        for name in pairs(want) do
            if not RC.coll[name] then
                pcall(RC.addCollection, RC, name)
                touched[name] = true
            end
            local real = realpath(path)
            if RC.coll[name] and not RC.coll[name][real] then
                local ok = pcall(RC.addItem, RC, real, name)
                if ok then
                    changed = changed + 1
                    touched[name] = true
                    state.placed[name] = state.placed[name] or {}
                    state.placed[name][path] = true
                end
            elseif RC.coll[name] and not (state.placed[name] and state.placed[name][path]) then
                -- Already there (put there on the device, or before): the
                -- device's own place, never taken out by Aleph.
            end
        end
    end
    if next(touched) then
        if not pcall(RC.write, RC, touched) then pcall(RC.write, RC) end
    end
    return changed
end

-- Aleph modification, 2026-11-19: whether Aleph put books in collection
-- `name` from Calibre (it then puts them back while Calibre names it).
function CC.fromCalibre(name)
    local placed = loadState().placed[name]
    return type(placed) == "table" and next(placed) ~= nil
end

-- A collection renamed or deleted on the device: Aleph forgets what it put
-- there, so a renamed collection is the device's own from now on and never
-- emptied by the next run (Calibre's name comes back on its own while
-- Calibre still has it).
function CC.forget(name)
    local state = loadState()
    if state.placed[name] == nil then return end
    state.placed[name] = nil
    require("aleph_file").write(stateFile(), state)
end

-- The books whose file changed since it was read (or never read).
function CC.toRead(state, books)
    local list = {}
    for _i, b in ipairs(books) do
        local path = b.path
        local attr = path and lfs.attributes(path)
        if attr and attr.mode == "file" then
            local e = state.books[path]
            local opf = (path:match("^(.*)/[^/]*$") or "") .. "/metadata.opf"
            local om = lfs.attributes(opf, "modification") or 0
            if not e or e.m ~= attr.modification or e.s ~= attr.size or (e.o or 0) ~= om then
                list[#list + 1] = { path = path, m = attr.modification, s = attr.size, o = om }
            end
        end
    end
    return list
end

local function finish(state, books, on_done)
    -- Books no longer in the library: their readings go (their places stay).
    local present, paths = {}, {}
    for _i, b in ipairs(books) do
        if b.path then present[b.path] = true; paths[#paths + 1] = b.path end
    end
    for path in pairs(state.books) do
        if not present[path] then state.books[path] = nil end
    end
    local ok, n = pcall(CC.apply, state, paths)
    if not ok then logger.warn("Aleph: Calibre collections:", n); n = 0 end
    pcall(require("aleph_file").write, stateFile(), state)
    running = false
    if n > 0 then logger.info("Aleph: Calibre collections: " .. n .. " change(s)") end
    if on_done then pcall(on_done, n) end
end

-- Reads what changed (in the background when it can) and syncs. books: the
-- library's books; on_done(n): n places changed. False when nothing ran.
function CC.sync(books, on_done, force)
    if running or not CC.enabled() or type(books) ~= "table" then return false end
    if not force and os.time() - last_run < CC.MIN_GAP then return false end
    running, last_run = true, os.time()
    local state = loadState()
    local list = CC.toRead(state, books)
    if #list == 0 then
        finish(state, books, on_done)
        return true
    end
    -- Memory low: the books are read another time (aleph_mem.lua).
    if require("aleph_mem").low() then
        running = false
        pcall(function() require("logger").info("Aleph: Calibre collections put off, memory low:", require("aleph_mem").describe()) end)
        return false
    end
    local Job = require("aleph_job")
    local File = require("aleph_file")
    local out = stateFile() .. ".read"
    if Job.available() then
        os.remove(out)
        local pid = Job.start(function()
            local got = {}
            for _i, item in ipairs(list) do
                local ok, names = pcall(CC.read, item.path)
                got[item.path] = { m = item.m, s = item.s, o = item.o, c = ok and names or false }
                -- Written as it goes, so a stop for time keeps what was read.
                if _i % 100 == 0 then File.write(out, got) end
            end
            File.write(out, got)
        end, { optional = true, name = "calibre collections" })
        if pid then
            Job.watch(pid, { every = 1, timeout = CC.TIMEOUT, on_done = function()
                local got = File.read(out)
                os.remove(out)
                if type(got) == "table" then
                    for path, e in pairs(got) do state.books[path] = e end
                end
                finish(state, books, on_done)
            end })
            return true
        end
    end
    -- No background process: read here, a few books at a time.
    local UIManager = require("ui/uimanager")
    local i = 0
    local function step()
        local t0 = os.clock()
        while i < #list and os.clock() - t0 < 0.08 do
            i = i + 1
            local item = list[i]
            local ok, names = pcall(CC.read, item.path)
            state.books[item.path] = { m = item.m, s = item.s, o = item.o, c = ok and names or false }
        end
        if i < #list then UIManager:scheduleIn(0.05, step) else finish(state, books, on_done) end
    end
    UIManager:nextTick(step)
    return true
end

-- For tests.
function CC._reset() running, last_run = false, 0 end

return CC
