-- Aleph modification, 2026-11-09: the table of contents as a Reading
-- Board panel.
--[[--
The table of contents in the board's style, laid out like the library's
Genre picker: a panel over the page (the page stays in view around it, dimmed),
"Back" on the left and the title in the middle, the chapters in outlined cards
with hairlines between them (two columns when every title fits), the page
number on the right of each as a plain number, and "‹ 1 / 7 ›" under the cards.

  tap a chapter          go there (Back in the reader returns, as KOReader's does)
  swipe, page keys, ‹ ›  turn the pages of the list
  ≡ (top right)          KOReader's own table of contents, with its settings,
                         expanding and holding entries

The list opens on the page with the current chapter, which is bold. Nested
chapters are indented. If anything fails, KOReader's own table of contents
opens instead.
]]

local Device = require("device")
local Event = require("ui/event")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local BoardMetrics = require("aleph_board_metrics")
local BoardUI = require("aleph_board_ui")
local MenuPage = require("aleph_menu_page")
local MenuUI = require("aleph_menu_ui")

local INK = BoardMetrics.INK
local px = BoardMetrics.px
local text, vstack, hstack, space, flex, icon = BoardUI.text, BoardUI.vstack, BoardUI.hstack, BoardUI.space, BoardUI.flex, BoardUI.icon

local Toc = {}

local ROW_H = 46
local MAX_DEPTH = 4

local function wOf(widget) return widget:getSize().w end
local function hOf(widget) return widget:getSize().h end

local function widthOf(str, o)
    local t = text(str, o)
    local w = wOf(t)
    if t.free then t:free() end
    return w
end

-- ----------------------------------------------------------------- data
local function currentPage(ui)
    local page
    pcall(function() page = ui.toc and ui.toc.pageno end)
    if not page then pcall(function() page = ui:getCurrentPage() end) end
    if not page then pcall(function() page = ui.document:getCurrentPage() end) end
    return page
end

-- A chapter's page as the reader names it: the book's own page labels when
-- KOReader is set to show them, else the page number. Only the number.
local function pageLabel(ui, item)
    local label
    pcall(function()
        if ui.pagemap and ui.pagemap:wantsPageLabels() then
            if item.xpointer then
                label = ui.pagemap:getXPointerPageLabel(item.xpointer, true)
            else
                label = ui.pagemap:getPageLabel(item.page, true)
            end
        end
    end)
    if type(label) == "string" and label ~= "" then return label end
    return item.page and tostring(item.page) or ""
end

-- The entries, each { title, depth, page, label, xpointer }, and the index of
-- the current chapter.
function Toc.entries(ui)
    local toc = ui.toc
    pcall(toc.fillToc, toc)
    local items = {}
    for _i, item in ipairs(toc.toc or {}) do
        local title = tostring(item.title or ""):gsub("^%s+", ""):gsub("%s+$", "")
        items[#items + 1] = {
            title = title ~= "" and title or _("Untitled"),
            depth = math.max(1, math.min(MAX_DEPTH, tonumber(item.depth) or 1)),
            page = item.page, xpointer = item.xpointer,
            label = pageLabel(ui, item),
        }
    end
    local current
    local page = currentPage(ui)
    if page then pcall(function() current = toc:getTocIndexByPage(page) end) end
    return items, current
end

-- --------------------------------------------------------------- layout
local function rowWidget(entry, rw, label_w, on, index)
    local indent = px(16) * (entry.depth - 1)
    local num = text(entry.label, { s = 14, b = on, col = on and INK.black or INK.g4, data = true })
    local title = text(entry.title, { s = 15, b = on, w = math.max(px(40), label_w - indent), data = true })
    local row = hstack({ w = rw, h = px(ROW_H) }, {
        indent > 0 and space(indent, 1) or false, title, flex(px(12)), num,
    })
    return BoardUI.hit(row, { kind = "go", index = index })
end

local function card(page, from, to, card_w)
    local rw = MenuUI.rowsIn(card_w)
    local num_w = page.num_w
    local label_w = rw - num_w - px(12)
    local children = {}
    for i = from, to do
        if #children > 0 then table.insert(children, BoardUI.rect(rw, MenuUI.hair(), INK.gb)) end
        table.insert(children, rowWidget(page.entries[i], rw, label_w, i == page.current, i))
    end
    return MenuUI.card(card_w, children)
end

local function step(name, delta, on)
    local c = hstack({ w = px(52), h = px(44) }, { flex(0), icon(name, px(22), { sw = 2.25, col = on and "black" or "gb" }), flex(0) })
    return on and BoardUI.hit(c, { kind = "page", delta = delta }) or c
end

-- Works out once per screen size how many rows fit, whether two columns do,
-- and how many pages that makes.
local function plan(page, inner, avail)
    local key = inner .. "x" .. avail
    if page.plan_key == key then return end
    page.plan_key = key
    local n = #page.entries
    local row = px(ROW_H) + MenuUI.hair()
    local per_col_all = math.max(3, math.floor((avail - 2 * MenuUI.line()) / row))
    -- With a pager under the cards there is a little less room.
    local per_col = n <= per_col_all and n or math.max(3, math.floor((avail - px(52) - 2 * MenuUI.line()) / row))
    -- The widest page number decides the number column.
    local num_w = 0
    for _i, e in ipairs(page.entries) do num_w = math.max(num_w, widthOf(e.label, { s = 14, b = true })) end
    page.num_w = num_w
    -- Two columns when the list is longer than one and every title fits its
    -- column on one line.
    local gap = px(12)
    local col_w = math.floor((inner - gap) / 2)
    local two = false
    if n > per_col_all and col_w >= px(220) then
        local room = MenuUI.rowsIn(col_w) - num_w - px(12)
        two = true
        for _i, e in ipairs(page.entries) do
            if widthOf(e.title, { s = 15, b = true }) + px(16) * (e.depth - 1) > room then two = false; break end
        end
    end
    if two and n <= 2 * per_col_all then per_col = per_col_all end
    page.two = two
    page.per_col = per_col
    page.per_page = (two and 2 or 1) * per_col
    page.pages = math.max(1, math.ceil(n / page.per_page))
    -- First time: the page with the current chapter.
    if not page.index then
        page.index = page.current and math.ceil(page.current / page.per_page) or 1
    end
    page.index = math.max(1, math.min(page.pages, page.index))
end

local function build(page, sw, sh)
    BoardMetrics.refresh()
    local mx = math.max(px(16), MenuUI.mx())
    local margin_y = px(20)
    local pw = math.min(sw - 2 * mx, px(760))
    local pad = px(16)
    local line = math.max(1, px(1.5))
    local inner = pw - 2 * pad
    local back = BoardUI.hit(hstack({ h = px(44), gap = px(2) }, { icon("chevron-left", px(22), { sw = 2.25 }), text(_("Back"), { s = 14, b = true }) }), { kind = "close" })
    local native = BoardUI.hit(hstack({ w = px(44), h = px(44) }, { flex(0), icon("menu", px(22), { sw = 2 }), flex(0) }), { kind = "native" })
    local side = math.max(wOf(back), wOf(native))
    local head = hstack({ w = inner, h = px(44) }, {
        back, space(side - wOf(back), 1), flex(px(8)), text(page.title, { s = 18, b = true, w = math.min(widthOf(page.title, { s = 18, b = true }), inner - 2 * side - px(16)) }),
        flex(px(8)), space(side - wOf(native), 1), native,
    })
    local gap = px(12)
    local avail = sh - 2 * margin_y - 2 * pad - hOf(head) - gap
    plan(page, inner, avail)
    local first = (page.index - 1) * page.per_page + 1
    local last = math.min(#page.entries, page.index * page.per_page)
    local items = { head, space(nil, gap) }
    if page.two and last - first + 1 > page.per_col then
        local col_w = math.floor((inner - gap) / 2)
        table.insert(items, hstack({ w = inner, gap = gap, valign = "top" }, {
            card(page, first, first + page.per_col - 1, col_w),
            card(page, first + page.per_col, last, inner - gap - col_w),
        }))
    else
        table.insert(items, card(page, first, last, inner))
    end
    if page.pages > 1 then
        local mid = text(page.index .. " / " .. page.pages, { s = 14, b = true })
        table.insert(items, space(nil, px(8)))
        table.insert(items, hstack({ w = inner, h = px(44) }, { step("chevron-left", -1, page.index > 1), flex(0), mid, flex(0), step("chevron-right", 1, page.index < page.pages) }))
    end
    local body = vstack({ w = inner }, items)
    local ph = hOf(body) + 2 * pad
    local x, y = math.floor((sw - pw) / 2), margin_y
    local content = vstack({ w = pw - 2 * line, pad = { pad - line, pad - line, pad - line, pad - line } }, { body })
    local panel = BoardUI.box({ w = pw, h = ph, radius = px(16), border = line, border_col = INK.black, bg = INK.white }, content)
    page.panel_rect = require("ui/geometry"):new{ x = x, y = y, w = pw, h = ph }
    return BoardUI.overlay(sw, sh, { { widget = panel, x = x, y = y } })
end

local function turn(page, delta)
    local target = math.max(1, math.min(page.pages or 1, page.index + delta))
    if target == page.index then return end
    page.index = target
    page:refresh(Device:hasEinkScreen() and "partial" or "ui")
end

-- Goes to a chapter the way KOReader's table of contents does.
local function go(ui, entry)
    pcall(function() ui.link:addCurrentLocationToStack() end)
    if entry.xpointer then
        ui:handleEvent(Event:new("GotoXPointer", entry.xpointer, entry.xpointer))
    else
        ui:handleEvent(Event:new("GotoPage", entry.page))
    end
end

-- Opens the panel for the reader's table of contents; returns nil when the
-- book has none (KOReader's own then says so).
function Toc.open(reader_toc, native)
    local ui = reader_toc.ui
    local entries, current = Toc.entries(ui)
    if #entries == 0 then return nil end
    local page
    page = MenuPage:new{
        name = "aleph_toc",
        backdrop = true,
        dismiss_outside = true,
        build = build,
        title = _("Table of contents"),
        entries = entries,
        current = current,
        on_action = function(p, action)
            if action.kind == "go" then
                local entry = p.entries[action.index]
                p:close()
                if entry then UIManager:nextTick(function() go(ui, entry) end) end
            elseif action.kind == "page" then
                turn(p, action.delta)
            elseif action.kind == "native" then
                p:close()
                if native then UIManager:nextTick(native) end
            end
            return true
        end,
        on_swipe = function(p, ges)
            if ges.direction == "west" then turn(p, 1) return true end
            if ges.direction == "east" then turn(p, -1) return true end
            return false
        end,
        on_page_key = function(p, delta) turn(p, delta) end,
    }
    UIManager:show(page, "ui")
    return page
end

local wanted = require("aleph_prefs").styleDialogs

-- Replaces ReaderToc:onShowToc with the panel; the original (already styled
-- by aleph_menu_skin) stays behind the ≡ button and as the fallback.
function Toc.install()
    local ReaderToc = require("apps/reader/modules/readertoc")
    if ReaderToc._aleph_toc then return end
    ReaderToc._aleph_toc = true
    local original = ReaderToc.onShowToc
    ReaderToc.onShowToc = function(self, ...)
        if not wanted() then return original(self, ...) end
        local args = { n = select("#", ...), ... }
        local unpack_ = table.unpack or unpack
        local function native() original(self, unpack_(args, 1, args.n)) end
        local ok, shown = pcall(Toc.open, self, native)
        if ok and shown then return true end
        if not ok then require("logger").warn("Aleph: table of contents panel failed:", shown) end
        return original(self, ...)
    end
end

return Toc
