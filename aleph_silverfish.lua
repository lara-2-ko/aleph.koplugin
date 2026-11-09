-- Horizontal companion card using the installed Silverfish's live state and art.
local Widget = require("ui/widget/widget")
local Geom = require("ui/geometry")
local Font = require("ui/font")
local TextBoxWidget = require("ui/widget/textboxwidget")
local Blitbuffer = require("ffi/blitbuffer")
local Screen = require("device").screen
local Estado = require("traca_estado")
local Desenho = require("traca_desenho")

local Card = Widget:extend{}
local speech = {}

function Card:init()
    self.pet_width = math.min(math.floor(self.width * 0.27), self.height)
    self.pet = self.module.render{
        width = self.pet_width, height = self.height,
        surface = "dashboard", preview = true,
    }
end

function Card:getSize()
    return Geom:new{ w = self.width, h = self.height }
end

function Card:paintTo(bb, x, y)
    self.dimen = Geom:new{ x = x, y = y, w = self.width, h = self.height }
    self.pet:paintTo(bb, x, y)
    local u = math.max(1, math.floor(self.height / 48))
    local bx = x + self.pet_width + 4 * u
    local by = y + 3 * u
    local bw = self.width - self.pet_width - 7 * u
    local bh = self.height - 8 * u
    if bw < 20 * u or bh < 12 * u then return end
    local black, white = Blitbuffer.COLOR_BLACK, Blitbuffer.COLOR_WHITE
    -- Three pixel steps soften the corners while retaining Silverfish's style.
    local function roundedPixelBox(rx, ry, rw, rh, color)
        bb:paintRect(rx + 3 * u, ry, rw - 6 * u, rh, color)
        bb:paintRect(rx + u, ry + u, rw - 2 * u, rh - 2 * u, color)
        bb:paintRect(rx, ry + 3 * u, rw, rh - 6 * u, color)
    end
    roundedPixelBox(bx + 2 * u, by + 2 * u, bw, bh, black)
    roundedPixelBox(bx, by, bw, bh, black)
    roundedPixelBox(bx + u, by + u, bw - 2 * u, bh - 2 * u, white)
    local tail_y = by + math.floor(bh / 2)
    bb:paintRect(bx - 2 * u, tail_y - u, 3 * u, 3 * u, black)
    bb:paintRect(bx - 3 * u, tail_y, u, u, black)
    bb:paintRect(bx - u, tail_y, 3 * u, u, white)
    local now = os.time()
    local state = self.traca.estado
    local key = tostring(self.traca) .. ":" .. tostring(state.paginas) .. ":" .. Estado.sprite(state, now)
    if speech.key ~= key or now - (speech.at or 0) >= 1200 then
        speech = { key = key, at = now, text = Estado.fala(state, now, nil, nil, "traca") }
    end
    local pad = 3 * u
    local factor = Screen:scaleBySize(1000) / 1000
    local size = math.max(10, math.min(self.height * 0.14, bw * 0.055))
    local face = Font:getFace(Desenho.caminhoFonte("Silkscreen-Regular.ttf"), size / factor)
    local avail_h = bh - 2 * pad
    -- A TextBoxWidget given a height reports that height, not the text's, so
    -- measure it free first; only text too long for the bubble is cut short.
    local text = TextBoxWidget:new{
        text = speech.text or "…", face = face,
        width = bw - 2 * pad, alignment = "center",
    }
    if text:getSize().h > avail_h then
        text:free()
        text = TextBoxWidget:new{
            text = speech.text or "…", face = face,
            width = bw - 2 * pad, height = avail_h,
            height_overflow_show_ellipsis = true, alignment = "center",
        }
    end
    local th = text:getSize().h
    text:paintTo(bb, bx + pad, by + math.max(pad, math.floor((bh - th) / 2)))
    text:free()
end

function Card:free()
    local pet = self.pet
    self.pet = nil
    if pet and type(pet.free) == "function" then pet:free() end
end

return Card
