-- Aleph modification, 2026-11-09: lines of reading stats at the top and
-- bottom of a book's pages ("bookends").
--[[--
A header and a footer painted in the page's top and bottom margins, each with a
left, a middle and a right slot. A slot shows one to three items, joined by
" · ". Items:

  progress      40%                   page        825 / 2049
  page_of       Page 825 of 2049      pages_left  38 pages left in chapter
  chapter_time  14 min left in chapter  book_time  27h 31m left
  chapter       the chapter's title   title       the book's title
  author        the author            clock       12:48
  date          Mon 9 Nov             battery     ▮ 88% (the board's battery)
  wifi          the Wi-Fi mark (only while on)   light   ☀ 19
  session       12m read (since the book was opened)

The text is light gray, gray (the default) or black, or a colour of one's
own on a colour screen, and regular or bold.

Under the header, optionally, a hairline progress line (the read part inked),
with ticks at the chapters if wanted.

Designs taken from:
  - ZenOS (modules/reader/patches/reader_top_status_bar.lua): the three-zone
    header painted after ReaderView, page view only.
  - Bookends 5.31 (bookends.koplugin, AGPL-3.0 like Aleph): the item
    set and its sources (statistics' avg_time for time left, ReaderToc's
    getChapterPagesLeft, powerd), hiding KOReader's own status bar with
    applyFooterMode(off), no painting in the forked thumbnail subprocess, a
    minute tick that repaints only while the reader is uncovered (its #114).
Written anew on Aleph's parts (fonts, sizes, grays, icons). The minute
tick repaints the whole band of the header and footer, never a part of it, so
an old clock is never left behind beside a new one.

Settings: G_reader_settings aleph.bookends (see Bookends.config); the
page to change them is aleph_bookends_page.lua. While the Bookends
plugin itself is on, nothing is painted here, so the two never overlap.
]]

local Device = require("device")
local Geom = require("ui/geometry")
local UIManager = require("ui/uimanager")
local T = require("ffi/util").template
local _ = require("gettext")

local BoardMetrics = require("aleph_board_metrics")
local BoardUI = require("aleph_board_ui")

local Screen = Device.screen
local INK = BoardMetrics.INK
local px = BoardMetrics.px
local floor = math.floor

local Bookends = {}

Bookends.ITEMS = {
    { id = "progress", label = function() return _("Progress") end, sample = "40%" },
    { id = "page", label = function() return _("Page") end, sample = "825 / 2049" },
    { id = "page_of", label = function() return _("Page of pages") end, sample = "Page 825 of 2049" },
    { id = "pages_left", label = function() return _("Pages left in chapter") end, sample = "38 pages left in chapter" },
    { id = "chapter_time", label = function() return _("Time left in chapter") end, sample = "14 min left in chapter" },
    { id = "book_time", label = function() return _("Time left in book") end, sample = "27h 31m left" },
    { id = "chapter", label = function() return _("Chapter") end, sample = "Chapter 21" },
    { id = "title", label = function() return _("Book title") end, sample = "East of Eden" },
    { id = "author", label = function() return _("Author") end, sample = "John Steinbeck" },
    { id = "clock", label = function() return _("Clock") end, sample = "12:48" },
    { id = "date", label = function() return _("Date") end, sample = "Mon 9 Nov" },
    { id = "battery", label = function() return _("Battery") end, sample = "88%" },
    { id = "wifi", label = function() return _("Wi-Fi") end, sample = "" },
    { id = "light", label = function() return _("Front light") end, sample = "19" },
    { id = "session", label = function() return _("Read this sitting") end, sample = "12m read" },
}
local ITEM_BY_ID = {}
for _i, it in ipairs(Bookends.ITEMS) do ITEM_BY_ID[it.id] = it end
Bookends.ITEM_BY_ID = ITEM_BY_ID

Bookends.SIZES = { small = 12, medium = 13, large = 15 }
-- The text's ink: three grays, or a colour of one's own (colour screens).
Bookends.INKS = { "light", "gray", "black", "custom" }
local INK_PRESETS = {
    light = { col = "g6", hex = "#666666" },
    gray = { col = "g3", hex = "#333333" },
    black = { col = "black", hex = "#000000" },
}
Bookends.LINES = { "none", "progress", "chapters" }
Bookends.MAX_ITEMS = 3

-- What Bookends showed on the Kindle in the photos: progress, clock and
-- battery over a progress line; time left in the chapter, this sitting and
-- time left in the book at the foot.
local DEFAULTS = {
    top = true, bottom = true,
    slots = {
        top = { left = { "progress" }, middle = { "clock" }, right = { "battery" } },
        bottom = { left = { "chapter_time" }, middle = { "session" }, right = { "book_time" } },
    },
    line = "progress",
    size = "small",
    hide_stock = false,
    ink = "gray", ink_hex = nil,
    bold = false,
    -- How far the top line sits from the top edge and the bottom line from
    -- the bottom edge, in steps of 2 from where they are by default.
    top_offset = 0, bottom_offset = 0,
}
Bookends.OFFSET_MIN, Bookends.OFFSET_MAX, Bookends.OFFSET_STEP = -6, 40, 2

local function copy(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = copy(v) end
    return out
end

-- The saved settings over the defaults.
function Bookends.config()
    local stored = G_reader_settings:readSetting("aleph")
    local saved = type(stored) == "table" and type(stored.bookends) == "table" and stored.bookends or {}
    local c = copy(DEFAULTS)
    for _i, key in ipairs({ "top", "bottom", "line", "size", "hide_stock", "ink", "ink_hex", "bold", "top_offset", "bottom_offset" }) do
        if saved[key] ~= nil then c[key] = saved[key] end
    end
    if type(saved.slots) == "table" then
        for _i, edge in ipairs({ "top", "bottom" }) do
            for _j, slot in ipairs({ "left", "middle", "right" }) do
                local list = saved.slots[edge] and saved.slots[edge][slot]
                if type(list) == "table" then
                    local clean = {}
                    for _k, id in ipairs(list) do
                        if ITEM_BY_ID[id] and #clean < Bookends.MAX_ITEMS then clean[#clean + 1] = id end
                    end
                    c.slots[edge][slot] = clean
                end
            end
        end
    end
    if not Bookends.SIZES[c.size] then c.size = DEFAULTS.size end
    if not (INK_PRESETS[c.ink] or (c.ink == "custom" and type(c.ink_hex) == "string" and c.ink_hex:match("^#%x%x%x%x%x%x$"))) then
        c.ink = DEFAULTS.ink
    end
    c.bold = c.bold == true
    for _i, key in ipairs({ "top_offset", "bottom_offset" }) do
        local v = tonumber(c[key]) or 0
        c[key] = math.max(Bookends.OFFSET_MIN, math.min(Bookends.OFFSET_MAX, floor(v + 0.5)))
    end
    return c
end

-- Whether a colour is light enough that text in it would be hard to read on
-- a white page.
function Bookends.tooLight(hex)
    local r, g, b = tostring(hex or ""):match("#?(%x%x)(%x%x)(%x%x)")
    if not r then return true end
    return (0.299 * tonumber(r, 16) + 0.587 * tonumber(g, 16) + 0.114 * tonumber(b, 16)) / 255 > 0.7
end

function Bookends.colourScreen()
    local ok, on = pcall(function() return Screen:isColorEnabled() end)
    return ok and on and true or false
end

-- The text's colour: { col = a colour for text and shapes, hex = for icons }.
-- A custom colour on a gray screen becomes the gray of its brightness.
function Bookends.ink(c)
    local preset = INK_PRESETS[c.ink]
    if preset then return { col = INK[preset.col], hex = preset.hex } end
    local hex = c.ink_hex
    local Blitbuffer = require("ffi/blitbuffer")
    if Bookends.colourScreen() then
        local ok, col = pcall(Blitbuffer.colorFromString, hex)
        if ok and col then return { col = col, hex = hex } end
    end
    local r, g, b = hex:match("#?(%x%x)(%x%x)(%x%x)")
    local level = floor(0.299 * tonumber(r, 16) + 0.587 * tonumber(g, 16) + 0.114 * tonumber(b, 16) + 0.5)
    return { col = Blitbuffer.Color8(level), hex = string.format("#%02x%02x%02x", level, level, level) }
end

-- The settings for drawing, read-only, kept until they change: the bands are
-- painted on every page turn, and config() copies the whole table. Editors
-- keep using config(), which returns a copy of their own.
local current_cache = { version = -1 }
Bookends._version = 0

function Bookends.current()
    local stored = G_reader_settings:readSetting("aleph")
    local saved = type(stored) == "table" and stored.bookends or nil
    if current_cache.version == Bookends._version and current_cache.saved == saved and current_cache.config then
        return current_cache.config
    end
    local c = Bookends.config()
    current_cache = { version = Bookends._version, saved = saved, config = c }
    return c
end

function Bookends.save(c)
    Bookends._version = Bookends._version + 1
    local stored = G_reader_settings:readSetting("aleph")
    if type(stored) ~= "table" then stored = {} end
    stored.bookends = c
    G_reader_settings:saveSetting("aleph", stored)
end

function Bookends.reset()
    Bookends._version = Bookends._version + 1
    local stored = G_reader_settings:readSetting("aleph")
    if type(stored) == "table" then
        stored.bookends = nil
        G_reader_settings:saveSetting("aleph", stored)
    end
end

local function enabledHere()
    local stored = G_reader_settings:readSetting("aleph")
    return not (type(stored) == "table" and stored.bookends_enabled == false)
end
Bookends.enabledHere = enabledHere

-- The Bookends plugin draws its own; this stays out of its way.
local function otherBookends(ui)
    local b = ui and rawget(ui, "bookends")
    return type(b) == "table" and b.enabled ~= false
end
Bookends.otherBookends = otherBookends

-- ------------------------------------------------------------------ values
local function minutes(m)
    m = math.max(0, floor(m + 0.5))
    if m < 60 then return T(_("%1 min"), m) end
    local h = floor(m / 60)
    local r = m % 60
    if r == 0 then return T(_("%1h"), h) end
    return T(_("%1h %2m"), h, r)
end
Bookends.minutes = minutes

local function avgSeconds(ui)
    local stats = ui.statistics
    local avg = stats and tonumber(stats.avg_time)
    if avg and avg > 0 and avg < math.huge then return avg end
end

-- The state an item is drawn from, read once per paint.
function Bookends.state(ui)
    local s = {}
    pcall(function() s.page = ui:getCurrentPage() end)
    pcall(function() s.pages = ui.document:getPageCount() end)
    s.page, s.pages = tonumber(s.page), tonumber(s.pages)
    if s.page and s.pages and s.pages > 0 then s.percent = s.page / s.pages end
    pcall(function() s.chapter_left = tonumber(ui.toc:getChapterPagesLeft(s.page)) end)
    pcall(function() s.chapter = ui.toc:getTocTitleByPage(s.page) end)
    s.avg = avgSeconds(ui)
    local props = ui.doc_props or {}
    s.title = props.display_title or props.title
    local authors = props.authors
    if type(authors) == "table" then authors = table.concat(authors, ", ") end
    s.author = type(authors) == "string" and authors:gsub("\n", ", ") or nil
    s.session_start = ui._rb_bookends_since
    return s
end

-- One item: { text = ..., icon = ..., battery = n } or nil for nothing.
function Bookends.value(id, s, ui)
    if id == "progress" then
        if s.percent then return { text = floor(s.percent * 100 + 0.5) .. "%" } end
    elseif id == "page" then
        if s.page and s.pages then return { text = s.page .. " / " .. s.pages } end
    elseif id == "page_of" then
        if s.page and s.pages then return { text = T(_("Page %1 of %2"), s.page, s.pages) } end
    elseif id == "pages_left" then
        local n = s.chapter_left
        if n then
            if n == 0 then return { text = _("Last page of chapter") } end
            return { text = n == 1 and _("1 page left in chapter") or T(_("%1 pages left in chapter"), n) }
        end
    elseif id == "chapter_time" then
        if s.chapter_left and s.avg then
            return { text = T(_("%1 left in chapter"), minutes((s.chapter_left + 1) * s.avg / 60)) }
        end
    elseif id == "book_time" then
        if s.page and s.pages and s.avg then
            return { text = T(_("%1 left"), minutes((s.pages - s.page + 1) * s.avg / 60)) }
        end
    elseif id == "chapter" then
        if type(s.chapter) == "string" and s.chapter:match("%S") then return { text = s.chapter } end
    elseif id == "title" then
        if s.title and s.title ~= "" then return { text = s.title } end
    elseif id == "author" then
        if s.author and s.author ~= "" then return { text = s.author } end
    elseif id == "clock" then
        return { text = require("datetime").secondsToHour(os.time(), G_reader_settings:isTrue("twelve_hour_clock")) }
    elseif id == "date" then
        return { text = (os.date("%a %d %b"):gsub(" 0", " ")) }
    elseif id == "battery" then
        local ok, cap = pcall(function() return Device:hasBattery() and Device:getPowerDevice():getCapacity() end)
        if ok and cap then
            local charging = false
            pcall(function() charging = Device:getPowerDevice():isCharging() and true or false end)
            return { battery = cap, charging = charging, text = cap .. "%" }
        end
    elseif id == "wifi" then
        local on = false
        pcall(function() on = require("ui/network/manager"):isWifiOn() end)
        if on then return { icon = "wifi" } end
    elseif id == "light" then
        local ok, level = pcall(function()
            local powerd = Device:getPowerDevice()
            return Device:hasFrontlight() and powerd:frontlightIntensity()
        end)
        if ok and level then return { icon = "sun", text = tostring(level) } end
    elseif id == "session" then
        if s.session_start then
            local m = (os.time() - s.session_start) / 60
            return { text = T(_("%1 read"), m < 60 and (floor(m) .. "m") or minutes(m)) }
        end
    end
    return nil
end

-- ----------------------------------------------------------------- drawing
-- The board's battery: an outline, its fill and the nub (as in its status
-- cluster), the bolt while charging.
local function battery(v, size, col, hex)
    local bw, bh = px(size + 7), px(floor(size * 0.85 + 0.5))
    local b = math.max(1, px(1.25))
    local pad = px(1.5)
    local fill_w = math.max(1, floor((bw - 2 * b - 2 * pad) * v.battery / 100 + 0.5))
    local body = BoardUI.box({ w = bw, h = bh, border = b, border_col = col, radius = px(2.5) },
        BoardUI.hstack({ h = bh - 2 * b }, { BoardUI.space(pad, 1), BoardUI.rect(fill_w, bh - 2 * b - 2 * pad, col, px(1)) }))
    local parts = {}
    if v.charging then parts[#parts + 1] = BoardUI.icon("zap", px(size + 2), { sw = 1.25, col = hex }) end
    parts[#parts + 1] = BoardUI.hstack({}, { body, BoardUI.rect(px(2), px(4.5), col) })
    return BoardUI.hstack({ gap = px(4) }, parts)
end
Bookends.batteryWidget = battery

-- One slot's widget, items joined by " · ".
local function slotWidget(ids, s, ui, size, ink, max_w, bold)
    local col = ink.col
    local parts = {}
    for _i, id in ipairs(ids) do
        local ok, v = pcall(Bookends.value, id, s, ui)
        if ok and v then
            if #parts > 0 then parts[#parts + 1] = BoardUI.text("·", { s = size, col = col, b = bold }) end
            if v.battery then parts[#parts + 1] = battery(v, size, col, ink.hex) end
            if v.icon then parts[#parts + 1] = BoardUI.icon(v.icon, px(size + 3), { sw = bold and 2.75 or 2.25, col = ink.hex }) end
            if v.text and v.text ~= "" then
                parts[#parts + 1] = { text = v.text }
            end
        end
    end
    if #parts == 0 then return nil end
    -- Text parts are made last, so a slot too wide for its room is cut in its
    -- text, never in its marks.
    local fixed, texts = 0, 0
    for _i, p in ipairs(parts) do
        if p.text then texts = texts + 1 else fixed = fixed + p:getSize().w end
    end
    local gap = px(5)
    local room = max_w and (max_w - fixed - gap * (#parts - 1)) or nil
    local each = room and texts > 0 and floor(room / texts) or nil
    local widgets = {}
    for i, p in ipairs(parts) do
        if p.text then
            local t = BoardUI.text(p.text, { s = size, col = col, b = bold, data = true })
            if each and t:getSize().w > each then
                t:free()
                t = BoardUI.text(p.text, { s = size, col = col, b = bold, w = math.max(px(16), each), data = true })
            end
            widgets[i] = t
        else
            widgets[i] = p
        end
    end
    return BoardUI.hstack({ gap = gap }, widgets)
end

-- A band: left, middle and right; the middle is centred on the page and the
-- sides have what is left either side of it.
local function band(slots, s, ui, size, ink, w, mx, bold)
    local h = BoardMetrics.lh1(size) + px(2)
    local middle = slotWidget(slots.middle or {}, s, ui, size, ink, floor(w * 0.5), bold)
    local mw = middle and middle:getSize().w or 0
    local side = floor((w - 2 * mx - mw) / 2) - px(12)
    local left = slotWidget(slots.left or {}, s, ui, size, ink, side, bold)
    local right = slotWidget(slots.right or {}, s, ui, size, ink, side, bold)
    local layers = {}
    local function place(widget, x)
        local wh = widget:getSize().h
        layers[#layers + 1] = { widget = widget, x = x, y = floor((h - wh) / 2) }
    end
    if left then place(left, mx) end
    if middle then place(middle, floor((w - mw) / 2)) end
    if right then place(right, w - mx - right:getSize().w) end
    if #layers == 0 then return nil, h end
    return BoardUI.overlay(w, h, layers), h
end

-- The line under the header: a hairline with the read part inked, ticks at
-- the chapters.
-- The chapter marks on the top line: their places are worked out once per
-- book, page count and width, and drawn as plain rectangles (no widget each).
local Widget = require("ui/widget/widget")
local Ticks = Widget:extend{ xs = nil, mark_w = 1, mark_h = 1 }
function Ticks:getSize() return { w = self.w, h = self.mark_h } end
function Ticks:paintTo(bb, x, y)
    for _i, tx in ipairs(self.xs) do bb:paintRect(x + tx, y, self.mark_w, self.mark_h, INK.g5) end
end

local ticks_cache = {}
function Bookends.ticks(ui, pages, lw, thick)
    local toc
    pcall(function() toc = ui.toc.toc end)
    if type(toc) ~= "table" then toc = {} end
    if ticks_cache.toc ~= toc or ticks_cache.pages ~= pages or ticks_cache.lw ~= lw then
        local xs = {}
        for _i, item in ipairs(toc) do
            local p = tonumber(item.page)
            if p and (tonumber(item.depth) or 1) <= 1 and p > 1 then
                xs[#xs + 1] = floor(lw * (p - 1) / (pages - 1))
                if #xs >= 200 then break end
            end
        end
        ticks_cache = { toc = toc, pages = pages, lw = lw, xs = xs }
    end
    return Ticks:new{ xs = ticks_cache.xs, w = lw, mark_w = math.max(1, px(1)), mark_h = thick + px(4) }
end

local function progressLine(ui, s, w, mx, ticks)
    local lw = w - 2 * mx
    local line = math.max(1, px(1))
    local thick = math.max(2, px(2))
    local layers = {
        { widget = BoardUI.rect(lw, line, INK.gb), x = 0, y = floor((thick - line) / 2) },
    }
    if s.percent then
        layers[#layers + 1] = { widget = BoardUI.rect(math.max(1, floor(lw * s.percent)), thick, INK.g3), x = 0, y = 0 }
    end
    if ticks and s.pages and s.pages > 1 then
        layers[#layers + 1] = { widget = Bookends.ticks(ui, s.pages, lw, thick), x = 0, y = -px(2) }
    end
    return BoardUI.overlay(lw, thick, layers), thick
end

-- Whether KOReader's status bar draws anything. It can be "on" with every
-- item and the progress bar turned off: it then still has a height, and the
-- bottom line sat that much higher over an empty bar.
local function footerShows(footer)
    local settings = footer.settings or {}
    if not settings.disable_progress_bar then return true end
    if footer.has_no_mode then return false end
    local text = footer.footer_text and footer.footer_text.text
    if type(text) == "string" and not text:match("%S") then return false end
    return true
end
Bookends.footerShows = footerShows

-- Where the bands go on this screen (also used by the pin badge).
function Bookends.geometry(ui)
    local c = Bookends.current()
    local size = Bookends.SIZES[c.size]
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    local text_h = BoardMetrics.lh1(size) + px(2)
    local top_y = px(8 + (c.top_offset or 0))
    local top_h = c.top and (top_y + text_h + ((c.line ~= "none") and (px(5) + px(2)) or 0) + px(4)) or 0
    local footer_h = 0
    local footer = ui and ui.view and ui.view.footer
    if footer and ui.view.footer_visible and not c.hide_stock and footer.getHeight then
        local ok, shows = pcall(footerShows, footer)
        if not ok or shows then
            local ok2, height = pcall(footer.getHeight, footer)
            footer_h = ok2 and tonumber(height) or 0
        end
    end
    local bottom_h = c.bottom and (text_h + px(10 + (c.bottom_offset or 0))) or 0
    return {
        config = c, size = size, sw = sw, sh = sh, text_h = text_h, top_y = top_y,
        top = Geom:new{ x = 0, y = 0, w = sw, h = top_h },
        bottom = Geom:new{ x = 0, y = sh - footer_h - bottom_h, w = sw, h = bottom_h },
        footer_h = footer_h,
    }
end

-- The height the footer takes, for things placed above it (the pin badge).
function Bookends.bottomHeight(ui)
    if not Bookends.showing(ui) then return 0 end
    local g = Bookends.geometry(ui)
    return g.bottom.h
end

function Bookends.showing(ui)
    if not enabledHere() or Bookends._subprocess then return false end
    if not ui or not ui.document or not ui.view then return false end
    if otherBookends(ui) then return false end
    -- Page view only, as ZenOS's header.
    return ui.view.view_mode == "page" or ui.view.view_mode == nil
end

function Bookends.paint(view, bb)
    local ui = view.ui
    if bb ~= Screen.bb or not Bookends.showing(ui) then return end
    local g = Bookends.geometry(ui)
    local c = g.config
    if not c.top and not c.bottom then return end
    local s = Bookends.state(ui)
    local ink = Bookends.ink(c)
    local mx = math.max(px(18), floor(g.sw * 0.06))
    local widgets = {}
    if c.top then
        local b = band(c.slots.top, s, ui, g.size, ink, g.sw, mx, c.bold)
        local y = g.top_y
        if b then widgets[#widgets + 1] = { b, 0, y } end
        if c.line ~= "none" then
            local line = progressLine(ui, s, g.sw, mx, c.line == "chapters")
            widgets[#widgets + 1] = { line, mx, y + g.text_h + px(5) }
        end
    end
    if c.bottom then
        local b = band(c.slots.bottom, s, ui, g.size, ink, g.sw, mx, c.bold)
        if b then widgets[#widgets + 1] = { b, 0, g.bottom.y + px(4) } end
    end
    for _i, w in ipairs(widgets) do
        pcall(w[1].paintTo, w[1], bb, w[2], w[3])
        if w[1].free then pcall(w[1].free, w[1]) end
    end
end

-- ------------------------------------------------------------------ ticks
-- Items that change without a page turn.
local TIMED = { clock = true, date = true, battery = true, wifi = true, light = true, session = true, chapter_time = true, book_time = true }

local function usesTimed(c)
    for _i, edge in ipairs({ "top", "bottom" }) do
        if c[edge] then
            for _j, slot in ipairs({ "left", "middle", "right" }) do
                for _k, id in ipairs(c.slots[edge][slot] or {}) do
                    if TIMED[id] then return true end
                end
            end
        end
    end
    return false
end

-- Repaints both bands whole: the page under them and the text on it.
function Bookends.repaint(ui)
    if not ui or not ui.view then return end
    local g = Bookends.geometry(ui)
    for _i, rect in ipairs({ g.top, g.bottom }) do
        if rect.h > 0 then UIManager:setDirty(ui.dialog or "all", "ui", rect) end
    end
end

-- Whether the reader is what is on screen (Bookends' #114: a repaint under a
-- menu is wasted, and the menu's own close repaints the page anyway).
local function uncovered(ui)
    local top = UIManager:getTopmostVisibleWidget()
    return top == nil or top == ui or top == ui.dialog or (top.name == "ReaderUI")
end

local function tick(ui)
    if not ui._rb_bookends_timer then return end
    if Bookends.showing(ui) and usesTimed(Bookends.current()) and uncovered(ui) then
        Bookends.repaint(ui)
    end
    -- On the next minute, so the clock turns with the device's.
    UIManager:scheduleIn(60 - (os.time() % 60) + 1, ui._rb_bookends_timer)
end

-- ---------------------------------------------------------------- install
function Bookends.install()
    local View = require("apps/reader/modules/readerview")
    if View._aleph_bookends then return end
    View._aleph_bookends = true
    local paint = View.paintTo
    View.paintTo = function(self, bb, x, y)
        paint(self, bb, x, y)
        local ok, err = pcall(Bookends.paint, self, bb)
        if not ok and not Bookends._warned then
            Bookends._warned = true
            require("logger").warn("Aleph: bookends failed:", err)
        end
    end
    -- Never in the forked thumbnail renderer (Bookends: its battery and other
    -- reads can block there, and a thumbnail has no room for them).
    pcall(function()
        require("ffi/util").addRunInSubProcessAfterForkFunc("aleph_bookends_skip", function()
            Bookends._subprocess = true
        end)
    end)
end

-- KOReader's own status bar, hidden while the setting asks (Bookends'
-- stock_bar_disabled).
function Bookends.applyStock(ui)
    local footer = ui and ui.view and ui.view.footer
    if not footer or not footer.mode_list then return end
    local c = Bookends.config()
    if Bookends.showing(ui) and c.hide_stock and c.bottom then
        pcall(function() footer:applyFooterMode(footer.mode_list.off) end)
    end
end

function Bookends.attach(ui)
    if not ui or not ui.document or ui._rb_bookends_timer then return end
    ui._rb_bookends_since = os.time()
    ui._rb_bookends_timer = function() tick(ui) end
    UIManager:scheduleIn(60 - (os.time() % 60) + 1, ui._rb_bookends_timer)
    Bookends.applyStock(ui)
end

function Bookends.detach(ui)
    if not ui or not ui._rb_bookends_timer then return end
    UIManager:unschedule(ui._rb_bookends_timer)
    ui._rb_bookends_timer = nil
end

-- After a change in the settings: KOReader's bar, then the page.
function Bookends.changed(ui)
    if not ui or not ui.document then return end
    Bookends.applyStock(ui)
    UIManager:setDirty(ui.dialog or "all", "ui")
end

return Bookends
