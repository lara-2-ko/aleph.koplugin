-- Aleph modification, 2026-11-11: the other e-reader's progress, from
-- Syncery's files, before the book is opened here.
--[[--
Syncery keeps each book's position on every device in a shared file:

  hash mode  <settings>/syncery/synceryhash/<md5 first 2>/<md5>/syncery-progress.json
  sdr mode   <the book's sidecar folder>/<book file name>.syncery-progress.json

  { "schema_version": 1, "entries": { "<device id>": { percent = 0..1,
    label = "Colorsoft", timestamp = <epoch>, ... }, ... } }

KOReader's own percentage changes only when the book is opened here (that
is when Syncery offers the jump), so the library and the book's page show
the newest other device's position beside it: "60% on Colorsoft".

The book is found by KOReader's partial MD5 (what Syncery uses). When the
two e-readers hold different copies of the file (sent separately, for
instance), the MD5s differ and Syncery treats them as two books: the
title.txt Syncery writes next to each file finds it then, and the page says
the copies differ (Syncery cannot jump between them).
]]

local try = require("aleph_try").call
local Remote = {}

local lfs_ok, lfs = pcall(require, "libs/libkoreader-lfs")

local function attr(path, what)
    if not lfs_ok then return nil end
    return lfs.attributes(path, what)
end

function Remote.root()
    local ok, dir = pcall(function() return require("datastorage"):getSettingsDir() end)
    return (ok and dir or ".") .. "/syncery/synceryhash"
end

local function decode(path)
    local ok, v = pcall(function()
        local rj = require("rapidjson")
        return rj.load(path)
    end)
    if ok and type(v) == "table" then return v end
    ok, v = pcall(function()
        local f = io.open(path, "r")
        if not f then return nil end
        local data = f:read("*a")
        f:close()
        return require("json").decode(data)
    end)
    if ok and type(v) == "table" then return v end
    return nil
end
Remote.decode = decode

-- ------------------------------------------------------------ finding it
local title_index = { at = 0, map = nil }

-- What Syncery's folder holds, cheaply: the modification times of the
-- folder and of its two-letter shard folders. A book Syncery adds or removes
-- changes its shard's time; the title.txt files are read again only then.
local function folderSignature(root)
    if attr(root, "mode") ~= "directory" then return "none" end
    local parts = { tostring(attr(root, "modification")) }
    try(function()
        for shard in lfs.dir(root) do
            if shard ~= "." and shard ~= ".." and #shard <= 4 then
                parts[#parts + 1] = shard .. "=" .. tostring(attr(root .. "/" .. shard, "modification"))
            end
        end
    end)
    table.sort(parts)
    return table.concat(parts, ";")
end
Remote.folderSignature = folderSignature

-- title key -> progress file, from Syncery's title.txt files. Looked at
-- again at most once a minute, and read again only when the folder changed.
function Remote.titleIndex(force)
    local now = os.time()
    if title_index.map and not force and now - title_index.at < 60 then return title_index.map end
    local root = Remote.root()
    local sig = folderSignature(root)
    -- (Read again every ten minutes anyway: a book's folder can appear a
    -- moment before Syncery writes its title in it.)
    if title_index.map and not force and title_index.sig == sig and now - (title_index.built or 0) < 600 then
        title_index.at = now
        return title_index.map
    end
    local map = {}
    try(function()
        if attr(root, "mode") ~= "directory" then return end
        local Import = require("aleph_goodreads_import")
        for shard in lfs.dir(root) do
            if shard ~= "." and shard ~= ".." and #shard <= 4 then
                local sdir = root .. "/" .. shard
                if attr(sdir, "mode") == "directory" then
                    for id in lfs.dir(sdir) do
                        if id ~= "." and id ~= ".." then
                            local dir = sdir .. "/" .. id
                            local f = io.open(dir .. "/title.txt", "r")
                            if f then
                                local title = f:read("*l") or ""
                                f:close()
                                local full = Import.titleKeys(title)
                                if full ~= "" and attr(dir .. "/syncery-progress.json", "mode") == "file" then
                                    map[full] = map[full] or {}
                                    table.insert(map[full], { path = dir .. "/syncery-progress.json", id = id })
                                end
                            end
                        end
                    end
                end
            end
        end
    end)
    title_index.at, title_index.map, title_index.sig, title_index.built = now, map, sig, now
    return map
end

-- The progress files that may be this book's: { path, other_copy } each.
function Remote.files(book)
    local out = {}
    if type(book) ~= "table" or type(book.path) ~= "string" then return out end
    local md5 = type(book.md5) == "string" and book.md5 ~= "" and book.md5 or nil
    if md5 then
        local p = Remote.root() .. "/" .. md5:sub(1, 2) .. "/" .. md5 .. "/syncery-progress.json"
        if attr(p, "mode") == "file" then out[#out + 1] = { path = p } end
    end
    try(function()
        local dir = require("docsettings"):getSidecarDir(book.path)
        local name = book.path:match("([^/]+)$")
        local p = dir .. "/" .. name .. ".syncery-progress.json"
        if attr(p, "mode") == "file" then out[#out + 1] = { path = p } end
    end)
    -- Another copy of the same book, by its title.
    try(function()
        local full = require("aleph_goodreads_import").titleKeys(book.title)
        for _i, hit in ipairs(Remote.titleIndex()[full] or {}) do
            if hit.id ~= md5 then out[#out + 1] = { path = hit.path, other_copy = true } end
        end
    end)
    return out
end

-- ------------------------------------------------------------ reading it
local cache = {}

local function entriesOf(path)
    local mtime = attr(path, "modification")
    if not mtime then return nil end
    local hit = cache[path]
    if hit and hit.mtime == mtime then return hit.entries end
    local data = decode(path)
    local entries = type(data) == "table" and type(data.entries) == "table" and data.entries or {}
    cache[path] = { mtime = mtime, entries = entries }
    return entries
end

local function myId()
    return G_reader_settings:readSetting("device_id") or G_reader_settings:readSetting("syncery_device_id")
end
Remote.myId = myId

-- The newest position of another device: { pct (0-100), label, time,
-- other_copy } or nil.
function Remote.other(book)
    local mine = myId()
    local best
    for _i, f in ipairs(Remote.files(book)) do
        for id, e in pairs(entriesOf(f.path) or {}) do
            if id ~= mine and type(e) == "table" and tonumber(e.percent) then
                local t = tonumber(e.timestamp) or 0
                if not best or t > best.time then
                    local p = tonumber(e.percent)
                    if p <= 1 then p = p * 100 end
                    best = { pct = math.max(0, math.min(100, p)), label = tostring(e.label or "?"), time = t, other_copy = f.other_copy }
                end
            end
        end
    end
    return best
end

-- "60% on Colorsoft" when another device is further on than this one, or
-- nil. A finished book here says nothing.
function Remote.note(book)
    if type(book) ~= "table" or book.readStatus == "read" then return nil end
    local ok, r = pcall(Remote.other, book)
    if not ok or not r then return nil end
    local here = tonumber(book.progressPercentage) or 0
    if r.pct < here + 1 then return nil end
    local pct = math.floor(r.pct + 0.5)
    if pct >= 100 then pct = 99 end
    local T = require("ffi/util").template
    local _ = require("aleph_gettext")
    return T(_("%1% on %2"), pct, r.label), r
end

-- For tests: forget what was read.
function Remote._reset() cache = {}; title_index = { at = 0, map = nil } end

return Remote
