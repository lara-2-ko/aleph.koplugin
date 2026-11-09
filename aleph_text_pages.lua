-- Modified for Aleph, 2026-11-09. Unofficial local-only fork. See NOTICE.
--[[--
A book's long text on pages of its own: About this book and Highlights, plus
the Genres & tags sheet.

After BookOrbit's text pages (bookorbit_text_pages.lua). Text turns page by
page like a book, never scrolls: the pager at the foot, swipes and the page
keys move through it. The header names the book the page belongs to, so its
back button says where it goes.

Everything comes from the local index: the description KOReader read from the
book, its highlights and notes, and its genres (the book's tags, which
Calibre writes from its Tags column). Genre chips are buttons here, because
Aleph can list the books of a genre.
]]

local Device = require("device")
local TextBoxWidget = require("ui/widget/textboxwidget")
local UIManager = require("ui/uimanager")
local datetime = require("datetime")
local T = require("ffi/util").template
local _ = require("gettext")

local BoardMetrics = require("aleph_board_metrics")
local BoardUI = require("aleph_board_ui")
local MenuPage = require("aleph_menu_page")
local MenuUI = require("aleph_menu_ui")
local SheetUI = require("aleph_sheet_ui")

local INK = BoardMetrics.INK
local px, lh = BoardMetrics.px, BoardMetrics.lh
local text, vstack, hstack, space, flex, icon = BoardUI.text, BoardUI.vstack, BoardUI.hstack, BoardUI.space, BoardUI.flex, BoardUI.icon

local TextPages = {}

local function wOf(widget) return widget:getSize().w end
local function hOf(widget) return widget:getSize().h end

local BODY_SIZE = 16

-- How many lines str takes at width w.
local function linesNeeded(str, o, w)
    local kind = o.serif and (o.i and "serif_italic" or "serif") or (o.i and "sans_italic" or "sans")
    local tb = TextBoxWidget:new{ text = str, face = BoardMetrics.face(o.s, kind), width = w }
    local n = math.max(1, math.floor(tb:getSize().h / lh(o.s) + 0.5))
    tb:free()
    return n
end
TextPages.linesNeeded = linesNeeded

-- Splits n items of the given heights into pages no taller than page_h, gap
-- apart. An item taller than a page gets a page of its own.
function TextPages.pack(heights, page_h, gap)
    local pages, first, used = {}, 1, 0
    for index, h in ipairs(heights) do
        local need = (index > first) and (gap + h) or h
        if index > first and used + need > page_h then
            table.insert(pages, { first = first, last = index - 1 })
            first, used = index, h
        else
            used = used + need
        end
    end
    if #heights >= first then table.insert(pages, { first = first, last = #heights }) end
    if #pages == 0 then pages = { { first = 1, last = 0 } } end
    return pages
end

-- The description as plain text: KOReader keeps EPUB descriptions as HTML.
function TextPages.cleanDescription(str)
    if type(str) ~= "string" or not str:match("%S") then return nil end
    local ok, plain = pcall(function() return require("util").htmlToPlainTextIfHtml(str) end)
    str = (ok and plain or str):gsub("\r", ""):gsub("\n%s*\n%s*\n+", "\n\n"):gsub("^%s+", ""):gsub("%s+$", "")
    return str ~= "" and str or nil
end

-- ----------------------------------------------------------------- frame
-- The header: back with the book's title, the device status.
local function header(page, w)
    local box = px(44)
    local label = page.back_label or _("Back")
    local back_inner = hstack({ h = box, gap = px(2) }, { icon("chevron-left", px(24), { sw = 2.25 }), text(label, { s = 15, b = true, data = true }), space(px(8), 1) })
    local max_back = math.floor(w * 0.6)
    if wOf(back_inner) > max_back then
        back_inner = hstack({ h = box, gap = px(2) }, { icon("chevron-left", px(24), { sw = 2.25 }),
            text(label, { s = 15, b = true, w = max_back - px(24) - px(2) - px(8), data = true }), space(px(8), 1) })
    end
    local back = BoardUI.hit(back_inner, { kind = "back" })
    local status = BoardUI.statusCluster({ clock = datetime.secondsToHour(os.time(), G_reader_settings:isTrue("twelve_hour_clock")) })
    -- The chevron sits on the margin; its tap area reaches into it.
    local row = hstack({ w = w + px(8), h = px(48) }, { back, flex(0), status })
    return BoardUI.overlay(w, px(48), { { widget = row, x = -px(8), y = 0 } })
end

