-- Aleph modification, 2026-11-11: importing Goodreads' library export.
--[[--
Goodreads exports a reader's books as a CSV file (My Books > Import and
export > Export library: goodreads_library_export.csv), which Excel opens;
the same file saved again from Excel as a workbook (.xlsx) is read too.

Settings > Library > Import from Goodreads looks for that file in the usual
places (the home folder, the library's folders, the Kindle's documents, the
Downloads folder) or lets one be chosen, shows what it would change, and on
OK:

  Books on the device (found by ISBN when known, else by title and author)
    status         Read -> Finished, Currently reading -> Reading, a shelf
                   named like "did not finish" -> On hold. Only for books
                   still unread here: a status set on the device stays.
    finished date  Goodreads' Date Read, when the book is marked Finished
                   here by the import, or is Finished here with no day.
                   A book Finished here on another day than Goodreads'
                   keeps this device's day unless "Choose finished dates"
                   (on the summary) picks Goodreads' for it.
    rating         Goodreads' stars, when the book has no rating here.
  Books read on Goodreads and not on the device
    go on Aleph's record of finished books (aleph_finished_log.lua) with the
    day they were read, so they count in their year's goal, like books read
    and deleted. Read books without a Date Read have no year to count in
    and are left out. Importing again updates them rather than adding twice.

Nothing is sent anywhere; Goodreads' page counts and progress are not used
(the export has no progress, only shelves).
]]

local try = require("aleph_try").call
local Import = {}

