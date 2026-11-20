-- Aleph modification, 2026-11-13: a wallpaper behind the Home widgets.
--[[--
Customize Home > Add wallpaper: a picture (JPG, PNG, WebP, GIF, BMP, SVG)
chosen from the device, copied to Aleph's settings so it stays if the file
is moved, drawn behind every page of Home. Its sheet sets:

  Fit                 Fill (the screen, edges trimmed) or Whole (all of it,
                      white around)
  Wallpaper opacity   10% to 100%: below 100% the picture is faded toward
                      the page colour, so text over it stays readable
  Widget opacity      40% to 100%: below 100% each widget lets the wallpaper
                      show through (the widget and what is under it are
                      mixed, by the C blitter: cheap even on a Kindle)
  Change picture, Remove

Settings: aleph.wallpaper = { file, fit, opacity, widgets }.
The picture is scaled once per screen size and kept while Home is open.
]]

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Geom = require("ui/geometry")
local Widget = require("ui/widget/widget")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("aleph_gettext")
local try = require("aleph_try").call

local Screen = Device.screen
local WP = {}

WP.OPACITY_STEPS = { 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1 }
WP.WIDGET_STEPS = { 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1 }
WP.DEFAULT_OPACITY = 0.4
WP.DEFAULT_WIDGETS = 0.8

local function clampStep(v, steps, default)
    v = tonumber(v) or default
    local best = steps[1]
    for _i, s in ipairs(steps) do if math.abs(s - v) < math.abs(best - v) then best = s end end
    return best
end

-- The wallpaper settings in use, or nil when none is set (or its file is gone).
function WP.config(settings)
    local c = type(settings) == "table" and settings.wallpaper
    if type(c) ~= "table" or type(c.file) ~= "string" then return nil end
    local lfs = require("libs/libkoreader-lfs")
    if lfs.attributes(c.file, "mode") ~= "file" then return nil end
    return {
        file = c.file,
        fit = c.fit == "whole" and "whole" or "fill",
        opacity = clampStep(c.opacity, WP.OPACITY_STEPS, WP.DEFAULT_OPACITY),
        widgets = clampStep(c.widgets, WP.WIDGET_STEPS, WP.DEFAULT_WIDGETS),
        text = (c.text == "dark" or c.text == "light") and c.text or "auto",
        outline = c.outline == true,
    }
end

-- ------------------------------------------------------------ the picture
local cache = { key = nil, bb = nil }

local function screenType()
    local t
    try(function() t = Screen.bb:getType() end)
    if t then return t end
    return Screen:isColorEnabled() and Blitbuffer.TYPE_BBRGB32 or Blitbuffer.TYPE_BB8
end

-- The picture at w×h as fitted, or nil. Kept for the next drawing.
function WP.image(c, w, h)
    local lfs = require("libs/libkoreader-lfs")
    local key = table.concat({ c.file, tostring(lfs.attributes(c.file, "modification")), w, h, c.fit }, "|")
    if cache.key == key and cache.bb then return cache.bb end
    WP.release()
    local ok, canvas = pcall(function()
        local RenderImage = require("ui/renderimage")
        local src = RenderImage:renderImageFile(c.file, false)
        if not src then return nil end
        local iw, ih = src:getWidth(), src:getHeight()
        local scale = c.fit == "whole" and math.min(w / iw, h / ih) or math.max(w / iw, h / ih)
        local sw, sh = math.max(1, math.floor(iw * scale + 0.5)), math.max(1, math.floor(ih * scale + 0.5))
        local scaled = RenderImage:scaleBlitBuffer(src, sw, sh, true)
        local out = Blitbuffer.new(w, h, screenType())
        out:fill(Blitbuffer.COLOR_WHITE)
        if c.fit == "whole" then
            out:blitFrom(scaled, math.floor((w - sw) / 2), math.floor((h - sh) / 2), 0, 0, sw, sh)
        else
            out:blitFrom(scaled, 0, 0, math.floor((sw - w) / 2), math.floor((sh - h) / 2), w, h)
        end
        scaled:free()
        return out
    end)
    if not ok then
        require("logger").warn("Aleph: wallpaper could not be drawn:", canvas)
        return nil
    end
    cache.key, cache.bb = key, canvas
    return canvas
