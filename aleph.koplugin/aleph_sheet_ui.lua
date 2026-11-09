-- Modified for Aleph, 2026-11-09. Unofficial local-only fork. See NOTICE.
--[[--
Parts for Aleph's sheets: the bottom sheet (a popover when wide) that
the Highlight of the day drawer and the Genres & tags sheet open in.

Taken from BookOrbit's dialog parts (bookorbit_dialog_ui.lua): only the
pieces those two sheets use. A sheet is a MenuPage that keeps the screen
underneath as a lightened backdrop, laid out by ListView.sheet.
]]

local Geom = require("ui/geometry")
local UIManager = require("ui/uimanager")

local BoardMetrics = require("aleph_board_metrics")
local BoardUI = require("aleph_board_ui")
local MenuPage = require("aleph_menu_page")
local MenuUI = require("aleph_menu_ui")

local INK = BoardMetrics.INK
local px = BoardMetrics.px
local text, vstack, hstack, space, flex, icon = BoardUI.text, BoardUI.vstack, BoardUI.hstack, BoardUI.space, BoardUI.flex, BoardUI.icon

local SheetUI = {}

local function wOf(widget) return widget:getSize().w end
local function hOf(widget) return widget:getSize().h end

-- A bottom sheet (popover when wide) holding build(inner_w, max_body_h)'s
-- items. Sets page.panel_rect so taps outside close it.
function SheetUI.sheet(page, sw, sh, build, o)
    o = o or {}
    local ListView = require("aleph_library_view")
    local layers, rect = ListView.sheet(sw, sh, { build = build, pop_w = o.pop_w or 460 })
    page.panel_rect = Geom:new{ x = rect.x, y = rect.y, w = rect.w, h = rect.h }
    return BoardUI.overlay(sw, sh, layers)
end

-- Opens a sheet over whatever is on screen. opts as for MenuPage; build is
-- function(page, sw, sh).
function SheetUI.open(opts)
    opts.backdrop = opts.backdrop ~= false
    if opts.dismiss_outside == nil then opts.dismiss_outside = true end
    local page = MenuPage:new(opts)
    UIManager:show(page, "ui")
    return page
end

-- A sheet's title row: a title, an optional muted line, and close.
function SheetUI.titleRow(w, title, sub)
    local inset = MenuUI.tapInset(23)
    local close = MenuUI.iconButton("x", { kind = "close" })
    local tw = w - (wOf(close) - inset + px(8))
    local column = vstack({ w = tw }, {
        text(title, { s = 18, b = true, w = tw }),
        sub and sub ~= "" and text(sub, { s = 13, col = INK.g4, w = tw, data = true }) or false,
    })
    local h = math.max(hOf(column), wOf(close) - 2 * inset)
    return BoardUI.overlay(w, h, {
        { widget = column, x = 0, y = 0 },
        { widget = close, x = w - wOf(close) + inset, y = -inset },
    })
end

-- Widgets left to right, wrapping onto new lines, gap between both ways.
function SheetUI.wrap(w, widgets, gap)
    gap = gap or px(8)
    local lines, line, used = {}, {}, 0
    for _i, widget in ipairs(widgets) do
        local ww = wOf(widget)
        if #line > 0 and used + gap + ww > w then
            table.insert(lines, line)
            line, used = {}, 0
        end
        if #line > 0 then used = used + gap end
        table.insert(line, widget)
        used = used + ww
    end
    if #line > 0 then table.insert(lines, line) end
    local rows = {}
    for index, items in ipairs(lines) do
        if index > 1 then table.insert(rows, space(nil, gap)) end
        local row = {}
        for _i, item in ipairs(items) do table.insert(row, item) end
        table.insert(row, flex(0))
        table.insert(rows, hstack({ w = w, gap = gap, valign = "center" }, row))
    end
    return vstack({ w = w }, rows)
end

-- An outlined chip. With an action it is a button (Aleph can list
-- the books of a genre), drawn with the black ring the book page uses.
function SheetUI.chip(label, max_w, action)
    local h = px(34)
    local b = math.max(1, px(action and 1.25 or 1))
    local t = text(label, { s = 14, data = true })
    if max_w and wOf(t) > max_w - 2 * px(14) then t = text(label, { s = 14, data = true, w = max_w - 2 * px(14) }) end
    local w = wOf(t) + 2 * px(14)
    local chip = BoardUI.box({ w = w, h = h, radius = math.floor(h / 2), border = b, border_col = action and INK.black or INK.g8, bg = INK.white },
        hstack({ w = w - 2 * b, h = h - 2 * b }, { flex(0), t, flex(0) }))
    return action and BoardUI.hit(chip, action) or chip
end

-- Pills sharing the width equally. pills: { label, icon, kind, action }.
function SheetUI.pillRow(w, pills)
    local gap = px(10)
    local n = #pills
    local each = math.floor((w - gap * (n - 1)) / n)
    local items = {}
    for index, p in ipairs(pills) do
        local pw = index == n and (w - (each + gap) * (n - 1)) or each
        table.insert(items, MenuUI.pill(p.label, { icon = p.icon, kind = p.kind, w = pw, action = p.action }))
    end
    return hstack({ w = w, gap = gap }, items)
end

-- A short line: an icon and a few words.
function SheetUI.note(w, glyph, str, o)
    o = o or {}
    return hstack({ w = w, gap = px(8), valign = "top" }, {
        icon(glyph, px(16), { sw = 2.25, col = o.icon_col or "black" }),
        text(str, { s = 13, b = o.b, col = o.col or INK.g3, w = w - px(24), lines = o.lines or 2, data = o.data }),
    })
end

-- A section label over a body.
function SheetUI.section(w, title, body, right)
    return vstack({ w = w }, { MenuUI.label(w, title, right), space(nil, px(8)), body })
end

return SheetUI
