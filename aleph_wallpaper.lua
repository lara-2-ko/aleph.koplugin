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
local _ = require("gettext")
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

-- One scratch picture for the widget opacity (Veil), kept while Aleph is
-- open and made larger when a larger widget needs it.
local scratch = nil

function WP.release()
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

-- The sheet (Customize Home > Add wallpaper). browser: the board's browser.
function WP.openSheet(browser)
    local UIManager = require("ui/uimanager")
    local T = require("ffi/util").template
    local BoardMetrics = require("aleph_board_metrics")
    local BoardUI = require("aleph_board_ui")
    local MenuUI = require("aleph_menu_ui")
    local Panel = require("aleph_panel")
    local INK, px, floor = BoardMetrics.INK, BoardMetrics.px, math.floor

    local function stored()
        local s = browser.settings.wallpaper
        return type(s) == "table" and s or {}
    end
    local function save(change)
        local s = {}
        for k, v in pairs(stored()) do s[k] = v end
        change(s)
        browser:persistSetting("wallpaper", next(s) and s or nil)
        browser:updateItems(nil, true)
    end

    local panel
    local function choose()
        local start = G_reader_settings:readSetting("home_dir") or "/"
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
                save(function(s) s.file = copy end)
                if panel and not panel.closed then panel:refresh() end
            end,
        })
    end

    local function step(list, value, delta)
        local i = 1
        for k, v in ipairs(list) do if math.abs(v - value) < 0.001 then i = k end end
        return list[math.max(1, math.min(#list, i + delta))]
    end

    panel = Panel:new{
        build = function(p, sw, sh)
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
        end,
        on_action = function(p, a)
            local c = WP.config(browser.settings) or {}
            if a.kind == "close" then p:close()
            elseif a.kind == "choose" then choose()
            elseif a.kind == "remove" then
                WP.release()
                save(function(s) s.file = nil end)
                p:refresh()
            elseif a.kind == "fit" then
                WP.release()
                save(function(s) s.fit = a.value end); p:refresh()
            elseif a.kind == "opacity" then
                save(function(s) s.opacity = step(WP.OPACITY_STEPS, c.opacity or WP.DEFAULT_OPACITY, a.delta) end); p:refresh()
            elseif a.kind == "widgets" then
                save(function(s) s.widgets = step(WP.WIDGET_STEPS, c.widgets or WP.DEFAULT_WIDGETS, a.delta) end); p:refresh()
            end
        end,
    }
    panel:show()
    return panel
end

return WP
