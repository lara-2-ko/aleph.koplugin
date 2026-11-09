-- Aleph modification, 2026-11-08: local light popup using the board's own Light tile.
local Device = require("device")
local Geom = require("ui/geometry")
local UIManager = require("ui/uimanager")
local Metrics = require("aleph_board_metrics")
local UI = require("aleph_board_ui")
local Data = require("aleph_board_data")
local Store = require("aleph_board_store")
local Widgets = require("aleph_board_widgets")
local MenuUI = require("aleph_menu_ui")
local MenuPage = require("aleph_menu_page")
local _ = require("gettext")
local px = Metrics.px
local LightSheet = {}

local function build(page, sw, sh)
    local light = Data.light()
    local state = Store.read(page.browser.settings)
    local w = math.min(px(480), sw - 2 * px(16))
    local pad = px(14)
    local iw = w - 2 * pad
    local tile_h = px(light and light.warmth ~= nil and 150 or 110)
    -- The on/off switch is a row of the menu kit, in a card like the menu's.
    local switch = MenuUI.group(iw, { MenuUI.row(MenuUI.rowsIn(iw), {
        icon = "sun", label = _("Frontlight"), s = 16, h = 48,
        toggle = light and light.on or false, action = { kind = "light-toggle" },
    }) })
    local switch_h = switch:getSize().h
    local h = tile_h + switch_h + px(44) + 2 * px(8) + 2 * pad
    local ctx = { d = { light = light, fingerprint = "light-popup:" .. tostring(light and light.brightness) .. ":" .. tostring(light and light.on)
        .. ":" .. tostring(light and light.warmth) }, tiles = state.tiles, colour = state.colour }
    local header = UI.hstack({ w = iw, h = px(44) }, {
        UI.text(_("Light"), { s = 20, b = true, w = iw - px(52) }),
        UI.flex(0), MenuUI.iconButton("x", { kind = "close" }),
    })
    local content = UI.vstack({ w = w, h = h, pad = pad }, {
        header, UI.space(nil, px(8)),
        switch, UI.space(nil, px(8)),
        Widgets.tile(ctx, { type = "light", chrome = "line" }, iw, tile_h),
    })
    local panel = UI.box({ w = w, h = h, radius = px(16), bg = Metrics.INK.white,
        border = math.max(1, px(1.5)), border_col = Metrics.INK.g6 }, content)
    local x, y = math.floor((sw - w) / 2), math.max(0, math.floor((sh - h) / 2))
    page.panel_rect = Geom:new{ x = x, y = y, w = w, h = h }
    return UI.overlay(sw, sh, { { widget = panel, x = x, y = y } })
end

local function adjust(page, action)
    local changed
    if action.kind == "light-toggle" then changed = Data.toggleLight()
    elseif action.kind == "light" then changed = Data.adjustLight(action.what, action.delta) end
    if not changed then return end
    -- "ui" repaints only the panel without the full-screen flash that
    -- "partial" causes on e-ink; the backdrop under it never changes.
    page:refresh("ui")
end

function LightSheet.open(browser)
    if not Device:hasFrontlight() then return end
    if browser.light_sheet and not browser.light_sheet.closed then return browser.light_sheet end
    local page = MenuPage:new{
        name = "aleph_light_sheet", browser = browser,
        backdrop = true, dismiss_outside = true, build = build, on_action = adjust,
        on_close = function(closed)
            if browser.light_sheet == closed then browser.light_sheet = nil end
            if not browser.closed then browser:updateItems() end
        end,
    }
    browser.light_sheet = page
    UIManager:show(page, "partial")
    if Device.screen:isColorEnabled() then
        UIManager:setDirty(page, function() return "partial", page.panel_rect, true end)
    end
    return page
end

return LightSheet