-- "‹ 2 of 5 ›", the arrows greyed at the ends.
function TextPages.pager(w, index, count)
    local fh = px(40)
    local function chev(name, on, delta)
        local c = hstack({ w = px(44), h = fh }, { flex(0), icon(name, px(20), { sw = 2.5, col = on and "black" or "gb" }), flex(0) })
        return on and BoardUI.hit(c, { kind = "page", delta = delta }) or c
    end
    local mid = text(T(_("%1 of %2"), index, count), { s = 13, b = true })
    return hstack({ w = w, h = fh, gap = px(4) }, { flex(0), chev("chevron-left", index > 1, -1), space(px(6), 1), mid, space(px(6), 1), chev("chevron-right", index < count, 1), flex(0) })
end

-- The page around a body: build_body(page, w, body_h) returns the body for
-- page.index and sets page.count.
local function buildPage(page, sw, sh)
    local mx = MenuUI.mx()
    local w = sw - 2 * mx
    local top, bottom = px(6), px(8)
    local head = header(page, w)
    local title = vstack({ w = w }, {
        text(page.title, { s = 22, b = true, w = w }),
        page.sub and text(page.sub, { s = 13, col = INK.g4, w = w, data = true }) or false,
    })
    local fixed = top + hOf(head) + px(4) + hOf(title) + px(14) + px(8) + px(40) + bottom
    local body_h = sh - fixed
    local body = page.build_body(page, w, body_h)
    local items = { head, space(nil, px(4)), title, space(nil, px(14)), vstack({ w = w, h = body_h }, { body, flex(0) }), space(nil, px(8)) }
    if (page.count or 1) > 1 then
        table.insert(items, TextPages.pager(w, page.index, page.count))
    else
        table.insert(items, space(nil, px(40)))
    end
    return vstack({ w = sw, h = sh, pad = { top, mx, bottom, mx } }, items)
end

function TextPages.turn(page, delta)
    local next_index = math.max(1, math.min(page.count or 1, page.index + delta))
    if next_index == page.index then return end
    page.index = next_index
    page:refresh(Device:hasEinkScreen() and "partial" or "ui")
end
local turn = TextPages.turn

local function openPage(o)
    local page = MenuPage:new{
        name = o.name,
        build = buildPage,
        on_action = function(page, action)
            if action.kind == "page" then turn(page, action.delta) end
            return true
        end,
        on_swipe = function(page, ges)
            if ges.direction == "west" then turn(page, 1) return true end
            if ges.direction == "east" then turn(page, -1) return true end
            return false
        end,
        on_page_key = function(page, delta) turn(page, delta) end,
        title = o.title,
        sub = o.sub,
        back_label = o.back_label,
        build_body = o.build_body,
        index = 1,
    }
    UIManager:show(page, "ui")
    return page
end

-- The book's title as the back button says it: short, without a subtitle.
function TextPages.backLabel(title)
    title = tostring(title or "")
    title = title:gsub("%s*[:(].*$", "")
    if title == "" then return _("Back") end
    return title
end

-- -------------------------------------------------------------- about
-- book: a library entry (title, props.description).
function TextPages.about(book)
    local description = TextPages.cleanDescription(book.props and book.props.description)
        or _("No description in this book's metadata.")
    local state = {}
    return openPage{
        name = "aleph_about_book",
        title = _("About this book"),
        back_label = TextPages.backLabel(book.title),
        build_body = function(page, w, body_h)
            local line = lh(BODY_SIZE)
            local per_page = math.max(1, math.floor(body_h / line))
            if not state.total or state.w ~= w then
                state.w = w
                state.total = linesNeeded(description, { s = BODY_SIZE, serif = true }, w)
            end
            page.count = math.max(1, math.ceil(state.total / per_page))
            if page.index > page.count then page.index = page.count end
            return TextBoxWidget:new{
                text = description,
                face = BoardMetrics.face(BODY_SIZE, "serif"),
                width = w,
                height = per_page * line,
                virtual_line_num = (page.index - 1) * per_page + 1,
                fgcolor = INK.black,
                bgcolor = INK.white,
            }
        end,
    }
end

-- ---------------------------------------------------------- highlights
local function trimmed(value)
    if type(value) ~= "string" then return nil end
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    return value ~= "" and value or nil
end

-- What a highlight shows: its text, chapter, day and note.
function TextPages.highlightView(hl)
    if type(hl) ~= "table" then return {} end
    local when
    local stamp = trimmed(hl.datetime)
    if stamp then
        local y, m, d = stamp:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)")
        if y then
            when = os.date("%b %d, %Y", os.time{ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 }):gsub(" 0", " ")
        end
    end
    return {
        text = trimmed(hl.text) or "",
        chapter = trimmed(hl.chapter) or trimmed(hl.chapterTitle),
        when = when,
        note = trimmed(hl.note),
    }
end

