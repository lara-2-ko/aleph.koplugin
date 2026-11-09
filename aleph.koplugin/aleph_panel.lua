-- Aleph modification, 2026-11-08: a pop-up panel in the board's style
-- that can sit over any KOReader screen, the reader included.
--[[--
Like MenuPage, but it does not cover the screen: it draws only its panel, so
the page underneath (a book, with its highlight) stays visible and live. The
panel is built by `build(panel, screen_w, screen_h)`, which sets
`panel.panel_rect`; every tappable part is a BoardUI hit area.

  on_action(panel, action, ges)  a tap on a hit area
  on_hold(panel, action, ges)    a hold on a hit area
  on_close(panel)                after it closed
  dismiss                        a tap outside the panel closes it (default)
  on_gesture(panel, ges)         swipes, pinches and spreads (true when used)
]]

local Device = require("device")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")

local BoardMetrics = require("aleph_board_metrics")
local BoardUI = require("aleph_board_ui")

local Screen = Device.screen
local px = BoardMetrics.px

local Panel = InputContainer:extend{
    name = "aleph_panel",
    build = nil,
    on_action = nil,
    on_hold = nil,
    on_close = nil,
    dismiss = true,
    panel_rect = nil,
    on_gesture = nil,
}

function Panel:init()
    BoardMetrics.refresh()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.ges_events = {
        TapPanel = { GestureRange:new{ ges = "tap", range = self.dimen } },
        HoldPanel = { GestureRange:new{ ges = "hold", range = self.dimen } },
        SwipePanel = { GestureRange:new{ ges = "swipe", range = self.dimen } },
    }
    if self.on_gesture then
        self.ges_events.PinchPanel = { GestureRange:new{ ges = "pinch", range = self.dimen } }
        self.ges_events.SpreadPanel = { GestureRange:new{ ges = "spread", range = self.dimen } }
    end
    self.key_events = {}
    if Device:hasKeys() then
        self.key_events.ClosePanel = { { Device.input.group.Back } }
    end
    self:rebuild()
end

function Panel:rebuild()
    local widget, hits = BoardUI.collectHits(function()
        return self.build(self, self.dimen.w, self.dimen.h)
    end)
    if self[1] and self[1].free then self[1]:free() end
    self[1] = widget
    self.hits = hits
end

-- Where the panel is drawn, and what to repaint on e-ink.
function Panel:region()
    return self.panel_rect or self.dimen
end

function Panel:dither()
    return Screen:isColorEnabled()
end

function Panel:show()
    UIManager:show(self, "ui", self:region(), nil, nil, self:dither())
    return self
end

-- Rebuilds and repaints, the panel's own rectangle only (the larger of the
-- old and new one when the panel changed size).
function Panel:refresh()
    local before = self.panel_rect and self.panel_rect:copy() or nil
    self:rebuild()
    local region = self:region()
    if before then region = region:combine(before) end
    local dither = self:dither()
    UIManager:setDirty(self, function() return "ui", region, dither end)
end

-- `extra` is something drawn over the page that is not part of the panel (the
-- highlight's drag posts, see aleph_handles.lua). It paints itself, is
-- offered every gesture first (`extra:gesture(ges)` returns true when it used
-- it), and hides the panel while it is being dragged (`extra.dragging`).
-- KOReader sends a touch to the topmost window, so this has to live here and
-- not in a window of its own.
-- The posts are painted first and the panel over them, so where a post runs
-- under the menu the menu wins and the post is hidden.
function Panel:paintTo(bb, x, y)
    local extra = self.extra
    if extra then extra:paintTo(bb) end
    if not (extra and extra.dragging) and self[1] then self[1]:paintTo(bb, 0, 0) end
end

function Panel:handleEvent(event)
    local extra = self.extra
    if extra and event.handler == "onGesture" and event.args and extra:gesture(event.args[1]) then
        return true
    end
    return InputContainer.handleEvent(self, event)
end

function Panel:onCloseWidget()
    if self.extra and self.extra.close then self.extra:close() end
    if self[1] and self[1].free then self[1]:free() end
end

-- Closes without on_close (the caller is about to show a fresh menu).
function Panel:closeQuiet()
    if self.closed then return end
    self.closed = true
    UIManager:close(self, "ui", self:region())
end

function Panel:close()
    if self.closed then return end
    self.closed = true
    local region = self:region()
    UIManager:close(self, "ui", region)
    if self.on_close then self.on_close(self) end
end

-- The smallest hit area under the finger wins; a near miss goes to the
-- closest one within a finger's width.
function Panel:hitAt(pos)
    local best, best_size
    for index = #self.hits, 1, -1 do
        local area = self.hits[index]
        local d = area.dimen
        if d and pos:intersectWith(d) and (not best_size or d.w * d.h < best_size) then
            best, best_size = area, d.w * d.h
        end
    end
    if best then return best end
    local slop, best_dist = px(10), nil
    for _i, area in ipairs(self.hits) do
        local d = area.dimen
        if d then
            local dx = math.max(d.x - pos.x, 0, pos.x - (d.x + d.w))
            local dy = math.max(d.y - pos.y, 0, pos.y - (d.y + d.h))
            local dist = math.max(dx, dy)
            if dist <= slop and (not best_dist or dist < best_dist) then best, best_dist = area, dist end
        end
    end
    return best
end

function Panel:onTapPanel(_, ges)
    local area = ges and ges.pos and self:hitAt(ges.pos)
    if area then
        local action = area.action
        if action and action.kind == "close" then self:close()
        elseif action and action.kind ~= "noop" and self.on_action then self.on_action(self, action, ges) end
    elseif self.dismiss and self.panel_rect and ges and ges.pos and not ges.pos:intersectWith(self.panel_rect) then
        self:close()
    end
    return true
end

function Panel:onHoldPanel(_, ges)
    local area = ges and ges.pos and self:hitAt(ges.pos)
    if area and area.action and self.on_hold then self.on_hold(self, area.action, ges) end
    return true
end

function Panel:onSwipePanel(_, ges)
    if self.on_gesture and ges then self.on_gesture(self, ges) end
    return true
end

function Panel:onPinchPanel(_, ges)
    if self.on_gesture and ges then self.on_gesture(self, ges) end
    return true
end

function Panel:onSpreadPanel(_, ges)
    if self.on_gesture and ges then self.on_gesture(self, ges) end
    return true
end

function Panel:onClosePanel()
    self:close()
    return true
end

return Panel
