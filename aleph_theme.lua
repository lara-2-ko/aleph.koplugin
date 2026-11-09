-- Aleph modification, 2026-11-09: KOReader's own windows in Aleph's style.
--[[--
Aleph restyles some KOReader screens one by one (the top menu, the table of
contents, bookmarks, the dictionary, highlights...). Everything else KOReader
shows (info messages, questions, button dialogs, text input, number and date
pickers, the text viewer, sort lists, notifications, title bars of full
pages) is built from the same few parts. This dresses those parts once, so
every window made from them comes out in Aleph's style:

  sizes        Size.radius.window / .button: Aleph's rounder corners
  fonts        Font.sizemap: Aleph's sizes for KOReader's named UI fonts
               (the same Noto Sans; book text and the status bar untouched)
  class fonts  the fonts a few widget classes picked when KOReader started
  title bars   a light rule instead of a black one
  windows      a gray border, as Aleph's sheets (MovableContainer frames)
  icons        close, chevrons, check, info, question, warning... drawn with
               Aleph's icons (IconWidget names)

No widget is built twice and nothing is copied: only numbers, fonts and icon
file names change, before a window is built. Screens Aleph already styles keep
their own look (they set their fonts and sizes explicitly).

Follows Settings > Opening > Aleph dialogs: off puts KOReader's values back
for the next window opened. Theme.sync() applies the setting (and the
interface size).
]]

local Theme = { on = false }

-- KOReader's named UI fonts, at Aleph's sizes (nominal, as BoardMetrics).
-- Left alone: book fonts, ffont family (status bar), infont (keyboard),
-- scfont (monospace).
local SIZES = {
    tfont = 20, smalltfont = 18, x_smalltfont = 18,
    cfont = 16, infofont = 16,
    smallinfofont = 15, smallinfofontbold = 15,
    x_smallinfofont = 14, xx_smallinfofont = 13,
}

-- Fonts widget classes fetched when they were loaded: field = font name, or
-- { name, size } for a size of their own.
local CLASS_FACES = {
    ["ui/widget/buttondialog"] = { title_face = "x_smalltfont", info_face = "infofont" },
    ["ui/widget/checkbutton"] = { face = "smallinfofont", checkmark_face = "smallinfofont" },
    ["ui/widget/checkmark"] = { face = "smallinfofont" },
    ["ui/widget/confirmbox"] = { face = "infofont" },
    ["ui/widget/datetimewidget"] = { title_face = "x_smalltfont" },
    ["ui/widget/doublespinwidget"] = { title_face = "x_smalltfont" },
    ["ui/widget/inputdialog"] = { input_face = { "x_smallinfofont", 16 } },
    ["ui/widget/inputtext"] = { face = { "smallinfofont", 16 } },
    ["ui/widget/multiconfirmbox"] = { face = "infofont" },
    ["ui/widget/notification"] = { face = "x_smallinfofont" },
    ["ui/widget/numberpickerwidget"] = { spinner_face = { "smalltfont", 20 } },
    ["ui/widget/radiomark"] = { face = "smallinfofont" },
    ["ui/widget/sortwidget"] = { face = "smallinfofont" },
    ["ui/widget/titlebar"] = { title_face_fullscreen = "smalltfont", title_face_not_fullscreen = "x_smalltfont",
        subtitle_face = "xx_smallinfofont", info_text_face = "x_smallinfofont" },
    ["ui/widget/trapwidget"] = { face = "infofont" },
}

-- KOReader icon name -> Aleph icon.
local ICONS = {
    ["close"] = "x", ["cancel"] = "x",
    ["chevron.left"] = "chevron-left", ["chevron.right"] = "chevron-right",
    ["chevron.first"] = "chevrons-left", ["chevron.last"] = "chevrons-right",
    ["chevron.up"] = "chevron-up", ["chevron.down"] = "chevron-down",
    ["check"] = "check", ["plus"] = "plus", ["edit"] = "pen-line",
    ["info"] = "info", ["notice-info"] = "info", ["notice-question"] = "circle-help",
    ["notice-warning"] = "triangle-alert", ["bookmark"] = "bookmark",
    ["move.up"] = "arrow-up", ["move.down"] = "arrow-down",
}

-- KOReader's values, kept to put back.
local saved = nil

local function wanted()
    local ok, on = pcall(function() return require("aleph_prefs").styleDialogs() end)
    return ok and on
