-- Modified for Aleph, 2026-11-07. Unofficial local-only fork. See NOTICE.
--[[--
The library page: a BookOrbit-style list frame drawn from local books.

Header with a back chevron, title and sub line, the device status (Wi-Fi,
battery, clock), search and the menu; a toolbar (Sort, Filter, Collection)
with the List / Grid switch on its right; the books as a grid or as rows; a
dictionary-style A-Z thumb index down the right edge while the order is
alphabetical; and a pager whose middle opens Jump.

Adapted from BookOrbit's list view. Sizes are the design mock's dp values
through BoardMetrics, so the page lays out like BookOrbit's does. Every
control is its own tappable region; a D-pad press is a tap at the focused
region's centre.
]]
local DataStorage = require("datastorage")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local IconWidget = require("ui/widget/iconwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local Widget = require("ui/widget/widget")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")
local T = require("ffi/util").template
local _ = require("gettext")

local BoardMetrics = require("aleph_board_metrics")
local BoardUI = require("aleph_board_ui")
local CatalogWidgets = require("aleph_catalog_widgets")
local ListData = require("aleph_list_data")

-- The few menu parts the sheets need (BookOrbit keeps these in its menu kit).
local MenuUI = {}
function MenuUI.hair() return math.max(1, math.floor(BoardMetrics.get().dp * 0.75 + 0.5)) end
function MenuUI.line() return math.max(1, BoardMetrics.px(1)) end
function MenuUI.card(w, children)
    local px_ = BoardMetrics.px
    local border = MenuUI.line()
    local pad = px_(16)
    local inner = BoardUI.vstack({ w = w - 2 * border, pad = { 0, pad - border, 0, pad - border } }, children)
    local h = inner:getSize().h + 2 * border
    return BoardUI.box({ w = w, h = h, border = border, radius = px_(12), border_col = BoardMetrics.INK.g8, bg = BoardMetrics.INK.white }, inner)
end
function MenuUI.toggle(on)
    local px_, INK_ = BoardMetrics.px, BoardMetrics.INK
    local w, h, k, pad = px_(48), px_(28), px_(20), px_(4)
    local b = math.max(1, px_(1.5))
    local track = on and BoardUI.rect(w, h, INK_.black, math.floor(h / 2))
        or BoardUI.box({ w = w, h = h, radius = math.floor(h / 2), border = b, border_col = INK_.g5, bg = INK_.white })
    local knob = BoardUI.rect(k, k, on and INK_.white or INK_.g5, math.floor(k / 2))
    return BoardUI.overlay(w, h, { { widget = track }, { widget = knob, x = on and (w - pad - k) or pad, y = pad } })
end
function MenuUI.radio(on)
    local px_, INK_ = BoardMetrics.px, BoardMetrics.INK
    return BoardUI.circle(px_(22), { border = math.max(1, px_(1.75)), bg = INK_.white },
        on and BoardUI.rect(px_(10), px_(10), INK_.black, px_(5)) or BoardUI.space(1, 1))
end

local INK = BoardMetrics.INK
local px, lh1 = BoardMetrics.px, BoardMetrics.lh1
local text, runs, vstack, hstack, flex, space, icon = BoardUI.text, BoardUI.runs, BoardUI.vstack, BoardUI.hstack, BoardUI.flex, BoardUI.space, BoardUI.icon

local ListView = {}

local function hair() return MenuUI.hair() end
local function line1() return math.max(1, px(1)) end
local function wOf(widget) return widget:getSize().w end
local function hOf(widget) return widget:getSize().h end
local function clamp(v, lo, hi) if v < lo then return lo end if v > hi then return hi end return v end

-- The screen's width in dp, rounded as the design mock rounds it.
local function screenW()
    return BoardMetrics.layoutW()
end
ListView.screenW = screenW

function ListView.mx()
    local W = screenW()
    return px(W >= 900 and 28 or W >= 700 and 24 or W >= 560 and 20 or 16)
end

-- ----------------------------------------------------------------- regions
local Region = InputContainer:extend{ action = nil, run = nil }

function Region:init()
    local size = self[1]:getSize()
    self.dimen = Geom:new{ w = size.w, h = size.h }
    self.ges_events = {
        TapSelect = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } },
        HoldSelect = { GestureRange:new{ ges = "hold", range = function() return self.dimen end } },
    }
end

function Region:handleEvent(event)
    if event.handler == "onTapSelect" or event.handler == "onHoldSelect" then
        return Widget.handleEvent(self, event)
    end
    return InputContainer.handleEvent(self, event)
end

function Region:onTapSelect()
    if self.action and self.run then self.run(self.action, self) end
    return true
end

function Region:onHoldSelect()
    if self.action and self.run then self.run(self.action, self, true) end
    return true
end

local env = nil

-- Wraps widget as a control in focus row `row`; key names it for the dump.
local function region(widget, action, row, key)
    local r = Region:new{ action = action, run = env and env.run, CatalogWidgets.focusable(widget) }
    if env and row then
        env.rows[row] = env.rows[row] or {}
        table.insert(env.rows[row], r)
        if not env.row_seen[row] then env.row_seen[row] = true; table.insert(env.row_list, row) end
    end
    if env and key then env.regions[key] = r end
    return r
end

-- A painted-position wrapper for the parity dump.
local Mark = WidgetContainer:extend{ key = nil }
function Mark:getSize() return self[1]:getSize() end
function Mark:paintTo(bb, x, y)
    local size = self[1]:getSize()
    self.dimen = Geom:new{ x = x, y = y, w = size.w, h = size.h }
    self[1]:paintTo(bb, x, y)
end
local function mark(key, widget)
    if not env or not env.marks or not widget then return widget end
    local m = Mark:new{ key = key, widget }
    env.regions[key] = m
    return m
end

-- ------------------------------------------------------------- text tools
local function textWidth(str, o)
    local w = text(str, o)
    local width = wOf(w)
    if w.free then w:free() end
    return width
end

local function runsWidth(parts, o)
    local w = runs(parts, o)
    local width = wOf(w)
    if w.free then w:free() end
    return width
end

local function rule(w, col, t)
    return BoardUI.rect(w, t or hair(), col or INK.gc)
end

-- --------------------------------------------------------------- the frame
-- Header, toolbar, content and pager. The content box is what lists size
-- their rows to, so a page fills the screen exactly; nothing scrolls.
function ListView.frame(screen_w, screen_h, o)
    o = o or {}
    local mx = ListView.mx()
    local w = screen_w - 2 * mx
    local top, bottom = px(6), px(8)
    local tb = o.toolbar and px(44) or 0
    local band = o.offline and (px(32) + px(8)) or 0
    local content_h = screen_h - top - bottom - px(64) - tb - band - px(8) - px(40)
    return { mx = mx, w = w, content_h = content_h, top = top, bottom = bottom }
end

-- ------------------------------------------------------------------ pieces
local function iconButton(name, action, key, o)
    o = o or {}
    local box = px(44)
    local b = hstack({ w = box, h = box }, { flex(0), icon(name, px(o.size or 23), { sw = o.sw or 2 }), flex(0) })
    return region(b, action, "header", key)
end

-- The board's 64dp header: back, title over one sub line, device status,
-- search and the menu. While selecting: no back, no search, ✕ ends it.
function ListView.header(w, o)
    local box = px(44)
    local tap = math.floor((box - px(24)) / 2)
    local select = o.select
    local status = BoardUI.statusCluster({ clock = o.clock })
    local right = {}
    table.insert(right, space(px(8), 1))
    table.insert(right, status)
    table.insert(right, space(px(6), 1))
    if select then
        table.insert(right, iconButton("ellipsis", { kind = "select-menu" }, "select-menu"))
    else
        table.insert(right, iconButton("search", { kind = "search" }, "search"))
    end
    table.insert(right, iconButton(select and "x" or "menu", { kind = select and "select-done" or "menu" }, select and "select-done" or "menu"))
    local right_w = 0
    for _i, item in ipairs(right) do right_w = right_w + wOf(item) end
    -- The tap boxes reach into the margins so the glyphs sit on them.
    local row_w = w + tap + (select and 0 or tap)
    local lead = select and 0 or (box - px(4))
    local title_w = row_w - lead - right_w
    -- A long title steps down to 18 before it is cut.
    local title_s = 22
    while title_s > 18 and textWidth(o.title or "", { s = title_s, b = true }) > title_w do title_s = title_s - 1 end
    local title = text(o.title or "", { s = title_s, b = true, w = title_w, data = o.title_data })
    local sub
    if o.sub then
        if type(o.sub) == "table" then sub = runs(o.sub, { s = 13, col = INK.g4, w = title_w, data = true })
        else sub = text(o.sub, { s = 13, col = INK.g4, w = title_w, data = true }) end
    end
    local col = vstack({ w = title_w }, { title, sub or false })
    local items = { space(lead, 1), col, flex(0) }
    for _i, item in ipairs(right) do table.insert(items, item) end
    local row = hstack({ w = row_w, h = px(64) }, items)
    local layers = { { widget = row, x = 0, y = 0 } }
    if not select then
        local back = region(hstack({ w = box, h = box }, { flex(0), icon("chevron-left", px(26), { sw = 2.25 }), flex(0) }), { kind = "back" }, "header", "back")
        table.insert(layers, { widget = back, x = 0, y = math.floor((px(64) - box) / 2) })
    end
    local x0 = select and 0 or -tap
    return BoardUI.overlay(w, px(64), { { widget = BoardUI.overlay(row_w, px(64), layers), x = x0, y = 0 } })
end

-- A toolbar button: icon, value, a small down chevron; tinted when a filter
-- is on.
local function toolbarButton(b, with_icon)
    local items = {}
    if with_icon and b.icon then table.insert(items, icon(b.icon, px(16), { sw = 2.25 })) end
    table.insert(items, text(b.label, { s = 14, b = true, data = true }))
    table.insert(items, icon("chevron-down", px(13), { sw = 2.75, col = "g4" }))
    local inner = hstack({ h = b.on and px(32) or px(44), gap = px(6) }, items)
    if b.on then
        inner = BoardUI.box({ w = wOf(inner) + 2 * px(10), h = px(32), radius = px(16), bg = INK.ge },
            hstack({ w = wOf(inner) + 2 * px(10), h = px(32) }, { space(px(10), 1), inner, flex(0) }))
    end
    return inner
end

-- List / Grid, the current one inked.
function ListView.viewToggle(view, row_key)
    local s = px(32)
    local b = math.max(1, px(1.25))
    local function seg(name, on, which)
        local body = hstack({ w = s, h = s - 2 * b }, { flex(0), icon(name, px(16), { sw = 2.25, col = on and "white" or "black" }), flex(0) })
        local cell = on and BoardUI.box({ w = s, h = s - 2 * b, radius = px(7), bg = INK.black }, body) or body
        return region(cell, { kind = "view", view = which }, row_key or "toolbar", "view-" .. which)
    end
    return BoardUI.box({ w = 2 * s + 2 * b, h = s, radius = px(9), border = b, border_col = INK.black, bg = INK.white },
        hstack({ w = 2 * s, h = s - 2 * b }, { seg("list", view == "list", "list"), seg("layout-grid", view == "grid", "grid") }))
end

