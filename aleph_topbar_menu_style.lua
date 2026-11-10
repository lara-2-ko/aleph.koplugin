local BD = require("ui/bidi")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local Size = require("ui/size")
local Style = require("aleph_topbar_style")
local TextWidget = require("ui/widget/textwidget")
local Widget = require("ui/widget/widget")
local _ = require("gettext")

local floor = math.floor
local MenuStyle = {}
local ink = Style.ink
local border = ink.g8

-- ------------------------------------------------------------- arrows
-- The footer's arrows: page back, page forward, and up one level. They take
-- the place of KOReader's buttons and answer the calls the menu makes on
-- them (showHide, enableDisable). An arrow that is hidden draws nothing and
-- takes no taps; with `collapse` it also takes no room.
local Arrow = InputContainer:extend{
    file = nil, box = 0, size = 0, enabled = true, hidden = false, collapse = false,
    callback = nil, hold_callback = nil,
}

function Arrow:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.box, h = self.box }
    self.width = self.box
    self.ges_events = {
        TapArrow = { GestureRange:new{ ges = "tap", range = self.dimen } },
        HoldArrow = { GestureRange:new{ ges = "hold", range = self.dimen } },
    }
    self.image = IconWidget:new{ file = self.file, width = self.size, height = self.size, alpha = true }
end

function Arrow:getSize()
    return self.dimen
end

function Arrow:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    if self.hidden then return end
    self.image.dim = not self.enabled
    self.image:paintTo(bb, x + floor((self.box - self.size) / 2), y + floor((self.box - self.size) / 2))
end

function Arrow:hide()
    self.hidden = true
    if self.collapse then self.dimen.w = 0 end
end

function Arrow:show()
    self.hidden = false
    self.dimen.w = self.box
end

function Arrow:showHide(visible)
    if visible then self:show() else self:hide() end
end

function Arrow:enable() self.enabled = true end
function Arrow:disable() self.enabled = false end
function Arrow:enableDisable(enabled) self.enabled = enabled and true or false end

function Arrow:onTapArrow()
    if not self.hidden and self.enabled and self.callback then self.callback() end
    return true
end

function Arrow:onHoldArrow()
    if not self.hidden and self.enabled and self.hold_callback then self.hold_callback() end
    return true
end

function Arrow:free()
    if self.image then self.image:free() end
end

-- ------------------------------------------------------- check and radio
-- A row's check mark in Aleph's style: a black circle with a white
-- check when on, a thin ring when off; a radio is a ring with a dot.
local Mark = Widget:extend{
    checkable = false, checked = false, enabled = true, radio = false, w = 0, h = 0, check_file = nil,
}

function Mark:getSize()
    return { w = self.w, h = self.h }
end

function Mark:paintTo(bb, x, y)
    if not self.checkable then return end
    local radius = floor(Style.px(20) / 2)
    -- At the start of its slot; the rest of the slot is the gap to the text.
    local cx, cy = x + radius + Style.px(1), y + floor(self.h / 2)
    local color = self.enabled and ink.black or ink.g8
    local ring = math.max(1, Style.px(1.5))
    if self.radio then
        bb:paintCircle(cx, cy, radius, self.enabled and ink.g6 or ink.gd, ring)
        if self.checked then bb:paintCircle(cx, cy, floor(radius / 2), color) end
    elseif self.checked then
        bb:paintCircle(cx, cy, radius, color)
        local size = floor(radius * 1.25)
        if not self.image then
            self.image = IconWidget:new{ file = self.check_file, width = size, height = size, alpha = true }
        end
        self.image:paintTo(bb, cx - floor(size / 2), cy - floor(size / 2))
    else
        bb:paintCircle(cx, cy, radius, self.enabled and ink.g6 or ink.gd, ring)
    end
end

function Mark:free()
    if self.image then self.image:free(); self.image = nil end
end

-- ------------------------------------------------------------ menu setup
function MenuStyle.prepare(menu)
    local hairline = math.max(1, Style.px(0.75))
    menu.item_height = Style.px(40)
    menu.bordersize = hairline
    menu.split_height = hairline
    menu.split_color = ink.gb
end

