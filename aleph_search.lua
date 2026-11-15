-- Aleph modification, 2026-11-15: searching a book as the Kindle does.
--[[--
KOReader's search goes from one match to the next, or lists them all in a
plain menu. With Settings > Reader > Search like a Kindle on (as it is unless
turned off), searching a book works this way instead:

  the results    one page of every match, two lines of text around each,
                 the word in bold, with its chapter and page; tabs for
                 Annotations (highlights and notes with the words) and Text
  a result       the book opens there with the match highlighted, and a bar
                 at the foot of the page: the page, ‹ Result 3 of 46 › and ×.
                 The page still turns as usual; "Result 3 of 46" brings the
                 list back
  ×              closes the bar. When the page is not the one you were
                 reading, a strip offers "Go to most recent page" (from page
                 53 to 11); once there, "Return to page 53" goes back again

Searching starts from Aleph's text prompt (the reader menu's search, a
gesture, selected text's Search): it always finds every match, ignoring
case. Holding the search button on the results page opens KOReader's own
search box, with its options (case, whole words, regular expressions).

The search itself is KOReader's (ReaderSearch:findAllText, in a background
process that a tap cancels); only what shows the results is Aleph's.
]]

local Device = require("device")
local Event = require("ui/event")
local Geom = require("ui/geometry")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")
local T = require("ffi/util").template
local _ = require("aleph_gettext")

local BoardMetrics = require("aleph_board_metrics")
local BoardUI = require("aleph_board_ui")
local try = require("aleph_try").call

local Screen = Device.screen
local INK = BoardMetrics.INK
local px = BoardMetrics.px
local text, vstack, hstack, space, flex, icon = BoardUI.text, BoardUI.vstack, BoardUI.hstack, BoardUI.space, BoardUI.flex, BoardUI.icon
local floor = math.floor

local Search = {}

local SNIPPET_SIZE = 15
local SNIPPET_LINES = 2
local META_SIZE = 13

local function hOf(w) return w:getSize().h end
local function wOf(w) return w:getSize().w end

function Search.wanted()
    local ok, on = pcall(function() return require("aleph_prefs").get().kindle_search ~= false end)
    return not ok or on
end

-- -------------------------------------------------------------- places
-- Where the reader is: an xpointer (EPUB and the like) or a page (PDF).
function Search.here(ui)
    if ui.rolling then return ui.document:getXPointer() end
    return ui.paging and ui.paging.current_page or ui:getCurrentPage()
end

function Search.pageOf(ui, loc)
    if ui.rolling then
        local n
        pcall(function() n = ui.document:getPageFromXPointer(loc) end)
        return n
    end
    return tonumber(loc)
end

-- The page as the book numbers it (its own page labels when it has them).
function Search.pageLabel(ui, loc)
    local pn = Search.pageOf(ui, loc)
    local ref
    pcall(function() ref = ui.annotation:getPageRef(loc, pn) end)
    return tostring(ref or pn or "?")
end

local function clearMark(ui)
    try(function() ui.highlight:clear() end)
    if ui.paging then try(function() ui.view.highlight.temp = {} end) end
end

function Search.go(ui, loc)
    clearMark(ui)
    if ui.rolling then
        ui.rolling:onGotoXPointer(loc)
    else
        ui.paging:onGotoPage(loc)
    end
end

-- ----------------------------------------------------------- the results
local function lower(s)
    local ok, low = pcall(function() return require("ffi/utf8proc").lowercase(s) end)
    return ok and low or s:lower()
end

