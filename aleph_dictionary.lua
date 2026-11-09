-- Aleph modification, 2026-11-08: KOReader's dictionary pop-up in the
-- board's style.
--[[--
The pop-up keeps all of KOReader's behaviour (results, switching dictionaries,
Wikipedia, text selection, scrolling, hold to look up a word, the vocabulary
builder). Only its look changes, in place, after KOReader has built it:

  - the board's font for the word, the definition and the buttons
  - a rounded frame in the board's colors
  - a header: results menu, dictionary name, close
  - a pencil for editing the looked up word
  - the buttons: Previous / Next dictionary, Wikipedia, Highlight, Search and
    Close (and Wikipedia's link and Save) as one row of icons; any button
    with words (the vocabulary builder, plugin buttons) on a row of its own,
    its words centred, hairlines between the rows

If anything fails while restyling, the pop-up is left as KOReader built it.
]]

local Device = require("device")
local Geom = require("ui/geometry")
local Widget = require("ui/widget/widget")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local BoardMetrics = require("aleph_board_metrics")
local BoardUI = require("aleph_board_ui")

local INK = BoardMetrics.INK
local px = BoardMetrics.px
local floor = math.floor

local Dict = {}

-- Which icon stands for which of KOReader's buttons.
local ICONS = {
    prev_dict = "chevrons-left",
    next_dict = "chevrons-right",
    highlight = "highlighter",
    wikipedia = "globe",
    search = "search",
    close = "x",
    link = "arrow-up-right",
    save = "download",
}

-- The order of the icon row; unlisted buttons sit before Close.
local ORDER = {
    prev_dict = 1, next_dict = 2, wikipedia = 3, link = 4, save = 5,
    highlight = 6, search = 7, close = 99,
}

-- ------------------------------------------------------------- a tap cell
local Cell = require("aleph_cell")

-- ----------------------------------------------------------- the header
-- The dictionary's name, read when it is painted (switching dictionaries
-- changes it); it also stands in for KOReader's title bar where KOReader
-- looks at that bar's position.
-- A container, so taps on the close icon and the menu icon reach them (a plain
-- widget would swallow them, and KOReader would read the tap as one on the
-- title, which makes the dictionary "no longer preferred").
local Header = WidgetContainer:extend{ owner = nil, w = 0, h = 0, row = nil }

function Header:init()
    self[1] = self.row
end

function Header:getSize()
    return { w = self.w, h = self.h }
end

function Header:paintTo(bb, x, y)
    self.owner.dict_title.dimen = Geom:new{ x = x, y = y, w = self.w, h = self.h }
    self.row:paintTo(bb, x, y)
end

local TitleText = Widget:extend{ owner = nil, w = 0 }

function TitleText:getSize()
    return { w = self.w, h = BoardMetrics.lh1(18) }
end

function TitleText:paintTo(bb, x, y)
    local str = self.owner.displaydictname or ""
    if str ~= self._str then
        if self._text and self._text.free then self._text:free() end
        self._text = BoardUI.text(str, { s = 18, b = true, w = self.w, data = true })
        self._str = str
    end
    self._text:paintTo(bb, x, y + floor((self:getSize().h - self._text:getSize().h) / 2))
end

-- Runs fn with some of KOReader's settings reading as `overrides` for as long
-- as it runs: the user's saved values are never changed.
local function withSettings(overrides, fn, ...)
    local settings = G_reader_settings
    local original = settings.readSetting
    settings.readSetting = function(this, key, default)
        local value = overrides[key]
        if value ~= nil then return value end
        return original(this, key, default)
    end
    local ok, result = pcall(fn, ...)
    settings.readSetting = nil
    if rawget(settings, "readSetting") == nil and settings.readSetting ~= original then settings.readSetting = original end
    if not ok then error(result, 0) end
    return result
end

