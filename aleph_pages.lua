-- Aleph modification, 2026-11-10: a book's page count, from Calibre first.
--[[--
Calibre keeps a page count in a custom column (the Count Pages plugin's
"#pages", or any column whose name says pages). It reaches the device in
three ways, tried in this order:

  1. metadata.opf next to the book (a Calibre library folder, or Save to disk)
  2. the OPF inside an EPUB: Calibre writes its custom columns there when it
     sends or saves a book with its metadata
  3. metadata.calibre (or .metadata.calibre) in a folder above the book,
     written by Calibre's device driver, when it still has the columns

Without any of them, KOReader's own count is used (it depends on the font
and margins), and the caption says so. Looked up when a book's page opens,
and kept until the files change.
]]

local lfs = require("libs/libkoreader-lfs")
local try = require("aleph_try").call

local Pages = {}

local function unescape(s)
    return (s:gsub("&quot;", '"'):gsub("&apos;", "'"):gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&amp;", "&"))
end

-- Whether a Calibre column name is a page count.
local function pageColumn(name)
    name = tostring(name or ""):lower():gsub("^#", "")
    return name:find("page", 1, true) ~= nil or name == "pgs"
end
Pages.pageColumn = pageColumn

local function positive(v)
    v = tonumber(v)
    if v and v >= 1 and v < 1e6 then return math.floor(v + 0.5) end
end

-- The page count in an OPF's text, or nil.
function Pages.fromOpf(xml)
    if type(xml) ~= "string" or xml == "" then return nil end
    -- OPF 2: one <meta name="calibre:user_metadata:#pages" content="{json}"/>
    -- per column (attributes in either order).
    for tag in xml:gmatch("<meta%s[^>]*>") do
        local name = tag:match('name%s*=%s*"calibre:user_metadata:([^"]+)"') or tag:match("name%s*=%s*'calibre:user_metadata:([^']+)'")
        if name and pageColumn(name) then
            local content = tag:match('content%s*=%s*"([^"]*)"') or tag:match("content%s*=%s*'([^']*)'")
            local n = content and positive(unescape(content):match('"#value#"%s*:%s*"?([%d%.]+)'))
            if n then return n end
        end
    end
    -- OPF 3: all columns in one <meta property="calibre:user_metadata">{json}</meta>.
    local blob = xml:match('<meta[^>]-property%s*=%s*"calibre:user_metadata"[^>]*>(.-)</meta>')
    if blob then
        blob = unescape(blob)
        for key, body in blob:gmatch('"(#[^"]+)"%s*:%s*(%b{})') do
            if pageColumn(key) then
                local n = positive(body:match('"#value#"%s*:%s*"?([%d%.]+)'))
                if n then return n end
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

-- 2. The OPF inside an EPUB, found through META-INF/container.xml.
function Pages.epubOpf(path)
    local ok, xml = pcall(function()
        local Archiver = require("ffi/archiver")
        local arc = Archiver.Reader:new()
        if not arc:open(path) then return nil end
        local container = arc:extractToMemory("META-INF/container.xml")
        local opf_path = container and container:match('full%-path%s*=%s*"([^"]+)"')
        local opf
        if opf_path then opf = arc:extractToMemory(opf_path) end
        if not opf then
            -- No container: the first .opf in the archive.
            for entry in arc:iterate() do
                if entry.mode == "file" and entry.path:lower():match("%.opf$") then
                    opf = arc:extractToMemory(entry.path)
                    break
                end
            end
        end
        arc:close()
        return opf
    end)
    return ok and xml or nil
end

-- 3. Calibre's device file: lpath -> pages, read once per file and change.
local device_files = {}
local function deviceIndex(file)
    local mtime = lfs.attributes(file, "modification")
    if not mtime then return nil end
    local hit = device_files[file]
    if hit and hit.mtime == mtime then return hit.map end
    local map = {}
    try(function()
        local books
        local ok_rj, rapidjson = pcall(require, "rapidjson")
        if ok_rj and rapidjson.load_calibre then books = rapidjson.load_calibre(file)
        elseif ok_rj and rapidjson.load then books = rapidjson.load(file)
        else books = require("json").decode(readFile(file)) end
        for _i, b in ipairs(books or {}) do
            local um = type(b) == "table" and b.user_metadata
            if type(b.lpath) == "string" and type(um) == "table" then
                for key, col in pairs(um) do
                    if pageColumn(key) and type(col) == "table" then
                        local n = positive(col["#value#"])
                        if n then map[b.lpath] = n; break end
                    end
                end
            end
        end
    end)
    device_files[file] = { mtime = mtime, map = map }
    return map
end

function Pages.fromDevice(path)
    local dir = path:match("^(.*)/[^/]*$")
    for _level = 1, 8 do
        if not dir or dir == "" then break end
        for _i, name in ipairs({ "metadata.calibre", ".metadata.calibre" }) do
            local file = dir .. "/" .. name
            if lfs.attributes(file, "mode") == "file" then
                local map = deviceIndex(file)
                local lpath = path:sub(#dir + 2)
                local n = map and map[lpath]
                if n then return n end
            end
        end
        dir = dir:match("^(.*)/[^/]*$")
    end
    return nil
end

-- KOReader's count: the sidecar's, as the book was last laid out.
local function koreaderPages(book)
    local n
    try(function()
        local ds = require("docsettings"):open(book.path)
        n = positive(ds:readSetting("doc_pages"))
        if not n then
            local stats = ds:readSetting("stats")
            n = positive(type(stats) == "table" and stats.pages)
        end
    end)
    return n or positive(book.props and book.props.pages)
end

-- The year a book came out, from an OPF's dc:date (the publication date,
-- not a modification date), or nil. Calibre writes 0101-01-01 for "none".
function Pages.yearFromOpf(xml)
    if type(xml) ~= "string" then return nil end
    local best
    for attrs, value in xml:gmatch("<dc:date([^>]*)>(.-)</dc:date>") do
        local event = attrs:match('event%s*=%s*"([^"]+)"')
        local year = tonumber(value:match("^%s*(%d%d%d%d)"))
        if year and year >= 1000 and year <= 2200 and (not event or event == "publication" or event == "original-publication") then
            if not best or event then best = year end
        end
    end
    return best
end

-- The ISBN in an OPF's dc:identifier (opf:scheme="ISBN", urn:isbn:, or a
-- 13-digit 978/979 number), or nil.
function Pages.isbnFromOpf(xml)
    if type(xml) ~= "string" then return nil end
    for attrs, value in xml:gmatch("<dc:identifier([^>]*)>(.-)</dc:identifier>") do
        local v = value:gsub("^%s*urn:isbn:", ""):gsub("[%s%-]", "")
        local scheme = (attrs:match('scheme%s*=%s*"([^"]+)"') or ""):lower()
        if (scheme == "isbn" or value:lower():find("isbn", 1, true) or v:match("^97[89]%d%d%d%d%d%d%d%d%d%d$"))
                and (v:match("^%d%d%d%d%d%d%d%d%d[%dXx]$") or v:match("^%d%d%d%d%d%d%d%d%d%d%d%d%d$")) then
            return v:upper()
        end
    end
    return nil
