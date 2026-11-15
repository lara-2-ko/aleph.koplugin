-- Aleph modification, 2026-11-13: coloured page bookmarks, as in the Kindle
-- app.
--[[--
A page bookmark gets a colour (Red, Orange, Yellow, Green, Aqua, Blue,
Purple, Pink). KOReader's dog-ear in the top-right corner becomes a ribbon
in that colour (in shades of grey on a black-and-white screen).

  adding a bookmark   (the corner tap, the reader menu's switch, a gesture):
                      it takes the colour used last, and a list of the
                      colours drops from the ribbon to change it (Settings >
                      Reader > Choose a colour when bookmarking turns that
                      list off); "Remove bookmark" at its foot
  the reader menu     its "Bookmark this page" switch adds one the same way:
                      the menu closes and the list drops from the ribbon
  the bookmarks page  each page bookmark's icon is in its colour

The colour is kept on KOReader's own bookmark (annotation field
`aleph_color`), so it stays with the book's other annotations and follows
them wherever they are copied. Bookmarks made before have the default
colour.
]]

local Prefs = require("aleph_prefs")
local _ = require("aleph_gettext")
local try = require("aleph_try").call

local BC = {}

BC.COLORS = {
    { id = "red", label = function() return _("Red") end, hex = "#D8654F" },
    { id = "orange", label = function() return _("Orange") end, hex = "#E8903A" },
    { id = "yellow", label = function() return _("Yellow") end, hex = "#E8C33E" },
    { id = "green", label = function() return _("Green") end, hex = "#5E9F6B" },
    { id = "aqua", label = function() return _("Aqua") end, hex = "#4FAFBD" },
    { id = "blue", label = function() return _("Blue") end, hex = "#4D6DB5" },
    { id = "purple", label = function() return _("Purple") end, hex = "#8A6EBE" },
    { id = "pink", label = function() return _("Pink") end, hex = "#D581B1" },
}
local BY_ID = {}
for _i, c in ipairs(BC.COLORS) do BY_ID[c.id] = c end
BC.DEFAULT = "blue"

function BC.hex(id)
    local c = BY_ID[id] or BY_ID[BC.DEFAULT]
    return c.hex
end
function BC.known(id) return BY_ID[id] ~= nil end

local function settings()
    return Prefs.get()
end
local function save(key, value)
    Prefs.set(key, value)
end

-- The colour a new bookmark takes: the one chosen last.
function BC.last()
    local id = settings().bookmark_color_last
    return BY_ID[id] and id or BC.DEFAULT
end
function BC.setLast(id) if BY_ID[id] then save("bookmark_color_last", id) end end

-- Whether adding a bookmark shows the list of colours.
function BC.askOnAdd() return settings().bookmark_color_ask ~= false end

-- The page bookmark of the page shown, or nil.
function BC.currentItem(ui)
    local item
    try(function()
        local bm = ui.bookmark
        local index = bm:getDogearBookmarkIndex(bm:getCurrentPageNumber())
        item = index and ui.annotation.annotations[index] or nil
    end)
    return item
end

function BC.colorOf(item)
    local id = type(item) == "table" and item.aleph_color
    return BY_ID[id] and id or BC.DEFAULT
end

-- ------------------------------------------------------------ the ribbon
local ribbon_written = {}
function BC.ribbonFile(hex)
    local DataStorage = require("datastorage")
    local lfs = require("libs/libkoreader-lfs")
    local dir = DataStorage:getDataDir() .. "/cache/aleph/icons"
    local path = dir .. "/ribbon-" .. hex:gsub("#", "") .. ".svg"
    if ribbon_written[path] then return path end
    if lfs.attributes(path, "mode") ~= "file" then
        try(function()
            if lfs.attributes(dir, "mode") ~= "directory" then
                lfs.mkdir(DataStorage:getDataDir() .. "/cache/aleph")
                lfs.mkdir(dir)
            end
        end)
        local f = io.open(path, "w")
        if not f then return nil end
        -- A ribbon hanging from the top edge, with a notch at its foot; a thin
        -- dark edge keeps light colours visible on grey screens.
        f:write(string.format([[<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="M5.5 0H18.5V23.2L12 18.4L5.5 23.2Z" fill="%s" stroke="#2B2B2B" stroke-width="0.9" stroke-linejoin="round"/></svg>]], hex))
        f:close()
    end
    ribbon_written[path] = true
    return path
end

-- The dog-ear's picture set to a ribbon of `hex` (rebuilt only when the
-- colour or the size changes; KOReader rebuilds it itself on other sizes).
local function ensureRibbon(dogear, hex)
    local size = dogear.dogear_size
    if not size or not dogear.vgroup then return end
    if dogear._aleph_hex == hex and dogear._aleph_size == size and dogear.icon and dogear.icon._aleph_ribbon then return end
    local file = BC.ribbonFile(hex)
    if not file then return end
    local ImageWidget = require("ui/widget/imagewidget")
    local widget = ImageWidget:new{ file = file, width = size, height = size, alpha = true }
    widget._aleph_ribbon = true
    local old = dogear.icon
    -- The picture is the vertical group's second item (after the top pad).
    for i, w in ipairs(dogear.vgroup) do
        if w == old then dogear.vgroup[i] = widget end
    end
    if old and old.free and old ~= widget then pcall(old.free, old) end
    dogear.icon = widget
    dogear.vgroup:resetLayout()
    dogear._aleph_hex, dogear._aleph_size = hex, size
