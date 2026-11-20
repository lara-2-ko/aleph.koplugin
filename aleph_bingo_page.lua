-- Aleph modification, 2026-11-18: the Reading bingo card, full screen.
--[[--
Opened from the Reading bingo widget. No card yet: a new one of 12 or 24
books. A card: every square with its challenge, filled ones with the book
(its cover when there is one), bingo lines framed heavier; a tap on a square
opens what can be done with it:
  empty    Choose a book… (the finished books not on the card), Another
           challenge (one of the same kind), Write my own…
  filled   Choose another book…, Empty this square
And at the foot, New card.

BingoPage.ask(book): the question after a book is finished that no rule or
Calibre placed (aleph_bingo.lua, onFinished): which open square, if any.
]]

local Geom = require("ui/geometry")
local UIManager = require("ui/uimanager")
local _ = require("aleph_gettext")
local T = require("ffi/util").template

local Bingo = require("aleph_bingo")
local BoardMetrics = require("aleph_board_metrics")
local BoardUI = require("aleph_board_ui")
local MenuPage = require("aleph_menu_page")
local MenuUI = require("aleph_menu_ui")
local SheetUI = require("aleph_sheet_ui")

local INK = BoardMetrics.INK
local px = BoardMetrics.px
local text, vstack, hstack, space, flex, icon = BoardUI.text, BoardUI.vstack, BoardUI.hstack, BoardUI.space, BoardUI.flex, BoardUI.icon
local floor = math.floor

local BingoPage = {}

local function toast(str, glyph)
    pcall(function() require("aleph_toast").show(str, { icon = glyph or "grid-3x3", timeout = 3 }) end)
end

-- Home drawn again, when it is open, for the widget.
local function refreshHome()
    pcall(function()
        local board = require("pluginloader"):getPluginInstance("aleph")
        local browser = board and board.browser
        if browser and not browser.closed and browser.mode == "home" then browser:updateItems() end
    end)
end

local function library()
    local ok, lib = pcall(function() return require("aleph_local").shared() end)
    return ok and lib or nil
end

-- The library's entry for a path (its cover, its title), or nil.
function BingoPage.bookAt(path)
    local lib = library()
    if not lib or not path then return nil end
    for _i, b in ipairs(lib.books or {}) do if b.path == path then return b end end
    return nil
end

