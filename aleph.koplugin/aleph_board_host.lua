--[[--
The widget dashboard, installed over the catalog's dashboard view.

Draws the board for the current page: a header (greeting, date, device
status, search and menu), the packed grid of widget tiles, and a footer that
moves between the pages. Swipes and page-turn keys flip pages too.

Every tile is one InputContainer, so a change refreshes only that tile's
rectangle. Widgets record the regions a tap can land on while they paint, so
a tap goes to exactly what was drawn there: a cover, a stepper, a button. A
D-pad press is a tap at the focused tile's centre, which lands on the tile's
own action.
]]

local Device = require("device")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local NetworkMgr = require("ui/network/manager")
local VerticalSpan = require("ui/widget/verticalspan")
local T = require("ffi/util").template
local _ = require("gettext")

local BoardData = require("aleph_board_data")
local BoardEdit = require("aleph_board_edit")
local BoardLayout = require("aleph_board_layout")
local BoardMetrics = require("aleph_board_metrics")
local BoardStore = require("aleph_board_store")
local BoardUI = require("aleph_board_ui")
local BoardWidgets = require("aleph_board_widgets")
local CatalogWidgets = require("aleph_catalog_widgets")

local INK = BoardMetrics.INK
local px, lh1 = BoardMetrics.px, BoardMetrics.lh1
local text, runs, vstack, hstack, flex, space, icon = BoardUI.text, BoardUI.runs, BoardUI.vstack, BoardUI.hstack, BoardUI.flex, BoardUI.space, BoardUI.icon

local CatalogBoard = {}

-- --------------------------------------------------------------- tiles
local BoardTile = InputContainer:extend{
    item = nil,
    menu = nil,
    hits = nil,
}

function BoardTile:init()
    self.ges_events = {
        TapSelect = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } },
        HoldSelect = { GestureRange:new{ ges = "hold", range = function() return self.dimen end } },
    }
end

function BoardTile:actionAt(pos)
    if pos and self.hits then
        for index = #self.hits, 1, -1 do
            local area = self.hits[index]
            if area.dimen and pos:intersectWith(area.dimen) then return area.action end
        end
    end
    return self.item.action
end

function BoardTile:onTapSelect(_, ges)
    local action = self:actionAt(ges and ges.pos)
    if action then self.menu:boardRun(action, self) end
    return true
end

-- The action of a hit area drawn under `pos`, if any (no fallback).
function BoardTile:hitAt(pos)
    if pos and self.hits then
        for index = #self.hits, 1, -1 do
            local area = self.hits[index]
            if area.dimen and pos:intersectWith(area.dimen) then return area.action end
        end
    end
end

-- Holding a book's cover opens its page. Holding any other part of a widget
-- starts editing the board with that widget selected.
function BoardTile:onHoldSelect(_, ges)
    local menu = self.menu
    if not menu:boardEditing() then
        local pos = ges and ges.pos
        -- A plain region (a library cell) acts as one hit area; a board tile
        -- only counts the covers drawn inside it.
        local action = self.item.index == nil and self:actionAt(pos) or self:hitAt(pos)
        if action and menu.boardHoldBook and menu:boardHoldBook(action) then return true end
        if self.item.index then menu:boardEnterEdit(self.item.index) end
    end
    return true
end

-- A zero-height stand-in for KOReader's title bar while the board is shown:
-- the board draws its own header.
local TitleBarStub = VerticalSpan:extend{ width = 0 }
function TitleBarStub:getHeight() return 0 end
function TitleBarStub:setTitle() end
function TitleBarStub:setSubTitle() end
function TitleBarStub:setLeftIcon() end
function TitleBarStub:generateVerticalLayout() return {} end
function TitleBarStub:generateHorizontalLayout() return {} end

function CatalogBoard:boardTitleBar()
    return TitleBarStub:new{}
end

-- -------------------------------------------------------------- context
function CatalogBoard:boardHasLight()
    return Device:hasFrontlight()
end

function CatalogBoard:boardLandscape()
    local m = BoardMetrics.get()
    return m.w > m.h
end

function CatalogBoard:boardPages(cols)
    return BoardStore.pages(self.settings, cols, self:boardHasLight(), self:boardLandscape())
end

-- The names of the pages on screen, in order: a Stats or Library starter puts
-- a different page first.
function CatalogBoard:boardPageNames(cols)
    if self.board_edit then return BoardStore.pageNames(self.board_edit.pages) end
    return BoardStore.pageNames(self:boardPages(cols))