-- ------------------------------------------------------------ the file
-- CSV as Goodreads (and Excel) write it: quoted fields may hold commas,
-- quotes ("") and line breaks. `sep` is "," or ";" (Excel in many
-- languages saves with semicolons).
function Import.parseCsv(text, sep)
    sep = sep or ","
    local rows, row, field = {}, {}, {}
    local i, n = 1, #text
    local quoted = false
    while i <= n do
        local c = text:sub(i, i)
        if quoted then
            if c == '"' then
                if text:sub(i + 1, i + 1) == '"' then field[#field + 1] = '"'; i = i + 1
                else quoted = false end
            else field[#field + 1] = c end
        elseif c == '"' then quoted = true
        elseif c == sep then row[#row + 1] = table.concat(field); field = {}
        elseif c == "\n" or c == "\r" then
            row[#row + 1] = table.concat(field); field = {}
            if #row > 1 or row[1] ~= "" then rows[#rows + 1] = row end
            row = {}
            if c == "\r" and text:sub(i + 1, i + 1) == "\n" then i = i + 1 end
        else field[#field + 1] = c end
        i = i + 1
    end
    if #field > 0 or #row > 0 then
        row[#row + 1] = table.concat(field)
        if #row > 1 or row[1] ~= "" then rows[#rows + 1] = row end
    end
    return rows
end

-- An .xlsx workbook's first sheet as rows of text, or nil, why.
local function xmlText(s)
    return (s:gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&quot;", '"'):gsub("&apos;", "'")
        :gsub("&#(%d+);", function(d) d = tonumber(d); return d and d < 128 and string.char(d) or "" end):gsub("&amp;", "&"))
end
local function colIndex(ref)
    local letters = ref:match("^(%a+)") or "A"
    local n = 0
    for k = 1, #letters do n = n * 26 + (letters:upper():byte(k) - 64) end
    return n
end

function Import.parseSheet(shared_xml, sheet_xml)
    local shared = {}
    for si in (shared_xml or ""):gmatch("<si>(.-)</si>") do
        local parts = {}
        for t in si:gmatch("<t[^>]*>(.-)</t>") do parts[#parts + 1] = xmlText(t) end
        shared[#shared + 1] = table.concat(parts)
    end
    local rows = {}
    for row_xml in (sheet_xml or ""):gmatch("<row[^>]*>(.-)</row>") do
        local row = {}
        for attrs, body in row_xml:gmatch("<c([^>]*)>(.-)</c>") do
            local ref = attrs:match('r="([^"]+)"')
            local kind = attrs:match('t="([^"]+)"')
            local value
            if kind == "s" then value = shared[(tonumber(body:match("<v>(.-)</v>")) or -1) + 1]
            elseif kind == "inlineStr" then
                local parts = {}
                for t in body:gmatch("<t[^>]*>(.-)</t>") do parts[#parts + 1] = xmlText(t) end
                value = table.concat(parts)
            else value = xmlText(body:match("<v>(.-)</v>") or "") end
            local col = ref and colIndex(ref) or (#row + 1)
            for k = #row + 1, col - 1 do row[k] = "" end
            row[col] = value or ""
        end
        if #row > 0 then rows[#rows + 1] = row end
    end
    return rows
end

local function readXlsx(path)
    local ok, rows = pcall(function()
        local Archiver = require("ffi/archiver")
        local arc = Archiver.Reader:new()
        if not arc:open(path) then return nil end
        local shared = arc:extractToMemory("xl/sharedStrings.xml")
        local sheet = arc:extractToMemory("xl/worksheets/sheet1.xml")
        arc:close()
        if not sheet then return nil end
        return Import.parseSheet(shared, sheet)
    end)
    return ok and rows or nil
end

-- The rows of the file at `path` (CSV or .xlsx), or nil, why.
function Import.readRows(path)
    local f = io.open(path, "rb")
    if not f then return nil, "open" end
    local data = f:read("*a")
    f:close()
    if not data or data == "" then return nil, "empty" end
    if data:sub(1, 2) == "PK" then
        local rows = readXlsx(path)
        if not rows then return nil, "xlsx" end
        return rows
    end
    if data:sub(1, 2) == "\255\254" or data:sub(1, 2) == "\254\255" then return nil, "utf16" end
    data = data:gsub("^\239\187\191", "")
    local head = data:match("^[^\r\n]*") or ""
    local _c, commas = head:gsub(",", "")
    local _s, semis = head:gsub(";", "")
    return Import.parseCsv(data, semis > commas and ";" or ",")
end

-- ------------------------------------------------------------ the books
local function clean(v)
    v = tostring(v or ""):gsub("^%s+", ""):gsub("%s+$", "")
    -- Goodreads writes ISBNs as ="0439023483" so spreadsheets keep them as text.
    v = v:gsub('^="(.*)"$', "%1"):gsub("^=", "")
    return v
end

-- Goodreads' dates are 2023/05/12; Excel may turn them into 2023-05-12,
-- 12/05/2023 or a day number (days since 1899-12-30).
function Import.date(v)
    v = clean(v)
    if v == "" then return nil end
    local y, m, d = v:match("^(%d%d%d%d)[/%-.](%d%d?)[/%-.](%d%d?)")
    if not y then
        local a, b, c = v:match("^(%d%d?)[/%-.](%d%d?)[/%-.](%d%d%d%d)")
        if a then
            -- Day first unless that cannot be (13/05 is a day; 05/13 a month).
            if tonumber(b) > 12 then y, m, d = c, a, b else y, m, d = c, b, a end
        end
    end
    if not y and v:match("^%d+%.?%d*$") then
        local serial = math.floor(tonumber(v))
        if serial > 10000 and serial < 80000 then
            local t = os.time{ year = 1899, month = 12, day = 30, hour = 12 } + serial * 86400
            return os.date("%Y-%m-%d", t)
        end
    end
    if not y then return nil end
    y, m, d = tonumber(y), tonumber(m), tonumber(d)
    if y < 1000 or m < 1 or m > 12 or d < 1 or d > 31 then return nil end
    return string.format("%04d-%02d-%02d", y, m, d)
end

-- The export's rows as books: { id, title, authors, isbns, rating, read,
-- shelf, pages }. Nil, why when the file is not Goodreads' export.
function Import.records(rows)
    local header = rows and rows[1]
    if not header then return nil, "empty" end
    local col = {}
    for i, name in ipairs(header) do col[clean(name):lower()] = i end
    if not (col["title"] and col["exclusive shelf"]) then return nil, "not-goodreads" end
    local function get(row, name) local i = col[name]; return i and clean(row[i]) or "" end
    local out = {}
    for r = 2, #rows do
        local row = rows[r]
        local title = get(row, "title")
        if title ~= "" then
            local authors = {}
            local main = get(row, "author")
            if main ~= "" then authors[1] = main end
            for a in get(row, "additional authors"):gmatch("[^,]+") do
                a = clean(a)
                if a ~= "" then authors[#authors + 1] = a end
            end
            local isbns = {}
            for _i, k in ipairs({ "isbn", "isbn13" }) do
                local v = get(row, k):gsub("[^%dXx]", "")
                if #v == 10 or #v == 13 then isbns[#isbns + 1] = v:upper() end
            end
            local rating = tonumber(get(row, "my rating"))
            out[#out + 1] = {
                id = get(row, "book id"), title = title, authors = authors, isbns = isbns,
                author_lf = get(row, "author l-f"),
                rating = (rating and rating >= 1 and rating <= 5) and math.floor(rating) or nil,
                read = Import.date(get(row, "date read")),
                shelf = get(row, "exclusive shelf"):lower(),
                pages = tonumber(get(row, "number of pages")),
            }
        end
    end
    return out
end

-- ------------------------------------------------------------ matching
local FOLD = {
    ["à"]="a",["á"]="a",["â"]="a",["ã"]="a",["ä"]="a",["å"]="a",["æ"]="ae",["ç"]="c",
    ["è"]="e",["é"]="e",["ê"]="e",["ë"]="e",["ì"]="i",["í"]="i",["î"]="i",["ï"]="i",
    ["ñ"]="n",["ò"]="o",["ó"]="o",["ô"]="o",["õ"]="o",["ö"]="o",["ø"]="o",["œ"]="oe",
    ["ù"]="u",["ú"]="u",["û"]="u",["ü"]="u",["ý"]="y",["ÿ"]="y",["ß"]="ss",
    ["À"]="a",["Á"]="a",["Â"]="a",["Ã"]="a",["Ä"]="a",["Å"]="a",["Ç"]="c",["È"]="e",["É"]="e",
    ["Ê"]="e",["Ë"]="e",["Ì"]="i",["Í"]="i",["Î"]="i",["Ï"]="i",["Ñ"]="n",["Ò"]="o",["Ó"]="o",
    ["Ô"]="o",["Õ"]="o",["Ö"]="o",["Ø"]="o",["Ù"]="u",["Ú"]="u",["Û"]="u",["Ü"]="u",
    ["’"]="'",["‘"]="'",["“"]='"',["”"]='"',["–"]="-",["—"]="-",
}
local ARTICLES = { the = true, a = true, an = true, el = true, la = true, los = true, las = true,
    le = true, les = true, il = true, lo = true, der = true, die = true, das = true, o = true, os = true, as = true }

local function fold(s)
    s = tostring(s or ""):gsub("[\195\197\226][\128-\191]+", function(ch) return FOLD[ch] or ch end)
    return s:lower()
end

-- A title as compared: lower case, no accents, punctuation or leading
-- article. short: without a subtitle ("Dune: Deluxe Edition") or a series
-- note ("Catching Fire (The Hunger Games, #2)").
function Import.titleKeys(title)
    local t = fold(title)
    local function tidy(s)
        s = s:gsub("&", " and "):gsub("[^%w%s\128-\255]", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
        local first, rest = s:match("^(%S+)%s+(.+)$")
        if first and ARTICLES[first] then s = rest end
        return s
    end
    local full = tidy(t)
    local short = tidy((t:gsub("%b()", " "):gsub("%b[]", " "):match("^[^:;]*") or t))
    return full, short
end

-- An author's surname as compared ("Collins, Suzanne" and "Suzanne Collins").
function Import.surname(name)
    local n = fold(name)
    if n:find(",") then n = n:match("^([^,]*)") end
    n = n:gsub("[^%w%s%-\128-\255]", " "):gsub("%s+", " "):gsub("%s+$", "")
    return n:match("(%S+)$")
end

local function surnames(list)
    local out = {}
    for _i, a in ipairs(list or {}) do
        local s = Import.surname(a)
        if s then out[s] = true end
    end
    return out
end

-- An index of `books` (library entries) to find a record's book in.
function Import.index(books)
    local idx = { by_isbn = {}, by_title = {} }
    for _i, b in ipairs(books or {}) do
        local isbn = b.opf and b.opf.isbn
        if isbn then idx.by_isbn[isbn] = b end
        local full, short = Import.titleKeys(b.title)
        for _j, key in ipairs({ full, short }) do
            if key ~= "" then
                idx.by_title[key] = idx.by_title[key] or {}
                local list = idx.by_title[key]
                if list[#list] ~= b then list[#list + 1] = b end
            end
        end
    end
    return idx
end

-- The library book a record is, or nil.
function Import.find(idx, rec)
    for _i, isbn in ipairs(rec.isbns or {}) do
        if idx.by_isbn[isbn] then return idx.by_isbn[isbn] end
    end
    local full, short = Import.titleKeys(rec.title)
    local wanted = surnames(rec.authors)
    if rec.author_lf and rec.author_lf ~= "" then
        local s = Import.surname(rec.author_lf); if s then wanted[s] = true end
    end
    local alone
    for _i, key in ipairs({ full, short }) do
        local list = idx.by_title[key]
        for _j, b in ipairs(list or {}) do
            for s in pairs(surnames(b.authors)) do
                if wanted[s] then return b end
            end
        end
        -- The same full title and no author to tell: the only one.
        if key == full and list and #list == 1 and #(list[1].authors or {}) == 0 then alone = list[1] end
    end
    return alone
end

-- Whether two books (record entries or library books) are the same by
-- title and author: used to keep a book from counting twice.
function Import.same(a, b)
    local fa, sa = Import.titleKeys(a.title)
    local fb, sb = Import.titleKeys(b.title)
    if not (fa == fb or sa == sb) then return false end
    local wa, wb = surnames(a.authors), surnames(b.authors)
    if next(wa) == nil or next(wb) == nil then return fa == fb end
    for s in pairs(wa) do if wb[s] then return true end end
    return false
end

-- ------------------------------------------------------------ the plan
local function statusOf(shelf)
    if shelf == "read" then return "read" end
    if shelf == "currently-reading" then return "reading" end
    if shelf:find("dnf", 1, true) or shelf:find("did%-not%-finish") or shelf:find("abandon")
        or shelf:find("not%-finish") or shelf:find("gave%-up") then return "on_hold" end
    return nil
end
Import.statusOf = statusOf

-- What the import would do. records: Import.records; books: the library's;
-- log: the record of finished books (key -> entry).
-- Returns { device = { { book, status, date, rating } }, record = { key -> entry },
--           counts = { rows, matched, status, rating, record, undated, kept } }
function Import.plan(records, books, log)
    local idx = Import.index(books)
    local plan = { device = {}, record = {}, dates = {},
        counts = { rows = #records, matched = 0, status = 0, rating = 0, record = 0, undated = 0, kept = 0, dated = 0, differ = 0 } }
    local c = plan.counts
    local others = {}
    for key, e in pairs(log or {}) do
        if type(e) == "table" and not tostring(key):match("^goodreads:") then others[#others + 1] = e end
    end
    local seen = {}
    for _i, rec in ipairs(records) do
        local book = Import.find(idx, rec)
        local status = statusOf(rec.shelf)
        if book and not seen[book] then
            seen[book] = true
            c.matched = c.matched + 1
            local change = { book = book }
            if status and book.readStatus == "unread" then
                change.status = status
                if status == "read" then change.date = rec.read; if rec.read then c.dated = c.dated + 1 end end
                c.status = c.status + 1
            elseif status == "read" and book.readStatus == "read" and rec.read then
                -- Finished on both: a day missing here is filled in; a
                -- different day is a choice (plan.dates, this device's by
                -- default).
                local here = type(book.finishedOn) == "string" and book.finishedOn:sub(1, 10) or nil
                if not here or here == "" then
                    change.date_only = rec.read
                    c.dated = c.dated + 1
                elseif here ~= rec.read then
                    plan.dates[#plan.dates + 1] = { book = book, title = book.title or rec.title, here = here, there = rec.read, use = "here" }
                    c.differ = c.differ + 1
                end
            elseif status and book.readStatus ~= status then
                c.kept = c.kept + 1
            end
            if rec.rating and not book.rating then change.rating = rec.rating; c.rating = c.rating + 1 end
            if change.status or change.rating or change.date_only then plan.device[#plan.device + 1] = change end
        elseif not book and status == "read" then
            if not rec.read then
                c.undated = c.undated + 1
            else
                local entry = { finished = rec.read, title = rec.title, authors = rec.authors,
                    rating = rec.rating, pages = rec.pages, source = "goodreads" }
                local twice = false
                for _j, e in ipairs(others) do
                    if Import.same(e, entry) then twice = true; break end
                end
                if not twice then
                    local key = "goodreads:" .. (rec.id ~= "" and rec.id or (Import.titleKeys(rec.title)))
                    plan.record[key] = entry
                    c.record = c.record + 1
                end
            end
        end
    end
    return plan
end

-- The finished days taken from Goodreads (the choices set to "goodreads").
function Import.chosenDates(plan)
    local n = 0
    for _i, d in ipairs(plan.dates or {}) do if d.use == "goodreads" then n = n + 1 end end
    return n
end

-- Carries out a plan on `lib` (aleph_local). Returns the counts.
function Import.apply(plan, lib)
    local STATUS = { reading = "reading", read = "complete", on_hold = "abandoned" }
    local changes = {}
    for _i, ch in ipairs(plan.device) do changes[#changes + 1] = ch end
    for _i, d in ipairs(plan.dates or {}) do
        if d.use == "goodreads" then changes[#changes + 1] = { book = d.book, date_only = d.there } end
    end
    for _i, ch in ipairs(changes) do
        local b = ch.book
        try(function()
            local summary = lib:saveSummary(b, function(summary)
                if ch.status then
                    summary.status = STATUS[ch.status]
                    if ch.status == "read" then summary.modified = ch.date end
                end
                if ch.rating then summary.rating, summary.aleph_rating = ch.rating, nil end
                if ch.date_only then summary.modified = ch.date_only end
            end)
            if ch.date_only and not ch.status then b.finishedOn = summary.modified end
            if ch.status then
                b.readStatus = ch.status
                b.finishedOn = ch.status == "read" and summary.modified or nil
            end
            if ch.rating then b.rating = ch.rating end
        end)
    end
    local Log = require("aleph_finished_log")
    try(Log.sync, lib.books)
    try(Log.addImported, plan.record)
    try(function()
        lib._group_cache = nil
        if lib.saveIndex then lib:saveIndex() else
            lib.cache:saveSetting("books", lib.books)
            lib.cache:flush()
        end
    end)
    return plan.counts
end

-- ------------------------------------------------------------ the file's place
local function isExport(name)
    local n = name:lower()
    return (n:find("goodreads", 1, true) ~= nil) and (n:match("%.csv$") or n:match("%.xlsx$")) ~= nil
end
Import.isExport = isExport

-- The export files in the usual places, newest first: { path, modified }.
function Import.findFiles(settings)
    local lfs = require("libs/libkoreader-lfs")
    local dirs, seen = {}, {}
    local function add(d)
        if type(d) == "string" and d ~= "" and not seen[d] then seen[d] = true; dirs[#dirs + 1] = d end
    end
    add(G_reader_settings:readSetting("home_dir"))
    for _i, r in ipairs(type(settings) == "table" and settings.library_roots or {}) do add(r) end
    try(function()
        local DataStorage = require("datastorage")
        add(DataStorage:getDataDir()); add(DataStorage:getFullDataDir())
    end)
    for _i, d in ipairs({ "/mnt/us", "/mnt/us/documents", "/mnt/us/documents/Downloads", "/mnt/onboard",
            "/mnt/onboard/Downloads", "/sdcard/Download", "/storage/emulated/0/Download", "/sdcard/Books" }) do
        add(d)
    end
    local out = {}
    for _i, d in ipairs(dirs) do
        try(function()
            if lfs.attributes(d, "mode") ~= "directory" then return end
            for name in lfs.dir(d) do
                if name:sub(1, 1) ~= "." and isExport(name) then
                    local path = d:gsub("/$", "") .. "/" .. name
                    local attr = lfs.attributes(path)
                    if attr and attr.mode == "file" then out[#out + 1] = { path = path, modified = attr.modification } end
                end
            end
        end)
    end
    table.sort(out, function(a, b) return a.modified > b.modified end)
    return out
end

-- ------------------------------------------------------------ the screens
local function why(err)
    local _ = require("aleph_gettext")
    if err == "not-goodreads" then return _("This file is not Goodreads' library export: its first row should have columns such as Title, Author and Exclusive Shelf.") end
    if err == "xlsx" then return _("This Excel workbook could not be read. Use the CSV file Goodreads exported, or save the workbook as CSV.") end
    if err == "utf16" then return _("This file was saved as Unicode text. Use the CSV file Goodreads exported, or save it as CSV UTF-8.") end
    if err == "empty" then return _("This file is empty.") end
    return _("This file could not be read.")
end

local function confirm(o)
    local ok = pcall(function() require("aleph_confirm").show(o) end)
    if not ok then
        local UIManager = require("ui/uimanager")
        UIManager:show(require("ui/widget/confirmbox"):new{ text = (o.title or "") .. "\n\n" .. (o.text or ""),
            ok_text = o.ok_label, ok_callback = o.on_ok, cancel_callback = o.on_cancel })
    end
end

local function chooseFile(browser, start)
    local UIManager = require("ui/uimanager")
    local _ = require("aleph_gettext")
    local dir = (start and start:match("^(.*)/[^/]*$")) or (G_reader_settings and G_reader_settings:readSetting("home_dir")) or "/"
    UIManager:show(require("ui/widget/pathchooser"):new{
        select_directory = false, select_file = true, path = dir,
        title = _("Choose Goodreads' export"),
        file_filter = function(name) return name:lower():match("%.csv$") ~= nil or name:lower():match("%.xlsx$") ~= nil end,
        onConfirm = function(path) Import.review(browser, path) end,
    })
end
Import.chooseFile = chooseFile

-- "12 Mar 2024" for 2024-03-12.
function Import.day(iso)
    local Dates = require("aleph_dates")
    local t = Dates.fromISO(iso)
    if not t then return tostring(iso or "") end
    return Dates.dayMonthYearShort(t)
end

-- The books finished on another day here than on Goodreads: for each, keep
-- this device's day or take Goodreads'. on_done() when closed.
function Import.chooseDates(plan, on_done)
    local _ = require("aleph_gettext")
    local T = require("ffi/util").template
    local Device = require("device")
    local UIManager = require("ui/uimanager")
    local BoardMetrics = require("aleph_board_metrics")
    local BoardUI = require("aleph_board_ui")
    local MenuPage = require("aleph_menu_page")
    local MenuUI = require("aleph_menu_ui")
    local INK, px = BoardMetrics.INK, BoardMetrics.px
    local text, vstack, hstack, space, flex = BoardUI.text, BoardUI.vstack, BoardUI.hstack, BoardUI.space, BoardUI.flex
    local dates = plan.dates or {}
    local function turn(page, delta)
        local to = math.max(1, math.min(page.count or 1, (page.index or 1) + delta))
        if to == page.index then return end
        page.index = to
        page:refresh(Device:hasEinkScreen() and "partial" or "ui")
    end
    local page = MenuPage:new{
        name = "aleph_goodreads_dates",
        index = 1,
        build = function(page, sw, sh)
            local mx = MenuUI.mx()
            local w = sw - 2 * mx
            local iw = MenuUI.rowsIn(w)
            local header = MenuUI.pageHeader(w, _("Finished dates"),
                { sub = T(_("%1 books finished on another day here than on Goodreads"), #dates) })
            local gap = px(10)
            local half = math.floor((w - gap) / 2)
            local bulk = hstack({ w = w, gap = gap }, {
                MenuUI.pill(_("All from this device"), { kind = "outline", w = half, h = 40, s = 14, action = { kind = "all", use = "here" } }),
                MenuUI.pill(_("All from Goodreads"), { kind = "outline", w = w - gap - half, h = 40, s = 14, action = { kind = "all", use = "goodreads" } }),
            })
            local ihalf = math.floor((iw - gap) / 2)
            local rows = {}
            for i, d in ipairs(dates) do
                local function choice(label, use, cw)
                    local on = d.use == use
                    return MenuUI.pill(label, { kind = on and "dark" or "outline", icon = on and "check" or nil, icon_size = 16,
                        w = cw, h = 40, s = 13, pad_x = 10, action = { kind = "use", at = i, use = use } })
                end
                local row = vstack({ w = iw, pad = { px(10), 0, px(10), 0 } }, {
                    text(d.title or "?", { s = 15, b = true, w = iw, data = true }),
                    space(nil, px(8)),
                    hstack({ w = iw, gap = gap }, {
                        choice(T(_("Here: %1"), Import.day(d.here)), "here", ihalf),
                        choice(T(_("Goodreads: %1"), Import.day(d.there)), "goodreads", iw - gap - ihalf),
                    }),
                })
                row._no_icon = true
                rows[#rows + 1] = row
            end
            local done = MenuUI.pill(_("Done"), { w = w, h = 48, s = 16, action = { kind = "close" } })
            local used = header:getSize().h + px(8) + bulk:getSize().h + px(12) + px(40) + px(10) + done:getSize().h
            local avail = sh - px(6) - px(8) - used - px(8)
            local row_h = (rows[1] and rows[1]:getSize().h or px(80)) + MenuUI.hair()
            local per = math.max(1, math.floor((avail - 2 * MenuUI.line()) / row_h))
            page.count = math.max(1, math.ceil(#rows / per))
            page.index = math.max(1, math.min(page.index or 1, page.count))
            local shown = {}
            for i = (page.index - 1) * per + 1, math.min(#rows, page.index * per) do shown[#shown + 1] = rows[i] end
            local pager = page.count > 1 and require("aleph_text_pages").pager(w, page.index, page.count) or space(nil, px(40))
            return vstack({ w = sw, h = sh, pad = { px(6), mx, px(8), mx }, top = true }, {
                header, space(nil, px(8)), bulk, space(nil, px(12)),
                vstack({ w = w, h = avail }, { MenuUI.group(w, shown, { inset = 0 }), flex(0) }),
                space(nil, px(8)), pager, space(nil, px(10)), done,
            })
        end,
        on_action = function(page, action)
            local k = action.kind
            if k == "use" and dates[action.at] then
                dates[action.at].use = action.use
                page:refresh()
            elseif k == "all" then
                for _i, d in ipairs(dates) do d.use = action.use end
                page:refresh()
            elseif k == "page" then
                turn(page, action.delta or 0)
            end
            return true
        end,
        on_swipe = function(page, ges)
            if ges.direction == "west" then turn(page, 1) return true end
            if ges.direction == "east" then turn(page, -1) return true end
            return false
        end,
        on_page_key = function(page, delta) turn(page, delta) end,
        on_close = function() if on_done then on_done() end end,
    }
    UIManager:show(page, "ui")
    return page
end

-- Reads `path`, shows what would change, imports on OK. `plan` (optional):
-- one already made, back from choosing finished dates.
function Import.review(browser, path, plan)
    local _ = require("aleph_gettext")
    local T = require("ffi/util").template
    local lib = browser.local_library
    if not plan then
        local rows, err = Import.readRows(path)
        local records
        if rows then records, err = Import.records(rows) end
        if not records then
            return confirm{ title = _("Import from Goodreads"), text = why(err), ok_label = _("Choose file…"),
                cancel_label = _("Close"), on_ok = function() chooseFile(browser, path) end }
        end
        local Log = require("aleph_finished_log")
        plan = Import.plan(records, lib.books or {}, Log.all())
    end
    local c = plan.counts
    local taken = Import.chosenDates(plan)
    local lines = {
        T(_("%1 books in %2."), c.rows, path:match("([^/]+)$")),
        "",
        T(_("On this device: %1 found."), c.matched),
        T(_("  · %1 get a status (Finished, Reading or On hold)"), c.status),
        T(_("  · %1 get a rating"), c.rating),
    }
    if c.dated > 0 then lines[#lines + 1] = T(_("  · %1 get Goodreads' finished date"), c.dated) end
    if c.kept > 0 then lines[#lines + 1] = T(_("  · %1 keep the status set here, which differs"), c.kept) end
    if c.differ > 0 then
        lines[#lines + 1] = T(_("  · %1 were finished on another day here than on Goodreads: %2 keep this device's day, %3 take Goodreads'"),
            c.differ, c.differ - taken, taken)
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = T(_("Read, not on this device: %1 go on the record of finished books, in the year they were read."), c.record)
    if c.undated > 0 then lines[#lines + 1] = T(_("%1 read books have no Date Read on Goodreads and are left out."), c.undated) end
    lines[#lines + 1] = ""
    if taken > 0 then
        lines[#lines + 1] = _("Only what is empty here is filled in, and the finished days you chose to take from Goodreads.")
    else
        lines[#lines + 1] = _("Only what is empty here is filled in; nothing on this device is overwritten.")
    end
    local nothing = #plan.device == 0 and next(plan.record) == nil and taken == 0
    confirm{
        title = _("Import from Goodreads"),
        text = table.concat(lines, "\n"), lines = 26,
        extra_label = c.differ > 0 and T(_("Choose finished dates (%1)"), c.differ) or nil,
        on_extra = c.differ > 0 and function()
            Import.chooseDates(plan, function() Import.review(browser, path, plan) end)
        end or nil,
        ok_label = nothing and _("Close") or _("Import"),
        cancel_label = _("Other file…"),
        on_cancel = function() chooseFile(browser, path) end,
        on_ok = function()
            if nothing then return end
            Import.apply(plan, lib)
            try(function()
                require("aleph_toast").show(T(_("Goodreads: %1 books updated, %2 added to the record."), #plan.device + taken, c.record), { icon = "check" })
            end)
            if not browser.closed then browser:refreshData() end
        end,
    }
end

-- From Settings: the newest export found, or how to get one.
function Import.start(browser)
    local _ = require("aleph_gettext")
    local files = Import.findFiles(browser.settings)
    if files[1] then return Import.review(browser, files[1].path) end
    confirm{
        title = _("Import from Goodreads"),
        text = _("On goodreads.com, open My Books, then Import and export, and press Export Library. Copy the file it gives you (goodreads_library_export.csv) to this device, for example next to your books, then come back here.\n\nAleph fills in the status, finished date and rating of the books on this device that have none, and adds the books you read elsewhere to the record of finished books."),
        ok_label = _("Choose file…"), cancel_label = _("Close"),
        on_ok = function() chooseFile(browser) end,
    }
end

return Import
