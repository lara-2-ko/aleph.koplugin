-- Aleph modification, 2026-11-08: a confirmation in the board's style.
--[[--
Replaces KOReader's ConfirmBox for the board's own questions (downloading or
removing author portraits): a rounded panel with the board's font and sizes, a
title, the explanation, and Cancel / action pills. Tapping outside cancels.

  Confirm.show{ title, text, ok_label, cancel_label, on_ok, on_cancel }
  (on_cancel: run by the cancel pill only, not by a tap outside)
]]

local Geom = require("ui/geometry")
local _ = require("gettext")

local BoardMetrics = require("aleph_board_metrics")
local BoardUI = require("aleph_board_ui")
local MenuUI = require("aleph_menu_ui")
local Panel = require("aleph_panel")

local INK = BoardMetrics.INK
local px = BoardMetrics.px
local floor = math.floor

local Confirm = {}

function Confirm.show(o)
    local panel
    panel = Panel:new{
        build = function(p, sw, sh)
            local w = math.min(px(460), sw - 2 * px(16))
            local pad = px(18)
            local iw = w - 2 * pad
            local gap = px(10)
            local half = floor((iw - gap) / 2)
            local items = {
                BoardUI.text(o.title or "", { s = 19, b = true, w = iw, data = true }),
                BoardUI.space(nil, px(10)),
                BoardUI.text(o.text or "", { s = 15, col = INK.g2, w = iw, lines = 14, data = true }),
                BoardUI.space(nil, px(18)),
                BoardUI.hstack({ w = iw, gap = gap }, {
                    MenuUI.pill(o.cancel_label or _("Cancel"), { kind = "outline", w = half, h = 48, s = 16, action = { kind = o.on_cancel and "cancel" or "close" } }),
                    MenuUI.pill(o.ok_label or _("OK"), { kind = "dark", w = half, h = 48, s = 16, action = { kind = "ok" } }),
                }),
            }
            local content = BoardUI.vstack({ w = w, pad = pad }, items)
            local border = math.max(1, px(1.5))
            local ph = content:getSize().h + 2 * border
            local widget = BoardUI.box({ w = w, h = ph, radius = px(16), bg = INK.white, border = border, border_col = INK.g6 }, content)
            local x, y = floor((sw - w) / 2), math.max(px(8), floor((sh - ph) / 2))
            p.panel_rect = Geom:new{ x = x, y = y, w = w, h = ph }
            return BoardUI.overlay(sw, sh, { { widget = widget, x = x, y = y } })
        end,
        on_action = function(p, action)
            if action.kind == "ok" then
                p:close()
                if o.on_ok then o.on_ok() end
            elseif action.kind == "cancel" then
                p:close()
                o.on_cancel()
            end
        end,
    }
    panel:show()
    return panel
end

return Confirm
