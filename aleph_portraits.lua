-- Aleph modification, 2026-11-08: author portraits.
--[[--
Optional (Settings > Author portraits): looks up a photo of each author and
shows it, round, in the Authors list. Nothing is looked up unless it is turned
on, and the only thing sent is the author's name.

Sources, in order:
  1. Open Library (openlibrary.org): finds the author, then their photo.
  2. Wikipedia: the page for the name, if it is described as a writer, and
     its picture.
A name with no photo is remembered as such and tried again after 30 days.

Photos are saved in KOReader's cache folder (cache/aleph/authors). One
author is looked up about every second, in the background, and only on Wi-Fi
that is already on. While a request runs the screen waits for it (a few
hundred milliseconds, at most 8 seconds if the network is slow).
]]

local Blitbuffer = require("ffi/blitbuffer")
local DataStorage = require("datastorage")
local Widget = require("ui/widget/widget")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")

local BoardMetrics = require("aleph_board_metrics")

local INK = BoardMetrics.INK
local px = BoardMetrics.px
local floor, sqrt = math.floor, math.sqrt

local Portraits = {}

local USER_AGENT = "Aleph-KOReader/1.0 (local e-reader plugin; author portraits)"
local RETRY_AFTER = 30 * 24 * 3600

-- ------------------------------------------------------------------ store
local function dir()
    local d = DataStorage:getDataDir() .. "/cache/aleph/authors"
    if lfs.attributes(d, "mode") ~= "directory" then require("util").makePath(d) end
    return d
end

local index
local function store()
    if not index then
        index = require("luasettings"):open(dir() .. "/index.lua")
    end
    return index
end

