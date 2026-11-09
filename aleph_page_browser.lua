-- Aleph modification, 2026-11-09: a page browser like the Kindle app's,
-- after ZenOS's (zenos.koplugin, modules/reader/patches/page_browser.lua and
-- modules/reader/page_browser_widget.lua; see ZENOS_NOTICE.md), drawn with
-- Aleph's own parts, font and sizes.
--[[--
Over the book, a page at a glance and everything around it:

  top      ⋮ KOReader's menu, a row of tabs, close
           Pages (this view) · Aa (KOReader's reading settings) · Bookmarks ·
           Highlights · Contents · Pinned pages
  middle   the pages as a carousel: the focused page large in the middle with
           its number, its neighbours either side
             swipe left / right, or tap a side page   move through the book
             tap the middle page                      read from there
  bottom   the chapter and "Page 118 of 616 · 19%", the page grid (KOReader's
           own page browser) and search; a slider with ‹ and ›
             tap the slider        jump to that point of the book
             ‹ ›                   one page back or on; hold for the previous
                                   or next chapter

Opened by swiping up from the bottom edge of a book (ZenOS's bottom swipe
zone; Settings > Opening > Dialogs turns it off) or by the "Aleph:
page browser" gesture action. Back or × returns to the page you were on.

As in ZenOS, the previews are KOReader's own page thumbnails
(ReaderThumbnail), the zone overrides KOReader's bottom swipes so the swipe
up wins, and jumps put the page you were on in the location stack.
]]

local Device = require("device")
local Event = require("ui/event")
local Geom = require("ui/geometry")
local UIManager = require("ui/uimanager")
local T = require("ffi/util").template
local _ = require("gettext")

local BoardMetrics = require("aleph_board_metrics")
local BoardUI = require("aleph_board_ui")
local MenuPage = require("aleph_menu_page")
local MenuUI = require("aleph_menu_ui")
local Picture = require("aleph_picture")

local Screen = Device.screen
local INK = BoardMetrics.INK
local px = BoardMetrics.px
local text, vstack, hstack, space, flex, icon = BoardUI.text, BoardUI.vstack, BoardUI.hstack, BoardUI.space, BoardUI.flex, BoardUI.icon
local floor = math.floor

local PageBrowser = {}

local TABS = {
    { id = "pages", icon = "book-open", label = function() return _("Pages") end },
    { id = "aa", icon = "type", label = function() return _("Reading settings") end },
    { id = "bookmarks", icon = "bookmark", label = function() return _("Bookmarks") end },
    { id = "highlights", icon = "highlighter", label = function() return _("Highlights") end },
    { id = "toc", icon = "list-ordered", label = function() return _("Contents") end },
    { id = "pins", icon = "pin", label = function() return _("Pinned pages") end },
}

local function hOf(widget) return widget:getSize().h end
local function wOf(widget) return widget:getSize().w end

-- ------------------------------------------------------------------ book
local function pageCount(ui)
    local n
    pcall(function() n = ui.document:getPageCount() end)
    return math.max(1, tonumber(n) or 1)
end

local function currentPage(ui)
    local page
    pcall(function() page = ui:getCurrentPage() end)
    if not page then pcall(function() page = ui.document:getCurrentPage() end) end
    return tonumber(page) or 1
end

local function chapterOf(ui, page)
    local title
    pcall(function() title = ui.toc:getTocTitleByPage(page) end)
    if type(title) ~= "string" or not title:match("%S") then return nil end
    return title
end

-- "Page 118 of 616 · 19%" (ZenOS's format_progress).
function PageBrowser.progress(page, total)
    return T(_("Page %1 of %2"), page, total) .. " · " .. floor(page / math.max(1, total) * 100) .. "%"
end

-- The page a tap at x on a slider from x0, w wide, stands for.
function PageBrowser.pageAt(x, x0, w, total)
    local ratio = math.max(0, math.min(1, (x - x0) / math.max(1, w)))
    return math.max(1, math.min(total, floor(ratio * (total - 1) + 0.5) + 1))
end

-- ------------------------------------------------------------ thumbnails
-- The previews: only the page in the middle and its two neighbours are kept
-- (each is a page-sized bitmap, several megabytes on a color screen), asked
-- for one at a time, the middle page first, a moment after the browser stops
-- moving, so fast swiping does not pile up renders. Anything else is freed,
-- and pending renders are cancelled when the browser closes. (0.1.46 kept
-- every page it was asked for and prefetched two more each step, which ran
-- the Kindle out of memory: the "Killed" at the end of the crash log.)
local KEEP = 1
local SETTLE = 0.3

local function wanted(page, n)
    return n >= 1 and n <= page.total and math.abs(n - page.focus) <= KEEP
end

local function prune(page)
    local st = page.thumbs
    for n, bb in pairs(st.bbs or {}) do
        if not wanted(page, n) then
            if bb.free then bb:free() end
            st.bbs[n] = nil
        end
    end
end

local requestNext

local function schedule(page)
    local st = page.thumbs
    if st.timer then UIManager:unschedule(st.timer) end
    st.timer = function()
        st.timer = nil
        requestNext(page)
    end
    -- The first preview is asked for at once; later ones once moving stops.
    UIManager:scheduleIn(st.started and SETTLE or 0, st.timer)
    st.started = true
end

-- A preview that arrived is drawn in its own place only, with KOReader's
-- quiet "ui" refresh, and previews arriving close together share one
-- repaint. (0.1.47 redrew the whole screen for each, which flashed the
-- e-ink screen three times as the browser opened.)
local function repaintPreview(page, n)
    local rect = page.preview_rects and page.preview_rects[n]
    if not rect then return end
    page.dirty_rect = page.dirty_rect and page.dirty_rect:combine(rect) or rect:copy()
    if page.repaint_task then return end
    page.repaint_task = function()
        page.repaint_task = nil
        local region = page.dirty_rect
        page.dirty_rect = nil
        if page.closed or not region then return end
        page:rebuild()
        UIManager:setDirty(page, function() return "ui", region end)
    end
    UIManager:scheduleIn(0.15, page.repaint_task)
end

requestNext = function(page)
    local st, ui = page.thumbs, page.ui
    if page.closed or st.pending or not ui.thumbnail or not st.w then return end
    local n
    for _i, c in ipairs({ page.focus, page.focus + 1, page.focus - 1 }) do
        if wanted(page, c) and not st.bbs[c] and not st.failed[c] then n = c; break end
    end
    if not n then return end
    st.pending = n
    local w, h = st.w, st.h
    local ok = pcall(function()
        ui.thumbnail:getPageThumbnail(n, w, h, "aleph_page_browser", function(tile)
            st.pending = nil
            local bb = tile and tile.bb
            if page.closed or st.w ~= w or st.h ~= h then return end
            if not bb then
                st.failed[n] = true
            elseif wanted(page, n) and not st.bbs[n] then
                st.bbs[n] = bb:copy()
                repaintPreview(page, n)
            end
            UIManager:nextTick(function() requestNext(page) end)
        end)
    end)
    if not ok then st.pending = nil; st.failed[n] = true end
end

function PageBrowser.releaseThumbs(page)
    Picture.release(page)
    local st = page.thumbs
    if st.timer then UIManager:unschedule(st.timer); st.timer = nil end
    if page.repaint_task then UIManager:unschedule(page.repaint_task); page.repaint_task = nil end
    for _k, bb in pairs(st.bbs or {}) do if bb.free then bb:free() end end
    st.bbs = {}
    if st.pending and page.ui.thumbnail then
        pcall(function() page.ui.thumbnail:cancelPageThumbnailRequests() end)
    end
    st.pending = nil
end

local function thumb(page, n, w, h)
    local st = page.thumbs
    if st.w ~= w or st.h ~= h then
        for _k, bb in pairs(st.bbs or {}) do if bb.free then bb:free() end end
        st.bbs, st.failed, st.w, st.h = {}, {}, w, h
    end
    return st.bbs[n]
end

-- A page preview w x h; with crop_side ("left" / "right") only that edge of
-- it shows, w being the part on screen out of full_w.
local function preview(page, n, w, h, o)
    o = o or {}
    local full_w = o.full_w or w
    local bb = thumb(page, n, full_w, h)
    local b = o.focus and math.max(2, px(2.5)) or math.max(1, px(1.25))
    local inner_w, inner_h = w - 2 * b, h - 2 * b
    local picture
    if bb then
        if o.crop_side then
            local fit = math.min((full_w - 2 * b) / bb:getWidth(), inner_h / bb:getHeight())
            local shown = math.min(1, inner_w / (bb:getWidth() * fit))
            local cx = o.crop_side == "left" and (1 - shown / 2) or (shown / 2)
            picture = Picture.view(page, bb, inner_w, inner_h, fit, cx, 0.5)
        else
            picture = Picture.view(page, bb, inner_w, inner_h)
        end
    else
        picture = hstack({ w = inner_w, h = inner_h }, { flex(0), text("…", { s = 20, col = INK.g6 }), flex(0) })
    end
    local box = BoardUI.box({ w = w, h = h, radius = px(6), border = b, border_col = o.focus and INK.black or INK.g8, bg = INK.white },
        hstack({ w = inner_w, h = inner_h }, { flex(0), picture, flex(0) }))
    return box
end

-- --------------------------------------------------------------- the top
local function tabBar(page, w)
    local n = #TABS
    local b = math.max(1, px(1.5))
    local cell_w = floor((w - 2 * b) / n)
    local h = px(48)
    local cells = {}
    for i, tab in ipairs(TABS) do
        local on = tab.id == "pages"
        local cw = i == n and (w - 2 * b - cell_w * (n - 1)) or cell_w
        local cell = hstack({ w = cw, h = h - 2 * b }, { flex(0), icon(tab.icon, px(22), { sw = 2.25, col = on and "white" or "black" }), flex(0) })
        if on then cell = BoardUI.box({ w = cw, h = h - 2 * b, radius = px(10), bg = INK.black }, cell) end
        cells[#cells + 1] = BoardUI.hit(cell, { kind = "tab", id = tab.id })
    end
    return BoardUI.box({ w = w, h = h, radius = px(12), border = b, border_col = INK.black, bg = INK.white },
        hstack({ w = w - 2 * b, h = h - 2 * b }, cells))
end

local function iconButton(name, action, size)
    return BoardUI.hit(hstack({ w = px(44), h = px(48) }, { flex(0), icon(name, px(size or 24), { sw = 2.25 }), flex(0) }), action)
end

-- --------------------------------------------------------------- the foot
local function slider(page, w)
    local h = px(48)
    local knob = px(24)
    local track_h = math.max(2, px(4))
    local total = page.total
    local ratio = total > 1 and (page.focus - 1) / (total - 1) or 0
    local usable = w - knob
    local kx = floor(usable * ratio)
    local fill_w = kx + floor(knob / 2)
    local track_y = floor((h - track_h) / 2)
    local layers = {
        { widget = BoardUI.rect(w - knob, track_h, INK.g8, floor(track_h / 2)), x = floor(knob / 2), y = track_y },
        { widget = BoardUI.rect(math.max(1, fill_w - floor(knob / 2)), track_h, INK.black, floor(track_h / 2)), x = floor(knob / 2), y = track_y },
        { widget = BoardUI.circle(knob, { bg = INK.black, border = 0 }, BoardUI.space(1, 1)), x = kx, y = floor((h - knob) / 2) },
    }
    page.slider_span = { x0 = page.slider_x + floor(knob / 2), w = usable }
    return BoardUI.hit(BoardUI.overlay(w, h, layers), { kind = "slider" })
end

local function foot(page, w)
    local grid = iconButton("layout-grid", { kind = "grid" }, 26)
    local search = iconButton("search", { kind = "search" }, 26)
    local mid_w = w - wOf(grid) - wOf(search) - px(16)
    local chapter = chapterOf(page.ui, page.focus)
    local block = vstack({ w = mid_w }, {
        chapter and text(chapter, { s = 17, w = mid_w, align = "center", data = true }) or false,
        text(PageBrowser.progress(page.focus, page.total), { s = 14, col = INK.g3, w = mid_w, align = "center" }),
    })
    local row1 = hstack({ w = w, h = math.max(px(56), hOf(block)) }, { grid, flex(px(8)), block, flex(px(8)), search })
    local left = BoardUI.hit(hstack({ w = px(44), h = px(48) }, { flex(0), icon("chevron-left", px(26), { sw = 2.25, col = page.focus > 1 and "black" or "gb" }), flex(0) }), { kind = "step", delta = -1 })
    local right = BoardUI.hit(hstack({ w = px(44), h = px(48) }, { flex(0), icon("chevron-right", px(26), { sw = 2.25, col = page.focus < page.total and "black" or "gb" }), flex(0) }), { kind = "step", delta = 1 })
    local sw_ = w - 2 * px(44) - 2 * px(12)
    page.slider_x = page.mx + px(44) + px(12)
    local row2 = hstack({ w = w, h = px(48) }, { left, space(px(12), 1), slider(page, sw_), space(px(12), 1), right })
    return vstack({ w = w }, { row1, space(nil, px(4)), row2 })
end

-- ------------------------------------------------------------- the pages
local function carousel(page, sw, h)
    local gap = px(14)
    -- The middle page as wide as two thirds of the screen (ZenOS's carousel),
    -- in the screen's shape, smaller when the height is short.
    local pw = floor(sw * 0.66)
    local ph = floor(pw * Screen:getHeight() / Screen:getWidth())
    if ph > h then ph = h; pw = floor(ph * Screen:getWidth() / Screen:getHeight()) end
    local x = floor((sw - pw) / 2)
    local y = floor((h - ph) / 2)
    local layers = {}
    local side_w = x - gap
    -- Where each preview is on screen, for repainting it alone.
    local top = page.carousel_top or 0
    page.preview_rects = {
        [page.focus] = Geom:new{ x = x, y = top + y, w = pw, h = ph },
        [page.focus - 1] = Geom:new{ x = 0, y = top + y, w = math.max(1, side_w), h = ph },
        [page.focus + 1] = Geom:new{ x = x + pw + gap, y = top + y, w = math.max(1, side_w), h = ph },
    }
    if side_w > px(12) then
        if page.focus > 1 then
            layers[#layers + 1] = { widget = BoardUI.hit(preview(page, page.focus - 1, side_w, ph, { full_w = pw, crop_side = "left" }), { kind = "focus", delta = -1 }), x = 0, y = y }
        end
        if page.focus < page.total then
            layers[#layers + 1] = { widget = BoardUI.hit(preview(page, page.focus + 1, side_w, ph, { full_w = pw, crop_side = "right" }), { kind = "focus", delta = 1 }), x = x + pw + gap, y = y }
        end
    end
    layers[#layers + 1] = { widget = BoardUI.hit(preview(page, page.focus, pw, ph, { focus = true }), { kind = "open" }), x = x, y = y }
    -- The page number on a dark pill at the foot of the page.
    local num = text(tostring(page.focus), { s = 13, b = true, col = INK.white })
    local pill_w, pill_h = math.max(px(36), wOf(num) + px(18)), px(28)
    local pill = BoardUI.box({ w = pill_w, h = pill_h, radius = floor(pill_h / 2), bg = INK.black },
        hstack({ w = pill_w, h = pill_h }, { flex(0), num, flex(0) }))
    layers[#layers + 1] = { widget = pill, x = floor((sw - pill_w) / 2), y = y + ph - pill_h - px(10) }
    -- Free what is no longer on screen, and ask for what is missing.
    thumb(page, page.focus, pw, ph)
    prune(page)
    schedule(page)
    return BoardUI.overlay(sw, h, layers)
end

local function build(page, sw, sh)
    -- The previews' scaled copies from the last build.
    Picture.release(page)
    BoardMetrics.refresh()
    local mx = MenuUI.mx()
    page.mx = mx
    local w = sw - 2 * mx
    local top = px(8)
    local more = iconButton("ellipsis", { kind = "menu" })
    local close = iconButton("x", { kind = "close" })
    local header = hstack({ w = w, h = px(52) }, { more, flex(px(8)), tabBar(page, w - 2 * px(44) - 2 * px(10)), flex(px(8)), close })
    local footer = foot(page, w)
    local rule_top = BoardUI.rect(sw, math.max(1, px(1)), INK.gc)
    local rule_bottom = BoardUI.rect(sw, math.max(1, px(1)), INK.gc)
    page.carousel_top = top + hOf(header) + px(10) + math.max(1, px(1)) + px(12)
    local mid_h = sh - top - hOf(header) - px(10) - hOf(rule_top) - px(12) - px(12) - hOf(rule_bottom) - px(8) - hOf(footer) - px(10)
    return vstack({ w = sw, h = sh }, {
        space(nil, top),
        hstack({ w = sw }, { space(mx, 1), header, space(mx, 1) }),
        space(nil, px(10)),
        rule_top,
        space(nil, px(12)),
        carousel(page, sw, mid_h),
        space(nil, px(12)),
        rule_bottom,
        space(nil, px(8)),
        hstack({ w = sw }, { space(mx, 1), footer, space(mx, 1) }),
        flex(0),
    })
end

-- ---------------------------------------------------------------- actions
local function setFocus(page, n)
    n = math.max(1, math.min(page.total, n))
    if n == page.focus then return end
    page.focus = n
    page:refresh(Device:hasEinkScreen() and "partial" or "ui")
end

local function goTo(ui, n)
    pcall(function() ui.link:addCurrentLocationToStack() end)
    ui:handleEvent(Event:new("GotoPage", n))
end

-- Closes the browser, then runs fn (another screen opens in its place).
local function handOff(page, fn)
    page:close()
    UIManager:nextTick(function()
        local ok, err = pcall(fn)
        if not ok then require("logger").warn("Aleph: page browser action failed:", err) end
    end)
end

local function chapterStep(ui, n, dir)
    local target
    pcall(function()
        if dir < 0 then target = ui.toc:getPreviousChapter(n) else target = ui.toc:getNextChapter(n) end
    end)
    return tonumber(target)
end

local function openTab(page, id)
    local ui = page.ui
    if id == "pages" then return end
    handOff(page, function()
        if id == "aa" then
            -- KOReader's own style menu, not Aleph's reader menu.
            require("aleph_reader_sheet").nativeMenu(ui)
        elseif id == "bookmarks" or id == "highlights" then
            local ok = pcall(function()
                require("aleph_bookmarks").open(ui.bookmark, function() ui.bookmark:onShowBookmark() end,
                    { kind = id == "bookmarks" and "bookmark" or "highlight" })
            end)
            if not ok then ui.bookmark:onShowBookmark() end
        elseif id == "toc" then
            ui.toc:onShowToc()
        elseif id == "pins" then
            require("aleph_pins").openList(ui)
        end
    end)
end

-- ⋮: the rest of the book's tools, as a sheet over the browser. Each closes
-- the browser and opens its screen.
function PageBrowser.openMore(page)
    local ui = page.ui
    local SheetUI = require("aleph_sheet_ui")
    local rows = {
        { icon = "file-text", label = _("Go to page…"), sub = _("Type a page number"), run = function() ui:handleEvent(Event:new("ShowGotoDialog")) end },
        { icon = "book-open-text", label = _("This book"), sub = _("Its page in Aleph"), run = function() require("aleph_topbar_book").showDetails(ui) end },
        { icon = "layout-grid", label = _("Aleph"), sub = _("Home, library and settings"), run = function()
            local board = ui.aleph or require("pluginloader"):getPluginInstance("aleph")
            if board then board:onShowAleph() end
        end },
        { icon = "menu", label = _("KOReader menu"), sub = _("All of KOReader's settings and tools"), run = function() ui.menu:onShowMenu() end },
    }
    return SheetUI.open{
        name = "aleph_page_browser_more",
        build = function(sheet, sw, sh)
            return SheetUI.sheet(sheet, sw, sh, function(w)
                local iw = MenuUI.rowsIn(w)
                local list = {}
                for i, r in ipairs(rows) do
                    list[#list + 1] = MenuUI.row(iw, { icon = r.icon, label = r.label, sub = r.sub, chevron = true, h = 60, action = { kind = "run", index = i } })
                end
                return { SheetUI.titleRow(w, _("More"), nil), MenuUI.group(w, list) }
            end, { pop_w = 460 })
        end,
        on_action = function(sheet, action)
            if action.kind == "run" and rows[action.index] then
                sheet:close()
                handOff(page, rows[action.index].run)
            end
            return true
        end,
    }
end

function PageBrowser.open(ui)
    if not ui or not ui.document then return nil end
    local total = pageCount(ui)
    local page
    page = MenuPage:new{
        name = "aleph_page_browser",
        ui = ui,
        total = total,
        focus = math.max(1, math.min(total, currentPage(ui))),
        thumbs = {},
        build = build,
        on_action = function(p, action)
            local k = action.kind
            if k == "focus" then setFocus(p, p.focus + action.delta)
            elseif k == "step" then setFocus(p, p.focus + action.delta)
            elseif k == "open" then
                local n = p.focus
                p:close()
                if n ~= currentPage(ui) then UIManager:nextTick(function() goTo(ui, n) end) end
            elseif k == "slider" then
                local tap, span = p.last_tap, p.slider_span
                if tap and span then setFocus(p, PageBrowser.pageAt(tap.x, span.x0, span.w, p.total)) end
            elseif k == "tab" then openTab(p, action.id)
            elseif k == "menu" then PageBrowser.openMore(p)
            elseif k == "grid" then
                handOff(p, function()
                    if ui.thumbnail and ui.thumbnail.onShowPageBrowser then ui.thumbnail:onShowPageBrowser()
                    else ui:handleEvent(Event:new("ShowPageBrowser")) end
                end)
            elseif k == "search" then
                handOff(p, function() ui.search:onShowFulltextSearchInput() end)
            end
            return true
        end,
        on_hold = function(p, action)
            if action.kind == "step" then
                local target = chapterStep(ui, p.focus, action.delta)
                if target then setFocus(p, target) end
                return true
            end
        end,
        on_swipe = function(p, ges)
            if ges.direction == "west" then setFocus(p, p.focus + 1) return true end
            if ges.direction == "east" then setFocus(p, p.focus - 1) return true end
            if ges.direction == "south" then p:close() return true end
            return false
        end,
        on_page_key = function(p, delta) setFocus(p, p.focus + delta) end,
        on_close = function(p) PageBrowser.releaseThumbs(p); Picture.collectSoon() end,
    }
    UIManager:show(page, "ui")
    return page
end

-- ----------------------------------------------------------- the opening
local function swipeWanted()
    local stored = G_reader_settings:readSetting("aleph")
    return not (type(stored) == "table" and stored.page_browser_swipe == false)
end
PageBrowser.swipeWanted = swipeWanted

-- ZenOS's primary intercept: KOReader's own bottom swipe handler opens the
-- page browser on a swipe up, whatever order the touch zones end up in (the
-- zone below alone lost to KOReader's style menu on the Kindle).
function PageBrowser.install()
    local ok, ReaderConfig = pcall(require, "apps/reader/modules/readerconfig")
    if not ok or type(ReaderConfig) ~= "table" or ReaderConfig._aleph_page_browser then return end
    ReaderConfig._aleph_page_browser = true
    local original = ReaderConfig.onSwipeShowConfigMenu
    ReaderConfig.onSwipeShowConfigMenu = function(self, ges)
        if swipeWanted() and ges and ges.direction == "north" and self.ui and self.ui.document then
            local shown = pcall(PageBrowser.open, self.ui)
            if shown then return true end
        end
        if original then return original(self, ges) end
    end
end

-- ZenOS's bottom swipe zone: the lowest seventh of the screen, a swipe up,
-- winning over KOReader's own bottom swipes (its reading settings and page
-- turns) while it is on.
function PageBrowser.registerZone(ui)
    if not ui or not ui.registerTouchZones then return end
    ui:registerTouchZones({
        {
            id = "aleph_page_browser_swipe",
            ges = "swipe",
            screen_zone = { ratio_x = 0, ratio_y = 0.86, ratio_w = 1, ratio_h = 0.14 },
            overrides = { "readerconfigmenu_swipe", "readerconfigmenu_ext_swipe", "paging_swipe", "rolling_swipe" },
            handler = function(ges)
                if not swipeWanted() or not ges or ges.direction ~= "north" then return end
                PageBrowser.open(ui)
                return true
            end,
        },
    })
end

return PageBrowser
