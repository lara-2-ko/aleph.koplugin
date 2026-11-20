local Prefs = require("aleph_prefs")
local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")

local Screen = Device.screen
local Style = {}
local interface_sizes = { [100] = 1, [105] = 1.05, [110] = 1.1, [115] = 1.15, [120] = 1.2, [125] = 1.25, [130] = 1.3, [140] = 1.4, [150] = 1.5 }

-- The sixteen grays Aleph draws with, by the same names.
Style.ink = {
    black = Blitbuffer.COLOR_BLACK, g2 = Blitbuffer.COLOR_GRAY_2, g4 = Blitbuffer.COLOR_GRAY_4,
    g6 = Blitbuffer.COLOR_GRAY_6, g8 = Blitbuffer.COLOR_DARK_GRAY, g9 = Blitbuffer.COLOR_GRAY_9,
    gb = Blitbuffer.COLOR_GRAY_B, gd = Blitbuffer.COLOR_GRAY_D, ge = Blitbuffer.COLOR_GRAY_E,
    white = Blitbuffer.COLOR_WHITE,
}

-- With Aleph installed its own metrics are used, so a size here is
-- the same size there; without it the same rules are applied directly:
-- Noto Sans, KOReader's scale, a gentle density step and the interface size
-- chosen in Aleph's settings (1.05 by default).
local function board()
    local ok, metrics = pcall(require, "aleph_board_metrics")
    if ok and type(metrics) == "table" and metrics.px and metrics.face and metrics.setUserScale then
        return metrics
    end
end

local synced
local function sync(metrics)
    local value = tonumber(Prefs.get().ui_scale) or nil
    if value ~= synced then
        synced = value
        if value then metrics.setUserScale(value) end
    end
end

local function scale()
    local selected = tonumber(Prefs.get().ui_scale)
    local size = selected and interface_sizes[math.floor(selected * 100 + 0.5)]
    local dpi, short = Screen:getDPI(), math.min(Screen:getWidth(), Screen:getHeight())
    local density = 1
    if dpi and dpi > 0 and short > 0 then
        density = math.max(0.78, math.min(1.12, math.sqrt(3.6 * dpi / short)))
        density = math.floor(density * 100 + 0.5) / 100
    end
    return density * (size or 1.05)
end

-- Aleph modification, 2026-11-18: the top menu's own font and text size
-- (aleph_fonts.lua; Settings > Top menu > Font, Text size). The size scales
-- the whole menu with its text: rows, icons and tabs.
local function menuScale()
    local ok, v = pcall(function() return require("aleph_fonts").menuScale() end)
    return ok and tonumber(v) or 1
end

local function menuFile()
    local ok, c = pcall(function() return require("aleph_fonts").menu() end)
    return ok and type(c) == "table" and c.file or "NotoSans-Regular.ttf"
end

function Style.px(size)
    size = size * menuScale()
    local metrics = board()
    if metrics then
        sync(metrics)
        return metrics.px(size)
    end
    return Screen:scaleBySize(size * scale())
end

function Style.face(size)
    size = size * menuScale()
    local metrics = board()
    if metrics then
        sync(metrics)
        return metrics.fileFace(menuFile(), size)
    end
    return Font:getFace(menuFile(), size * scale())
end

function Style.rowFace()
    return Style.face(16)
end

-- A bundled icon file.
function Style.icon(root, name)
    return root .. "/icons/" .. name .. ".svg"
end

return Style
