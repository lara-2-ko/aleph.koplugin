-- Aleph modification, 2026-11-09: the bookmarks list as an Aleph
-- page, after Annotations Viewer's list.
--[[--
Every highlight, note and page bookmark of the book, each shown whole: where
and when (chapter · day) with the page on the right, the passage in its own
highlight color (a tint for Lighten and Invert, a colored rule beside it for
Underline and Strikeout), and the note under it. A passage longer than six
lines ends in "…". Items fill each page as they fit, so pages hold more short
ones than long ones.

  header        ≡ options: search, go to the current page or the latest
                bookmark, export, and KOReader's own list (select several,
                the edited-text filter); the title with the count, sort, close
  sort          cycles Page order → Newest first → Oldest first (remembered)
  filters       All / Highlights / Bookmarks / Notes, then the styles and the
                colors (tap one again to show all); counts follow the filters
  tap an item   a sheet with the whole passage (paged when long) and note,
                Go to in book, and Edit (KOReader's details: edit, note,
                style, delete)
  hold an item  go straight to it in the book
  pages         ‹ › and the ends, swipes, the page keys

In page order the list opens on the page of the item nearest your reading
position. If anything fails, KOReader's own list opens instead.
]]

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Event = require("ui/event")
local TextBoxWidget = require("ui/widget/textboxwidget")
local UIManager = require("ui/uimanager")
local datetime = require("datetime")
local T = require("ffi/util").template
local _ = require("gettext")

local BoardMetrics = require("aleph_board_metrics")
local BoardUI = require("aleph_board_ui")
local MenuPage = require("aleph_menu_page")
local MenuUI = require("aleph_menu_ui")
local SheetUI = require("aleph_sheet_ui")
local TextPages = require("aleph_text_pages")

local Screen = Device.screen
local INK = BoardMetrics.INK
local px, lh = BoardMetrics.px, BoardMetrics.lh
local text, vstack, hstack, space, flex, icon = BoardUI.text, BoardUI.vstack, BoardUI.hstack, BoardUI.space, BoardUI.flex, BoardUI.icon
local floor = math.floor

local Bookmarks = {}

local QUOTE_SIZE = 15
local QUOTE_LINES = 6
local NOTE_LINES = 3
local SORTS = { "page", "newest", "oldest" }
local SORT_LABELS = {
    page = function() return _("Page order") end,
    newest = function() return _("Newest first") end,
    oldest = function() return _("Oldest first") end,
}

local function hOf(widget) return widget:getSize().h end
local function wOf(widget) return widget:getSize().w end

local function settings()
    local stored = G_reader_settings:readSetting("aleph")
    if type(stored) ~= "table" then stored = {} end
    return stored
end

local function saveSort(sort)
    local stored = settings()
    stored.bookmarks_sort = sort
    G_reader_settings:saveSetting("aleph", stored)
end

-- ------------------------------------------------------------------ data
local function trimmed(value)
    if type(value) ~= "string" then return nil end
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    return value ~= "" and value or nil
end

-- "13 Sep", with the year when it is not this one.
function Bookmarks.day(stamp)
    local y, m, d = tostring(stamp or ""):match("^(%d%d%d%d)%-(%d%d)%-(%d%d)")
    if not y then return nil end
    local t = os.time{ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 }
    local fmt = (y == os.date("%Y")) and "%d %b" or "%d %b %Y"
    return (os.date(fmt, t):gsub("^0", ""))
end

local function kindOf(bm, item)
    local ok, kind = pcall(bm.getBookmarkType, item)
    if ok and kind then return kind end
    if item.note and item.note ~= "" then return "note" end
    if item.pos0 then return "highlight" end
    return "bookmark"
end

local function pageOf(bm, item)
    local label
    pcall(function() label = bm:getBookmarkPageString(item.page) end)
    if label == nil or label == "" then label = item.pageno or (type(item.page) == "number" and item.page) or nil end
    return label and tostring(label) or ""
end

local function numericPage(item)
    if tonumber(item.pageno) then return tonumber(item.pageno) end
    if type(item.page) == "number" then return item.page end
    return nil
end

