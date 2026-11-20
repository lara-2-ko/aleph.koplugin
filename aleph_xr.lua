-- Aleph modification, 2026-11-14: Aleph's own X-Ray.
--[[--
The people, places and other names of the book that is open: who they are,
and where they were mentioned up to the page being read.

Made to cost nothing while reading:

  - Nothing runs when a page is turned. With the names underlined (an
    option), a turned page looks up its own few names, and nothing else.
  - A book is read for its names once, when asked, by a background process
    (the way KOReader's Cover browser reads books for their covers), which
    writes what it found next to the book's settings. Reading goes on
    meanwhile.
  - What it found is loaded only when X-Ray is opened (or, with the
    underlines on, a moment after the book).
  - With X-Ray off in Settings (it is off unless turned on), none of this
    file is loaded.

Three small files in the book's settings folder (where its highlights are):

    aleph_xray.lua        the names: { version, names = { { name, aliases,
                          count, person, kind, about, hidden }, ... }, ... }
    aleph_xray_hits.lua   where each is mentioned, in the book's order:
                          { n = { name index, ... }, s = { start, ... },
                            e = { end, ... } }
    aleph_xray_text.lua   the few words around each mention, read only when
                          a name's mentions are listed

The names come from the book's text alone (aleph_xr_names.lua). What each
one is, in a sentence or two, can be added by a language model for books
where that is wanted (aleph_xr_ai.lua); that is the only part that uses the
network, and only when asked.

Books KOReader lays out itself (EPUB, FB2, HTML, plain text...) only: a PDF
or a comic has no text positions to keep.

    XR.enabled()            X-Ray on in Settings (xray_enabled)
    XR.install()            the page's paint hook, once
    XR.attach(ui)           for the book that opens: the X-Ray button in the
                            text menu, the tap on an underlined name
    XR.detach(ui)           for the book that closes
    XR.scan(ui, on_done)    reads the book in the background
    XR.names(ui)            what was found, or nil
    XR.find(ui, text)       the entry for a word or a selection, and its index
    XR.open(ui, text)       the X-Ray sheet, or the card of the name in text

The mentions of a name are found with KOReader's own search
(CreDocument:findAllText), as the xray.koplugin by Jimmy Pautz does (MIT);
nothing else is taken from it.
]]

local Prefs = require("aleph_prefs")
local try = require("aleph_try").call

local XR = {}

XR.VERSION = 1
XR.MAX_HITS = 15000
-- A scan that takes longer than this is stopped.
XR.SCAN_WAIT = 420
-- Longest search pattern handed to KOReader's search at once.
local MAX_PATTERN = 2800
-- Words kept on each side of a mention.
local CONTEXT_WORDS = 7

function XR.enabled() return Prefs.is("xray_enabled") end
function XR.underlined() return Prefs.is("xray_underline") end
function XR.spoilers() return Prefs.is("xray_show_all") end

-- Whether this book can have an X-Ray.
function XR.supported(ui)
    local doc = ui and ui.document
    return ui ~= nil and ui.rolling ~= nil and doc ~= nil
        and type(doc.findAllText) == "function" and type(doc.getTextFromXPointers) == "function"
        and type(doc.compareXPointers) == "function"
end

-- ------------------------------------------------------------------ files
function XR.dir(ui)
    local DocSettings = require("docsettings")
    local ok, dir = pcall(function() return DocSettings:getSidecarDir(ui.document.file) end)
    return ok and type(dir) == "string" and dir or nil
end

-- The reader a background job's result belongs to. KOReader closes and
-- reopens a book by itself when its layout changes (a font or weight
-- change, the night profile's bolder text): the reader that started the job
-- is then gone, and another shows the same book. Returns that one; or, with
-- the book closed, a stand-in good enough to save the result with the book.
function XR.target(ui, file)
    if not file then return ui end
    if ui and ui.document and ui.document.file == file then return ui end
    local ok, ReaderUI = pcall(require, "apps/reader/readerui")
    local now = ok and type(ReaderUI) == "table" and rawget(ReaderUI, "instance") or nil
    if type(now) == "table" and now.document and now.document.file == file then return now end
    return { document = { file = file }, _aleph_xr = {} }
end

local function clean(str)
    return (tostring(str or ""):gsub("[%c]+", " "))
end

-- X-Ray's files are Lua tables, read and written by aleph_file.lua.
local File = require("aleph_file")
local writeFile, readFile = File.write, File.read
XR.writeFile = writeFile

-- ------------------------------------------------------- reading the book
-- Everything below, down to "the scan", runs in the background process (or
-- here, where there can be none): it only reads the document and writes
-- files.

-- A name as part of a search pattern (KOReader's search takes ECMAScript
-- expressions): its signs escaped, any white space between its words, and a
-- word boundary at each end that is a plain letter or digit (the boundary
-- only knows those).
local function termPattern(term)
    local esc = term:gsub("([%^%$%.%*%+%?%(%)%[%]%{%}|\\])", "\\%1"):gsub("%s+", "\\s+")
    if term:find("^[%w]") then esc = "\\b" .. esc end
    if term:find("[%w]$") then esc = esc .. "\\b" end
    return esc
end

-- The search patterns for a list of names: the longest names first, so
-- "Elizabeth Bennet" is found before "Elizabeth"; cut into several when
-- one would be too long. Also the map from a name's key to its index.
function XR.patterns(names)
    local Names = require("aleph_xr_names")
    local terms, lookup = {}, {}
    local function add(term, index)
        local key = Names.key(term)
        if key ~= "" and #term >= 2 and not lookup[key] then
            lookup[key] = index
            terms[#terms + 1] = term
        end
    end
    for index, entry in ipairs(names) do
        if not entry.hidden then
            add(entry.name, index)
            for _i, alias in ipairs(entry.aliases or {}) do add(alias, index) end
        end
    end
    table.sort(terms, function(a, b)
        if #a ~= #b then return #a > #b end
        return a < b
    end)
    local patterns, current, len = {}, {}, 0
    for _i, term in ipairs(terms) do
        local p = termPattern(term)
        if len + #p + 1 > MAX_PATTERN and #current > 0 then
            patterns[#patterns + 1] = "(" .. table.concat(current, "|") .. ")"
            current, len = {}, 0
        end
        current[#current + 1] = p
        len = len + #p + 1
    end
    if #current > 0 then patterns[#patterns + 1] = "(" .. table.concat(current, "|") .. ")" end
    return patterns, lookup
end

-- The book's names, from its text: a few pages at a time.
local function readNames(doc)
    local Names = require("aleph_xr_names")
    local state = Names.new()
    local pages = doc:getPageCount()
    local page, step = 1, 8
    while page < pages do
        local upto = math.min(page + step, pages)
        local ok, text = pcall(function()
            return doc:getTextFromXPointers(doc:getPageXPointer(page), doc:getPageXPointer(upto), false)
        end)
        if ok and type(text) == "string" and text ~= "" then Names.feed(state, text) end
        page = upto
    end
    return Names.finish(state)
end

-- Two lists of mentions, each in the book's order, made one.
local function merge(doc, a, b)
    local out, i, j = {}, 1, 1
    while i <= #a and j <= #b do
        local ok, order = pcall(doc.compareXPointers, doc, a[i].s, b[j].s)
        -- 1: b's is after a's.
        if not ok or order >= 0 then out[#out + 1] = a[i]; i = i + 1
        else out[#out + 1] = b[j]; j = j + 1 end
    end
    for k = i, #a do out[#out + 1] = a[k] end
    for k = j, #b do out[#out + 1] = b[k] end
    return out
end

-- Every mention of the names, in the book's order: { n = index, s, e, t }.
local function readHits(doc, names)
    local Names = require("aleph_xr_names")
    local patterns, lookup = XR.patterns(names)
    local all = {}
    for _i, pattern in ipairs(patterns) do
        local ok, found = pcall(function()
            return doc:findAllText(pattern, false, CONTEXT_WORDS, XR.MAX_HITS, true)
        end)
        local list = {}
        if ok and type(found) == "table" then
            for _j, hit in ipairs(found) do
                local s, e = hit.start, hit["end"]
                local index = lookup[Names.key(hit.matched_text or "")]
                if s and e and index then
                    list[#list + 1] = { n = index, s = s, e = e,
                        t = clean(hit.prev_text) .. " \1" .. clean(hit.matched_text) .. "\2 " .. clean(hit.next_text) }
                end
            end
        end
        all = #all == 0 and list or merge(doc, all, list)
    end
    for i = #all, XR.MAX_HITS + 1, -1 do all[i] = nil end
    return all
end

-- Reads the book and writes the three files. True when they were written.
function XR.work(doc, dir, keep)
    local names = keep or readNames(doc)
    local hits = readHits(doc, names)
    local counts = {}
    local n, s, e, t = {}, {}, {}, {}
    for i, hit in ipairs(hits) do
        n[i], s[i], e[i], t[i] = hit.n, hit.s, hit.e, hit.t
        counts[hit.n] = (counts[hit.n] or 0) + 1
    end
    for index, entry in ipairs(names) do entry.count = counts[index] or 0 end
    if not writeFile(dir .. "/aleph_xray_hits.lua", { n = n, s = s, e = e }) then return false end
    if not writeFile(dir .. "/aleph_xray_text.lua", { t = t }) then return false end
    -- The names last: they are what says the scan is done.
    return writeFile(dir .. "/aleph_xray.lua", { version = XR.VERSION, names = names, mentions = #hits, scanned = os.time() })
end

-- --------------------------------------------------------------- the scan
local job

function XR.scanning(ui)
    return job ~= nil and (ui == nil or job.file == (ui.document and ui.document.file))
end

local function finish(ok)
    local j = job
    job = nil
    if not j then return end
    local ui = XR.target(j.ui, j.file)
    if ui and ui._aleph_xr then
        -- What was loaded before is of the old scan.
        ui._aleph_xr = { attached = ui._aleph_xr.attached }
        if ok and XR.underlined() then try(XR.loadForPage, ui) end
    end
    for _i, fn in ipairs(j.done) do try(fn, ok) end
end

-- The scan has ended (stopped: it was taking too long).
local function scanned(stopped)
    local j = job
    if not j then return end
    local data = readFile(j.dir .. "/aleph_xray.lua")
    finish(not stopped and data ~= nil and (data.scanned or 0) >= j.started)
end

-- Reads the open book for its names (or, with keep_names, only looks again
-- for where the names it has are mentioned). on_done(ok) when it is over.
-- Returns false when it cannot start.
function XR.scan(ui, on_done, keep_names)
    if not XR.supported(ui) then return false end
    if job then
        if on_done and job.file == ui.document.file then table.insert(job.done, on_done) end
        return job.file == ui.document.file
    end
    local dir = XR.dir(ui)
    if not dir then return false end
    require("util").makePath(dir)
    local doc = ui.document
    local keep
    if keep_names then
        local data = XR.names(ui)
        keep = data and data.names or nil
    end
    job = { file = doc.file, dir = dir, ui = ui, started = os.time(), done = { on_done } }
    local Job = require("aleph_job")
    local pid = Job.start(function() pcall(XR.work, doc, dir, keep) end)
    if pid then
        job.pid = pid
        Job.watch(pid, { timeout = XR.SCAN_WAIT, on_done = scanned })
        return true
    end
    -- No background process on this device: read here. The screen waits.
    local ok, written = pcall(XR.work, doc, dir, keep)
    finish(ok and written == true)
    return true
end

-- ---------------------------------------------------------- what was found
local function state(ui)
    local st = ui._aleph_xr
    if not st then
        st = {}
        ui._aleph_xr = st
    end
    return st
end

-- The names file of the open book: { names = {...}, mentions, scanned, ai },
-- or nil when the book has not been read yet.
function XR.names(ui)
    local st = state(ui)
    if st.data == nil then
        local dir = XR.dir(ui)
        local data = dir and readFile(dir .. "/aleph_xray.lua") or nil
        if data and type(data.names) ~= "table" then data = nil end
        st.data = data or false
        st.lookup = nil
    end
    return st.data or nil
end

function XR.save(ui)
    local data = XR.names(ui)
    local dir = XR.dir(ui)
    if not data or not dir then return false end
    state(ui).lookup = nil
    return writeFile(dir .. "/aleph_xray.lua", data)
end

-- Where the names are mentioned: { n, s, e, by = { [index] = { hit, ... } } }.
function XR.hits(ui)
    local st = state(ui)
    if st.hits == nil then
        local dir = XR.dir(ui)
        local hits = dir and readFile(dir .. "/aleph_xray_hits.lua") or nil
        if hits and type(hits.n) == "table" and type(hits.s) == "table" and type(hits.e) == "table" then
            local by = {}
            for i, index in ipairs(hits.n) do
                local list = by[index]
                if not list then list = {}; by[index] = list end
                list[#list + 1] = i
            end
            hits.by = by
            st.hits = hits
        else
            st.hits = false
        end
    end
    return st.hits or nil
end

-- The words around mention number `hit`: before, the name as written, after.
function XR.snippet(ui, hit)
    local st = state(ui)
    if st.text == nil then
        local dir = XR.dir(ui)
        local data = dir and readFile(dir .. "/aleph_xray_text.lua") or nil
        st.text = data and type(data.t) == "table" and data.t or false
    end
    local line = st.text and st.text[hit]
    if type(line) ~= "string" then return nil end
    local before, name, after = line:match("^(.-)\1(.-)\2(.*)$")
    if not before then return line, "", "" end
    return before, name, after
end

-- The entry for a word or a selection (a name, another way to say it, or
-- one of the words selected), and its index.
function XR.find(ui, text)
    local data = XR.names(ui)
    if not data then return nil end
    local Names = require("aleph_xr_names")
    local st = state(ui)
    if not st.lookup then
        local lookup = {}
        for index, entry in ipairs(data.names) do
            lookup[Names.key(entry.name)] = lookup[Names.key(entry.name)] or index
            for _i, alias in ipairs(entry.aliases or {}) do
                local key = Names.key(alias)
                lookup[key] = lookup[key] or index
            end
        end
        st.lookup = lookup
    end
    local key = Names.key(text)
    local index = st.lookup[key]
    if not index then
        -- A selection that holds a name: its longest part that is one.
        local words = {}
        for w in key:gmatch("%S+") do
            w = w:gsub("^%p+", ""):gsub("%p+$", "")
            if w ~= "" then words[#words + 1] = w end
        end
        for size = math.min(#words, 4), 1, -1 do
            for from = 1, #words - size + 1 do
                index = st.lookup[table.concat(words, " ", from, from + size - 1)]
                if index then break end
            end
            if index then break end
        end
    end
    if not index then return nil end
    return data.names[index], index
end

-- ------------------------------------------------------ up to this page
-- The first mention at or after position xp (1 past the last when none).
local function firstAtOrAfter(doc, starts, xp)
    local lo, hi = 1, #starts + 1
    while lo < hi do
        local mid = math.floor((lo + hi) / 2)
        local ok, order = pcall(doc.compareXPointers, doc, xp, starts[mid])
        -- 1: the mention is after xp; 0: at it.
        if ok and order >= 0 then hi = mid else lo = mid + 1 end
    end
    return lo
end

-- The start of the page after the one shown (`ahead` pages on), or nil
-- when that is past the end.
local function pageAfter(ui, ahead)
    local doc = ui.document
    local ok, xp = pcall(function()
        local page = ui:getCurrentPage() + (ahead or 1)
        if page > doc:getPageCount() then return nil end
        return doc:getPageXPointer(page)
    end)
    return ok and xp or nil
end

-- How many mentions (of all names) lie on the pages read so far, this one
-- included. Kept for the page being shown.
function XR.readSoFar(ui)
    local hits = XR.hits(ui)
    if not hits then return 0 end
    local st = state(ui)
    local ok, here = pcall(function() return ui.document:getXPointer() end)
    if not ok then return #hits.s end
    if st.sofar_at ~= here then
        local next_page = pageAfter(ui, 1)
        st.sofar = next_page and firstAtOrAfter(ui.document, hits.s, next_page) - 1 or #hits.s
        st.sofar_at = here
    end
    return st.sofar
end

-- How many of name `index`'s mentions have been read, and how many there are.
function XR.count(ui, index)
    local hits = XR.hits(ui)
    local list = hits and hits.by[index]
    if not list then return 0, 0 end
    if XR.spoilers() then return #list, #list end
    local limit = XR.readSoFar(ui)
    local lo, hi = 1, #list + 1
    while lo < hi do
        local mid = math.floor((lo + hi) / 2)
        if list[mid] > limit then hi = mid else lo = mid + 1 end
    end
    return lo - 1, #list
end

-- Mention number `nth` of name `index`: its position, page and chapter.
function XR.mention(ui, index, nth)
    local hits = XR.hits(ui)
    local hit = hits and hits.by[index] and hits.by[index][nth]
    if not hit then return nil end
    local doc = ui.document
    local m = { hit = hit, s = hits.s[hit], e = hits.e[hit] }
    try(function()
        m.page = doc:getPageFromXPointer(m.s)
        if ui.toc and m.page then m.chapter = ui.toc:getTocTitleByPage(m.page) end
    end)
    return m
end

function XR.goTo(ui, m)
    local Event = require("ui/event")
    try(function()
        if ui.link and ui.link.addCurrentLocationToStack then ui.link:addCurrentLocationToStack() end
        ui:handleEvent(Event:new("GotoXPointer", m.s, m.s))
    end)
end

-- ------------------------------------------------------------- underlines
-- The names on the page shown: { { x, y, w, h, n = index }, ... }, worked
-- out once per page (a few position look-ups for the page's own names).
function XR.pageBoxes(ui)
    local st = ui._aleph_xr
    if not st or not st.attached then return nil end
    local hits = st.hits
    if not hits then return nil end
    local doc = ui.document
    local Screen = require("device").screen
    local ok, here = pcall(function() return doc:getXPointer() end)
    if not ok or not here then return nil end
    -- The page as laid out now: another font or margin moves the names
    -- without moving the page's first position.
    local laid = ""
    if type(doc.getDocumentRenderingHash) == "function" then
        local got, hash = pcall(doc.getDocumentRenderingHash, doc)
        if got and hash then laid = tostring(hash) end
    end
    local key = here .. "|" .. Screen:getWidth() .. "x" .. Screen:getHeight() .. "|" .. tostring(ui.view and ui.view.view_mode) .. "|" .. laid
    if st.boxes_key == key then return st.boxes end
    local boxes = {}
    try(function()
        local data = XR.names(ui)
        local names = data and data.names or {}
        -- In scroll mode a page and the next may both be on screen.
        local scroll = ui.view and ui.view.view_mode == "scroll"
        local first = firstAtOrAfter(doc, hits.s, here)
        local after = pageAfter(ui, scroll and 2 or 1)
        local last = after and firstAtOrAfter(doc, hits.s, after) - 1 or #hits.s
        last = math.min(last, first + 120)
        local sh = Screen:getHeight()
        for i = first, last do
            local entry = names[hits.n[i]]
            if entry and not entry.hidden then
                local got, list = pcall(doc.getScreenBoxesFromPositions, doc, hits.s[i], hits.e[i], true)
                if got and type(list) == "table" then
                    for _j, b in ipairs(list) do
                        if b.w and b.w > 0 and b.y and b.y >= 0 and b.y < sh then
                            boxes[#boxes + 1] = { x = b.x, y = b.y, w = b.w, h = b.h, n = hits.n[i] }
                        end
                    end
                end
            end
        end
    end)
    st.boxes_key, st.boxes = key, boxes
    return boxes
end

function XR.paint(view, bb)
    local ui = view.ui
    local st = ui and ui._aleph_xr
    if not st or not st.attached or XR._subprocess then return end
    if not XR.underlined() or not XR.enabled() then return end
    local Screen = require("device").screen
    if bb ~= Screen.bb then return end
    local boxes = XR.pageBoxes(ui)
    if not boxes or #boxes == 0 then return end
    local Blitbuffer = require("ffi/blitbuffer")
    local thick = math.max(1, math.floor(Screen:scaleBySize(1) + 0.5))
    local color = Blitbuffer.COLOR_DARK_GRAY
    for _i, b in ipairs(boxes) do
        bb:paintRect(b.x, b.y + b.h - thick, b.w, thick, color)
    end
end

-- The name under a tap, when the names are underlined.
function XR.at(ui, pos)
    if not XR.underlined() or not pos then return nil end
    local st = ui._aleph_xr
    local boxes = st and st.boxes
    if not boxes then return nil end
    for _i, b in ipairs(boxes) do
        local slack = math.floor(b.h * 0.15)
        if pos.x >= b.x - slack and pos.x < b.x + b.w + slack and pos.y >= b.y - slack and pos.y < b.y + b.h + slack then
            return b.n
        end
    end
    return nil
end

-- Loads where the names are, for the underlines, and paints the page again.
function XR.loadForPage(ui)
    if not ui._aleph_xr or not ui._aleph_xr.attached or not ui.document then return end
    if not XR.names(ui) then return end
    if XR.hits(ui) then
        local st = state(ui)
        st.boxes_key = nil
        try(function()
            local UIManager = require("ui/uimanager")
            UIManager:setDirty(ui.dialog or ui, "ui")
        end)
    end
end

-- ------------------------------------------------------------- the reader
function XR.install()
    local Paint = require("aleph_reader_paint")
    if not Paint.has("x-ray") then
        Paint.add("x-ray", 40, function(view, bb) XR.paint(view, bb) end)
        -- The page browser's thumbnails are made by another process: no
        -- underlines are worked out there.
        try(function()
            require("ffi/util").addRunInSubProcessAfterForkFunc("aleph_xr", function() XR._subprocess = true end)
        end)
    end
end

function XR.open(ui, text)
    return require("aleph_xr_page").open(ui, text)
end

function XR.attach(ui)
    if not XR.enabled() or not ui or not ui.document or not XR.supported(ui) then return end
    local st = state(ui)
    if st.attached then return end
    st.attached = true
    -- When the book was last read, before this session saves anything: for
    -- the recap offered after a break. Only with a provider set.
    if type(Prefs.get().xray_ai_key) == "string" or Prefs.get().xray_ai_provider == "custom" then
        try(function() require("aleph_xr_story").noteOpened(ui) end)
    end
    local _ = require("aleph_gettext")
    if ui.highlight and ui.highlight.addToHighlightDialog then
        ui.highlight:addToHighlightDialog("14_aleph_xray", function(this)
            return {
                text = _("X-Ray"),
                callback = function()
                    local selected = this.selected_text and this.selected_text.text or ""
                    this:onClose()
                    require("ui/uimanager"):nextTick(function() try(XR.open, ui, selected) end)
                end,
            }
        end)
    end
    ui:registerPostInitCallback(function()
        if not ui._aleph_xr or not ui._aleph_xr.attached then return end
        -- A tap on an underlined name opens it; any other tap goes to the
        -- page as usual.
        local overrides = { "readerfooter_tap", "readerlink_tap", "readerhighlight_tap",
            "tap_forward", "tap_backward", "readermenu_tap", "readermenu_ext_tap" }
        for id, zone in pairs(ui._zones or {}) do
            if zone.def and zone.def.ges == "tap" then overrides[#overrides + 1] = id end
        end
        ui:registerTouchZones({
            { id = "aleph_xray_tap", ges = "tap",
                screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 }, overrides = overrides,
                handler = function(ges)
                    if not ui._aleph_xr or not ui._aleph_xr.attached then return false end
                    local index = XR.at(ui, ges and ges.pos)
                    if not index then return false end
                    try(function() require("aleph_xr_page").openEntry(ui, index) end)
                    return true
                end,
            },
        })
        -- A book picked up again after a while: the story so far is offered
        -- (aleph_xr_story.lua), a moment after it opens.
        if type(Prefs.get().xray_ai_key) == "string" or Prefs.get().xray_ai_provider == "custom" then
            require("ui/uimanager"):scheduleIn(3, function()
                if ui._aleph_xr and ui._aleph_xr.attached and ui.document then
                    try(function() require("aleph_xr_story").offer(ui) end)
                end
            end)
        end
        -- With the underlines on, where the names are is loaded a moment
        -- after the book, not while it opens.
        if XR.underlined() then
            require("ui/uimanager"):scheduleIn(2, function() try(XR.loadForPage, ui) end)
        end
    end)
end

function XR.detach(ui)
    if not ui then return end
    ui._aleph_xr = nil
end

return XR
