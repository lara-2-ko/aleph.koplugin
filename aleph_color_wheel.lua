-- Aleph modification, 2026-11-08: a color wheel for choosing a
-- highlight color.
--[[--
A hue and saturation disc, a brightness bar, a preview and Reset / Cancel / Use
buttons, in the board's panel style. Tap the disc for hue and saturation and
the bar for brightness. The disc is drawn once per size, pixel by pixel, and
kept.

  Wheel.open{ title, hex, on_use(hex), on_reset() }
]]

local Blitbuffer = require("ffi/blitbuffer")
local Geom = require("ui/geometry")
local Widget = require("ui/widget/widget")
local _ = require("gettext")

local BoardMetrics = require("aleph_board_metrics")
local BoardUI = require("aleph_board_ui")
local MenuUI = require("aleph_menu_ui")
local Panel = require("aleph_panel")

local INK = BoardMetrics.INK
local px = BoardMetrics.px
local floor, sqrt, abs = math.floor, math.sqrt, math.abs

local Wheel = {}

-- ------------------------------------------------------------ color maths
local function hsv2rgb(h, s, v)
    local c = v * s
    local hp = h / 60
    local x = c * (1 - abs(hp % 2 - 1))
    local m = v - c
    local r, g, b
    if hp < 1 then r, g, b = c, x, 0
    elseif hp < 2 then r, g, b = x, c, 0
    elseif hp < 3 then r, g, b = 0, c, x
    elseif hp < 4 then r, g, b = 0, x, c
    elseif hp < 5 then r, g, b = x, 0, c
    else r, g, b = c, 0, x end
    return floor((r + m) * 255 + 0.5), floor((g + m) * 255 + 0.5), floor((b + m) * 255 + 0.5)
end

local function rgb2hsv(r, g, b)
    r, g, b = r / 255, g / 255, b / 255
    local max, min = math.max(r, g, b), math.min(r, g, b)
    local d = max - min
    local h
    if d == 0 then h = 0
    elseif max == r then h = 60 * (((g - b) / d) % 6)
    elseif max == g then h = 60 * ((b - r) / d + 2)
    else h = 60 * ((r - g) / d + 4) end
    return h, max == 0 and 0 or d / max, max
end

local function parseHex(hex)
    local r, g, b = tostring(hex or ""):match("#?(%x%x)(%x%x)(%x%x)")
    if not r then return 204, 204, 204 end
    return tonumber(r, 16), tonumber(g, 16), tonumber(b, 16)
end

local function toHex(r, g, b)
    return string.format("#%02X%02X%02X", r, g, b)
end

local function color(r, g, b)
    return Blitbuffer.ColorRGB32(r, g, b, 0xFF)
end

-- ------------------------------------------------------------- the disc
local cache = {}

local function makeDisc(size)
    if cache[size] then return cache[size] end
    local bb = Blitbuffer.new(size, size, Blitbuffer.TYPE_BBRGB32)
    bb:fill(Blitbuffer.COLOR_WHITE)
    local R = size / 2
    local c = color(0, 0, 0)
    for y = 0, size - 1 do
        local dy = y + 0.5 - R
        for x = 0, size - 1 do
            local dx = x + 0.5 - R
            local d = sqrt(dx * dx + dy * dy)
            if d <= R - 1 then
                local hue = math.deg(math.atan2(dy, dx))
                if hue < 0 then hue = hue + 360 end
                local r, g, b = hsv2rgb(hue, math.min(1, d / (R - 1)), 1)
                c.r, c.g, c.b = r, g, b
                bb:setPixel(x, y, c)
            end
        end
    end
    cache[size] = bb
    return bb
end

local Disc = Widget:extend{ size = 0, state = nil }

function Disc:getSize()
    return Geom:new{ w = self.size, h = self.size }
end

function Disc:paintTo(bb, x, y)
    self.dimen = Geom:new{ x = x, y = y, w = self.size, h = self.size }
    bb:blitFrom(makeDisc(self.size), x, y, 0, 0, self.size, self.size)
    local R = self.size / 2
    local st = self.state
    local a = math.rad(st.h)
    local cx = floor(x + R + math.cos(a) * st.s * (R - 1) + 0.5)
    local cy = floor(y + R + math.sin(a) * st.s * (R - 1) + 0.5)
    bb:paintCircle(cx, cy, px(12), INK.black)
    bb:paintCircle(cx, cy, px(9), INK.white)
    bb:paintCircle(cx, cy, px(6.5), color(hsv2rgb(st.h, st.s, 1)))
end

-- ----------------------------------------------------------- the bar
local Bar = Widget:extend{ w = 0, h = 0, state = nil }

function Bar:getSize()
    return Geom:new{ w = self.w, h = self.h }
end