-- The finished books not on the card, the most recently finished first.
function BingoPage.candidates(card)
    local lib = library()
    local out = {}
    for _i, b in ipairs(lib and lib.books or {}) do
        if b.readStatus == "read" and not (card and Bingo.onCard(card, b.path)) then out[#out + 1] = b end
    end
    table.sort(out, function(a, b) return tostring(a.finishedOn or "") > tostring(b.finishedOn or "") end)
    return out
end

local function summary(card)
    local p = Bingo.progress(card)
    return T(_("%1/%2 read"), p.read, p.total) .. " · " .. T(_.ngettext("%1 bingo", "%1 bingos", p.bingos), p.bingos), p
end

-- ---------------------------------------------------------------- squares
-- One square, cw x ch: the challenge, or the book that filled it.
-- bold: the challenge in bold (the full page).
function BingoPage.cell(card, index, cw, ch, in_line, s, bold)
    local cell = card.cells[index]
    local border = math.max(1, px(in_line and 2.5 or 1))
    local r = px(6)
    local inner_w, inner_h = cw - 2 * border, ch - 2 * border
    local body
    if cell.free then
        body = vstack({ w = inner_w, h = inner_h, align = "center" }, {
            flex(0), icon("star", px(18), { sw = 2 }), space(nil, px(3)),
            text(_("Free space"), { s = s, b = true, w = inner_w - px(6), align = "center" }), flex(0),
        })
        return BoardUI.box({ w = cw, h = ch, radius = r, border = border, border_col = INK.black, bg = INK.ge }, body)
    end
    if cell.path then
        local book = BingoPage.bookAt(cell.path)
        local cover = book and require("aleph_local").cachedCover(book)
        local badge = BoardUI.circle(px(20), { bg = INK.black }, icon("check", px(12), { col = "white", sw = 3 }))
        local layers
        if cover then
            layers = { { widget = BoardUI.cover(book, inner_w, inner_h, { path = cover }) } }
        else
            layers = { { widget = BoardUI.box({ w = inner_w, h = inner_h, bg = INK.g3 }, vstack({ w = inner_w, h = inner_h, pad = px(5), align = "center" }, {
                flex(0), text(cell.title or "", { s = s, b = true, col = INK.white, bg = INK.g3, w = inner_w - px(10), lines = 3, align = "center", data = true }), flex(0),
            })) } }
        end
        layers[#layers + 1] = { widget = badge, x = inner_w - px(22), y = px(2) }
        return BoardUI.box({ w = cw, h = ch, radius = r, border = border, border_col = INK.black, bg = INK.white },
            BoardUI.overlay(inner_w, inner_h, layers))
    end
    local lines = math.max(1, math.min(5, floor((inner_h - px(8)) / BoardMetrics.lh(s))))
    body = vstack({ w = inner_w, h = inner_h, pad = px(4), align = "center" }, {
        flex(0), text(Bingo.text(cell), { s = s, b = bold, w = inner_w - px(8), lines = lines, align = "center", data = true }), flex(0),
    })
    return BoardUI.box({ w = cw, h = ch, radius = r, border = border, border_col = in_line and INK.black or INK.g8, bg = INK.white }, body)
end

-- The grid of squares, w wide and at most h high; taps when `tap`; the
-- challenges in bold when `bold`.
function BingoPage.grid(card, w, h, s, tap, bold)
    local cols, rows = Bingo.shape(card.size)
    local gap = px(6)
    local cw = floor((w - (cols - 1) * gap) / cols)
    local ch = math.min(floor(cw * 1.0), floor((h - (rows - 1) * gap) / rows))
    local p = Bingo.progress(card)
    local lines = {}
    for r = 1, rows do
        if r > 1 then lines[#lines + 1] = space(nil, gap) end
        local items = {}
        for c = 1, cols do
            local index = (r - 1) * cols + c
            local sq = BingoPage.cell(card, index, cw, ch, p.in_line[index], s, bold)
            items[#items + 1] = (tap and not card.cells[index].free) and BoardUI.hit(sq, { kind = "cell", index = index }) or sq
        end
        lines[#lines + 1] = hstack({ gap = gap }, items)
    end
    return vstack({ w = w, align = "center" }, lines)
end

-- ------------------------------------------------------------------ page
local function build(page, sw, sh)
    local mx = MenuUI.mx()
    local w = sw - 2 * mx
    local top, bottom = px(6), px(12)
    local card = Bingo.card()
    local items
    if not card then
        local header = MenuUI.pageHeader(w, _("Reading bingo"), { sub = _("No card yet") })
        items = {
            header, space(nil, px(16)),
            text(_("A card of reading challenges: half genres, a quarter places and cultures, a quarter literary experiments. A finished book fills a square by itself when its tags or Calibre's #bingo column say which; otherwise Aleph asks. A full row or column is a bingo."),
                { s = 15, w = w, lines = 7 }),
            space(nil, px(20)),
            MenuUI.pill(_("24 books (5 × 5)"), { kind = "dark", w = w, h = 48, s = 16, icon = "grid-3x3", action = { kind = "new", size = 24 } }),
            space(nil, px(10)),
            MenuUI.pill(_("12 books (4 × 3)"), { kind = "outline", w = w, h = 48, s = 16, action = { kind = "new", size = 12 } }),
        }
    else
        local sub = summary(card)
        local header = MenuUI.pageHeader(w, _("Reading bingo"), { sub = sub })
        local rule = card.size == 12 and _("A row or a column = Bingo!") or _("5 in a row = Bingo!")
        local new = MenuUI.pill(_("New card"), { kind = "outline", h = 36, s = 14, pad_x = 14, icon = "rotate-ccw", action = { kind = "new-ask" } })
        local foot = hstack({ w = w, h = px(40) }, { text(rule, { s = 13, col = INK.g4 }), flex(px(8)), new })
        local hint = text(_("Tap a square to choose its book or change its challenge."), { s = 13, col = INK.g4, w = w })
        local room = sh - top - bottom - header:getSize().h - px(8) - hint:getSize().h - px(10) - px(10) - foot:getSize().h
        items = { header, space(nil, px(8)), hint, space(nil, px(10)), BingoPage.grid(card, w, room, card.size == 12 and 13 or 11, true, true), flex(px(10)), foot }
    end
    page.panel_rect = Geom:new{ x = 0, y = 0, w = sw, h = sh }
    return vstack({ w = sw, h = sh, pad = { top, mx, bottom, mx }, top = true }, items)
end

-- A sheet of rows (each { label, sub, icon, run }), a page at a time.
local function listSheet(title, sub, rows, extra)
    local state = { page = 1 }
    return SheetUI.open{
        name = "aleph_bingo_list",
        build = function(sheet, sw, sh)
            return SheetUI.sheet(sheet, sw, sh, function(w, max_h)
                local iw = MenuUI.rowsIn(w)
                local head = SheetUI.titleRow(w, title, sub)
                local row_h = px(60)
                local room = (max_h or sh * 0.7) - head:getSize().h - px(60) - (extra and px(56) or 0)
                local per = math.max(3, floor(room / row_h))
                local count = math.max(1, math.ceil(#rows / per))
                state.page = math.max(1, math.min(count, state.page))
                local shown = {}
                for i = (state.page - 1) * per + 1, math.min(#rows, state.page * per) do
                    local r = rows[i]
                    shown[#shown + 1] = MenuUI.row(iw, { icon = r.icon, label = r.label, sub = r.sub, data = true, sub_data = true, chevron = true, action = { kind = "pick", i = i } })
                end
                local out = { head }
                if #shown > 0 then out[#out + 1] = MenuUI.group(w, shown) end
                if count > 1 then out[#out + 1] = require("aleph_text_pages").pager(w, state.page, count) end
                if extra then out[#out + 1] = MenuUI.pill(extra.label, { kind = "outline", w = w, h = 44, s = 15, action = { kind = "extra" } }) end
                return out
            end, { pop_w = 520 })
        end,
        on_action = function(sheet, action)
            if action.kind == "page" then
                state.page = state.page + (action.delta or 0)
                sheet:refresh()
            elseif action.kind == "pick" then
                local r = rows[action.i]
                sheet:close()
                if r and r.run then UIManager:nextTick(r.run) end
            elseif action.kind == "extra" then
                sheet:close()
                if extra.run then UIManager:nextTick(extra.run) end
            end
            return true
        end,
    }
end

local function catName(cell)
    local cat = cell.cat or (Bingo.byId[cell.id] and Bingo.byId[cell.id].cat)
    return cat and Bingo.CATS[cat] and Bingo.CATS[cat]() or nil
end

local function chooseBook(page, index)
    local card = Bingo.card()
    if not card then return end
    local rows = {}
    for _i, b in ipairs(BingoPage.candidates(card)) do
        rows[#rows + 1] = { icon = "book-open", label = b.title or "", sub = b.finishedOn and T(_("Finished %1"), b.finishedOn) or nil, run = function()
            local c = Bingo.card()
            if not c then return end
            Bingo.clear(c, index)
            Bingo.fill(c, index, b)
            Bingo.save(c)
            if page and not page.closed then page:refresh() end
            refreshHome()
        end }
    end
    if #rows == 0 then return toast(_("No finished books to choose from yet."), "info") end
    listSheet(_("Choose a book"), Bingo.text(card.cells[index]), rows)
end

local function cellSheet(page, index)
    local card = Bingo.card()
    local cell = card and card.cells[index]
    if not cell or cell.free then return end
    local rows = {}
    if cell.path then
        rows[#rows + 1] = { icon = "book-open", label = _("Choose another book…"), sub = cell.title, run = function() chooseBook(page, index) end }
        rows[#rows + 1] = { icon = "x", label = _("Empty this square"), run = function()
            local c = Bingo.card(); Bingo.clear(c, index); Bingo.save(c)
            if not page.closed then page:refresh() end
            refreshHome()
        end }
    else
        rows[#rows + 1] = { icon = "book-open", label = _("Choose a book…"), sub = _("One you have finished"), run = function() chooseBook(page, index) end }
        rows[#rows + 1] = { icon = "shuffle", label = _("Another challenge"), sub = catName(cell), run = function()
            local c = Bingo.card()
            if Bingo.redraw(c, index) then Bingo.save(c) end
            if not page.closed then page:refresh() end
            refreshHome()
        end }
        rows[#rows + 1] = { icon = "pencil", label = _("Write my own…"), run = function()
            require("aleph_input").prompt{
                title = _("Your own challenge"), text = Bingo.text(cell), ok_label = _("Save"),
                on_ok = function(v)
                    v = tostring(v or ""):gsub("^%s+", ""):gsub("%s+$", "")
                    if v == "" then return end
                    local c = Bingo.card()
                    c.cells[index].text = v
                    Bingo.save(c)
                    if not page.closed then page:refresh() end
                    refreshHome()
                end,
            }
        end }
    end
    listSheet(Bingo.text(cell), catName(cell), rows)
end

local function newCard(page, size)
    Bingo.save(Bingo.newCard(size))
    if page and not page.closed then page:refresh() end
    refreshHome()
end

local function onAction(page, action)
    local k = action.kind
    if k == "cell" then cellSheet(page, action.index)
    elseif k == "new" then newCard(page, action.size)
    elseif k == "new-ask" then
        listSheet(_("New card"), _("The books on this card are let go"), {
            { icon = "grid-3x3", label = _("24 books (5 × 5)"), run = function() newCard(page, 24) end },
            { icon = "grid-3x3", label = _("12 books (4 × 3)"), run = function() newCard(page, 12) end },
        })
    end
    return true
end

function BingoPage.open()
    local page = MenuPage:new{ name = "aleph_bingo", build = build, on_action = onAction }
    UIManager:show(page, "ui")
    return page
end

-- After a finished book no rule placed: which open square does it fill?
function BingoPage.ask(book)
    local card = Bingo.card()
    if not card or not book or Bingo.onCard(card, book.path) then return end
    local rows = {}
    for index, cell in ipairs(card.cells) do
        if not cell.free and not cell.path then
            rows[#rows + 1] = { icon = "grid-3x3", label = Bingo.text(cell), sub = catName(cell), run = function()
                local c = Bingo.card()
                if not c or Bingo.onCard(c, book.path) then return end
                Bingo.fill(c, index, book)
                Bingo.save(c)
                local p = Bingo.progress(c)
                toast((p.in_line[index] and (_("Bingo!") .. " ") or "") .. T(_("Reading bingo: %1"), Bingo.text(c.cells[index])))
                refreshHome()
            end }
        end
    end
    if #rows == 0 then return end
    listSheet(T(_("Does %1 fill a square?"), book.title or ""), _("Reading bingo"), rows, { label = _("Not now") })
end

return BingoPage