end

-- The page shown, kept on the dashboard context so going into a book and
-- back returns to the same page.
function CatalogBoard:boardPage()
    local context = self.current_context or {}
    local page = tonumber(context.board_page) or 1
    return math.max(1, math.min(BoardStore.PAGE_COUNT, page))
end

function CatalogBoard:boardHeader(d, w, mode, page_name)
    local box = px(44)
    local tap_pad = math.floor((box - px(24)) / 2)
    local function iconButton(name, action, nudge)
        local btn = hstack({ w = box, h = box }, { flex(0), icon(name, px(23), { sw = 2 }), flex(0) })
        return BoardUI.hit(btn, action), nudge
    end
    if mode == "edit" then
        local done_inner = hstack({ h = px(40) }, { space(px(20), 1), text(_("Done"), { s = 15, b = true, col = INK.white }), space(px(20), 1) })
        local done = BoardUI.hit(BoardUI.box({ w = done_inner:getSize().w, h = px(40), radius = px(20), bg = INK.black }, done_inner), { kind = "edit-done" })
        local tw = w - done:getSize().w - px(12)
        local edit_page = self.board_edit and self.board_edit.pages[self:boardPage()]
        local hidden = edit_page and edit_page.hidden and #edit_page.hidden or 0
        local hint = hidden > 0
            and T(_.ngettext("%1 widget does not fit at this interface size", "%1 widgets do not fit at this interface size", hidden), hidden)
            or _("Tap a widget to move, resize or remove it")
        return hstack({ w = w, h = px(64) }, {
            vstack({ w = tw }, {
                text(T(_("Edit %1"), page_name), { s = 22, b = true, w = tw }),
                text(hint, { s = 13, col = INK.g4, w = tw }),
            }),
            space(px(12), 1),
            done,
        })
    end
    local status = BoardUI.statusCluster(d)
    local search = iconButton("search", { kind = "search" })
    local menu = iconButton("menu", { kind = "menu" })
    local right_w = status:getSize().w + px(6) + 2 * box - tap_pad
    local tw = w - right_w
    local function fits(parts) return runs(parts, { s = 13 }):getSize().w <= tw end
    local parts
    if d.online or not d.stale then
        parts = { { t = d.date_long } }
    else
        -- Offline: the date gives way first, then when it was saved.
        local offline = { t = _("Offline"), b = true, col = INK.black }
        local saved = { t = d.updated and (", " .. T(_("saved %1"), d.updated)) or "" }
        parts = { { t = d.date_long .. " · " }, offline, saved }
        if not fits(parts) then parts = { offline, saved } end
        if not fits(parts) then parts = { offline } end
    end
    local sub = runs(parts, { s = 13, col = INK.g4, w = tw })
    -- A long greeting steps down to 18 before it is cut.
    local greet_s = BoardUI.fitSize(d.greeting, { s = 22, b = true }, tw, 18)
    return hstack({ w = w + tap_pad, h = px(64) }, {
        vstack({ w = tw }, { text(d.greeting, { s = greet_s, b = true, w = tw }), sub }),
        status,
        space(px(6), 1),
        search,
        menu,
    })
end

function CatalogBoard:boardFooter(w, page, mode)
    local fh = px(40)
    local names = self:boardPageNames(self._board_geometry and self._board_geometry.cols or BoardLayout.columnsFor(BoardMetrics.layoutW()))
    local function chev(name, enabled, delta)
        local btn = hstack({ w = px(44), h = fh }, { flex(0), icon(name, px(20), { sw = 2.5, col = enabled and "black" or "gb" }), flex(0) })
        return BoardUI.hit(btn, enabled and { kind = "page", delta = delta } or { kind = "noop" })
    end
    local dot_items = {}
    for index = 1, BoardStore.PAGE_COUNT do
        table.insert(dot_items, BoardUI.dot(px(7), index == page, { off = INK.g8 }))
    end
    local dots = hstack({ gap = px(6) }, dot_items)
    if mode == "edit" then
        local add_inner = hstack({ h = px(38), gap = px(8) }, { space(px(6), 1), icon("plus", px(17), { col = "white", sw = 2.75 }), text(_("Add widget"), { s = 14, b = true, col = INK.white }), space(px(10), 1) })
        local add = BoardUI.hit(BoardUI.box({ w = add_inner:getSize().w, h = px(38), radius = px(19), bg = INK.black }, add_inner), { kind = "edit-add" })
        local side = px(120)
        return hstack({ w = w, h = fh }, {
            hstack({ w = side, gap = px(8) }, { dots, text(names[page], { s = 13, b = true }), flex(0) }),
            flex(0), add, flex(0),
            BoardUI.hit(hstack({ w = side, gap = px(4) }, { flex(0), icon("layout-grid", px(16), { sw = 2.25 }), text(_("Pages"), { s = 13, b = true }) }), { kind = "edit-pages" }),
        })
    end
    return hstack({ w = w, h = fh }, {
        flex(0),
        chev("chevron-left", page > 1, -1), space(px(6), 1),
        dots, space(px(6), 1), space(px(4), 1), space(px(6), 1),
        text(names[page], { s = 13, b = true }), space(px(6), 1),
        chev("chevron-right", page < BoardStore.PAGE_COUNT, 1),
        flex(0),
    })