-- Every annotation as an entry the page draws; index is its place in
-- KOReader's list (book order).
function Bookmarks.entries(ui)
    local bm = ui.bookmark
    local out = {}
    for index, item in ipairs(ui.annotation and ui.annotation.annotations or {}) do
        local kind = kindOf(bm, item)
        out[#out + 1] = {
            index = index, item = item, kind = kind,
            text = trimmed(item.text), note = trimmed(item.note), chapter = trimmed(item.chapter),
            drawer = item.drawer, color = item.color,
            page = pageOf(bm, item), pageno = numericPage(item),
            datetime = item.datetime, day = Bookmarks.day(item.datetime),
        }
    end
    return out
end

-- The entries the filters let through, in the chosen order.
function Bookmarks.view(entries, state)
    local list = {}
    for _i, e in ipairs(entries) do
        local ok = true
        if state.kind and e.kind ~= state.kind then ok = false end
        if state.drawer and (e.kind == "bookmark" or e.drawer ~= state.drawer) then ok = false end
        if state.color and (e.kind == "bookmark" or e.color ~= state.color) then ok = false end
        if ok and state.search then
            local needle = state.search:lower()
            local hay = ((e.text or "") .. "\n" .. (e.note or "") .. "\n" .. (e.chapter or "")):lower()
            if not hay:find(needle, 1, true) then ok = false end
        end
        if ok then list[#list + 1] = e end
    end
    if state.sort == "newest" or state.sort == "oldest" then
        local newest = state.sort == "newest"
        table.sort(list, function(a, b)
            local da, db = a.datetime or "", b.datetime or ""
            if da == db then return a.index < b.index end
            if newest then return da > db end
            return da < db
        end)
    end
    return list
end

-- How many of each kind the style and color filters let through.
function Bookmarks.counts(entries, state)
    local counts = { all = 0, highlight = 0, bookmark = 0, note = 0 }
    for _i, e in ipairs(entries) do
        local ok = true
        if state.drawer and (e.kind == "bookmark" or e.drawer ~= state.drawer) then ok = false end
        if state.color and (e.kind == "bookmark" or e.color ~= state.color) then ok = false end
        if ok then
            counts.all = counts.all + 1
            counts[e.kind] = (counts[e.kind] or 0) + 1
        end
    end
    return counts
end

-- ---------------------------------------------------------------- colors
local function HL() return require("aleph_highlight") end

-- The highlight's color lightened toward white, as the page shows a tint:
-- a color on a color screen, its gray on a black and white one.
local function tint(color, amount)
    local hex = HL().palette.hex(color or "yellow")
    local r, g, b = tostring(hex):match("#?(%x%x)(%x%x)(%x%x)")
    if not r then return INK.ge end
    local k = amount or 0.55
    local function mix(v) return floor(tonumber(v, 16) + (255 - tonumber(v, 16)) * k + 0.5) end
    local R, G, B = mix(r), mix(g), mix(b)
    if Screen:isColorEnabled() then
        return Blitbuffer.colorFromString(string.format("#%02X%02X%02X", R, G, B))
    end
    return Blitbuffer.Color8(floor(0.299 * R + 0.587 * G + 0.114 * B + 0.5))
end

local function solid(color)
    if Screen:isColorEnabled() then return HL().colorOf(HL().palette.hex(color or "yellow")) end
    return INK.g6
end

-- ---------------------------------------------------------------- an item
local function quoteBlock(e, w, max_lines)
    local filled = e.drawer == "lighten" or e.drawer == "invert" or e.drawer == nil
    if e.kind == "bookmark" then
        local label = e.chapter and T(_("in %1"), e.chapter) or _("Page bookmark")
        return hstack({ w = w, gap = px(8) }, { icon("bookmark", px(18), { sw = 2.25 }), text(label, { s = QUOTE_SIZE, b = true, w = w - px(26), data = true }) })
    end
    local str = e.text or ""
    if filled then
        local pad = px(8)
        local bg = tint(e.color)
        local tw = w - 2 * pad
        local lines = math.max(1, math.min(max_lines, TextPages.linesNeeded(str, { s = QUOTE_SIZE, serif = true }, tw)))
        -- One line is drawn straight onto the tint; more lines in a text box
        -- painted the tint's color.
        local body = lines > 1 and text(str, { s = QUOTE_SIZE, serif = true, w = tw, lines = lines, bg = bg, data = true })
            or text(str, { s = QUOTE_SIZE, serif = true, w = tw, data = true })
        return BoardUI.box({ w = w, h = hOf(body) + 2 * px(4), radius = px(4), bg = bg },
            vstack({ w = w, pad = { px(4), pad, px(4), pad } }, { body }))
    end
    -- Underline, strikeout: a colored rule down the left edge.
    local bar = math.max(3, px(4))
    local tw = w - bar - px(10)
    local lines = math.max(1, math.min(max_lines, TextPages.linesNeeded(str, { s = QUOTE_SIZE, serif = true }, tw)))
    local body = text(str, { s = QUOTE_SIZE, serif = true, w = tw, lines = lines, data = true })
    return hstack({ w = w, valign = "top" }, { BoardUI.rect(bar, hOf(body), solid(e.color), floor(bar / 2)), space(px(10), 1), body })
end

local function noteBlock(note, w, max_lines)
    local nw = w - 2 * px(10) - px(16) - px(8)
    local lines = math.max(1, math.min(max_lines, TextPages.linesNeeded(note, { s = 14 }, nw)))
    local inner = hstack({ w = w - 2 * px(10), gap = px(8), valign = "top" }, {
        icon("pen-line", px(16), { sw = 2.25 }),
        text(note, { s = 14, w = nw, lines = lines, data = true, bg = INK.ge }),
    })
    return BoardUI.box({ w = w, h = hOf(inner) + 2 * px(8), radius = px(8), bg = INK.ge },
        vstack({ w = w, pad = { px(8), px(10), px(8), px(10) } }, { inner }))
end

-- Where and when, the page on the right.
local function metaLine(e, w)
    local parts = {}
    if e.chapter and e.kind ~= "bookmark" then parts[#parts + 1] = e.chapter end
    if e.day then parts[#parts + 1] = e.day end
    local page = text(e.page, { s = 12, b = true, col = INK.g3, data = true })
    local left = text(table.concat(parts, " · "), { s = 12, col = INK.g4, w = math.max(px(20), w - wOf(page) - px(12)), data = true })
    return hstack({ w = w }, { left, flex(px(12)), page })
end

function Bookmarks.itemWidget(e, w, index_in_view)
    local items = { metaLine(e, w), space(nil, px(6)), quoteBlock(e, w, QUOTE_LINES) }
    if e.note and e.kind ~= "bookmark" then
        items[#items + 1] = space(nil, px(6))
        items[#items + 1] = noteBlock(e.note, w, NOTE_LINES)
    end
    local block = vstack({ w = w, pad = { px(10), 0, px(10), 0 } }, items)
    return BoardUI.hit(block, { kind = "item", at = index_in_view })
end

-- --------------------------------------------------------------- filters
local function chipRow(page, w)
    local counts = Bookmarks.counts(page.entries, page.state)
    local kinds = {
        { nil, _("All"), counts.all }, { "highlight", _("Highlights"), counts.highlight },
        { "bookmark", _("Bookmarks"), counts.bookmark }, { "note", _("Notes"), counts.note },
    }
    local gap = px(6)
    local cw = floor((w - 3 * gap) / 4)
    local h = px(36)
    local cells = {}
    for i, k in ipairs(kinds) do
        local on = page.state.kind == k[1]
        local b = math.max(1, px(1.25))
        local label = text(k[2] .. " " .. k[3], { s = 13, b = true, col = on and INK.white or INK.black, w = cw - 2 * px(8), align = "center" })
        local box = BoardUI.box({ w = cw, h = h, radius = px(10), border = on and 0 or b, border_col = INK.g6, bg = on and INK.black or INK.white },
            hstack({ w = cw - 2 * (on and 0 or b), h = h - 2 * (on and 0 or b) }, { flex(0), label, flex(0) }))
        cells[i] = BoardUI.hit(box, { kind = "type", value = k[1] or false })
    end
    return hstack({ w = w, gap = gap }, cells)
end

local function lookRows(page, w)
    local ui = page.ui
    local styles, colors = {}, {}
    pcall(function() styles = ui.highlight:getHighlightStyles() end)
    pcall(function() colors = ui.highlight.highlight_colors end)
    local sample_color = HL().palette.hex(page.state.color or "yellow")
    local sgap = px(10)
    local sw_ = math.min(px(64), floor((w - (#styles - 1) * sgap) / math.max(1, #styles)))
    local sh_ = px(40)
    local style_cells = {}
    for _i, style in ipairs(styles) do
        local id = style[2]
        local on = page.state.drawer == id
        local ring = on and math.max(2, px(2.5)) or math.max(1, px(1.25))
        local sample = HL().styleSample(id, sw_ - 2 * ring - px(6), sh_ - 2 * ring - px(6), sample_color)
        local box = BoardUI.box({ w = sw_, h = sh_, radius = px(10), border = ring, border_col = on and INK.black or INK.g6, bg = INK.white },
            hstack({ w = sw_ - 2 * ring, h = sh_ - 2 * ring }, { flex(0), sample, flex(0) }))
        style_cells[#style_cells + 1] = BoardUI.hit(box, { kind = "drawer", value = id })
    end
    local cgap = px(8)
    local d = math.min(px(36), floor((w - (#colors - 1) * cgap) / math.max(1, #colors)))
    local color_cells = {}
    for _i, c in ipairs(colors) do
        local id = c[2]
        local on = page.state.color == id
        local ring = on and math.max(3, px(3)) or math.max(1, px(1.25))
        local dot = BoardUI.circle(d, { bg = HL().colorOf(HL().palette.hex(id)), border = ring, border_col = INK.black }, BoardUI.space(1, 1))
        color_cells[#color_cells + 1] = BoardUI.hit(dot, { kind = "color", value = id })
    end
    local search_row = false
    if page.state.search then
        -- The search in force, as a chip that clears it.
        local label = text(T(_("Search: “%1”"), page.state.search), { s = 13, b = true, data = true })
        local chip_w = wOf(label) + px(18) + px(16) + px(8) + px(14)
        local chip = BoardUI.box({ w = math.min(w, chip_w), h = px(34), radius = px(17), bg = INK.ge },
            hstack({ w = math.min(w, chip_w), h = px(34) }, { space(px(14), 1), icon("search", px(16), { sw = 2.25 }), space(px(8), 1), label, flex(0), icon("x", px(16), { sw = 2.5 }), space(px(10), 1) }))
        search_row = hstack({ w = w }, { flex(0), BoardUI.hit(chip, { kind = "clear-search" }), flex(0) })
    end
    return vstack({ w = w }, {
        hstack({ w = w }, { flex(0), hstack({ gap = sgap, valign = "center" }, style_cells), flex(0) }),
        space(nil, px(10)),
        hstack({ w = w }, { flex(0), hstack({ gap = cgap, valign = "center" }, color_cells), flex(0) }),
        search_row and space(nil, px(10)) or false,
        search_row,
    })
end

-- ------------------------------------------------------------------ build
local function iconButton(name, action, size)
    return BoardUI.hit(hstack({ w = px(44), h = px(44) }, { flex(0), icon(name, px(size or 22), { sw = 2.25 }), flex(0) }), action)
end

local function header(page, w)
    local menu = iconButton("menu", { kind = "native" })
    local sort = BoardUI.hit(hstack({ h = px(44), gap = px(4) }, { icon("arrow-up-down", px(18), { sw = 2.25 }),
        text(SORT_LABELS[page.state.sort](), { s = 13, b = true }) }), { kind = "sort" })
    local close = iconButton("x", { kind = "close" })
    local side = math.max(wOf(menu), wOf(sort) + wOf(close))
    local title = text(T(_("Bookmarks (%1)"), #page.entries), { s = 19, b = true })
    return hstack({ w = w, h = px(48) }, {
        menu, space(side - wOf(menu), 1), flex(px(8)), title, flex(px(8)),
        space(side - wOf(sort) - wOf(close), 1), sort, close,
    })
end

local function pager(page, w)
    local fh = px(44)
    local function step(name, kind, on)
        local c = hstack({ w = px(52), h = fh }, { flex(0), icon(name, px(22), { sw = 2.25, col = on and "black" or "gb" }), flex(0) })
        return on and BoardUI.hit(c, kind) or c
    end
    local i, n = page.index, page.count
    return hstack({ w = w, h = fh }, {
        flex(0), step("chevrons-left", { kind = "page", to = 1 }, i > 1), step("chevron-left", { kind = "page", delta = -1 }, i > 1),
        flex(0), text(i .. " / " .. n, { s = 14, b = true }), flex(0),
        step("chevron-right", { kind = "page", delta = 1 }, i < n), step("chevrons-right", { kind = "page", to = n }, i < n), flex(0),
    })
end

-- Splits the view into pages by measuring each item at width w.
local function paginate(page, w, body_h)
    local key = w .. "x" .. body_h
    if page.pages_key == key and page.pages then return end
    local heights = {}
    for i, e in ipairs(page.list) do
        local it = Bookmarks.itemWidget(e, w, i)
        heights[i] = math.min(hOf(it), body_h) + MenuUI.hair()
        if it.free then it:free() end
    end
    page.pages = TextPages.pack(heights, body_h, 0)
    page.pages_key = key
    page.count = #page.pages
    if page.want_item then
        for p, range in ipairs(page.pages) do
            if page.want_item >= range.first and page.want_item <= range.last then page.index = p; break end
        end
        page.want_item = nil
    end
    page.index = math.max(1, math.min(page.count, page.index or 1))
end

local function build(page, sw, sh)
    BoardMetrics.refresh()
    local mx = MenuUI.mx()
    local w = sw - 2 * mx
    local top, bottom = px(6), px(8)
    local head = header(page, w)
    local chips = chipRow(page, w)
    local looks = lookRows(page, w)
    local rule = BoardUI.rect(w, math.max(1, px(1)), INK.gc)
    local fixed = top + hOf(head) + px(4) + hOf(chips) + px(10) + hOf(looks) + px(12) + hOf(rule) + px(44) + bottom
    local body_h = sh - fixed - px(4)
    -- Collected in a sink so the measuring drafts are not tappable.
    BoardUI.collectHits(function() paginate(page, w, body_h) end)
    local body
    if #page.list == 0 then
        body = vstack({ w = w }, { space(nil, px(24)), text(_("Nothing matches these filters."), { s = 15, col = INK.g4, w = w, align = "center" }) })
    else
        local range = page.pages[page.index]
        local items = {}
        for i = range.first, range.last do
            if #items > 0 then items[#items + 1] = BoardUI.rect(w, MenuUI.hair(), INK.gc) end
            items[#items + 1] = Bookmarks.itemWidget(page.list[i], w, i)
        end
        body = vstack({ w = w }, items)
    end
    local items = {
        head, space(nil, px(4)), chips, space(nil, px(10)), looks, space(nil, px(12)), rule,
        vstack({ w = w, h = body_h + px(4) }, { body, flex(0) }),
        page.count > 1 and pager(page, w) or space(nil, px(44)),
    }
    return vstack({ w = sw, h = sh, pad = { top, mx, bottom, mx } }, items)
end

-- ----------------------------------------------------------------- jumps
function Bookmarks.goTo(ui, e)
    local item = e.item
    local ok = pcall(function() ui.bookmark:gotoBookmark(item.page, item.pos0) end)
    if ok then return end
    pcall(function() ui.link:addCurrentLocationToStack() end)
    if type(item.page) == "string" then
        ui:handleEvent(Event:new("GotoXPointer", item.page, item.pos0 or item.page))
    elseif item.page then
        ui:handleEvent(Event:new("GotoPage", item.page))
    end
end

-- -------------------------------------------------------------- the sheet
local function turnSheet(sheet, delta)
    local target = math.max(1, math.min(sheet.count or 1, sheet.index + delta))
    if target == sheet.index then return end
    sheet.index = target
    sheet:refresh(Device:hasEinkScreen() and "partial" or "ui")
end

-- The whole passage, paged inside the sheet when it is long.
function Bookmarks.openSheet(page, e)
    local ui = page.ui
    local titles = { highlight = _("Highlight"), note = _("Note"), bookmark = _("Bookmark") }
    local sub_parts = {}
    if e.chapter then sub_parts[#sub_parts + 1] = e.chapter end
    if e.page ~= "" then sub_parts[#sub_parts + 1] = T(_("page %1"), e.page) end
    if e.day then sub_parts[#sub_parts + 1] = e.day end
    return SheetUI.open{
        name = "aleph_bookmark_sheet",
        index = 1,
        build = function(sheet, sw, sh)
            return SheetUI.sheet(sheet, sw, sh, function(w, max_h)
                local head = SheetUI.titleRow(w, titles[e.kind] or _("Bookmark"), table.concat(sub_parts, " · "))
                local note = e.note and e.kind ~= "bookmark" and noteBlock(e.note, w, 8) or nil
                local pills = SheetUI.pillRow(w, {
                    { label = _("Edit"), icon = "pen-line", kind = "outline", action = { kind = "edit" } },
                    { label = _("Go to in book"), icon = "corner-up-right", action = { kind = "goto" } },
                })
                local gap = px(14)
                local items = { head }
                if e.kind == "bookmark" or not e.text then
                    items[#items + 1] = quoteBlock(e, w, 1)
                    sheet.count = 1
                else
                    -- The passage, a page of it at a time.
                    local bar = math.max(2, px(3))
                    local qw = w - bar - px(14)
                    local total = TextPages.linesNeeded(e.text, { s = 16, serif = true }, qw)
                    local fixed = hOf(head) + hOf(pills) + (note and (hOf(note) + gap) or 0) + 3 * gap
                    local per = math.max(3, floor((max_h - fixed) / lh(16)))
                    if total > per then per = math.max(3, floor((max_h - fixed - px(40) - gap) / lh(16))) end
                    sheet.count = math.max(1, math.ceil(total / per))
                    sheet.index = math.max(1, math.min(sheet.count, sheet.index))
                    local shown = math.min(per, total - (sheet.index - 1) * per)
                    local quote = TextBoxWidget:new{
                        text = e.text, face = BoardMetrics.face(16, "serif"), width = qw,
                        height = shown * lh(16), virtual_line_num = (sheet.index - 1) * per + 1,
                        fgcolor = INK.black, bgcolor = INK.white,
                    }
                    local rule_col = (e.drawer == "underscore" or e.drawer == "strikeout") and solid(e.color) or tint(e.color, 0.2)
                    items[#items + 1] = hstack({ w = w, valign = "top" }, { BoardUI.rect(bar, hOf(quote), rule_col, floor(bar / 2)), space(px(14), 1), quote })
                end
                if note then items[#items + 1] = note end
                if (sheet.count or 1) > 1 then items[#items + 1] = TextPages.pager(w, sheet.index, sheet.count) end
                items[#items + 1] = pills
                return items
            end, { pop_w = 560 })
        end,
        on_action = function(sheet, action)
            if action.kind == "page" then
                turnSheet(sheet, action.delta)
            elseif action.kind == "goto" then
                sheet:close()
                page:close()
                UIManager:nextTick(function() Bookmarks.goTo(ui, e) end)
            elseif action.kind == "edit" then
                -- KOReader's details: edit text, note, style, delete. The list
                -- closes, as what it shows may change.
                sheet:close()
                page:close()
                UIManager:nextTick(function() ui.bookmark:showBookmarkDetails(e.index) end)
            end
            return true
        end,
        on_swipe = function(sheet, ges)
            if ges.direction == "west" then turnSheet(sheet, 1) return true end
            if ges.direction == "east" then turnSheet(sheet, -1) return true end
            return false
        end,
        on_page_key = function(sheet, delta) turnSheet(sheet, delta) end,
    }
end

-- ------------------------------------------------------------------ page
local function refilter(page)
    page.list = Bookmarks.view(page.entries, page.state)
    page.pages, page.pages_key = nil, nil
    page.index = 1
end

local function turn(page, delta, to)
    local target = to or (page.index + delta)
    target = math.max(1, math.min(page.count or 1, target))
    if target == page.index then return end
    page.index = target
    page:refresh(Device:hasEinkScreen() and "partial" or "ui")
end

-- The item nearest the reading position, in page order.
local function nearest(page)
    if page.state.sort ~= "page" then return nil end
    local current
    pcall(function() current = page.ui:getCurrentPage() end)
    if not current then pcall(function() current = page.ui.document:getCurrentPage() end) end
    if not current then return nil end
    local best
    for i, e in ipairs(page.list) do
        if e.pageno and e.pageno <= current then best = i end
    end
    return best
end

-- ---------------------------------------------------------------- options
-- What KOReader's list offers behind its ≡, done on this page where it can:
-- search, current page, latest bookmark, export; KOReader's own list for
-- selecting several and the edited-text filter.
local function sectionBar(w, label)
    return vstack({ w = w }, {
        text(label:upper(), { s = 12, b = true, col = INK.g4, w = w }),
        space(nil, px(6)),
        BoardUI.rect(w, math.max(1, px(1.5)), INK.black),
    })
end

local function jumpTo(page, at)
    page.want_item = at
    page.pages, page.pages_key = nil, nil
    page:refresh()
end

local function exportNotes(ui)
    local exporter = ui.exporter
    if exporter then
        for _i, name in ipairs({ "onExportCurrentNotes", "exportCurrentNotes" }) do
            if type(exporter[name]) == "function" then
                local ok = pcall(exporter[name], exporter)
                if ok then return true end
            end
        end
    end
    return false
end

function Bookmarks.openOptions(page, native)
    local ui = page.ui
    local function row(iw, ic, label, sub, action)
        return MenuUI.row(iw, { icon = ic, label = label, sub = sub, chevron = true, h = sub and 60 or 50, action = action })
    end
    return SheetUI.open{
        name = "aleph_bookmark_options",
        build = function(sheet, sw, sh)
            return SheetUI.sheet(sheet, sw, sh, function(w)
                local iw = MenuUI.rowsIn(w)
                local find = {
                    row(iw, "search", _("Search bookmarks"), page.state.search and T(_("Now: “%1”"), page.state.search) or _("In the passages, notes and chapters"), { kind = "search" }),
                }
                if page.state.search then find[#find + 1] = row(iw, "x", _("Clear search"), nil, { kind = "clear" }) end
                return {
                    SheetUI.titleRow(w, _("Bookmarks"), T(_("%1 shown"), #page.list)),
                    vstack({ w = w }, { sectionBar(w, _("Find")), space(nil, px(10)), MenuUI.group(w, find) }),
                    vstack({ w = w }, { sectionBar(w, _("Go to")), space(nil, px(10)), MenuUI.group(w, {
                        row(iw, "file-text", _("Current page"), _("The bookmarks where you are reading"), { kind = "current" }),
                        row(iw, "clock", _("Latest bookmark"), _("The one made most recently"), { kind = "latest" }),
                    }) }),
                    vstack({ w = w }, { sectionBar(w, _("More")), space(nil, px(10)), MenuUI.group(w, {
                        row(iw, "download", _("Export annotations"), _("With KOReader's exporter"), { kind = "export" }),
                        row(iw, "list-checks", _("Select, edited text and more"), _("In KOReader's own list"), { kind = "native" }),
                    }) }),
                }
            end, { pop_w = 520 })
        end,
        on_action = function(sheet, action)
            local k = action.kind
            sheet:close()
            if k == "search" then
                UIManager:tickAfterNext(function()
                    local function apply(value)
                        value = value and value:gsub("^%s+", ""):gsub("%s+$", "") or ""
                        page.state.search = value ~= "" and value or nil
                        refilter(page)
                        page:refresh()
                    end
                    local ok = pcall(function()
                        require("aleph_input").prompt{ title = _("Search bookmarks"), text = page.state.search or "",
                            hint = _("A word in a passage or note"), ok_label = _("Search"), on_ok = apply }
                    end)
                    if not ok then
                        local InputDialog = require("ui/widget/inputdialog")
                        local dialog
                        dialog = InputDialog:new{ title = _("Search bookmarks"), input = page.state.search or "",
                            buttons = { { { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
                                { text = _("Search"), is_enter_default = true, callback = function() local v = dialog:getInputText(); UIManager:close(dialog); apply(v) end } } } }
                        UIManager:show(dialog)
                        dialog:onShowKeyboard()
                    end
                end)
            elseif k == "clear" then
                page.state.search = nil
                refilter(page); page:refresh()
            elseif k == "current" then
                if page.state.sort ~= "page" then page.state.sort = "page"; saveSort("page"); refilter(page) end
                jumpTo(page, nearest(page) or 1)
            elseif k == "latest" then
                local at, newest
                for i, e in ipairs(page.list) do
                    if e.datetime and (not newest or e.datetime > newest) then at, newest = i, e.datetime end
                end
                if at then
                    jumpTo(page, at)
                    UIManager:tickAfterNext(function() Bookmarks.openSheet(page, page.list[at]) end)
                end
            elseif k == "export" then
                if not exportNotes(ui) then
                    page:close()
                    if native then UIManager:nextTick(native) end
                end
            elseif k == "native" then
                page:close()
                if native then UIManager:nextTick(native) end
            end
            return true
        end,
    }
end

-- Opens the list; nil when the book has nothing (KOReader's own list then
-- says so).
function Bookmarks.open(bm, native, opts)
    local ui = bm.ui
    local entries = Bookmarks.entries(ui)
    if #entries == 0 then return nil end
    local sort = settings().bookmarks_sort
    local state = { sort = (sort == "newest" or sort == "oldest") and sort or "page", kind = opts and opts.kind or nil }
    local page
    page = MenuPage:new{
        name = "aleph_bookmarks",
        ui = ui,
        entries = entries,
        state = state,
        list = Bookmarks.view(entries, state),
        want_item = nil,
        index = 1,
        build = build,
        on_action = function(p, action)
            local k = action.kind
            if k == "page" then turn(p, action.delta or 0, action.to)
            elseif k == "item" then
                local e = p.list[action.at]
                if e then Bookmarks.openSheet(p, e) end
            elseif k == "type" then
                p.state.kind = action.value or nil
                refilter(p); p:refresh()
            elseif k == "drawer" then
                p.state.drawer = p.state.drawer ~= action.value and action.value or nil
                refilter(p); p:refresh()
            elseif k == "color" then
                p.state.color = p.state.color ~= action.value and action.value or nil
                refilter(p); p:refresh()
            elseif k == "sort" then
                local nxt = SORTS[1]
                for i, s in ipairs(SORTS) do if s == p.state.sort then nxt = SORTS[i % #SORTS + 1] end end
                p.state.sort = nxt
                saveSort(nxt)
                refilter(p)
                p.want_item = nearest(p)
                p:refresh()
            elseif k == "native" then
                Bookmarks.openOptions(p, native)
            elseif k == "clear-search" then
                p.state.search = nil
                refilter(p); p:refresh()
            elseif k == "native-list" then
                p:close()
                if native then UIManager:nextTick(native) end
            end
            return true
        end,
        on_hold = function(p, action)
            if action.kind == "item" and p.list[action.at] then
                local e = p.list[action.at]
                p:close()
                UIManager:nextTick(function() Bookmarks.goTo(ui, e) end)
                return true
            end
        end,
        on_swipe = function(p, ges)
            if ges.direction == "west" then turn(p, 1) return true end
            if ges.direction == "east" then turn(p, -1) return true end
            return false
        end,
        on_page_key = function(p, delta) turn(p, delta) end,
    }
    -- Opened on the page nearest the reading position (page order).
    page.want_item = nearest(page)
    if page.want_item then
        page.pages, page.pages_key = nil, nil
        page:rebuild()
    end
    UIManager:show(page, "ui")
    return page
end

local wanted = require("aleph_prefs").styleDialogs

-- KOReader's own list is still used while one of its filters, a search or a
-- selection is on (its own buttons reopen it that way).
local function nativeState(bm)
    return bm.match_table or bm.show_drawer_only or bm.show_color_only or bm.show_edited_only or bm.select_count
end

function Bookmarks.install()
    local ReaderBookmark = require("apps/reader/modules/readerbookmark")
    if ReaderBookmark._aleph_list then return end
    ReaderBookmark._aleph_list = true
    local original = ReaderBookmark.onShowBookmark
    ReaderBookmark._rb_native_show = original
    ReaderBookmark.onShowBookmark = function(self, ...)
        if not wanted() or nativeState(self) then return original(self, ...) end
        local args = { n = select("#", ...), ... }
        local unpack_ = table.unpack or unpack
        local function native() original(self, unpack_(args, 1, args.n)) end
        local ok, shown = pcall(Bookmarks.open, self, native)
        if ok and shown then return true end
        if not ok then require("logger").warn("Aleph: bookmarks page failed:", shown) end
        return original(self, ...)
    end
end

return Bookmarks
