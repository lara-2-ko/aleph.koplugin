local WidgetContainer = require("ui/widget/container/widgetcontainer")
local UIManager = require("ui/uimanager")
local Dispatcher = require("dispatcher")
local Board = WidgetContainer:extend{name="aleph", is_doc_only=false}

-- Opening the board over the file browser, at startup and after a book is
-- closed. Done the way ZenOS takes over the browser: a class-level hook on
-- FileManager:showFiles, which KOReader calls every time it builds the file
-- browser (the first time at startup, again whenever a book is closed). The
-- browser is put on screen inside showFiles, so what is shown right after it
-- lands on top of it. Nothing here waits or guesses: it acts on the browser
-- KOReader has just built.
local logger = require("logger")

-- Settings, library index and cache from the plugin's old name
-- (readingboard.koplugin), moved before anything reads them.
pcall(function() require("aleph_migrate").run() end)
-- KOReader's own windows in Aleph's style (Settings > Opening > Aleph dialogs).
do
    local ok, err = pcall(function() require("aleph_theme").sync() end)
    if not ok then logger.warn("Aleph: theme not applied:", err) end
end

local function wantsBoard()
    local stored = G_reader_settings:readSetting("aleph")
    return type(stored) == "table" and stored.open_home == true
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
    if not fm or fm._aleph_opened or not wantsBoard() then return end
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
    local ok, err = pcall(plugin.onShowAleph, plugin)
    if not ok then
        logger.warn("Aleph: could not open over the file browser:", err)
        UIManager:show(require("ui/widget/infomessage"):new{ text = "Aleph could not open at startup:\n" .. tostring(err) })
    end
end

local FileManager = require("apps/filemanager/filemanager")
if not FileManager._aleph_hooked then
    FileManager._aleph_hooked = true
    local original_showFiles = FileManager.showFiles
    function FileManager:showFiles(...)
        local result = original_showFiles(self, ...)
        openOver(FileManager.instance)
        return result
    end
end