local function ptf(before, word, after)
    local TextBoxWidget = require("ui/widget/textboxwidget")
    local parts = { TextBoxWidget.PTF_HEADER }
    if before and before ~= "" then
        parts[#parts + 1] = before
        if not before:find("%s$") then parts[#parts + 1] = " " end
    end
    parts[#parts + 1] = TextBoxWidget.PTF_BOLD_START .. word .. TextBoxWidget.PTF_BOLD_END
    if after and after ~= "" then
        if not after:find("^[%s%p]") then parts[#parts + 1] = " " end
        parts[#parts + 1] = after
    end
    return table.concat(parts)
end

-- A match found by KOReader's findAllText.
local function textResult(item)
    return {
        kind = "text", item = item, loc = item.start,
        snippet = ptf(item.prev_text, (item.matched_word_prefix or "") .. (item.matched_text or "") .. (item.matched_word_suffix or ""), item.next_text),
    }
end

-- Highlights and notes holding the words, as the Kindle's Annotations tab.
function Search.annotationResults(ui, query)
    local out = {}
    local q = lower(query or "")
    if q == "" then return out end
    local entries = {}
    try(function() entries = require("aleph_bookmarks").entries(ui) end)
    for _i, e in ipairs(entries) do
        for _j, field in ipairs({ e.text, e.note }) do
            if field and field ~= "" then
                local low = lower(field)
                local at = low:find(q, 1, true)
                if at then
                    -- Byte positions agree as long as lowering kept lengths
                    -- (it does for the scripts that matter here); if not,
                    -- the whole passage is shown with nothing bold.
                    local snippet
                    if #low == #field then
                        local before = field:sub(math.max(1, at - 80), at - 1):gsub("^[\128-\191]+", "")
                        local word = field:sub(at, at + #q - 1)
                        local after = field:sub(at + #q, at + #q + 160)
                        if at > 81 then before = "…" .. before end
                        snippet = ptf(before, word, after)
                    else
                        snippet = field
                    end
                    out[#out + 1] = { kind = "annotation", entry = e, snippet = snippet, chapter = e.chapter, label = e.page }
                    break
                end
            end
        end
    end
    return out
end

-- The session of one search in one book.
local session

function Search.session() return session end

local function listOf(s) return s.tab == "annotations" and s.annots or s.text end

local function metaOf(ui, r)
    if r.meta then return r.meta end
    local chapter, label = r.chapter, r.label
    if r.kind == "text" then
        try(function() chapter = ui.toc:getTocTitleByPage(r.loc) end)
        label = Search.pageLabel(ui, r.loc)
    end
    if chapter and chapter ~= "" and label and label ~= "" then
        r.meta = T(_("%1, page %2"), chapter, label)
    elseif label and label ~= "" then
        r.meta = T(_("Page %1"), label)
    else
        r.meta = chapter or ""
    end
    return r.meta
end

local function rowHeight()
    return px(10) + BoardMetrics.textBoxHeight(SNIPPET_LINES, SNIPPET_SIZE) + px(6) + BoardMetrics.lh1(META_SIZE) + px(10)
end

local function rowWidget(ui, r, w, at)
    local TextBoxWidget = require("ui/widget/textboxwidget")
    local cw = px(28)
    local tw = w - cw - px(8)
    local snippet = TextBoxWidget:new{
        text = r.snippet,
        face = BoardMetrics.face(SNIPPET_SIZE, "sans"),
        fgcolor = INK.black,
        bgcolor = INK.white,
        width = tw,
        height = BoardMetrics.textBoxHeight(SNIPPET_LINES, SNIPPET_SIZE),
        height_adjust = true,
        height_overflow_show_ellipsis = true,
    }
    local body = vstack({ w = tw, h = rowHeight(), pad = { px(10), 0, px(10), 0 } }, {
        snippet, space(nil, px(6)),
        text(metaOf(ui, r), { s = META_SIZE, col = INK.g3, w = tw, data = true }),
    })
    local row = hstack({ w = w, h = rowHeight() }, { body, flex(px(8)), icon("chevron-right", px(22), { sw = 2.25 }) })
    return BoardUI.hit(row, { kind = "result", at = at })
end

local function iconButton(name, action, size)
    return BoardUI.hit(hstack({ w = px(48), h = px(48) }, { flex(0), icon(name, px(size or 24), { sw = 2.25 }), flex(0) }), action)
end

local function tabsRow(s, w)
    local cells = {}
    local tabs = {
        { "annotations", T(_("Annotations (%1)"), #s.annots) },
        { "text", T(_("Text (%1)"), #s.text) },
    }
    for i, t in ipairs(tabs) do
        local on = s.tab == t[1]
        local label = text(t[2], { s = 15, b = on, col = on and INK.black or INK.g3 })
        local cell = vstack({ w = wOf(label) + px(24), h = px(48) }, {
            flex(0), hstack({ w = wOf(label) + px(24) }, { flex(0), label, flex(0) }), flex(0),
            BoardUI.rect(wOf(label) + px(24), on and math.max(3, px(4)) or 1, on and INK.black or INK.white),
        })
        cells[i] = BoardUI.hit(cell, { kind = "tab", tab = t[1] })
    end
    return vstack({ w = w }, {
        hstack({ w = w, gap = px(8) }, { cells[1], cells[2], flex(0) }),
        BoardUI.rect(w, math.max(1, px(1.5)), INK.black),
    })
end

local function pagerRow(p, w)
    local fh = px(48)
    local function step(name, action, on)
        local c = hstack({ w = px(52), h = fh }, { flex(0), icon(name, px(22), { sw = 2.25, col = on and "black" or "gb" }), flex(0) })
        return on and BoardUI.hit(c, action) or c
    end
    local i, n = p.index, p.count
    return hstack({ w = w, h = fh }, {
        flex(0), step("chevron-left", { kind = "page", delta = -1 }, i > 1),
        text(T(_("%1 of %2"), i, n), { s = 14 }),
        step("chevron-right", { kind = "page", delta = 1 }, i < n), flex(0),
    })
end

local function buildResults(p, sw, sh)
    BoardMetrics.refresh()
    local s, ui = p.session, p.session.ui
    local mx = require("aleph_menu_ui").mx()
    local w = sw - 2 * mx
    local total = #s.text + #s.annots
    local head = hstack({ w = w, h = px(56) }, {
        iconButton("arrow-left", { kind = "results-back" }),
        space(px(8), 1),
        text(total == 1 and _("1 result") or T(_("%1 results"), total), { s = 20, b = true, w = w - 3 * px(48) - px(8), data = true }),
        iconButton("search", { kind = "new-search" }),
        iconButton("x", { kind = "results-close" }),
    })
    local tabs = tabsRow(s, w)
    local list = listOf(s)
    local pager_h = px(48)
    local body_h = sh - px(6) - hOf(head) - hOf(tabs) - pager_h - px(8)
    local row_h = rowHeight() + math.max(1, px(1))
    p.per_page = math.max(1, floor(body_h / row_h))
    p.count = math.max(1, math.ceil(#list / p.per_page))
    if p.want then
        p.index = floor((p.want - 1) / p.per_page) + 1
        p.want = nil
    end
    p.index = math.max(1, math.min(p.count, p.index or 1))
    local items = {}
    if #list == 0 then
        items[1] = space(nil, px(32))
        items[2] = text(s.tab == "annotations" and _("No highlights or notes with these words.") or _("These words are not in the text."),
            { s = 15, col = INK.g4, w = w, align = "center" })
    else
        local first = (p.index - 1) * p.per_page + 1
        for i = first, math.min(#list, first + p.per_page - 1) do
            items[#items + 1] = rowWidget(ui, list[i], w, i)
            items[#items + 1] = BoardUI.rect(w, math.max(1, px(1)), INK.gc)
        end
    end
    return vstack({ w = sw, h = sh, pad = { px(6), mx, px(8), mx }, top = true }, {
        head, tabs,
        vstack({ w = w, h = body_h }, { vstack({ w = w }, items), flex(0) }),
        p.count > 1 and pagerRow(p, w) or space(nil, pager_h),
    })
end

local function turnResults(p, delta)
    local target = math.max(1, math.min(p.count or 1, (p.index or 1) + delta))
    if target ~= p.index then
        p.index = target
        p:refresh(Device:hasEinkScreen() and "partial" or "ui")
    end
end

-- ------------------------------------------------- the strip at the foot
local Strip = InputContainer:extend{
    ui = nil,
    height = nil,
    build = nil,        -- function(strip, w, h) -> widget
    on_action = nil,    -- function(strip, action)
    on_outside = nil,   -- function(strip, ges): before the book gets the gesture
    name = "aleph_search_strip",
    covers_fullscreen = false,
}

function Strip:init()
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = sh - self.height, w = sw, h = self.height }
    self:rebuild()
end

function Strip:rebuild()
    local widget, hits = BoardUI.collectHits(function()
        return self.build(self, self.dimen.w, self.dimen.h)
    end)
    if self[1] and self[1].free then self[1]:free() end
    self[1] = widget
    self.hits = hits
end

function Strip:refresh()
    self:rebuild()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

function Strip:paintTo(bb, x, y)
    local d = self.dimen
    bb:paintRect(d.x, d.y, d.w, d.h, INK.white)
    self[1]:paintTo(bb, d.x, d.y)
end

function Strip:onCloseWidget()
    if self[1] and self[1].free then self[1]:free() end
end

function Strip:close()
    if self.closed then return end
    self.closed = true
    UIManager:close(self, "ui", self.dimen)
end

local function hitAt(hits, pos)
    local best, best_size
    for _i, area in ipairs(hits or {}) do
        local d = area.dimen
        if d and pos:intersectWith(d) and (not best_size or d.w * d.h < best_size) then
            best, best_size = area, d.w * d.h
        end
    end
    return best
end

-- Taps on the strip are its own; everything else goes on to the book under
-- it, so its pages still turn.
function Strip:handleEvent(event)
    if self.closed then return false end
    if event.handler == "onGesture" then
        local ges = event.args and event.args[1]
        if ges and ges.pos and ges.pos:intersectWith(self.dimen) then
            if ges.ges == "tap" or ges.ges == "hold" then
                local area = hitAt(self.hits, ges.pos)
                if area and area.action and self.on_action then
                    self.on_action(self, area.action, ges.ges == "hold")
                end
            end
            return true
        end
        if self.on_outside then self.on_outside(self, ges) end
        local ui = self.ui
        local used = ui and ui.handleEvent and ui:handleEvent(event)
        if not self.closed and self.after_book then self.after_book(self) end
        return used
    end
    if event.handler == "onKeyPress" then
        local key = event.args and event.args[1]
        if key and Device:hasKeys() and key.match and key:match({ Device.input.group.Back }) then
            if self.on_action then self.on_action(self, { kind = "strip-back" }) end
            return true
        end
        local used = self.ui and self.ui:handleEvent(event)
        if not self.closed and self.after_book then self.after_book(self) end
        return used
    end
    return InputContainer.handleEvent(self, event)
end

-- ----------------------------------------------------------- the session
local nav_strip, back_strip

local function closeStrips()
    if nav_strip then nav_strip:close(); nav_strip = nil end
    if back_strip then back_strip:close(); back_strip = nil end
end

local function pickResult(s, index)
    local list = listOf(s)
    local r = list[index]
    if not r then return end
    s.index = index
    local ui = s.ui
    if not s.stacked then
        -- KOReader's own Go back returns here too.
        try(function() ui.link:addCurrentLocationToStack() end)
        s.stacked = true
    end
    clearMark(ui)
    if r.kind == "text" then
        local item = r.item
        if ui.rolling then
            ui.rolling:onGotoXPointer(item.start, item.start)
            try(function() ui.document:getTextFromXPointers(item.start, item["end"], true) end)
        else
            local page = item.start
            local boxes = {}
            try(function()
                for i, box in ipairs(item.boxes or {}) do boxes[i] = ui.document:nativeToPageRectTransform(page, box) end
            end)
            ui.paging:onGotoPage(page)
            try(function() ui.view.highlight.temp[page] = boxes end)
        end
    else
        require("aleph_bookmarks").goTo(ui, r.entry)
    end
    UIManager:setDirty(ui.dialog, "ui")
end

local showBack -- forward

local function buildNav(strip, w, h)
    local s = session
    local ui = s.ui
    local list = listOf(s)
    local n, i = #list, s.index or 1
    local bar = math.max(2, px(2.5))
    local mx = px(16)
    local page = text(T(_("Page %1"), Search.pageLabel(ui, Search.here(ui))), { s = 13, col = INK.g3 })
    local close = BoardUI.hit(hstack({ w = px(48), h = h - bar }, { flex(0), icon("x", px(24), { sw = 2.25 }), flex(0) }), { kind = "nav-close" })
    local side = math.max(wOf(page), wOf(close))
    local function arrow(name, kind, on)
        local c = hstack({ w = px(56), h = h - bar }, { flex(0), icon(name, px(24), { sw = 2.25, col = on and "black" or "gb" }), flex(0) })
        return on and BoardUI.hit(c, { kind = kind }) or c
    end
    local label = text(T(_("Result %1 of %2"), i, n), { s = 15, b = true })
    local result = BoardUI.hit(vstack({ w = wOf(label), h = h - bar }, {
        flex(0), label, space(nil, px(2)), BoardUI.rect(wOf(label), math.max(1, px(1.5)), INK.black), flex(0),
    }), { kind = "nav-list" })
    return vstack({ w = w, h = h }, {
        BoardUI.rect(w, bar, INK.black),
        hstack({ w = w, h = h - bar }, {
            space(mx, 1),
            hstack({ w = side, h = h - bar }, { page, flex(0) }),
            flex(0), arrow("chevron-left", "nav-prev", i > 1), space(px(8), 1), result, space(px(8), 1),
            arrow("chevron-right", "nav-next", i < n), flex(0),
            hstack({ w = side, h = h - bar }, { flex(0), close }),
            space(mx - px(4), 1),
        }),
    })
end

local function showNav()
    local s = session
    if not s then return end
    if nav_strip then nav_strip:close() end
    nav_strip = Strip:new{
        ui = s.ui,
        height = px(64),
        build = buildNav,
        on_action = function(strip, action, held)
            local list = listOf(session)
            local k = action.kind
            if k == "nav-prev" then
                pickResult(session, held and 1 or math.max(1, session.index - 1))
                strip:refresh()
            elseif k == "nav-next" then
                pickResult(session, held and #list or math.min(#list, session.index + 1))
                strip:refresh()
            elseif k == "nav-list" then
                strip:close(); nav_strip = nil
                Search.openResults(session, session.index)
            elseif k == "nav-close" or k == "strip-back" then
                strip:close(); nav_strip = nil
                Search.finish()
            end
        end,
        -- The page label follows a page turned under the strip.
        after_book = function(strip) strip:refresh() end,
    }
    UIManager:show(nav_strip)
    UIManager:setDirty(nav_strip, function() return "ui", nav_strip.dimen end)
end

local function buildBack(strip, w, h)
    local b = strip.state
    local ui = b.ui
    local here = Search.pageLabel(ui, Search.here(ui))
    local there = Search.pageLabel(ui, b.other)
    local bar = math.max(2, px(2.5))
    local mx = px(24)
    local iw = w - 2 * mx
    local label
    if b.mode == "back" then
        label = hstack({ h = px(52), gap = px(10) }, { icon("chevron-left", px(22), { sw = 2.25 }), text(_("Go to most recent page"), { s = 15 }) })
    else
        label = hstack({ h = px(52), gap = px(10) }, { text(T(_("Return to page %1"), there), { s = 15 }), icon("chevron-right", px(22), { sw = 2.25 }) })
    end
    local bw = math.min(iw, math.max(wOf(label) + px(48), floor(iw * 0.62)))
    local button = BoardUI.hit(BoardUI.box({ w = bw, h = px(56), radius = px(6), border = math.max(1, px(1.5)), border_col = INK.black, bg = INK.white },
        hstack({ w = bw - 2 * math.max(1, px(1.5)), h = px(56) - 2 * math.max(1, px(1.5)) }, { flex(0), label, flex(0) })), { kind = "back-go" })
    local hide = BoardUI.hit(hstack({ w = px(96), h = px(40) }, { flex(0), icon("chevron-down", px(30), { sw = 2.25 }), flex(0) }), { kind = "back-hide" })
    return vstack({ w = w, h = h }, {
        BoardUI.rect(w, bar, INK.black),
        hstack({ w = w }, { flex(0), hide, flex(0) }),
        space(nil, px(8)),
        hstack({ w = w }, { flex(0), button, flex(0) }),
        flex(0),
        hstack({ w = w }, { space(mx, 1), text(T(_("From page %1 to %2"), here, there), { s = 13, col = INK.g3, w = iw, data = true }) }),
        space(nil, px(10)),
    })
end

showBack = function(ui, other)
    if back_strip then back_strip:close() end
    back_strip = Strip:new{
        ui = ui,
        height = px(150),
        state = { ui = ui, other = other, mode = "back" },
        build = buildBack,
        on_action = function(strip, action)
            local k = action.kind
            if k == "back-go" then
                local b = strip.state
                local now = Search.here(ui)
                Search.go(ui, b.other)
                b.other = now
                b.mode = b.mode == "back" and "return" or "back"
                strip:refresh()
            elseif k == "back-hide" or k == "strip-back" then
                strip:close(); back_strip = nil
            end
        end,
        -- Reading on (a tap or a page turned) puts the strip away.
        on_outside = function(strip, ges)
            if ges and (ges.ges == "tap" or ges.ges == "swipe") then strip:close(); back_strip = nil end
        end,
    }
    UIManager:show(back_strip)
    UIManager:setDirty(back_strip, function() return "ui", back_strip.dimen end)
end

-- The search is over: the mark goes, and when the page is not the one the
-- reader left, the way back is offered.
function Search.finish()
    local s = session
    if not s then return end
    local ui = s.ui
    clearMark(ui)
    UIManager:setDirty(ui.dialog, "ui")
    local now = Search.here(ui)
    if s.start and Search.pageOf(ui, s.start) ~= Search.pageOf(ui, now) then
        showBack(ui, s.start)
    end
    s.stacked = false
end

function Search.openResults(s, at_index)
    local MenuPage = require("aleph_menu_page")
    local page
    page = MenuPage:new{
        name = "aleph_search_results",
        session = s,
        index = 1,
        want = at_index,
        build = buildResults,
        on_action = function(p, action)
            local k = action.kind
            if k == "tab" then
                if s.tab ~= action.tab then s.tab = action.tab; p.index = 1; p:refresh() end
            elseif k == "page" then
                turnResults(p, action.delta or 0)
            elseif k == "result" then
                p:close()
                UIManager:nextTick(function()
                    pickResult(s, action.at)
                    showNav()
                end)
            elseif k == "new-search" then
                p:close()
                UIManager:nextTick(function() Search.prompt(s.ui, s.query) end)
            elseif k == "results-back" then
                p:close()
                -- Back to the result that was open, or out of the search.
                if s.index and s.opened then
                    UIManager:nextTick(showNav)
                else
                    UIManager:nextTick(Search.finish)
                end
            elseif k == "results-close" then
                p:close()
                UIManager:nextTick(Search.finish)
            end
        end,
        on_back = function(p)
            p:runAction({ kind = "results-back" })
            return true
        end,
        on_hold = function(p, action)
            if action.kind == "new-search" then
                -- KOReader's own search box, with its options.
                p:close()
                UIManager:nextTick(function()
                    local rs = s.ui.search
                    if rs and Search._native_input then Search._native_input(rs, s.query) end
                end)
                return true
            end
        end,
        on_swipe = function(p, ges)
            if ges.direction == "west" then turnResults(p, 1) return true end
            if ges.direction == "east" then turnResults(p, -1) return true end
            return false
        end,
        on_page_key = function(p, delta) turnResults(p, delta) end,
    }
    if at_index then s.opened = true end
    UIManager:show(page, "ui")
    return page
end

-- A new set of results from KOReader's findAllText.
function Search.showResults(rs, fresh)
    local ui = rs.ui
    closeStrips()
    if fresh or not session or session.ui ~= ui or session.query ~= rs.last_search_text then
        local text_results = {}
        for _i, item in ipairs(rs.findall_results or {}) do text_results[#text_results + 1] = textResult(item) end
        local annots = Search.annotationResults(ui, rs.last_search_text)
        -- Where the reader was before searching: KOReader notes it as the
        -- search starts.
        local start = rs.start_page or Search.here(ui)
        if session and session.ui == ui and session.start and session.stacked then start = session.start end
        session = {
            ui = ui, query = rs.last_search_text, text = text_results, annots = annots,
            tab = (#text_results == 0 and #annots > 0) and "annotations" or "text",
            start = start,
        }
    end
    if not session.stacked then
        -- A search again after the last one was closed starts from here.
        session.start = rs.start_page or Search.here(ui)
    end
    session.opened = false
    Search.openResults(session, nil)
end

-- Aleph's search prompt: Search finds every match.
function Search.prompt(ui, current)
    local rs = ui.search
    if not rs then return end
    require("aleph_input").prompt{
        title = _("Search this book"),
        text = current or rs.last_search_text or (ui.doc_settings and ui.doc_settings:readSetting("fulltext_search_last_search_text")) or "",
        hint = _("Words to find"),
        ok_label = _("Search"),
        on_ok = function(query)
            query = tostring(query or ""):gsub("^%s+", ""):gsub("%s+$", "")
            if query == "" then return end
            -- KOReader's "find all", case ignored, plain text.
            rs:searchCallback(nil, query)
        end,
    }
end

-- A book closes: the strips go with it.
function Search.detach(ui)
    closeStrips()
    if session and session.ui == ui then session = nil end
end

-- For tests.
Search._pick = function(s, i) return pickResult(s, i) end
Search._strips = function() return nav_strip, back_strip end
Search._showNav = function() return showNav() end

function Search.install()
    local ok, ReaderSearch = pcall(require, "apps/reader/modules/readersearch")
    if not ok or not ReaderSearch or ReaderSearch._aleph_search then return end
    ReaderSearch._aleph_search = true
    local native_input = ReaderSearch.onShowFulltextSearchInput
    local native_results = ReaderSearch.onShowFindAllResults
    local native_text = ReaderSearch.searchText
    Search._native_input = native_input
    ReaderSearch.onShowFulltextSearchInput = function(self, search_string, ...)
        if not Search.wanted() then return native_input(self, search_string, ...) end
        local shown = pcall(Search.prompt, self.ui, search_string)
        if not shown then return native_input(self, search_string, ...) end
        return true
    end
    ReaderSearch.searchText = function(self, text_, ...)
        if not Search.wanted() then return native_text(self, text_, ...) end
        -- Selected text's Search: every match, as on a Kindle.
        try(function() self.ui.highlight:clear() end)
        return self:searchCallback(nil, text_)
    end
    ReaderSearch.onShowFindAllResults = function(self, not_cached, ...)
        if not Search.wanted() or not self.last_search_hash or not self.findall_results then
            return native_results(self, not_cached, ...)
        end
        local shown, err = pcall(Search.showResults, self, not_cached)
        if shown then return true end
        require("logger").warn("Aleph: search results page failed:", err)
        return native_results(self, not_cached, ...)
    end
end

return Search