-- One highlight: the quote in italic serif, a rule down its left edge, where
-- and when, and the note in a gray box.
function TextPages.quote(hl, w)
    local bar = math.max(2, px(3))
    local pad = px(14)
    local tw = w - bar - pad
    local view = TextPages.highlightView(hl)
    local quote_lines = math.min(14, linesNeeded(view.text, { s = BODY_SIZE, serif = true, i = true }, tw))
    local items = {
        text(view.text, { s = BODY_SIZE, i = true, serif = true, lines = quote_lines, w = tw, data = true }),
    }
    local meta = {}
    if view.chapter then table.insert(meta, { t = view.chapter, b = true, col = INK.g2 }) end
    if view.when then table.insert(meta, { t = (#meta > 0 and " · " or "") .. view.when, col = INK.g4 }) end
    if #meta > 0 then
        table.insert(items, space(nil, px(6)))
        table.insert(items, BoardUI.runs(meta, { s = 12, w = tw, data = true }))
    end
    if view.note then
        local nw = tw - 2 * px(12) - px(16) - px(8)
        local note_lines = math.min(8, linesNeeded(view.note, { s = 14 }, nw))
        local note = text(view.note, { s = 14, w = nw, lines = note_lines, data = true, bg = INK.ge })
        local inner = hstack({ w = tw - 2 * px(12), gap = px(8), valign = "top" }, { icon("pen-line", px(16), { sw = 2.25 }), note })
        table.insert(items, space(nil, px(8)))
        table.insert(items, BoardUI.box({ w = tw, h = hOf(inner) + 2 * px(10), radius = px(8), bg = INK.ge }, vstack({ w = tw, pad = { px(10), px(12), px(10), px(12) } }, { inner })))
    end
    local body = vstack({ w = tw }, items)
    return hstack({ w = w, valign = "top" }, { BoardUI.rect(bar, hOf(body), INK.black, math.floor(bar / 2)), space(pad, 1), body })
end

-- book: a library entry (title, highlights).
function TextPages.highlights(book)
    local items = book.highlights or {}
    local gap = px(18)
    local state = {}
    local count = #items
    return openPage{
        name = "aleph_book_highlights",
        title = _("Highlights"),
        sub = count == 0 and _("None in this book yet") or count == 1 and _("1 in this book") or T(_("%1 in this book"), count),
        back_label = TextPages.backLabel(book.title),
        build_body = function(page, w, body_h)
            if count == 0 then
                page.count = 1
                return SheetUI.note(w, "highlighter", _("Highlights you make in this book show here, with their notes."), { col = INK.g4 })
            end
            if not state.pages or state.w ~= w or state.h ~= body_h then
                local heights = {}
                for _i, item in ipairs(items) do
                    local q = TextPages.quote(item, w)
                    table.insert(heights, math.min(hOf(q), body_h))
                    q:free()
                end
                state.pages, state.w, state.h = TextPages.pack(heights, body_h, gap), w, body_h
            end
            page.count = #state.pages
            if page.index > page.count then page.index = page.count end
            local range = state.pages[page.index]
            local blocks = {}
            for index = range.first, range.last do
                if #blocks > 0 then table.insert(blocks, space(nil, gap)) end
                table.insert(blocks, TextPages.quote(items[index], w))
            end
            return vstack({ w = w }, blocks)
        end,
    }
end

-- --------------------------------------------------------- genres & tags
-- Every genre of the book as a chip; tapping one closes the sheet and runs
-- on_pick(genre), which lists that genre's books.
function TextPages.tags(book, on_pick)
    local genres = {}
    for _i, v in ipairs(book.genres or {}) do
        local g = trimmed(v)
        if g then table.insert(genres, g) end
    end
    local build = function(page, sw, sh)
        return SheetUI.sheet(page, sw, sh, function(w)
            local items = { SheetUI.titleRow(w, _("Genres & tags"), book.title) }
            if #genres > 0 then
                local chips = {}
                for index, g in ipairs(genres) do table.insert(chips, SheetUI.chip(g, w, { kind = "genre", index = index })) end
                table.insert(items, SheetUI.section(w, _("Genres"), SheetUI.wrap(w, chips, px(8)), text(tostring(#genres), { s = 13, col = INK.g4 })))
                table.insert(items, SheetUI.note(w, "tag", _("From the book's tags (Calibre's Tags column). Tap one to see its books."), { col = INK.g4 }))
            else
                table.insert(items, SheetUI.note(w, "tag", _("No tags on this book yet. Tags added in Calibre show here."), { col = INK.g4 }))
            end
            return items
        end, { pop_w = 460 })
    end
    return SheetUI.open{
        name = "aleph_genres_tags",
        build = build,
        on_action = function(page, action)
            if action.kind == "genre" and genres[action.index] then
                local g = genres[action.index]
                page:close()
                if on_pick then UIManager:tickAfterNext(function() on_pick(g) end) end
            end
            return true
        end,
    }
end

return TextPages