end

-- ------------------------------------------------------------ the list
function BC.showPicker(ui, item)
    if not item then return end
    local Geom = require("ui/geometry")
    local Blitbuffer = require("ffi/blitbuffer")
    local UIManager = require("ui/uimanager")
    local Event = require("ui/event")
    local BoardMetrics = require("aleph_board_metrics")
    local BoardUI = require("aleph_board_ui")
    local Panel = require("aleph_panel")
    local INK, px = BoardMetrics.INK, BoardMetrics.px
    local current = BC.colorOf(item)
    local panel = Panel:new{
        build = function(p, sw, sh)
            local w = math.min(px(300), sw - 2 * px(16))
            local pad = px(10)
            local iw = w - 2 * pad
            local rh = px(54)
            local rows = {}
            for _i, c in ipairs(BC.COLORS) do
                local on = c.id == current
                local d = px(26)
                local dot = BoardUI.circle(d, { bg = Blitbuffer.colorFromString(c.hex), border = math.max(1, px(1)), border_col = INK.g4 }, BoardUI.space(1, 1))
                local line = BoardUI.hstack({ w = iw, h = rh }, {
                    BoardUI.space(px(10), 1), dot, BoardUI.space(px(16), 1),
                    BoardUI.text(c.label(), { s = 16, b = on }), BoardUI.flex(0),
                    on and BoardUI.icon("check", px(22), { sw = 2.5 }) or BoardUI.space(px(22), 1), BoardUI.space(px(12), 1),
                })
                rows[#rows + 1] = BoardUI.hit(line, { kind = "color", id = c.id })
            end
            rows[#rows + 1] = BoardUI.rect(iw, math.max(1, px(1)), INK.g6)
            rows[#rows + 1] = BoardUI.hit(BoardUI.hstack({ w = iw, h = rh }, {
                BoardUI.space(px(10), 1), BoardUI.icon("trash", px(22), { sw = 2.25 }), BoardUI.space(px(18), 1),
                BoardUI.text(_("Remove bookmark"), { s = 16 }), BoardUI.flex(0),
            }), { kind = "remove" })
            local content = BoardUI.vstack({ w = w, pad = pad }, rows)
            local border = math.max(1, px(1.5))
            local ph = content:getSize().h + 2 * border
            local widget = BoardUI.box({ w = w, h = ph, radius = px(14), bg = INK.white, border = border, border_col = INK.black }, content)
            -- Under the ribbon, at the right edge, as the Kindle app does.
            local x = sw - w - px(14)
            local y = math.min(px(64), math.max(px(8), sh - ph - px(8)))
            p.panel_rect = Geom:new{ x = x, y = y, w = w, h = ph }
            return BoardUI.overlay(sw, sh, { { widget = widget, x = x, y = y } })
        end,
        on_action = function(p, action)
            if action.kind == "color" then
                p:close()
                BC.setColor(ui, item, action.id)
            elseif action.kind == "remove" then
                p:close()
                ui:handleEvent(Event:new("ToggleBookmark"))
            end
        end,
    }
    -- Shown with a refresh of its own rectangle: on e-ink a window shown
    -- without one is drawn but not put on the screen until something else
    -- refreshes that part (the reader menu closing did; a tap on the page's
    -- corner refreshes only the ribbon).
    panel:show()
    return panel
end

function BC.setColor(ui, item, id)
    if not (item and BY_ID[id]) then return end
    item.aleph_color = id
    BC.setLast(id)
    try(function()
        local Event = require("ui/event")
        ui:handleEvent(Event:new("AnnotationsModified", { item }))
    end)
    try(function()
        local UIManager = require("ui/uimanager")
        UIManager:setDirty(ui.view.dialog, function() return "ui", ui.view.dogear:getRefreshRegion() end)
    end)
end

-- ------------------------------------------------------------ in a book
function BC.attach(ui)
    if not (ui and ui.view and ui.view.dogear and ui.bookmark) or ui._aleph_bookmark_colors then return end
    ui._aleph_bookmark_colors = true
    local dogear, bm = ui.view.dogear, ui.bookmark

    -- The ribbon, in the colour of the page's bookmark.
    local paint = dogear.paintTo
    dogear.paintTo = function(self, bb, x, y)
        try(function() ensureRibbon(self, BC.hex(BC.colorOf(BC.currentItem(ui)))) end)
        return paint(self, bb, x, y)
    end

    -- A new bookmark of the page shown: the colour used last, and the list.
    local toggle = bm.toggleBookmark
    bm.toggleBookmark = function(self, pageno, ...)
        -- The page shown: no page given, or the page shown given.
        local here = pageno == nil
        if not here then pcall(function()
            local cur = self:getCurrentPageNumber()
            here = pageno == cur or (ui.rolling and ui.document:getPageXPointer(pageno) == cur)
        end) end
        local before = nil
        if here then pcall(function() before = self:isPageBookmarked() end) end
        local result = toggle(self, pageno, ...)
        if here and before == false then
            local item = BC.currentItem(ui)
            if item then
                item.aleph_color = item.aleph_color or BC.last()
                if BC.askOnAdd() then
                    require("ui/uimanager"):nextTick(function()
                        if ui.document then BC.showPicker(ui, item) end
                    end)
                end
            end
        end
        return result
    end
end

return BC