-- "Rowling, J. K." and "J.K. Rowling" are the same author.
local function normalize(name)
    name = tostring(name or "")
    local last, first = name:match("^([^,]+),%s*(.+)$")
    if last then name = first .. " " .. last end
    name = name:lower():gsub("[%p]", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    return name
end

local function keyOf(name)
    return require("ffi/sha2").md5(normalize(name))
end

function Portraits.pathFor(name)
    local entry = store():readSetting(keyOf(name))
    if entry and entry.ok and entry.file then
        local path = dir() .. "/" .. entry.file
        if lfs.attributes(path, "mode") == "file" then return path end
    end
end

function Portraits.count()
    local n = 0
    for key, entry in pairs(store().data) do
        if type(entry) == "table" and entry.ok and entry.file then n = n + 1 end
    end
    return n
end

function Portraits.clear()
    local d = dir()
    for entry in lfs.dir(d) do
        if entry ~= "." and entry ~= ".." then os.remove(d .. "/" .. entry) end
    end
    index = nil
    Portraits.disposeCache()
end

-- ---------------------------------------------------------------- network
local function get(url)
    local ltn12 = require("ltn12")
    local socketutil = require("socketutil")
    local body = {}
    socketutil:set_timeout(8, 20)
    local ok, code = pcall(function()
        local https = require("ssl.https")
        local _r, status = https.request{
            url = url, method = "GET", sink = ltn12.sink.table(body),
            headers = { ["User-Agent"] = USER_AGENT, ["Accept"] = "*/*" },
        }
        return status
    end)
    socketutil:reset_timeout()
    if ok and code == 200 then return table.concat(body) end
    return nil, ok and code or "error"
end

local function json(body)
    local ok, data = pcall(function() return require("json").decode(body) end)
    return ok and type(data) == "table" and data or nil
end

local function urlencode(s)
    return (tostring(s):gsub("[^%w%-_%.~]", function(c) return string.format("%%%02X", c:byte()) end))
end

-- Every word of the author's name is in the candidate's name.
local function sameName(wanted, candidate)
    local a, b = normalize(wanted), normalize(candidate)
    if a == b then return true end
    for word in a:gmatch("%S+") do
        if not (" " .. b .. " "):find(" " .. word .. " ", 1, true) then return false end
    end
    return a:find(" ", 1, true) ~= nil
end

local function imageExtension(data)
    if not data or #data < 1000 then return nil end
    if data:sub(1, 2) == "\255\216" then return "jpg" end
    if data:sub(1, 4) == "\137PNG" then return "png" end
end

local function fromOpenLibrary(name)
    local body = get("https://openlibrary.org/search/authors.json?limit=5&q=" .. urlencode(name))
    local data = body and json(body)
    for _i, doc in ipairs(data and data.docs or {}) do
        if doc.key and sameName(name, doc.name) then
            local photo = get("https://covers.openlibrary.org/a/olid/" .. doc.key .. "-M.jpg?default=false")
            if imageExtension(photo) then return photo, "openlibrary" end
        end
    end
end

local WRITER = { "writer", "author", "novelist", "poet", "playwright", "essayist", "journalist", "biograph",
    "historian", "screenwriter", "illustrator", "translator", "critic", "columnist" }

local function fromWikipedia(name)
    local url = "https://en.wikipedia.org/w/api.php?action=query&format=json&redirects=1&generator=search&gsrlimit=4"
        .. "&prop=pageimages%7Cdescription&piprop=thumbnail&pithumbsize=320&gsrsearch=" .. urlencode(name .. " writer")
    local body = get(url)
    local data = body and json(body)
    local pages = data and data.query and data.query.pages
    for _id, page in pairs(pages or {}) do
        local thumb = page.thumbnail and page.thumbnail.source
        local description = tostring(page.description or ""):lower()
        local is_writer = false
        for _i, word in ipairs(WRITER) do
            if description:find(word, 1, true) then is_writer = true; break end
        end
        if thumb and is_writer and sameName(name, page.title) then
            local photo = get(thumb)
            if imageExtension(photo) then return photo, "wikipedia" end
        end
    end
end

-- One author: the photo's bytes and where they came from, or nothing.
local function lookup(name)
    local photo, source = fromOpenLibrary(name)
    if photo then return photo, source end
    return fromWikipedia(name)
end

-- ------------------------------------------------------------------ queue
local queue, queued = {}, {}
local running = false
local run = { total = 0, done = 0, found = 0, on_progress = nil, on_done = nil }
local listener

function Portraits.setListener(fn)
    listener = fn
end

local notify_scheduled = false
local function notify()
    if notify_scheduled or not listener then return end
    notify_scheduled = true
    UIManager:scheduleIn(1.5, function()
        notify_scheduled = false
        if listener then pcall(listener) end
    end)
end

local function online()
    local ok, connected = pcall(function() return require("ui/network/manager"):isConnected() end)
    return ok and connected
end

local function due(name)
    local entry = store():readSetting(keyOf(name))
    if not entry then return true end
    if entry.ok then return false end
    return (os.time() - (entry.at or 0)) > RETRY_AFTER
end

local pump
local function schedule(seconds)
    if running then return end
    running = true
    UIManager:scheduleIn(seconds or 1, pump)
end

local function finishRun()
    if run.total > 0 then
        local done = run.on_done
        local found, total = run.found, run.total
        run.total, run.done, run.found, run.on_progress, run.on_done = 0, 0, 0, nil, nil
        if done then pcall(done, found, total) end
    end
end

pump = function()
    running = false
    local name = table.remove(queue, 1)
    if not name then return finishRun() end
    queued[normalize(name)] = nil
    if not online() then
        -- Wi-Fi is off: keep the rest for next time and stop quietly.
        queue, queued = {}, {}
        return finishRun()
    end
    local ok, photo, source = pcall(lookup, name)
    local key = keyOf(name)
    if ok and photo then
        local file = key .. "." .. imageExtension(photo)
        local f = io.open(dir() .. "/" .. file, "wb")
        if f then
            f:write(photo)
            f:close()
            store():saveSetting(key, { ok = true, file = file, src = source, at = os.time() })
            run.found = run.found + 1
            notify()
        end
    elseif ok then
        store():saveSetting(key, { ok = false, at = os.time() })
    else
        logger.warn("Aleph: portrait lookup failed:", photo)
    end
    run.done = run.done + 1
    if run.on_progress then pcall(run.on_progress, run.done, run.total, run.found) end
    if run.done % 10 == 0 then pcall(function() store():flush() end) end
    if #queue == 0 then
        pcall(function() store():flush() end)
        return finishRun()
    end
    schedule(1)
end

-- Adds the names not looked up yet (the ones the Authors list shows).
function Portraits.request(names)
    local added = false
    for _i, name in ipairs(names or {}) do
        local n = normalize(name)
        if n ~= "" and not queued[n] and due(name) and #queue < 400 then
            queued[n] = true
            queue[#queue + 1] = name
            run.total = run.total + 1
            added = true
        end
    end
    if added then schedule(0.5) end
end

-- All the authors, with progress and a result.
function Portraits.downloadAll(names, on_progress, on_done)
    run.on_progress, run.on_done = on_progress, on_done
    for _i, name in ipairs(names or {}) do
        local n = normalize(name)
        if n ~= "" and not queued[n] and due(name) then
            queued[n] = true
            queue[#queue + 1] = name
            run.total = run.total + 1
        end
    end
    if run.total == 0 then return finishRun() end
    schedule(0.2)
end

function Portraits.running()
    return #queue > 0 or running, run.done, run.total
end

function Portraits.cancel()
    queue, queued = {}, {}
    finishRun()
end

-- How many of `names` have no answer yet.
function Portraits.pending(names)
    local n = 0
    for _i, name in ipairs(names or {}) do
        if due(name) then n = n + 1 end
    end
    return n
end

-- ----------------------------------------------------------------- widget
-- A round portrait of diameter d: the photo cropped square (a little above the
-- middle, where faces are), scaled, and cut to a circle with an alpha mask.
local cache, order = {}, {}

function Portraits.disposeCache()
    for key, bb in pairs(cache) do if bb and bb.free then bb:free() end end
    cache, order = {}, {}
end

local function disc(path, d)
    local key = path .. ":" .. d
    if cache[key] ~= nil then return cache[key] or nil end
    local ok, result = pcall(function()
        local RenderImage = require("ui/renderimage")
        local img = RenderImage:renderImageFile(path, false)
        if not img then return nil end
        local iw, ih = img:getWidth(), img:getHeight()
        local side = math.min(iw, ih)
        local sq = Blitbuffer.new(side, side, Blitbuffer.TYPE_BBRGB32)
        sq:blitFrom(img, 0, 0, floor((iw - side) / 2), floor((ih - side) * 0.2), side, side)
        img:free()
        local scaled = RenderImage:scaleBlitBuffer(sq, d, d, true)
        local out = Blitbuffer.new(d, d, Blitbuffer.TYPE_BBRGB32)
        out:blitFrom(scaled, 0, 0, 0, 0, d, d)
        scaled:free()
        local r = d / 2
        for y = 0, d - 1 do
            for x = 0, d - 1 do
                local dx, dy = x + 0.5 - r, y + 0.5 - r
                local dist = sqrt(dx * dx + dy * dy)
                local alpha = dist <= r - 1 and 255 or (dist < r and floor((r - dist) * 255) or 0)
                out:getPixelP(x, y).alpha = alpha
            end
        end
        return out
    end)
    if not ok then logger.warn("Aleph: portrait could not be drawn:", result) end
    cache[key] = ok and result or false
    if ok and result then
        order[#order + 1] = key
        if #order > 60 then
            local old = table.remove(order, 1)
            if cache[old] and cache[old].free then cache[old]:free() end
            cache[old] = nil
        end
    end
    return cache[key] or nil
end

local Portrait = Widget:extend{ path = nil, d = 0 }

function Portrait:getSize()
    return { w = self.d, h = self.d }
end

function Portrait:paintTo(bb, x, y)
    local r = self.d / 2
    local img = disc(self.path, self.d)
    if img then
        bb:alphablitFrom(img, x, y, 0, 0, self.d, self.d)
    else
        bb:paintCircle(floor(x + r), floor(y + r), floor(r), INK.ge)
    end
    bb:paintCircle(floor(x + r), floor(y + r), floor(r), INK.g6, math.max(1, px(1.25)))
end

function Portraits.widget(path, d)
    return Portrait:new{ path = path, d = d }
end

return Portraits