end

-- Default tap action for each widget type. Widgets that draw their own
-- buttons (Resume, steppers, covers) route those taps themselves.
function CatalogBoard:boardItemAction(item, d)
    local t = item.type
    local lead = d.continue_reading[1]
    local tap_resumes = self.settings.catalog_dashboard_tap_resumes ~= false
    if t == "hero" or t == "forecast" then
        if lead then return { kind = "book", book = lead, resume = tap_resumes, list = { label = _("Continue reading"), books = d.continue_reading } } end
        return { kind = "books", params = { sort = "title" }, title = _("All books") }
    elseif t == "also" then
        return { kind = "books", params = { sort = "recently_read", readStatus = "reading" }, title = _("In progress") }
    elseif t == "highlight" and d.highlight then
        return { kind = "highlight", highlight = d.highlight }
    elseif t == "shelf" then
        local source = item.props and item.props.source
        return { kind = "shelf", source = source, props = item.props }
    elseif t == "link" then
        return { kind = "link", link = item.props and item.props.link }
    elseif t == "yearago" and d.year_ago and d.year_ago.book then
        return { kind = "detail", book_id = d.year_ago.book.id }
    elseif t == "word" and d.word then
        return { kind = "lookup", word = d.word.word }
    elseif t == "chapters" and lead then
        return { kind = "book", book = lead, resume = tap_resumes, list = { label = _("Continue reading"), books = d.continue_reading } }
    elseif t == "silverfish" then
        return { kind = "silverfish" }
    elseif t == "streak" then
        -- Reading insights (readinginsights.koplugin), when it is installed.
        return { kind = "insights", view = "streak" }
    elseif t == "heatmap" then
        return { kind = "insights", view = "habits" }
    elseif t == "goalpace" then
        -- The books that count toward the goal: those finished this year.
        return { kind = "shelf", source = "finished", props = { source = "finished" } }
    elseif t == "week" or t == "today" then
        -- Its popup has the yearly reading goal and today among all time.
        return { kind = "insights", view = "insights" }
    elseif t == "records" then
        return { kind = "insights", view = "records" }
    elseif t == "hours" then
        -- Reading habits has the time of day breakdown.
        return { kind = "insights", view = "habits" }
    elseif t == "calendar" then
        return { kind = "insights", view = "streak" }
    elseif t == "dust" then
        local dust = d.dust
        if dust and dust.book then return { kind = "detail", book_id = dust.book.id } end
    end
    return nil
end

function CatalogBoard:boardBuildTile(ctx, item, w, h, edit)
    local frame, hits = BoardUI.collectHits(function() return BoardWidgets.tile(ctx, item, w, h) end)
    return BoardTile:new{
        dimen = Geom:new{ w = w, h = h },
        item = item,
        menu = self,
        -- In edit mode a tap selects the widget, whatever is drawn under it.
        hits = not edit and hits or nil,
        CatalogWidgets.focusable(frame),
    }
end

-- A tappable region that is not a widget tile: the header, the footer, the
-- edit bar, a sheet.
function CatalogBoard:boardRegion(build, action)
    local widget, hits = BoardUI.collectHits(build)
    local size = widget:getSize()
    return BoardTile:new{
        dimen = Geom:new{ w = size.w, h = size.h },
        item = { action = action },
        menu = self,
        hits = hits,
        CatalogWidgets.focusable(widget),
    }
end

