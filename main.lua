local Prefs = require("aleph_prefs")
local _ = require("aleph_gettext")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local UIManager = require("ui/uimanager")
local Dispatcher = require("dispatcher")
local try = require("aleph_try").call
local Board = WidgetContainer:extend{ name = "aleph", is_doc_only = false }

-- Aleph modification, 2026-11-18: who asks for redraws many times a second,
-- written to crash.log (aleph_redraw_watch.lua).
try(function() require("aleph_redraw_watch").install(UIManager) end)

-- Opening the board over the file browser, at startup and after a book is
-- closed. Done the way ZenOS takes over the browser: a class-level hook on
-- FileManager:showFiles, which KOReader calls every time it builds the file
-- browser (the first time at startup, again whenever a book is closed). The
-- browser is put on screen inside showFiles, so what is shown right after it
-- lands on top of it. Nothing here waits or guesses: it acts on the browser
-- KOReader has just built.
local logger = require("logger")

-- The library index written if it has changes not written yet
-- (aleph_local.lua: in a background process where one can be started).
-- Set when KOReader quits or restarts: the book open then closes after that,
-- and its new state is written as it does.
local quitting = false
local function saveIndexLater()
    local Local = package.loaded["aleph_local"]
    if Local and Local.flushIfDirty then try(Local.flushIfDirty) end
end

-- Settings, library index and cache from the plugin's old name
-- (readingboard.koplugin), moved before anything reads them.
try(function() require("aleph_migrate").run() end)
-- Home's font (Settings > Home > Font, aleph_fonts.lua), before anything is drawn.
try(function() require("aleph_fonts").apply() end)
-- KOReader's own windows in Aleph's style (Settings > Home > Aleph dialogs).
do
    local ok, err = pcall(function() require("aleph_theme").sync() end)
    if not ok then logger.warn("Aleph: theme not applied:", err) end
end

local function wantsBoard()
    return Prefs.is("open_home")
end

local function onScreen(widget)
    for _i, window in ipairs(UIManager._window_stack or {}) do
        if window.widget == widget then return true end
    end
    return false
end

-- Shows the board over `fm` once. Each file browser KOReader builds is a new
-- widget, so each gets one opening: closing the board is never undone.
local function openOver(fm, tries)
    -- Aleph Home from a book's reader menu asks for the board this once.
    local Opening = package.loaded["aleph_opening"]
    local pending = Opening and Opening.pending_home
    if not fm or (fm._aleph_opened and not pending) or not (wantsBoard() or pending) then return end
    local plugin = fm.aleph or (fm.modules and fm.modules.aleph)
    if not plugin then
        -- Registered under another name: find it among the browser's modules.
        for _i, module in ipairs(fm) do
            if type(module) == "table" and module.onShowAleph then plugin = module; break end
        end
    end
    if not plugin then return end
    -- Not on screen yet (it is shown right after it is built): look again shortly.
    if not onScreen(fm) then
        if (tries or 0) < 25 then UIManager:scheduleIn(0.2, function() openOver(fm, (tries or 0) + 1) end) end
        return
    end
    fm._aleph_opened = true
    if pending then Opening.pending_home = nil end
    -- At startup quietly (Bookshelf's "Start with" decides then); asked for
    -- from a book, Aleph stays above Bookshelf (aleph_shelf_guard.lua).
    local ok, err = pcall(plugin.onShowAleph, plugin, not pending)
    if ok and type(pending) == "function" and plugin.browser then pcall(pending, plugin.browser) end
    if not ok then
        logger.warn("Aleph: could not open over the file browser:", err)
        UIManager:show(require("ui/widget/infomessage"):new{ text = _("Aleph could not open at startup:") .. "\n" .. tostring(err) })
    end
end

-- Aleph modification, 2026-11-18: advokatb's Goodreads plugin still on: a
-- warning, once a start, a moment after the file browser or a book is ready
-- (aleph_gr.lua).
local function warnGoodreadsPlugin(ui)
    UIManager:scheduleIn(3, function()
        try(function() require("aleph_gr").warnPlugin(ui) end)
    end)
end

-- Once each time KOReader starts, when its file browser is first built:
-- the Goodreads warning and the memory diary's first line. (These were in
-- Board:onFileManagerReady, which KOReader never sends to a plugin: they
-- never ran.)
local started_once = false
local function fileBrowserStarted(fm)
    if started_once or not fm then return end
    started_once = true
    warnGoodreadsPlugin(fm)
    try(function() require("aleph_mem").report("file browser ready") end)
