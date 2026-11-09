-- Aleph modification, 2026-11-08: the table of contents and the
-- bookmarks list in the board's style.
--[[--
Both are KOReader Menu lists. Each keeps all of its behaviour (paging, taps,
holds, the left button's dialog, selecting several bookmarks) and is restyled
as it is built: the board's font and size for the rows, a header with the menu
button, the title and a close icon, and the page arrows as icons.

The bookmarks list also gets a quick filter at the top:

  All | Highlights | Bookmarks | Notes     the type, with how many of each
  four style samples, nine color dots      tap one to keep only that style or
                                          color, tap it again to show all

These use KOReader's own filters, so the subtitle and the Filter dialog agree.
]]

local Device = require("device")
local Geom = require("ui/geometry")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local BoardMetrics = require("aleph_board_metrics")
local BoardUI = require("aleph_board_ui")
local Cell = require("aleph_cell")

local Screen = Device.screen
local INK = BoardMetrics.INK
local px = BoardMetrics.px
local floor = math.floor

local MenuSkin = {}

-- Which restyled screen is being opened (set around KOReader's own call).
local scope

local FONTS = {
    cfont = true, smallinfofont = true, infont = true, x_smallinfofont = true, ffont = true,
    smallffont = true, pgfont = true, tfont = true, smalltfont = true, x_smalltfont = true,
}

-- Runs fn with KOReader's named fonts answered by the board's.
local function withFonts(fn, ...)
    local Font = require("ui/font")
    local original = Font.getFace
    local file = BoardMetrics.faceFile("sans")
    Font.getFace = function(font, name, size, ...)
        if FONTS[name] then name = file end
        return original(font, name, size, ...)
    end
    local ok, result = pcall(fn, ...)
    Font.getFace = original
    if not ok then error(result, 0) end
    return result
end

-- --------------------------------------------------------------- arrows
-- The page arrows, as the board's icons, answering what Menu calls on its own
-- buttons (showHide, enableDisable, show, hide).
local Chevron = Cell:extend{ hidden = false }

function Chevron:init()
    Cell.init(self)
    self.width = self.w
end

function Chevron:showHide(visible) self.hidden = not visible end
function Chevron:show() self.hidden = false end
function Chevron:hide() self.hidden = true end
function Chevron:enable() self.source.enabled = true end
function Chevron:disable() self.source.enabled = false end
function Chevron:enableDisable(enabled) self.source.enabled = enabled and true or false end

function Chevron:paintTo(bb, x, y)
    if self.hidden then
        self.dimen.x, self.dimen.y = x, y
        return
    end
    Cell.paintTo(self, bb, x, y)
end

function Chevron:onTapCell()
    if self.hidden then return false end
    return Cell.onTapCell(self)
end

function Chevron:onHoldCell()
    if self.hidden then return false end
    return Cell.onHoldCell(self)
end

local function chevron(name, callback, hold)
    local box = px(40)
    return Chevron:new{ w = box, h = box, icon_name = name, bare = true, icon_size = 22,
        source = { enabled = true, callback = callback, hold_callback = hold } }
end

-- -------------------------------------------------------------- the header
local ICONS = { ["appbar.menu"] = "menu", ["appbar.checkmark"] = "check" }

local Bar = WidgetContainer:extend{ menu = nil, bookmark = nil, title = "", subtitle = "", left_icon = "menu", w = 0, h = 0 }

function Bar:init()
    if self.w <= 0 then self.w = Screen:getWidth() end
    self:rebuild()
end

-- The quick filter of the bookmarks list.
function Bar:filterRows(w)
    local HL = require("aleph_highlight")
    local bm = self.bookmark
    local ui = bm.ui
    local menu = self.menu
    local gap, h = px(6), px(36)
    local pad = px(14)
    local counts = { highlight = 0, note = 0, bookmark = 0 }
    for _i, item in ipairs(ui.annotation.annotations) do
        local kind = bm.getBookmarkType(item)
        counts[kind] = (counts[kind] or 0) + 1
    end
    local total = counts.highlight + counts.note + counts.bookmark
    local active_type
    if bm.match_table and not bm.match_table.search_str then
        for kind in pairs(bm.match_table) do active_type = kind end
    end
    local filtered = bm.show_drawer_only or bm.show_color_only or bm.show_edited_only
    local function reopen(match)
        menu:onClose()
        bm.match_table = match
        -- KOReader's own list again, not Aleph's bookmarks page.
        local show = bm._rb_native_show or bm.onShowBookmark
        show(bm)
    end
    -- Type.
    local cw = floor((w - 2 * pad - 3 * gap) / 4)
    local types = {
        { nil, _("All"), total }, { "highlight", _("Highlights"), counts.highlight },
        { "bookmark", _("Bookmarks"), counts.bookmark }, { "note", _("Notes"), counts.note },
    }
    local type_cells = {}
    for _i, t in ipairs(types) do
        local kind = t[1]
        table.insert(type_cells, Cell:new{
            w = cw, h = h, label = t[2] .. " " .. t[3], label_size = 13,
            active = (kind == nil and not active_type and not filtered) or (kind ~= nil and kind == active_type),
            source = { enabled = true, callback = function() reopen(kind and { [kind] = true } or nil) end },
        })
    end
    -- Style and color.
    local function apply(field, value)
        if (field == "drawer" and bm.show_drawer_only == value) or (field == "color" and bm.show_color_only == value) then
            menu:onClose()
            local show = bm._rb_native_show or bm.onShowBookmark
            show(bm)
            return
        end
        local item_table = menu.item_table
        for i = #item_table, 1, -1 do
            if item_table[i][field] ~= value then table.remove(item_table, i) end
        end
        if field == "drawer" then bm.show_drawer_only = value else bm.show_color_only = value end
        bm:updateBookmarkList(item_table)
    end
    -- Styles on one row, colors on the row below, each centred.
    local styles = ui.highlight:getHighlightStyles()
    local colors = ui.highlight.highlight_colors
    local look_gap = px(10)
    local style_w = math.min(px(64), floor((w - 2 * pad - (#styles - 1) * look_gap) / math.max(1, #styles)))
    local swatch_w = math.min(px(40), floor((w - 2 * pad - (#colors - 1) * gap) / math.max(1, #colors)))
    local look_cells, color_cells = {}, {}
    local sample_color = HL.palette.hex(bm.show_color_only or "yellow")
    for _i, style in ipairs(styles) do
        local id = style[2]
        table.insert(look_cells, Cell:new{
            w = style_w, h = px(40), radius = px(10), active = bm.show_drawer_only == id,
            sample = function(sw, sh) return HL.styleSample(id, sw, sh, sample_color) end,
            source = { enabled = true, callback = function() apply("drawer", id) end },
        })
    end
    for _i, color in ipairs(colors) do
        local id = color[2]
        table.insert(color_cells, Cell:new{
            w = swatch_w, h = swatch_w, swatch = HL.colorOf(HL.palette.hex(id)), active = bm.show_color_only == id,
            source = { enabled = true, callback = function() apply("color", id) end },
        })
    end
    return {
        BoardUI.vstack({ w = w, pad = { px(4), pad, 0, pad } }, {
            BoardUI.hstack({ gap = gap }, type_cells),
            BoardUI.space(nil, px(10)),
            BoardUI.hstack({ w = w - 2 * pad }, { BoardUI.flex(0), BoardUI.hstack({ gap = look_gap, valign = "center" }, look_cells), BoardUI.flex(0) }),
            BoardUI.space(nil, px(8)),
            BoardUI.hstack({ w = w - 2 * pad }, { BoardUI.flex(0), BoardUI.hstack({ gap = gap, valign = "center" }, color_cells), BoardUI.flex(0) }),
        }),
    }
end

function Bar:stateKey()
    local bm = self.bookmark
    local filters = bm and table.concat({
        tostring(bm.show_drawer_only), tostring(bm.show_color_only), tostring(bm.show_edited_only),
        bm.match_table and "m" or "-", tostring(#(bm.ui.annotation.annotations)),
    }, ",") or ""
    return table.concat({ tostring(self.title), tostring(self.subtitle), tostring(self.left_icon), filters }, "|")
end

function Bar:rebuild()
    BoardMetrics.refresh()
    if self[1] and self[1].free then self[1]:free() end
    local w = self.w
    local box = px(44)
    local title_w = w - 2 * (box + px(10))
    local menu = self.menu
    local left = Cell:new{ w = box, h = box, icon_name = self.left_icon, bare = true, source = {
        enabled = true,
        callback = function()
            if not menu.onLeftButtonTap then return end
            -- KOReader's dialog behind this button opens as an Aleph sheet.
            local title = self.bookmark and _("Bookmarks") or _("Table of contents")
            local ok, err = pcall(function()
                require("aleph_dialog_sheet").capture(function() menu:onLeftButtonTap() end, { title = title })
            end)
            if not ok then
                require("logger").warn("Aleph: menu options sheet failed:", err)
                menu:onLeftButtonTap()
            end
        end,
        hold_callback = function() if menu.onLeftButtonHold then menu:onLeftButtonHold() end end,
    } }
    local close = Cell:new{ w = box, h = box, icon_name = "x", bare = true, source = {
        enabled = true, callback = function() menu:onClose() end,
    } }
    local items = {
        BoardUI.hstack({ w = w, h = px(52) }, {
            BoardUI.space(px(10), 1), left,
            BoardUI.text(tostring(self.title or ""), { s = 19, b = true, w = title_w, align = "center", data = true }),
            close, BoardUI.space(px(10), 1),
        }),
    }
    -- The subtitle line is always kept, empty or not: KOReader lays the list
    -- out under the header once, so a header that grew when a filter added
    -- a subtitle ran into the first item.
    local subtitle = tostring(self.subtitle or "")
    table.insert(items, BoardUI.text(subtitle ~= "" and subtitle or " ", { s = 12, col = INK.g4, w = w - 2 * px(14), align = "center", data = true }))
    table.insert(items, BoardUI.space(nil, px(4)))
    if self.bookmark then
        local ok, rows = pcall(self.filterRows, self, w)
        if ok then
            for _i, row in ipairs(rows) do table.insert(items, row) end
            table.insert(items, BoardUI.space(nil, px(14)))
        else
            require("logger").warn("Aleph: bookmark filters failed:", rows)
        end
    end
    table.insert(items, BoardUI.rect(w, math.max(1, px(1)), INK.gc))
    self[1] = BoardUI.vstack({ w = w }, items)
    self.h = self[1]:getSize().h
    self._key = self:stateKey()
end

function Bar:getHeight() return self.h end
function Bar:getSize() return { w = self.w, h = self.h } end

function Bar:paintTo(bb, x, y)
    if self:stateKey() ~= self._key then self:rebuild() end
    self.dimen = Geom:new{ x = x, y = y, w = self.w, h = self.h }
    self[1]:paintTo(bb, x, y)
end

function Bar:setTitle(title) self.title = title end
function Bar:setSubTitle(subtitle) self.subtitle = subtitle end
function Bar:setLeftIcon(icon) self.left_icon = ICONS[icon] or "menu" end
function Bar:generateVerticalLayout() return {} end
function Bar:free() if self[1] and self[1].free then self[1]:free() end end

-- ------------------------------------------------------------ page label
-- KOReader's "Page 4 of 4" drawn as the board's "4 / 4": the button keeps its
-- size, text and taps (tap it to type a page number); only its painting is
-- the board's, in the board's font and size.
function MenuSkin.pageLabel(menu)
    local button = menu.page_info_text
    if not button or button._rb_label then return end
    button._rb_label = true
    local cache = {}
    button.paintTo = function(b, bb, x, y)
        local size = b:getSize()
        b.dimen = Geom:new{ x = x, y = y, w = size.w, h = size.h }
        local nums = {}
        for n in tostring(b.text or ""):gmatch("%d+") do nums[#nums + 1] = n end
        if #nums < 2 then return end
        local str = nums[1] .. " / " .. nums[2]
        if cache.str ~= str or cache.w ~= size.w or cache.h ~= size.h then
            if cache.widget and cache.widget.free then cache.widget:free() end
            cache.widget = BoardUI.hstack({ w = size.w, h = size.h }, { BoardUI.flex(0), BoardUI.text(str, { s = 14, b = true }), BoardUI.flex(0) })
            cache.str, cache.w, cache.h = str, size.w, size.h
        end
        cache.widget:paintTo(bb, x, y)
    end
end

-- ---------------------------------------------------------------- install
local wanted = require("aleph_prefs").styleDialogs

function MenuSkin.install()
    local Menu = require("ui/widget/menu")
    if Menu._aleph_skin then return end
    Menu._aleph_skin = true
    local original_init, original_update = Menu.init, Menu.updateItems

    function Menu:init()
        if not scope or not self.title_bar_fm_style or not wanted() then return original_init(self) end
        BoardMetrics.refresh()
        self._rb_kind = scope.kind
        self.items_font_size = BoardMetrics.fontSize(15)
        -- Page numbers on their own, without dotted leaders.
        if scope.kind == "toc" then self.with_dots = false end
        self.custom_title_bar = Bar:new{
            menu = self, bookmark = scope.kind == "bookmarks" and scope.bookmark or nil,
            title = self.title, subtitle = self.subtitle, left_icon = "menu", w = Screen:getWidth(),
        }
        self.page_info_first_chev = chevron("chevrons-left", function() self:onFirstPage() end)
        self.page_info_left_chev = chevron("chevron-left", function() self:onPrevPage() end, function() self:onFirstPage() end)
        self.page_info_right_chev = chevron("chevron-right", function() self:onNextPage() end, function() self:onLastPage() end)
        self.page_info_last_chev = chevron("chevrons-right", function() self:onLastPage() end)
        local result = withFonts(original_init, self)
        pcall(MenuSkin.pageLabel, self)
        return result
    end

    function Menu:updateItems(...)
        if not self._rb_kind then return original_update(self, ...) end
        return withFonts(original_update, self, ...)
    end

    local function scoped(class, name, kind)
        local original = class[name]
        class[name] = function(self, ...)
            local previous = scope
            scope = { kind = kind, bookmark = self }
            local ok, result = pcall(original, self, ...)
            scope = previous
            if not ok then error(result, 0) end
            return result
        end
    end
    scoped(require("apps/reader/modules/readertoc"), "onShowToc", "toc")
    scoped(require("apps/reader/modules/readerbookmark"), "onShowBookmark", "bookmarks")
    -- The bookmarks list opens as Aleph's own page; KOReader's (styled
    -- above) stays behind its menu button.
    local ok_bm, err_bm = pcall(function() require("aleph_bookmarks").install() end)
    if not ok_bm then require("logger").warn("Aleph: bookmarks page not installed:", err_bm) end
    -- The table of contents opens as Aleph's own panel; KOReader's
    -- (styled above) stays behind its menu button.
    local ok, err = pcall(function() require("aleph_toc").install() end)
    if not ok then require("logger").warn("Aleph: table of contents panel not installed:", err) end
end

return MenuSkin