-- ---------------------------------------------------------- edit overlays
local SIZE_ORDER = { "S", "M", "L", "W", "XL" }
local SIZE_LABELS = { S = "S", M = "M", L = "L", W = function() return _("Wide") end, XL = "XL" }

local function sizeLabel(code)
    local l = SIZE_LABELS[code]
    return type(l) == "function" and l() or l
end

function CatalogBoard:boardEditBar(item, index, g)
    local bar_h = px(52)
    local function button(name, label, action)
        local inner = vstack({ align = "center" }, {
            icon(name, px(19), { col = "white", sw = 2.25 }),
            space(nil, px(2)),
            text(label, { s = 11, b = true, col = INK.white }),
        })
        return BoardUI.hit(hstack({ h = bar_h }, { space(px(10), 1), inner, space(px(10), 1) }), action)
    end
    local function divider()
        return BoardUI.rect(math.max(1, px(1)), px(30), INK.g5)
    end
    local entry = BoardEdit.entryFor(item)
    local current = BoardEdit.sizeCode(item, g.cols)
    local segs = { text(_("Size"), { s = 11, b = true, col = INK.gb }) }
    local offered = {}
    for _i, code in ipairs(entry and entry.sizes or { current }) do offered[code] = true end
    local seen_dims = {}
    for _i, code in ipairs(SIZE_ORDER) do
        local cw, rh = BoardLayout.sizeDims(code, g.cols)
        local dims = cw .. "x" .. rh
        if offered[code] and not seen_dims[dims] then
            seen_dims[dims] = true
            local on = cw == math.min(item.cw, g.cols) and rh == item.rh
            local label = text(sizeLabel(code), { s = 13, b = true, col = on and INK.black or INK.white })
            local w = math.max(px(30), label:getSize().w + 2 * px(6))
            local seg = BoardUI.box({ w = w, h = px(30), radius = px(6), bg = on and INK.white or nil, border = on and 0 or math.max(1, px(1)), border_col = INK.g8 },
                hstack({ w = w - (on and 0 or 2 * math.max(1, px(1))), h = px(30) - (on and 0 or 2 * math.max(1, px(1))) }, { flex(0), label, flex(0) }))
            table.insert(segs, BoardUI.hit(seg, { kind = "edit-size", code = code }))
        end
    end
    local inner = hstack({ h = bar_h, gap = px(2) }, {
        space(px(6) - px(2), 1),
        button("chevron-left", _("Earlier"), { kind = "edit-move", delta = -1 }),
        button("chevron-right", _("Later"), { kind = "edit-move", delta = 1 }),
        divider(),
        hstack({ h = bar_h, gap = px(5) }, { space(px(8) - px(5), 1), unpack(segs) }),
        space(px(8), 1),
        divider(),
        button("layout-grid", _("Page"), { kind = "edit-page" }),
        button("x", _("Remove"), { kind = "edit-remove", index = index }),
        space(px(6) - px(2), 1),
    })
    local w = inner:getSize().w
    local ring = px(2)
    return BoardUI.overlay(w + 2 * ring, bar_h + 2 * ring, {
        { widget = BoardUI.rect(w + 2 * ring, bar_h + 2 * ring, INK.white, px(12) + ring) },
        { widget = BoardUI.box({ w = w, h = bar_h, radius = px(12), bg = INK.black }, inner), x = ring, y = ring },
    })
end

