-- Modified for Aleph, 2026-11-07. Unofficial local-only fork. See NOTICE.
local FrameContainer = require("ui/widget/container/framecontainer")
local Device = require("device")
local px = require("aleph_board_metrics").px
local FOCUS_NAV = Device:hasDPad() and not Device:isTouchDevice()
local CatalogWidgets = {}
function CatalogWidgets.focusable(child)
    if not FOCUS_NAV then return child end
    return FrameContainer:new{
        margin = 0,
        padding = 0,
        bordersize = 0,
        focusable = true,
        focus_inner_border = true,
        focus_border_size = px(3),
        child,
    }
end

return CatalogWidgets