end

local function remember()
    if saved then return end
    local Font = require("ui/font")
    local Size = require("ui/size")
    saved = { sizemap = {}, radius_window = Size.radius.window, radius_button = Size.radius.button }
    for name in pairs(SIZES) do saved.sizemap[name] = Font.sizemap[name] end
    local ok, TitleBar = pcall(require, "ui/widget/titlebar")
    if ok then saved.title_line = rawget(TitleBar, "bottom_line_color") end
end

-- The class fonts again, from the sizes now in place.
local function refreshClassFaces(on)
    local Font = require("ui/font")
    local BoardMetrics = require("aleph_board_metrics")
    for module, fields in pairs(CLASS_FACES) do
        -- Only classes already loaded: one loaded later reads the new sizes.
        local class = package.loaded[module]
        if type(class) == "table" then
            for field, spec in pairs(fields) do
                if rawget(class, field) ~= nil then
                    local name, size = spec, nil
                    if type(spec) == "table" then
                        name = spec[1]
                        size = on and BoardMetrics.fontSize(spec[2]) or nil
                    end
                    local ok, face = pcall(Font.getFace, Font, name, size)
                    if ok and face then rawset(class, field, face) end
                end
            end
        end
    end
end

function Theme.apply()
    remember()
    local Font = require("ui/font")
    local Size = require("ui/size")
    local BoardMetrics = require("aleph_board_metrics")
    pcall(BoardMetrics.refresh)
    for name, n in pairs(SIZES) do Font.sizemap[name] = BoardMetrics.fontSize(n) end
    Size.radius.window = BoardMetrics.px(16)
    Size.radius.button = BoardMetrics.px(10)
    local ok, TitleBar = pcall(require, "ui/widget/titlebar")
    if ok then rawset(TitleBar, "bottom_line_color", BoardMetrics.INK.g9) end
    refreshClassFaces(true)
    Theme.on = true
end

function Theme.restore()
    if not saved then return end
    local Font = require("ui/font")
    local Size = require("ui/size")
    for name, n in pairs(saved.sizemap) do Font.sizemap[name] = n end
    Size.radius.window, Size.radius.button = saved.radius_window, saved.radius_button
    local ok, TitleBar = pcall(require, "ui/widget/titlebar")
    if ok then rawset(TitleBar, "bottom_line_color", saved.title_line) end
    refreshClassFaces(false)
    Theme.on = false
end

-- The window frames and icons: checked as each is built, so they follow the
-- setting without being put back.
-- Whether a frame's border colour is KOReader's black (or unset, which
-- draws black). Colours are cdata: comparing one with nil or a colour of
-- another kind runs KOReader's colour comparison, which fails on nil, so
-- the colour is read as a gray level instead.
local function isBlackBorder(color)
    if type(color) ~= "cdata" then return color == nil end
    local ok, level = pcall(function() return color:getColor8().a end)
    return ok and level == 0
end
Theme.isBlackBorder = isBlackBorder

local function installHooks()
    if Theme.hooked then return end
    Theme.hooked = true
    local MovableContainer = require("ui/widget/container/movablecontainer")
    local movable_init = MovableContainer.init
    MovableContainer.init = function(self, ...)
        if Theme.on then
            -- Never in the way of the window itself.
            pcall(function()
                local frame = self[1]
                -- A dialog's frame: bordered, rounded, drawn in black.
                if type(frame) == "table" and frame.radius and (frame.bordersize or 0) > 0
                        and isBlackBorder(rawget(frame, "color")) then
                    frame.color = require("aleph_board_metrics").INK.g6
                end
            end)
        end
        return movable_init(self, ...)
    end
    local IconWidget = require("ui/widget/iconwidget")
    local icon_init = IconWidget.init
    IconWidget.init = function(self, ...)
        if Theme.on and not self.image and not self.file and self.icon and ICONS[self.icon] then
            local ok, file = pcall(function()
                return require("aleph_board_icons").file(ICONS[self.icon], "#000000", 2)
            end)
            if ok and file then self.file = file end
        end
        return icon_init(self, ...)
    end
end

-- Applies the setting; call again after it or the interface size changed.
function Theme.sync()
    installHooks()
    if wanted() then Theme.apply() else Theme.restore() end
end

Theme.SIZES, Theme.ICONS, Theme.CLASS_FACES = SIZES, ICONS, CLASS_FACES

return Theme