-- Controls on the left, List / Grid on the right, a black rule under.
-- Buttons drop their icons, then the last button, before a label is cut.
function ListView.toolbar(w, buttons, view)
    local right = view and ListView.viewToggle(view) or nil
    local rw = right and (wOf(right) + px(12)) or 0
    local gap = px(18)
    local function width(list, with_icon)
        local total = 0
        for i, b in ipairs(list) do
            local tb = toolbarButton(b, with_icon)
            total = total + wOf(tb) + (i > 1 and gap or 0)
        end
        return total
    end
    local chosen, with_icon = buttons, true
    if width(buttons, true) > w - rw then
        with_icon = false
        if width(buttons, false) > w - rw then
            chosen = {}
            for i = 1, #buttons - 1 do chosen[i] = buttons[i] end
        end
    end
    local left = {}
    for _i, b in ipairs(chosen) do table.insert(left, region(toolbarButton(b, with_icon), b.action, "toolbar", b.key)) end
    local row = hstack({ w = w, h = px(43) }, { hstack({ gap = gap }, left), flex(0), right or false })
    return mark("toolbar", vstack({ w = w }, { row, rule(w, INK.black, line1()) }))
end

-- ---------------------------------------------------------------- the pager
-- Chevrons turn pages (page keys and swipes do too); the middle says where
-- you are in the list's own terms and opens Jump.
function ListView.pager(w, o)
    local fh = px(40)
    local function chev(name, on, delta)
        local c = hstack({ w = px(44), h = fh }, { flex(0), icon(name, px(20), { sw = 2.5, col = on and "black" or "gb" }), flex(0) })
        return on and region(c, { kind = "page", delta = delta }, "pager", delta < 0 and "page-prev" or "page-next") or c
    end
    local parts = {}
    if o.range then table.insert(parts, { t = o.range, b = true }) end
    local count = o.pages and T(_("%1 of %2"), o.page, o.pages) or T(_("Page %1"), o.page)
    if (o.pages or 2) > 1 or not o.range then
        if o.range then table.insert(parts, { t = "   " }) end
        table.insert(parts, { t = count, b = not o.range, col = o.range and INK.g4 or INK.black })
    end
    local mid_items = { runs(parts, { s = 13 }) }
    if o.jump then table.insert(mid_items, icon("chevron-up", px(14), { sw = 2.75, col = "g4" })) end
    local mid = hstack({ h = fh, gap = px(6) }, { space(px(10) - px(6), 1), hstack({ gap = px(6) }, mid_items), space(px(10) - px(6), 1) })
    if o.jump then mid = region(mid, { kind = "jump-sheet" }, "pager", "jump") end
    local more_prev = o.page > 1 or o.has_prev
    local more_next = (o.pages and o.page < o.pages) or o.has_next
    return mark("pager", hstack({ w = w, h = fh, gap = px(4) }, { flex(0), chev("chevron-left", more_prev, -1), mid, chev("chevron-right", more_next, 1), flex(0) }))
end

-- --------------------------------------------------------- the thumb index
-- A dictionary's cut-in tabs, two letters a tab. The tab with this page's
-- letters is inked; tabs with nothing in the list are gray.
local TABS = { "#A", "BC", "DE", "FG", "HI", "JK", "LM", "NO", "PQ", "RS", "TU", "VW", "XYZ" }
ListView.TABS = TABS

local function chars(s)
    local out = {}
    for ch in s:gmatch(".") do table.insert(out, ch) end
    return out
end

function ListView.thumbIndex(hh, current, present)
    -- The rail is px(30) wide with its black edge inside that width.
    local b = line1()
    local tw = px(30) - b
    local n = #TABS
    local th = math.floor(hh / n)
    local cur = {}
    for _i, l in ipairs(current or {}) do cur[l] = true end
    local tabs = {}
    local prev_here = false
    for i, tab in ipairs(TABS) do
        local letters = chars(tab)
        local here, has, first_has = false, false, nil
        -- A tab of several letters goes to whichever comes first in the list
        -- ("#" can sort after Z).
        for _j, l in ipairs(letters) do
            if cur[l] then here = true end
            if present[l] then
                has = true
                local at = tonumber(present[l])
                if not first_has or (at and tonumber(present[first_has]) and at < tonumber(present[first_has])) then first_has = l end
            end
        end
        local h = i == n and (hh - th * (n - 1)) or th
        local labels = #letters > 2 and { letters[1] .. letters[2], letters[3] } or letters
        local stack = {}
        for _j, l in ipairs(labels) do
            table.insert(stack, text(l, { s = 11, b = true, col = here and INK.white or has and INK.black or INK.gb, w = tw, align = "center" }))
        end
        local body = vstack({ w = tw, h = h }, { flex(0), vstack({ w = tw }, stack), flex(0) })
        local cell
        if here then
            -- Rounded on the left only: a square right half covers the right corners.
            cell = BoardUI.overlay(tw, h, {
                { widget = BoardUI.rect(tw, h, INK.black, px(6)) },
                { widget = BoardUI.rect(math.ceil(tw / 2), h, INK.black), x = tw - math.ceil(tw / 2) },
                { widget = body },
            })
        else
            local top_line = i > 1 and not prev_here
            cell = BoardUI.overlay(tw, h, { top_line and { widget = rule(tw, INK.gc) } or {}, { widget = body } })
        end
        prev_here = here
        table.insert(tabs, has and region(cell, { kind = "jump-letter", letter = first_has }, "rail", "tab-" .. i) or cell)
    end
    return mark("rail", hstack({ w = tw + b, h = hh, valign = "top" }, { BoardUI.rect(b, hh, INK.black), vstack({ w = tw }, tabs) }))
end
ListView.RAIL_W = function() return px(30) + px(12) end

-- -------------------------------------------------------------- the covers
-- A cover in a hairline frame. Covers within 30% of 2:3 are cropped to fill;
-- other shapes sit centred on a gray plate. Dimmed when offline and not on
-- this device, since it cannot open until the server is back.
local function cover(book, w, h, o)
    o = o or {}
    local path = env and env.thumb and env.thumb(book) or nil
    local dim = env and env.offline and not (env.on_device and env.on_device(book))
    if path then
        return BoardUI.cover(book, w, h, { path = path, border = math.max(1, px(0.75)), border_col = INK.gb, crop_tol = 0.3, plate = true, dim = dim })
    end
    -- A book whose cover could not be read shows its title on a plate; one whose
    -- cover is still being extracted shows an empty gray plate.
    if book and book.cover_checked then return BoardUI.cover(book, w, h, {}) end
    return BoardUI.box({ w = w, h = h, border = math.max(1, px(0.75)), border_col = INK.gb, bg = INK.ge }, space(1, 1))
end

-- Paints children at offsets; each child may carry a white ring around it.
local Layered = Widget:extend{ layers = nil }
function Layered:getSize() return self.dimen end
function Layered:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    for _i, l in ipairs(self.layers) do
        if l.ring and l.ring > 0 then
            local s = l.widget:getSize()
            bb:paintRect(x + l.x - l.ring, y + l.y - l.ring, s.w + 2 * l.ring, s.h + 2 * l.ring, INK.white)
        end
        l.widget:paintTo(bb, x + l.x, y + l.y)
    end
end
local function layered(w, h, layers)
    return Layered:new{ dimen = Geom:new{ w = w, h = h }, layers = layers }
end


-- ----------------------------------------------------------- small marks
local function bar(w, h, pct, o)
    o = o or {}
    return BoardUI.bar(w, h, pct, { track = o.track or INK.gd, fill = INK.black, r = math.floor(h / 2) })
end

local function doneDot(s)
    return BoardUI.circle(s, { bg = INK.black }, icon("check", math.floor(s * 0.66 + 0.5), { col = "white", sw = 3.25 }))
end

-- The read mark: a black fold in the cover's top-right corner with a white
-- check, set off from the art by a white edge along its diagonal. Drawn as
-- an SVG once per size.
local function svgFile(name, body, size)
    local dir = DataStorage:getDataDir() .. "/cache/aleph/icons"
    util.makePath(dir)
    local path = dir .. "/" .. name .. ".svg"
    if lfs.attributes(path, "mode") ~= "file" then
        local f = io.open(path, "w")
        if f then
            f:write(string.format('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">%s</svg>', size, size, size, size, body))
            f:close()
        end
    end
    return path
end

local function checkPath(cx, cy, k)
    return string.format("M%.2f %.2fL%.2f %.2fL%.2f %.2f", cx - 0.42 * k, cy + 0.02 * k, cx - 0.12 * k, cy + 0.32 * k, cx + 0.44 * k, cy - 0.3 * k)
end

local function readMark(cover_w)
    local L = math.floor(clamp(cover_w * 0.27, px(24), px(36)) + 0.5)
    local edge = math.max(2, math.floor(px(1.5) + 0.5))
    local S = L + 2 * edge
    local k = L * 0.34
    local body = string.format('<path d="M0 0H%dV%dZ" fill="#ffffff"/><path d="M%d 0H%dV%dZ" fill="#000000"/><path d="%s" fill="none" stroke="#ffffff" stroke-width="%.2f" stroke-linecap="round" stroke-linejoin="round"/>',
        S, S, S - L, S, L, checkPath(S - L * 0.3, L * 0.3, k), math.max(2, L * 0.085))
    local path = svgFile(string.format("rb-readmark-%d-%d", S, L), body, S)
    return IconWidget:new{ file = path, width = S, height = S, alpha = true }, S
end
ListView.readMark = readMark

-- A strip flush with the cover's foot: progress while reading.
local function progressStrip(w, pct)
    local h = math.max(3, px(5))
    local edge = math.max(1, px(0.75))
    local fill = math.floor(w * clamp(pct or 0, 0, 100) / 100 + 0.5)
    fill = math.max(fill, math.floor(w * 0.02 + 0.5))
    return vstack({ w = w }, { BoardUI.rect(w, edge, INK.black), BoardUI.overlay(w, h, { { widget = BoardUI.rect(w, h, INK.white) }, { widget = BoardUI.rect(fill, h, INK.black) } }) }), h + edge
end


-- The checkbox, the same on rows and covers: a rounded square with a full
-- black border; chosen, it is inked with a white check.
local function checkbox(on, on_cover)
    local sz = px(24)
    local bw = math.max(2, math.floor(px(2) + 0.5))
    local box = on and BoardUI.box({ w = sz, h = sz, radius = px(6), bg = INK.black }, hstack({ w = sz, h = sz }, { flex(0), icon("check", px(16), { col = "white", sw = 3.25 }), flex(0) }))
        or BoardUI.box({ w = sz, h = sz, radius = px(6), border = bw, border_col = INK.black, bg = INK.white }, space(1, 1))
    if not on_cover then return box end
    -- On a cover it sits on a white halo, so dark art never eats its edge.
    local halo = math.max(2, math.floor(px(2) + 0.5))
    return BoardUI.overlay(sz + 2 * halo, sz + 2 * halo, {
        { widget = BoardUI.rect(sz + 2 * halo, sz + 2 * halo, INK.white, px(6) + halo) },
        { widget = box, x = halo, y = halo },
    }), halo
end

