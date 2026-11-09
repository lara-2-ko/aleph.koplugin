-- Aleph modification, 2026-11-08: the highlight's Details dialog in the
-- board's style.
--[[--
KOReader shows a highlight's details (chapter, date, page, style, color, the
text and the note) in a text viewer with a row of arrows and rows of buttons.
That viewer is kept, with its scrolling and its text selection, and restyled in
place: the board's font and rounded frame, a header with the "2 / 2" counter
and a close icon, and the buttons as rounded cells with icons (the four arrows
are icons only). Only the viewer made for a highlight's details is touched.
]]


local BoardMetrics = require("aleph_board_metrics")
local BoardUI = require("aleph_board_ui")
local Cell = require("aleph_cell")

local INK = BoardMetrics.INK
local px = BoardMetrics.px
local floor = math.floor

local Details = {}

local depth = 0

local function iconFor(text, arrows)
    local _ = require("gettext")
    if text == arrows.first then return "chevrons-left", true end
    if text == arrows.prev then return "chevron-left", true end
    if text == arrows.next then return "chevron-right", true end
    if text == arrows.last then return "chevrons-right", true end
    local by_text = {
        [_("Reset text")] = "rotate-ccw", [_("Edit text")] = "pen-line", [_("Remove bookmark")] = "trash",
        [_("Add note")] = "quote", [_("Edit note")] = "quote", [_("Go to bookmark")] = "bookmark", [_("Close")] = "x",
    }
    return by_text[text], false
end

function Details.restyle(self)
    local VerticalSpan = require("ui/widget/verticalspan")
    local frame = self.frame
    local group = frame[1]
    local old_h = frame:getSize().h
    local w = self.width
    local pad = px(10)

    frame.radius = px(16)
    frame.bordersize = math.max(1, px(1.5))
    frame.color = INK.g6

    -- Header: the counter and a close icon.
    local close = Cell:new{ w = px(44), h = px(44), icon_name = "x", bare = true, source = {
        enabled = true, callback = function() self:onClose() end,
    } }
    local header = BoardUI.hstack({ w = w, h = px(52) }, {
        BoardUI.space(px(16), 1),
        BoardUI.text(self.title or "", { s = 19, b = true, w = w - px(44) - px(16) - px(8) - px(8), data = true }),
        BoardUI.flex(0), close, BoardUI.space(px(8), 1),
    })
    group[1] = BoardUI.vstack({ w = w }, { header, BoardUI.rect(w, math.max(1, px(1)), INK.gc) })

    -- Buttons: KOReader's own rows as cells.
    local layout = self.button_table and self.button_table.buttons_layout
    if layout then
        local BD = require("ui/bidi")
        local prev, nxt, first, last = BD.getArrowLabels()
        local arrows = { prev = prev, next = nxt, first = first, last = last }
        local gap = px(8)
        local rows = {}
        for _i, row_buttons in ipairs(layout) do
            local n = #row_buttons
            if n > 0 then
                local cw = floor((w - 2 * pad - (n - 1) * gap) / n)
                local cells = {}
                for _j, button in ipairs(row_buttons) do
                    local name, only_icon = iconFor(button.text, arrows)
                    cells[#cells + 1] = Cell:new{ w = cw, h = px(46), icon_name = name, show_label = name ~= nil and not only_icon, source = button, label_size = 14 }
                end
                if #rows > 0 then table.insert(rows, BoardUI.space(nil, gap)) end
                table.insert(rows, BoardUI.hstack({ gap = gap }, cells))
            end
        end
        if #rows > 0 then
            group[#group] = BoardUI.vstack({ w = w, pad = { px(8), pad, pad, pad } }, rows)
        end
    end

    -- Same overall height as KOReader made it: what is left over goes above the buttons.
    group._size, group._offsets = nil, nil
    local delta = old_h - frame:getSize().h
    if delta > 0 then
        table.insert(group, #group, VerticalSpan:new{ width = delta })
        group._size, group._offsets = nil, nil
    end
end

local wanted = require("aleph_prefs").styleDialogs

function Details.install()
    local TextViewer = require("ui/widget/textviewer")
    if TextViewer._aleph_hooked then return end
    TextViewer._aleph_hooked = true
    local original_init = TextViewer.init
    function TextViewer:init(...)
        if depth == 0 or self.text_type ~= "bookmark" or not wanted() then return original_init(self, ...) end
        local Font = require("ui/font")
        local original_getFace = Font.getFace
        local file = BoardMetrics.faceFile("sans")
        Font.getFace = function(font, name, size, ...)
            if name == "x_smallinfofont" or name == "smallinfont" then name = file end
            return original_getFace(font, name, size, ...)
        end
        local ok, err = pcall(original_init, self, ...)
        Font.getFace = original_getFace
        if not ok then error(err, 0) end
        BoardMetrics.refresh()
        local styled, why = pcall(Details.restyle, self)
        if not styled then require("logger").warn("Aleph: details restyle failed:", why) end
    end

    local Bookmark = require("apps/reader/modules/readerbookmark")
    local original_show = Bookmark.showBookmarkDetails
    function Bookmark:showBookmarkDetails(...)
        depth = depth + 1
        local ok, result = pcall(original_show, self, ...)
        depth = depth - 1
        if not ok then error(result, 0) end
        return result
    end
end

return Details
