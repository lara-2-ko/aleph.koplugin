-- Aleph modification, 2026-11-08: the reader controls menu (the bottom
-- panel with its row of tabs) in the board's style, and a new Background tab.
--[[--
Restyled in place; every option and its behaviour is KOReader's:

  - the tab icons are the board's line icons, and the tab bar is shorter
  - option names and the choice buttons use the board's font and sizes
  - the choice buttons are rounded, the chosen one black with white text
  - the panel has a rounded top and the board's border

A new tab, Background, sets the page color: White, Paper, Sepia, Gray, or
Custom (a color wheel). It is KOReader's own page background, so margins and
the page itself take the color; it is remembered for each book.
]]

local Prefs = require("aleph_prefs")
local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Event = require("ui/event")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local BoardMetrics = require("aleph_board_metrics")
local BoardIcons = require("aleph_board_icons")
local try = require("aleph_try").call

local Screen = Device.screen
local px = BoardMetrics.px
local Override = require("aleph_override")

local Config = {}

-- ----------------------------------------------------------- background
local PRESETS = { "#FFFFFF", "#F4ECD8", "#E9D8B4", "#E4E4E4" }
Config.PRESETS = PRESETS

local function stored()
    return Prefs.get()
end

local function colorFor(index)
    if index == 5 then return stored().page_bg_custom or "#FFFFFF" end
    return PRESETS[index] or PRESETS[1]
end