end

-- ----------------------------------------------- Home's text over it
-- Aleph modification, 2026-11-18: Home's own text (the greeting, date,
-- status, buttons and the page dots and name at the foot) is drawn over the
-- wallpaper, not on a widget, so a dark picture hid it. "Text over the
-- wallpaper": Auto (dark or light, from how light the picture is behind the
-- header and behind the foot, each on its own), Dark, or Light; and an
-- optional outline in the other colour, for a busy picture.

-- How light the picture is (0 dark to 255 light) in a band of the screen,
-- as drawn: faded toward white by the wallpaper opacity. Looked at once per
-- picture, size and band.
local band_memo = {}
function WP.bandLight(c, w, h, y0, y1)
    local img = WP.image(c, w, h)
    if not img then return 255 end
    local key = table.concat({ cache.key or "", y0, y1, c.opacity }, "|")
    if band_memo[key] then return band_memo[key] end
    y0, y1 = math.max(0, math.floor(y0)), math.min(h - 1, math.floor(y1))
    local sum, n = 0, 0
    local sx = math.max(1, math.floor(w / 48))
    local sy = math.max(1, math.floor((y1 - y0 + 1) / 8))
    for y = y0, y1, sy do
        for x = 0, w - 1, sx do
            local ok, v = pcall(function() return img:getPixel(x, y):getColor8().a end)
            if ok and v then sum, n = sum + v, n + 1 end
        end
    end
    local lum = n > 0 and sum / n or 255
    lum = lum + (255 - lum) * (1 - c.opacity)
    band_memo[key] = lum
    return lum
end

-- The ink (aleph_board_ui.lua, BoardUI.withInk) for Home's text in a band
-- of the screen, or nil for the usual black.
function WP.inkFor(c, w, h, y0, y1)
    if not c then return nil end
    local light = c.text == "light"
    if c.text == "auto" then
        local ok, lum = pcall(WP.bandLight, c, w, h, y0, y1)
        light = ok and lum < 128 or false
    end
    if not light and not c.outline then return nil end
    local ink = {}
    if light then ink.invert = true end
    if c.outline then
        local BoardMetrics = require("aleph_board_metrics")
        ink.halo = light and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE
        ink.halo_hex = light and "#000000" or "#ffffff"
        ink.r = math.max(1, BoardMetrics.px(1))
    end
    return ink
end

-- One scratch picture for the widget opacity (Veil), kept while Aleph is
-- open and made larger when a larger widget needs it.
local scratch = nil

function WP.release()
    band_memo = {}
    if cache.bb then cache.bb:free() end
    cache.key, cache.bb = nil, nil
    if scratch then scratch:free() end
    scratch = nil
end

local function scratchFor(w, h, bbtype)
    if scratch and scratch:getWidth() >= w and scratch:getHeight() >= h and scratch:getType() == bbtype then
        return scratch
    end
    local nw, nh = w, h
    if scratch then
        nw, nh = math.max(w, scratch:getWidth()), math.max(h, scratch:getHeight())
        if scratch:getType() ~= bbtype then nw, nh = w, h end
        scratch:free()
    end
    scratch = Blitbuffer.new(nw, nh, bbtype)
    return scratch
end
WP._scratchFor = scratchFor

-- The wallpaper as a widget the size of the screen.
local Wall = Widget:extend{ w = 0, h = 0, conf = nil }
function Wall:getSize() return Geom:new{ w = self.w, h = self.h } end
function Wall:paintTo(bb, x, y)
    self.dimen = Geom:new{ x = x, y = y, w = self.w, h = self.h }
    local img = WP.image(self.conf, self.w, self.h)
    if not img then return end
    bb:blitFrom(img, x, y, 0, 0, self.w, self.h)
    if self.conf.opacity < 0.999 then bb:lightenRect(x, y, self.w, self.h, 1 - self.conf.opacity) end