-- A cover with its marks: a strip while reading, the corner fold once read,
-- or the checkbox and an inked frame while selecting.
local function markedCover(book, w, h, o)
    o = o or {}
    local layers = { { widget = cover(book, w, h) } }
    local state = ListData.stateOf(book)
    if state == "reading" then
        local st, sh = progressStrip(w, tonumber(book.progressPercentage) or 0)
        table.insert(layers, { widget = st, x = 0, y = h - sh })
    end
    if o.select then
        if o.selected then
            local f = px(3)
            table.insert(layers, { widget = BoardUI.box({ w = w, h = h, border = f, border_col = INK.black }, space(1, 1)) })
        end
        local cb, halo = checkbox(o.selected, true)
        table.insert(layers, { widget = cb, x = w - px(8) - px(24) - halo, y = px(8) - halo })
    elseif state == "finished" then
        local m, S = readMark(w)
        table.insert(layers, { widget = m, x = w - S, y = 0 })
    end
    return BoardUI.overlay(w, h, layers)
end
ListView.markedCover = markedCover

-- --------------------------------------------------------------- the rows
local VW = function() return px(44) end
local ROW = 62
ListView.ROW = ROW

-- The status column narrows with its row so a two-column list keeps titles.
local function statusWidth(w)
    local wdp = w / BoardMetrics.get().dp
    if wdp >= 560 then return px(112) end
    if wdp < 400 then return px(80) end
    return px(92)
end

local function pictureCol(hh, widget)
    return hstack({ w = VW(), h = hh - 1 }, { flex(0), widget, flex(0) })
end

local function textCol(tw, title, second, o)
    o = o or {}
    local items = { text(title, { s = 15, b = true, w = tw, data = true }) }
    if second then
        if type(second) == "table" then table.insert(items, runs(second, { s = 13, col = INK.g4, w = tw, data = true }))
        else table.insert(items, text(second, { s = 13, col = INK.g3, w = tw, data = true })) end
    end
    return vstack({ w = tw }, { items[1], items[2] and space(nil, px(2)) or false, items[2] or false })
end

-- The right-hand cell: the value on top, words under it.
local function cell(sw, top, bottom)
    return vstack({ w = sw, align = "right" }, { top, bottom and space(nil, px(3)) or false, bottom and text(bottom, { s = 12, col = INK.g4, w = sw, align = "right", data = true }) or false })
end

local function doneTop(sw, label)
    return hstack({ w = sw }, { flex(0), doneDot(px(14)), space(px(5), 1), text(label, { s = 14, b = true }) })
end

local function statusCell(book, sw)
    local c = ListData.statusCell(book, { minutes_left = env and env.minutes_left and env.minutes_left(book), narrow = sw < px(90), now = env and env.now })
    if c.kind == "reading" then
        return cell(sw, hstack({ w = sw }, { flex(0), bar(px(30), px(4), c.pct), space(px(6), 1), text(c.label, { s = 14, b = true }) }), c.bottom)
    elseif c.kind == "finished" then
        return cell(sw, doneTop(sw, c.label), c.bottom)
    elseif c.kind == "want" then
        return cell(sw, text(c.label, { s = 14, b = true, w = sw, align = "right" }), c.bottom)
    end
    return cell(sw, text(c.label, { s = 13, col = INK.g4, w = sw, align = "right", data = true }), c.bottom)
end
ListView.statusCell = statusCell

function ListView.bookRow(w, hh, b, o)
    o = o or {}
    local ch = math.min(px(54), hh - px(14))
    local sel = o.select and checkbox(o.selected) or nil
    local sel_w = sel and (px(24) + px(12)) or 0
    local mark_w = px(17) + px(10)
    local sw = statusWidth(w)
    local tw = w - VW() - px(12) - sel_w - sw - px(10) - mark_w
    local series = b.seriesName and (b.seriesIndex and (b.seriesName .. " #" .. tostring(b.seriesIndex)) or b.seriesName) or nil
    local second
    if o.context == "series" then second = nil
    elseif o.context == "author" then second = series
    else
        local parts = {}
        if b.authors and b.authors[1] then table.insert(parts, b.authors[1]) end
        if series then table.insert(parts, series) end
        second = #parts > 0 and table.concat(parts, " · ") or nil
    end
    local on_device = env and env.on_device and env.on_device(b)
    local items = {}
    if sel then table.insert(items, sel); table.insert(items, space(px(12), 1)) end
    table.insert(items, pictureCol(hh, cover(b, math.floor(ch * 2 / 3 + 0.5), ch)))
    table.insert(items, space(px(12), 1))
    table.insert(items, textCol(tw, b.title or "", second))
    table.insert(items, space(px(10), 1))
    table.insert(items, statusCell(b, sw))
    table.insert(items, space(px(10), 1))
    table.insert(items, on_device and icon("bo-device", px(17), { sw = 2 }) or space(px(17), 1))
    return hstack({ w = w, h = hh - 1 }, items)
end


-- ------------------------------------------------------------ index lists
-- Entries on hairlines, the group mark set in the margin where its group
-- starts. Wide screens run it in two columns, like a printed index, when
-- each column keeps a readable title (440dp).
function ListView.indexColumns(total_w)
    local W = BoardMetrics.layoutDp(total_w)
    return ((W - 28) / 2 >= 440) and 2 or 1
end

