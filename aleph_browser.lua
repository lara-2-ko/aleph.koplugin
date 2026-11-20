local InputContainer = require("ui/widget/container/inputcontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local GestureRange = require("ui/gesturerange")
local Geom = require("ui/geometry")
local Device = require("device")
local UIManager = require("ui/uimanager")
local Event = require("ui/event")
local UI = require("aleph_board_ui")
local Metrics = require("aleph_board_metrics")
local Layout = require("aleph_board_layout")
local Store = require("aleph_board_store")
local Data = require("aleph_board_data")
local Local = require("aleph_local")
local LV = require("aleph_library_view")
local ListData = require("aleph_list_data")
local datetime = require("datetime")
local try = require("aleph_try").call
local CoverJob = require("aleph_cover_job")
local KeyNav = require("aleph_keynav")
local T = require("ffi/util").template
local _ = require("aleph_gettext")
local px = Metrics.px
local function stack(o, items)
    if o.gap then
        local spaced = {}
        for _i, item in ipairs(items) do
            if item then
                if #spaced > 0 then spaced[#spaced + 1] = UI.space(nil, o.gap) end
                spaced[#spaced + 1] = item
            end
        end
        items = spaced
    end
    return UI.vstack(o, items)
end
local Browser = InputContainer:extend{ covers_fullscreen = true }
-- The direction keys, on devices that have them (aleph_keynav.lua): a mark
-- moved between everything that can be tapped, Press to tap it.
KeyNav.install(Browser)
function Browser:paintTo(bb, x, y)
    InputContainer.paintTo(self, bb, x, y)
    KeyNav.paint(self, bb)
end
-- Nothing further left or right of the mark: the page is turned.
function Browser:navEdge(dx)
    if dx ~= 0 then self:boardFlip(dx) end
end
require("aleph_board_host").install(Browser)

function Browser:init()
    self.local_library = Local.new(self.settings, self.plugin.ui)
    self.current_context = { board_page = 1, dashboard = self.local_library:dashboard() }
    self.mode, self.page, self.params = "home", 1, {}
    self.cover_queue, self.cover_pending, self.cover_prefetch = {}, {}, {}
    -- The page-turn keys (a Kobo Libra's or a Kindle Oasis's buttons, or a
    -- keyboard's): KOReader names them in its key groups (RPgFwd, LPgFwd...);
    -- "PageForward" was no key's name, so the buttons did nothing here.
    local keys = Device.input and Device.input.group or {}
    self.key_events = { Back = { { "Back" } },
        Next = { { keys.PgFwd or { "RPgFwd", "LPgFwd" } } }, Prev = { { keys.PgBack or { "RPgBack", "LPgBack" } } } }
    self.ges_events = { Swipe = { GestureRange:new{ ges = "swipe", range = function() return self.dimen end } } }
    KeyNav.keys(self)
    self.show_dashboard_menu = function() self:showMenu() end
    self:updateItems()
    -- Redraws the header (clock, battery) when the board is the screen on top:
    -- only the status corner, unless the page shows the time elsewhere.
    self.status_refresh = function()
        if self.closed or not self:statusVisible() then return end
        if not self:refreshStatusOnly() then self:updateItems() end
    end
    -- Each minute: the clock in the header and the clock widgets are drawn
    -- again in place and only their rectangles refreshed; the whole page is
    -- built again on the hour (greeting, date, reading buddy) or when that
    -- cannot be done.
    self.clock_task = function()
        self._clock_armed = false
        if self.closed then return end
        if self:statusVisible() then
            if self:needsFullTick() or not self:refreshStatusOnly() or not self:refreshMinuteTiles() then self:updateItems() end
        end
        self:armClock()
    end
    self:armClock()
    -- Covers made in the background (aleph_cover_job.lua) are heard of here,
    -- also those a Home closed earlier had asked for.
    self.cover_listener = function(event, items) self:coversArrived(event, items) end
    CoverJob.listen(self.cover_listener)
end
-- The minute tick, set for the next minute unless it is already. It stops
-- while the device sleeps (onSuspend) and starts again on waking; any
-- redraw of the page sets it again too, should a wake-up go unheard.
function Browser:armClock()
    if self.closed or self._clock_armed or not self.clock_task then return end
    self._clock_armed = true
    UIManager:scheduleIn(60 - os.time() % 60 + 1, self.clock_task)
end
function Browser:onSuspend()
    if self.clock_task then UIManager:unschedule(self.clock_task) end
    self._clock_armed = false
end
function Browser:onResume()
    if self.closed or not self.clock_task then return end
    -- Soon after waking (the clock on screen is the one from before the
    -- sleep), then each minute again.
    UIManager:unschedule(self.clock_task)
    self._clock_armed = true
    UIManager:scheduleIn(2, self.clock_task)
end
-- Whether the board's own header is what is on screen.
function Browser:statusVisible()
    local top = UIManager.getTopmostVisibleWidget and UIManager:getTopmostVisibleWidget()
    return (self.mode == "home" and not self.board_edit or self.mode == "library" and not self.library_sheet) and (not top or top == self)
end
-- A new hour (the greeting, the reading buddy, the date at midnight): the
-- whole page is built again.
function Browser:needsFullTick()
    return os.date("%Y%m%d%H") ~= self._built_hour
end
-- The clock widgets on Home drawn again in place (aleph_board_host.lua);
-- false when the page must be rebuilt instead.
function Browser:refreshMinuteTiles()
    if self.mode ~= "home" then return true end
    local ok, rects = pcall(self.boardRefreshMinuteTiles, self)
    if not ok then require("logger").warn("Aleph: clock widgets not redrawn in place:", rects) return false end
    if not rects then return false end
    for _i, rect in ipairs(rects) do UIManager:setDirty(self, "ui", rect, true) end
    return true
end
-- The clock and battery redrawn in place; false when the page must be rebuilt.
function Browser:refreshStatusOnly()
    local clock = datetime.secondsToHour(os.time(), G_reader_settings:isTrue("twelve_hour_clock"))
    local ok, rect = pcall(UI.refreshStatus, clock)
    if not ok or not rect then return false end
    UIManager:setDirty(self, function() return "ui", rect end)
    return true
end
function Browser:persistSetting(key, value)
    self.settings[key] = value
    G_reader_settings:saveSetting("aleph", self.settings)
    -- Written out now, so a restart or a power-off cannot lose it.
    if key == "open_home" then G_reader_settings:flush() end
end
function Browser:dashboardMode() return self.mode == "home" end
function Browser:menuChromeHeight() return 0, 0 end
function Browser:isOnDevice(book) return book and book.path ~= nil end
function Browser:onDeviceCount() return #self.local_library.books end
function Browser:boardBookMd5(book) return book and book.md5 end
function Browser:getCurrentDownloadDir() return self.settings.library_roots[1] end
function Browser:thumbnailDisplay(book)
    if not book then return nil, "missing" end
    local canonical = self.by_id and self.by_id[book.id] or book
    if canonical.cover_path then return canonical.cover_path, "ready" end
    -- Decode covers only when drawn, not for every book in every dashboard shelf.
    return nil, "missing"
end
-- Covers on screen are extracted first. `prefetch` marks covers that are not
-- drawn yet (the library's next page), extracted only when nothing visible waits.
function Browser:prepareCover(book, prefetch)
    local b = self.by_id[book.id] or book
    -- A cover whose file could not be read when it was last drawn: if the
    -- file is gone (the cache was cleared), the cover is made again.
    if b.cover_path and UI.coverFailed(b.cover_path)
            and not require("libs/libkoreader-lfs").attributes(b.cover_path, "mode") then
        b.cover_path, b.cover_checked = nil, nil
        self._cover_epoch = (self._cover_epoch or 0) + 1
    end
    book.cover_path = b.cover_path
    if not b.cover_path and not b.cover_checked then
        local state = self.cover_pending[b.id]
        if not state or (state == "prefetch" and not prefetch) then
            self.cover_pending[b.id] = prefetch and "prefetch" or "visible"
            local queue = prefetch and self.cover_prefetch or self.cover_queue
            queue[#queue + 1] = b
        end
    end
    return book
end
-- What Home's lists of books were made from: it changes when a cover
-- arrives or the library's entries change (aleph_board_data.lua keeps the
-- lists while it stays the same).
function Browser:boardEpoch()
    return (self._cover_epoch or 0) .. ":" .. (self.local_library.revision or 0)
end
-- Show covers as they arrive (at most every other second) instead of
-- waiting for the whole queue; prefetched covers never trigger a redraw.
function Browser:showNewCovers(last)
    local now = os.time()
    if self.cover_dirty and (last or now - (self.cover_painted or 0) >= 2) then
        self.cover_dirty = false; self.cover_painted = now
        self:updateItems()
    end
end
-- Covers from the background process: "progress" as they arrive, "done"
-- when the batch is over (the books still without one have none).
function Browser:coversArrived(event, items)
    if self.closed then return end
    self._cover_epoch = (self._cover_epoch or 0) + 1
    for _i, it in ipairs(items or {}) do
        if it.done or event == "done" then
            if it.visible ~= false and not it.shown then it.shown = true; self.cover_dirty = true end
            if event == "done" and it.book then self.cover_pending[it.book.id] = nil end
        end
    end
    self:showNewCovers(event == "done" and #self.cover_queue == 0)
    if event == "done" then self:queueCovers() end
end
-- How many books are handed to the background process at a time.
local COVER_BATCH = 6
-- delay: seconds before the next look (0.02 unless said).
function Browser:queueCovers(delay)
    if self.cover_task or self.closed or (#self.cover_queue == 0 and (#self.cover_prefetch == 0 or self.mode == "detail")) then return end
    self._cover_delay = delay
    self.cover_task = function()
        self.cover_task = nil
        if self.closed then return end
        local lib = self.local_library
        local visible = #self.cover_queue > 0
        local queue = visible and self.cover_queue or self.cover_prefetch
        -- While a batch is being made, books that need one wait for it to
        -- end (coversArrived comes back here then).
        local busy = CoverJob.busy()
        -- Covers that take no work (a saved thumbnail, a custom cover) are
        -- taken now; books that must be opened for theirs go to the batch.
        -- Covers not on screen yet go a few at a time, so one that comes on
        -- screen meanwhile does not wait long behind them.
        local batch, waiting = {}, {}
        local limit = visible and COVER_BATCH or 2
        local reader = self.plugin and self.plugin.ui
        local open_file = reader and reader.document and reader.document.file
        while #queue > 0 and #batch < limit do
            local b = table.remove(queue, 1)
            local waits = false
            if not b.cover_path and not b.cover_checked then
                local ok, path, target, th = pcall(lib.coverQuick, lib, b)
                if ok and not path and target and b.path == open_file then
                    -- The book open in the reader: its cover is taken from
                    -- the document as it is open here, not by another process.
                    ok, path = pcall(lib.cover, lib, b)
                    target = nil
                end
                if ok and not path and target then
                    if busy then waiting[#waiting + 1] = b
                    else batch[#batch + 1] = { book = b, path = b.path, target = target, th = th, visible = visible } end
                    waits = true
                else
                    if not (ok and path) then b.cover_checked = true end
                    self._cover_epoch = (self._cover_epoch or 0) + 1
                    if visible then self.cover_dirty = true end
                end
            end
            if not waits then self.cover_pending[b.id] = nil end
        end
        if busy then
            for i = #waiting, 1, -1 do table.insert(queue, 1, waiting[i]) end
            self:showNewCovers(false)
            return
        end
        local started, why = true, nil
        if #batch > 0 then started, why = CoverJob.start(batch, self.cover_listener) end
        local wait
        if not started and (why == "failed" or why == "low memory") then
            -- Aleph modification, 2026-11-18: the background process could
            -- not start this time: the books wait, and it is tried again in
            -- half a minute (never made here, the screen waiting, meanwhile).
            for i = #batch, 1, -1 do table.insert(queue, 1, batch[i].book) end
            wait = 30
        elseif not started then
            -- No background processes on this device: one cover is made here
            -- (the screen waits for it), the others go back in the queue, and
            -- the next waits half a second so the screen still answers.
            for i = #batch, 2, -1 do table.insert(queue, 1, batch[i].book) end
            local it = batch[1]
            it.book.cover_checked = true
            local t0 = os.time()
            local ok, made = pcall(Local.extractCover, it.path, it.target, it.th)
            if ok and made then it.book.cover_path = it.target end
            if os.time() - t0 >= 2 then
                require("logger").warn("Aleph: covers: made in KOReader's process in", os.time() - t0, "s:", tostring(it.path))
            end
            self._cover_epoch = (self._cover_epoch or 0) + 1
            self.cover_pending[it.book.id] = nil
            if visible then self.cover_dirty = true end
            wait = 0.5
        end
        self:showNewCovers(#self.cover_queue == 0 and not CoverJob.busy())
        self:queueCovers(wait)
    end
    UIManager:scheduleIn(self._cover_delay or 0.02, self.cover_task)
    self._cover_delay = nil
end
function Browser:cover(book, w, h)
    self:prepareCover(book)
    return UI.cover(book, w, h, { path = book.cover_path })
end
function Browser:updateItems()
    if self.closed then return end
    self._built_hour = os.date("%Y%m%d%H")
    Metrics.setUserScale(self.settings.ui_scale or 1)
    local m = Metrics.refresh()
    self.dimen = Geom:new{ x = 0, y = 0, w = m.w, h = m.h }; self.inner_dimen = self.dimen
    -- The lookup of every book by its id, made again only when the library's
    -- entries changed (it was made on every redraw: every tap).
    local lib = self.local_library
    if not self.by_id or self._by_id_books ~= lib.books or self._by_id_rev ~= lib.revision or self._by_id_count ~= #lib.books then
        self.by_id = {}; self.on_device = {}
        for _i, b in ipairs(lib.books) do self.by_id[b.id] = b; self.on_device[b.id] = b.path end
        self._by_id_books, self._by_id_rev, self._by_id_count = lib.books, lib.revision, #lib.books
    end
    self:armClock()
    local screen
    if self.mode == "home" then
        local g = Layout.geometry(px, m.w, m.h, m.LW)
        self._board_geometry = g
        local d = Data.build(self, self.current_context)
        local state = Store.read(self.settings)
        local ctx = { d = d, tiles = state.tiles, colour = state.colour, menu = self, tap_resumes = true }
        self._board_ctx = ctx
        -- Dashboard shelves draw at most a few covers each; schedule those only.
        for i = 1, math.min(4, #d.continue_reading) do self:prepareCover(d.continue_reading[i]) end
        for _i, shelf in pairs(d.shelves) do
            for i = 1, math.min(4, #shelf) do self:prepareCover(shelf[i]) end
        end
        screen = self:boardBuildScreen(ctx, g, self:boardPage(), m.w, m.h)
        if self.board_edit and self.board_edit.sheet then
            local sheet = self:boardRegion(function() return self:boardSheet(ctx, g, m.w, m.h) end, { kind = "noop" })
            local sh = sheet:getSize().h
            screen = UI.overlay(m.w, m.h, { { widget = screen },
                { widget = self:boardRegion(function() return UI.space(m.w, m.h - sh) end, { kind = "sheet-close" }) },
                { widget = sheet, x = 0, y = m.h - sh } })
        end
    elseif self.mode == "detail" then screen = self:buildDetail(m)
    else screen = self:buildLibrary(m) end
    local old = self[1]
    self[1] = FrameContainer:new{ margin = 0, padding = 0, bordersize = 0, background = Metrics.INK.white, screen }
    if old then old:free() end
    UIManager:setDirty(self, "ui", nil, true)
    self:queueCovers()
end

function Browser:button(label, action, w, dark)
    return self:boardRegion(function()
        return UI.box({ w = w, h = px(38), radius = px(18), bg = dark and Metrics.INK.black or Metrics.INK.white,
            border = px(1), border_col = Metrics.INK.g8 },
            UI.hstack({ w = w, h = px(38) }, { UI.flex(0), UI.text(label, { s = 14, b = true, col = dark and Metrics.INK.white or Metrics.INK.black }), UI.flex(0) }))
    end, action)
end
function Browser:header(title, subtitle, w)
    return stack({ w = w, gap = px(8) }, {
        UI.hstack({ w = w, gap = px(10) }, {
            self:button("‹", { kind = "back" }, px(40)),
            stack({ w = w - px(150) }, { UI.text(title, { s = 22, b = true, w = w - px(150), data = true }),
                UI.text(subtitle or "", { s = 12, col = Metrics.INK.g5, w = w - px(150), data = true }) }),
            self:button("☰", { kind = "menu" }, px(60)),
        }),
    })
end
-- ------------------------------------------------------------- the library
-- BookOrbit's list page, drawn from local books: header with the device
-- status, a Sort / Filter / Collection toolbar with the List / Grid switch, the
-- books, an A-Z thumb index and a pager that opens Jump.
local SORTS = { "title", "author", "series", "recently_added", "last_read" }
local SORT_LABELS = { _("Title"), _("Author"), _("Series"), _("Added"), _.pgettext("Sort by", "Read") }
local TIME_SORTS = { recently_added = true, last_read = true }
-- Aleph modification, 2026-11-18: with Reading shown, Progress is a sort
-- too (furthest along first, or the other way).
local DESC_FIRST = { recently_added = true, last_read = true, progress = true }
local function sortsFor(read_status)
    if read_status ~= "reading" then return SORTS, SORT_LABELS end
    local ids, labels = {}, {}
    for i, id in ipairs(SORTS) do ids[i], labels[i] = id, SORT_LABELS[i] end
    ids[#ids + 1], labels[#labels + 1] = "progress", _("Progress")
    return ids, labels
end
local STATUSES = { "all", "unread", "reading", "read", "on_hold" }
local STATUS_LABELS = { _("All"), _("Unread"), _("Reading"), _("Finished"), _("On hold") }
local STATUS_SHORT = { unread = _("Unread"), reading = _("Reading"), read = _("Finished"), on_hold = _("On hold") }
-- Settings that carry the library's sort and filters from one visit to the next.
local SAVED = { sort = "library_sort", order = "library_order", read_status = "library_status",
    collection = "library_collection", genre = "library_genre", format = "library_format",
    language = "library_language", pages = "library_pages", released = "library_released" }
-- The filters besides reading status, in the order the sheet shows them.
local FILTER_KEYS = { "collection", "genre", "format", "language", "pages", "released" }

-- A list of one author, series, search or shelf is its own list: it neither
-- takes the saved filters nor saves the ones set on it.
local function isScoped(params)
    return params.search or params.author or params.series or params.ids or params.genre
end
-- Language, Pages and Released are offered only once the extra filters are
-- turned on (Settings > Library): they need each book's details read.
local EXTRA_FILTERS = { language = true, pages = true, released = true }
function Browser:extraFilters() return self.settings.extra_filters == true end
function Browser:savedLibraryParams()
    local p = {}
    for key, setting in pairs(SAVED) do
        if not EXTRA_FILTERS[key] or self:extraFilters() then p[key] = self.settings[setting] or nil end
    end
    return p
end
-- The extra filters turned off: none of them stays set.
function Browser:dropExtraFilters()
    for key in pairs(EXTRA_FILTERS) do
        self.params[key] = nil
        self.settings[SAVED[key]] = false
    end
    G_reader_settings:saveSetting("aleph", self.settings)
end
function Browser:saveLibraryParams(params)
    for key, setting in pairs(SAVED) do self.settings[setting] = params[key] or false end
    G_reader_settings:saveSetting("aleph", self.settings)
end
function Browser:sortLabel(params)
    local sort, order = params.sort or "title", params.order
    if sort == "title" then return order == "desc" and _("Title Z–A") or _("Title A–Z") end
    if sort == "author" then return order == "desc" and _("Author Z–A") or _("Author A–Z") end
    if sort == "author_last" then return order == "desc" and _("Last name Z–A") or _("Last name A–Z") end
    if sort == "series" then return order == "desc" and _("Series, last first") or _("Series order") end
    if sort == "recently_added" then return order == "asc" and _("Added (oldest)") or _("Recently added") end
    if sort == "last_read" or sort == "recently_read" then return order == "asc" and _("Read (oldest)") or _("Last read") end
    return order == "asc" and _("Least read first") or _("Most read first")
end
function Browser:libraryGroupOf(params)
    local sort = params.sort or "title"
    if sort == "author" then return function(b) return ListData.letterOf(b.authors and b.authors[1] or "") end, true, true end
    if sort == "author_last" then
        return function(b) return ListData.letterOf(Local.surnameOf(b.authors and b.authors[1] or "")) end, true, true
    end
    if sort == "series" then return function(b) return ListData.letterOf(b.series or b.title) end, true, false end
    if sort == "recently_added" then
        return function(b) return require("aleph_dates").shortMonth(b.added or 0) end, false, false, 52
    elseif sort == "last_read" or sort == "recently_read" then
        local now = os.time()
        return function(b)
            if not b.last_open or b.last_open <= 0 then return "" end
            local days = math.floor((os.time{ year = os.date("%Y", now), month = os.date("%m", now), day = os.date("%d", now), hour = 12 }
                - os.time{ year = os.date("%Y", b.last_open), month = os.date("%m", b.last_open), day = os.date("%d", b.last_open), hour = 12 }) / 86400 + 0.5)
            if days < 1 then return _("Today") end
            if days < 7 then return require("aleph_dates").shortWeekday(b.last_open) end
            return require("aleph_dates").shortMonth(b.last_open)
        end, false, false, 52, true
    elseif sort == "progress" then return function() return "" end, false, false, 0 end
    return function(b) return ListData.letterOf(b.title) end, true, true
end
function Browser:collectionLabel(params)
    return params.collection and self.local_library:collectionTitle(params.collection) or _("Whole library")
end
function Browser:libraryEmpty(total_books)
    local p = self.params
    if self.scanning and total_books == 0 then
        return { icon = "book", title = _("Scanning your library…"), body = _("Books appear here as they are found.") }
    end
    if total_books == 0 then
        return { icon = "book", title = _("No books yet"), body = _("Choose the folders that hold your books."),
            action = { label = _("Library folders"), action = { kind = "folders" } } }
    end
    if p.search then return { icon = "search", title = T(_("Nothing matches “%1”"), p.search), body = _("Check the spelling, or try fewer or different words.") } end
    return { icon = "list-filter", title = _("Nothing matches these filters"), body = _("Clear a filter to see more."),
        action = { label = _("Clear filters"), action = { kind = "clear-filters" } } }
end

function Browser:buildLibrary(m)
    if self.index_kind then return self:buildIndexPage(m) end
    local params = self.params
    local books = self.local_library:query(params)
    self.results = books
    local view = self.settings.library_view == "list" and "list" or "grid"
    -- One series has its own page (BookOrbit's series page): the stack of its
    -- covers, how far through it you are, Up next, then the books in order.
    if params.series and not params.search then return self:buildSeriesPage(m, books, view) end
    local groupOf, alpha, rail, gutter, carried = self:libraryGroupOf(params)
    local present = alpha and ListData.bucketsOf(books, groupOf) or nil
    local per = LV.capacity(m.w, m.h, { rail = rail and alpha, view = view })
    self.library_per, self.library_present = per, present
    self.page_count = math.max(1, math.ceil(#books / per)); self.page = math.max(1, math.min(self.page, self.page_count))
    local first = (self.page - 1) * per
    local entries = {}
    for i = first + 1, math.min(#books, first + per) do entries[#entries + 1] = books[i] end
    -- Warm the next page's covers while the reader looks at this one.
    for _i, queued in ipairs(self.cover_prefetch) do
        if self.cover_pending[queued.id] == "prefetch" then self.cover_pending[queued.id] = nil end
    end
    self.cover_prefetch = {}
    for i = self.page * per + 1, math.min(#books, (self.page + 1) * per) do self:prepareCover(books[i], true) end

    local letters = ListData.lettersOf(entries, groupOf)
    local sheet = self.library_sheet
    local status = params.read_status
    local filtered = (status and status ~= "all") or params.genre or params.format or params.language or params.pages or params.released
    local title = self.library_title or _("Library")
    if title == _("Library") and params.collection and not isScoped(params) then title = self.local_library:collectionTitle(params.collection) end
    local sub
    if params.search then sub = T(_("%1 results for “%2”"), #books, params.search)
    else sub = ListData.bookCount(#books) .. " · " .. self:sortLabel(params) end
    local pager = { page = self.page, pages = self.page_count,
        range = alpha and ListData.letterRange(letters) or nil,
        jump = self.page_count > 1 or (alpha and #books > 0) or false }
    local sel = self.select
    if sel then
        title = T(_("%1 selected"), sel.count)
        sub = view == "grid" and _("Tap covers to add or remove") or _("Tap books to add or remove")
    end
    local ctx = {
        screen_w = m.w, screen_h = m.h, marks = false,
        run = function(a, _i, hold)
            if hold then
                if self:collectionHold(a) then return end
                if not self:selectHold(a) then self:boardHoldBook(a) end
            else self:boardRun(a) end
        end,
        env = { thumb = function(book) self:prepareCover(book); return book.cover_path end },
        header = { title = title, title_data = not sel, sub = sub, select = sel and true or nil,
            clock = datetime.secondsToHour(os.time(), G_reader_settings:isTrue("twelve_hour_clock")) },
        toolbar = { view = view, buttons = {
            { icon = "arrow-up-down", label = self:sortLabel(params), action = { kind = "sort-sheet" }, key = "tb-sort" },
            { icon = "list-filter", label = (status and STATUS_SHORT[status]) or (params.genre or params.format or params.language
                or self.local_library.pageBandLabel(params.pages) or self.local_library.decadeLabel(params.released)) or _("All books"),
                on = filtered and true or false, action = { kind = "sort-sheet" }, key = "tb-show" },
            { icon = "library", label = self:collectionLabel(params), on = params.collection ~= nil,
                action = { kind = "sort-sheet", pick = "collection" }, key = "tb-collection" },
        } },
        body = function(f)
            return LV.booksBody({ view = view, entries = entries, rail = rail and alpha, letters = letters, present = present or {},
                groupOf = groupOf, gutter = gutter, first_only = carried, screen_w = m.w, screen_h = m.h,
                select = sel ~= nil, selected = sel and function(b) return sel.ids[b.id] and true or false end,
                action = function(b)
                    if sel then return { kind = "select-toggle", book_id = b.id } end
                    return { kind = "detail", book_id = b.id }
                end,
                empty = #books == 0 and self:libraryEmpty(#self.local_library.books) or nil }, f)
        end,
        pager = pager,
    }
    if sel and sel.sheet then
        ctx.sheet = LV.optionsSheet(self:selectSheetModel())
    elseif sheet then
        if sheet.kind == "jump" then
            ctx.sheet = LV.jumpSheet({ present = present, current = letters, page = self.page, pages = self.page_count })
        else
            local model = self:librarySheetModel(sheet)
            ctx.sheet = model.pick and LV.pickSheet(model) or LV.sortSheet(model)
        end
    end
    local screen = LV.build(ctx)
    return screen
end
-- The series page: header, then a summary (stacked covers, "x of N read", one
-- segment per book, Up next and Continue) over the books in reading order.
function Browser:buildSeriesPage(m, books, view)
    local states, indexes = {}, {}
    local next_book, cur
    local finished, reading = 0, 0
    for i, b in ipairs(books) do
        local st = ListData.stateOf(b)
        states[i] = st == "finished" and "finished" or st == "reading" and "reading" or "unread"
        indexes[i] = b.seriesIndex or i
        if states[i] == "finished" then finished = finished + 1 elseif states[i] == "reading" then reading = reading + 1 end
    end
    for i, b in ipairs(books) do if states[i] == "reading" then next_book, cur = b, i; break end end
    if not next_book then
        for i, b in ipairs(books) do if states[i] ~= "finished" then next_book, cur = b, i; break end end
    end
    local layout = LV.seriesLayout(m.w, m.h, view, #books, false)
    self.page_count = layout.pages
    self.page = math.max(1, math.min(self.page, layout.pages))
    self.library_per, self.library_present = nil, nil
    -- Covers of other pages are not drawn here; drop work queued for them.
    for _i, queued in ipairs(self.cover_prefetch) do
        if self.cover_pending[queued.id] == "prefetch" then self.cover_pending[queued.id] = nil end
    end
    self.cover_prefetch = {}
    local first = self.page == 1 and 1 or (layout.first + (self.page - 2) * layout.rest + 1)
    local last = math.min(#books, self.page == 1 and layout.first or (first + layout.rest - 1))
    local who = books[1] and books[1].authors and books[1].authors[1]
    local sub = who and (who .. " · " .. ListData.bookCount(#books)) or ListData.bookCount(#books)
    -- Holding a book starts a selection, as in the library list; while it
    -- lasts a tap adds or removes a book and the Continue button rests.
    local sel = self.select
    if sel then sub = _("Tap books to add or remove") end
    local sm = {
        entries = books, view = view, screen_w = m.w, screen_h = m.h, local_page = self.page,
        order_label = _("Reading order"),
        states = states, indexes = indexes, current_index = cur, next_book = next_book,
        progress = { count = #books, finished = finished, reading = reading },
        select = sel ~= nil, selected = sel and function(b) return sel.ids[b.id] and true or false end,
        action = function(b)
            if sel then return { kind = "select-toggle", book_id = b.id } end
            return { kind = "detail", book_id = b.id }
        end,
        open_action = function(b)
            if sel then return { kind = "noop" } end
            return { kind = "book", book = b }
        end,
    }
    local ctx = {
        screen_w = m.w, screen_h = m.h, marks = false,
        run = function(a, _i, hold)
            if hold then
                if self:collectionHold(a) then return end
                if not self:selectHold(a) then self:boardHoldBook(a) end
            else self:boardRun(a) end
        end,
        env = { thumb = function(book) self:prepareCover(book); return book.cover_path end },
        header = { title = sel and (T(_("%1 selected"), sel.count)) or (self.library_title or _("Series")), title_data = not sel, sub = sub, select = sel and true or nil,
            clock = datetime.secondsToHour(os.time(), G_reader_settings:isTrue("twelve_hour_clock")) },
        body = function(f) return LV.seriesBody(sm, f) end,
        pager = { page = self.page, pages = layout.pages,
            range = #books > 0 and T(_("Books %1 – %2"), first, last) or nil, jump = false },
    }
    if sel and sel.sheet then ctx.sheet = LV.optionsSheet(self:selectSheetModel()) end
    return LV.build(ctx)
end
-- The sort sheet's model: the sort and filter choices staged in it.
function Browser:librarySheetModel(sheet)
    local s = sheet.staged
    local lib = self.local_library
    if sheet.pick == "collection" then
        local options = { { label = _("Whole library"), value = false, on = s.collection == nil } }
        for _i, c in ipairs(lib:collections()) do options[#options + 1] = { label = c.title .. " (" .. c.count .. ")", value = c.name, on = s.collection == c.name } end
        return { pick = true, title = _("Collection"), options = options, page = sheet.pick_page, empty = _("No collections yet. Create them in the file browser."),
            note = #options > 1 and _("Hold a collection to rename or delete it.") or nil }
    elseif sheet.pick == "genre" then
        local options = { { label = _("Any genre"), value = false, on = s.genre == nil } }
        for _i, g in ipairs(lib:genres()) do options[#options + 1] = { label = g.name .. " (" .. g.count .. ")", value = g.name, on = s.genre == g.name } end
        return { pick = true, title = _("Genre"), options = options, page = sheet.pick_page }
    elseif sheet.pick == "format" then
        local options = { { label = _("Any"), value = false, on = s.format == nil } }
        for _i, f in ipairs(lib:formats()) do options[#options + 1] = { label = f.name .. " (" .. f.count .. ")", value = f.name, on = s.format == f.name } end
        return { pick = true, title = _("Format"), options = options, page = sheet.pick_page }
    elseif sheet.pick == "language" then
        local options = { { label = _("Any language"), value = false, on = s.language == nil } }
        for _i, l in ipairs(lib:languages()) do options[#options + 1] = { label = l.name .. " (" .. l.count .. ")", value = l.name, on = s.language == l.name } end
        return { pick = true, title = _("Language"), options = options, page = sheet.pick_page,
            empty = _("No languages found. They come from each book's metadata.") }
    elseif sheet.pick == "pages" then
        local options = { { label = _("Any length"), value = false, on = s.pages == nil } }
        for _i, band in ipairs(lib:pageBands()) do options[#options + 1] = { label = band.name .. " (" .. band.count .. ")", value = band.id, on = s.pages == band.id } end
        return { pick = true, title = _("Pages"), options = options, page = sheet.pick_page,
            empty = _("No page counts found. They come from a Calibre page-count column, or from KOReader once a book has been opened.") }
    elseif sheet.pick == "released" then
        local options = { { label = _("Any year"), value = false, on = s.released == nil } }
        for _i, d in ipairs(lib:decades()) do options[#options + 1] = { label = d.name .. " (" .. d.count .. ")", value = d.decade, on = s.released == d.decade } end
        return { pick = true, title = _("Released"), options = options, page = sheet.pick_page,
            empty = _("No release dates found. They come from each book's publication date (Calibre's Published column).") }
    end
    local sort_index = 1
    -- Author by last name is Author with "Last name" chosen under it.
    local by_last = s.sort == "author_last"
    local sort_ids, sort_labels = sortsFor(s.read_status)
    for i, id in ipairs(sort_ids) do if id == (by_last and "author" or s.sort or "title") then sort_index = i end end
    local time = TIME_SORTS[s.sort]
    local order_labels = time and { _("Newest"), _("Oldest") } or s.sort == "progress" and { _("Most read"), _("Least read") } or { "A–Z", "Z–A" }
    local status_index = 1
    for i, id in ipairs(STATUSES) do if id == (s.read_status or "all") then status_index = i end end
    local rows = {
        { icon = "library", label = _("Collection"), value = s.collection or _("Whole library"), chevron = true,
            action = { kind = "sheet-open-pick", pick = "collection" }, key = "collection" },
        { icon = "tag", label = _("Genre"), value = s.genre or _("Any"), chevron = true,
            action = { kind = "sheet-open-pick", pick = "genre" }, key = "genre" },
        { icon = "file-text", label = _("Format"), value = s.format or _("Any"), chevron = true,
            action = { kind = "sheet-open-pick", pick = "format" }, key = "format" },
    }
    if self:extraFilters() then
        rows[#rows + 1] = { icon = "globe", label = _("Language"), value = s.language or _("Any"), chevron = true,
            action = { kind = "sheet-open-pick", pick = "language" }, key = "language" }
        rows[#rows + 1] = { icon = "book-open", label = _("Pages"), value = lib.pageBandLabel(s.pages) or _("Any"), chevron = true,
            action = { kind = "sheet-open-pick", pick = "pages" }, key = "pages" }
        rows[#rows + 1] = { icon = "calendar", label = _("Released"), value = lib.decadeLabel(s.released) or _("Any"), chevron = true,
            action = { kind = "sheet-open-pick", pick = "released" }, key = "released" }
    end
    return {
        title = _("Sort and filter"),
        sorts = { labels = sort_labels, selected = sort_index },
        names = (s.sort == "author" or by_last) and { labels = { _("First name"), _("Last name") }, selected = by_last and 2 or 1 } or nil,
        order = { labels = order_labels, selected = s.order and 2 or 1 },
        shows = { labels = STATUS_LABELS, selected = status_index },
        rows = rows,
        note = self.library_scoped and _("For this list only") or _("Saved for the library"),
    }
end
function Browser:libraryOpenSheet(kind, pick)
    if kind == "jump" then self.library_sheet = { kind = "jump" }
    else
        local p = self.params
        local staged = { sort = p.sort or "title", order = p.order, read_status = p.read_status }
        for _i, key in ipairs(FILTER_KEYS) do staged[key] = p[key] end
        self.library_sheet = { kind = "sort", pick = pick, staged = staged }
    end
    self:updateItems()
end
function Browser:libraryApplySheet()
    local sheet = self.library_sheet
    self.library_sheet = nil
    if sheet and sheet.kind == "sort" then
        local s = sheet.staged
        for _i, key in ipairs({ "sort", "order", "read_status" }) do self.params[key] = s[key] end
        for _i, key in ipairs(FILTER_KEYS) do self.params[key] = s[key] end
        if s.read_status == "all" then self.params.read_status = nil end
        self.page = 1
        if not self.library_scoped then self:saveLibraryParams(self.params) end
    end
    self:updateItems()
end
-- Handles the library page's own controls. True when `a` was one of them.
function Browser:libraryRun(a)
    if self.mode ~= "library" then return false end
    local k = a.kind
    local sheet = self.library_sheet
    if k == "sort-sheet" then self:libraryOpenSheet("sort", a.pick)
    elseif k == "jump-sheet" then self:libraryOpenSheet("jump")
    elseif k == "close-sheet" or k == "sheet-done" then
        if sheet then self:libraryApplySheet() end
    elseif k == "sheet-sort" and sheet and sheet.staged then
        sheet.staged.sort = (sortsFor(sheet.staged.read_status))[a.index] or "title"; sheet.staged.order = nil; self:updateItems()
    elseif k == "sheet-names" and sheet and sheet.staged then
        sheet.staged.sort = a.index == 2 and "author_last" or "author"; self:updateItems()
    elseif k == "sheet-order" and sheet and sheet.staged then
        sheet.staged.order = (a.index == 2) and (DESC_FIRST[sheet.staged.sort] and "asc" or "desc") or nil; self:updateItems()
    elseif k == "sheet-show" and sheet and sheet.staged then
        sheet.staged.read_status = STATUSES[a.index]
        -- Progress goes with Reading: another filter goes back to Last read.
        if sheet.staged.sort == "progress" and sheet.staged.read_status ~= "reading" then
            sheet.staged.sort, sheet.staged.order = "last_read", nil
        end
        self:updateItems()
    elseif k == "sheet-open-pick" and sheet then sheet.pick = a.pick; sheet.pick_page = 1; self:updateItems()
    elseif k == "sheet-back" and sheet then sheet.pick = nil; sheet.pick_page = nil; self:updateItems()
    elseif k == "sheet-page" and sheet and sheet.pick then
        sheet.pick_page = math.max(1, (sheet.pick_page or 1) + a.delta); self:updateItems()
    elseif k == "sheet-pick" and sheet and sheet.pick then
        sheet.staged[sheet.pick] = a.value or nil; sheet.pick = nil; sheet.pick_page = nil; self:updateItems()
    elseif k == "sheet-reset" and sheet then
        sheet.staged = { sort = "title" }; sheet.pick = nil; sheet.pick_page = nil; self:updateItems()
    elseif k == "jump-letter" then
        local index = self.library_present and self.library_present[a.letter]
        if index then self.page = ListData.pageOf(index, self.library_per or 1) end
        if a.close then self.library_sheet = nil end
        self:updateItems()
    elseif k == "page-to" then
        self.page = math.max(1, math.min(self.page_count or 1, a.page))
        if a.close then self.library_sheet = nil end
        self:updateItems()
    elseif k == "view" then
        self:persistSetting("library_view", a.view or (self.settings.library_view == "list" and "grid" or "list")); self.page = 1; self:updateItems()
    elseif k == "clear-filters" then
        for _i, key in ipairs(FILTER_KEYS) do self.params[key] = nil end
        self.params.read_status, self.params.search = nil, nil
        if not self.library_scoped then self:saveLibraryParams(self.params) end
        self.page = 1; self:updateItems()
    elseif k == "folders" then self:showSettings("library")
    else return false end
    return true
end
function Browser:buildDetail(m)
    local ok, screen = pcall(function()
        return self:boardRegion(function()
            local page = require("aleph_detail").build(self, m)
            if self.detail_sheet then
                page = LV.withSheet(m.w, m.h, page, LV.optionsSheet(self:detailSheetModel()), function(a, _i, hold) if not hold then self:boardRun(a) end end)
            end
            return page
        end, { kind = "noop" })
    end)
    if ok and screen then return screen end
    require("logger").warn("Aleph: book page failed:", screen)
    return self:buildDetailSimple(m)
end
function Browser:buildDetailSimple(m)
    local b = self.detail_book
    local margin = px(22); local w = m.w - 2 * margin
    local ch = math.min(px(235), math.floor(m.h * 0.31)); local cw = math.floor(ch * 0.67)
    local tw = w - cw - px(20)
    local description = require("util").htmlToPlainTextIfHtml(b.props.description or _("No description in this book's local metadata."))
    return stack({ w = m.w, h = m.h, pad = { margin, margin, margin, margin }, gap = px(18) }, {
        self:header(_("Book"), b.series or b.format, w),
        UI.hstack({ w = w, gap = px(20) }, { self:cover(b, cw, ch),
            stack({ w = tw, gap = px(12) }, { UI.text(b.title, { s = 22, b = true, w = tw, data = true }),
                UI.text(table.concat(b.authors, ", "), { s = 15, w = tw, data = true }),
                UI.text(math.floor(b.progressPercentage) .. "% · " .. b.readStatus, { s = 16, b = true, w = tw }),
                UI.text(b.rating and (b.rating .. " / 5") or _("Not rated"), { s = 13 }),
                self:button(_.pgettext("Open the book", "Read"), { kind = "open", book = b }, math.min(tw, px(200)), true) }) }),
        UI.text((require("aleph_language").name(b.props.language) or "") .. "  ·  " .. b.format .. "  ·  " .. string.format("%.1f MB", b.size / 1048576), { s = 13, w = w }),
        UI.text(description, { s = 15, w = w, lines = math.max(2, math.min(7, math.floor((m.h - ch - px(280)) / Metrics.lh(15)))), data = true }),
        UI.hstack({ w = w, gap = px(10) }, { self:button(_("Book information"), { kind = "info", book = b }, math.floor((w - px(10)) / 2)),
            self:button(_("Highlights"), { kind = "highlights", book = b }, math.floor((w - px(10)) / 2)) }),
        UI.flex(0), UI.text(T(_("On this device · %1"), b.path), { s = 11, w = w, data = true, col = Metrics.INK.g5 }),
    })
end
-- The Read widget: every finished book, apart from the library's saved
-- filters (so the list holds what the percentage counts).
function Browser:loadReadBooks()
    local ids = {}
    for _i, b in ipairs(self.local_library.books or {}) do if b.readStatus == "read" then ids[b.id] = true end end
    self:loadBooks({ read_status = "read", sort = "last_read", ids = ids }, _("Read"))
end
function Browser:loadBooks(params, title, from_index)
    params = params or {}
    self.select = nil
    -- Opened from the Authors or Series list: Back returns to it.
    self.return_to_index = from_index and self.index_kind or nil
    self.index_kind = nil
    self.library_scoped = isScoped(params) and true or false
    -- The plain library comes back as it was left; a list of one author,
    -- series, genre or search starts clean.
    if not self.library_scoped then
        local merged = self:savedLibraryParams()
        for key, value in pairs(params) do merged[key] = value end
        params = merged
    end
    self.mode = "library"; self.params = params; self.page = 1; self.library_title = title or _("Library")
    self.library_sheet = nil; self.select = nil
    self:updateItems()
end
-- Drops cover work that has not started, so opening a page is not stuck
-- behind covers the reader has already left.
function Browser:dropCoverWork()
    for _i, queue in ipairs({ self.cover_queue, self.cover_prefetch }) do
        for _i, b in ipairs(queue) do self.cover_pending[b.id] = nil end
    end
    self.cover_queue, self.cover_prefetch = {}, {}
    if self.cover_task then UIManager:unschedule(self.cover_task); self.cover_task = nil end
end
-- Opens a book's page. `list` ({label, books}) is what the pager walks through;
-- it defaults to the library list the book was opened from.
function Browser:loadBookDetail(id, list)
    local b = self.by_id[id]
    if not b and type(id) == "string" and id:match("^finished%-log:") then return self:showRemovedBook(id) end
    if not b then return end
    if self.mode ~= "detail" then self.detail_from = self.mode end
    if list then self.detail_list = list
    elseif self.mode == "library" then self.detail_list = { label = self.library_title or _("Library"), books = self.results or {} }
    elseif self.mode ~= "detail" then self.detail_list = nil end
    self:dropCoverWork()
    self.library_sheet = nil; self.detail_sheet = nil
    self.detail_book = b; self.mode = "detail"; self:updateItems()
end
-- The warning before a book is deleted, then the deleting (aleph_delete.lua).
function Browser:confirmDelete(b, with_data)
    local Delete = require("aleph_delete")
    if Delete.openInReader(b.path) then
        return self:message(_("This book is open in the reader. Close it first, then delete it here."))
    end
    local text
    if with_data then
        text = T(_("“%1” will be deleted from this device, with everything KOReader keeps about it: highlights, notes, bookmarks, the last page read, its status and rating.\n\nYour reading statistics are kept, and a finished book still counts toward this year.\n\nThis cannot be undone."),
            b.title)
    else
        text = T(_("The file of “%1” will be deleted from this device.\n\nIts highlights, notes, bookmarks, last page, status and rating are kept: put the same file back in the same folder and KOReader finds them again. Your reading statistics are kept, and a finished book still counts toward this year.\n\nThe file itself cannot be brought back."),
            b.title)
    end
    require("aleph_confirm").show{
        title = with_data and _("Delete the book and its data?") or _("Delete the book file?"),
        text = text, ok_label = _("Delete"),
        on_ok = function()
            local ok, why = Delete.run(self.local_library, b, with_data)
            if not ok then
                if why == "open" then return self:message(_("This book is open in the reader. Close it first, then delete it here.")) end
                if why == "missing" then return self:message(_("This book is no longer on this device.")) end
                return self:message(T(_("Could not delete the book.\n%1"), why))
            end
            try(function() require("aleph_toast").show(T(_("Deleted “%1”."), b.title), { icon = "trash" }) end)
            if self.closed then return end
            -- A page opened on its own (from a book's menus) closes with it.
            if self.close_on_back then return self:onClose() end
            -- Back to where the book's page was opened from, without it.
            self.detail_book = nil; self.detail_sheet = nil
            if self.detail_list and self.detail_list.books then
                for i = #self.detail_list.books, 1, -1 do
                    if self.detail_list.books[i].path == b.path then table.remove(self.detail_list.books, i) end
                end
            end
            self.mode = self.detail_from or "library"
            self:refreshData()
        end,
    }
end
-- A finished book whose file was deleted: when it was finished, and a way
-- to take it off the record (aleph_finished_log.lua).
function Browser:showRemovedBook(id)
    local Log = require("aleph_finished_log")
    local T = require("ffi/util").template
    local book
    for _i, b in ipairs(Log.removed(self.local_library.books)) do if b.id == id then book = b end end
    if not book then return end
    local by = book.authors and book.authors[1] and (" · " .. book.authors[1]) or ""
    local y, m, d = book.finishedOn:match("(%d+)-(%d+)-(%d+)")
    local when = y and require("aleph_dates").dayMonthYear(os.time{ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 }) or book.finishedOn
    require("aleph_confirm").show{
        title = book.title .. by,
        text = book.source == "goodreads"
            and T(_("Read on %1, imported from Goodreads.\n\nThis book is not on this device. It counts toward the books you finished that year. Remove it from the record if it should not."), when)
            or T(_("Finished on %1.\n\nThis book is no longer on this device. It still counts toward the books you finished this year. Remove it from the record if it should not."), when),
        cancel_label = _("Close"), ok_label = _("Remove from record"),
        on_ok = function()
            Log.forget(book.key)
            if not self.closed then self:refreshData() end
        end,
    }
end
-- The previous (-1) or next (1) book in the pager's list.
function Browser:detailGo(delta)
    local list = self.detail_list
    if not list or not self.detail_book then return end
    for i, x in ipairs(list.books) do
        if x.id == self.detail_book.id then
            local target = list.books[i + delta]
            local b = target and self.by_id[target.id]
            if b then self:dropCoverWork(); self.detail_sheet = nil; self.detail_book = b; self:updateItems() end
            return
        end
    end
end
-- ------------------------------------------------ selecting several books
-- Holding a book in the library starts a selection; tapping others adds or
-- removes them. The "…" in the header opens a menu to set the reading status
-- of all of them, add them to a collection, or select everything listed.
local STATUS_ROWS = { { "unread", _("Unread"), "bookmark" }, { "reading", _("Reading"), "book-open" }, { "read", _("Finished"), "book-check" }, { "on_hold", _("On hold"), "circle-pause" } }
local STATUS_NAMES = { unread = _("Unread"), reading = _("Reading"), read = _("Finished"), on_hold = _("On hold") }
function Browser:selectedBooks()
    local out = {}
    if not self.select then return out end
    for id in pairs(self.select.ids) do
        local b = self.by_id and self.by_id[id]
        if b then out[#out + 1] = b end
    end
    table.sort(out, function(a, b) return a.title:lower() < b.title:lower() end)
    return out
end
function Browser:selectToggle(id)
    local sel = self.select
    if not sel then return end
    if sel.ids[id] then sel.ids[id] = nil; sel.count = sel.count - 1 else sel.ids[id] = true; sel.count = sel.count + 1 end
    self:updateItems()
end
-- A long press on a book of the library list. True when it was handled.
-- Aleph modification, 2026-11-19: a collection held in the Collection list:
-- Rename or Delete. One that Aleph fills from Calibre's #collections column
-- comes back while Calibre names it: said first, with the choice to go on.
function Browser:collectionHold(a)
    local sheet = self.library_sheet
    if not (a.kind == "sheet-pick" and a.value and sheet and sheet.pick == "collection") then return false end
    local lib = self.local_library
    local name = a.value
    local title = lib:collectionTitle(name)
    local Confirm = require("aleph_confirm")
    if Local.isFavorites(name) then
        self:message(_("Favorites is KOReader's own collection: it cannot be renamed or deleted."))
        return true
    end
    local from_calibre = false
    pcall(function() from_calibre = require("aleph_calibre_collections").fromCalibre(name) end)
    local function done(new_name)
        pcall(function() require("aleph_calibre_collections").forget(name) end)
        if sheet.staged and sheet.staged.collection == name then sheet.staged.collection = new_name end
        local params = self.params
        if params and params.collection == name then params.collection = new_name end
        pcall(function() require("aleph_board_data").invalidateLocal() end)
        self:updateItems()
    end
    local function rename()
        self:input(_("Rename collection"), title, function(new_name)
            new_name = (new_name or ""):gsub("^%s+", ""):gsub("%s+$", "")
            if new_name == "" or new_name == name then return end
            local ok, err = pcall(lib.renameCollection, lib, name, new_name)
            if not ok then return self:message(_("Could not rename the collection.") .. "\n" .. tostring(err)) end
            done(new_name)
        end, _("Rename"))
    end
    local function delete()
        Confirm.show{
            title = T(_("Delete \"%1\"?"), title),
            text = _("The collection goes; its books stay on the device and in the library."),
            ok_label = _("Delete"), cancel_label = _("Cancel"),
            on_ok = function()
                local ok, err = pcall(lib.deleteCollection, lib, name)
                if not ok then return self:message(_("Could not delete the collection.") .. "\n" .. tostring(err)) end
                done(nil)
            end,
        }
    end
    local function menu()
        Confirm.show{
            title = title,
            text = _("Rename this collection or delete it. Deleting it keeps its books."),
            ok_label = _("Rename"), cancel_label = _("Close"),
            extra_label = _("Delete"),
            on_ok = rename, on_extra = delete,
        }
    end
    if from_calibre then
        Confirm.show{
            title = _("This collection comes from Calibre"),
            text = T(_("Aleph fills \"%1\" from Calibre's #collections column. Renamed or deleted here, it comes back with its books the next time Aleph reads Calibre's column (when Home opens), alongside any new name.\n\nTo change it for good, rename it or clear it in Calibre's #collections column and send the books again."), title),
            ok_label = _("Change here anyway"), cancel_label = _("Cancel"),
            on_ok = menu,
        }
    else
        menu()
    end
    return true
end

function Browser:selectHold(a)
    if self.mode ~= "library" or self.index_kind or self.detail_sheet then return false end
    if self.select then
        if a.kind == "select-toggle" then self:selectToggle(a.book_id) end
        return true
    end
    if a.kind == "detail" and a.book_id then
        self.select = { ids = { [a.book_id] = true }, count = 1 }
        self.library_sheet = nil
        self:updateItems()
        return true
    end
    return false
end
function Browser:selectEnd()
    self.select = nil
    self:updateItems()
end
local function booksText(n) return n == 1 and _("1 book") or T(_("%1 books"), n) end
-- What the selection's sheets show. Drawn by LV.optionsSheet.
function Browser:selectSheetModel()
    local sel = self.select
    local sheet = sel.sheet
    local lib = self.local_library
    local books = self:selectedBooks()
    if sheet.kind == "status" then
        local shared
        for i, b in ipairs(books) do
            if i == 1 then shared = b.readStatus elseif shared ~= b.readStatus then shared = nil end
        end
        local rows = {}
        for _i, r in ipairs(STATUS_ROWS) do
            local on = shared == r[1]
            rows[#rows + 1] = { label = r[2], icon = r[3], radio = on, bold = on, action = { kind = "sel-set-status", status = r[1] } }
        end
        return { title = _("Reading status"), sub = booksText(#books), rows = rows }
    elseif sheet.kind == "collections" then
        local counts = lib:collectionCounts(books)
        local rows = {}
        for _i, c in ipairs(lib:collectionList()) do
            local n = counts[c.name] or 0
            rows[#rows + 1] = { label = c.title, icon = "folder-open", toggle = (#books > 0 and n == #books),
                value = (n > 0 and n < #books) and (n .. " of " .. #books) or nil,
                action = { kind = "sel-toggle-collection", name = c.name, all = (#books > 0 and n == #books) } }
        end
        return { title = _("Add to collection"), sub = booksText(#books), rows = rows, page = sheet.page,
            empty = _("No collections yet. Create the first one below."),
            foot = { { label = _("New collection…"), icon = "plus", action = { kind = "sel-new-collection" } } } }
    end
    local total = #(self.results or {})
    local rows = {
        { label = _("Reading status"), icon = "book-open", chevron = true, action = { kind = "sel-status" } },
        { label = _("Add to collection"), icon = "folder-open", chevron = true, action = { kind = "sel-collections" } },
        { label = T(_("Select all (%1)"), total), icon = "list-checks", chevron = true, action = { kind = "sel-all" } },
    }
    return { title = T(_("%1 selected"), sel.count), sub = sel.count == 0 and _("Tap books to add them") or nil, rows = sel.count > 0 and rows or { rows[3] } }
end
local function selectToast(text)
    try(function() require("aleph_toast").show(text) end)
end
-- The selection's own controls. True when `a` was one of them.
function Browser:selectRun(a)
    if self.mode ~= "library" or not self.select then return false end
    local sel = self.select
    local k = a.kind
    local lib = self.local_library
    if k == "select-toggle" then self:selectToggle(a.book_id)
    elseif k == "select-done" then self:selectEnd()
    elseif k == "select-menu" then
        sel.sheet = { kind = "menu" }; self:updateItems()
    elseif sel.sheet and k == "close-sheet" then
        sel.sheet = nil; self:updateItems()
        if self.collections_changed then self.collections_changed = nil; self:refreshData() end
    elseif sel.sheet and k == "noop" then return true
    elseif sel.sheet and k == "sheet-page" then
        sel.sheet.page = math.max(1, (sel.sheet.page or 1) + a.delta); self:updateItems()
    elseif k == "sel-status" then sel.sheet = { kind = "status" }; self:updateItems()
    elseif k == "sel-collections" then sel.sheet = { kind = "collections", page = 1 }; self:updateItems()
    elseif k == "sel-all" then
        sel.ids, sel.count = {}, 0
        for _i, b in ipairs(self.results or {}) do sel.ids[b.id] = true; sel.count = sel.count + 1 end
        sel.sheet = nil; self:updateItems()
    elseif k == "sel-set-status" then
        local books = self:selectedBooks()
        local failed, done = 0, 0
        for _i, b in ipairs(books) do
            local ok = pcall(lib.setStatus, lib, b, a.status, { bulk = true })
            if ok then done = done + 1 else failed = failed + 1 end
        end
        self.select = nil
        self:refreshData()
        if failed > 0 then
            self:message(T(_("Could not save the status for %1."), booksText(failed)))
        else
            selectToast(T(_("%1 set to %2"), booksText(done), STATUS_NAMES[a.status]))
        end
    elseif k == "sel-toggle-collection" then
        local books = self:selectedBooks()
        local ok, err = pcall(lib.setManyInCollection, lib, books, a.name, not a.all)
        if not ok then return self:message(_("Could not change the collection.") .. "\n" .. tostring(err)) or true end
        self.collections_changed = true
        self:updateItems()
    elseif k == "sel-new-collection" then
        self:input(_("New collection"), "", function(name)
            name = (name or ""):gsub("^%s+", ""):gsub("%s+$", "")
            if name == "" then return end
            local ok, err = pcall(function() lib:createCollection(name); lib:setManyInCollection(self:selectedBooks(), name, true) end)
            if not ok then return self:message(_("Could not create the collection.") .. "\n" .. tostring(err)) end
            self.collections_changed = true
            if self.select then self.select.sheet = { kind = "collections", page = 1 } end
            self:updateItems()
        end)
    else return false end
    return true
end
-- Holding a book's cover anywhere opens its page.
function Browser:boardHoldBook(a)
    if self.detail_sheet then return true end
    if a.kind == "detail" and a.book_id then self:loadBookDetail(a.book_id, a.list); return true end
    if (a.kind == "book" or a.kind == "book-actions") and a.book then self:loadBookDetail(a.book.id, a.list); return true end
    return false
end
-- Sets the rating (tapping the current one clears it) and the reading status.
-- Both are written to KOReader's own sidecar for the book.
function Browser:afterBookChange()
    self:refreshData()
end
function Browser:rateBook(b, rating)
    local new = rating
    if b.rating == rating then new = nil end
    local ok, err = pcall(self.local_library.setRating, self.local_library, b, new)
    if not ok then return self:message(_("Could not save the rating.") .. "\n" .. tostring(err)) end
    self:afterBookChange()
end
function Browser:setBookStatus(b, status)
    local ok, err = pcall(self.local_library.setStatus, self.local_library, b, status)
    if not ok then return self:message(_("Could not save the status.") .. "\n" .. tostring(err)) end
    self:afterBookChange()
end
-- What the book page's sheet shows: the reading status, the "…" menu, or the
-- collections the book can be put in. Drawn by LV.optionsSheet.
function Browser:detailSheetModel()
    local sheet, b, lib = self.detail_sheet, self.detail_book, self.local_library
    if sheet.kind == "status" then
        local rows = {}
        for _i, s in ipairs(STATUS_ROWS) do
            local on = b.readStatus == s[1]
            rows[#rows + 1] = { label = s[2], icon = s[3], radio = on, bold = on, action = { kind = "set-status", status = s[1] } }
        end
        return { title = _("Reading status"), sub = b.title, rows = rows }
    elseif sheet.kind == "delete" then
        -- The file only, or the file and everything KOReader keeps about it.
        -- Each asks first.
        return { title = _("Delete book"), sub = b.title, rows = {
            { label = _("Delete book, keep its data"), icon = "trash", chevron = true, action = { kind = "menu-delete", with_data = false } },
            { label = _("Delete book and its data"), icon = "trash", chevron = true, action = { kind = "menu-delete", with_data = true } },
        } }
    elseif sheet.kind == "goodreads-pick" then
        return require("aleph_goodreads_send").sheetModel(sheet, b)
    elseif sheet.kind == "collections" then
        local member = lib:collectionsOf(b)
        local rows = {}
        for _i, c in ipairs(lib:collectionList()) do
            rows[#rows + 1] = { label = c.title, icon = "folder-open", toggle = member[c.name] and true or false, action = { kind = "toggle-collection", name = c.name } }
        end
        return { title = _("Add to collection"), sub = b.title, rows = rows, page = sheet.page,
            empty = _("No collections yet. Create the first one below."),
            foot = { { label = _("New collection…"), icon = "plus", action = { kind = "collection-new" } } } }
    end
    local rows = {
        { label = _("Book information"), icon = "info", chevron = true, action = { kind = "menu-info" } },
        { label = T(_("Highlights (%1)"), #(b.highlights or {})), icon = "highlighter", chevron = true, action = { kind = "menu-highlights" } },
        { label = _("Add to collection"), icon = "folder-open", chevron = true, action = { kind = "menu-collections" } },
    }
    if b.authors and b.authors[1] then
        rows[#rows + 1] = { label = T(_("More by %1"), b.authors[1]), icon = "feather", chevron = true, action = { kind = "menu-author" } }
    end
    -- Goodreads (aleph_goodreads_send.lua; Aleph's own since 1.2.32).
    rows[#rows + 1] = { label = _("Send to Goodreads"), icon = "arrow-up-right", chevron = true, action = { kind = "menu-goodreads" } }
    -- Deleting, last: one entry, which opens the two ways to do it.
    rows[#rows + 1] = { label = _("Delete book"), icon = "trash", chevron = true, action = { kind = "menu-delete-choose" } }
    return { title = b.title, rows = rows }
end
-- The sheet's own actions; true when `a` was handled here.
function Browser:detailRun(a)
    if self.mode ~= "detail" then return false end
    local k = a.kind
    local b = self.detail_book
    local lib = self.local_library
    local function close() self.detail_sheet = nil end
    if k == "status-menu" then self.detail_sheet = { kind = "status" }; self:updateItems()
    elseif k == "detail-menu" then self.detail_sheet = { kind = "menu" }; self:updateItems()
    elseif k == "close-sheet" then
        if self.detail_sheet then
            close()
            if self.collections_changed then self.collections_changed = nil; self:refreshData() else self:updateItems() end
        end
    elseif k == "noop" then return true
    elseif k == "sheet-page" and self.detail_sheet then
        self.detail_sheet.page = math.max(1, (self.detail_sheet.page or 1) + a.delta); self:updateItems()
    elseif k == "set-status" then close(); self:setBookStatus(b, a.status)
    elseif k == "menu-info" then close(); self:updateItems(); self:showBookInformation(b)
    elseif k == "menu-highlights" then close(); self:updateItems(); self:showHighlights(b)
    elseif k == "menu-collections" then self.detail_sheet = { kind = "collections", page = 1 }; self:updateItems()
    elseif k == "menu-author" then
        close(); self:loadBooks({ author = b.authors[1], sort = "title" }, b.authors[1])
    elseif k == "menu-delete-choose" then self.detail_sheet = { kind = "delete" }; self:updateItems()
    elseif k == "menu-goodreads" then
        close(); self:updateItems()
        local ok, err = pcall(function() require("aleph_goodreads_send").start(self, b) end)
        if not ok then self:message(_("Could not send to Goodreads.") .. "\n" .. tostring(err)) end
    elseif k == "gr-pick" and self.detail_sheet and self.detail_sheet.kind == "goodreads-pick" then
        local sheet = self.detail_sheet
        local data = sheet.choices and sheet.choices[a.index]
        close(); self:updateItems()
        if data then sheet.on_pick(data) end
    elseif k == "gr-search" and self.detail_sheet and self.detail_sheet.kind == "goodreads-pick" then
        local sheet = self.detail_sheet
        close(); self:updateItems()
        sheet.on_search()
    elseif k == "menu-delete" then
        close(); self:updateItems(); self:confirmDelete(b, a.with_data)
    elseif k == "toggle-collection" then
        local member = lib:collectionsOf(b)[a.name]
        local ok, err = pcall(lib.setInCollection, lib, b, a.name, not member)
        if not ok then return self:message(_("Could not change the collection.") .. "\n" .. tostring(err)) or true end
        self.collections_changed = true
        self:updateItems()
    elseif k == "collection-new" then
        self:input(_("New collection"), "", function(name)
            name = (name or ""):gsub("^%s+", ""):gsub("%s+$", "")
            if name == "" then return end
            local ok, err = pcall(function() lib:createCollection(name); lib:setInCollection(b, name, true) end)
            if not ok then return self:message(_("Could not create the collection.") .. "\n" .. tostring(err)) end
            self.collections_changed = true
            self.detail_sheet = { kind = "collections", page = 1 }
            self:updateItems()
        end)
    else return false end
    return true
end
-- KOReader's own Book information. It opens the document, so say so first.
function Browser:showBookInformation(b)
    local InfoMessage = require("ui/widget/infomessage")
    local msg = InfoMessage:new{ text = _("Opening book information…") }
    UIManager:show(msg)
    UIManager:scheduleIn(0.15, function()
        local ok, err = pcall(function()
            require("apps/filemanager/filemanagerbookinfo"):new{ ui = self.plugin.ui }:show(b.path, b.props)
        end)
        UIManager:close(msg)
        if not ok then self:message(_("Could not open book information.") .. "\n" .. tostring(err)) end
    end)
end
-- The book's highlights and notes, page by page (aleph_text_pages.lua);
-- KOReader's text viewer if that page cannot be built.
function Browser:showHighlights(b)
    local ok, err = pcall(function() require("aleph_text_pages").highlights(b) end)
    if ok then return end
    require("logger").warn("Aleph: highlights page failed:", err)
    local lines = {}; for _i, h in ipairs(b.highlights or {}) do lines[#lines + 1] = h.text .. (h.note and "\n" .. h.note or "") end
    UIManager:show(require("ui/widget/textviewer"):new{ title = T(_("Highlights · %1"), b.title), text = #lines > 0 and table.concat(lines, "\n\n") or _("No local highlights.") })
end
-- About this book: the whole description, page by page.
function Browser:showAboutBook(b)
    local ok, err = pcall(function() require("aleph_text_pages").about(b) end)
    if not ok then require("logger").warn("Aleph: about page failed:", err) end
end
-- Genres & tags: every genre of the book; a tap lists that genre's books.
function Browser:showGenresSheet(b)
    local ok, err = pcall(function()
        require("aleph_text_pages").tags(b, function(g)
            if not self.closed then self:loadBooks({ genre = g, sort = "title" }, g) end
        end)
    end)
    if not ok then require("logger").warn("Aleph: genres sheet failed:", err); self:loadSection("genres") end
end
-- Highlight of the day: the whole passage in a drawer, the book a tap away.
function Browser:showHighlightOfTheDay(hl)
    local ok, err = pcall(function()
        require("aleph_highlight_sheet").open(hl, function(id)
            if not self.closed then self:loadBookDetail(id) end
        end)
    end)
    if not ok then require("logger").warn("Aleph: highlight drawer failed:", err); self:loadBookDetail(hl.bookId) end
end
function Browser:openBook(b)
    if not require("libs/libkoreader-lfs").attributes(b.path, "mode") then
        return self:message(_("This book is no longer on this device. Refresh the library."))
    end
    self:onClose()
    if self.plugin.ui.document and self.plugin.ui.document.file == b.path then return end
    require("apps/reader/readerui"):showReader(b.path)
end
function Browser:message(text)
    UIManager:show(require("ui/widget/infomessage"):new{ text = text })
end
function Browser:choices(title, entries)
    local Menu = require("ui/widget/menu")
    local menu
    local items = {}
    for _i, e in ipairs(entries) do
        local entry = e
        items[#items + 1] = { text = entry[1], callback = function() UIManager:close(menu); entry[2]() end }
    end
    menu = Menu:new{ title = title, item_table = items, width = Device.screen:getWidth(), is_popout = false, is_borderless = true }
    UIManager:show(menu)
end
-- A text prompt in the Aleph style (aleph_input.lua).
function Browser:input(title, value, callback, ok_label, hint, input_type)
    local ok, err = pcall(function()
        require("aleph_input").prompt{ title = title, text = value, ok_label = ok_label or _("Save"), hint = hint, input_type = input_type, on_ok = callback }
    end)
    if ok then return end
    -- The styled prompt could not be built: KOReader's own.
    require("logger").warn("Aleph: prompt failed:", err)
    local dialog
    dialog = require("ui/widget/inputdialog"):new{ title = title, input = tostring(value or ""), input_type = input_type, buttons = { {
        { text = _("Cancel"), callback = function() UIManager:close(dialog) end },
        { text = _("Save"), is_enter_default = true, callback = function() local v = dialog:getInputText(); UIManager:close(dialog); callback(v) end },
    } } }
    UIManager:show(dialog); dialog:onShowKeyboard()
end
function Browser:promptSearch()
    self:input(_("Search title, author or series"), self.params.search, function(q)
        self:loadBooks({ search = q }, _("Search"))
    end, _("Search"), _("Title, author or series"))
end
-- Lists the genres (Calibre tags) found in the library; `apply` gets the
-- chosen genre, or nil for all genres.
function Browser:pickGenre(apply)
    local entries = { { _("All genres"), function() apply(nil) end } }
    for _i, group in ipairs(self.local_library:genres()) do
        local g = group
        entries[#entries + 1] = { g.name .. " (" .. g.count .. ")", function() apply(g.name) end }
    end
    if #entries == 1 then
        return self:message(_("No genres found. Genres come from each book's tags (EPUB subjects, or a Calibre metadata.opf next to the book). Use Refresh local library to read them."))
    end
    self:choices(_("Genre"), entries)
end
function Browser:loadSection(kind)
    if kind == "genres" then
        return self:pickGenre(function(genre)
            if genre then self:loadBooks({ genre = genre }, genre) else self:loadBooks({}) end
        end)
    end
    if kind ~= "authors" and kind ~= "series" then return self:loadBooks({}) end
    self:loadIndex(kind)
end
-- The Authors and Series lists: BookOrbit's index pages, drawn from the local
-- books, with the A-Z thumb index, Sort and Show controls and a List / Grid switch.
function Browser:loadIndex(kind)
    self.select = nil
    self.mode = "library"; self.index_kind = kind; self.params = {}; self.page = 1
    self.library_title = kind == "authors" and _("Authors") or _("Series")
    self.library_scoped = true; self.library_sheet = nil; self.return_to_index = nil
    self:dropCoverWork()
    self:updateItems()
end
local INDEX_SHOWS = { authors = { _("Everyone"), _("Reading now"), _("Read") }, series = { _("All series"), _("In progress"), _("Finished") } }
local INDEX_FILTERS = { false, "reading", "finished" }
function Browser:indexPrefs(kind)
    local p = (self.settings.index_prefs or {})[kind] or {}
    return p.sort or "name", p.filter
end
function Browser:indexSave(kind, sort, filter)
    local all = {}
    for k, v in pairs(self.settings.index_prefs or {}) do all[k] = v end
    all[kind] = { sort = sort or "name", filter = filter or nil }
    self:persistSetting("index_prefs", all)
end
function Browser:indexSheetModel(sheet)
    local s = sheet.staged
    local by_books = s.sort == "books"
    -- Authors sort by first name or by last name; series by name.
    local sorts
    if self.index_kind == "authors" then
        local by_last = s.sort == "last" or s.sort == "last_desc"
        sorts = { labels = { _("First name"), _("Last name"), _("Most books") }, selected = by_books and 3 or by_last and 2 or 1 }
    else
        sorts = { labels = { _("Name"), _("Most books") }, selected = by_books and 2 or 1 }
    end
    return {
        title = _("Sort and filter"),
        sorts = sorts,
        order = not by_books and { labels = { "A–Z", "Z–A" }, selected = (s.sort == "name_desc" or s.sort == "last_desc") and 2 or 1 } or nil,
        shows = { labels = INDEX_SHOWS[self.index_kind], selected = s.filter == "reading" and 2 or s.filter == "finished" and 3 or 1 },
        rows = {}, note = _("Saved for this list"),
    }
end
function Browser:buildIndexPage(m)
    local kind = self.index_kind
    local sort, filter = self:indexPrefs(kind)
    local all = self.local_library:groupEntries(kind, sort)
    local entries_all = all
    if filter then
        entries_all = {}
        for _i, e in ipairs(all) do
            if filter == "reading" then
                if e.readingCount > 0 then entries_all[#entries_all + 1] = e end
            elseif e.count > 0 and e.finishedCount >= e.count then entries_all[#entries_all + 1] = e end
        end
    end
    local view = self.settings.index_view == "grid" and "grid" or "list"
    local alpha = sort ~= "books"
    local by_last = sort == "last" or sort == "last_desc"
    local groupOf = function(e) return by_last and e.last_letter or e.letter end
    local present = alpha and ListData.bucketsOf(entries_all, groupOf) or nil
    local per = LV.groupsGeometry(m.w, m.h, { rail = alpha, view = view, kind = kind }).per
    self.library_per, self.library_present = per, present
    self.page_count = math.max(1, math.ceil(#entries_all / per)); self.page = math.max(1, math.min(self.page, self.page_count))
    local first = (self.page - 1) * per
    local entries = {}
    for i = first + 1, math.min(#entries_all, first + per) do entries[#entries + 1] = entries_all[i] end
    -- Author portraits (Settings > Author portraits): the ones already
    -- downloaded are shown; the rest of this page are looked up in the background.
    if kind == "authors" then
        local wanted = self.settings.author_portraits == true
        local ok_p, Portraits = pcall(require, "aleph_portraits")
        local missing = {}
        for _i, e in ipairs(entries) do
            e.portrait = (wanted and ok_p) and Portraits.pathFor(e.title) or nil
            if wanted and ok_p and not e.portrait then missing[#missing + 1] = e.title end
        end
        if wanted and ok_p then
            Portraits.setListener(function()
                if not self.closed and self.mode == "library" and self.index_kind == "authors" and not self.library_sheet then self:updateItems() end
            end)
            Portraits.request(missing)
        end
    end
    -- Only the covers on this page are wanted.
    for _i, queued in ipairs(self.cover_prefetch) do
        if self.cover_pending[queued.id] == "prefetch" then self.cover_pending[queued.id] = nil end
    end
    self.cover_prefetch = {}
    local letters = alpha and ListData.lettersOf(entries, groupOf) or {}
    local count = kind == "authors" and ListData.plural(#entries_all, _("%1 author"), _("%1 authors")) or ListData.plural(#entries_all, _("%1 series"), _("%1 series"))
    local order = sort == "books" and _("most books first") or (sort == "name_desc" or sort == "last_desc") and "Z–A" or "A–Z"
    if by_last then order = T(_("by last name, %1"), order) end
    local sort_label = sort == "books" and _("Most books") or sort == "name_desc" and _("Name Z–A") or sort == "last" and _("Last name A–Z")
        or sort == "last_desc" and _("Last name Z–A") or (kind == "authors" and _("First name A–Z") or _("Name A–Z"))
    local show_label = INDEX_SHOWS[kind][filter == "reading" and 2 or filter == "finished" and 3 or 1]
    local empty
    if #entries_all == 0 then
        if filter then
            empty = { icon = kind == "authors" and "feather" or "layers-2", title = _("Nothing matches this filter"), body = _("Show everyone to see more."),
                action = { label = _("Clear filter"), action = { kind = "clear-filters" } } }
        elseif self.scanning and #self.local_library.books == 0 then
            empty = { icon = "book", title = _("Scanning your library…"), body = _("Books appear here as they are found.") }
        else
            empty = kind == "authors" and { icon = "feather", title = _("No authors yet"), body = _("Authors appear here as books with author metadata are added.") }
                or { icon = "layers-2", title = _("No series yet"), body = _("Series appear here as books that belong to one are added.") }
        end
    end
    local sheet = self.library_sheet
    local ctx = {
        screen_w = m.w, screen_h = m.h, marks = false,
        run = function(a, _i, hold) if hold then self:boardHoldBook(a) else self:boardRun(a) end end,
        env = { thumb = function(book) self:prepareCover(book); return book.cover_path end },
        header = { title = self.library_title, sub = count .. " · " .. order,
            clock = datetime.secondsToHour(os.time(), G_reader_settings:isTrue("twelve_hour_clock")) },
        toolbar = { view = view, buttons = {
            { icon = "arrow-up-down", label = sort_label, action = { kind = "sort-sheet" }, key = "tb-sort" },
            { icon = "list-filter", label = show_label, on = filter ~= nil, action = { kind = "sort-sheet" }, key = "tb-show" },
        } },
        body = function(f)
            return LV.groupsBody({ kind = kind, view = view, entries = entries, rail = alpha, letters = letters, present = present or {},
                groupOf = groupOf, gutter = alpha and 34 or 0, screen_w = m.w, screen_h = m.h,
                action = function(e) return { kind = "open-group", entry = e } end, empty = empty }, f)
        end,
        pager = { page = self.page, pages = self.page_count, range = alpha and ListData.letterRange(letters) or nil,
            jump = self.page_count > 1 or (alpha and #entries_all > 0) or false },
    }
    if sheet then
        if sheet.kind == "jump" then
            ctx.sheet = LV.jumpSheet({ present = present, current = letters, page = self.page, pages = self.page_count })
        else ctx.sheet = LV.sortSheet(self:indexSheetModel(sheet)) end
    end
    return LV.build(ctx)
end
-- The Authors / Series list's own controls; the rest (Jump, pages) are the
-- library page's. True when `a` was handled here.
function Browser:indexRun(a)
    local kind = self.index_kind
    if not kind or self.mode ~= "library" then return false end
    local k = a.kind
    local sheet = self.library_sheet
    local sort, filter = self:indexPrefs(kind)
    if k == "sort-sheet" then
        self.library_sheet = { kind = "sort", staged = { sort = sort, filter = filter } }; self:updateItems()
    elseif k == "close-sheet" or k == "sheet-done" then
        if sheet and sheet.kind == "sort" then
            self:indexSave(kind, sheet.staged.sort, sheet.staged.filter); self.page = 1
        end
        self.library_sheet = nil; self:updateItems()
    elseif k == "sheet-sort" and sheet and sheet.staged then
        if kind == "authors" then
            sheet.staged.sort = a.index == 3 and "books" or a.index == 2 and "last" or "name"
        else sheet.staged.sort = a.index == 2 and "books" or "name" end
        self:updateItems()
    elseif k == "sheet-order" and sheet and sheet.staged then
        local last = sheet.staged.sort == "last" or sheet.staged.sort == "last_desc"
        sheet.staged.sort = a.index == 2 and (last and "last_desc" or "name_desc") or (last and "last" or "name"); self:updateItems()
    elseif k == "sheet-show" and sheet and sheet.staged then
        sheet.staged.filter = INDEX_FILTERS[a.index] or nil; self:updateItems()
    elseif k == "sheet-reset" and sheet and sheet.staged then
        sheet.staged = { sort = "name" }; self:updateItems()
    elseif k == "clear-filters" then
        self:indexSave(kind, sort, nil); self.page = 1; self:updateItems()
    elseif k == "view" then
        self:persistSetting("index_view", a.view or (self.settings.index_view == "grid" and "list" or "grid")); self.page = 1; self:updateItems()
    elseif k == "open-group" then
        local name = a.entry.title
        self:loadBooks({ [kind == "authors" and "author" or "series"] = name, sort = kind == "series" and "series" or "title" }, name, true)
    else return false end
    return true
end
function Browser:showMenu()
    local ok, err = pcall(function()
        require("aleph_menu_sheet").open(self, function(page, a) self:menuRun(page, a) end)
    end)
    if not ok then
        require("logger").warn("Aleph: menu failed:", err)
        self:message(_("The menu could not open.") .. "\n" .. tostring(err))
    end
end
-- What the menu sheet's controls do. The sheet closes first, so what they open
-- is drawn over the board and not over the sheet.
function Browser:menuRun(page, a)
    local k = a.kind
    if k == "link" then
        page:close()
        local link = a.link
        if link == "library" then self:loadBooks({})
        elseif link == "read" then self:loadReadBooks()
        elseif link == "collections" then self:loadBooks({}); self:libraryOpenSheet("sort", "collection")
        elseif link == "history" then self:loadHistory()
        elseif link == "authors" or link == "series" or link == "genres" then self:loadSection(link) end
    elseif k == "customize" then
        page:close(); self.mode = "home"; self:updateItems(); self:boardEnterEdit()
    elseif k == "home" then
        page:close(); self.mode = "home"; self:updateItems()
    elseif k == "exit" then
        page:close(); self:onClose()
    elseif k == "settings" then
        page:close(); self:showSettings()
    elseif k == "about" then
        page:close(); self:showAbout()
    elseif k == "owner" then
        page:close(); require("aleph_owner").open(self)
    elseif k == "search" then
        page:close(); self:promptSearch()
    end
end
-- The books that were opened, most recent first.
function Browser:loadHistory()
    local ids = {}
    local any = false
    for _i, b in ipairs(self.local_library.books) do
        if (b.last_open or 0) > 0 then ids[b.id] = true; any = true end
    end
    if not any then return self:message(_("No books opened yet.")) end
    self:loadBooks({ ids = ids, sort = "last_read" }, _("History"))
end
function Browser:showSettings(view)
    local ok, err = pcall(function() require("aleph_settings_page").open(self, view) end)
    if not ok then
        require("logger").warn("Aleph: settings failed:", err)
        self:message(_("Settings could not open.") .. "\n" .. tostring(err))
    end
end
function Browser:showAbout()
    local dialog
    dialog = require("ui/widget/buttondialog"):new{ title = "Aleph " .. require("aleph_prefs").VERSION, text =
        "Powered by BookOrbit\nCopyright (C) 2025-2026 neon.\nAdditional copyright is held by the respective BookOrbit contributors.\nOriginal project: https://github.com/bookorbit/bookorbit\n\n" ..
        "This is a modified version of BookOrbit and is not an official BookOrbit release. Modified 2026-11-20.\n\n" ..
        "Licensed under the GNU Affero General Public License, version 3 only, with additional terms. This software is provided without warranty. You may redistribute and modify it under those terms.\n\n" ..
        "Complete source is included in aleph.koplugin. See LICENSE, ADDITIONAL_TERMS.md and MODIFICATIONS.md. Books and statistics come from KOReader; Syncthing operates independently.",
        buttons = { { { text = _("Powered by BookOrbit ↗"), callback = function()
            if Device.openLink then Device:openLink("https://github.com/bookorbit/bookorbit")
            else self:message("https://github.com/bookorbit/bookorbit") end
        end } }, { { text = _("Close"), callback = function() UIManager:close(dialog) end } } } }
    UIManager:show(dialog)
end
function Browser:refreshData()
    Data.invalidateLocal()
    Data.invalidateHabits()
    Data.invalidateUnopened()
    self.current_context.dashboard = self.local_library:dashboard()
    self:updateItems()
end
function Browser:boardPickShelfSource() self:message(_("Choose one of the local shelf widgets in Add widget → Library.")) end
function Browser:startScan()
    if self.scanning or self.closed then return end
    self.scanning = true
    local co = self.local_library:scanCoroutine()
    self.scan_task = function()
        if self.closed or not self.scanning then return end
        local ok, value = coroutine.resume(co)
        if not ok then
            self.scanning = false; self:message(_("Library scan stopped; the previous index was kept.") .. "\n" .. tostring(value)); return
        end
        if coroutine.status(co) == "dead" then
            self.scanning = false
            -- An unchanged library keeps the board as it is: no rebuild, no redraw.
            if self.local_library.last_scan_changed ~= false or #self.local_library.errors > 0 then self:refreshData() end
            if #self.local_library.errors > 0 then self:message(T(_("Indexed %1 books. %2 files could not be read."),
                #self.local_library.books, #self.local_library.errors) .. "\n" .. self.local_library.errors[1]) end
            if #self.local_library.books == 0 and #self.settings.library_roots == 0 then self:showSettings("library") end
            self:syncCalibreCollections(true)
        else UIManager:scheduleIn(0.01, self.scan_task) end
    end
    UIManager:nextTick(self.scan_task)
end
-- The scan when Home opens: only when one is due (aleph_local.lua, scanDue).
-- The book just closed has been read again by itself, so most times Home is
-- already right and the whole library is not gone through.
function Browser:startScanIfDue()
    local ok, due = pcall(self.local_library.scanDue, self.local_library)
    if not ok or due then self:startScan() else self:syncCalibreCollections() end
end
-- Aleph modification, 2026-11-17: the books into the collections Calibre's
-- #collections column names (aleph_calibre_collections.lua), in the
-- background; Home or the library drawn again when something changed.
function Browser:syncCalibreCollections(force)
    if self.settings.calibre_collections == false then return end
    local lib = self.local_library
    if not (lib and type(lib.books) == "table" and #lib.books > 0) then return end
    try(function()
        require("aleph_calibre_collections").sync(lib.books, function(n)
            if n > 0 and not self.closed and (self.mode == "home" or self.mode == "library") then self:updateItems() end
        end, force)
    end)
end
function Browser:cancelScan()
    self.scanning = false
    if self.scan_task then UIManager:unschedule(self.scan_task) end
end
function Browser:boardRefreshIfMissing() self:updateItems() end
function Browser:boardRefreshTile() self:updateItems() end
function Browser:boardFlip(delta)
    if self.mode == "detail" then return self:detailGo(delta) end
    -- A sort or filter sheet covers the page; turning pages behind it would
    -- change what is being filtered.
    if self.mode == "library" and self.library_sheet and self.library_sheet.kind == "sort" then return end
    if self.mode == "library" and self.select and self.select.sheet then return end
    if self.mode == "home" then
        -- Over the pages shown (a page with no widgets is skipped).
        local step = delta > 0 and 1 or -1
        local at = self:boardPage()
        for _i = 1, math.abs(delta) do
            local nxt = self:boardNextPage(at, step)
            if not nxt then break end
            at = nxt
        end
        self.current_context.board_page = at
    else self.page = math.max(1, math.min(self.page_count or 1, self.page + delta)) end
    self:updateItems()
end
function Browser:onNext() self:boardFlip(1); return true end
function Browser:onPrev() self:boardFlip(-1); return true end
-- Swipe left or right turns the page; a swipe down from the top edge opens
-- KOReader's top menu, as its own menu gesture does elsewhere.
function Browser:onSwipe(_i, ges)
    local dir = ges and ges.direction
    -- A diagonal swipe clears ghosting: the whole screen is redrawn with a full
    -- e-ink refresh, as in KOReader's own screens.
    if dir == "northeast" or dir == "northwest" or dir == "southeast" or dir == "southwest" then
        UIManager:setDirty("all", "full")
        return true
    end
    if self.detail_sheet or self.library_sheet then return true end
    -- Swipe up or down along the left edge for brightness, along the right edge
    -- for warmth, on every page of the board (as the LiveLight plugin does).
    if (dir == "north" or dir == "south") and ges.pos and not self.board_edit and self:adjustLight(ges) then return true end
    if dir == "west" then return self:onNext() elseif dir == "east" then return self:onPrev()
    elseif dir == "south" and ges.pos and ges.pos.y < self.dimen.h / 8 and not self.board_edit then
        return self:showKOReaderMenu()
    end
end
-- A vertical swipe that starts in the left fifth of the screen changes the
-- frontlight, one in the right fifth the warmth, by as much as the swipe is
-- long (a swipe over the whole height covers a bit more than the whole range).
function Browser:adjustLight(ges)
    local width = self.dimen.w
    local zone = ges.pos.x < width * 0.2 and "brightness" or ges.pos.x > width * 0.8 and "warmth" or nil
    if not zone then return false end
    local Device = require("device")
    local powerd = Device:getPowerDevice()
    local fraction = (ges.distance or math.abs((ges.end_pos and ges.end_pos.y or ges.pos.y) - ges.pos.y)) / self.dimen.h
    local sign = ges.direction == "north" and 1 or -1
    local label, icon, value
    if zone == "brightness" then
        if not Device:hasFrontlight() then return false end
        local low, high = powerd.fl_min, powerd.fl_max
        local step = math.max(1, math.floor(fraction * (high - low) * 1.2 + 0.5))
        value = math.max(low, math.min(high, powerd:frontlightIntensity() + sign * step))
        powerd:setIntensity(value)
        label, icon = _("Brightness"), "sun"
    else
        if not Device:hasNaturalLight() then return false end
        local low, high = powerd.fl_warmth_min, powerd.fl_warmth_max
        local step = math.max(1, math.floor(fraction * (high - low) * 1.2 + 0.5))
        value = math.max(low, math.min(high, powerd:toNativeWarmth(powerd:frontlightWarmth()) + sign * step))
        powerd:setWarmth(powerd:fromNativeWarmth(value))
        label, icon = _("Warmth"), "thermometer-sun"
    end
    try(function() require("aleph_toast").show(label .. " " .. value, { icon = icon }) end)
    return true
end
function Browser:showKOReaderMenu()
    local ui = self.plugin and self.plugin.ui
    if not ui then
        local fm = require("apps/filemanager/filemanager").instance
        ui = fm
    end
    local menu = ui and ui.menu
    if menu and menu.onShowMenu then
        menu:onShowMenu()
        return true
    end
    return false
end
function Browser:onSetDimensions() self:updateItems() end
-- Plugging in or unplugging a cable: redraw the battery after the device has
-- settled (the next minute's clock redraw catches it otherwise).
function Browser:chargingChanged()
    if self.closed or not self.status_refresh then return end
    UIManager:unschedule(self.status_refresh)
    UIManager:scheduleIn(1, self.status_refresh)
end
function Browser:onCharging() self:chargingChanged() end
function Browser:onNotCharging() self:chargingChanged() end
function Browser:onCharged() self:chargingChanged() end
-- The board's page for one book, opened from the reader (for example from
-- TopBar's cover). Back closes the board and returns to the book. False
-- when the book is not in the board's library.
function Browser:openBookPage(path)
    for _i, b in ipairs(self.local_library.books) do
        if b.path == path then
            self.close_on_back = true
            self:loadBookDetail(b.id)
            return true
        end
    end
    return false
end
function Browser:onBack()
    if self.mode == "detail" and self.close_on_back and not self.detail_sheet then return self:onClose() end
    if self.board_edit then self:boardExitEdit()
    elseif self.mode == "detail" and self.detail_sheet then self:detailRun({ kind = "close-sheet" })
    elseif self.mode == "library" and self.select then
        -- Back closes the selection menu, then ends the selection.
        if self.select.sheet then self.select.sheet = nil else self.select = nil end
        self:updateItems()
    elseif self.mode == "library" and self.library_sheet then
        if self.library_sheet.pick then self.library_sheet.pick = nil; self:updateItems()
        else self.library_sheet = nil; self:updateItems() end
    elseif self.mode == "detail" then self.mode = self.detail_from or "library"; self:updateItems()
    elseif self.mode == "library" and self.return_to_index and not self.index_kind then
        local kind = self.return_to_index; self.return_to_index = nil; self:loadIndex(kind)
    elseif self.mode ~= "home" then self.mode = "home"; self.index_kind = nil; self.return_to_index = nil; self:updateItems()
    else self:onClose() end
    return true
end
function Browser:onClose()
    if self.closed then return true end
    if self.board_edit then self:boardExitEdit() end
    self:cancelScan(); self.closed = true
    if self.light_sheet then self.light_sheet:close() end
    if self.cover_task then UIManager:unschedule(self.cover_task) end
    if self.clock_task then UIManager:unschedule(self.clock_task) end
    -- The wallpaper's scaled picture (aleph_wallpaper.lua) is let go.
    try(function() require("aleph_wallpaper").release() end)
    if self.status_refresh then UIManager:unschedule(self.status_refresh) end
    if self.cover_listener then CoverJob.unlisten(self.cover_listener) end
    UIManager:close(self)
    -- The covers Home drew stay decoded for the next time it opens (after a
    -- book, most times): the few drawn last, within a smaller budget.
    UI.trimCoverCache(16, 6 * 1024 * 1024)
    -- The file browser under the board was not rebuilt when the screen
    -- turned (main.lua): it is now, before it shows.
    try(function()
        local fm = require("apps/filemanager/filemanager").instance
        if not (fm and fm._aleph_rotate_pending) then return end
        fm._aleph_rotate_pending = nil
        -- Not while the file browser itself is closing (Exit, Restart).
        local shown = false
        for _i, window in ipairs(UIManager._window_stack or {}) do if window.widget == fm then shown = true end end
        if shown then fm:reinit() end
    end)
    require("aleph_picture").collectSoon()
    return true
end
-- ------------------------------------------------------ Home's actions
-- What a tap on Home does, by the action's kind: one function each,
-- (self, a) with a the action a widget or a button carries. boardRun finds
-- the kind's function here once the book page, the lists, a selection and
-- the library have had their say.
local BOARD_ACTIONS = {}

BOARD_ACTIONS["noop"] = function() end
BOARD_ACTIONS["back"] = function(self) self:onBack() end
BOARD_ACTIONS["menu"] = function(self) self:showMenu() end
BOARD_ACTIONS["page"] = function(self, a) self:boardFlip(a.delta) end
BOARD_ACTIONS["search"] = function(self) self:promptSearch() end
BOARD_ACTIONS["book"] = function(self, a) self:openBook(a.book) end
BOARD_ACTIONS["open"] = BOARD_ACTIONS["book"]
BOARD_ACTIONS["detail"] = function(self, a) self:loadBookDetail(a.book_id, a.list) end
BOARD_ACTIONS["detail-go"] = function(self, a) self:detailGo(a.delta) end
BOARD_ACTIONS["rate"] = function(self, a) self:rateBook(a.book, a.rating) end
BOARD_ACTIONS["book-actions"] = function(self, a) self:loadBookDetail(a.book.id) end
BOARD_ACTIONS["books"] = function(self, a) self:loadBooks(a.params, a.title) end
BOARD_ACTIONS["folders"] = function(self) self:showSettings("library") end
BOARD_ACTIONS["goal-settings"] = function(self) self:showSettings("profile") end
BOARD_ACTIONS["bingo"] = function() require("aleph_bingo_page").open() end
BOARD_ACTIONS["shuffle"] = function(self) self:refreshData() end
BOARD_ACTIONS["silverfish"] = function() return require("aleph_integrations").openSilverfish() end
-- Aleph modification, 2026-11-16: the weather's settings.
BOARD_ACTIONS["weather"] = function(self) return require("aleph_weather").openMenu(self) end
BOARD_ACTIONS["insights"] = function(self, a) return require("aleph_integrations").openInsights(self.plugin.ui, a.view) end
BOARD_ACTIONS["night"] = function(self) UIManager:broadcastEvent(Event:new("ToggleNightMode")); self:updateItems() end
BOARD_ACTIONS["rotate"] = function() UIManager:broadcastEvent(Event:new("IterateRotation")) end
BOARD_ACTIONS["frontlight"] = function(self) require("aleph_light_sheet").open(self) end
BOARD_ACTIONS["wifi"] = function(self) self:boardToggleWifi() end
BOARD_ACTIONS["light"] = function(self, a) self:boardAdjustLight(a.what, a.delta) end
BOARD_ACTIONS["info"] = function(self, a) self:showBookInformation(a.book) end
BOARD_ACTIONS["highlights"] = function(self, a) self:showHighlights(a.book) end
BOARD_ACTIONS["highlight"] = function(self, a) self:showHighlightOfTheDay(a.highlight) end

-- A link to one of the library's lists.
BOARD_ACTIONS["link"] = function(self, a)
    if a.link == "authors" or a.link == "series" or a.link == "genres" then self:loadSection(a.link)
    elseif a.link == "collections" then self:loadBooks({}); self:libraryOpenSheet("sort", "collection")
    elseif a.link == "history" then self:loadHistory()
    elseif a.link == "search" then self:promptSearch()
    elseif a.link == "read" then self:loadReadBooks()
    else self:loadBooks({}) end
end

-- A shelf widget's "See all": the list the shelf was drawn from.
BOARD_ACTIONS["shelf"] = function(self, a)
    local source = a.props and a.props.source
    local params = {}
    if source == "in-progress" or source == "pick-back-up" then params = { read_status = "reading", sort = "last_read" }
    elseif source == "want-to-read" then params = { read_status = "unread" }
    elseif source == "finished" then params = { read_status = "read" }
    elseif source == "recently-added" then params = { sort = "recently_added" } end
    local shelf = self.current_context.dashboard.boardShelves[source]
    if shelf then
        params.ids = {}
        for _i, book in ipairs(shelf) do params.ids[book.id] = true end
    end
    self:loadBooks(params, require("aleph_board_widgets").shelfTitle(a.props or {}))
end

-- The quick controls' refresh button. With KOSyncthing+ installed it starts
-- Syncthing instead of rescanning; Settings still has the library rescan.
BOARD_ACTIONS["refresh"] = function(self)
    local Integrations = require("aleph_integrations")
    local Chain = require("aleph_sync_chain")
    if Chain.available(self.plugin.ui) then
        -- KOSyncthing+ and Syncery: the whole chain, both e-readers
        -- (aleph_sync_chain.lua); the library is read again after.
        Chain.run(self.plugin.ui, { on_done = function(ok)
            if ok and not self.closed then self:startScan() end
        end })
    elseif Integrations.syncthing() then
        -- The page is redrawn only when Syncthing's state changes, so the
        -- button lights once it is up and nothing flashes meanwhile.
        local function redraw() if not self.closed and self.mode == "home" then self:updateItems() end end
        Integrations.startSyncthing(redraw)
        Integrations.watchSyncthing(redraw)
    else
        -- Without KOSyncthing+ the button rescans the library, and says so.
        try(function() require("aleph_toast").show(_("KOSyncthing+ was not found. Rescanning the library.")) end)
        self:startScan()
    end
end

-- An action of KOReader's or a plugin's, put on a button or a widget.
BOARD_ACTIONS["dispatch"] = function(self, a)
    require("aleph_plugins").dispatch(self.plugin.ui, a.id)
    if not self.closed then self:updateItems() end
end

BOARD_ACTIONS["about"] = function(self, a)
    local b = a.book or self.detail_book
    if b then self:showAboutBook(self.by_id[b.id] or b) end
end

BOARD_ACTIONS["genres-sheet"] = function(self, a)
    local b = a.book or self.detail_book
    if b then self:showGenresSheet(self.by_id[b.id] or b) end
end

BOARD_ACTIONS["lookup"] = function(self, a)
    if self.plugin.ui.dictionary then self.plugin.ui.dictionary:onLookupWord(a.word) end
end

-- Gathering dust: the next unopened book, for today.
BOARD_ACTIONS["dust-next"] = function(self)
    local day = os.date("%Y-%m-%d")
    local state = self.settings.board_dust or {}
    self:persistSetting("board_dust", { day = day, skip = (state.day == day and state.skip or 0) + 1 })
    self:updateItems()
end

Browser.BOARD_ACTIONS = BOARD_ACTIONS

function Browser:boardRun(a)
    if not a then return end
    local k = a.kind
    if self:detailRun(a) then return end
    if self:indexRun(a) then return end
    if self:selectRun(a) then return end
    if self:libraryRun(a) then return end
    if k:match("^edit%-") or k:match("^sheet%-") then return self:boardEditRun(a) end
    local handler = BOARD_ACTIONS[k]
    if handler then return handler(self, a) end
end
return Browser
