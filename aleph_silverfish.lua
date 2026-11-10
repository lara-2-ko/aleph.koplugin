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
-- Whether the bubble on the board had to cut its text short (a tap then
-- opens the whole of it, see Card.openPopup).
Card.truncated = false

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
    Card.truncated = text:getSize().h > avail_h
    if Card.truncated then
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

-- What the companion is saying now, as on the board.
function Card.speechText()
    return speech.text
end

-- ------------------------------------------------------------------ popup
-- Aleph modification, 2026-11-10: the whole of a long speech. A tap on a
-- Silverfish widget whose bubble had to cut its text opens this sheet: the
-- companion drawn larger and everything it says, in Aleph's sheet style and
-- type, with a way on to Silverfish's own screen.
local PetBox = Widget:extend{ pet = nil, size = 0 }
function PetBox:getSize() return Geom:new{ w = self.size, h = self.size } end
function PetBox:paintTo(bb, x, y)
    self.dimen = Geom:new{ x = x, y = y, w = self.size, h = self.size }
    if self.pet then self.pet:paintTo(bb, x, y) end
end

-- module: Silverfish's micro-module (render, on_tap); on_open runs its own tap.
function Card.openPopup(module, on_open)
    local SheetUI = require("aleph_sheet_ui")
    local BoardUI = require("aleph_board_ui")
    local BoardMetrics = require("aleph_board_metrics")
    local TextPages = require("aleph_text_pages")
    local _ = require("gettext")
    local INK, px = BoardMetrics.INK, BoardMetrics.px
    local said = speech.text or "…"
    local pets = {}
    local function freePets()
        for _i, pet in ipairs(pets) do
            if type(pet.free) == "function" then pcall(pet.free, pet) end
        end
        pets = {}
    end
    return SheetUI.open{
        name = "aleph_silverfish_speech",
        build = function(page, sw, sh)
            freePets()
            return SheetUI.sheet(page, sw, sh, function(w, max_h)
                local size = math.min(px(150), math.floor(w * 0.36))
                local ok, pet = pcall(module.render, { width = size, height = size, surface = "dashboard", preview = true })
                if ok and pet then pets[#pets + 1] = pet else pet = nil end
                local gap = px(14)
                local bw = w - size - gap
                local pad = px(14)
                local tw = bw - 2 * pad
                local lines = math.max(1, TextPages.linesNeeded(said, { s = 16 }, tw))
                -- Never taller than the sheet allows; a longer speech ends in "…".
                local room = max_h - px(140)
                lines = math.max(1, math.min(lines, math.floor(room / BoardMetrics.lh(16))))
                local words = BoardUI.text(said, { s = 16, w = tw, lines = lines, align = "center", data = true })
                local bh = math.max(size, words:getSize().h + 2 * pad)
                local bubble = BoardUI.box({ w = bw, h = bh, radius = px(14), border = math.max(1, px(1.5)), border_col = INK.black, bg = INK.white },
                    BoardUI.vstack({ w = bw, h = bh, align = "center" }, { BoardUI.flex(0), words, BoardUI.flex(0) }))
                return {
                    SheetUI.titleRow(w, _("Silverfish"), _("Your reading companion")),
                    BoardUI.hstack({ w = w, gap = gap, valign = "center" }, {
                        BoardUI.vstack({ w = size, h = bh }, { BoardUI.flex(0), PetBox:new{ pet = pet, size = size }, BoardUI.flex(0) }),
                        bubble,
                    }),
                    SheetUI.pillRow(w, {
                        { label = _("Open Silverfish"), icon = "chevron-right", kind = "outline", action = { kind = "open" } },
                    }),
                }
            end, { pop_w = 560 })
        end,
        on_action = function(page, action)
            if action.kind == "open" then
                page:close()
                if on_open then require("ui/uimanager"):tickAfterNext(on_open) end
            end
            return true
        end,
        on_close = freePets,
    }
end

return Card