end

-- What the library keeps of a book's OPF: { pages = n|nil, year = n|nil },
-- from metadata.opf next to the book or the OPF inside an EPUB. Read once
-- per file, when the library is scanned.
function Pages.bookInfo(path)
    local dir = path:match("^(.*)/[^/]*$") or ""
    local opf = dir .. "/metadata.opf"
    local info = {}
    if lfs.attributes(opf, "mode") == "file" then
        local xml = readFile(opf, 262144)
        info.pages, info.year, info.isbn = Pages.fromOpf(xml), Pages.yearFromOpf(xml), Pages.isbnFromOpf(xml)
    end
    if (not info.pages or not info.year) and path:lower():match("%.epub$") then
        local xml = Pages.epubOpf(path)
        info.pages = info.pages or Pages.fromOpf(xml)
        info.year = info.year or Pages.yearFromOpf(xml)
        info.isbn = info.isbn or Pages.isbnFromOpf(xml)
    end
    return info
end

local memo = {}

-- { pages = n, calibre = true|false } or nil.
function Pages.of(book)
    if type(book) ~= "table" or type(book.path) ~= "string" then return nil end
    local path = book.path
    local dir = path:match("^(.*)/[^/]*$") or ""
    local opf = dir .. "/metadata.opf"
    local opf_mtime = lfs.attributes(opf, "modification")
    local key = table.concat({ tostring(book.modified), tostring(opf_mtime) }, "|")
    local hit = memo[path]
    if hit and hit.key == key then
        if hit.result and hit.result.calibre then return hit.result end
        -- KOReader's own count changes as books are opened: asked again.
        local n = koreaderPages(book)
        return n and { pages = n, calibre = false } or nil
    end
    local n = book.opf and book.opf.pages
    if not n and opf_mtime then n = Pages.fromOpf(readFile(opf, 262144)) end
    if not n and path:lower():match("%.epub$") then n = Pages.fromOpf(Pages.epubOpf(path)) end
    if not n then n = Pages.fromDevice(path) end
    local result
    if n then result = { pages = n, calibre = true }
    else
        local k = koreaderPages(book)
        result = k and { pages = k, calibre = false } or false
    end
    memo[path] = { key = key, result = result }
    return result or nil
end

return Pages
