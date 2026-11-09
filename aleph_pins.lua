-- Aleph modification, 2026-11-08: pinned pages.
--[[--
Keep a page, or a picture, at hand while you read.

  Pin: hold text and tap Pin in the menu (that page is pinned), or hold a
       picture and choose Pin image (the picture itself is kept). Pin again on
       a pinned page to unpin it.
  Badge: once something is pinned, a small badge with a pin and the count sits
       at the bottom corner of the page, above the status bar. It is painted on
       the page (not a window over it); tap it to open the newest pin in a
       drawer, hold it for the list of every pin.
  Drawer: the pinned page beside your reading, small or large (the resize
       icon). + and − (or pinch and spread on the picture) zoom it, a swipe
       moves a zoomed picture, the zoom level goes back to the whole page.
       Arrows step through the pins, the expand icon (or the picture) opens a
       full screen view (KOReader's own image viewer), the corner arrow goes
       to the page (Back returns), the bin removes the pin.
  All pins: hold the badge, or use the "Aleph: pinned pages" gesture
       action: tap one to view it, the arrow to go to its page, hold to remove.

Pins are kept in the book's own settings. The newest pin is also KOReader's
own pinned page, so the page browser and Go to > Go to pinned page see it.

Structure after ZenOS's pinned pages: the badge is painted by ReaderView and
reached through touch zones, and KOReader's own pin and go-to-pin actions use
these pins.
]]

local Device = require("device")
local Event = require("ui/event")
local Geom = require("ui/geometry")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local BoardMetrics = require("aleph_board_metrics")
local BoardUI = require("aleph_board_ui")
local MenuUI = require("aleph_menu_ui")
local Panel = require("aleph_panel")

local Screen = Device.screen
local INK = BoardMetrics.INK
local px = BoardMetrics.px
local floor = math.floor

local Picture = require("aleph_picture")
local KEY = "aleph_pins"
local Pins = {}

local function wanted()
    local stored = G_reader_settings:readSetting("aleph")
    return not (type(stored) == "table" and stored.pins_enabled == false)
end

local function toast(text, icon)
    pcall(function() require("aleph_toast").show(text, { icon = icon or "pin" }) end)
end

-- ------------------------------------------------------------------ store
function Pins.list(ui)
    local list = require("aleph_migrate").docKey(ui.doc_settings, KEY)
    if type(list) ~= "table" then
        list = {}
        ui.doc_settings:saveSetting(KEY, list)
    end
    return list
end

function Pins.pageOf(ui, pin)
    local location = pin.location
    if ui.rolling and type(location) == "string" then
        local ok, page = pcall(ui.document.getPageFromXPointer, ui.document, location)
        if ok and page then return page end
    elseif type(location) == "number" then
        return location
    end
    return ui:getCurrentPage()
end

local function imageDir()
    local dir = require("datastorage"):getDataDir() .. "/cache/aleph/pins"
    require("util").makePath(dir)
    return dir
end

-- A Blitbuffer is a cdata, not a Lua table.
local function isBitmap(value)
    if value == nil or type(value) == "function" then return false end
    local ok, writer = pcall(function() return value.writePNG end)
    return ok and writer ~= nil
end

local function saveImage(image)
    local bb
    if type(image) == "function" then
        local ok, result = pcall(image, 1)
        bb = ok and result or nil
    elseif isBitmap(image) then
        bb = image
    end
    if not bb then return nil end
    local name = require("ffi/sha2").md5(tostring(os.time()) .. tostring(os.clock())) .. ".png"
    local path = imageDir() .. "/" .. name
    local ok = pcall(function() bb:writePNG(path) end)
    if type(image) == "function" then pcall(image, false) end
    return ok and path or nil
end

-- What changed: the badge repaints, the footer count follows, KOReader's own
-- single pinned page follows the newest pin.
local function changed(ui)
    local list = Pins.list(ui)
    if list[1] then ui.doc_settings:saveSetting("pinned_page", list[1].location)
    else ui.doc_settings:delSetting("pinned_page") end
    local footer = ui.view and ui.view.footer
    if footer and ui.view.footer_visible and footer.onUpdateFooter then pcall(footer.onUpdateFooter, footer, true, true) end
    Pins.repaintBadge(ui)
end

-- The index of the page pin on `page`, if any.
function Pins.indexOfPage(ui, page)
    for i, pin in ipairs(Pins.list(ui)) do
        if pin.kind == "page" and Pins.pageOf(ui, pin) == page then return i end
    end
end

-- spec: kind ("page" or "image"), page, snippet, image.
function Pins.add(ui, spec)
    local list = Pins.list(ui)
    local page = spec.page or ui:getCurrentPage()
    local location = ui.rolling and ui.document:getPageXPointer(page) or page
    if spec.kind == "page" then
        for _i, pin in ipairs(list) do
            if pin.kind == "page" and Pins.pageOf(ui, pin) == page then
                toast(_("This page is already pinned."))
                return false
            end
        end
    end
    local pin = { kind = spec.kind, location = location, snippet = spec.snippet, at = os.time() }
    if spec.kind == "image" then
        pin.file = saveImage(spec.image)
        if not pin.file then
            toast(_("The picture could not be pinned."), "x")
            return false
        end
    end
    table.insert(list, 1, pin)
    ui.doc_settings:saveSetting(KEY, list)
    changed(ui)
    toast(spec.kind == "image" and _("Picture pinned") or _("Page pinned"))
    return true
end

function Pins.remove(ui, index)
    local list = Pins.list(ui)
    local pin = table.remove(list, index)
    if pin and pin.file then os.remove(pin.file) end
    ui.doc_settings:saveSetting(KEY, list)
    changed(ui)
end

-- ----------------------------------------------------------- pictures
-- done(bb): the pinned page as a bitmap of about w x h (a page is drawn by
-- KOReader's page thumbnail machinery, in the background), or the pinned
-- picture as it was saved. The bitmap given is the caller's to free.
-- Where a picture pin's file is. Pictures pinned before 0.1.60 point into
-- cache/readingboard/pins, which the rename moved to cache/aleph/pins: such a
-- pin is found again by its file name and its path corrected in the book's
-- settings. nil when the file is gone.
function Pins.imageFile(ui, pin)
    local lfs = require("libs/libkoreader-lfs")
    local file = pin.file
    if type(file) ~= "string" then return nil end
    if lfs.attributes(file, "mode") == "file" then return file end
    local name = file:match("([^/]+)$")
    local moved = name and (imageDir() .. "/" .. name)
    if moved and lfs.attributes(moved, "mode") == "file" then
        pin.file = moved
        pcall(function() ui.doc_settings:saveSetting(KEY, Pins.list(ui)) end)
        return moved
    end
    return nil
end

function Pins.render(ui, pin, w, h, done)
    if pin.kind == "image" then
        local file = Pins.imageFile(ui, pin)
        if not file then return done(nil) end
        -- Decoded at full size, then kept no bigger than asked: a phone photo
        -- or a map can be tens of megabytes as a bitmap.
        local ok, bb = pcall(function() return require("ui/renderimage"):renderImageFile(file, false) end)
        bb = ok and bb or nil
        if bb then bb = require("aleph_picture").shrink(bb, w, h) end
        done(bb)
        return
    end
    local page = Pins.pageOf(ui, pin)
    if not ui.thumbnail then return done(nil) end
    ui.thumbnail:getPageThumbnail(page, w, h, "aleph_pins", function(tile)
        -- ReaderThumbnail supplies a TileCacheItem, not a BlitBuffer.
        -- Copy its bitmap because the thumbnail cache owns the original.
        local bb = tile and tile.bb
        done(bb and bb:copy() or nil)
    end)
end

function Pins.openViewer(ui, pin)
    local ImageViewer = require("ui/widget/imageviewer")
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    if pin.kind ~= "image" then toast(_("Preparing the page…"), "file-text") end
    Pins.render(ui, pin, floor(sw * 1.5), floor(sh * 1.5), function(bb)
        if not bb then toast(_("The pinned page could not be shown."), "x"); return end
        UIManager:show(ImageViewer:new{ image = bb, image_disposable = true, with_title_bar = false, fullscreen = true })
    end)
end

function Pins.goTo(ui, pin)
    if ui.link and ui.link.addCurrentLocationToStack then pcall(ui.link.addCurrentLocationToStack, ui.link) end
    if ui.rolling and type(pin.location) == "string" then
        ui:handleEvent(Event:new("GotoXPointer", pin.location))
    else
        ui:handleEvent(Event:new("GotoPage", Pins.pageOf(ui, pin)))
    end
end

-- ------------------------------------------------------------------ badge
-- A pin and the count, painted on the page by ReaderView (a window over the
-- page would take part in every gesture; this does not).
local function side()
    local stored = G_reader_settings:readSetting("aleph")
    return (type(stored) == "table" and stored.pins_left) and "left" or "right"
end

local function badgeWidget(ui, count)
    BoardMetrics.refresh()
    local background = ui.view and ui.view.page_bgcolor or INK.white
    local cached = ui._rb_pin_badge
    if cached and cached.count == count and cached.background == background
            and cached.scale == BoardMetrics.get().dp then
        return cached
    end
    if cached and cached.widget and cached.widget.free then cached.widget:free() end
    local h = px(28)
    local border = math.max(1, px(1.5))
    local content = BoardUI.hstack({ gap = px(5) }, {
        BoardUI.icon("pin-badge", px(15), { sw = 2.25, fill = true }), BoardUI.text(tostring(count), { s = 13, b = true }),
    })
    local w = content:getSize().w + 2 * px(10) + 2 * border
    local widget = BoardUI.box({ w = w, h = h, radius = px(8), border = border, border_col = INK.black, bg = background },
        BoardUI.hstack({ w = w - 2 * border, h = h - 2 * border }, { BoardUI.flex(0), content, BoardUI.flex(0) }))
    cached = { count = count, background = background, scale = BoardMetrics.get().dp, widget = widget, w = w, h = h }
    ui._rb_pin_badge = cached
    return cached
end

-- Where the badge sits: one of eight places around the page (corners and
-- edge middles), nudged from there (dp, in steps of NUDGE). Saved as
-- pins_badge = { anchor = "br", dx = 0, dy = 0 }; without it, the bottom
-- corner on the side the drawer opens.
local ANCHORS = { "tl", "tc", "tr", "ml", "mr", "bl", "bc", "br" }
local ANCHOR_LABELS = {
    tl = function() return _("Top left") end, tc = function() return _("Top") end, tr = function() return _("Top right") end,
    ml = function() return _("Left") end, mr = function() return _("Right") end,
    bl = function() return _("Bottom left") end, bc = function() return _("Bottom") end, br = function() return _("Bottom right") end,
}
local NUDGE = 8
Pins.ANCHORS, Pins.NUDGE = ANCHORS, NUDGE

function Pins.badgePlace()
    local stored = G_reader_settings:readSetting("aleph")
    local place = type(stored) == "table" and type(stored.pins_badge) == "table" and stored.pins_badge or {}
    local anchor = place.anchor
    if not ANCHOR_LABELS[anchor] then anchor = side() == "left" and "bl" or "br" end
    return { anchor = anchor, dx = tonumber(place.dx) or 0, dy = tonumber(place.dy) or 0 }
end

function Pins.setBadgePlace(place)
    local stored = G_reader_settings:readSetting("aleph")
    if type(stored) ~= "table" then stored = {} end
    stored.pins_badge = { anchor = place.anchor, dx = place.dx ~= 0 and place.dx or nil, dy = place.dy ~= 0 and place.dy or nil }
    G_reader_settings:saveSetting("aleph", stored)
end

function Pins.placeLabel(place)
    place = place or Pins.badgePlace()
    local label = ANCHOR_LABELS[place.anchor]()
    if place.dx ~= 0 or place.dy ~= 0 then label = label .. " " .. _("(moved)") end
    return label
end

-- The rectangle for a badge w x h on a screen sw x sh above a status bar
-- footer_h tall, at place (pure, for testing).
function Pins.placeRect(place, w, h, sw, sh, footer_h, unit)
    unit = unit or px
    local margin = unit(14)
    local col, row = place.anchor:sub(2, 2), place.anchor:sub(1, 1)
    local x = (col == "l" and margin) or (col == "r" and sw - w - margin) or floor((sw - w) / 2)
    if place.anchor == "ml" then x = margin elseif place.anchor == "mr" then x = sw - w - margin end
    local y = (row == "t" and unit(8)) or (row == "b" and sh - (footer_h or 0) - h - unit(4)) or floor((sh - h) / 2)
    x = x + unit(place.dx or 0)
    y = y + unit(place.dy or 0)
    x = math.max(0, math.min(sw - w, x))
    y = math.max(0, math.min(sh - h, y))
    return x, y
end

-- Where the badge is, given the status bar.
local function badgeRect(ui, badge)
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    local footer = ui.view and ui.view.footer
    local footer_h = 0
    if footer and ui.view.footer_visible and footer.getHeight then
        local ok, height = pcall(footer.getHeight, footer)
        footer_h = ok and height or 0
    end
    -- Above Aleph's bottom line too, when it shows.
    pcall(function() footer_h = footer_h + require("aleph_bookends").bottomHeight(ui) end)
    local x, y = Pins.placeRect(Pins.badgePlace(), badge.w, badge.h, sw, sh, footer_h)
    return Geom:new{ x = x, y = y, w = badge.w, h = badge.h }
end

function Pins.paintBadge(view, bb)
    local ui = view.ui
    if not ui or not ui._rb_pins_attached or not wanted() or bb ~= Screen.bb then return end
    local count = #Pins.list(ui)
    if count == 0 then ui._rb_pin_rect = nil; return end
    local ok, badge = pcall(badgeWidget, ui, count)
    if not ok then return end
    local rect = badgeRect(ui, badge)
    ui._rb_pin_rect = rect
    pcall(badge.widget.paintTo, badge.widget, bb, rect.x, rect.y)
end

-- Repaints the badge's old and new place.
function Pins.repaintBadge(ui)
    if not ui.view then return end
    local before = ui._rb_pin_rect
    local count = #Pins.list(ui)
    local region = before and before:copy()
    if count > 0 then
        local ok, badge = pcall(badgeWidget, ui, count)
        if ok then
            local rect = badgeRect(ui, badge)
            region = region and region:combine(rect) or rect
        end
    end
    if region then
        local pad = px(4)
        region = Geom:new{ x = region.x - pad, y = region.y - pad, w = region.w + 2 * pad, h = region.h + 2 * pad }
        UIManager:setDirty(ui.dialog or "all", "ui", region)
    end
end

-- ------------------------------------------------------------------ drawer
-- The pinned page in a drawer at the bottom corner. Taps outside close it.
--
-- Two sizes, small and large (the resize icon in the header; the choice is
-- remembered). The picture zooms in the drawer: + and − under it, or pinch
-- and spread on it; swipe on a zoomed picture to move around it, and tap the
-- zoom level to go back to the whole page. The expand icon, or a tap on the
-- picture, still opens the full screen viewer.
local ZOOMS = { 1, 1.5, 2, 3, 4 }

local function drawerLarge()
    local stored = G_reader_settings:readSetting("aleph")
    return type(stored) == "table" and stored.pins_large == true
end

local function setDrawerLarge(on)
    local stored = G_reader_settings:readSetting("aleph")
    if type(stored) ~= "table" then stored = {} end
    stored.pins_large = on and true or nil
    G_reader_settings:saveSetting("aleph", stored)
end

-- The zoom step after (dir 1) or before (dir -1) z.
local function zoomStep(z, dir)
    if dir > 0 then
        for _i, v in ipairs(ZOOMS) do if v > z + 0.01 then return v end end
        return ZOOMS[#ZOOMS]
    end
    for i = #ZOOMS, 1, -1 do if ZOOMS[i] < z - 0.01 then return ZOOMS[i] end end
    return 1
end
Pins.zoomStep = zoomStep

-- Keeps the view's centre (ratios of the picture) inside the picture: the
-- visible part never runs past an edge.
function Pins.clampCenter(c, visible)
    if visible >= 1 then return 0.5 end
    local half = visible / 2
    return math.max(half, math.min(1 - half, c))
end

local function zoomLabel(z)
    if z == floor(z) then return string.format("%d×", z) end
    return string.format("%.1f×", z)
end

function Pins.openDrawer(ui, index)
    local pins = Pins.list(ui)
    if #pins == 0 then
        toast(_("Nothing is pinned in this book. Hold text and tap Pin."), "pin")
        return
    end
    local state = { index = math.max(1, math.min(index or 1, #pins)), thumbs = {}, failed = {}, large = drawerLarge(),
        zoom = 1, cx = 0.5, cy = 0.5 }
    local panel
    local function free()
        Picture.release(state)
        for _i, bb in pairs(state.thumbs) do
            if bb and bb.free then bb:free() end
        end
        state.thumbs = {}
        Picture.collectSoon()
    end
    local function resetView()
        state.zoom, state.cx, state.cy = 1, 0.5, 0.5
    end
    -- The picture is drawn once at the screen's size, so both drawer sizes and
    -- every zoom step use the same bitmap.
    local function failKey(pin) return tostring(pin.file or pin.location or pin.page) end
    local function request(i)
        if state.requested == i then return end
        local pin = Pins.list(ui)[i]
        if not pin or state.failed[failKey(pin)] then return end
        state.requested = i
        local sw, sh = Screen:getWidth(), Screen:getHeight()
        UIManager:nextTick(function()
            if not panel or panel.closed then return end
            Pins.render(ui, pin, sw, sh, function(bb)
                if panel.closed then
                    if bb and bb.free then bb:free() end
                    return
                end
                state.requested = nil
                if not bb then
                    -- Asked once: a missing picture is not decoded again on
                    -- every redraw (which made the drawer crawl).
                    state.failed[failKey(pin)] = true
                    if state.index == i then panel:refresh() end
                    return
                end
                if state.thumbs[i] and state.thumbs[i].free then state.thumbs[i]:free() end
                state.thumbs[i] = bb
                if state.index == i then panel:refresh() end
            end)
        end)
    end
    -- How much of the picture shows across and down at the current zoom.
    local function visible()
        local bb, view = state.thumbs[state.index], state.view
        if not bb or not view then return 1, 1 end
        local fit = math.min(view.w / bb:getWidth(), view.h / bb:getHeight())
        local scale = fit * state.zoom
        return view.w / (bb:getWidth() * scale), view.h / (bb:getHeight() * scale), scale
    end
    local function setZoom(z)
        z = math.max(1, math.min(ZOOMS[#ZOOMS], z))
        if z == state.zoom then return end
        state.zoom = z
        if z == 1 then state.cx, state.cy = 0.5, 0.5 end
        local vx, vy = visible()
        state.cx, state.cy = Pins.clampCenter(state.cx, vx), Pins.clampCenter(state.cy, vy)
        panel:refresh()
    end
    panel = Panel:new{
        build = function(p, sw, sh)
            local list = Pins.list(ui)
            state.index = math.max(1, math.min(state.index, math.max(1, #list)))
            local pin = list[state.index]
            if not pin then p:close(); return BoardUI.overlay(sw, sh, {}) end
            local pw = state.large and math.min(px(440), floor(sw * 0.8)) or math.min(px(240), floor(sw * 0.46))
            local pad = px(10)
            local iw = pw - 2 * pad
            local th = math.min(floor(iw * sh / sw), floor(sh * (state.large and 0.62 or 0.5)))
            local function control(name, action, size, on)
                local col = (on == false) and "gb" or "black"
                local c = BoardUI.hstack({ w = px(40), h = px(36) }, { BoardUI.flex(0), BoardUI.icon(name, px(size or 20), { sw = 2.25, col = col }), BoardUI.flex(0) })
                return (on == false) and c or BoardUI.hit(c, action)
            end
            local header = BoardUI.hstack({ w = iw, h = px(36) }, {
                BoardUI.icon("pin", px(17), { sw = 2.25 }), BoardUI.space(px(6), 1),
                BoardUI.text(state.index .. " / " .. #list, { s = 14, b = true }), BoardUI.flex(0),
                control(state.large and "minimize-2" or "maximize-2", { kind = "size" }, 18),
                control("maximize", { kind = "view" }, 18), control("x", { kind = "close" }),
            })
            local bb = state.thumbs[state.index]
            local inner_w, inner_h = iw - 2, th - 2
            state.view = { w = inner_w, h = inner_h }
            -- The pictures of the last build go before new ones are made.
            Picture.release(state)
            local picture
            if bb then
                local scale
                if state.zoom > 1 then scale = select(3, visible()) end
                picture = Picture.view(state, bb, inner_w, inner_h, scale, state.cx, state.cy)
            else
                local failed = state.failed[failKey(pin)]
                local note = failed and (pin.kind == "image" and _("The picture's file is missing.") or _("This page could not be drawn."))
                picture = BoardUI.hstack({ w = iw, h = th }, { BoardUI.flex(0),
                    failed and BoardUI.text(note, { s = 14, col = INK.g4, w = iw - 2 * px(16), align = "center" })
                        or BoardUI.text("…", { s = 18, col = INK.g6 }), BoardUI.flex(0) })
                if not failed then request(state.index) end
            end
            local framed = BoardUI.box({ w = iw, h = th, radius = px(6), border = math.max(1, px(1)), border_col = INK.g9, bg = INK.white },
                BoardUI.hstack({ w = inner_w, h = inner_h }, { BoardUI.flex(0), picture, BoardUI.flex(0) }))
            -- Zoom: − level +; the level returns to the whole page.
            local can_out, can_in = state.zoom > 1, state.zoom < ZOOMS[#ZOOMS]
            local level = BoardUI.hit(BoardUI.hstack({ w = px(56), h = px(36) }, { BoardUI.flex(0),
                BoardUI.text(zoomLabel(state.zoom), { s = 13, b = true, col = state.zoom > 1 and INK.black or INK.g4 }), BoardUI.flex(0) }), { kind = "zoom-reset" })
            local label = pin.snippet and pin.snippet ~= "" and BoardUI.text(pin.snippet, { s = 12, col = INK.g3, w = iw - 3 * px(40) - px(56) - px(8), lines = 1, data = true })
                or BoardUI.text(pin.kind == "image" and _("Picture") or _("Page") .. " " .. Pins.pageOf(ui, pin), { s = 12, col = INK.g3 })
            local zoom_row = BoardUI.hstack({ w = iw, h = px(36) }, {
                label, BoardUI.flex(px(8)),
                control("zoom-out", { kind = "zoom", dir = -1 }, 19, can_out), level, control("zoom-in", { kind = "zoom", dir = 1 }, 19, can_in),
            })
            if not state.large then
                -- Narrow: the name above, the zoom controls on their own row.
                zoom_row = BoardUI.vstack({ w = iw }, {
                    pin.snippet and pin.snippet ~= "" and BoardUI.text(pin.snippet, { s = 12, col = INK.g3, w = iw, lines = 2, data = true })
                        or BoardUI.text(pin.kind == "image" and _("Picture") or _("Page") .. " " .. Pins.pageOf(ui, pin), { s = 12, col = INK.g3, w = iw }),
                    BoardUI.hstack({ w = iw, h = px(36) }, { BoardUI.flex(0),
                        control("zoom-out", { kind = "zoom", dir = -1 }, 19, can_out), level, control("zoom-in", { kind = "zoom", dir = 1 }, 19, can_in), BoardUI.flex(0) }),
                })
            end
            local footer = BoardUI.hstack({ w = iw, h = px(40) }, {
                control("chevron-left", { kind = "prev" }), BoardUI.flex(0), control("corner-up-right", { kind = "goto" }),
                BoardUI.flex(0), control("trash", { kind = "remove" }), BoardUI.flex(0), control("chevron-right", { kind = "next" }),
            })
            local content = BoardUI.vstack({ w = pw, pad = pad }, {
                header, BoardUI.space(nil, px(4)), BoardUI.hit(framed, { kind = "view" }), BoardUI.space(nil, px(4)), zoom_row,
                BoardUI.space(nil, px(2)), footer,
            })
            local border = math.max(1, px(1.5))
            local ph = content:getSize().h + 2 * border
            local widget = BoardUI.box({ w = pw, h = ph, radius = px(14), border = border, border_col = INK.g6, bg = INK.white }, content)
            local x = side() == "right" and (sw - pw) or 0
            local y = math.max(0, sh - ph)
            p.panel_rect = Geom:new{ x = x, y = y, w = pw, h = ph }
            -- Where the picture is, for pinches and swipes on it.
            state.picture_rect = Geom:new{ x = x + border + pad, y = y + border + pad + px(36) + px(4), w = iw, h = th }
            return BoardUI.overlay(sw, sh, { { widget = widget, x = x, y = y } })
        end,
        on_action = function(p, action)
            local list = Pins.list(ui)
            local pin = list[state.index]
            local k = action.kind
            if k == "close" then p:close()
            elseif k == "prev" and #list > 0 then state.index = (state.index - 2) % #list + 1; resetView(); p:refresh()
            elseif k == "next" and #list > 0 then state.index = state.index % #list + 1; resetView(); p:refresh()
            elseif k == "view" and pin then
                if not state.failed[failKey(pin)] then Pins.openViewer(ui, pin) end
            elseif k == "goto" and pin then p:close(); Pins.goTo(ui, pin)
            elseif k == "size" then
                state.large = not state.large
                setDrawerLarge(state.large)
                local vx, vy = 1, 1
                p:rebuild() -- the new size first, so the view is kept inside it
                vx, vy = visible()
                state.cx, state.cy = Pins.clampCenter(state.cx, vx), Pins.clampCenter(state.cy, vy)
                -- The drawer changes size: repaint the page where it was.
                UIManager:setDirty("all", "ui")
                p:refresh()
            elseif k == "zoom" then setZoom(zoomStep(state.zoom, action.dir))
            elseif k == "zoom-reset" then if state.zoom > 1 then setZoom(1) end
            elseif k == "remove" and pin then
                require("aleph_confirm").show{
                    title = _("Remove pin"), text = _("The pin is removed from this book. The page itself is not changed."),
                    ok_label = _("Remove"), on_ok = function()
                        Pins.remove(ui, state.index)
                        -- Pictures are kept by place in the list, which has
                        -- just moved up by one: drawn again from the new list.
                        free()
                        state.requested = nil
                        resetView()
                        if #Pins.list(ui) == 0 then p:close() else p:refresh() end
                    end,
                }
            end
        end,
        -- On the picture: spread / pinch zoom, a swipe moves a zoomed picture.
        on_gesture = function(p, ges)
            local rect = state.picture_rect
            local pos = ges.pos
            if not rect or not pos or not pos:intersectWith(rect) then return false end
            if ges.ges == "spread" then setZoom(zoomStep(state.zoom, 1)); return true end
            if ges.ges == "pinch" then setZoom(zoomStep(state.zoom, -1)); return true end
            if ges.ges == "swipe" and state.zoom > 1 then
                local vx, vy = visible()
                local d = ges.distance or 0
                local dir = ges.direction or ""
                local dx = (dir:find("east") and d or 0) - (dir:find("west") and d or 0)
                local dy = (dir:find("south") and d or 0) - (dir:find("north") and d or 0)
                -- The picture follows the finger, so the view moves against it.
                state.cx = Pins.clampCenter(state.cx - dx / state.view.w * vx, vx)
                state.cy = Pins.clampCenter(state.cy - dy / state.view.h * vy, vy)
                p:refresh()
                return true
            end
            return false
        end,
        on_close = free,
    }
    panel:show()
    return panel
end

-- ----------------------------------------------------------------- placer
-- Where the badge sits, and the side the drawer opens on. Over a book the
-- page stays in view and the badge moves as you choose; the panel keeps to
-- the half of the screen away from it.
function Pins.openPlacer(ui, on_close)
    local place = Pins.badgePlace()
    local in_book = ui and ui.document and ui._rb_pins_attached
    local panel
    local function badgeAtTop()
        local rect = in_book and ui._rb_pin_rect
        if rect then return rect.y < Screen:getHeight() / 2 end
        return place.anchor:sub(1, 1) == "t"
    end
    local function changed()
        Pins.setBadgePlace(place)
        if in_book then Pins.repaintBadge(ui) end
        local before = panel.panel_rect and panel.panel_rect:copy()
        panel:refresh()
        -- The panel may have moved to the other half: the page where it was.
        if before and panel.panel_rect and (before.y ~= panel.panel_rect.y or before.h ~= panel.panel_rect.h) then
            UIManager:setDirty("all", "ui", before)
        end
    end
    panel = Panel:new{
        build = function(p, sw, sh)
            local pw = math.min(px(440), sw - 2 * px(12))
            local pad = px(16)
            local iw = pw - 2 * pad
            local close = BoardUI.hit(BoardUI.hstack({ w = px(44), h = px(40) }, { BoardUI.flex(0), BoardUI.icon("x", px(22), { sw = 2.25 }), BoardUI.flex(0) }), { kind = "close" })
            local title = BoardUI.vstack({ w = iw - px(44) }, {
                BoardUI.text(_("Pinned pages"), { s = 18, b = true }),
                BoardUI.text(_("Where the pin badge sits on the page"), { s = 13, col = INK.g4, w = iw - px(44) }),
            })
            -- A small page with the eight places; the chosen one inked.
            local mw = px(120)
            local mh = floor(mw * sh / sw)
            local dot = px(26)
            local m = px(6)
            local spots = {}
            for _i, a in ipairs(ANCHORS) do
                local col, row = a:sub(2, 2), a:sub(1, 1)
                if a == "ml" then col = "l" elseif a == "mr" then col = "r" end
                local x = (col == "l" and m) or (col == "r" and mw - dot - m) or floor((mw - dot) / 2)
                local y = (row == "t" and m) or (row == "b" and mh - dot - m) or floor((mh - dot) / 2)
                local on = place.anchor == a
                local mark = BoardUI.box({ w = dot, h = dot, radius = px(6), border = on and 0 or math.max(1, px(1.25)), border_col = INK.g6, bg = on and INK.black or INK.white },
                    BoardUI.hstack({ w = dot, h = dot }, { BoardUI.flex(0), on and BoardUI.icon("pin", px(14), { sw = 2.25, col = "white" }) or BoardUI.space(1, 1), BoardUI.flex(0) }))
                spots[#spots + 1] = { widget = BoardUI.hit(mark, { kind = "anchor", anchor = a }), x = x, y = y }
            end
            local lines = {}
            for i = 1, 5 do
                lines[#lines + 1] = { widget = BoardUI.rect(mw - 2 * px(30), math.max(1, px(2)), INK.ge), x = px(30), y = floor(mh * (0.22 + i * 0.1)) }
            end
            local frame = { { widget = BoardUI.box({ w = mw, h = mh, radius = px(10), border = math.max(1, px(1.5)), border_col = INK.black, bg = INK.white }) } }
            for _i, l in ipairs(lines) do frame[#frame + 1] = l end
            for _i, sp in ipairs(spots) do frame[#frame + 1] = sp end
            local mini = BoardUI.overlay(mw, mh, frame)
            -- Nudge: a pad of arrows, and Reset.
            local function arrow(name, dx, dy)
                local b = math.max(1, px(1.25))
                local box = BoardUI.box({ w = px(48), h = px(44), radius = px(10), border = b, border_col = INK.g6, bg = INK.white },
                    BoardUI.hstack({ w = px(48) - 2 * b, h = px(44) - 2 * b }, { BoardUI.flex(0), BoardUI.icon(name, px(22), { sw = 2.5 }), BoardUI.flex(0) }))
                return BoardUI.hit(box, { kind = "nudge", dx = dx, dy = dy })
            end
            local gap = px(6)
            local pad_w = 3 * px(48) + 2 * gap
            local nudge = BoardUI.vstack({ w = pad_w }, {
                BoardUI.text(_("Move it"), { s = 13, b = true, col = INK.g4 }),
                BoardUI.space(nil, px(6)),
                BoardUI.hstack({ w = pad_w }, { BoardUI.flex(0), arrow("chevron-up", 0, -NUDGE), BoardUI.flex(0) }),
                BoardUI.space(nil, gap),
                BoardUI.hstack({ w = pad_w, gap = gap }, { arrow("chevron-left", -NUDGE, 0), arrow("chevron-down", 0, NUDGE), arrow("chevron-right", NUDGE, 0) }),
                BoardUI.space(nil, px(8)),
                BoardUI.text(Pins.placeLabel(place), { s = 13, col = INK.g3, w = pad_w, align = "center" }),
            })
            local body = BoardUI.hstack({ w = iw, valign = "center" }, { BoardUI.flex(0), mini, BoardUI.flex(0), nudge, BoardUI.flex(0) })
            local panel_side = side() == "left" and 1 or 2
            local foot = MenuUI.segmented(iw, { _("Drawer on the left"), _("On the right") }, panel_side, function(index) return { kind = "drawer-side", left = index == 1 } end)
            local reset = BoardUI.hstack({ w = iw }, {
                BoardUI.hit(MenuUI.pill(_("Reset"), { kind = "outline", h = 40, s = 14, icon = "rotate-ccw", icon_size = 16 }), { kind = "reset" }),
                BoardUI.flex(0),
                BoardUI.hit(MenuUI.pill(_("Done"), { h = 40, s = 14, icon = "check", icon_size = 16 }), { kind = "close" }),
            })
            local content = BoardUI.vstack({ w = pw, pad = pad }, {
                BoardUI.hstack({ w = iw, valign = "top" }, { title, BoardUI.flex(0), close }),
                BoardUI.space(nil, px(14)), body,
                BoardUI.space(nil, px(14)), foot,
                BoardUI.space(nil, px(12)), reset,
            })
            local border = math.max(1, px(1.5))
            local ph = content:getSize().h + 2 * border
            local widget = BoardUI.box({ w = pw, h = ph, radius = px(16), border = border, border_col = INK.black, bg = INK.white }, content)
            local x = floor((sw - pw) / 2)
            local y = badgeAtTop() and (sh - ph - px(24)) or px(24)
            p.panel_rect = Geom:new{ x = x, y = y, w = pw, h = ph }
            return BoardUI.overlay(sw, sh, { { widget = widget, x = x, y = y } })
        end,
        on_action = function(p, action)
            local k = action.kind
            if k == "anchor" then
                place.anchor, place.dx, place.dy = action.anchor, 0, 0
                changed()
            elseif k == "nudge" then
                place.dx, place.dy = place.dx + action.dx, place.dy + action.dy
                changed()
            elseif k == "reset" then
                place = { anchor = side() == "left" and "bl" or "br", dx = 0, dy = 0 }
                local stored = G_reader_settings:readSetting("aleph")
                if type(stored) == "table" then stored.pins_badge = nil; G_reader_settings:saveSetting("aleph", stored) end
                if in_book then Pins.repaintBadge(ui) end
                p:refresh()
            elseif k == "drawer-side" then
                local stored = G_reader_settings:readSetting("aleph")
                if type(stored) ~= "table" then stored = {} end
                stored.pins_left = action.left or nil
                G_reader_settings:saveSetting("aleph", stored)
                p:refresh()
            end
        end,
        on_close = function()
            if on_close then UIManager:nextTick(on_close) end
        end,
    }
    panel:show()
    return panel
end

-- ------------------------------------------------------------------- list
function Pins.openList(ui)
    local list = Pins.list(ui)
    if #list == 0 then
        toast(_("Nothing is pinned in this book. Hold text and tap Pin."), "pin")
        return
    end
    local page_of_list = 1
    local panel
    panel = Panel:new{
        build = function(p, sw, sh)
            local pins = Pins.list(ui)
            local w = math.min(px(500), sw - 2 * px(12))
            local pad = px(14)
            local iw = w - 2 * pad
            local row_h = 60
            local per = math.max(3, floor((sh * 0.7 - px(140)) / px(row_h)))
            local pages = math.max(1, math.ceil(#pins / per))
            page_of_list = math.max(1, math.min(page_of_list, pages))
            local header = BoardUI.hstack({ w = iw, h = px(44) }, {
                BoardUI.icon("pin", px(20), { sw = 2.25 }), BoardUI.space(px(8), 1),
                BoardUI.text(_("Pinned pages"), { s = 20, b = true }), BoardUI.flex(0), MenuUI.iconButton("x", { kind = "close" }),
            })
            local items = { header, BoardUI.space(nil, px(6)) }
            for i = (page_of_list - 1) * per + 1, math.min(#pins, page_of_list * per) do
                local pin = pins[i]
                local title = (pin.kind == "image" and _("Picture") or _("Page")) .. " " .. Pins.pageOf(ui, pin)
                local snippet = pin.snippet and pin.snippet ~= "" and pin.snippet or ""
                local text_w = iw - px(44) - px(44) - px(10)
                local body = BoardUI.vstack({ w = text_w }, {
                    BoardUI.text(title, { s = 15, b = true, w = text_w }),
                    snippet ~= "" and BoardUI.text(snippet, { s = 12, col = INK.g3, w = text_w, data = true }) or BoardUI.space(nil, 1),
                })
                local row = BoardUI.hstack({ w = iw, h = px(row_h) }, {
                    BoardUI.hstack({ w = px(36), h = px(row_h) }, { BoardUI.flex(0), BoardUI.icon(pin.kind == "image" and "layout-grid" or "file-text", px(20), { sw = 2 }), BoardUI.flex(0) }),
                    BoardUI.hit(BoardUI.hstack({ w = text_w + px(10), h = px(row_h) }, { body, BoardUI.flex(0) }), { kind = "view", i = i, hold = "remove" }),
                    BoardUI.hit(BoardUI.hstack({ w = px(44), h = px(row_h) }, { BoardUI.flex(0), BoardUI.icon("corner-up-right", px(20), { sw = 2.25 }), BoardUI.flex(0) }), { kind = "goto", i = i }),
                })
                table.insert(items, BoardUI.hit(row, { kind = "view", i = i, hold = "remove" }))
                table.insert(items, BoardUI.rect(iw, math.max(1, px(0.75)), INK.gc))
            end
            if pages > 1 then
                local function step(name, delta)
                    return BoardUI.hit(BoardUI.hstack({ w = px(52), h = px(44) }, { BoardUI.flex(0), BoardUI.icon(name, px(22), { sw = 2.25 }), BoardUI.flex(0) }),
                        { kind = "page", delta = delta })
                end
                table.insert(items, BoardUI.hstack({ w = iw, h = px(44) }, { step("chevron-left", -1), BoardUI.flex(0),
                    BoardUI.text(page_of_list .. " / " .. pages, { s = 14, b = true }), BoardUI.flex(0), step("chevron-right", 1) }))
            end
            table.insert(items, BoardUI.space(nil, px(6)))
            table.insert(items, BoardUI.text(_("Tap to view, the arrow to go to the page, hold to remove."), { s = 12, col = INK.g4, w = iw, lines = 2 }))
            local content = BoardUI.vstack({ w = w, pad = pad }, items)
            local border = math.max(1, px(1.5))
            local ph = content:getSize().h + 2 * border
            local widget = BoardUI.box({ w = w, h = ph, radius = px(16), bg = INK.white, border = border, border_col = INK.g6 }, content)
            local x, y = floor((sw - w) / 2), math.max(px(8), floor((sh - ph) / 2))
            p.panel_rect = Geom:new{ x = x, y = y, w = w, h = ph }
            return BoardUI.overlay(sw, sh, { { widget = widget, x = x, y = y } })
        end,
        on_action = function(p, action)
            local pin = action.i and Pins.list(ui)[action.i]
            if action.kind == "view" and pin then
                p:close()
                Pins.openViewer(ui, pin)
            elseif action.kind == "goto" and pin then
                p:close()
                Pins.goTo(ui, pin)
            elseif action.kind == "page" then
                page_of_list = page_of_list + action.delta
                p:refresh()
            end
        end,
        on_hold = function(p, action)
            if action.hold == "remove" and action.i then
                require("aleph_confirm").show{
                    title = _("Remove pin"), text = _("The pin is removed from this book. The page itself is not changed."),
                    ok_label = _("Remove"), on_ok = function()
                        Pins.remove(ui, action.i)
                        if #Pins.list(ui) == 0 then p:close() else p:refresh() end
                    end,
                }
            end
        end,
    }
    panel:show()
    return panel
end

-- ------------------------------------------------- hold a picture to pin it
-- Holding a picture normally opens it. Here it opens a small menu at the
-- finger: View image, or Pin image. (Text holds are not touched.)
local function imageMenu(highlight, pos, spec, open)
    local ui = highlight.ui
    local used = false
    local panel
    local function release()
        if used then return end
        used = true
        local image = spec.image
        if type(image) == "function" then pcall(image, false)
        elseif spec.image_disposable ~= false and isBitmap(image) then pcall(image.free, image) end
    end
    panel = Panel:new{
        build = function(p, sw, sh)
            local w = math.min(px(300), sw - 2 * px(12))
            local pad = px(12)
            local gap = px(8)
            local cw = floor((w - 2 * pad - gap) / 2)
            local function cell(name, label, action)
                local border = math.max(1, px(1.25))
                local inner = BoardUI.hstack({ w = cw - 2 * border, h = px(52) - 2 * border }, {
                    BoardUI.flex(0), BoardUI.hstack({ gap = px(8) }, {
                        BoardUI.icon(name, px(20), { sw = 2.25 }), BoardUI.text(label, { s = 14, b = true, w = cw - px(52), data = true }) }),
                    BoardUI.flex(0) })
                return BoardUI.hit(BoardUI.box({ w = cw, h = px(52), radius = px(12), border = border, border_col = INK.g6, bg = INK.white }, inner), action)
            end
            local content = BoardUI.vstack({ w = w, pad = pad }, {
                BoardUI.hstack({ w = w - 2 * pad, gap = gap }, {
                    cell("maximize", _("View image"), { kind = "view" }), cell("pin", _("Pin image"), { kind = "pin" }) }),
            })
            local border = math.max(1, px(1.5))
            local ph = content:getSize().h + 2 * border
            local widget = BoardUI.box({ w = w, h = ph, radius = px(16), bg = INK.white, border = border, border_col = INK.g6 }, content)
            local x = math.max(px(8), math.min(sw - w - px(8), floor(pos.x - w / 2)))
            local y = math.max(px(8), math.min(sh - ph - px(8), floor(pos.y - ph - px(16))))
            p.panel_rect = Geom:new{ x = x, y = y, w = w, h = ph }
            return BoardUI.overlay(sw, sh, { { widget = widget, x = x, y = y } })
        end,
        on_action = function(p, action)
            if action.kind == "view" then
                used = true
                local viewer = open()
                p:close()
                UIManager:show(viewer)
            elseif action.kind == "pin" then
                local position = highlight.view:screenToPageTransform(pos)
                local page = position and position.page or ui:getCurrentPage()
                local image = spec.image
                used = true
                p:close()
                Pins.add(ui, { kind = "image", page = page, image = image })
                if spec.image_disposable ~= false and isBitmap(image) then pcall(image.free, image) end
            end
        end,
        on_close = release,
    }
    return panel
end

function Pins.install()
    local Highlight = require("apps/reader/modules/readerhighlight")
    if Highlight._aleph_pins then return end
    Highlight._aleph_pins = true
    local original_hold = Highlight.onHold
    function Highlight:onHold(arg, ges)
        if not wanted() or not ges or not ges.pos then return original_hold(self, arg, ges) end
        local ImageViewer = require("ui/widget/imageviewer")
        local own_new = rawget(ImageViewer, "new")
        local factory = ImageViewer.new
        ImageViewer.new = function(class, spec)
            ImageViewer.new = own_new
            local ok, menu = pcall(imageMenu, self, ges.pos, spec, function() return factory(class, spec) end)
            if ok then return menu end
            require("logger").warn("Aleph: image menu failed:", menu)
            return factory(class, spec)
        end
        local ok, result = pcall(original_hold, self, arg, ges)
        ImageViewer.new = own_new
        if not ok then error(result, 0) end
        return result
    end

    -- The badge is painted by the reader's view.
    local View = require("apps/reader/modules/readerview")
    if not View._aleph_pins then
        View._aleph_pins = true
        local paint = View.paintTo
        View.paintTo = function(self, bb, x, y)
            paint(self, bb, x, y)
            Pins.paintBadge(self, bb)
        end
    end

    -- KOReader's own "Pin page" and "Go to pinned page" use these pins.
    local Goto = require("apps/reader/modules/readergoto")
    if not Goto._aleph_pins then
        Goto._aleph_pins = true
        local pin = Goto.onPinPage
        Goto.onPinPage = function(self, page, remove)
            if not wanted() or not self.ui._rb_pins_attached then return pin(self, page, remove) end
            local ui = self.ui
            page = page or ui:getCurrentPage()
            local at = Pins.indexOfPage(ui, page)
            if remove then
                if at then Pins.remove(ui, at) end
            elseif not at then
                Pins.add(ui, { kind = "page", page = page })
            end
            return true
        end
        local go = Goto.onGoToPinnedPage
        Goto.onGoToPinnedPage = function(self, ...)
            if not wanted() or not self.ui._rb_pins_attached or #Pins.list(self.ui) == 0 then return go(self, ...) end
            Pins.openDrawer(self.ui, 1)
            return true
        end
    end
end

-- Attaches to the book that is open: the Pin button in the text menu and the
-- touch zones of the badge.
function Pins.attach(ui)
    if not wanted() or not ui.document then return end
    if ui._rb_pins_attached then return end
    ui._rb_pins_attached = true
    if ui.highlight and ui.highlight.addToHighlightDialog then
        ui.highlight:addToHighlightDialog("13_rb_pin", function(this)
            local selection = this.selected_text
            local pos = selection and selection.pos0
            local page
            if ui.rolling and type(pos) == "string" then page = ui.document:getPageFromXPointer(pos)
            elseif type(pos) == "table" then page = pos.page end
            page = page or ui:getCurrentPage()
            local at = Pins.indexOfPage(ui, page)
            return {
                text = at and _("Unpin") or _("Pin"),
                callback = function()
                    local snippet = selection and selection.text and selection.text:gsub("%s+", " "):sub(1, 140) or nil
                    this:onClose()
                    if at then
                        local now = Pins.indexOfPage(ui, page)
                        if now then Pins.remove(ui, now) end
                    else
                        Pins.add(ui, { kind = "page", page = page, snippet = snippet })
                    end
                end,
            }
        end)
    end
    ui:registerPostInitCallback(function()
        if not ui._rb_pins_attached then return end
        -- Tap and hold on the badge take precedence over the page's own zones,
        -- and anything else goes to the page as usual.
        local overrides = { "readerfooter_tap", "readerfooter_hold", "readerlink_tap", "readerhighlight_tap",
            "tap_forward", "tap_backward", "readermenu_tap", "readermenu_ext_tap" }
        for id, zone in pairs(ui._zones or {}) do
            if zone.def and (zone.def.ges == "tap" or zone.def.ges == "hold") then overrides[#overrides + 1] = id end
        end
        local function hit(ges)
            local box = ui._rb_pin_rect
            return wanted() and box and ges and ges.pos and #Pins.list(ui) > 0
                and ges.pos.x >= box.x - box.w * 0.1 and ges.pos.x < box.x + box.w * 1.1
                and ges.pos.y >= box.y - box.h * 0.1 and ges.pos.y < box.y + box.h * 1.1
        end
        local zones = {}
        for _i, gesture in ipairs({ "tap", "hold" }) do
            zones[#zones + 1] = { id = "rb_pin_" .. gesture, ges = gesture,
                screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 }, overrides = overrides,
                handler = function(ges)
                    if not hit(ges) then return false end
                    if gesture == "hold" then Pins.openList(ui) else Pins.openDrawer(ui, 1) end
                    return true
                end,
            }
        end
        ui:registerTouchZones(zones)
    end)
end

function Pins.detach(ui)
    if not ui then return end
    ui._rb_pins_attached = nil
    ui._rb_pin_rect = nil
    local cached = ui._rb_pin_badge
    if cached and cached.widget and cached.widget.free then cached.widget:free() end
    ui._rb_pin_badge = nil
end

return Pins
