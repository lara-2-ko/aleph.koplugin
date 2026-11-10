-- Aleph modification, 2026-11-09: the reader's bottom menu as a
-- Aleph sheet, after BookOrbit's "This book" sheet
-- (bookorbit_book_sheet.lua): the book at the top, where you are in it, and
-- what you reach for while reading.
--[[--
Opened where KOReader opens its bottom menu (a tap at the bottom of the
page, or a swipe up while the page browser's swipe is off). The page stays in
view above it, dimmed.

  head        cover, title, author, a chip with the progress, close
  card        This book: 18%, page 214 of 542 · Chapter: its title, pages left
  tabs        This book | Also reading
  This book   Style & format (KOReader's own bottom menu: fonts, margins,
              spacing, contrast…), Contents, Bookmarks, Pages (the page
              browser); Bookmark this page; Book details (its Aleph
              page, with the highlight and bookmark counts); Aleph
              Home; with BT Manager - HID Passthrough or Syncery installed, a
              row of small buttons under the tiles: a Bluetooth switch for
              the HID daemon, Sync now, and Syncery's progress browser
  Also        the other books you are reading, newest first, with their
  reading     covers and progress: tap one to switch to it; All books opens
              the library
  Each tab sets the sheet's height, so switching tabs resizes it.

Settings > Opening Aleph > Dialogs > "Reader menu at the bottom"
turns it off, and KOReader's own menu comes back. If the sheet cannot be
built, KOReader's opens.
]]

local Event = require("ui/event")
local Geom = require("ui/geometry")
local UIManager = require("ui/uimanager")
local T = require("ffi/util").template
local _ = require("gettext")

local BoardMetrics = require("aleph_board_metrics")
local BoardUI = require("aleph_board_ui")
local MenuPage = require("aleph_menu_page")
local MenuUI = require("aleph_menu_ui")

local INK = BoardMetrics.INK
local px = BoardMetrics.px
local text, vstack, hstack, space, flex, icon = BoardUI.text, BoardUI.vstack, BoardUI.hstack, BoardUI.space, BoardUI.flex, BoardUI.icon
local floor = math.floor

local Sheet = {}

local MAX_OTHERS = 4

local function hOf(widget) return widget:getSize().h end
local function wOf(widget) return widget:getSize().w end

local function wanted()
    local stored = G_reader_settings:readSetting("aleph")
    return not (type(stored) == "table" and stored.reader_sheet == false)
end
Sheet.wanted = wanted

-- ------------------------------------------------------------------ data
local function pct(value)
    if not value then return nil end
    local n = value * 100
    if n > 0 and n < 0.5 then return "<1%" end
    if n < 100 and n >= 99.5 then return "99%" end
    return tostring(floor(n + 0.5)) .. "%"
end
Sheet.pct = pct

local function annotationCounts(ui)
    local highlights, bookmarks = 0, 0
    for _i, a in ipairs(ui.annotation and ui.annotation.annotations or {}) do
        if a.drawer or a.pos0 then highlights = highlights + 1 else bookmarks = bookmarks + 1 end
    end
    return highlights, bookmarks
end

local function bookmarked(ui)
    local on = false
    pcall(function() on = ui.bookmark:isCurrentPageBookmarked() end)
    return on == true
end

-- The library index: this book's cover, and the others in progress. It is
-- read again only when the index file changed (a big library's index takes a
-- while to read on an e-reader).
local index_cache
local function library(ui)
    local path = require("datastorage"):getSettingsDir() .. "/aleph_index.lua"
    local mtime = require("libs/libkoreader-lfs").attributes(path, "modification")
    if index_cache and index_cache.mtime == mtime then return index_cache.lib end
    local ok, lib = pcall(function()
        local settings = G_reader_settings:readSetting("aleph") or {}
        local full = require("aleph_local").new(settings, ui)
        -- Only what the sheet shows is kept for the reading session, not the
        -- whole index (every book's highlights and descriptions).
        local books = {}
        for i, b in ipairs(full.books or {}) do
            books[i] = { path = b.path, title = b.title, authors = b.authors, readStatus = b.readStatus,
                last_open = b.last_open, progressPercentage = b.progressPercentage, cover_path = b.cover_path,
                modified = b.modified, size = b.size }
        end
        return { books = books }
    end)
    if not ok then return nil end
    index_cache = { mtime = mtime, lib = lib }
    collectgarbage("step", 512)
    return lib
end

function Sheet.others(books, current_path, limit)
    local out = {}
    for _i, b in ipairs(books or {}) do
        if b.path ~= current_path and b.readStatus == "reading" then out[#out + 1] = b end
    end
    table.sort(out, function(a, b) return (a.last_open or 0) > (b.last_open or 0) end)
    while #out > (limit or MAX_OTHERS) do table.remove(out) end
    return out
end

-- Other plugins the sheet offers shortcuts to, when they are installed.
local function plugin(ui, name)
    local p = ui and rawget(ui, name)
    if type(p) ~= "table" then
        pcall(function() p = require("pluginloader"):getPluginInstance(name) end)
    end
    return type(p) == "table" and p or nil
end
Sheet.plugin = plugin

-- Whether the HID daemon is running: a question to it on this device
-- (answered at once when it is off), asked when the sheet opens.
local function hidRunning(hid)
    local ok, on = pcall(hid.isRunning, hid)
    return ok and on == true
end
Sheet.hidRunning = hidRunning

function Sheet.data(ui)
    local doc = ui.document
    local props = ui.doc_props or {}
    local page, pages
    pcall(function() page = ui:getCurrentPage() end)
    pcall(function() pages = doc:getPageCount() end)
    local percent
    pcall(function() percent = ui.doc_settings:readSetting("percent_finished") end)
    if page and pages and pages > 0 then percent = page / pages end
    local chapter, left
    pcall(function() chapter = ui.toc:getTocTitleByPage(page) end)
    pcall(function() left = ui.toc:getChapterPagesLeft(page) end)
    local highlights, bookmarks = annotationCounts(ui)
    local lib = library(ui)
    local file = doc and doc.file
    local this, others = nil, {}
    if lib then
        for _i, b in ipairs(lib.books or {}) do
            if b.path == file then this = b; break end
        end
        others = Sheet.others(lib.books, file)
    end
    local Local = require("aleph_local")
    for _i, b in ipairs(others) do b.cover_path = Local.cachedCover(b) end
    local Xray = require("aleph_xray")
    local xray = Xray.plugin(ui)
    local authors = props.authors
    if type(authors) == "table" then authors = table.concat(authors, ", ") end
    local hid = plugin(ui, "hidpassthrough")
    if hid and type(hid.isRunning) ~= "function" then hid = nil end
    local syncery = plugin(ui, "syncery")
    if syncery and type(syncery.syncNow) ~= "function" then syncery = nil end
    return {
        -- The library's title first: it has a comic's ComicInfo.xml title,
        -- which KOReader does not read.
        title = (props.title and props.title ~= "" and props.title) or (this and this.title)
            or props.display_title or (file and file:match("([^/]+)$")) or "",
        author = type(authors) == "string" and authors:gsub("\n", ", ") or "",
        page = page, pages = pages, percent = percent,
        chapter = type(chapter) == "string" and chapter:match("%S") and chapter or nil,
        chapter_left = tonumber(left),
        highlights = highlights, bookmarks = bookmarks,
        bookmarked = bookmarked(ui),
        cover_path = this and Local.cachedCover(this) or nil,
        others = others,
        file = file,
        xray = xray ~= nil,
        xray_summary = xray and Xray.summary(xray) or nil,
        hid = hid ~= nil, hid_on = hid and hidRunning(hid) or false,
        syncery = syncery ~= nil,
    }
end

-- ------------------------------------------------------------------ parts
local function coverOf(page, w, h)
    local d = page.data
    if d.cover_path then return BoardUI.cover({ title = d.title }, w, h, { path = d.cover_path, border = math.max(1, px(1)), border_col = INK.g6 }) end
    -- Not in the library index: the book's own cover, drawn once.
    if not page.cover_bb and not page.cover_tried then
        page.cover_tried = true
        pcall(function() page.cover_bb = page.ui.document:getCoverPageImage() end)
    end
    if page.cover_bb then
        return require("aleph_picture").view(page, page.cover_bb, w, h)
    end
    return BoardUI.cover({ title = d.title }, w, h, {})
end

-- The author; with X-Ray installed it opens X-Ray's author info, and says so
-- with a chevron.
local function authorLine(d, tw)
    if not d.xray then return text(d.author, { s = 13, col = INK.g4, w = tw, data = true }) end
    local chev = icon("chevron-right", px(14), { sw = 2.5, col = "g4" })
    local t = text(d.author, { s = 13, b = true, col = INK.g3, data = true })
    if wOf(t) > tw - px(20) then t:free(); t = text(d.author, { s = 13, b = true, col = INK.g3, w = tw - px(20), data = true }) end
    return BoardUI.hit(hstack({ gap = px(3), h = px(24) }, { t, chev }), { kind = "author" })
end

local function head(page, w)
    local d = page.data
    local inset = MenuUI.tapInset(24)
    local cw, ch = px(52), px(78)
    local close = MenuUI.iconButton("x", { kind = "close" })
    local tw = w - cw - px(14) - wOf(close) + inset - px(14)
    local chip = MenuUI.chip(d.bookmarked and T(_("%1 · page bookmarked"), pct(d.percent) or "") or T(_("Reading · %1"), pct(d.percent) or "?"),
        { icon = d.bookmarked and "bookmark-check" or "book-open", ink = true })
    local row = hstack({ w = w + inset, valign = "top", gap = px(14) }, {
        coverOf(page, cw, ch),
        vstack({ w = tw }, {
            text(d.title, { s = 18, b = true, w = tw, data = true }),
            d.author ~= "" and authorLine(d, tw) or false,
            space(nil, px(6)),
            chip,
        }),
        close,
    })
    return BoardUI.overlay(w, hOf(row), { { widget = row } })
end

-- Where you are: the book and the chapter, BookOrbit's two-row card.
local function where(page, w)
    local d = page.data
    local pad = px(16)
    local pw = w - 2 * pad
    local function line(glyph, label, value, bold)
        local v = text(value, { s = 14, b = bold, col = bold and INK.black or INK.g4, data = true })
        if wOf(v) > pw * 0.62 then v = text(value, { s = 14, b = bold, col = bold and INK.black or INK.g4, w = floor(pw * 0.62), data = true, align = "right" }) end
        return hstack({ w = pw, h = px(40), gap = px(12) }, {
            icon(glyph, px(20), { sw = 2 }),
            text(label, { s = 15, w = pw - px(20) - 2 * px(12) - wOf(v) }),
            v,
        })
    end
    local here = pct(d.percent) or "?"
    if d.page and d.pages then here = T(_("%1, page %2 of %3"), here, d.page, d.pages) end
    local rows = { line("book-open", _("This book"), here, true) }
    if d.chapter then
        local value = d.chapter
        if d.chapter_left then
            value = d.chapter_left == 0 and T(_("%1 · last page"), d.chapter)
                or (d.chapter_left == 1 and T(_("%1 · 1 page left"), d.chapter) or T(_("%1 · %2 pages left"), d.chapter, d.chapter_left))
        end
        rows[#rows + 1] = BoardUI.rect(pw, MenuUI.hair(), INK.gb)
        rows[#rows + 1] = line("list-ordered", _("Chapter"), value)
    end
    return MenuUI.card(w, rows, { vpad = 4 })
end

-- Four tiles, an icon over its name.
local function tiles(page, w)
    local items = {
        { "type", _("Style"), { kind = "style" } },
        { "list-ordered", _("Contents"), { kind = "toc" } },
        { "bookmark", _("Bookmarks"), { kind = "bookmarks" } },
        { "book-open", _("Pages"), { kind = "pages" } },
    }
    local gap = px(8)
    local tw = floor((w - (#items - 1) * gap) / #items)
    local th = px(64)
    local cells = {}
    for i, it in ipairs(items) do
        local cw = i == #items and (w - (#items - 1) * (tw + gap)) or tw
        local first = i == 1
        local b = math.max(1, px(1.25))
        local inner = vstack({ w = cw - 2 * b, align = "center" }, {
            space(nil, px(9)),
            hstack({ w = cw - 2 * b }, { flex(0), icon(it[1], px(22), { sw = 2.25, col = first and "white" or "black" }), flex(0) }),
            space(nil, px(5)),
            text(it[2], { s = 13, b = true, col = first and INK.white or INK.black, w = cw - 2 * b - px(8), align = "center" }),
        })
        local box = BoardUI.box({ w = cw, h = th, radius = px(12), border = first and 0 or b, border_col = INK.g6, bg = first and INK.black or INK.white }, inner)
        cells[i] = BoardUI.hit(box, it[3])
    end
    return hstack({ w = w, gap = gap }, cells)
end

-- A switch half the size of a row's, for the small buttons.
local function miniSwitch(on)
    local w, h, k, pad = px(30), px(18), px(12), px(3)
    local b = math.max(1, px(1.25))
    local track = on and BoardUI.rect(w, h, INK.black, floor(h / 2))
        or BoardUI.box({ w = w, h = h, radius = floor(h / 2), border = b, border_col = INK.g5, bg = INK.white })
    local knob = BoardUI.rect(k, k, on and INK.white or INK.g5, floor(k / 2))
    return BoardUI.overlay(w, h, { { widget = track }, { widget = knob, x = on and (w - pad - k) or pad, y = pad } })
end

-- Shortcuts into other plugins, as small outlined buttons in one row: only
-- those installed are shown, and nothing when none is.
local function quickRow(page, w)
    local d = page.data
    local items = {}
    if d.hid then items[#items + 1] = { icon = "bluetooth", label = _("Bluetooth"), switch = d.hid_on, action = { kind = "hid" } } end
    if d.syncery then
        items[#items + 1] = { icon = "refresh-cw", label = _("Sync now"), action = { kind = "sync" } }
        items[#items + 1] = { icon = "smartphone", label = _("Progress"), action = { kind = "sync_progress" } }
    end
    if #items == 0 then return nil end
    local gap = px(8)
    local bw = floor((w - (#items - 1) * gap) / #items)
    local h = px(42)
    local b = math.max(1, px(1.25))
    local cells = {}
    for i, it in ipairs(items) do
        local cw = i == #items and (w - (#items - 1) * (bw + gap)) or bw
        local inner_w = cw - 2 * b - 2 * px(10)
        local glyph = icon(it.icon, px(18), { sw = 2.25 })
        local switch = it.switch ~= nil and miniSwitch(it.switch) or nil
        local room = inner_w - wOf(glyph) - px(8) - (switch and (wOf(switch) + px(8)) or 0)
        local label = text(it.label, { s = 13, b = true, data = true })
        if wOf(label) > room then label:free(); label = text(it.label, { s = 13, b = true, w = math.max(px(16), room), data = true }) end
        local row = { glyph, space(px(8), 1), label }
        if switch then row[#row + 1] = flex(0); row[#row + 1] = switch
        else table.insert(row, 1, flex(0)); row[#row + 1] = flex(0) end
        local box = BoardUI.box({ w = cw, h = h, radius = px(12), border = b, border_col = INK.g6, bg = INK.white },
            hstack({ w = cw - 2 * b, h = h - 2 * b }, { space(px(10), 1), hstack({ w = inner_w, h = h - 2 * b }, row), space(px(10), 1) }))
        cells[i] = BoardUI.hit(box, it.action)
    end
    return hstack({ w = w, gap = gap }, cells)
end
Sheet.quickRow = quickRow

local function thisBook(page, w)
    local d = page.data
    local rows = {
        MenuUI.row(w, { icon = d.bookmarked and "bookmark-check" or "bookmark", label = _("Bookmark this page"),
            toggle = d.bookmarked, action = { kind = "bookmark" } }),
        MenuUI.row(w, { icon = "book-open-text", label = _("Book details"),
            sub = T(_("%1 highlights, %2 bookmarks"), d.highlights, d.bookmarks), chevron = true, action = { kind = "details" } }),
        MenuUI.row(w, { icon = "house", label = _("Aleph Home"), chevron = true, action = { kind = "home" } }),
    }
    -- X-Ray, when installed, right under the book's details.
    if d.xray then
        table.insert(rows, 3, MenuUI.row(w, { icon = "sparkles", label = _("X-Ray"),
            sub = d.xray_summary or _("Characters, places, terms and more"), chevron = true, action = { kind = "xray" } }))
    end
    local list = {}
    for index, r in ipairs(rows) do
        if index > 1 then list[#list + 1] = MenuUI.divider(w) end
        list[#list + 1] = r
    end
    local quick = quickRow(page, w)
    if quick then return { tiles(page, w), space(nil, px(10)), quick, space(nil, px(10)), vstack({ w = w }, list) } end
    return { tiles(page, w), space(nil, px(10)), vstack({ w = w }, list) }
end

local function alsoReading(page, w)
    local d = page.data
    local items = {}
    if #d.others == 0 then
        items[#items + 1] = hstack({ w = w, gap = px(8), valign = "top" }, {
            icon("book-open", px(16), { sw = 2.25 }),
            text(_("No other books in progress. Books you start show here, newest first."), { s = 13, col = INK.g3, w = w - px(24), lines = 2 }),
        })
    else
        local cw, ch = px(36), px(54)
        for i, b in ipairs(d.others) do
            if i > 1 then items[#items + 1] = MenuUI.divider(w, 0) end
            local tw = w - cw - px(12) - px(18) - px(8)
            local sub = {}
            if b.authors and b.authors[1] then sub[#sub + 1] = b.authors[1] end
            sub[#sub + 1] = T(_("%1 read"), tostring(floor((b.progressPercentage or 0) + 0.5)) .. "%")
            local row = hstack({ w = w, h = ch + px(12), gap = px(12) }, {
                BoardUI.cover(b, cw, ch, { path = b.cover_path, border = math.max(1, px(1)), border_col = INK.g6 }),
                vstack({ w = tw }, {
                    text(b.title or "", { s = 15, b = true, w = tw, data = true }),
                    text(table.concat(sub, " · "), { s = 13, col = INK.g4, w = tw, data = true }),
                    space(nil, px(4)),
                    BoardUI.bar(tw, math.max(2, px(3)), b.progressPercentage or 0, { r = px(2) }),
                }),
                icon("chevron-right", px(18), { sw = 2.25 }),
            })
            items[#items + 1] = BoardUI.hit(row, { kind = "switch", index = i })
        end
    end
    items[#items + 1] = MenuUI.divider(w, 0)
    items[#items + 1] = MenuUI.row(w, { icon = "library", label = _("All books"), sub = _("The library in Aleph"), chevron = true, action = { kind = "library" } })
    return { vstack({ w = w }, items) }
end

local function body(page, w)
    local d = page.data
    local tab = page.tab or "book"
    local tabs = MenuUI.segmented(w, { _("This book"), #d.others > 0 and T(_("Also reading · %1"), #d.others) or _("Also reading") },
        tab == "book" and 1 or 2, function(index) return { kind = "tab", tab = index == 1 and "book" or "others" } end)
    local items = { head(page, w), space(nil, px(14)), where(page, w), space(nil, px(14)), tabs, space(nil, px(12)) }
    for _i, it in ipairs(tab == "book" and thisBook(page, w) or alsoReading(page, w)) do items[#items + 1] = it end
    return items
end

-- BookOrbit's frame: a bottom sheet rounded at the top below 700dp, a
-- bordered popover above it.
local function build(page, sw, sh)
    pcall(function() require("aleph_picture").release(page) end)
    BoardMetrics.refresh()
    local mx = MenuUI.mx()
    local wide = BoardMetrics.layoutW() >= 700
    local panel_w = wide and math.min(px(540), sw - 2 * mx) or sw
    local pad = wide and px(20) or mx
    local w = panel_w - 2 * pad
    local content = vstack({ w = panel_w, pad = { px(18), pad, px(wide and 18 or 14), pad } }, body(page, w))
    -- Each tab at its own height: a shorter tab leaves no empty space (the
    -- page behind is the dimmed backdrop, repainted where the sheet was).
    local ph = hOf(content)
    local x = wide and floor((sw - panel_w) / 2) or 0
    local y = wide and (sh - ph - px(24)) or (sh - ph)
    local line = math.max(1, px(1.5))
    local r = px(16)
    local panel
    if wide then
        panel = BoardUI.box({ w = panel_w, h = ph, radius = r, border = line, border_col = INK.black, bg = INK.white }, content)
    else
        panel = BoardUI.overlay(panel_w, ph, {
            { widget = BoardUI.rect(panel_w, ph, INK.black, r) },
            { widget = BoardUI.rect(panel_w, r, INK.black), y = ph - r },
            { widget = BoardUI.rect(panel_w, ph - line, INK.white, r), y = line },
            { widget = BoardUI.rect(panel_w, r, INK.white), y = ph - r },
            { widget = content },
        })
    end
    page.panel_rect = Geom:new{ x = x, y = y, w = panel_w, h = ph }
    return BoardUI.overlay(sw, sh, { { widget = panel, x = x, y = y } })
end

-- ---------------------------------------------------------------- actions
local function handOff(page, fn)
    page:close()
    UIManager:nextTick(function()
        local ok, err = pcall(fn)
        if not ok then require("logger").warn("Aleph: reader menu action failed:", err) end
    end)
end

local function openBoard(ui, then_fn)
    local board = ui.aleph
    if not board then pcall(function() board = require("pluginloader"):getPluginInstance("aleph") end) end
    if board then
        board:onShowAleph()
        if then_fn and board.browser then then_fn(board.browser) end
    end
end

local function onAction(page, action)
    local ui = page.ui
    local k = action.kind
    if k == "tab" then
        page.tab = action.tab
        page:refresh()
    elseif k == "style" then
        handOff(page, function() Sheet.nativeMenu(ui) end)
    elseif k == "toc" then
        handOff(page, function() ui.toc:onShowToc() end)
    elseif k == "bookmarks" then
        handOff(page, function() ui.bookmark:onShowBookmark() end)
    elseif k == "pages" then
        handOff(page, function() require("aleph_page_browser").open(ui) end)
    elseif k == "bookmark" then
        ui:handleEvent(Event:new("ToggleBookmark"))
        page.data.bookmarked = bookmarked(ui)
        local h, b = annotationCounts(ui)
        page.data.highlights, page.data.bookmarks = h, b
        page:refresh()
    elseif k == "hid" then
        -- The plugin's own toggle: it says what it does, and starting can
        -- take a few seconds. The switch flips now and is checked after.
        local hid = plugin(ui, "hidpassthrough")
        if not hid then return true end
        page.data.hid_on = not page.data.hid_on
        page:refresh()
        local ok = pcall(function()
            if hid.onHIDPassthroughToggle then hid:onHIDPassthroughToggle() else hid:toggle() end
        end)
        if not ok then require("logger").warn("Aleph: HID passthrough toggle failed") end
        UIManager:scheduleIn(0.5, function()
            if page.closed then return end
            page.data.hid_on = hidRunning(hid)
            page:refresh()
        end)
    elseif k == "sync" then
        local syncery = plugin(ui, "syncery")
        if syncery then handOff(page, function() syncery:syncNow() end) end
    elseif k == "sync_progress" then
        local syncery = plugin(ui, "syncery")
        if syncery then handOff(page, function()
            if syncery.onSynceryProgressBrowser then syncery:onSynceryProgressBrowser()
            else require("syncery_ui/progress_browser/init").show(syncery) end
        end) end
    elseif k == "xray" then
        local d = page.data
        page:close()
        UIManager:nextTick(function()
            local ok, err = pcall(function() require("aleph_xray").open(ui, { title = d.title, author = d.author }) end)
            if not ok then require("logger").warn("Aleph: X-Ray sheet failed:", err) end
        end)
    elseif k == "author" then
        local Xray = require("aleph_xray")
        local plugin = Xray.plugin(ui)
        if plugin then page:close(); Xray.run(plugin, "showAuthorInfo") end
    elseif k == "details" then
        handOff(page, function() require("aleph_topbar_book").showDetails(ui) end)
    elseif k == "home" then
        handOff(page, function() openBoard(ui) end)
    elseif k == "library" then
        handOff(page, function()
            openBoard(ui, function(browser) pcall(function() browser:loadBooks({}) end) end)
        end)
    elseif k == "switch" then
        local b = page.data.others[action.index]
        if not b then return true end
        if not require("libs/libkoreader-lfs").attributes(b.path, "mode") then
            pcall(function() require("aleph_toast").show(_("This book is no longer on this device."), { icon = "x" }) end)
            return true
        end
        handOff(page, function()
            if ui.switchDocument then ui:switchDocument(b.path)
            else require("apps/reader/readerui"):showReader(b.path) end
        end)
    end
    return true
end

function Sheet.open(ui)
    if not ui or not ui.document then return nil end
    local page = MenuPage:new{
        name = "aleph_reader_sheet",
        backdrop = true,
        dismiss_outside = true,
        build = build,
        on_action = onAction,
        on_swipe = function(p, ges)
            if ges.direction == "south" then p:close() return true end
            if ges.direction == "west" or ges.direction == "east" then
                p.tab = (p.tab or "book") == "book" and "others" or "book"
                p:refresh()
                return true
            end
            return false
        end,
        on_close = function(p)
            pcall(function() require("aleph_picture").release(p) end)
            if p.cover_bb and p.cover_bb.free then p.cover_bb:free() end
            p.cover_bb = nil
        end,
        ui = ui,
        tab = "book",
        data = Sheet.data(ui),
    }
    UIManager:show(page, "ui")
    return page
end

-- KOReader's own bottom menu, whatever opened it.
function Sheet.nativeMenu(ui)
    local config = ui.config
    local ReaderConfig = require("apps/reader/modules/readerconfig")
    local native = ReaderConfig._rb_native_show
    if config and native then return native(config) end
    if config then return config:onShowConfigMenu() end
end

-- ReaderConfig:onShowConfigMenu opens the sheet; the original stays behind
-- Style and is used whenever the sheet is off or fails.
function Sheet.install()
    local ok, ReaderConfig = pcall(require, "apps/reader/modules/readerconfig")
    if not ok or type(ReaderConfig) ~= "table" or ReaderConfig._aleph_sheet then return end
    ReaderConfig._aleph_sheet = true
    local original = ReaderConfig.onShowConfigMenu
    ReaderConfig._rb_native_show = original
    ReaderConfig.onShowConfigMenu = function(self, ...)
        if not wanted() or not self.ui or not self.ui.document then return original(self, ...) end
        local shown, page = pcall(Sheet.open, self.ui)
        if shown and page then return true end
        if not shown then require("logger").warn("Aleph: reader menu failed:", page) end
        return original(self, ...)
    end
end

return Sheet