end
WP.Wall = Wall

-- A widget drawn at `op` opacity over what is already painted under it:
-- what was there is kept aside, the widget painted, and the two mixed.
-- (Painted in place, so its tap areas are where they are seen.)
local Veil = WidgetContainer:extend{ op = 1 }
function Veil:getSize() return self[1]:getSize() end
function Veil:paintTo(bb, x, y)
    local s = self[1]:getSize()
    self.dimen = Geom:new{ x = x, y = y, w = s.w, h = s.h }
    if self.op >= 0.999 or s.w <= 0 or s.h <= 0 then return self[1]:paintTo(bb, x, y) end
    local under = scratchFor(s.w, s.h, bb:getType())
    under:blitFrom(bb, 0, 0, x, y, s.w, s.h)
    self[1]:paintTo(bb, x, y)
    bb:addblitFrom(under, x, y, 0, 0, s.w, s.h, 1 - self.op)
end
WP.Veil = Veil

-- ------------------------------------------------------------ choosing it
local EXT = { jpg = true, jpeg = true, png = true, webp = true, gif = true, bmp = true, svg = true }
function WP.isPicture(name) return EXT[(tostring(name):match("%.([^%.]+)$") or ""):lower()] == true end

-- Copies `path` to Aleph's settings and returns the copy's path, or nil, why.
function WP.adopt(path)
    local DataStorage = require("datastorage")
    local ffiutil = require("ffi/util")
    local ext = (path:match("%.([^%.]+)$") or "jpg"):lower()
    local dest = DataStorage:getSettingsDir() .. "/aleph_wallpaper." .. ext
    -- Earlier copies of other types go.
    for e in pairs(EXT) do
        local old = DataStorage:getSettingsDir() .. "/aleph_wallpaper." .. e
        if old ~= dest then os.remove(old) end
    end
    if path == dest then return dest end
    local ok, err = pcall(ffiutil.copyFile, path, dest)
    if not ok or err == false then return nil, tostring(err) end
    return dest
end

-- The sheet is kept in one table, `h`: browser (Home, whose settings hold the
-- wallpaper) and panel.
local function wpStored(h)
    local browser = h.browser
    local s = browser.settings.wallpaper
    return type(s) == "table" and s or {}
end

-- Saves the wallpaper settings after `change` has had its way with a copy, and
-- draws Home again behind the sheet.
local function wpSave(h, change)
    local browser = h.browser
    local s = {}
    for k, v in pairs(wpStored(h)) do s[k] = v end
    change(s)
    browser:persistSetting("wallpaper", next(s) and s or nil)
    browser:updateItems(nil, true)
end

