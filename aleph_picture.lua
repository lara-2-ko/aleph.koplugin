-- Aleph modification, 2026-11-09: pictures drawn from a bitmap Aleph keeps,
-- without leaking memory.
--[[--
An ImageWidget given a bitmap and a scale makes its own scaled copy, freed
only by the widget's free(). Aleph's drawers rebuild their widgets on every
refresh, so each zoom step, swipe or page left a scaled copy behind; zoomed
in on a big picture pin that was tens of megabytes a step, until KOReader
was killed (crash.log ends in "Killed").

Here:
  view()     draws only the part of the bitmap that shows, scaled to the
             space it fills, so a picture costs about its size on screen at
             any zoom;
  track()    remembers the widgets made for a screen, and release() frees
             them, before the screen is rebuilt and when it closes;
  shrink()   brings a decoded picture down to a size worth keeping.
]]

local Picture = {}

local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min

function Picture.track(owner, widget)
    if owner and widget then
        owner._aleph_pictures = owner._aleph_pictures or {}
        table.insert(owner._aleph_pictures, widget)
    end
    return widget
end

function Picture.release(owner)
    if not owner or not owner._aleph_pictures then return end
    for _i, widget in ipairs(owner._aleph_pictures) do
        pcall(function() widget:free() end)
    end
    owner._aleph_pictures = nil
end

-- The part of `bb` that shows in w x h at `scale` (screen pixels per bitmap
-- pixel; nil or 0 fits the whole bitmap), centred on cx, cy (0..1). The
-- bitmap stays the caller's. Returns an ImageWidget, remembered for `owner`.
function Picture.view(owner, bb, w, h, scale, cx, cy)
    local ImageWidget = require("ui/widget/imagewidget")
    local bw, bh = bb:getWidth(), bb:getHeight()
    local fit = min(w / bw, h / bh)
    if not scale or scale <= 0 or scale <= fit * 1.0001 then
        -- The whole bitmap: the widget's copy is no bigger than w x h.
        return Picture.track(owner, ImageWidget:new{ image = bb, image_disposable = false,
            width = w, height = h, scale_factor = 0 })
    end
    local sw, sh = min(bw, max(1, ceil(w / scale))), min(bh, max(1, ceil(h / scale)))
    local x = max(0, min(bw - sw, floor((cx or 0.5) * bw - sw / 2 + 0.5)))
    local y = max(0, min(bh - sh, floor((cy or 0.5) * bh - sh / 2 + 0.5)))
    local Blitbuffer = require("ffi/blitbuffer")
    local crop = Blitbuffer.new(sw, sh, bb:getType())
    crop:blitFrom(bb, 0, 0, x, y, sw, sh)
    -- The widget's scaled copy is freed first on release, then the crop.
    local widget = ImageWidget:new{ image = crop, image_disposable = false,
        width = min(w, max(1, floor(sw * scale + 0.5))), height = min(h, max(1, floor(sh * scale + 0.5))),
        scale_factor = 0 }
    Picture.track(owner, widget)
    Picture.track(owner, { free = function() crop:free() end })
    return widget
end

-- `bb` brought within max_w x max_h (aspect kept). The original is freed when
-- a smaller one is made.
function Picture.shrink(bb, max_w, max_h)
    if not bb then return bb end
    local bw, bh = bb:getWidth(), bb:getHeight()
    local s = min(max_w / bw, max_h / bh)
    if s >= 1 then return bb end
    local ok, small = pcall(function()
        return require("ui/renderimage"):scaleBlitBuffer(bb, max(1, floor(bw * s)), max(1, floor(bh * s)), true)
    end)
    return ok and small or bb
end

-- After a screen full of pictures closes: Lua does not see the bitmaps'
-- memory, so it would wait long before freeing what that screen left. A full
-- collection, once the screen under it has been drawn.
local collect_task
function Picture.collectSoon()
    local UIManager = require("ui/uimanager")
    if collect_task then UIManager:unschedule(collect_task) end
    collect_task = function()
        collect_task = nil
        collectgarbage("collect")
    end
    UIManager:scheduleIn(0.6, collect_task)
end

return Picture