function Bar:paintTo(bb, x, y)
    self.dimen = Geom:new{ x = x, y = y, w = self.w, h = self.h }
    local st = self.state
    local step = 3
    for i = 0, self.w - 1, step do
        local v = i / math.max(1, self.w - 1)
        local r, g, b = hsv2rgb(st.h, st.s, v)
        bb:paintRect(x + i, y, math.min(step, self.w - i), self.h, color(r, g, b))
    end
    bb:paintBorder(x, y, self.w, self.h, math.max(1, px(1)), INK.g6, 0)
    local mx = floor(x + st.v * (self.w - 1) + 0.5)
    bb:paintRect(mx - px(2), y - px(4), px(4), self.h + px(8), INK.black)
    bb:paintRect(mx - px(1), y - px(3), px(2), self.h + px(6), INK.white)
end

-- --------------------------------------------------------------- panel
function Wheel.open(o)
    local r, g, b = parseHex(o.hex)
    local h, s, v = rgb2hsv(r, g, b)
    local state = { h = h, s = s, v = v }
    local disc, bar

    local function currentHex()
        return toHex(hsv2rgb(state.h, state.s, state.v))
    end

    local panel
    panel = Panel:new{
        build = function(p, sw, sh)
            local w = math.min(px(440), sw - 2 * px(12))
            local pad = px(16)
            local iw = w - 2 * pad
            local header = BoardUI.hstack({ w = iw, h = px(44) }, {
                BoardUI.text(o.title or _("Pick a color"), { s = 19, b = true, w = iw - px(52), data = true }),
                BoardUI.flex(0), MenuUI.iconButton("x", { kind = "close" }),
            })
            local fixed = header:getSize().h + px(8) + px(10) + px(34) + px(10) + px(48) + px(10) + px(48) + 2 * pad
            local size = math.max(px(150), math.min(iw, px(320), sh - fixed - px(16)))
            size = size - size % 2
            disc = Disc:new{ size = size, state = state }
            bar = Bar:new{ w = iw, h = px(26), state = state }
            local hex = currentHex()
            local rr, gg, bb2 = parseHex(hex)
            local preview = BoardUI.hstack({ w = iw, h = px(48), gap = px(12) }, {
                BoardUI.circle(px(40), { bg = color(rr, gg, bb2), border = math.max(2, px(2)), border_col = INK.black }, BoardUI.space(1, 1)),
                BoardUI.text(hex, { s = 18, b = true }),
                BoardUI.flex(0),
                BoardUI.text(_("Tap the wheel, then the bar"), { s = 12, col = INK.g4, w = px(150), lines = 2, align = "right" }),
            })
            local gap = px(8)
            local third = floor((iw - 2 * gap) / 3)
            local buttons = BoardUI.hstack({ w = iw, gap = gap }, {
                MenuUI.pill(_("Reset"), { kind = "outline", w = third, h = 48, s = 15, action = { kind = "reset" } }),
                MenuUI.pill(_("Cancel"), { kind = "outline", w = third, h = 48, s = 15, action = { kind = "close" } }),
                MenuUI.pill(_("Use"), { kind = "dark", w = third, h = 48, s = 15, action = { kind = "use" } }),
            })
            local content = BoardUI.vstack({ w = w, pad = pad }, {
                header, BoardUI.space(nil, px(8)),
                BoardUI.hstack({ w = iw }, { BoardUI.flex(0), BoardUI.hit(disc, { kind = "disc" }), BoardUI.flex(0) }),
                BoardUI.space(nil, px(14)),
                BoardUI.hit(bar, { kind = "bar" }),
                BoardUI.space(nil, px(10)),
                preview,
                BoardUI.space(nil, px(10)),
                buttons,
            })
            local border = math.max(1, px(1.5))
            local ph = content:getSize().h + 2 * border
            local panel_widget = BoardUI.box({ w = w, h = ph, radius = px(16), bg = INK.white, border = border, border_col = INK.g6 }, content)
            local x, y = floor((sw - w) / 2), math.max(px(8), floor((sh - ph) / 2))
            p.panel_rect = Geom:new{ x = x, y = y, w = w, h = ph }
            return BoardUI.overlay(sw, sh, { { widget = panel_widget, x = x, y = y } })
        end,
        on_action = function(p, action, ges)
            local k = action.kind
            if k == "disc" and disc and disc.dimen and ges and ges.pos then
                local R = disc.size / 2
                local dx = ges.pos.x - (disc.dimen.x + R)
                local dy = ges.pos.y - (disc.dimen.y + R)
                local d = math.min(sqrt(dx * dx + dy * dy), R - 1)
                local hue = math.deg(math.atan2(dy, dx))
                if hue < 0 then hue = hue + 360 end
                state.h, state.s = hue, d / (R - 1)
                p:refresh()
            elseif k == "bar" and bar and bar.dimen and ges and ges.pos then
                state.v = math.max(0, math.min(1, (ges.pos.x - bar.dimen.x) / math.max(1, bar.w - 1)))
                p:refresh()
            elseif k == "use" then
                local hex = currentHex()
                p:close()
                if o.on_use then o.on_use(hex) end
            elseif k == "reset" then
                p:close()
                if o.on_reset then o.on_reset() end
            end
        end,
    }
    panel:show()
    return panel
end

return Wheel