-- Where the picture chooser opens: the folder the last picture came from,
-- else an "images" folder at the root of the device's storage (/mnt/us on a
-- Kindle, /mnt/onboard on a Kobo...), else KOReader's home folder.
-- `isDir` and `last` are for tests.
function WP.startFolder(last, isDir)
    isDir = isDir or function(p)
        local lfs = require("libs/libkoreader-lfs")
        return lfs.attributes(p, "mode") == "directory"
    end
    if last and isDir(last) then return last end
    local roots, seen = {}, {}
    local function root(r)
        if type(r) == "string" and r ~= "" and not seen[r] then seen[r] = true; roots[#roots + 1] = r:gsub("/+$", "") end
    end
    root(Device.home_dir)
    for _i, r in ipairs({ "/mnt/us", "/mnt/onboard", "/storage/emulated/0", "/sdcard" }) do root(r) end
    for _i, r in ipairs(roots) do
        for _j, name in ipairs({ "images", "Images", "IMAGES" }) do
            local p = r .. "/" .. name
            if isDir(p) then return p end
        end
    end
    local home = G_reader_settings and G_reader_settings:readSetting("home_dir")
    if home and isDir(home) then return home end
    return roots[1] and isDir(roots[1]) and roots[1] or "/"
end

local function wpChoose(h)
    local UIManager = require("ui/uimanager")
    local T = require("ffi/util").template
    local browser = h.browser
    local start = WP.startFolder(browser.settings and browser.settings.wallpaper_dir)
    UIManager:show(require("ui/widget/pathchooser"):new{
        select_directory = false, select_file = true, path = start,
        title = _("Choose a picture"),
        file_filter = function(name) return WP.isPicture(name) end,
        onConfirm = function(path)
            local copy, err = WP.adopt(path)
            if not copy then
                return browser:message(T(_("The picture could not be copied.\n%1"), tostring(err)))
            end
            WP.release()
            local dir = tostring(path):match("^(.*)/[^/]*$")
            if dir and dir ~= "" then browser:persistSetting("wallpaper_dir", dir) end
            wpSave(h, function(s) s.file = copy end)
            if h.panel and not h.panel.closed then h.panel:refresh() end
        end,
    })
end

-- The value one step up or down a list of steps from `value`.
local function wpStep(list, value, delta)
    local i = 1
    for k, v in ipairs(list) do if math.abs(v - value) < 0.001 then i = k end end
    return list[math.max(1, math.min(#list, i + delta))]
end

local function wpBuild(h, p, sw, sh)
    local T = require("ffi/util").template
    local BoardMetrics = require("aleph_board_metrics")
    local BoardUI = require("aleph_board_ui")
    local MenuUI = require("aleph_menu_ui")
    local INK, px, floor = BoardMetrics.INK, BoardMetrics.px, math.floor
    local browser = h.browser
    local c = WP.config(browser.settings)
    local w = math.min(px(520), sw - 2 * px(16))
    local pad = px(18)
    local iw = w - 2 * pad
    local items = {
        BoardUI.text(_("Wallpaper"), { s = 20, b = true, w = iw }),
        BoardUI.space(nil, px(12)),
    }
    if not c then
        items[#items + 1] = BoardUI.text(_("A picture behind the widgets on every page of Home. Choose one from this device (JPG, PNG, WebP…); it is copied, so it stays if the file is moved."),
            { s = 14, col = INK.g3, w = iw, lines = 5 })
        items[#items + 1] = BoardUI.space(nil, px(16))
        items[#items + 1] = MenuUI.pill(_("Choose a picture…"), { kind = "dark", w = iw, h = 48, s = 16, icon = "image", action = { kind = "choose" } })
    else
        local fit = c.fit == "whole" and 2 or 1
        local pct = function(v) return T(_("%1%"), floor(v * 100 + 0.5)) end
        local function row(label, sub, value, minus, plus)
            return BoardUI.hstack({ w = iw, h = px(64) }, {
                BoardUI.vstack({ w = iw - px(170) }, {
                    BoardUI.text(label, { s = 16, w = iw - px(170) }),
                    BoardUI.text(sub, { s = 12, col = INK.g4, w = iw - px(170), lines = 2 }),
                }),
                BoardUI.flex(0),
                MenuUI.stepper(value, nil, minus, plus),
            })
        end
        items[#items + 1] = BoardUI.text(_("Fit"), { s = 16, w = iw })
        items[#items + 1] = BoardUI.space(nil, px(6))
        items[#items + 1] = MenuUI.segmented(iw, { _("Fill"), _("Whole") }, fit, function(i) return { kind = "fit", value = i == 2 and "whole" or "fill" } end)
        items[#items + 1] = BoardUI.space(nil, px(12))
        items[#items + 1] = row(_("Wallpaper opacity"), _("Lower fades it, so text stays easy to read"), pct(c.opacity),
            { kind = "opacity", delta = -1 }, { kind = "opacity", delta = 1 })
        items[#items + 1] = row(_("Widget opacity"), _("Lower lets the wallpaper show through the widgets"), pct(c.widgets),
            { kind = "widgets", delta = -1 }, { kind = "widgets", delta = 1 })
        -- Home's own text (header, foot) over the picture.
        items[#items + 1] = BoardUI.space(nil, px(6))
        items[#items + 1] = BoardUI.text(_("Text over the wallpaper"), { s = 16, w = iw })
        items[#items + 1] = BoardUI.space(nil, px(6))
        local which = c.text == "dark" and 2 or c.text == "light" and 3 or 1
        items[#items + 1] = MenuUI.segmented(iw, { _.pgettext("Text colour", "Auto"), _.pgettext("Text colour", "Dark"), _.pgettext("Text colour", "Light") }, which,
            function(i) return { kind = "text", value = i == 2 and "dark" or i == 3 and "light" or "auto" } end)
        items[#items + 1] = BoardUI.hit(BoardUI.hstack({ w = iw, h = px(56) }, {
            BoardUI.vstack({ w = iw - px(80) }, {
                BoardUI.text(_("Outline"), { s = 16, w = iw - px(80) }),
                BoardUI.text(_("An edge in the other colour, for a busy picture"), { s = 12, col = INK.g4, w = iw - px(80), lines = 2 }),
            }),
            BoardUI.flex(0),
            MenuUI.toggle(c.outline),
        }), { kind = "outline" })
        items[#items + 1] = BoardUI.space(nil, px(14))
        local half = floor((iw - px(10)) / 2)
        items[#items + 1] = BoardUI.hstack({ w = iw, gap = px(10) }, {
            MenuUI.pill(_("Change picture"), { kind = "outline", w = half, h = 46, s = 15, action = { kind = "choose" } }),
            MenuUI.pill(_("Remove"), { kind = "outline", w = half, h = 46, s = 15, icon = "trash", action = { kind = "remove" } }),
        })
    end
    items[#items + 1] = BoardUI.space(nil, px(12))
    items[#items + 1] = MenuUI.pill(_("Done"), { kind = c and "dark" or "outline", w = iw, h = 46, s = 15, action = { kind = "close" } })
    local content = BoardUI.vstack({ w = w, pad = pad }, items)
    local border = math.max(1, px(1.5))
    local ph = content:getSize().h + 2 * border
    local widget = BoardUI.box({ w = w, h = ph, radius = px(16), bg = INK.white, border = border, border_col = INK.black }, content)
    -- At the foot, so the page above shows the change.
    local x, y = floor((sw - w) / 2), math.max(px(8), sh - ph - px(16))
    p.panel_rect = Geom:new{ x = x, y = y, w = w, h = ph }
    return BoardUI.overlay(sw, sh, { { widget = widget, x = x, y = y } })
end

local function wpAction(h, p, a)
    local browser = h.browser
    local c = WP.config(browser.settings) or {}
    if a.kind == "close" then p:close()
    elseif a.kind == "choose" then wpChoose(h)
    elseif a.kind == "remove" then
        WP.release()
        wpSave(h, function(s) s.file = nil end)
        p:refresh()
    elseif a.kind == "fit" then
        WP.release()
        wpSave(h, function(s) s.fit = a.value end); p:refresh()
    elseif a.kind == "opacity" then
        wpSave(h, function(s) s.opacity = wpStep(WP.OPACITY_STEPS, c.opacity or WP.DEFAULT_OPACITY, a.delta) end); p:refresh()
    elseif a.kind == "text" then
        wpSave(h, function(s) s.text = a.value ~= "auto" and a.value or nil end); p:refresh()
    elseif a.kind == "outline" then
        wpSave(h, function(s) s.outline = not c.outline or nil end); p:refresh()
    elseif a.kind == "widgets" then
        wpSave(h, function(s) s.widgets = wpStep(WP.WIDGET_STEPS, c.widgets or WP.DEFAULT_WIDGETS, a.delta) end); p:refresh()
    end
end

-- The sheet (Customize Home > Add wallpaper). browser: the board's browser.
function WP.openSheet(browser)
    local Panel = require("aleph_panel")
    local h = { browser = browser }
    h.panel = Panel:new{
        build = function(p, sw, sh) return wpBuild(h, p, sw, sh) end,
        on_action = function(p, a) return wpAction(h, p, a) end,
    }
    h.panel:show()
    return h.panel
end

return WP