local function gutterMark(gw, label, carried)
    if gw <= 0 then return nil end
    local items = { space(nil, px(9)) }
    if label and label ~= "" then
        table.insert(items, text(label, { s = #label > 1 and 13 or 22, b = true, serif = #label == 1, col = carried and INK.g9 or INK.black, w = gw - px(4), data = true }))
    end
    return vstack({ w = gw }, items)
end

-- o: entries (this page), rows_per_col, row_h, gutter (dp), rail, groupOf,
-- carried (the first entry's group started on an earlier page), row(w, hh,
-- entry, index), action(entry, index), cols, present, letters, group_rules.
function ListView.indexList(w, hh, o)
    local gw = px(o.gutter or 34)
    if o.gutter == 0 then gw = 0 end
    local rail = o.rail
    local total = w - (rail and ListView.RAIL_W() or 0)
    local ncols = o.cols or ListView.indexColumns(total)
    local col_gap = px(28)
    local lw = ncols > 1 and math.floor((total - (ncols - 1) * col_gap) / ncols) or total
    local n, rh = o.rows_per_col, o.row_h
    local columns = {}
    local prev = nil
    local index = 0
    local seen = {}
    for k = 1, ncols do
        local rows = {}
        for i = 1, n do
            index = index + 1
            local entry = o.entries[index]
            if not entry then break end
            local g = o.groupOf(entry)
            -- A group already labelled on this page joins the previous one.
            if o.first_only and seen[g] and g ~= prev then g = prev end
            seen[g] = true
            local label, carried
            if i == 1 and k == 1 then label = g; carried = o.carried == true
            elseif i == 1 then label = g; carried = (g == prev)
            elseif g ~= prev then label = g end
            local new_group = i > 1 and label ~= nil and o.group_rules ~= false and g ~= prev
            prev = g
            local body = o.row(lw - gw, rh, entry, index)
            local top = i > 1 and (new_group and BoardUI.rect(lw - gw, line1(), INK.black) or BoardUI.rect(lw - gw, hair(), INK.gc)) or nil
            local inner = vstack({ w = lw - gw, h = rh }, { top or false, flex(0), body, flex(0) })
            local r = region(inner, o.action(entry, index), "row-" .. ((k - 1) * n + i), "row-" .. index)
            table.insert(rows, hstack({ w = lw, h = rh, valign = "top" }, { gutterMark(gw, label, carried) or false, r }))
        end
        columns[k] = vstack({ w = lw }, rows)
    end
    local list = hstack({ w = total, valign = "top", gap = col_gap }, columns)
    local items = { list }
    if rail then
        table.insert(items, flex(0))
        table.insert(items, ListView.thumbIndex(hh, o.letters or {}, o.present or {}))
    end
    return hstack({ w = w, h = hh, valign = "top" }, items)
end

-- ------------------------------------------------------------------ grids
local function CAP() return px(8) + lh1(13) + px(1) + lh1(11) end
ListView.CAP = CAP

function ListView.gridCols(gw_px)
    local gw = BoardMetrics.layoutDp(gw_px)
    return gw >= 860 and 6 or gw >= 640 and 5 or gw >= 440 and 4 or 3
end

-- Columns by width, rows by height: covers grow until the page is full, and
-- a row that would leave half a cell of air takes one more, smaller row.
function ListView.gridGeom(w, hh, o)
    o = o or {}
    local cap = o.cap or CAP()
    local cols = o.cols or ListView.gridCols(w)
    local gx, gy = px(o.gx or 14), px(o.gy or 18)
    local cw = math.floor((w - (cols - 1) * gx) / cols)
    local aspect = o.aspect or 1.5
    local cover_h = math.floor(cw * aspect + 0.5)
    local rows = math.max(1, math.floor((hh + gy) / (cover_h + cap + gy)))
    if hh - rows * (cover_h + cap + gy) > (cover_h + cap) * 0.42 then
        rows = rows + 1
        cover_h = math.floor((hh + gy) / rows - cap - gy)
    else
        cover_h = math.min(math.floor(cw * aspect + 0.5), math.floor((hh + gy) / rows - cap - gy))
    end
    local cover_w = math.min(cw, math.floor(cover_h / aspect + 0.5))
    return { cols = cols, rows = rows, cw = cw, gx = gx, gy = gy, cover_h = cover_h, cover_w = cover_w, per = cols * rows }
end

-- The All books cover size on this screen; every grid of books uses it, so a
-- cover is one size everywhere.
function ListView.stdGeom(screen_w, screen_h)
    local f = ListView.frame(screen_w, screen_h, { toolbar = true })
    local gw = f.w - ListView.RAIL_W()
    return ListView.gridGeom(gw, f.content_h - px(6), { cols = ListView.gridCols(gw) })
end

-- n books at the standard size in a box w wide; covers shrink only when the
-- box cannot hold their rows.
function ListView.fitStd(screen_w, screen_h, w, hh, n)
    local std = ListView.stdGeom(screen_w, screen_h)
    local cols = ListView.gridCols(w)
    local gx, gy = px(14), px(18)
    local cw = math.floor((w - (cols - 1) * gx) / cols)
    local cover_w = math.min(cw, std.cover_w)
    local cover_h = math.floor(cover_w * 1.5 + 0.5)
    local rows = math.max(1, math.ceil(n / cols))
    local function need(ch) return rows * (ch + CAP()) + (rows - 1) * gy end
    if hh and need(cover_h) > hh then
        cover_h = math.max(px(60), math.floor((hh - (rows - 1) * gy) / rows - CAP()))
        cover_w = math.floor(cover_h / 1.5 + 0.5)
    end
    return { cols = cols, cw = cw, gx = gx, gy = gy, cover_w = cover_w, cover_h = cover_h, rows = rows, per = cols * rows, h = need(cover_h) }
end

-- The bold title and the gray line under a cover. The gray line drops its
-- second part before it would be cut; the device mark sits at its end unless
-- the line already says time left (which only this device knows).
local function caption(w, title, meta, o)
    o = o or {}
    local dev_w = px(13) + px(6)
    local dev = o.device
    local fits = function(m, room) return runsWidth(m, { s = 11 }) <= room end
    local m = meta
    if dev and o.implied and fits(meta, w) then dev = false
    elseif #m > 1 and not fits(m, w - (dev and dev_w or 0)) then m = { m[1] } end
    local dev_icon = dev and icon("bo-device", px(13), { sw = 2.25, col = "g3" }) or nil
    local styled = {}
    for _i, part in ipairs(m) do table.insert(styled, { t = part.t, b = part.b, col = part.b and INK.black or INK.g4 }) end
    local line
    if o.center then
        line = runs(styled, { s = 11, col = INK.g4, w = w, align = "center", data = true })
    else
        line = hstack({ w = w, gap = px(6) }, { runs(styled, { s = 11, col = INK.g4, w = w - (dev_icon and dev_w or 0), data = true }), dev_icon or false })
    end
    return vstack({ w = w }, { text(title, { s = 13, b = true, w = w, align = o.center and "center" or "left", data = true }), space(nil, px(1)), line })
end

function ListView.bookCell(g, b, o)
    o = o or {}
    local cv = markedCover(b, g.cover_w, g.cover_h, { select = o.select, selected = o.selected })
    local minutes = env and env.minutes_left and env.minutes_left(b)
    local meta = o.meta and o.meta(b) or ListData.bookMeta(b, { minutes_left = minutes, now = env and env.now, author = o.author })
    local on_device = env and env.on_device and env.on_device(b)
    local inner = vstack({ w = g.cover_w }, { cv, space(nil, px(8)), caption(g.cover_w, o.title and o.title(b) or b.title or "", meta, { device = on_device, implied = minutes ~= nil and not o.meta }) })
    return hstack({ w = g.cw }, { flex(0), inner, flex(0) })
end


-- Cells in rows; o.action(entry, index) makes each a region.
function ListView.cellsGrid(w, g, entries, build, action)
    local rows = {}
    local index = 0
    for start = 1, #entries, g.cols do
        local cells = {}
        for i = start, math.min(#entries, start + g.cols - 1) do
            index = index + 1
            table.insert(cells, region(build(entries[i], i), action(entries[i], i), "grid-" .. math.ceil(i / g.cols), "cell-" .. i))
        end
        if #rows > 0 then table.insert(rows, space(nil, g.gy)) end
        table.insert(rows, hstack({ gap = g.gx, valign = "top" }, cells))
    end
    return vstack({ w = w }, rows)
end

function ListView.withRail(w, hh, body, letters, present)
    return hstack({ w = w, h = hh, valign = "top" }, { body, flex(0), ListView.thumbIndex(hh, letters or {}, present or {}) })
end

-- --------------------------------------------------------- section heads
function ListView.sectionHead(w, o)
    local items = {}
    if o.icon then table.insert(items, icon(o.icon, px(16), { sw = 2.25 })) end
    table.insert(items, text(o.label, { s = 14, b = true, data = true }))
    if o.count then table.insert(items, text(tostring(o.count), { s = 13, col = INK.g4 })) end
    local left = hstack({ gap = px(8), valign = "bottom" }, items)
    local row = hstack({ w = w, h = px(36) - px(6) - line1(), valign = "bottom" }, { left, flex(0), o.right or false })
    return vstack({ w = w }, { row, space(nil, px(6)), BoardUI.rect(w, line1(), INK.black) })
end

-- ------------------------------------------------------------------ pills
-- o.disabled draws any kind as a gray outline: nothing to act on yet.
function ListView.pill(label, o)
    o = o or {}
    local h = px(o.h or 44)
    local kind = o.disabled and "outline" or o.kind
    local dark = kind ~= "outline" and kind ~= "ghost"
    local fg = o.disabled and "gb" or dark and "white" or "black"
    local items = {}
    if o.icon then table.insert(items, icon(o.icon, px(o.icon_size or 18), { col = fg, sw = 2.5 })) end
    table.insert(items, text(label, { s = o.s or 15, b = true, col = o.disabled and INK.gb or dark and INK.white or INK.black }))
    local content = hstack({ gap = px(8) }, items)
    local w = wOf(content) + 2 * px(o.pad_x or 18)
    local border = kind == "outline" and math.max(1, px(1.5)) or 0
    local body = hstack({ w = w - 2 * border, h = h - 2 * border }, { flex(0), content, flex(0) })
    return BoardUI.box({ w = w, h = h, radius = math.floor(h / 2), border = border, border_col = o.disabled and INK.gb or INK.black, bg = dark and INK.black or INK.white }, body)
end

-- --------------------------------------------------------------- states
function ListView.empty(w, hh, o)
    local action = o.action and region(ListView.pill(o.action.label, { kind = "outline", h = 40, s = 14 }), o.action.action, "empty", "empty-action") or nil
    local items = {
        flex(0),
        BoardUI.circle(px(64), { bg = INK.ge }, icon(o.icon, px(28), { sw = 2 })),
        space(nil, px(10) + px(4)),
        text(o.title, { s = 18, b = true, w = math.min(w, px(420)), align = "center" }),
        space(nil, px(10)),
        text(o.body, { s = 14, col = INK.g4, w = math.min(w, px(380)), align = "center", lines = 3 }),
    }
    if action then
        table.insert(items, space(nil, px(10) + px(6)))
        table.insert(items, action)
    end
    table.insert(items, flex(0))
    return vstack({ w = w, h = hh, align = "center" }, items)
end



-- ------------------------------------------------------------------ sheets
-- Lightens what is under a sheet.
local Scrim = Widget:extend{}
function Scrim:getSize() return self.dimen end
function Scrim:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    bb:lightenRect(x, y, self.dimen.w, self.dimen.h, 0.6)
end
ListView.Scrim = Scrim

-- A segmented control whose segments are regions.
function ListView.segmented(w, options, selected, action_for, o)
    o = o or {}
    local h = px(o.h or 40)
    local b = math.max(1, px(1.5))
    local n = #options
    local inner = w - 2 * b
    local seg_w = math.floor(inner / n)
    local segs = {}
    for index, label in ipairs(options) do
        local sw = index == n and (inner - seg_w * (n - 1)) or seg_w
        local on = index == selected
        local t = text(label, { s = o.s or 13, b = on, col = on and INK.white or INK.black, w = sw - px(8), align = "center" })
        local body = hstack({ w = sw, h = h - 2 * b }, { flex(0), t, flex(0) })
        local seg
        if on then
            seg = BoardUI.box({ w = sw, h = h - 2 * b, radius = px(8), bg = INK.black }, body)
        else
            local left_line = index > 1 and selected ~= index - 1
            seg = BoardUI.overlay(sw, h - 2 * b, { { widget = body }, left_line and { widget = BoardUI.rect(hair(), h - 2 * b, INK.g8) } or {} })
        end
        table.insert(segs, region(seg, action_for(index), o.row or ("seg-" .. tostring(options[1])), o.key and (o.key .. "-" .. index) or nil))
    end
    return BoardUI.box({ w = w, h = h, radius = px(10), border = b, border_col = INK.black, bg = INK.white }, hstack({ w = inner, h = h - 2 * b }, segs))
end

-- A sheet head: title and a control on the right.
local function sheetHead(w, title, right)
    local h = math.max(px(32), right and hOf(right) or 0)
    return hstack({ w = w, h = h }, { text(title, { s = 18, b = true }), flex(px(8)), right or false })
end
local function sheetLabel(w, t) return text(t, { s = 13, b = true, col = INK.g4, w = w }) end
ListView.sheetHead, ListView.sheetLabel = sheetHead, sheetLabel

-- A row inside a sheet's group card.
local function groupRow(w, o)
    local trailing = {}
    if o.value then table.insert(trailing, text(o.value, { s = 14, col = INK.g4, data = true })) end
    if o.toggle ~= nil then table.insert(trailing, MenuUI.toggle(o.toggle)) end
    if o.radio ~= nil then table.insert(trailing, MenuUI.radio(o.radio)) end
    if o.chevron then table.insert(trailing, icon("chevron-right", px(18), { sw = 2.25 })) end
    local right = #trailing > 0 and hstack({ gap = px(10) }, trailing) or nil
    local icon_w = o.icon and (px(24) + px(14)) or 0
    local right_w = right and (wOf(right) + px(12)) or 0
    local items = {}
    local s = o.s or 15
    local label_w = w - icon_w - right_w
    local label_s = BoardUI.fitSize(o.label, { s = s, b = o.bold }, label_w, s - 2)
    -- A label too long even two sizes down takes a second line, and the
    -- row grows to hold it.
    local lines = BoardUI.fitSize(o.label, { s = s - 2, b = o.bold }, label_w, s - 3) < s - 2 and 2 or nil
    local label = text(o.label, { s = label_s, b = o.bold, w = label_w, lines = lines })
    local h = math.max(px(o.h or 50), label:getSize().h + px(12))
    if o.icon then
        table.insert(items, hstack({ w = px(24), h = h }, { flex(0), icon(o.icon, px(22), { sw = 2 }), flex(0) }))
        table.insert(items, space(px(14), 1))
    end
    table.insert(items, label)
    if right then table.insert(items, flex(px(12))); table.insert(items, right) end
    return region(hstack({ w = w, h = h }, items), o.action, o.row or ("sheet-row-" .. o.label), o.key)
end
ListView.groupRow = groupRow

local function groupCard(w, rows)
    local iw = w - 2 * px(16)
    local children = {}
    for _i, r in ipairs(rows) do
        if #children > 0 then table.insert(children, BoardUI.rect(iw, hair(), INK.gb)) end
        table.insert(children, r)
    end
    return MenuUI.card(w, children)
end
ListView.groupCard = groupCard

-- The sheet's frame: a top sheet (from the toolbar) or a bottom sheet (from
-- the pager); a popover on wide screens.
-- o: kind ("top"/"bottom"), pop_w (dp), top (px, popover), build(inner_w).
function ListView.sheet(screen_w, screen_h, o)
    local mx = ListView.mx()
    local pad = px(16)
    local wide = screenW() >= 760
    local pw = wide and math.min(px(o.pop_w or 460), screen_w - 2 * mx) or screen_w
    local pad_x = wide and pad or mx
    local inner = pw - 2 * pad_x
    -- The tallest body that fits between the header and the bottom edge.
    local header_bottom = px(6) + px(64)
    local max_body = screen_h - header_bottom - px(8) - 2 * pad
    local gap = px(14)
    local function stack(items, width)
        local spaced = {}
        for _i, item in ipairs(items) do
            if item then
                if #spaced > 0 then table.insert(spaced, space(nil, gap)) end
                table.insert(spaced, item)
            end
        end
        return vstack({ w = width }, spaced)
    end
    -- What the build registers, so a draft can be taken back.
    local hit_mark = BoardUI.hitMark()
    local rows_mark = {}
    if env then for key, list in pairs(env.rows) do rows_mark[key] = #list end end
    local row_list_mark = env and #env.row_list or 0
    local body = stack(o.build(inner, max_body), inner)
    local function takeBack()
        BoardUI.hitTrim(hit_mark)
        if env then
            for key, list in pairs(env.rows) do
                for i = #list, (rows_mark[key] or 0) + 1, -1 do table.remove(list, i) end
                if #list == 0 and not rows_mark[key] then env.rows[key] = nil; env.row_seen[key] = nil end
            end
            for i = #env.row_list, row_list_mark + 1, -1 do table.remove(env.row_list, i) end
        end
    end
    local col_gap = px(24)
    local pw2 = math.min(2 * px(o.pop_w or 460) + col_gap, screen_w - 2 * mx)
    local col_w = math.floor((pw2 - 2 * pad - col_gap) / 2)
    -- The two columns, split where they come out most even; nil when
    -- something in them would be cut.
    local function columns(checked)
        local function draft()
            local items = {}
            for _i, item in ipairs(o.build(col_w, max_body)) do if item then table.insert(items, item) end end
            local heights, total = {}, 0
            for i, item in ipairs(items) do heights[i] = hOf(item); total = total + heights[i] end
            local best, best_h, run = #items, math.huge, 0
            for k = 1, #items - 1 do
                run = run + heights[k]
                local tallest = math.max(run + (k - 1) * gap, total - run + (#items - k - 1) * gap)
                if tallest < best_h then best, best_h = k, tallest end
            end
            local left, right = {}, {}
            for i, item in ipairs(items) do table.insert(i <= best and left or right, item) end
            return hstack({ w = pw2 - 2 * pad, gap = col_gap, valign = "top" }, { stack(left, col_w), stack(right, col_w) })
        end
        if checked then
            local clean, probe = BoardUI.fits(function() return BoardUI.collectHits(draft) end)
            if probe and probe.free then probe:free() end
            if not clean then return nil end
        end
        return draft()
    end
    -- A wide, short screen (landscape) sets a sheet too tall for it in two
    -- columns. Narrower columns are tried too when one column would not fit
    -- even raised to the header, as long as nothing in them is cut.
    local raised_max = screen_h - px(8) - header_bottom - 2 * pad
    if wide and hOf(body) > max_body and (col_w >= px(300) or (hOf(body) > raised_max and col_w >= px(220))) then
        body:free()
        takeBack()
        local split = columns(col_w < px(300))
        if split then
            pw, inner = pw2, pw2 - 2 * pad
            body = split
        else
            body = stack(o.build(inner, max_body), inner)
        end
    end
    local line = math.max(1, px(1.5))
    local r = px(16)
    local layers, x, y, ph
    if wide then
        ph = hOf(body) + 2 * pad
        local content = vstack({ w = pw - 2 * line, pad = { pad - line, pad - line, pad - line, pad - line } }, { body })
        local panel = BoardUI.box({ w = pw, h = ph, radius = r, border = line, border_col = INK.black, bg = INK.white }, content)
        x = o.kind == "top" and (screen_w - mx - pw) or math.floor((screen_w - pw) / 2)
        y = o.kind == "top" and (o.top or px(112)) or (screen_h - px(56) - ph)
        -- On a short screen a tall sheet rises toward the header rather than
        -- run off the bottom, and over it when it must.
        if y + ph > screen_h - px(8) then
            local lowest = screen_h - px(8) - ph
            y = lowest >= header_bottom and lowest or math.max(px(8), lowest)
        end
        layers = { { widget = panel, x = x, y = y } }
    else
        local pad_t = o.kind == "top" and px(10) or pad
        local pad_b = o.kind == "top" and pad or px(14)
        ph = pad_t + hOf(body) + pad_b
        local content = vstack({ w = pw, pad = { pad_t, pad_x, pad_b, pad_x } }, { body })
        x = 0
        if o.kind == "top" then
            y = 0
            -- Square at the top edge, rounded at the bottom with a black rule along it.
            layers = {
                { widget = BoardUI.rect(pw, ph + line, INK.black, r), x = 0, y = 0 },
                { widget = BoardUI.rect(pw, r, INK.black), x = 0, y = 0 },
                { widget = BoardUI.rect(pw, ph, INK.white, r), x = 0, y = 0 },
                { widget = BoardUI.rect(pw, r, INK.white), x = 0, y = 0 },
                { widget = content, x = 0, y = 0 },
            }
        else
            y = screen_h - ph
            layers = {
                { widget = BoardUI.rect(pw, ph + line, INK.black, r), x = 0, y = y - line },
                { widget = BoardUI.rect(pw, r, INK.black), x = 0, y = screen_h - r },
                { widget = BoardUI.rect(pw, ph, INK.white, r), x = 0, y = y },
                { widget = BoardUI.rect(pw, r, INK.white), x = 0, y = screen_h - r },
                { widget = content, x = 0, y = y },
            }
        end
    end
    return layers, { x = x, y = y, w = pw, h = ph }
end

-- Every letter as a key; letters with nothing in the list are drawn but
-- cannot be pressed. The current page's letters are inked.
function ListView.jumpKeys(w, present, current)
    local keys = { "#" }
    for c = string.byte("A"), string.byte("Z") do table.insert(keys, string.char(c)) end
    local cols = w >= BoardMetrics.lpx(560) and 9 or 7
    local gap = px(6)
    local kw = math.floor((w - (cols - 1) * gap) / cols)
    local kh = px(44)
    local cur = {}
    for _i, l in ipairs(current or {}) do cur[l] = true end
    local rows = {}
    for start = 1, #keys, cols do
        local cells = {}
        for i = start, math.min(#keys, start + cols - 1) do
            local k = keys[i]
            local has = present[k] ~= nil
            local here = cur[k]
            local label = text(k, { s = 17, b = true, col = here and INK.white or has and INK.black or INK.ga, w = kw, align = "center" })
            local body = hstack({ w = kw, h = kh }, { flex(0), label, flex(0) })
            local key
            if here then key = BoardUI.box({ w = kw, h = kh, radius = px(10), bg = INK.black }, body)
            elseif has then key = BoardUI.box({ w = kw, h = kh, radius = px(10), border = line1(), border_col = INK.g8, bg = INK.white }, hstack({ w = kw - 2 * line1(), h = kh - 2 * line1() }, { flex(0), label, flex(0) }))
            else key = BoardUI.box({ w = kw, h = kh, radius = px(10), bg = INK.ge }, body) end
            table.insert(cells, has and region(key, { kind = "jump-letter", letter = k, close = true }, "jump-row-" .. math.ceil(i / cols), "key-" .. k) or key)
        end
        if #rows > 0 then table.insert(rows, space(nil, gap)) end
        table.insert(rows, hstack({ gap = gap }, cells))
    end
    return vstack({ w = w }, rows)
end

function ListView.pageStepper(w, page, pages)
    local s = px(36)
    local function btn(name, delta, on)
        local c = BoardUI.circle(s, { border = math.max(1, px(1.5)), border_col = on and INK.black or INK.gb, bg = INK.white }, icon(name, px(16), { sw = 2.75, col = on and "black" or "gb" }))
        return on and region(c, { kind = "page", delta = delta }, "jump-stepper", "step-" .. (delta < 0 and "minus" or "plus")) or c
    end
    local mid = vstack({ w = px(52), align = "center" }, { text(tostring(page), { s = 18, b = true, w = px(52), align = "center" }), text(T(_("of %1"), pages), { s = 12, col = INK.g4, w = px(52), align = "center" }) })
    local stepper = hstack({ gap = px(10) }, { btn("minus", -1, page > 1), mid, btn("plus", 1, page < pages) })
    local first = region(ListView.pill(_("First"), { kind = "outline", icon = "chevrons-left", h = 40, s = 14, pad_x = 14 }), { kind = "page-to", page = 1, close = true }, "jump-stepper", "first")
    local last = region(ListView.pill(_("Last"), { kind = "outline", icon = "chevrons-right", h = 40, s = 14, pad_x = 14 }), { kind = "page-to", page = pages, close = true }, "jump-stepper", "last")
    return hstack({ w = w }, { first, flex(0), stepper, flex(0), last })
end

-- ------------------------------------------------------------- the screen
-- Builds one page. ctx: screen_w, screen_h, run, marks, env (thumb, photo,
-- on_device, minutes_left, offline, now), header ({ title, sub, title_data,
-- select, clock }), toolbar ({ buttons, view }), body(f) -> widget, pager
-- ({ page, pages, range, jump, has_prev, has_next }) or select_bar, sheet
-- (function(screen_w, screen_h) -> layers).
-- Returns the screen, the focus rows (top to bottom) and regions by key.
function ListView.build(ctx)
    BoardMetrics.refresh()
    local screen_w, screen_h = ctx.screen_w, ctx.screen_h
    env = {
        rows = {}, row_seen = {}, row_list = {}, regions = {}, run = ctx.run, marks = ctx.marks,
        thumb = ctx.env and ctx.env.thumb, on_device = ctx.env and ctx.env.on_device,
        minutes_left = ctx.env and ctx.env.minutes_left, offline = ctx.env and ctx.env.offline, now = ctx.env and ctx.env.now,
    }
    local ok, result = pcall(function()
        local f = ListView.frame(screen_w, screen_h, { toolbar = ctx.toolbar ~= nil })
        local items = { mark("header", ListView.header(f.w, ctx.header)) }
        if ctx.toolbar then table.insert(items, ListView.toolbar(f.w, ctx.toolbar.buttons, ctx.toolbar.view)) end
        table.insert(items, mark("content", ctx.body(f)))
        table.insert(items, flex(px(8)))
        table.insert(items, ListView.pager(f.w, ctx.pager or { page = 1, pages = 1 }))
        local screen = vstack({ w = screen_w, h = screen_h, pad = { f.top, f.mx, f.bottom, f.mx } }, items)
        local layers = { { widget = screen } }
        if ctx.sheet then
            -- With a sheet open, a tap anywhere outside it closes it and reaches
            -- nothing underneath.
            table.insert(layers, { widget = region(space(screen_w, screen_h), { kind = "close-sheet" }, nil, "outside") })
            table.insert(layers, { widget = Scrim:new{ dimen = Geom:new{ w = screen_w, h = screen_h } } })
            local sheet_layers, rect = ctx.sheet(screen_w, screen_h)
            -- The sheet itself swallows taps that land between its controls.
            table.insert(layers, { widget = region(space(rect.w, rect.h), { kind = "noop" }, nil, "sheet"), x = rect.x, y = rect.y })
            for _i, l in ipairs(sheet_layers) do table.insert(layers, l) end
        end
        return BoardUI.overlay(screen_w, screen_h, layers)
    end)
    local out = env
    env = nil
    if not ok then error(result, 0) end
    local rows = {}
    for _i, key in ipairs(out.row_list) do
        local list = out.rows[key]
        if list and #list > 0 then list.id = key; table.insert(rows, list) end
    end
    return result, rows, out.regions
end


-- For pieces built outside a page build.
ListView.region = function(...) return region(...) end
ListView.cover = function(...) return cover(...) end
ListView.layered = layered
ListView.bar = bar
ListView.doneDot = doneDot
ListView.textWidth = textWidth
ListView.runsWidth = runsWidth
ListView.caption = function(...) return caption(...) end
ListView.mark = function(...) return mark(...) end
ListView.rule = rule

-- ================================================================ the page
-- What the library page holds and how many books fit one screen.

-- How the page is laid out on this screen. o: rail (A-Z index), view
-- ("list" or "grid"), min_row.
function ListView.geometry(screen_w, screen_h, o)
    local f = ListView.frame(screen_w, screen_h, { toolbar = true })
    if o.view == "grid" then
        local gw = f.w - (o.rail and ListView.RAIL_W() or 0)
        local g = ListView.gridGeom(gw, f.content_h - px(6), { cols = ListView.gridCols(gw) })
        return { f = f, g = g, gw = gw, per = g.per }
    end
    local total = f.w - (o.rail and ListView.RAIL_W() or 0)
    local cols = o.cols or ListView.indexColumns(total)
    local rows = ListData.fillRows(f.content_h, px(o.min_row or ListView.ROW))
    return { f = f, cols = cols, n = rows.n, rh = rows.rh, per = rows.n * cols }
end

-- Books per screen.
function ListView.capacity(screen_w, screen_h, o)
    return ListView.geometry(screen_w, screen_h, o).per
end

-- A page of books as rows or a grid. m: view, entries, rail, letters, present,
-- groupOf, screen_w, screen_h, gutter, action(book, index), empty.
function ListView.booksBody(m, f)
    if #m.entries == 0 and m.empty then
        return ListView.empty(f.w, f.content_h, m.empty)
    end
    if m.view == "grid" then
        local geo = ListView.geometry(m.screen_w, m.screen_h, { rail = m.rail, view = "grid" })
        local g = geo.g
        local grid = ListView.cellsGrid(geo.gw, g, m.entries, function(b) return ListView.bookCell(g, b, { select = m.select, selected = m.selected and m.selected(b) }) end, m.action)
        local body = vstack({ w = geo.gw }, { space(nil, px(6)), grid })
        if m.rail then return ListView.withRail(f.w, f.content_h, body, m.letters, m.present) end
        return body
    end
    local geo = ListView.geometry(m.screen_w, m.screen_h, { rail = m.rail, view = "list" })
    return ListView.indexList(f.w, f.content_h, {
        entries = m.entries, rows_per_col = geo.n, row_h = geo.rh, cols = geo.cols, gutter = m.gutter or 34,
        rail = m.rail, groupOf = m.groupOf,
        row = function(w, hh, b) return ListView.bookRow(w, hh, b, { select = m.select, selected = m.selected and m.selected(b) }) end,
        action = m.action, present = m.present, letters = m.letters, first_only = m.first_only,
    })
end

-- --------------------------------------------------------------- sheets
-- Sort and filter, from the toolbar. sheet: { title, sorts = { labels,
-- selected }, order = { labels, selected } or nil, shows = { labels, selected },
-- rows = { { icon, label, value, toggle, chevron, action, key } }, note }.
function ListView.sortSheet(sheet)
    return function(screen_w, screen_h)
        return ListView.sheet(screen_w, screen_h, { kind = "top", pop_w = 460, top = px(112), build = function(inner)
            local items = {
                ListView.sheetHead(inner, sheet.title, region(ListView.pill(_("Done"), { h = 36, s = 14, pad_x = 16 }), { kind = "sheet-done" }, "sheet-head", "done")),
                ListView.sheetLabel(inner, _("Sort by")),
                ListView.segmented(inner, sheet.sorts.labels, sheet.sorts.selected, function(i) return { kind = "sheet-sort", index = i } end, { h = 40, s = 13, row = "sheet-sort", key = "sort" }),
            }
            if sheet.order then
                table.insert(items, ListView.segmented(inner, sheet.order.labels, sheet.order.selected, function(i) return { kind = "sheet-order", index = i } end, { h = 36, s = 13, row = "sheet-order", key = "order" }))
            end
            table.insert(items, ListView.sheetLabel(inner, _("Show")))
            table.insert(items, ListView.segmented(inner, sheet.shows.labels, sheet.shows.selected, function(i) return { kind = "sheet-show", index = i } end, { h = 40, s = 12, row = "sheet-show", key = "show" }))
            if sheet.rows and #sheet.rows > 0 then
                local rw = inner - 2 * px(16)
                local rows = {}
                for i, r in ipairs(sheet.rows) do
                    table.insert(rows, ListView.groupRow(rw, { icon = r.icon, label = r.label, value = r.value, toggle = r.toggle, chevron = r.chevron, action = r.action, row = "sheet-row-" .. i, key = r.key, h = 50, s = 15 }))
                end
                table.insert(items, ListView.groupCard(inner, rows))
            end
            local reset = region(text(_("Reset to defaults"), { s = 14, b = true }), { kind = "sheet-reset" }, "sheet-foot", "reset")
            table.insert(items, hstack({ w = inner }, { reset, flex(px(8)), text(sheet.note or "", { s = 13, col = INK.g4 }) }))
            return items
        end })
    end
end

-- A list of choices (a collection, a genre, a format), replacing the sort sheet.
function ListView.pickSheet(sheet)
    return function(screen_w, screen_h)
        return ListView.sheet(screen_w, screen_h, { kind = "top", pop_w = 460, top = px(112), build = function(inner, max_body)
            local back = region(hstack({ h = px(32), gap = px(2) }, { icon("chevron-left", px(22), { sw = 2.25 }), text(_("Back"), { s = 14, b = true }) }), { kind = "sheet-back" }, "sheet-head", "pick-back")
            local head = hstack({ w = inner, h = px(32) }, { back, flex(px(8)), text(sheet.title, { s = 18, b = true }), flex(px(8)), space(wOf(back), 1) })
            -- A list too long for one column takes two; one too long for both is
            -- paged, with the pager under the card.
            local n = #sheet.options
            local rowh = px(46)
            local room = max_body or screen_h
            local fixed = px(32) + px(14) + px(8)
            local fits_one = math.floor((room - fixed) / rowh)
            local paged = n > 2 * fits_one
            local per_col = n <= fits_one and n or math.max(3, math.floor((room - fixed - (paged and (px(14) + px(44)) or 0)) / rowh))
            local per_page = n <= fits_one and n or 2 * per_col
            local pages = math.max(1, math.ceil(n / per_page))
            local page = math.max(1, math.min(sheet.page or 1, pages))
            local first, last = (page - 1) * per_page + 1, math.min(n, page * per_page)
            local two = (last - first + 1) > per_col
            local gap = px(12)
            local card_w = two and math.floor((inner - gap) / 2) or inner
            local rw = card_w - 2 * px(16)
            local function card(from, to)
                local rows = {}
                for i = from, to do
                    local o = sheet.options[i]
                    table.insert(rows, ListView.groupRow(rw, { label = o.label, radio = o.on, action = { kind = "sheet-pick", value = o.value }, row = "pick-" .. i, key = "pick-" .. i, h = 46, s = 15, bold = o.on }))
                end
                return ListView.groupCard(card_w, rows)
            end
            local items = { head }
            if two then
                table.insert(items, hstack({ w = inner, valign = "top", gap = gap }, { card(first, first + per_col - 1), card(first + per_col, last) }))
            else
                table.insert(items, card(first, last))
            end
            if pages > 1 then
                local function step(name, delta)
                    return region(hstack({ w = px(52), h = px(44) }, { flex(0), icon(name, px(22), { sw = 2.25 }), flex(0) }),
                        { kind = "sheet-page", delta = delta }, "sheet-pager", "sheet-" .. name)
                end
                local mid = text(page .. " / " .. pages, { s = 14, b = true })
                table.insert(items, hstack({ w = inner, h = px(44) }, { step("chevron-left", -1), flex(0), mid, flex(0), step("chevron-right", 1) }))
            end
            return items
        end })
    end
end

-- Jump: a key for every letter, and a page stepper.
function ListView.jumpSheet(sheet)
    return function(screen_w, screen_h)
        return ListView.sheet(screen_w, screen_h, { kind = "bottom", pop_w = 460, build = function(inner)
            local close = region(hstack({ w = px(44), h = px(44) }, { flex(0), icon("x", px(22), { sw = 2 }), flex(0) }), { kind = "close-sheet" }, "sheet-head", "jump-close")
            local items = { ListView.sheetHead(inner, _("Jump to"), close) }
            if sheet.present then
                table.insert(items, ListView.jumpKeys(inner, sheet.present, sheet.current))
                table.insert(items, ListView.rule(inner))
            end
            table.insert(items, ListView.pageStepper(inner, sheet.page, sheet.pages))
            return items
        end })
    end
end


-- ================================================== a series page
-- Adapted from BookOrbit's series page (list pages module), modified 2026-11-07.
-- Covers stacked up and to the right, each 2:3, the first in front.
local function stackFit(books, w, hh)
    local list = {}
    for i = 1, math.min(3, #(books or {})) do list[i] = books[i] end
    local n = math.max(1, #list)
    local dy = n > 1 and math.max(1, math.floor(hh * 0.07 + 0.5)) or 0
    local ch = hh - dy * (n - 1)
    local cw = math.min(w, math.floor(ch * 2 / 3 + 0.5))
    local dx = n > 1 and math.min(math.floor(cw * 0.42 + 0.5), math.floor((w - cw) / (n - 1))) or 0
    local total = cw + dx * (n - 1)
    local ring = math.max(1, px(1.25))
    local layers = {}
    if #list == 0 then
        table.insert(layers, { widget = BoardUI.rect(cw, ch, INK.ge, px(4)), x = 0, y = 0 })
    end
    for i = #list, 1, -1 do
        table.insert(layers, { widget = cover(list[i], cw, ch), x = (i - 1) * dx, y = (n - i) * dy, ring = ring })
    end
    return layered(total, hh, layers)
end
ListView.stackFit = stackFit

-- ------------------------------------------------------------ a series
-- Where a series page's books go: page 1 under the summary, later pages
-- with the list alone (landscape keeps the summary column on every page).
-- A grid shrinks its covers to keep a series on one page only down to three
-- quarters of the All books size; past that it pages at full size.
function ListView.seriesLayout(screen_w, screen_h, view, n, offline)
    local f = ListView.frame(screen_w, screen_h, { toolbar = false, offline = offline })
    local side = BoardMetrics.get().w > BoardMetrics.get().h
    local side_w = side and math.floor(f.w * 0.38 + 0.5) or f.w
    local list_w = side and (f.w - side_w - px(28)) or f.w
    local hero_h = side and f.content_h or math.max(px(156), math.min(px(200), math.floor(f.content_h * 0.27 + 0.5)))
    local head = px(44) + px(8)
    local h1 = (side and f.content_h or (f.content_h - hero_h - px(16))) - head
    local hn = side and h1 or (f.content_h - head)
    local cap1, capn, g1, gn
    if view == "grid" then
        local std = ListView.stdGeom(screen_w, screen_h)
        local cols = ListView.gridCols(list_w)
        local function cap(h) return cols * math.max(1, math.floor((h + px(18)) / (std.cover_h + ListView.CAP() + px(18)))) end
        local fit = ListView.fitStd(screen_w, screen_h, list_w, h1, n)
        if fit.cover_h >= std.cover_h * 0.75 then
            return { pages = 1, first = n, rest = n, list_w = list_w, list_h1 = h1, list_hn = hn, g1 = fit, single = true }
        end
        cap1, capn = cap(h1), cap(hn)
        g1 = ListView.fitStd(screen_w, screen_h, list_w, nil, 1)
        gn = g1
    else
        cap1 = ListData.fillRows(h1, px(56)).n
        capn = ListData.fillRows(hn, px(56)).n
    end
    local pages = n <= cap1 and 1 or (1 + math.ceil((n - cap1) / capn))
    return { pages = pages, first = cap1, rest = capn, list_w = list_w, list_h1 = h1, list_hn = hn, g1 = g1, gn = gn }
end

-- The stack, how far through it you are as a ruler of its books, Up next and
-- Continue; then its books in reading order, as rows or covers. Landscape
-- puts the summary beside the books.
function ListView.seriesBody(m, f)
    local all_books = m.entries
    local layout = ListView.seriesLayout(m.screen_w, m.screen_h, m.view, #all_books, m.offline ~= nil)
    local page = math.max(1, math.min(layout.pages, m.local_page or 1))
    local books = {}
    local start = page == 1 and 1 or (layout.first + (page - 2) * layout.rest + 1)
    local stop = page == 1 and layout.first or (start + layout.rest - 1)
    for i = start, math.min(#all_books, stop) do table.insert(books, all_books[i]) end
    local next_book = m.next_book
    local side = BoardMetrics.get().w > BoardMetrics.get().h
    local side_w = side and math.floor(f.w * 0.38 + 0.5) or f.w
    local list_w = side and (f.w - side_w - px(28)) or f.w
    local hero_h = side and f.content_h or math.max(px(156), math.min(px(200), math.floor(f.content_h * 0.27 + 0.5)))
    local deck_h = side and math.min(px(220), math.floor(f.content_h * 0.42 + 0.5)) or hero_h
    local deck_w = math.floor(deck_h * 0.74 + 0.5)
    local tw = side and side_w or (f.w - deck_w - px(20))
    local states = m.states or {}
    local n = math.max(1, #states)
    local gap = px(4)
    local seg_w = math.floor((tw - (n - 1) * gap) / n)
    local cur = m.current_index
    local segs, nums = {}, {}
    for i, s in ipairs(states) do
        local h = px(i == cur and 10 or 8)
        local col = s == "finished" and INK.black or s == "reading" and INK.g8 or INK.gd
        local seg = BoardUI.rect(seg_w, h, col, px(5))
        if i == cur then
            local r1, r2 = math.max(1, px(1.5)), math.max(2, px(3))
            seg = BoardUI.overlay(seg_w + 2 * r2, h + 2 * r2, {
                { widget = BoardUI.rect(seg_w + 2 * r2, h + 2 * r2, INK.black, px(5) + r2) },
                { widget = BoardUI.rect(seg_w + 2 * r1, h + 2 * r1, INK.white, px(5) + r1), x = r2 - r1, y = r2 - r1 },
                { widget = BoardUI.rect(seg_w, h, col, px(5)), x = r2, y = r2 },
            })
        end
        table.insert(segs, seg)
        if seg_w >= px(16) then
            table.insert(nums, text(tostring(m.indexes and m.indexes[i] or i), { s = 11, b = i == cur, col = i == cur and INK.black or INK.g4, w = seg_w, align = "center" }))
        end
    end
    local seg_row = {}
    for i, s in ipairs(segs) do
        local sw = wOf(s)
        local pad = math.floor((sw - seg_w) / 2)
        table.insert(seg_row, BoardUI.overlay(seg_w, px(10), { { widget = s, x = -pad, y = math.floor((px(10) - hOf(s)) / 2) } }))
    end
    local p = m.progress
    -- level 1 gives the next title one line, level 2 also drops the ruler's
    -- numbers: a short screen at a large interface size keeps the summary
    -- inside its band instead of pushing it into the header. live = false
    -- measures without making the button tappable.
    local function summaryOf(level, live)
        local with_nums = #nums > 0 and level < 2
        local ruler = vstack({ w = tw }, {
            hstack({ gap = gap, h = px(10) }, seg_row),
            with_nums and space(nil, px(4)) or false,
            with_nums and hstack({ gap = gap }, nums) or false,
        })
        local summary = {
            runs({ { t = T(_("%1 of %2 read"), p.finished, p.count), b = true, col = INK.black, s = 19 }, { t = "   " .. T(_("%1 in progress"), p.reading) } }, { s = 13, col = INK.g4, w = tw }),
            space(nil, px(8)), ruler, space(nil, level > 0 and px(12) or (px(8) + px(4) + px(8))),
        }
        if next_book then
            table.insert(summary, text(next_book.seriesIndex and T(_("Up next · Book %1"), tostring(next_book.seriesIndex)) or _("Up next"), { s = 12, b = true, col = INK.g4, w = tw }))
            table.insert(summary, space(nil, px(level > 0 and 4 or 8)))
            table.insert(summary, text(next_book.title or "", { s = 16, b = true, lines = level == 0 and 2 or nil, w = tw, data = true }))
            table.insert(summary, space(nil, px(8)))
            local pill = ListView.pill(ListData.stateOf(next_book) == "reading" and _("Continue") or (next_book.seriesIndex and T(_("Start book %1"), tostring(next_book.seriesIndex)) or _("Start book")), { icon = "book-open", h = 40, s = 14, pad_x = 18 })
            local cont = live and region(pill, m.open_action and m.open_action(next_book) or { kind = "book", book = next_book }, "series-hero", "continue") or pill
            local right = nil
            if ListData.stateOf(next_book) == "reading" then
                local left = m.next_minutes and (" · " .. T(_("%1 left"), ListData.duration(m.next_minutes))) or (" · " .. (require("aleph_board_data").relativeDay(next_book.lastReadAt) or ""))
                right = runs({ { t = ListData.pctLabel(next_book) or "0%", b = true, col = INK.black }, { t = left } }, { s = 13, col = INK.g4, data = true })
            end
            table.insert(summary, hstack({ gap = px(12) }, { cont, right or false }))
        end
        return vstack({ w = tw }, summary)
    end
    local level = 0
    if not side then
        while level < 2 do
            -- Measured only; its ruler pieces are reused, so it is not freed.
            if hOf(summaryOf(level, false)) <= hero_h then break end
            level = level + 1
        end
    end
    local summary_col = summaryOf(level, true)
    local deck = region(hstack({ w = side and side_w or deck_w, h = deck_h, valign = "bottom" }, { side and space(1, 1) or flex(0), ListView.stackFit(m.deck or books, deck_w, deck_h), flex(0) }),
        next_book and (m.open_action and m.open_action(next_book) or { kind = "book", book = next_book }) or { kind = "noop" }, "series-hero", "deck")
    local hero
    if side then
        hero = vstack({ w = side_w, h = hero_h }, { space(nil, px(6)), deck, space(nil, px(18)), summary_col, flex(0) })
    else
        hero = hstack({ w = f.w, h = hero_h, gap = px(20) }, { deck, vstack({ w = tw, h = hero_h }, { flex(0), summary_col, flex(0) }) })
    end
    local head = ListView.sectionHead(list_w, { icon = "layers-2", label = m.order_label or _("Reading order"), count = #all_books, right = ListView.viewToggle(m.view, "series-head") })
    local list_h = page == 1 and layout.list_h1 or layout.list_hn
    local content
    if m.view == "grid" then
        local g = layout.single and layout.g1 or ListView.fitStd(m.screen_w, m.screen_h, list_w, nil, 1)
        local short = ListData.distinctTitles(books)
        content = ListView.cellsGrid(list_w, g, books, function(b)
            return ListView.bookCell(g, b, {
                select = m.select, selected = m.selected and m.selected(b),
                title = function(x) return x.seriesIndex and (tostring(x.seriesIndex) .. ". " .. (short[x.id] or x.title or "")) or (short[x.id] or x.title or "") end,
                meta = function(x)
                    local st = ListData.stateOf(x)
                    if st == "reading" then
                        local ml = m.minutes_left and m.minutes_left(x)
                        local day = not ml and require("aleph_board_data").relativeDay(x.lastReadAt)
                        return { { t = ListData.pctLabel(x) or "0%", b = true }, { t = ml and T(_(" · %1 left"), ListData.shortDuration(ml)) or day and (" · " .. day) or "" } }
                    elseif st == "finished" then return { { t = _("Read"), b = true } } end
                    return { { t = _("Not started") } }
                end,
            })
        end, m.action)
    else
        local rows = ListData.fillRows(list_h, px(56))
        content = ListView.indexList(list_w, list_h, {
            entries = books, rows_per_col = rows.n, row_h = rows.rh, cols = 1, gutter = 34, rail = false,
            groupOf = function(b) return "#" .. tostring(b.seriesIndex or "") end, group_rules = false,
            row = function(w, hh, b) return ListView.bookRow(w, hh, b, { context = "series", select = m.select, selected = m.selected and m.selected(b) }) end, action = m.action,
        })
    end
    local list = vstack({ w = list_w }, { head, space(nil, px(8)), content })
    if side then return hstack({ w = f.w, valign = "top", gap = px(28) }, { hero, list }) end
    if page > 1 then return vstack({ w = f.w }, { list }) end
    return vstack({ w = f.w }, { space(nil, px(4)), hero, space(nil, px(12)), list })
end



-- ============================================ the authors and series lists
-- Adapted from BookOrbit's author and series rows and cells (list view) and its
-- paged list body (list pages), modified 2026-11-07. Local libraries have no
-- author portraits, so an author is shown by the covers of their books.

-- Overlapping covers, the first in front, each a little smaller behind.
local function fan(books, cover_h, o)
    o = o or {}
    local cw = math.floor(cover_h * 2 / 3 + 0.5)
    local list = {}
    for i = 1, math.min(o.max or 3, #(books or {})) do list[i] = books[i] end
    local step = math.floor(cw * (o.step or 0.42) + 0.5)
    local width = cw + step * math.max(0, #list - 1)
    local ring = math.max(1, px(1.25))
    local shrink = o.shrink or 0.08
    local layers = {}
    if #list == 0 then
        table.insert(layers, { widget = BoardUI.rect(cw, cover_h, INK.ge, px(4)), x = 0, y = 0 })
    end
    for i = #list, 1, -1 do
        local s = 1 - shrink * (i - 1)
        local ch, cww = math.floor(cover_h * s + 0.5), math.floor(cw * s + 0.5)
        table.insert(layers, { widget = cover(list[i], cww, ch), x = (i - 1) * step, y = math.floor((cover_h - ch) / 2 + 0.5), ring = ring })
    end
    return layered(width, cover_h, layers)
end

-- One segment per book along a cover's foot: read black, reading gray.
local function seriesStrip(w, states)
    local h = math.max(3, px(5))
    local edge = math.max(1, px(0.75))
    local n = math.max(1, #states)
    local gap = n <= 14 and math.max(1, px(1.5)) or 0
    local seg = (w - (n - 1) * gap) / n
    local layers = { { widget = BoardUI.rect(w, h, INK.white) } }
    for i, s in ipairs(states) do
        local x0 = math.floor((i - 1) * (seg + gap) + 0.5)
        local x1 = math.floor((i - 1) * (seg + gap) + seg + 0.5)
        local col = s == "finished" and INK.black or s == "reading" and INK.g8 or nil
        if col then table.insert(layers, { widget = BoardUI.rect(x1 - x0, h, col), x = x0 }) end
    end
    return vstack({ w = w }, { BoardUI.rect(w, edge, INK.black), BoardUI.overlay(w, h, layers) }), h + edge
end

-- A series bar for a row: one segment a book, read black, reading gray.
local function seriesBar(bw, states)
    local n = math.max(1, #states)
    local gap = n <= 14 and math.max(1, px(2)) or 0
    local seg = (bw - (n - 1) * gap) / n
    local layers = {}
    for i, s in ipairs(states) do
        local x0 = math.floor((i - 1) * (seg + gap) + 0.5)
        local x1 = math.floor((i - 1) * (seg + gap) + seg + 0.5)
        local col = s == "finished" and INK.black or s == "reading" and INK.g8 or INK.gd
        table.insert(layers, { widget = BoardUI.rect(x1 - x0, px(6), col, px(2)), x = x0 })
    end
    return BoardUI.overlay(bw, px(6), layers)
end

function ListView.authorRow(w, hh, a)
    local vh = hh - px(14)
    -- A downloaded portrait (Settings > Author portraits), else the author's covers.
    local pic
    if a.portrait then
        local ok_p, Portraits = pcall(require, "aleph_portraits")
        if ok_p then pic = Portraits.widget(a.portrait, math.min(VW(), vh)) end
    end
    pic = pic or stackFit(a.previewBooks or {}, VW(), vh)
    local sw = statusWidth(w)
    local c = ListData.authorCell(a)
    local right
    if c then
        local top
        if c.kind == "finished" then top = doneTop(sw, c.label)
        else top = text(c.label, { s = 14, b = true, w = sw, align = "right" }) end
        right = cell(sw, top, c.bottom)
    end
    local tw = w - VW() - px(12) - (right and (sw + px(10)) or 0)
    return hstack({ w = w, h = hh - 1 }, { pictureCol(hh, pic), space(px(12), 1), textCol(tw, a.title or "", ListData.authorSecond(a)), right and space(px(10), 1) or false, right or false })
end

function ListView.seriesRow(w, hh, s)
    local sw = statusWidth(w)
    local p = ListData.seriesProgress(s)
    local right
    if p.count > 1 and (p.finished > 0 or p.reading > 0) then
        local label, strong = ListData.seriesBarLabel(p)
        right = vstack({ w = sw, align = "right" }, {
            seriesBar(math.min(sw, px(64)), p.states),
            space(nil, px(6)),
            text(label, { s = 12, b = strong, col = strong and INK.black or INK.g4, w = sw, align = "right" }),
        })
    elseif p.count == 1 and s.previewBooks and s.previewBooks[1] and ListData.stateOf(s.previewBooks[1]) ~= "unread" then
        right = statusCell(s.previewBooks[1], sw)
    end
    local tw = w - VW() - px(12) - (right and (sw + px(10)) or 0)
    local who = ListData.seriesWho(s)
    local second = (who and (who .. " · ") or "") .. ListData.seriesCounts(s)
    return hstack({ w = w, h = hh - 1 }, { pictureCol(hh, stackFit(s.previewBooks or {}, VW(), hh - px(14))), space(px(12), 1), textCol(tw, s.title or "", second), right and space(px(10), 1) or false, right or false })
end

function ListView.seriesCell(g, s)
    local p = ListData.seriesProgress(s)
    local previews = s.previewBooks or {}
    local box
    if (tonumber(s.count) or #previews) < 2 or #previews < 2 then
        box = previews[1] and markedCover(previews[1], g.cover_w, g.cover_h)
            or BoardUI.box({ w = g.cover_w, h = g.cover_h, border = math.max(1, px(0.75)), border_col = INK.gb, bg = INK.ge }, space(1, 1))
    else
        -- The next books sit behind the first as neat sheets, up and right.
        local off = math.max(2, math.floor(g.cover_w * 0.05 + 0.5))
        local fw, fh = g.cover_w - 2 * off, g.cover_h - 2 * off
        local ring = math.max(1, px(1.25))
        local layers = {}
        for i = math.min(3, #previews), 1, -1 do
            local w
            if i == 1 then
                local front = { { widget = cover(previews[1], fw, fh) } }
                if not p.all_done and (p.finished > 0 or p.reading > 0) then
                    local st, sh = seriesStrip(fw, p.states)
                    table.insert(front, { widget = st, x = 0, y = fh - sh })
                end
                if p.all_done then
                    local m, S = readMark(fw)
                    table.insert(front, { widget = m, x = fw - S, y = 0 })
                end
                w = BoardUI.overlay(fw, fh, front)
            else
                w = cover(previews[i], fw, fh)
            end
            table.insert(layers, { widget = w, x = (i - 1) * off, y = (3 - i) * off, ring = ring })
        end
        box = layered(g.cover_w, g.cover_h, layers)
    end
    local inner = vstack({ w = g.cover_w }, { box, space(nil, px(8)), caption(g.cover_w, s.title or "", ListData.seriesMeta(s)) })
    return hstack({ w = g.cw }, { flex(0), inner, flex(0) })
end

function ListView.authorCell(g, a)
    local side = g.cover_w
    local books = a.previewBooks or {}
    local n = math.min(3, #books)
    local cw = math.floor(side * 2 / 3 + 0.5)
    local step = n > 1 and ((side - cw) / (n - 1) / cw) or 0.42
    local pic = fan(books, side, { step = step, shrink = 0.06 })
    if a.portrait then
        local ok_p, Portraits = pcall(require, "aleph_portraits")
        if ok_p then pic = Portraits.widget(a.portrait, side) end
    end
    local variants = ListData.authorMetaVariants(a)
    local meta = variants[#variants]
    for _i, v in ipairs(variants) do
        if runsWidth(v, { s = 11 }) <= side then meta = v; break end
    end
    local inner = vstack({ w = side, align = "center" }, { hstack({ w = side, h = side, valign = "bottom" }, { flex(0), pic, flex(0) }), space(nil, px(8)), caption(side, a.title or "", meta, { center = true }) })
    return hstack({ w = g.cw }, { flex(0), inner, flex(0) })
end

-- How an authors or series list is laid out. o: rail, view, kind.
function ListView.groupsGeometry(screen_w, screen_h, o)
    local f = ListView.frame(screen_w, screen_h, { toolbar = true })
    if o.view == "grid" then
        local gw = f.w - (o.rail and ListView.RAIL_W() or 0)
        local g = ListView.gridGeom(gw, f.content_h - px(6), { cols = ListView.gridCols(gw), aspect = o.kind == "authors" and 1 or 1.5 })
        return { f = f, g = g, gw = gw, per = g.per }
    end
    local total = f.w - (o.rail and ListView.RAIL_W() or 0)
    local cols = ListView.indexColumns(total)
    local rows = ListData.fillRows(f.content_h, px(ListView.ROW))
    return { f = f, cols = cols, n = rows.n, rh = rows.rh, per = rows.n * cols }
end

-- A page of authors or series as rows or a grid. m: kind, view, entries, rail,
-- letters, present, groupOf, screen_w, screen_h, action(entry), empty.
function ListView.groupsBody(m, f)
    if #m.entries == 0 and m.empty then
        return ListView.empty(f.w, f.content_h, m.empty)
    end
    if m.view == "grid" then
        local geo = ListView.groupsGeometry(m.screen_w, m.screen_h, { rail = m.rail, view = "grid", kind = m.kind })
        local g = geo.g
        local build = m.kind == "authors" and function(e) return ListView.authorCell(g, e) end
            or function(e) return ListView.seriesCell(g, e) end
        local grid = ListView.cellsGrid(geo.gw, g, m.entries, build, m.action)
        local body = vstack({ w = geo.gw }, { space(nil, px(6)), grid })
        if m.rail then return ListView.withRail(f.w, f.content_h, body, m.letters, m.present) end
        return body
    end
    local geo = ListView.groupsGeometry(m.screen_w, m.screen_h, { rail = m.rail, view = "list", kind = m.kind })
    local row = m.kind == "authors" and function(w, hh, e) return ListView.authorRow(w, hh, e) end
        or function(w, hh, e) return ListView.seriesRow(w, hh, e) end
    return ListView.indexList(f.w, f.content_h, {
        entries = m.entries, rows_per_col = geo.n, row_h = geo.rh, cols = geo.cols, gutter = m.gutter or 34,
        rail = m.rail, groupOf = m.groupOf, row = row, action = m.action,
        present = m.present, letters = m.letters, first_only = m.first_only,
    })
end


-- ======================================== a sheet over the book page
-- A page's own sheet in the same frame as the library's: options in a card,
-- with a title and a close button. `sheet`: title, sub, rows, foot, empty,
-- page. A row: label, icon, value, radio, toggle, chevron, bold, action.
-- Too many rows for the screen are paged, with a pager under the card.
function ListView.optionsSheet(sheet)
    return function(screen_w, screen_h)
        return ListView.sheet(screen_w, screen_h, { kind = "bottom", pop_w = 460, build = function(inner, max_body)
            local close = region(hstack({ w = px(44), h = px(44) }, { flex(0), icon("x", px(22), { sw = 2 }), flex(0) }), { kind = "close-sheet" }, "sheet-head", "sheet-close")
            local head = sheetHead(inner, sheet.title, close)
            local items = { head }
            local sub
            if sheet.sub then
                sub = text(sheet.sub, { s = 13, col = INK.g4, w = inner, data = true })
                table.insert(items, sub)
            end
            local rows = sheet.rows or {}
            local row_h = 52
            local foot_h = sheet.foot and (#sheet.foot * px(row_h) + px(14)) or 0
            local budget = (max_body or screen_h) - hOf(head) - (sub and (hOf(sub) + px(14)) or 0) - foot_h - px(14) - px(36)
            local per = math.max(3, math.floor(budget / px(row_h)))
            local paged = #rows > per
            if paged then per = math.max(3, math.floor((budget - px(52)) / px(row_h))) end
            local pages = math.max(1, math.ceil(#rows / per))
            local page = math.max(1, math.min(sheet.page or 1, pages))
            local rw = inner - 2 * px(16)
            if #rows == 0 and sheet.empty then
                table.insert(items, text(sheet.empty, { s = 14, col = INK.g4, w = inner }))
            else
                local cards = {}
                for i = (page - 1) * per + 1, math.min(#rows, page * per) do
                    local r = rows[i]
                    table.insert(cards, ListView.groupRow(rw, { label = r.label, icon = r.icon, value = r.value, radio = r.radio,
                        toggle = r.toggle, chevron = r.chevron, bold = r.bold, action = r.action,
                        row = "opt-" .. i, key = "opt-" .. i, h = row_h, s = 15 }))
                end
                table.insert(items, ListView.groupCard(inner, cards))
            end
            if paged then
                local function step(name, delta)
                    return region(hstack({ w = px(52), h = px(44) }, { flex(0), icon(name, px(22), { sw = 2.25 }), flex(0) }),
                        { kind = "sheet-page", delta = delta }, "sheet-pager", "sheet-" .. name)
                end
                local mid = text(page .. " / " .. pages, { s = 14, b = true })
                table.insert(items, hstack({ w = inner, h = px(44) }, { step("chevron-left", -1), flex(0), mid, flex(0), step("chevron-right", 1) }))
            end
            if sheet.foot then
                local foot = {}
                for i, r in ipairs(sheet.foot) do
                    table.insert(foot, ListView.groupRow(rw, { label = r.label, icon = r.icon, chevron = r.chevron, action = r.action,
                        row = "foot-" .. i, key = "foot-" .. i, h = row_h, s = 15 }))
                end
                table.insert(items, ListView.groupCard(inner, foot))
            end
            return items
        end })
    end
end

-- Draws `sheet` (from optionsSheet or another sheet builder) over `page`: a tap
-- anywhere outside it closes it and reaches nothing underneath. `run(action)`
-- handles the sheet's taps.
function ListView.withSheet(screen_w, screen_h, page, sheet, run)
    local saved = env
    env = { rows = {}, row_seen = {}, row_list = {}, regions = {}, run = run }
    local ok, result = pcall(function()
        local layers = { { widget = page } }
        table.insert(layers, { widget = region(space(screen_w, screen_h), { kind = "close-sheet" }, nil, "outside") })
        table.insert(layers, { widget = Scrim:new{ dimen = Geom:new{ w = screen_w, h = screen_h } } })
        local sheet_layers, rect = sheet(screen_w, screen_h)
        table.insert(layers, { widget = region(space(rect.w, rect.h), { kind = "noop" }, nil, "sheet"), x = rect.x, y = rect.y })
        for _i, l in ipairs(sheet_layers) do table.insert(layers, l) end
        return BoardUI.overlay(screen_w, screen_h, layers)
    end)
    env = saved
    if not ok then error(result, 0) end
    return result
end

return ListView