function MenuStyle.install(menu, plugin)
    if menu._qtb_styled then return end
    menu._qtb_styled = true

    menu.menu_frame.color = border
    menu.menu_frame.radius = Style.px(10)
    menu.split_span = menu.split_line
    menu.bar.bar_sep.background = border
    menu.bar.bar_sep.dimen.h = menu.bordersize
    menu.bar[1][1]:resetLayout()
    for _, separator in ipairs(menu.bar.icon_seps) do
        -- Keep the native tab geometry and selection logic.
        function separator:paintTo(bb, x, y)
            if self.style == "solid" then
                local inset = math.floor((self.dimen.w - menu.bordersize) / 2)
                bb:paintRect(x + inset, y, menu.bordersize, self.dimen.h, border)
            end
        end
    end

    -- The footer: page back, the page numbers with an up arrow after them,
    -- page forward. KOReader's own up button and clock are replaced.
    local left, center, right = menu.footer[1], menu.footer[2], menu.footer[3]
    local box, size = Style.px(40), Style.px(22)
    local prev, next_page = "chevron-left", "chevron-right"
    if BD.mirroredUILayout() then prev, next_page = next_page, prev end
    local function arrow(name, callback, hold, collapse)
        return Arrow:new{
            file = Style.icon(plugin.path, name), box = box, size = size, collapse = collapse,
            callback = callback, hold_callback = hold,
        }
    end

    left[1]:free()
    menu.page_info:free()
    menu.page_info = nil
    menu.device_info:free()
    menu.page_info_left_chev = arrow(prev, function() menu:onPrevPage() end, function() menu:onFirstPage() end)
    menu.page_info_right_chev = arrow(next_page, function() menu:onNextPage() end, function() menu:onLastPage() end)
    menu.page_info_text = TextWidget:new{ text = "", face = Style.face(13), bold = true }
    -- Up one level: shown only inside a submenu, after the page numbers if
    -- there are any, alone in the middle if there are none.
    menu.qtb_up = arrow("chevron-up", function() menu:backToUpperMenu() end, nil, true)
    menu.qtb_up:hide()
    left[1] = menu.page_info_left_chev
    center[1] = HorizontalGroup:new{ align = "center", menu.page_info_text, menu.qtb_up }
    right[1] = menu.page_info_right_chev
end

function MenuStyle.setPageLabel(menu)
    menu.page_info_text:setText(menu.page_num and menu.page_num > 1
        and string.format(_("%d / %d"), menu.page, menu.page_num) or "")
    local depth = menu.item_table_stack and #menu.item_table_stack or 0
    if menu.qtb_up then menu.qtb_up:showHide(depth > 0) end
    -- The footer's centre changes width with the arrow.
    if menu.footer then menu.footer[2][1]._size = nil; menu.footer[2][1]._offsets = nil end
end

-- ------------------------------------------------------------------ rows
-- Rows keep KOReader's text, taps and layout; the check mark and the
-- submenu arrow are drawn in Aleph's style.
local function styleRow(menu, plugin, row)
    local group = row.item_frame and row.item_frame[1]
    local holder, text_widget = group and group[1], group and group[2]
    if not holder or not text_widget or not holder[1] then return end
    local item = row.item
    local enabled = item.enabled
    if item.enabled_func then enabled = item.enabled_func() end
    local checked = item.checked
    if item.checked_func then checked = item.checked_func() end
    local old = holder[1]
    local slot = old:getSize()
    -- KOReader sizes this slot to its check glyph, which is narrower than
    -- Aleph's round mark at Aleph's font sizes: the mark ran into the text.
    -- The slot takes the mark plus a gap, and the text gives up the room.
    local wanted = Style.px(20) + Style.px(2) + Style.px(12)
    if slot.w < wanted then
        local extra = wanted - slot.w
        slot = { w = wanted, h = slot.h }
        if holder.dimen then holder.dimen.w = wanted end
        if text_widget.max_width then
            local narrower = math.max(Style.px(40), text_widget.max_width - extra)
            if text_widget.setMaxWidth then text_widget:setMaxWidth(narrower) else text_widget.max_width = narrower end
        end
    end
    holder[1] = Mark:new{
        checkable = item.checked_func ~= nil, checked = checked and true or false,
        enabled = enabled ~= false, radio = item.radio and true or false,
        w = slot.w, h = slot.h, check_file = Style.icon(plugin.path, "check-white"),
    }
    -- The submenu arrow: KOReader appends " ▸" to the text; an icon at the
    -- row's right edge takes its place.
    local text = text_widget.text
    -- (Matched as whole characters: a Lua set like [▸◂] works byte by byte
    -- and would cut a UTF-8 arrow in half.)
    local plain = text
    if type(text) == "string" then
        for _i, arrow in ipairs({ "▸", "◂" }) do
            local stripped = text:gsub("%s*" .. arrow .. "%s*$", "")
            if stripped ~= text then plain = stripped; break end
        end
    end
    if plain ~= text then
        local icon_size = Style.px(16)
        local row_width = row.dimen.w - 2 * Size.padding.default
        local max_w = row_width - slot.w - icon_size - Style.px(8)
        if text_widget.setMaxWidth then text_widget:setMaxWidth(max_w) else text_widget.max_width = max_w end
        text_widget:setText(plain)
        local gap = row_width - slot.w - text_widget:getSize().w - icon_size
        group[3] = HorizontalSpan:new{ width = math.max(0, gap) }
        group[4] = IconWidget:new{ file = Style.icon(plugin.path, "sub-arrow"), width = icon_size, height = icon_size, alpha = true }
    end
    group._size, group._offsets = nil, nil
end

function MenuStyle.styleRows(menu, plugin)
    for _, row in ipairs(menu.item_group) do
        if type(row) == "table" and row.item and row.item_frame and not row._qtb_row then
            row._qtb_row = true
            local ok, err = pcall(styleRow, menu, plugin, row)
            if not ok then require("logger").warn("QuickTopBar: could not style a menu row:", err) end
        end
    end
end

return MenuStyle