-- KOReader's "Opening file" message in the board's style. (The search prompt is
-- the board's own; the highlight sheet is installed when a book is open.)
local ok_opening, opening_err = pcall(function() require("aleph_opening").install() end)
if not ok_opening then logger.warn("Aleph: opening card not installed:", opening_err) end

-- The reader controls gain a Background tab; it is added here, at load, because
-- KOReader reads its option list when a book opens.
local ok_tab, tab_err = pcall(function() require("aleph_config").installOptions() end)
if not ok_tab then logger.warn("Aleph: Background tab not added:", tab_err) end

function Board:init()
    self.settings = G_reader_settings:readSetting("aleph", {})
    if not self.settings.library_roots then
        local home = G_reader_settings:readSetting("home_dir")
        self.settings.library_roots = home and {home} or {}
    end
    -- Aleph on the first page of Tools, below calibre.
    pcall(function() require("aleph_menu_pin").ensure() end)
    self.ui.menu:registerToMainMenu(self)
    -- The top menu's Controls and Apps tabs (settings: Opening > Quick top bar).
    local ok_bar, bar_err = pcall(function() require("aleph_topbar").sync(self) end)
    if not ok_bar then logger.warn("Aleph: Quick Top Bar not started:", bar_err) end
    Dispatcher:registerAction("aleph_open", {category="none", event="ShowAleph", title="Aleph: open", general=true})
    Dispatcher:registerAction("aleph_pins", {category="none", event="ShowAlephPins", title="Aleph: pinned pages", reader=true})
    Dispatcher:registerAction("aleph_page_browser", {category="none", event="ShowAlephPageBrowser", title="Aleph: page browser", reader=true})
    Dispatcher:registerAction("aleph_this_book", {category="none", event="ShowAlephThisBook", title="Aleph: this book", reader=true})
    -- Gestures bound to the old action names, and the old folder left installed.
    local ui = self.ui
    UIManager:nextTick(function()
        pcall(function() require("aleph_migrate").gestures(ui) end)
        pcall(function() require("aleph_migrate").warnOldFolder(ui) end)
        -- ZenOS replaces the same screens: say so (Aleph runs as usual).
        pcall(function() require("aleph_conflicts").check(ui) end)
    end)
    -- The first file browser of a session is being built while this runs, before
    -- the hook above can see its showFiles finish: open over it as soon as it is
    -- shown. (Later ones are covered by the hook.)
    if not self.ui.document then
        local fm = self.ui
        UIManager:nextTick(function() openOver(fm) end)
    else
        -- In a book. Each step is logged before and after it runs: if the
        -- reader ever stops here, the last "Aleph: reader" line in
        -- koreader/crash.log names the step that did not finish.
        local function step(name, fn)
            logger.info("Aleph: reader step " .. name)
            local ok, err = pcall(fn)
            if not ok then logger.warn("Aleph: " .. name .. " not installed:", err) end
            logger.info("Aleph: reader step " .. name .. " done")
        end
        step("highlight", function() require("aleph_highlight").install() end)
        step("dictionary", function() require("aleph_dictionary").install() end)
        step("details", function() require("aleph_bookmark").install() end)
        step("page browser", function() require("aleph_page_browser").install() end)
        step("reader menu", function() require("aleph_reader_sheet").install() end)
        -- Stats at the top and bottom of the pages, and their minute tick.
        step("bookends", function()
            local Bookends = require("aleph_bookends")
            Bookends.install()
            Bookends.attach(self.ui)
        end)
        for _i, name in ipairs({ "aleph_menu_skin", "aleph_imageviewer", "aleph_config" }) do
            step(name, function() require(name).install() end)
        end
        self.ui:registerPostInitCallback(function()
            logger.info("Aleph: reader step saved background")
            pcall(function() require("aleph_config").applySaved(self.ui) end)
            logger.info("Aleph: reader step saved background done")
        end)
        -- Pinned pages: the Pin button, the pictures menu, and (only when the
        -- book has pins) the badge.
        step("pins", function()
            local Pins = require("aleph_pins")
            Pins.install()
            Pins.attach(self.ui)
        end)
    end
end
function Board:addToMainMenu(items)
    items.aleph = {text="Aleph", callback=function() self:onShowAleph() end}
    -- In a book, where the pin badge sits (and the side its drawer opens on),
    -- right under Aleph in Tools.
    if self.ui.document then
        items.aleph_pin_badge = {text="Pin badge position", callback=function()
            require("aleph_pins").openPlacer(self.ui)
        end}
        items.aleph_bookends = {text="Book margins (top and bottom stats)", callback=function()
            require("aleph_bookends_page").open(self.ui)
        end}
    end
end
function Board:onShowAleph()
    if self.browser and not self.browser.closed then return true end
    self.browser = require("aleph_browser"):new{plugin=self,settings=self.settings}
    UIManager:show(self.browser)
    self.browser:startScan()
    return true
end
-- The board's page for a book, over the reader. True when it was shown.
function Board:showBookPage(path)
    if not path then return false end
    if self.browser and not self.browser.closed then return false end
    local browser = require("aleph_browser"):new{plugin=self,settings=self.settings}
    if not browser:openBookPage(path) then
        browser:onClose()
        return false
    end
    self.browser = browser
    UIManager:show(browser)
    return true
end
function Board:onFileManagerReady()
    if not self.ui.document then openOver(self.ui) end
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

function Board:onRBSetPageBackground(index)
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
    pcall(function() require("aleph_bookends").applyStock(self.ui) end)
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
function Board:onShowAlephPins()
    if not self.ui.document then return false end
    require("aleph_pins").openList(self.ui)
    return true
end
function Board:onCloseDocument()
    pcall(function() require("aleph_bookends").detach(self.ui) end)
    pcall(function() require("aleph_pins").detach(self.ui) end)
    if self.ui.doc_settings then
        require("aleph_chapter_map").remember(self.ui, self.ui.doc_settings:readSetting("partial_md5_checksum"))
    end
    require("aleph_board_data").invalidateLocal()
end
-- KOReader's Exit and Restart close the file browser, and KOReader quits when
-- nothing is left on screen. The board is a screen of its own over the file
-- browser, so it (and any page, sheet or panel of it) is closed with it; left
-- open it would keep KOReader running until it was closed by hand.
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
end
return Board