-- Gives the open book its page color.
-- Whether a colour can be a page: light enough for black text (a page
-- background is paper, not a dark theme; night mode is KOReader's own).
function Config.isPageColor(hex)
    local r, g, b = tostring(hex or ""):match("^#?(%x%x)(%x%x)(%x%x)$")
    if not r then return false end
    local lum = (0.299 * tonumber(r, 16) + 0.587 * tonumber(g, 16) + 0.114 * tonumber(b, 16)) / 255
    return lum >= 0.6
end

-- The page colour to use now: white in night mode (KOReader inverts the
-- whole screen there, so a coloured page would be inverted too: a dark one
-- came out as a white page that flashed on every turn) and white for a
-- colour too dark to read on.
function Config.effectiveColor(index)
    local hex = colorFor(tonumber(index) or 1)
    if Screen.night_mode or not Config.isPageColor(hex) then return "#FFFFFF" end
    return hex
end

function Config.applyBackground(ui, index)
    index = tonumber(index) or 1
    local hex = Config.effectiveColor(index)
    local document = ui and ui.document
    if not document then return end
    if document.setBackgroundColor then
        try(document.setBackgroundColor, document, tonumber(hex:sub(2), 16))
    end
    if ui.view then
        if hex == "#FFFFFF" then
            -- KOReader's own page colour, as without Aleph.
            ui.view.page_bgcolor = nil
        else
            local ok, color = pcall(Blitbuffer.colorFromString, hex)
            if ok and color then ui.view.page_bgcolor = color end
        end
    end
    if ui.rolling and ui.document.configurable then
        ui:handleEvent(Event:new("UpdatePos"))
    end
    UIManager:setDirty(ui.dialog, "partial")
end

-- The reader's saved choice, applied when a book opens.
function Config.applySaved(ui)
    -- A choice saved for this book under the option's name before 1.1.46.
    try(function() require("aleph_migrate").pageBackground(ui) end)
    local configurable = ui.document and ui.document.configurable
    local index = configurable and tonumber(configurable.aleph_page_background)
    if index and index ~= 1 then Config.applyBackground(ui, index) end
end

-- Night mode switched: the book's colour goes (or comes back) with it.
function Config.nightChanged(ui)
    local configurable = ui and ui.document and ui.document.configurable
    local index = configurable and tonumber(configurable.aleph_page_background)
    if index and index ~= 1 then Config.applyBackground(ui, index) end
end

function Config.pickCustom(ui, done)
    local current = colorFor(5)
    require("aleph_color_wheel").open{
        title = _("Page color"), hex = current,
        on_use = function(hex)
            if not Config.isPageColor(hex) then
                try(function() require("aleph_toast").show(_("Too dark for a page: pick a lighter colour. Night mode makes pages dark."), { icon = "triangle-alert" }) end)
                return
            end
            local settings = Prefs.table()
            settings.page_bg_custom = hex
            try(function() G_reader_settings:flush() end)
            done()
        end,
    }
end

-- ------------------------------------------------------------- the tab
-- Added to KOReader's reflowable document options, before any book opens.
function Config.installOptions()
    local ok, CreOptions = pcall(require, "ui/data/creoptions")
    if not ok or type(CreOptions) ~= "table" or CreOptions._aleph_tab then return end
    CreOptions._aleph_tab = true
    table.insert(CreOptions, {
        icon = "appbar.contrast", aleph_tab = true,
        options = {
            {
                name = "aleph_page_background",
                name_text = _("Background"),
                toggle = { _("White"), _("Paper"), _("Sepia"), _("Gray"), _("Custom") },
                values = { 1, 2, 3, 4, 5 },
                default_value = 1,
                args = { 1, 2, 3, 4, 5 },
                event = "AlephSetPageBackground",
                help_text = _("The color of the page and its margins. Custom opens a color wheel."),
            },
        },
    })
end

-- ------------------------------------------------------------- restyle
local TAB_ICONS = {
    ["appbar.rotation"] = "rotate-cw-square", ["appbar.crop"] = "crop", ["appbar.pageview"] = "file-text",
    ["appbar.textsize"] = "type", ["appbar.contrast"] = "contrast", ["appbar.settings"] = "settings",
}

local FACES = { cfont = true, ffont = true, smallinfofont = true, x_smallinfofont = true, infont = true, smallffont = true }

-- Option names and choices: the board's font; sizes land on the board's
-- 15, 14 and 12 whatever KOReader asked for.
local function boardSize(size)
    return size >= 20 and BoardMetrics.fontSize(15) or size >= 15 and BoardMetrics.fontSize(14) or BoardMetrics.fontSize(12)
end
local function withFonts(build)
    -- The tab bar's icons are sized from one constant; it is answered with
    -- a smaller one (aleph_override.lua).
    Override.fonts(FACES, boardSize, Override.tabIcons, px(26), build)
end

local function restyleTabs(dialog)
    local bar = dialog.config_menubar
    if not bar or not bar.menu_items then return end
    local IconWidget = require("ui/widget/iconwidget")
    for index, button in ipairs(bar.menu_items) do
        local spec = dialog.config_options[index]
        local name = spec and (spec.aleph_tab and "palette" or TAB_ICONS[spec.icon])
        local file = name and BoardIcons.file(name, "#000000", 2.25)
        if file and button.image and button.image.file ~= file then
            button.image:free()
            button.image = IconWidget:new{ file = file, width = button.width, height = button.height, alpha = true }
            if button.horizontal_group then button.horizontal_group[2] = button.image end
        end
    end
end

local function wanted()
    return Prefs.styleDialogs()
end

function Config.install()
    local ok, ToggleSwitch = pcall(require, "ui/widget/toggleswitch")
    if ok and not ToggleSwitch._aleph_hooked then
        ToggleSwitch._aleph_hooked = true
        -- The chosen choice is black with white text, the others white.
        ToggleSwitch.fgcolor = Blitbuffer.COLOR_BLACK
        ToggleSwitch.bgcolor = Blitbuffer.COLOR_WHITE
        ToggleSwitch.font_face = BoardMetrics.faceFile("sans")
        ToggleSwitch.font_size = BoardMetrics.fontSize(14)
    end
    local ConfigDialog = require("ui/widget/configdialog")
    if ConfigDialog._aleph_hooked then return end
    ConfigDialog._aleph_hooked = true
    local original_update = ConfigDialog.update
    function ConfigDialog:update(...)
        if not wanted() then return original_update(self, ...) end
        BoardMetrics.refresh()
        -- Varargs belong to this function, not the nested callback.
        local args = { n = select("#", ...), ... }
        withFonts(function() original_update(self, unpack(args, 1, args.n)) end)
        local styled, why = pcall(function()
            restyleTabs(self)
            local frame = self.dialog_frame
            if frame then
                frame.radius = px(14)
                frame.bordersize = math.max(1, px(1.5))
                frame.color = BoardMetrics.INK.g6
            end
        end)
        if not styled then require("logger").warn("Aleph: reader controls restyle failed:", why) end
    end
end

return Config