-- ------------------------------------------------------------ the sheet
function CatalogBoard:boardPreview(ctx, entry, box_w, box_h, g)
    -- Previews are drawn at the narrowest real column (132dp, a 6" panel),
    -- so a preview never shows a widget smaller than any board does.
    local unit = px(132)
    local cw, rh = BoardLayout.sizeDims(entry.sizes[1], 4)
    local pw = cw == 1 and unit or cw * unit + (cw - 1) * px(10)
    local ph = rh * unit + (rh - 1) * px(10)
    local scale = math.min(1, (box_h - px(16)) / ph, (box_w - px(20)) / pw)
    local sw, sh = math.floor(pw * scale + 0.5), math.floor(ph * scale + 0.5)
    local item = { type = entry.type, cw = cw, rh = rh, chrome = entry.chrome or "line", props = entry.props }
    local key = "preview:" .. entry.type .. ":" .. tostring(entry.props and (entry.props.source or entry.props.link or entry.props.animal) or "") .. ":" .. pw .. "x" .. ph .. ":" .. sw
    local shot = BoardUI.snapshot(key, pw, ph, sw, sh, function()
        return BoardWidgets.tile({ d = ctx.d, tiles = "outline", colour = ctx.colour, menu = self }, item, pw, ph)
    end)
    return BoardUI.box({ w = box_w, h = box_h, radius = px(12), bg = INK.ge }, hstack({ w = box_w, h = box_h }, { flex(0), shot, flex(0) }))
end

function CatalogBoard:boardSheet(ctx, g, screen_w, screen_h)
    local edit = self.board_edit
    local sheet_h = math.floor(screen_h * 0.7 + 0.5)
    local mx = g.mx
    local w = screen_w - 2 * mx
    local pad = px(18)
    local entries, new_count = {}, 0
    for _i, entry in ipairs(BoardEdit.LIBRARY) do
        if entry.new then new_count = new_count + 1 end
        if (edit.sheet_tab == "new" and entry.new) or entry.tab == edit.sheet_tab then table.insert(entries, entry) end
    end
    local tabs = {}
    for _i, tab in ipairs(BoardEdit.TABS) do
        local on = tab.id == edit.sheet_tab
        local label = text(tab.label(), { s = 14, b = on, col = on and INK.black or INK.g4 })
        table.insert(tabs, BoardUI.hit(vstack({ w = label:getSize().w, h = px(40) }, {
            flex(0), label, flex(0), on and BoardUI.rect(label:getSize().w, px(3), INK.black) or space(nil, px(3)),
        }), { kind = "sheet-tab", tab = tab.id }))
    end
    local tab_row = vstack({ w = w }, {
        hstack({ w = w, h = px(40), gap = px(BoardMetrics.layoutW() < 560 and 16 or 22), valign = "bottom" }, tabs),
        BoardUI.rect(w, math.max(1, px(1)), INK.gb),
    })
    local cols_n = BoardMetrics.layoutW() >= 700 and 3 or 2
    local gap = px(14)
    local card_w = math.floor((w - (cols_n - 1) * gap) / cols_n)
    local preview_h
    local stacked = false
    local function caption(entry)
        local chips = {}
        for _i, code in ipairs(entry.sizes) do
            local label = text(sizeLabel(code), { s = 11, b = true, col = INK.g3 })
            table.insert(chips, BoardUI.box({ w = label:getSize().w + 2 * px(5), h = label:getSize().h, radius = px(4), border = math.max(1, px(1)), border_col = INK.g8 },
                hstack({ w = label:getSize().w + 2 * px(5) - 2 * math.max(1, px(1)) }, { flex(0), label, flex(0) })))
        end
        local chip_row = hstack({ gap = px(4) }, chips)
        local name_w = card_w - chip_row:getSize().w - px(6)
        local name_s = BoardUI.fitSize(entry.name(), { s = 14, b = true }, name_w, 12)
        -- A name that does not fit beside its sizes even at 12 takes the
        -- line, with the sizes under it, and then so does every name so the
        -- cards line up on every tab.
        if text(entry.name(), { s = name_s, b = true }):getSize().w > name_w then stacked = true end
        local name_row
        if not stacked then
            name_row = BoardUI.spread(card_w, text(entry.name(), { s = name_s, b = true, w = name_w }), chip_row)
        else
            local s2 = BoardUI.fitSize(entry.name(), { s = 14, b = true }, card_w, 11)
            name_row = vstack({ w = card_w }, { text(entry.name(), { s = s2, b = true, w = card_w }), space(nil, px(4)), chip_row })
        end
        return vstack({ w = card_w }, {
            space(nil, px(6)),
            name_row,
            space(nil, px(6)),
            text(entry.desc(), { s = 12, col = INK.g4, lines = 2, w = card_w }),
        })
    end
    local function card(entry)
        return BoardUI.hit(vstack({ w = card_w }, {
            self:boardPreview(ctx, entry, card_w, preview_h, g),
            caption(entry),
        }), { kind = "sheet-add", entry = entry })
    end
    local head_h = pad + lh1(20) + lh1(13) + px(10) + px(40) + math.max(1, px(1)) + px(16)
    local pager_h = px(52)
    -- Rows are as tall as their tallest caption (a description can take two
    -- lines). Every widget's caption is measured, not just this tab's, so
    -- each tab keeps the same rows and cards per page.
    local text_h = 0
    local measured = BoardEdit.LIBRARY
    for _i, entry in ipairs(measured) do
        local sample = caption(entry)
        if sample.free then sample:free() end
    end
    for _i, entry in ipairs(measured) do
        local sample = caption(entry)
        text_h = math.max(text_h, sample:getSize().h)
        if sample.free then sample:free() end
    end
    local vgap = px(16)
    -- As many rows as fit with previews at least 80dp tall, the previews then
    -- grown to fill the sheet (up to a little taller than a card is wide), so
    -- a larger interface size leaves no band of empty sheet under the last
    -- row.
    local grid_h = sheet_h - head_h - pager_h
    local rows_fit = math.max(1, math.floor((grid_h + vgap) / (px(80) + text_h + vgap)))
    local preview_max = math.max(px(150), math.floor(card_w * 1.2))
    preview_h = math.max(px(64), math.min(preview_max, math.floor((grid_h + vgap) / rows_fit - vgap - text_h)))
    local per_page = rows_fit * cols_n
    local pages = math.max(1, math.ceil(#entries / per_page))
    edit.sheet_page = math.min(edit.sheet_page or 1, pages)
    local first = (edit.sheet_page - 1) * per_page + 1
    local grid_rows = {}
    for r = 0, rows_fit - 1 do
        local cards = {}
        for c = 0, cols_n - 1 do
            local entry = entries[first + r * cols_n + c]
            if entry then table.insert(cards, card(entry)) end
        end
        if #cards > 0 then
            if #grid_rows > 0 then table.insert(grid_rows, space(nil, vgap)) end
            table.insert(grid_rows, hstack({ gap = gap, valign = "top" }, cards))
        end
    end
    local function chev(name, enabled, delta)
        local b = hstack({ w = px(44), h = pager_h }, { flex(0), icon(name, px(22), { sw = 2.5, col = enabled and "black" or "gb" }), flex(0) })
        return BoardUI.hit(b, enabled and { kind = "sheet-page", delta = delta } or { kind = "noop" })
    end
    local pager = vstack({ w = w }, {
        BoardUI.rect(w, math.max(1, px(0.75)), INK.gc),
        hstack({ w = w, h = pager_h - math.max(1, px(0.75)), gap = px(18) }, {
            flex(0), chev("chevron-left", edit.sheet_page > 1, -1),
            text(T(_("%1 of %2"), edit.sheet_page, pages), { s = 13, b = true }),
            chev("chevron-right", edit.sheet_page < pages, 1), flex(0),
        }),
    })
    local close = BoardUI.hit(BoardUI.circle(px(40), { border = math.max(1, px(1.5)), bg = INK.white }, icon("x", px(20), { sw = 2.5 })), { kind = "sheet-close" })
    local title = vstack({}, {
        text(_("Add a widget"), { s = 20, b = true }),
        text(T(_("%1 widgets · %2 new"), #BoardEdit.LIBRARY, new_count), { s = 13, col = INK.g4 }),
    })
    local body = vstack({ w = screen_w, h = sheet_h, pad = { pad, mx, 0, mx } }, {
        BoardUI.spread(w, title, close),
        space(nil, px(10)),
        tab_row,
        space(nil, px(16)),
        vstack({ w = w }, grid_rows),
        flex(0),
        pager,
    })
    local line = math.max(1, px(2))
    local r = px(18)
    return BoardUI.overlay(screen_w, sheet_h + line, {
        { widget = BoardUI.rect(screen_w, sheet_h + line + r, INK.black, r) },
        { widget = BoardUI.rect(screen_w, sheet_h + r, INK.white, r), y = line },
        { widget = body, y = line },
    })
end

-- ----------------------------------------------------------- first run
function CatalogBoard:boardBuildScreen(ctx, g, page, screen_w, screen_h, opts)
    opts = opts or {}
    local d = ctx.d
    local edit = not opts.snapshot and self.board_edit or nil
    local packed
    if edit then
        packed = BoardLayout.pack(edit.pages[page].items, g.cols)
        packed.row_h = math.min(g.max_row, BoardLayout.rowHeight(g, packed.rows))
        packed.grid_h = packed.rows * packed.row_h + math.max(0, packed.rows - 1) * g.gap
    else
        local pages
        if opts.preset then
            pages = BoardStore.starterPages(g.cols, opts.preset, self:boardHasLight(), self:boardLandscape())
        else
            pages = self:boardPages(g.cols)
        end
        packed = BoardLayout.fitPage(g, pages[page].base, pages[page].extras)
    end
    local tiles = {}
    local layers = {}
    local rows = {}
    local selected
    for index, item in ipairs(packed.placed) do
        local tw = BoardLayout.spanWidth(g, item.x, item.cw)
        local th = item.rh * packed.row_h + (item.rh - 1) * g.gap
        local x, y = BoardLayout.cellX(g, item.x), item.y * (packed.row_h + g.gap)
        local placed = {}
        for k, v in pairs(item) do placed[k] = v end
        placed.index = index
        placed.action = edit and { kind = "edit-select", index = index } or self:boardItemAction(item, d)
        local tile = self:boardBuildTile(ctx, placed, tw, th, edit ~= nil)
        if edit and edit.selected == index then
            -- The selection ring: white, then black, outside the tile.
            local r = px(12)
            table.insert(layers, { widget = BoardUI.rect(tw + 2 * px(6), th + 2 * px(6), INK.black, r + px(6)), x = x - px(6), y = y - px(6) })
            table.insert(layers, { widget = BoardUI.rect(tw + 2 * px(3), th + 2 * px(3), INK.white, r + px(3)), x = x - px(3), y = y - px(3) })
            selected = { item = placed, index = index, x = x, y = y, w = tw, h = th }
        end
        table.insert(tiles, { tile = tile, item = placed, x = x, y = y, w = tw, h = th })
        table.insert(layers, { widget = tile, x = x, y = y })
        rows[item.y + 1] = rows[item.y + 1] or {}
        table.insert(rows[item.y + 1], tile)
    end
    if edit then
        local badge = px(26)
        for _i, entry in ipairs(tiles) do
            local b = self:boardRegion(function()
                return BoardUI.circle(badge, { border = math.max(1, px(1.5)), bg = INK.white }, icon("x", px(15), { sw = 3 }))
            end, { kind = "edit-remove", index = entry.item.index })
            table.insert(layers, { widget = b, x = entry.x - px(7), y = entry.y - px(7) })
        end
        -- The Add widget sheet covers the bottom of the board; the bar for the
        -- selected widget comes back when it closes.
        if selected and not edit.sheet then
            local bar = self:boardRegion(function() return self:boardEditBar(selected.item, selected.index, g) end, { kind = "noop" })
            local bw, bh = bar:getSize().w, bar:getSize().h
            local left = math.max(0, math.min(g.w - bw, selected.x + math.floor((selected.w - bw) / 2)))
            local top = BoardLayout.editBarTop(selected.y, selected.h, bh, px(12), g.avail)
            packed.grid_h = math.max(packed.grid_h, top + bh)
            table.insert(layers, { widget = bar, x = left, y = top })
        end
    end
    local grid = BoardUI.overlay(g.w, packed.grid_h, layers)
    local mode = edit and "edit" or "normal"
    local header = self:boardRegion(function() return self:boardHeader(d, g.w, mode, self:boardPageNames(g.cols)[page]) end)
    local footer = self:boardRegion(function() return self:boardFooter(g.w, page, mode) end)
    local board = vstack({ w = screen_w, h = screen_h, pad = { g.top, g.mx, g.bottom, g.mx } }, {
        header,
        space(nil, g.header_gap),
        grid,
        flex(g.footer_gap),
        footer,
    })
    if not opts.snapshot then
        self._board_tiles = tiles
        self._board_header = header
        self._board_origin = { x = g.mx, y = g.top + g.header_h + g.header_gap }
    end
    return board, rows, packed
end

function CatalogBoard:boardAdjustLight(what, delta)
    if not BoardData.adjustLight(what, delta) then return end
    for _i, entry in ipairs(self._board_tiles or {}) do
        if entry.item.type == "light" then self:boardRefreshTile(entry) end
    end
end

function CatalogBoard:boardToggleWifi()
    if NetworkMgr:isWifiOn() then
        NetworkMgr:toggleWifiOff(function() self:updateItems(nil, true) end)
    else
        NetworkMgr:toggleWifiOn(function() self:updateItems(nil, true) end)
    end
end

-- ------------------------------------------------------------ sources
-- The shelves and names the board's pages show, so a refresh fetches only
-- what some widget will draw.

function CatalogBoard.install(Catalog)
 BoardEdit.install(Catalog)
 for name, fn in pairs(CatalogBoard) do
  if name ~= "install" and type(fn) == "function" then Catalog[name] = fn end
 end
end
return CatalogBoard