end

local FileManager = require("apps/filemanager/filemanager")
if not FileManager._aleph_hooked then
    FileManager._aleph_hooked = true
    local original_showFiles = FileManager.showFiles
    function FileManager:showFiles(...)
        local result = original_showFiles(self, ...)
        openOver(FileManager.instance)
        fileBrowserStarted(FileManager.instance)
        return result
    end
    -- Turning the screen rebuilds the whole file browser, its book covers
    -- included, before anything else is drawn (a second or more), though
    -- the board covers it. While the board is up, the browser only learns
    -- the new size; it is rebuilt when the board closes.
    local original_rotate = FileManager.rotate
    function FileManager:rotate(...)
        local plugin = rawget(self, "aleph") or (self.modules and self.modules.aleph)
        local browser = plugin and plugin.browser
        if browser and not browser.closed then
            self._aleph_rotate_pending = true
            self.dimen = require("device").screen:getSize()
            self:handleEvent(require("ui/event"):new("SetDimensions", self.dimen))
            return
        end
        return original_rotate(self, ...)
    end
end

-- KOReader's "Opening file" message in the board's style. (The search prompt is
-- the board's own; the highlight sheet is installed when a book is open.)
local ok_opening, opening_err = pcall(function() require("aleph_opening").install() end)
if not ok_opening then logger.warn("Aleph: opening card not installed:", opening_err) end

-- The reader controls gain a Background tab; it is added here, at load, because
-- KOReader reads its option list when a book opens.
local ok_tab, tab_err = pcall(function() require("aleph_config").installOptions() end)
-- The night profile (Settings > Home > Night profile): watches night mode
-- turning on and off; does nothing while the profile is off.
try(function() require("aleph_night").install() end)
if not ok_tab then logger.warn("Aleph: Background tab not added:", tab_err) end

function Board:init()
    self.settings = G_reader_settings:readSetting("aleph", {})
    if not self.settings.library_roots then
        local home = G_reader_settings:readSetting("home_dir")
        self.settings.library_roots = home and { home } or {}
    end
    -- Aleph on the first page of Tools, below calibre.
    try(function() require("aleph_menu_pin").ensure() end)
    self.ui.menu:registerToMainMenu(self)
    -- The top menu's Controls and Apps tabs (settings: Opening > Quick top bar).
    local ok_bar, bar_err = pcall(function() require("aleph_topbar").sync(self) end)
    if not ok_bar then logger.warn("Aleph: Quick Top Bar not started:", bar_err) end
    Dispatcher:registerAction("aleph_open", { category = "none", event = "ShowAleph", title = _("Aleph: open"), general = true })
    Dispatcher:registerAction("aleph_pins", { category = "none", event = "ShowAlephPins", title = _("Aleph: pinned pages"), reader = true })
    Dispatcher:registerAction("aleph_page_browser", { category = "none", event = "ShowAlephPageBrowser", title = _("Aleph: page browser"), reader = true })
    Dispatcher:registerAction("aleph_xray", { category = "none", event = "ShowAlephXray", title = _("Aleph: X-Ray"), reader = true })
    Dispatcher:registerAction("aleph_this_book", { category = "none", event = "ShowAlephThisBook", title = _("Aleph: this book"), reader = true })
    -- Gestures bound to the old action names, and the old folder left installed.
    local ui = self.ui
    UIManager:nextTick(function()
        try(function() require("aleph_migrate").gestures(ui) end)
        try(function() require("aleph_migrate").warnOldFolder(ui) end)
        -- ZenOS replaces the same screens: say so (Aleph runs as usual).
        try(function() require("aleph_conflicts").check(ui) end)
    end)
    -- The first file browser of a session is being built while this runs, before
    -- the hook above can see its showFiles finish: open over it as soon as it is
    -- shown. (Later ones are covered by the hook.)
    if not self.ui.document then
        local fm = self.ui
        UIManager:nextTick(function() openOver(fm) end)
    else
        -- In a book. With the troubleshooting log on (Settings > About),
        -- each step is logged before and after it runs: if the reader ever
        -- stops here, the last "Aleph: debug: reader step" line in
        -- koreader/crash.log names the step that did not finish. A step
        -- that fails is always logged.
        local Debug = require("aleph_debug")
        local function step(name, fn)
            Debug.log("reader step " .. name)
            local ok, err = pcall(fn)
            if not ok then logger.warn("Aleph: " .. name .. " not installed:", err) end
            Debug.log("reader step " .. name .. " done")
        end
        step("highlight", function() require("aleph_highlight").install() end)
        step("dictionary", function() require("aleph_dictionary").install() end)
        step("details", function() require("aleph_bookmark").install() end)
        step("page browser", function() require("aleph_page_browser").install() end)
        step("reader menu", function() require("aleph_reader_sheet").install() end)
        -- Search as on a Kindle: every result on a page, then a bar to go
        -- through them, and a way back (Settings > Reader).
        step("search", function() require("aleph_search").install() end)
        -- Coloured bookmarks: the ribbon and the list of colours.
        step("bookmark colours", function()
            local ui = self.ui
            ui:registerPostInitCallback(function()
                try(function() require("aleph_bookmark_colors").attach(ui) end)
            end)
        end)
        -- Stats at the top and bottom of the pages, and their minute tick.
        step("bookends", function()
            local Bookends = require("aleph_bookends")
            Bookends.install()
            Bookends.attach(self.ui)
            -- The page turner's battery on the bottom line (HID Passthrough).
            try(function() require("aleph_page_turner").attach(self.ui) end)
        end)
        for _i, name in ipairs({ "aleph_menu_skin", "aleph_imageviewer", "aleph_config" }) do
            step(name, function() require(name).install() end)
        end
        self.ui:registerPostInitCallback(function()
            Debug.log("reader step saved background")
            try(function() require("aleph_config").applySaved(self.ui) end)
            Debug.log("reader step saved background done")
        end)
        -- Pinned pages: the Pin button, the pictures menu, and (only when the
        -- book has pins) the badge.
        step("pins", function()
            local Pins = require("aleph_pins")
            Pins.install()
            Pins.attach(self.ui)
        end)
        -- Aleph's own X-Ray (aleph_xr.lua): only with Settings > X-Ray on;
        -- off (as it is unless turned on), none of it is loaded.
        if Prefs.is("xray_enabled") then
            step("x-ray", function()
                local XR = require("aleph_xr")
                XR.install()
                XR.attach(self.ui)
            end)
        end
    end
end
function Board:addToMainMenu(items)
    items.aleph = { text = "Aleph", callback = function() self:onShowAleph() end }
    -- In a book, where the pin badge sits (and the side its drawer opens on),
    -- right under Aleph in Tools.
    if self.ui.document then
        items.aleph_pin_badge = { text = _("Pin badge position"), callback = function()
            require("aleph_pins").openPlacer(self.ui)
        end }
        items.aleph_bookends = { text = _("Book margins (top and bottom stats)"), callback = function()
            require("aleph_bookends_page").open(self.ui)
        end }
    end
end
-- quiet: opened by itself (at startup), not asked for. Asked for, it stays
-- above Bookshelf's screen (aleph_shelf_guard.lua).
function Board:onShowAleph(quiet)
    if not (self.browser and not self.browser.closed) then
        self.browser = require("aleph_browser"):new{ plugin = self, settings = self.settings }
        UIManager:show(self.browser)
        self.browser:startScanIfDue()
    end
    if quiet ~= true then try(function() require("aleph_shelf_guard").keep(self.browser) end) end
    return true
end
-- The board's page for a book, over the reader. True when it was shown.
function Board:showBookPage(path)
    if not path then return false end
    if self.browser and not self.browser.closed then return false end
    local browser = require("aleph_browser"):new{ plugin = self, settings = self.settings }
    if not browser:openBookPage(path) then
        browser:onClose()
        return false
    end
    self.browser = browser
    UIManager:show(browser)
    return true
end
-- The Background tab of the reader controls: White, Paper, Sepia, Gray, Custom.
-- KOReader's night mode on or off: the page colour follows (white at night).
-- Not consumed, so KOReader still switches night mode itself.
function Board:onToggleNightMode()
    if not self.ui or not self.ui.document then return end
    local ui = self.ui
    UIManager:nextTick(function()
        if ui.document then pcall(function() require("aleph_config").nightChanged(ui) end) end
    end)
end
Board.onSetNightMode = Board.onToggleNightMode

function Board:onAlephSetPageBackground(index)
    local Config = require("aleph_config")
    if index == 5 then
        Config.pickCustom(self.ui, function() Config.applyBackground(self.ui, 5) end)
    else
        Config.applyBackground(self.ui, index)
    end
    return true
end
-- "Aleph: this book": the open book's page, as the Quick Top Bar's
-- cover opens it (a book outside the library falls back to Bookshelf's page
-- or KOReader's Book information).
-- The page browser (aleph_page_browser.lua), from its gesture action.
function Board:onShowAlephPageBrowser()
    if not self.ui.document then return false end
    local ok, err = pcall(function() require("aleph_page_browser").open(self.ui) end)
    if not ok then logger.warn("Aleph: page browser failed:", err) end
    return true
end
-- Its swipe up from the bottom edge, registered once the book is ready
-- (ReaderMenu sets up KOReader's own touch zones then too).
function Board:onReaderReady()
    if not self.ui.document then return end
    local ok, err = pcall(function() require("aleph_page_browser").registerZone(self.ui) end)
    if not ok then logger.warn("Aleph: page browser swipe not added:", err) end
    -- KOReader sets up its status bar by now: hide it if the bottom line asks.
    try(function() require("aleph_bookends").applyStock(self.ui) end)
    -- Aleph modification, 2026-11-18: Aleph's own Goodreads, with
    -- advokatb's plugin off (aleph_gr.lua); while it is on, a warning.
    try(function() require("aleph_gr").open(self.ui) end)
    warnGoodreadsPlugin(self.ui)
    -- The memory diary: now, then every 10 minutes while reading.
    try(function()
        local Mem = require("aleph_mem")
        Mem.report("book opened")
        Mem.watch()
    end)
end
-- Page turns, for Goodreads' percentage (a comparison, then at most one
-- background question a minute). Not consumed.
function Board:onPageUpdate(page)
    local Core = package.loaded["aleph_gr"]
    if Core and self.ui.document then try(Core.page, self.ui, page) end
end
function Board:onPosUpdate(_pos, page)
    if page then return self:onPageUpdate(page) end
end
-- KOReader changed a book's status or stars: Goodreads follows (only the
-- open book's reader, or the file browser).
function Board:onDocSettingsItemsChanged(file, doc_settings)
    if self.ui.document and self.ui.document.file ~= file then return end
    try(function() require("aleph_gr").docChanged(self.ui, file, doc_settings) end)
end
-- Back online: what waits for Goodreads is sent.
function Board:onNetworkConnected()
    local Core = package.loaded["aleph_gr"]
    if not Core then return end
    try(Core.flush)
    if self.ui.document then try(Core.open, self.ui) end
end
function Board:onShowAlephThisBook()
    if not self.ui.document then return false end
    local ok, err = pcall(function() require("aleph_topbar_book").showDetails(self.ui) end)
    if not ok then
        logger.warn("Aleph: could not open this book's page:", err)
        if self.ui.bookinfo then self.ui.bookinfo:onShowBookInfo() end
    end
    return true
end
-- The gesture "Aleph: X-Ray": the names of the open book.
function Board:onShowAlephXray()
    if not self.ui.document then return false end
    if not Prefs.is("xray_enabled") then
        try(function() require("aleph_toast").show(_("X-Ray is off. Turn it on in Aleph's Settings > X-Ray."), { icon = "info", timeout = 4 }) end)
        return true
    end
    try(function()
        local XR = require("aleph_xr")
        XR.install()
        XR.attach(self.ui)
        XR.open(self.ui)
    end)
    return true
end
function Board:onShowAlephPins()
    if not self.ui.document then return false end
    require("aleph_pins").openList(self.ui)
    return true
end
function Board:onCloseDocument()
    try(function()
        local Mem = require("aleph_mem")
        Mem.unwatch()
        Mem.report("book closed")
    end)
    try(function() require("aleph_bookends").detach(self.ui) end)
    try(function() require("aleph_page_turner").detach(self.ui) end)
    try(function() require("aleph_pins").detach(self.ui) end)
    local Search = package.loaded["aleph_search"]
    if Search then try(Search.detach, self.ui) end
    -- X-Ray, when it was loaded for this book.
    local XR = package.loaded["aleph_xr"]
    if XR then try(XR.detach, self.ui) end
    if self.ui.doc_settings then
        require("aleph_chapter_map").remember(self.ui, self.ui.doc_settings:readSetting("partial_md5_checksum"))
    end
    -- A finished book goes on the record now, in case it is deleted before
    -- the library is scanned again.
    try(function() require("aleph_finished_log").fromReader(self.ui) end)
    -- Goodreads: the percentage it closed at (aleph_gr.lua).
    local Core = package.loaded["aleph_gr"]
    if Core then try(Core.close, self.ui) end
    -- The book's entry in the library, made again from the reader's own
    -- settings: Home is right the first time it is drawn after the book,
    -- with no scan of the whole library (aleph_local.lua).
    try(function() require("aleph_local").refreshClosing(self.ui) end)
    require("aleph_board_data").invalidateLocal()
    if quitting then saveIndexLater() end
end
-- The device goes to sleep: the minute tick of the page's top and bottom
-- lines stops, and starts again on waking (the page is painted again then).
-- Neither is consumed: KOReader and the other plugins hear them too.
function Board:onSuspend()
    if self.ui and self.ui.document then
        try(function() require("aleph_bookends").disarm(self.ui) end)
    end
    try(function() require("aleph_mem").report("going to sleep") end)
    -- Nobody waits as the device goes to sleep: the library index, when it
    -- has changes not written yet, is written now (in the background).
    saveIndexLater()
end
function Board:onResume()
    try(function() require("aleph_mem").report("woke up") end)
    if self.ui and self.ui.document then
        try(function() require("aleph_bookends").arm(self.ui) end)
    end
    -- Night mode by the clock (Settings > Home > Night profile): a period
    -- that started while the device slept is set now.
    try(function() require("aleph_night").checkSchedule() end)
end
-- KOReader's Exit and Restart close the file browser, and KOReader quits when
-- nothing is left on screen. The board is a screen of its own over the file
-- browser, so it (and any page, sheet or panel of it) is closed with it; left
-- open it would keep KOReader running until it was closed by hand.
-- The screen turned: the board and Aleph's pages over it are laid out again
-- for the new size at once (they did not hear of it, and waited for the next
-- tap or the clock). A sheet over the board keeps a picture of the screen
-- under it, which no longer fits: it closes.
function Board:onSetDimensions()
    local browser = self.browser
    if not browser or browser.closed then return end
    UIManager:nextTick(function()
        if browser.closed then return end
        local Screen = require("device").screen
        local w, h = Screen:getWidth(), Screen:getHeight()
        local pages = {}
        for _i, window in ipairs(UIManager._window_stack or {}) do
            local widget = window.widget
            if widget ~= browser and type(widget.name) == "string" and widget.name:find("^aleph") then pages[#pages + 1] = widget end
        end
        try(function() browser:updateItems() end)
        UIManager:setDirty(browser, "full")
        for _i, page in ipairs(pages) do
            try(function()
                if page.backdrop_bb or page.backdrop then
                    if page.close then page:close() else UIManager:close(page) end
                elseif page.dimen and (page.rebuild or page.refresh) then
                    page.dimen.w, page.dimen.h = w, h
                    if page.refresh then page:refresh() end
                    UIManager:setDirty(page, "full")
                end
            end)
        end
    end)
end

function Board:onCloseWidget()
    local browser = self.browser
    if browser and not browser.closed then pcall(function() browser:onClose() end) end
    local open = {}
    for _i, window in ipairs(UIManager._window_stack or {}) do
        local widget = window.widget
        if widget and type(widget.name) == "string" and widget.name:find("^aleph") then open[#open + 1] = widget end
    end
    for _i, widget in ipairs(open) do pcall(function() UIManager:close(widget) end) end
end
function Board:onFlushSettings()
    G_reader_settings:saveSetting("aleph", self.settings)
    -- The library index is not written here: KOReader saves its settings as
    -- each book closes, and writing the whole index then made changing books
    -- and quitting wait about 12 seconds (1.1.47). It is written as the
    -- device goes to sleep and as KOReader quits or restarts (below), in the
    -- background; the library kept in memory is the one Home shows meanwhile,
    -- and a scan puts right an index that missed a write.
end
-- KOReader quits or restarts: the index, when it has changes not written
-- yet, is written by a background process that finishes on its own.
-- With a book open, after it closes (onCloseDocument), so its new state is
-- in; from Home or the file browser, at once.
function Board:onExit()
    quitting = true
    if not (self.ui and self.ui.document) then saveIndexLater() end
end
Board.onRestart = Board.onExit
return Board
