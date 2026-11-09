-- Modified for Aleph, 2026-11-09. Unofficial local-only fork. See NOTICE.
--[[--
The Highlight of the day drawer, after BookOrbit's (bookorbit_highlight_sheet.lua).
The Home tile stays short; this sheet shows the whole passage, its chapter and
note, and keeps the book page one tap away. Long passages turn page by page
inside the drawer (pager, swipes, page keys).
]]

local TextBoxWidget = require("ui/widget/textboxwidget")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local BoardMetrics = require("aleph_board_metrics")
local BoardUI = require("aleph_board_ui")
local SheetUI = require("aleph_sheet_ui")
local TextPages = require("aleph_text_pages")

local INK = BoardMetrics.INK
local px, lh = BoardMetrics.px, BoardMetrics.lh
local text, vstack, hstack, space, icon = BoardUI.text, BoardUI.vstack, BoardUI.hstack, BoardUI.space, BoardUI.icon

local HighlightSheet = {}

local BODY_SIZE = 16

local function hOf(widget) return widget:getSize().h end

function HighlightSheet.pageWindow(total_lines, available_height, line_height, index)
    total_lines = math.max(1, tonumber(total_lines) or 1)
    line_height = math.max(1, tonumber(line_height) or 1)
    local per_page = math.max(1, math.floor(math.max(1, available_height) / line_height))
    local count = math.max(1, math.ceil(total_lines / per_page))
    index = math.max(1, math.min(count, tonumber(index) or 1))
    return {
        count = count,
        index = index,
        per_page = per_page,
        first_line = (index - 1) * per_page + 1,
        height = math.min(total_lines, per_page) * line_height,
    }
end

-- The chapter, and the day it was made when KOReader saved one.
local function metaLine(view, w)
    local parts = {}
    if view.chapter then table.insert(parts, { t = view.chapter, b = true, col = INK.g3 }) end
    if view.when then table.insert(parts, { t = (#parts > 0 and " · " or "") .. view.when, col = INK.g4 }) end
    if #parts == 0 then return nil end
    return BoardUI.runs(parts, { s = 13, w = w, data = true })
end

-- The note, in a gray box, up to four lines.
local function noteBox(note, w)
    if not note then return nil end
    local nw = w - 2 * px(12) - px(16) - px(8)
    local lines = math.min(4, TextPages.linesNeeded(note, { s = 14 }, nw))
    local inner = hstack({ w = w - 2 * px(12), gap = px(8), valign = "top" }, {
        icon("pen-line", px(16), { sw = 2.25 }),
        text(note, { s = 14, w = nw, lines = lines, data = true, bg = INK.ge }),
    })
    return BoardUI.box({ w = w, h = hOf(inner) + 2 * px(10), radius = px(8), bg = INK.ge },
        vstack({ w = w, pad = { px(10), px(12), px(10), px(12) } }, { inner }))
end

local function buildBody(page, w, max_body_h)
    local highlight = page.highlight
    local view = TextPages.highlightView(highlight)
    local head = SheetUI.titleRow(w, _("Highlight of the day"), highlight.bookTitle)
    local meta = metaLine(view, w)
    local note = noteBox(view.note, w)
    local details = highlight.bookId and SheetUI.pillRow(w, {
        { label = _("Book details"), icon = "book-open-text", kind = "outline", action = { kind = "details" } },
    }) or nil
    local gap = px(14)
    local line_height = lh(BODY_SIZE)
    local bar = math.max(2, px(3))
    local quote_gap = px(14)
    local quote_w = math.max(1, w - bar - quote_gap)
    local total_lines = TextPages.linesNeeded(view.text, { s = BODY_SIZE, serif = true, i = true }, quote_w)

    local function fixedHeight(with_pager)
        local height, n = hOf(head), 1
        for _i, item in ipairs({ meta or false, note or false, details or false }) do
            if item then height, n = height + hOf(item), n + 1 end
        end
        if with_pager then height, n = height + px(40), n + 1 end
        return height + n * gap
    end

    local window = HighlightSheet.pageWindow(total_lines, max_body_h - fixedHeight(false), line_height, page.index)
    if window.count > 1 then
        window = HighlightSheet.pageWindow(total_lines, max_body_h - fixedHeight(true), line_height, page.index)
    end
    page.index = window.index
    page.count = window.count

    local quote = TextBoxWidget:new{
        text = view.text,
        face = BoardMetrics.face(BODY_SIZE, "serif_italic"),
        width = quote_w,
        height = window.height,
        virtual_line_num = window.first_line,
        fgcolor = INK.black,
        bgcolor = INK.white,
    }
    local quote_block = hstack({ w = w, valign = "top" }, {
        BoardUI.rect(bar, window.height, INK.black, math.floor(bar / 2)),
        space(quote_gap, 1),
        quote,
    })
    local items = { head, quote_block }
    if meta then table.insert(items, meta) end
    if note then table.insert(items, note) end
    if window.count > 1 then table.insert(items, TextPages.pager(w, window.index, window.count)) end
    if details then table.insert(items, details) end
    return items
end

-- on_details(book_id): opens the book's page; the sheet is closed first.
function HighlightSheet.open(highlight, on_details)
    if type(highlight) ~= "table" then return nil end
    return SheetUI.open{
        name = "aleph_highlight_of_the_day",
        build = function(page, sw, sh)
            return SheetUI.sheet(page, sw, sh, function(w, max_body_h)
                return buildBody(page, w, max_body_h)
            end, { pop_w = 520 })
        end,
        on_action = function(page, action)
            if action.kind == "page" then
                TextPages.turn(page, action.delta)
            elseif action.kind == "details" and page.highlight.bookId then
                local book_id = page.highlight.bookId
                page:close()
                if on_details then UIManager:tickAfterNext(function() on_details(book_id) end) end
            end
            return true
        end,
        on_swipe = function(page, ges)
            if ges.direction == "west" then TextPages.turn(page, 1) return true end
            if ges.direction == "east" then TextPages.turn(page, -1) return true end
            return false
        end,
        on_page_key = function(page, delta) TextPages.turn(page, delta) end,
        highlight = highlight,
        index = 1,
    }
end

return HighlightSheet
