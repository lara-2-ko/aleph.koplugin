-- Aleph modification, 2026-11-09: the settings page of the stats at the
-- top and bottom of book pages (aleph_bookends.lua).
--[[--
A page in the board's style: a preview of a book page with its top and bottom
lines drawn from sample values, then three tabs.

  Top      show it; what the left, middle and right show; its distance
           from the top edge; the line under it (None / Progress / Chapters)
  Bottom   show it; left, middle and right; its distance from the bottom
  Look     text size, colour (three grays, or one's own on a colour
           screen) and weight (regular or bold); hide KOReader's own status bar; book margins on or off;
           reset

A slot opens a sheet of every item as a chip: tap to add (in the order tapped,
up to three, numbered on the chip), tap again to remove. In a book the page
behind updates as you change things.
]]

local Geom = require("ui/geometry")
local UIManager = require("ui/uimanager")
local T = require("ffi/util").template
local _ = require("gettext")

local BoardMetrics = require("aleph_board_metrics")
local BoardUI = require("aleph_board_ui")
local Bookends = require("aleph_bookends")
local MenuPage = require("aleph_menu_page")
local MenuUI = require("aleph_menu_ui")
local SheetUI = require("aleph_sheet_ui")

local INK = BoardMetrics.INK
local px = BoardMetrics.px
local text, vstack, hstack, space, flex, icon = BoardUI.text, BoardUI.vstack, BoardUI.hstack, BoardUI.space, BoardUI.flex, BoardUI.icon
local floor = math.floor

local Page = {}

local SLOTS = { "left", "middle", "right" }
local SLOT_LABELS = {
    left = function() return _("Left") end, middle = function() return _("Middle") end, right = function() return _("Right") end,
}
local EDGE_LABELS = { top = function() return _("Top") end, bottom = function() return _("Bottom") end }

local function hOf(widget) return widget:getSize().h end
local function wOf(widget) return widget:getSize().w end

