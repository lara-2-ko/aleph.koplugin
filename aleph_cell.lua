-- Aleph modification, 2026-11-08: a tappable cell for restyled KOReader
-- dialogs.
--[[--
A rounded cell with an icon, a label, or both, that does what a KOReader
button does. `source` is that button: its callback, hold_callback, text and
enabled state are read when they are needed, so the cell follows the button
(a dictionary switching, a button that becomes disabled). `bare` draws no
frame (a header icon).
]]

local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")

local BoardMetrics = require("aleph_board_metrics")
local BoardUI = require("aleph_board_ui")

local INK = BoardMetrics.INK
local px = BoardMetrics.px

local Cell = InputContainer:extend{
    w = 0, h = 0, icon_name = nil, source = nil, bare = false, icon_size = 22,
    -- With an icon, also show the label (the button's text, or `label`).
    show_label = false, label = nil, label_size = 15,
    -- center: a label alone is centred in the cell (a long one still fits).
    center = false,
    -- active: drawn inked (black, white content), for the chosen filter or tab.
    -- swatch: a color (Blitbuffer) drawn as a circle instead of an icon or text.
    -- sample: a function(w, h, active) returning a widget drawn in the cell.
    active = false, swatch = nil, sample = nil, radius = nil,
}

function Cell:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.w, h = self.h }
    self.ges_events = {
        TapCell = { GestureRange:new{ ges = "tap", range = self.dimen } },
        HoldCell = { GestureRange:new{ ges = "hold", range = self.dimen } },
    }
end

function Cell:getSize()
    return self.dimen
end

function Cell:isEnabled()
    return not self.source or self.source.enabled ~= false
end

function Cell:labelText()
    if self.icon_name and not self.show_label then return nil end
    return self.label or (self.source and self.source.text) or ""
end

function Cell:build(enabled, label)
    local items = {}
    local on = self.active
    local ink = on and "white" or (enabled and "black" or "gb")
    if self.swatch then
        local d = math.min(self.w, self.h) - 2 * px(6)
        local ring = on and math.max(2, px(2.5)) or math.max(1, px(1.25))
        table.insert(items, BoardUI.circle(d, { bg = self.swatch, border = ring, border_col = INK.black }, BoardUI.space(1, 1)))
    elseif self.sample then
        table.insert(items, self.sample(self.w - 2 * px(4), self.h - 2 * px(4), on))
    else
        if self.icon_name then
            table.insert(items, BoardUI.icon(self.icon_name, px(self.icon_size), { col = ink, sw = 2.25 }))
        end
        if label then
            local avail = self.w - 2 * px(10) - (self.icon_name and (px(self.icon_size) + px(8)) or 0)
            table.insert(items, BoardUI.text(label, { s = self.label_size, b = true, col = on and INK.white or (enabled and INK.black or INK.gb), w = avail, data = true,
                align = (self.center and not self.icon_name) and "center" or nil }))
        end
    end
    local content = #items > 1 and BoardUI.hstack({ gap = px(8) }, items) or items[1]
    local inner = BoardUI.hstack({ w = self.w, h = self.h }, { BoardUI.flex(0), content, BoardUI.flex(0) })
    if self.bare then return inner end
    local border = math.max(1, px(1.25))
    local radius = self.radius or px(12)
    if self.swatch then return inner end
    -- A drawn sample keeps its own colors, so "active" is a heavier outline, not a fill.
    local fill = on and not self.sample
    if self.sample and on then border = math.max(2, px(2.5)) end
    return BoardUI.box({ w = self.w, h = self.h, radius = radius, border = border, border_col = on and INK.black or (enabled and INK.g6 or INK.gd), bg = fill and INK.black or INK.white },
        BoardUI.hstack({ w = self.w - 2 * border, h = self.h - 2 * border }, { BoardUI.flex(0), content, BoardUI.flex(0) }))
end

function Cell:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local enabled = self:isEnabled()
    local label = self:labelText()
    local key = tostring(enabled) .. "|" .. tostring(label) .. "|" .. tostring(self.active)
    if key ~= self._key then
        if self[1] and self[1].free then self[1]:free() end
        self[1] = self:build(enabled, label)
        self._key = key
    end
    self[1]:paintTo(bb, x, y)
end

function Cell:onTapCell()
    if self:isEnabled() and self.source and self.source.callback then self.source.callback() end
    return true
end

function Cell:onHoldCell()
    if self:isEnabled() and self.source and self.source.hold_callback then self.source.hold_callback() end
    return true
end

function Cell:free()
    if self[1] and self[1].free then self[1]:free() end
end

return Cell