-- -------------------------------------------------------------- restyle
function Dict.restyle(self)
    local Size = require("ui/size")
    local TextWidget = require("ui/widget/textwidget")
    local frame = self.dict_frame
    local group = frame[1]
    local old_h = frame:getSize().h
    local inner_w = self.width - 2 * Size.border.window
    local pad = px(10)

    frame.radius = px(16)
    frame.color = INK.g6
    frame.bordersize = math.max(1, px(1.5))

    -- Header.
    local box = px(44)
    local menu = Cell:new{ w = box, h = box, icon_name = "menu", bare = true, source = {
        enabled = true,
        callback = function()
            local f = self.dict_title.left_icon_tap_callback
            if f then f() end
        end,
        hold_callback = function()
            local f = self.dict_title.left_icon_hold_callback
            if f then f() end
        end,
    } }
    local close = Cell:new{ w = box, h = box, icon_name = "x", bare = true, source = {
        enabled = true,
        callback = function() self.dict_title.close_callback() end,
        hold_callback = function()
            local f = self.dict_title.close_hold_callback
            if f then f() end
        end,
    } }
    local title = TitleText:new{ owner = self, w = inner_w - 2 * box - 2 * px(8) }
    local row = BoardUI.hstack({ w = inner_w, h = px(52) }, {
        BoardUI.space(px(8), 1), menu, title, BoardUI.flex(0), close, BoardUI.space(px(8), 1),
    })
    local header = Header:new{ owner = self, w = inner_w, h = px(52), row = row }
    local rule = BoardUI.rect(inner_w, math.max(1, px(1)), INK.gc)
    group[1] = BoardUI.vstack({ w = inner_w }, { header, rule })

    -- The looked up word, its count and the pencil, in the board's font.
    local word_row = group[3] and group[3][1]
    if word_row then
        local size = self.is_wiki and math.max(18, self.dict_font_size) or math.max(22, self.dict_font_size)
        local face = BoardMetrics.face(size, "sans")
        local old_word = self.lookup_word_text
        local word = TextWidget:new{
            text = self.displayword, face = face, bold = true,
            max_width = old_word and old_word.max_width or inner_w, padding = 0, lang = self.lang_in,
        }
        for i, child in ipairs(word_row) do
            if child == old_word then word_row[i] = word end
        end
        self.lookup_word_text = word
        if self.displaynb_text then
            local nb = TextWidget:new{ text = self.displaynb, face = face, padding = 0 }
            for _i, child in ipairs(word_row) do
                if type(child) == "table" and child[1] == self.displaynb_text then child[1] = nb end
            end
            self.displaynb_text = nb
        end
        -- The pencil: the board's own icon, same two actions.
        for i, child in ipairs(word_row) do
            if type(child) == "table" and child.icon == "edit" then
                local edit = Cell:new{ w = px(34), h = px(34), icon_name = "pen-line", bare = true, icon_size = 20, source = {
                    enabled = true,
                    callback = function() self:onLookupInputWord(self.word) end,
                    hold_callback = function() self:onLookupInputWord(self.lookupword) end,
                } }
                edit.overlap_align = "right"
                word_row[i] = edit
            end
        end
    end

    -- Buttons: KOReader's own buttons, laid out again. A button with words
    -- (the vocabulary builder, plugin buttons) gets a row of its own with the
    -- words centred; every button with an icon goes into one row of bare
    -- icons, hairlines between the rows.
    local table_ = self.button_table
    local layout = table_ and table_.buttons_layout
    if layout then
        local by_button = {}
        for id, button in pairs(table_.button_by_id or {}) do by_button[button] = id end
        local text_buttons, icon_buttons = {}, {}
        for _i, row_buttons in ipairs(layout) do
            for _j, button in ipairs(row_buttons) do
                local id = by_button[button]
                if ICONS[id] then
                    icon_buttons[#icon_buttons + 1] = { id = id, button = button }
                else
                    text_buttons[#text_buttons + 1] = button
                end
            end
        end
        -- Back and forward through the dictionaries first, Close last.
        local function rank(id)
            return ORDER[id] or 50
        end
        for index, entry in ipairs(icon_buttons) do entry.index = index end
        table.sort(icon_buttons, function(a, b)
            if rank(a.id) ~= rank(b.id) then return rank(a.id) < rank(b.id) end
            return a.index < b.index
        end)
        local row_w = inner_w - 2 * pad
        local line = math.max(1, px(1))
        local rows = {}
        local function rule()
            table.insert(rows, BoardUI.rect(row_w, line, INK.gc))
        end
        for _i, button in ipairs(text_buttons) do
            rule()
            table.insert(rows, Cell:new{ w = row_w, h = px(48), bare = true, center = true, label_size = 15, source = button })
        end
        if #icon_buttons > 0 then
            rule()
            -- One row; more than seven icons would be too tight, so they split
            -- into two even rows.
            local per_row = #icon_buttons > 7 and math.ceil(#icon_buttons / 2) or #icon_buttons
            for start = 1, #icon_buttons, per_row do
                local cells = {}
                local n = math.min(per_row, #icon_buttons - start + 1)
                local cw = floor(row_w / per_row)
                for k = start, start + n - 1 do
                    local entry = icon_buttons[k]
                    cells[#cells + 1] = Cell:new{ w = cw, h = px(52), bare = true, icon_size = 24, icon_name = ICONS[entry.id], source = entry.button }
                end
                table.insert(rows, BoardUI.hstack({ w = row_w }, { BoardUI.flex(0), BoardUI.hstack({}, cells), BoardUI.flex(0) }))
            end
        end
        if #rows > 0 then
            group[#group] = BoardUI.vstack({ w = inner_w, pad = { 0, pad, px(4), pad } }, rows)
        end
    end

    -- Docked to the bottom of the screen, whichever word was looked up.
    if not self.is_wiki then
        local Device = require("device")
        local sw, sh = Device.screen:getWidth(), Device.screen:getHeight()
        self.region = Geom:new{ x = 0, y = 0, w = sw, h = sh - px(8) }
        self.align = "bottom"
        if self[1] then
            self[1].align = "bottom"
            self[1].dimen = self.region
        end
    end

    -- Never taller than KOReader worked out, so a large window still fits the
    -- screen: anything the new parts add is taken from the space above the
    -- buttons. The tighter buttons make the pop-up shorter instead of leaving
    -- a gap there.
    group._size, group._offsets = nil, nil
    local new_h = frame:getSize().h
    local span = group[#group - 1]
    if span and span.width and new_h > old_h then
        span.width = math.max(px(4), span.width - (new_h - old_h))
        group._size, group._offsets = nil, nil
    end
end

local wanted = require("aleph_prefs").styleDialogs

-- Footnote pop-ups: the board's font family and body size instead of the
-- book's font and the popup size setting, for as long as one is built.
local function installFootnotes()
    local ok, Footnote = pcall(require, "ui/widget/footnotewidget")
    if not ok or type(Footnote) ~= "table" or Footnote._aleph_hooked then return end
    Footnote._aleph_hooked = true
    local original_init = Footnote.init
    function Footnote:init(...)
        local stored = G_reader_settings:readSetting("aleph")
        if type(stored) == "table" and stored.style_dialogs == false then return original_init(self, ...) end
        BoardMetrics.refresh()
        return withSettings({
            footnote_popup_absolute_font_size = BoardMetrics.fontSize(14),
            footnote_popup_use_book_font = false,
        }, original_init, self, ...)
    end
end

function Dict.install()
    installFootnotes()
    local class = require("ui/widget/dictquicklookup")
    if class._aleph_hooked then return end
    class._aleph_hooked = true
    local original_init = class.init
    function class:init()
        if not wanted() then return original_init(self) end
        local Font = require("ui/font")
        local original_getFace = Font.getFace
        local file = BoardMetrics.faceFile("sans")
        -- While the pop-up is built, KOReader's content and title fonts are the board's.
        Font.getFace = function(font, name, size, ...)
            if name == "cfont" or name == "tfont" or name == "smalltfont" or name == "x_smalltfont" then name = file end
            return original_getFace(font, name, size, ...)
        end
        BoardMetrics.refresh()
        -- The definition is set in the board's body size, not KOReader's
        -- (saved) dictionary font size, which is left as the reader set it.
        local ok, err = pcall(withSettings, { dict_font_size = BoardMetrics.fontSize(15) }, original_init, self)
        Font.getFace = original_getFace
        if not ok then error(err, 0) end
        local styled, why = pcall(Dict.restyle, self)
        if not styled then require("logger").warn("Aleph: dictionary restyle failed:", why) end
    end
end

return Dict