local function summary(list)
    if not list or #list == 0 then return _("Nothing") end
    local names = {}
    for _i, id in ipairs(list) do names[#names + 1] = Bookends.ITEM_BY_ID[id].label() end
    return table.concat(names, " · ")
end
Page.summary = summary

-- ---------------------------------------------------------------- preview
-- A book page in miniature with sample values in its margins.
local function sampleSlot(list, size, max_w, ink, bold)
    local col = ink.col
    local parts = {}
    for _i, id in ipairs(list or {}) do
        local it = Bookends.ITEM_BY_ID[id]
        local str = it.sample
        if id == "clock" then str = require("datetime").secondsToHour(os.time(), G_reader_settings:isTrue("twelve_hour_clock")) end
        local sw = bold and 2.75 or 2.25
        if id == "wifi" then parts[#parts + 1] = icon("wifi", px(size + 2), { sw = sw, col = ink.hex })
        elseif id == "light" then parts[#parts + 1] = icon("sun", px(size + 2), { sw = sw, col = ink.hex }); parts[#parts + 1] = text(str, { s = size, col = col, b = bold })
        else
            if id == "battery" then parts[#parts + 1] = Bookends.batteryWidget({ battery = 88 }, size, col, ink.hex) end
            local t = text(str, { s = size, col = col, b = bold, data = true })
            if wOf(t) > max_w then t:free(); t = text(str, { s = size, col = col, b = bold, w = max_w, data = true }) end
            parts[#parts + 1] = t
        end
    end
    if #parts == 0 then return nil end
    return hstack({ gap = px(4) }, parts)
end

local function preview(page, w)
    local c = page.config
    local size = math.max(10, Bookends.SIZES[c.size] - 2)
    local h = px(150)
    local inner_w = w - 2 * px(16)
    local layers = {}
    local ink = Bookends.ink(c)
    local function band(slots, y)
        local side = floor(inner_w / 3) - px(4)
        local l = sampleSlot(slots.left, size, side, ink, c.bold)
        local m = sampleSlot(slots.middle, size, side, ink, c.bold)
        local r = sampleSlot(slots.right, size, side, ink, c.bold)
        if l then layers[#layers + 1] = { widget = l, x = px(16), y = y } end
        if m then layers[#layers + 1] = { widget = m, x = floor((w - wOf(m)) / 2), y = y } end
        if r then layers[#layers + 1] = { widget = r, x = w - px(16) - wOf(r), y = y } end
    end
    local y = px(10)
    if c.top then
        band(c.slots.top, y)
        y = y + BoardMetrics.lh1(size) + px(4)
        if c.line ~= "none" then
            layers[#layers + 1] = { widget = BoardUI.rect(inner_w, math.max(1, px(1)), INK.gb), x = px(16), y = y }
            layers[#layers + 1] = { widget = BoardUI.rect(floor(inner_w * 0.4), math.max(2, px(2)), INK.g3), x = px(16), y = y }
            if c.line == "chapters" then
                for i = 1, 6 do
                    layers[#layers + 1] = { widget = BoardUI.rect(math.max(1, px(1)), px(6), INK.g5), x = px(16) + floor(inner_w * i / 7), y = y - px(2) }
                end
            end
        end
        y = y + px(10)
    end
    -- The page's text as gray lines.
    local bottom_y = h - px(10) - BoardMetrics.lh1(size)
    local line_y = y + px(6)
    while line_y + px(4) < (c.bottom and bottom_y - px(10) or h - px(12)) do
        layers[#layers + 1] = { widget = BoardUI.rect(inner_w - ((line_y % 3 == 0) and px(40) or 0), px(4), INK.ge, px(2)), x = px(16), y = line_y }
        line_y = line_y + px(11)
    end
    if c.bottom then band(c.slots.bottom, bottom_y) end
    local frame = BoardUI.box({ w = w, h = h, radius = px(10), border = math.max(1, px(1.5)), border_col = INK.black, bg = INK.white })
    table.insert(layers, 1, { widget = frame })
    return BoardUI.overlay(w, h, layers)
end

-- ------------------------------------------------------------------- tabs
local function slotRows(page, iw, edge)
    local c = page.config
    local rows = {
        MenuUI.row(iw, { icon = edge == "top" and "chevron-up" or "chevron-down", label = edge == "top" and _("Show at the top") or _("Show at the bottom"),
            toggle = c[edge] == true, action = { kind = "edge", edge = edge } }),
    }
    for _i, slot in ipairs(SLOTS) do
        rows[#rows + 1] = MenuUI.row(iw, { label = SLOT_LABELS[slot](), sub = summary(c.slots[edge][slot]), sub_data = true,
            chevron = c[edge], h = 58, action = c[edge] and { kind = "slot", edge = edge, slot = slot } or { kind = "noop" } })
    end
    return rows
end

-- Where a line sits: nearer the edge of the screen or further in.
local function offsetRow(c, iw, key)
    local v = c[key] or 0
    local shown = v == 0 and "0" or (v > 0 and ("+" .. v) or tostring(v))
    local minus = v > Bookends.OFFSET_MIN and { kind = "offset", key = key, delta = -Bookends.OFFSET_STEP } or nil
    local plus = v < Bookends.OFFSET_MAX and { kind = "offset", key = key, delta = Bookends.OFFSET_STEP } or nil
    return MenuUI.row(iw, { icon = key == "top_offset" and "arrow-down" or "arrow-up",
        label = key == "top_offset" and _("Distance from the top") or _("Distance from the bottom"),
        sub = _("+ moves the line in, away from the edge"), h = 64, trail = MenuUI.stepper(shown, nil, minus, plus) })
end

local function body(page, w, compact)
    local c = page.config
    local iw = MenuUI.rowsIn(w)
    local tab = page.tab or "top"
    local tabs = MenuUI.segmented(w, { _("Top"), _("Bottom"), _("Look") }, tab == "top" and 1 or tab == "bottom" and 2 or 3,
        function(index) return { kind = "tab", tab = index == 1 and "top" or index == 2 and "bottom" or "look" } end)
    local items = {}
    if not compact then items[#items + 1] = preview(page, w); items[#items + 1] = space(nil, px(14)) end
    items[#items + 1] = tabs
    items[#items + 1] = space(nil, px(12))
    if tab == "top" or tab == "bottom" then
        items[#items + 1] = MenuUI.group(w, slotRows(page, iw, tab))
        if c[tab] then
            items[#items + 1] = space(nil, px(12))
            items[#items + 1] = MenuUI.group(w, { offsetRow(c, iw, tab == "top" and "top_offset" or "bottom_offset") })
        end
        if tab == "top" then
            local lines = { _("No line"), _("Progress"), _("Chapters") }
            local at = c.line == "progress" and 2 or c.line == "chapters" and 3 or 1
            items[#items + 1] = space(nil, px(12))
            items[#items + 1] = MenuUI.section(w, _("Line under the top"), MenuUI.segmented(w, lines, at,
                function(index) return { kind = "line", value = Bookends.LINES[index] } end))
        end
    else
        local sizes = { _("Small"), _("Medium"), _("Large") }
        local at = c.size == "medium" and 2 or c.size == "large" and 3 or 1
        local on = Bookends.enabledHere()
        items[#items + 1] = MenuUI.section(w, _("Text size"), MenuUI.segmented(w, sizes, at,
            function(index) return { kind = "size", value = index == 1 and "small" or index == 2 and "medium" or "large" } end))
        items[#items + 1] = space(nil, px(12))
        -- The text's colour: three grays, and a colour of one's own on a
        -- colour screen (or when one was chosen there).
        local inks = { _("Light gray"), _("Gray"), _("Black") }
        local custom = Bookends.colourScreen() or c.ink == "custom"
        if custom then inks[4] = _("Colour") end
        local ink_at = ({ light = 1, gray = 2, black = 3, custom = 4 })[c.ink] or 2
        items[#items + 1] = MenuUI.section(w, _("Text colour"), MenuUI.segmented(w, inks, ink_at,
            function(index) return { kind = "ink", value = Bookends.INKS[index] } end))
        items[#items + 1] = space(nil, px(12))
        items[#items + 1] = MenuUI.section(w, _("Text weight"), MenuUI.segmented(w, { _("Regular"), _("Bold") }, c.bold and 2 or 1,
            function(index) return { kind = "bold", value = index == 2 } end))
        items[#items + 1] = space(nil, px(12))
        local note = Bookends.otherBookends(page.ui) and _("The Bookends plugin is on: these lines stay hidden while it is. Turn it off in Plugin management.") or nil
        items[#items + 1] = MenuUI.group(w, {
            MenuUI.row(iw, { icon = "file-text", label = _("Book margins"), sub = note or _("Stats at the top and bottom of book pages"),
                h = note and 76 or 64, sublines = note and 2 or nil, toggle = on, action = { kind = "enabled", value = not on } }),
            MenuUI.row(iw, { icon = "eye-off", label = _("Hide KOReader's status bar"), sub = _("Its bar at the foot of the page, while the bottom line shows"), h = 64,
                toggle = c.hide_stock == true, action = { kind = "stock" } }),
            MenuUI.row(iw, { icon = "rotate-ccw", label = _("Reset"), sub = _("Progress, clock and battery on top; time left at the foot"), h = 64, action = { kind = "reset" } }),
        })
    end
    return items
end

local function build(page, sw, sh)
    BoardMetrics.refresh()
    page.config = Bookends.config()
    local mx = MenuUI.mx()
    local w = sw - 2 * mx
    local header = MenuUI.pageHeader(w, _("Book margins"), { sub = _("Stats at the top and bottom of book pages") })
    local items = body(page, w, false)
    local h = hOf(header) + px(8)
    for _i, it in ipairs(items) do h = h + hOf(it) end
    if h > sh - px(20) then
        for _i, it in ipairs(items) do if it.free then it:free() end end
        items = body(page, w, true)
    end
    local all = { header, space(nil, px(8)) }
    for _i, it in ipairs(items) do all[#all + 1] = it end
    page.panel_rect = Geom:new{ x = 0, y = 0, w = sw, h = sh }
    return vstack({ w = sw, h = sh, pad = { px(6), mx, px(12), mx } }, all)
end

-- ---------------------------------------------------------------- picker
-- Every item as a chip; the chosen ones inked and numbered in their order.
function Page.openPicker(page, edge, slot)
    return SheetUI.open{
        name = "aleph_bookends_picker",
        build = function(sheet, sw, sh)
            return SheetUI.sheet(sheet, sw, sh, function(w)
                local list = Bookends.config().slots[edge][slot]
                local order = {}
                for i, id in ipairs(list) do order[id] = i end
                local chips = {}
                for _i, it in ipairs(Bookends.ITEMS) do
                    local n = order[it.id]
                    local label = text((n and (n .. "  ") or "") .. it.label(), { s = 14, b = n ~= nil, col = n and INK.white or INK.black })
                    local cw = math.min(w, wOf(label) + 2 * px(14))
                    local h = px(36)
                    local b = math.max(1, px(1.25))
                    local chip = BoardUI.box({ w = cw, h = h, radius = floor(h / 2), border = n and 0 or b, border_col = INK.g6, bg = n and INK.black or INK.white },
                        hstack({ w = cw - 2 * (n and 0 or b), h = h - 2 * (n and 0 or b) }, { flex(0), label, flex(0) }))
                    chips[#chips + 1] = BoardUI.hit(chip, { kind = "item", id = it.id })
                end
                return {
                    SheetUI.titleRow(w, T(_("%1 · %2"), EDGE_LABELS[edge](), SLOT_LABELS[slot]()), _("Tap in the order to show them, up to three")),
                    SheetUI.wrap(w, chips, px(8)),
                    hstack({ w = w }, {
                        BoardUI.hit(MenuUI.pill(_("Clear"), { kind = "outline", h = 40, s = 14 }), { kind = "clear" }),
                        flex(0),
                        BoardUI.hit(MenuUI.pill(_("Done"), { h = 40, s = 14, icon = "check", icon_size = 16 }), { kind = "close" }),
                    }),
                }
            end, { pop_w = 560 })
        end,
        on_action = function(sheet, action)
            local c = Bookends.config()
            local list = c.slots[edge][slot]
            if action.kind == "item" then
                local at
                for i, id in ipairs(list) do if id == action.id then at = i end end
                if at then
                    table.remove(list, at)
                elseif #list >= Bookends.MAX_ITEMS then
                    pcall(function() require("aleph_toast").show(_("Up to three in one place. Tap one to remove it first."), { icon = "info" }) end)
                    return true
                else
                    list[#list + 1] = action.id
                end
            elseif action.kind == "clear" then
                c.slots[edge][slot] = {}
            else
                return true
            end
            Bookends.save(c)
            sheet:refresh()
            Page.changed(page)
            return true
        end,
        on_close = function() if not page.closed then page:refresh() end end,
    }
end

-- A colour of one's own for the text, from the colour wheel. One too light
-- to read on a white page is refused.
function Page.pickInk(page)
    local c = Bookends.config()
    require("aleph_color_wheel").open{
        title = _("Text colour"), hex = c.ink == "custom" and c.ink_hex or "#335577",
        on_use = function(hex)
            if Bookends.tooLight(hex) then
                pcall(function() require("aleph_toast").show(_("Too light to read on the page: pick a darker colour."), { icon = "triangle-alert" }) end)
                return
            end
            local now = Bookends.config()
            now.ink, now.ink_hex = "custom", hex
            Bookends.save(now)
            if not page.closed then page:refresh() end
            Page.changed(page)
        end,
    }
end

function Page.changed(page)
    if page.ui then pcall(Bookends.changed, page.ui) end
end

local function onAction(page, action)
    local c = Bookends.config()
    local k = action.kind
    if k == "tab" then page.tab = action.tab
    elseif k == "edge" then c[action.edge] = not c[action.edge]; Bookends.save(c)
    elseif k == "slot" then Page.openPicker(page, action.edge, action.slot); return true
    elseif k == "line" then c.line = action.value; Bookends.save(c)
    elseif k == "size" then c.size = action.value; Bookends.save(c)
    elseif k == "bold" then c.bold = action.value; Bookends.save(c)
    elseif k == "offset" then
        c[action.key] = math.max(Bookends.OFFSET_MIN, math.min(Bookends.OFFSET_MAX, (c[action.key] or 0) + action.delta))
        Bookends.save(c)
    elseif k == "ink" then
        if action.value == "custom" then Page.pickInk(page); return true end
        c.ink = action.value; Bookends.save(c)
    elseif k == "stock" then
        c.hide_stock = not c.hide_stock
        Bookends.save(c)
        if not c.hide_stock and page.ui and page.ui.view and page.ui.view.footer then
            pcall(function() require("aleph_toast").show(_("KOReader's status bar comes back with its own toggle (tap the foot of the page)."), { icon = "info" }) end)
        end
    elseif k == "enabled" then
        local stored = G_reader_settings:readSetting("aleph")
        if type(stored) ~= "table" then stored = {} end
        stored.bookends_enabled = action.value and nil or false
        G_reader_settings:saveSetting("aleph", stored)
    elseif k == "reset" then Bookends.reset()
    else return true end
    page:refresh()
    Page.changed(page)
    return true
end

-- ui: the reader, when opened over a book (its page follows the changes).
function Page.open(ui)
    local page = MenuPage:new{
        name = "aleph_bookends_page",
        build = build,
        on_action = onAction,
        on_swipe = function(p, ges)
            local order = { "top", "bottom", "look" }
            local at = 1
            for i, t in ipairs(order) do if t == (p.tab or "top") then at = i end end
            if ges.direction == "west" and at < 3 then p.tab = order[at + 1]; p:refresh(); return true end
            if ges.direction == "east" and at > 1 then p.tab = order[at - 1]; p:refresh(); return true end
            return false
        end,
        ui = ui and ui.document and ui or nil,
        tab = "top",
    }
    UIManager:show(page, "ui")
    return page
end

return Page
