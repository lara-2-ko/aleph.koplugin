-- Quick Top Bar, built into Aleph: the Controls and Apps tabs of KOReader's
-- top menu. Aleph starts it for the file browser and the reader unless it is
-- switched off in Aleph's settings (Settings > Top menu) or the standalone
-- quicktopbar plugin is enabled, which then keeps the top menu.
local Apps = require("aleph_topbar_apps")
local Book = require("aleph_topbar_book")
local Device = require("device")
local Event = require("ui/event")
local FocusManager = require("ui/widget/focusmanager")
local GestureRange = require("ui/gesturerange")
local IconWidget = require("ui/widget/iconwidget")
local Icons = require("aleph_topbar_icons")
local NetworkMgr = require("ui/network/manager")
local Panel = require("aleph_topbar_panel")
local MenuStyle = require("aleph_topbar_menu_style")
local Style = require("aleph_topbar_style")
local TouchMenu = require("ui/widget/touchmenu")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local Screen = Device.screen
local settings_key = "quicktopbar"
local QuickTopBar = WidgetContainer:extend{ name = "quicktopbar" }

function QuickTopBar:read(key, default)
    local settings = G_reader_settings:readSetting(settings_key)
    if type(settings) == "table" and settings[key] ~= nil then return settings[key] end
    return default
end

function QuickTopBar:save(key, value)
    local settings = G_reader_settings:readSetting(settings_key)
    if type(settings) ~= "table" then settings = {} end
    settings[key] = value
    G_reader_settings:saveSetting(settings_key, settings)
end

function QuickTopBar:iconPath(key, default)
    return Icons.path(self.path, self:read(key), default)
end

function QuickTopBar:chooseIcon(menu, key, label, default)
    Icons.show(self.path, label, self:read(key), default, function(value)
        self:save(key, value)
        menu:updateItems()
    end)
end

function QuickTopBar:isAppHidden(key)
    local hidden = self:read("hidden_apps")
    return type(hidden) == "table" and hidden[key] == true
end

function QuickTopBar:setAppHidden(key, hide)
    local hidden = self:read("hidden_apps")
    if type(hidden) ~= "table" then hidden = {} end
    hidden[key] = hide and true or nil
    self:save("hidden_apps", hidden)
end

-- A held app in the Apps tab: change its icon or hide it, in a sheet.
function QuickTopBar:appTileOptions(menu, item)
    require("aleph_topmenu_page").appOptions(self.path, item, function()
        if menu and menu.item_table then menu:updateItems() end
    end)
end

local function send(name, ...)
    UIManager:broadcastEvent(Event:new(name, ...))
end

function QuickTopBar:controls(menu)
    local tiles, power = {}, Device:getPowerDevice()
    local frontlight, warmth = Device:hasFrontlight(), Device:hasNaturalLight()
    local function refresh()
        if self.ui.menu.menu_container and self.ui.menu.menu_container[1] == menu
                and menu._qtb_panel and menu.item_table.id == "quicktopbar_controls"
                and not menu._qtb_panel.dragging then
            menu:updateItems()
        end
    end
    local function add(key, label, active, tap)
        tiles[#tiles + 1] = { key = key, icon = key, label = label, active = active, tap = tap }
    end
    if Device:hasWifiToggle() then
        local active = NetworkMgr:isWifiOn()
        local network = active and NetworkMgr:getCurrentNetwork()
        local label = network and network.ssid
        if type(label) ~= "string" or label == "" then label = _("Wi-Fi") end
        add("wifi", label, active, function()
            if NetworkMgr:isWifiOn() then NetworkMgr:toggleWifiOff(refresh, true)
            else NetworkMgr:toggleWifiOn(refresh, false, true) end
            refresh()
        end)
    end
    add("night", _("Night"), G_reader_settings:isTrue("night_mode"), function()
        self.ui:handleEvent(Event:new("ToggleNightMode"))
        refresh()
    end)
    add("rotate", _("Rotate"), false, function()
        menu:closeMenu()
        self.ui:handleEvent(Event:new("IterateRotation"))
    end)
    if frontlight then
        add("light", _("Light"), function() return power:isFrontlightOn() end, function()
            power:toggleFrontlight(refresh)
            refresh()
        end)
    end
    add("restart", _("Restart"), false, function()
        require("aleph_confirm").show{
            title = _("Restart KOReader?"), text = _("Open books and settings are saved first."), ok_label = _("Restart"),
            on_ok = function()
                menu:closeMenu()
                send("Restart")
            end,
        }
    end)
    add("exit", _("Exit"), false, function()
        menu:closeMenu()
        send("Exit")
    end)
    if not frontlight then return tiles end

    local show_warmth = warmth and self.show_warmth
    local slider = {}
    if show_warmth then
        slider.label, slider.min, slider.max = _("Warmth"), power.fl_warmth_min, power.fl_warmth_max
        slider.style = self:read("warmth_style", "knob")
        slider.get = function() return power:toNativeWarmth(power:frontlightWarmth()) end
        slider.set = function(value) power:setWarmth(power:fromNativeWarmth(value)) end
    else
        slider.label, slider.min, slider.max = _("Brightness"), power.fl_min, power.fl_max
        slider.style = self:read("brightness_style", "knob")
        slider.get = function() return power:frontlightIntensity() end
        slider.set = function(value) power:setIntensity(value) end
    end
    slider.value = math.max(slider.min, math.min(slider.max, slider.get()))
    if warmth then
        slider.warmth = not not show_warmth
        slider.switch = function(use_warmth)
            if slider.warmth ~= use_warmth then
                self.show_warmth = use_warmth
                refresh()
            end
        end
    end
    return tiles, slider
end

function QuickTopBar:apps(menu, page, per_page, target_item)
    local tab, tiles, visible = menu.item_table, {}, {}
    for index, item in ipairs(tab) do
        if not self:isAppHidden(item.icon_key) then visible[#visible + 1] = index end
    end
    local offset = self.ui.document and self.ui.document.file and 1 or 0
    menu.page_num = offset + math.max(1, math.ceil(#visible / per_page))
    if target_item then
        for position, index in ipairs(visible) do
            local item = tab[index]
            if item.menu_item_id == target_item or item.icon_key == target_item then
                page = offset + math.ceil(position / per_page)
                break
            end
        end
    end
    menu.page = math.max(1, math.min(menu.page_num, page or menu.page or 1))
    if menu.page <= offset then return nil end
    local start = (menu.page - offset - 1) * per_page + 1
    for position = start, math.min(start + per_page - 1, #visible) do
        local index = visible[position]
        local item = tab[index]
        local function disabled()
            if item.unavailable then return true end
            if item.enabled_func then return item.enabled_func() == false end
            return item.enabled == false
        end
        tiles[#tiles + 1] = {
            key = item.icon_key, icon = "app", label = item.launcher_label,
            dim = disabled(),
            tap = function()
                if disabled() then return end
                item.idx = index
                menu:onMenuSelect(item)
            end,
            hold = function() self:appTileOptions(menu, item) end,
        }
    end
    return tiles
end

function QuickTopBar:bookSummary()
    return Book.summary(self.ui)
end

function QuickTopBar:openBookDetails(menu)
    local document = self.ui.document
    menu:closeMenu()
    UIManager:nextTick(function()
        if self.ui.document == document and not self.ui.tearing_down then
            Book.showDetails(self.ui)
        end
    end)
end

local function topbarOwner(menu)
    local first = menu.tab_item_table and menu.tab_item_table[1]
    return first and first.quicktopbar_owner
end

-- Every tab of the top menu is drawn with an icon in Aleph's style.
-- The two QuickTopBar tabs keep the icon chosen for them; KOReader's own tabs
-- get the matching bundled icon.
local TAB_ICONS = {
    ["appbar.filebrowser"] = "tab-filebrowser", ["appbar.navigation"] = "tab-navigation",
    ["appbar.typeset"] = "tab-typeset", ["appbar.settings"] = "tab-settings",
    ["appbar.tools"] = "tab-tools", ["appbar.search"] = "tab-search", ["appbar.menu"] = "tab-menu",
    ["appbar.aleph"] = "tab-aleph",
}

local function refreshTabIcons(menu, plugin)
    local owners = { "controls", "apps" }
    for i, tab in ipairs(menu.tab_item_table) do
        local button = menu.bar.icon_widgets[i]
        local file
        if i <= #owners and tab.quicktopbar_owner then
            file = plugin:iconPath("tab_" .. owners[i], owners[i])
        elseif TAB_ICONS[tab.icon] then
            file = Style.icon(plugin.path, TAB_ICONS[tab.icon])
        end
        if button and file and button.image.file ~= file then
            button.image:free()
            button.image = IconWidget:new{ file = file, width = button.width, height = button.height, alpha = true }
            button.horizontal_group[2] = button.image
        end
    end
end

-- KOReader sizes the tab icons (and with them the whole tab bar) from one
-- constant, 48 at its base scale, which is large next to Aleph's
-- header icons. While the menu is built, that one size is answered with
-- Aleph's, so the icons and the bar come out smaller together.
local function withSmallerTabIcons(build)
    local ok, full = pcall(function() return G_defaults:readSetting("DGENERIC_ICON_SIZE") end)
    full = ok and full or 48
    local own = rawget(Screen, "scaleBySize")
    local original = Screen.scaleBySize
    Screen.scaleBySize = function(screen, size)
        if size == full then return Style.px(26) end
        return original(screen, size)
    end
    local built, err = pcall(build)
    Screen.scaleBySize = own
    if not built then error(err, 0) end
end

local function installTouchMenu()
    if TouchMenu.quicktopbar_installed then return end
    TouchMenu.quicktopbar_installed = true

    local init = TouchMenu.init
    function TouchMenu:init()
        local plugin = topbarOwner(self)
        if plugin then
            MenuStyle.prepare(self)
            if not self.last_index or self.last_index < 1 then self.last_index = 1 end
            withSmallerTabIcons(function() init(self) end)
        else
            init(self)
        end
        if not plugin then return end
        self.ges_events.QuickTopBarHold = {
            GestureRange:new{ ges = "hold", range = self.dimen },
        }
        self.ges_events.QuickTopBarRelease = {
            GestureRange:new{ ges = "pan_release", range = self.screen_size },
        }
    end

    local update = TouchMenu.updateItems
    function TouchMenu:updateItems(page, target_item)
        local plugin = topbarOwner(self)
        if not plugin then return update(self, page, target_item) end
        self._qtb_panel = nil

        MenuStyle.install(self, plugin)
        refreshTabIcons(self, plugin)

        if not self.item_table.quicktopbar_owner then
            -- Keep custom font previews and change only the regular row text.
            local changed = {}
            for _, item in ipairs(self.item_table) do
                if not item.font_func then
                    changed[#changed + 1] = item
                    item.font_func = Style.rowFace
                end
            end
            local ok, err = pcall(update, self, page, target_item)
            for _, item in ipairs(changed) do item.font_func = nil end
            if not ok then error(err, 0) end
            MenuStyle.styleRows(self, plugin)
            MenuStyle.setPageLabel(self)
            return
        end

        local old = self.dimen:copy()
        self.item_group:clear()
        self._qtb_panel = Panel:new{ menu = self, plugin = plugin, target_page = page, target_item = target_item }
        self.item_group[1], self.item_group[2] = self.bar, self._qtb_panel
        self.item_group[3], self.item_group[4] = self.footer_top_margin, self.footer
        self.layout = { self.bar.icon_widgets }
        MenuStyle.setPageLabel(self)
        self.page_info_left_chev:showHide(self.page_num > 1)
        self.page_info_right_chev:showHide(self.page_num > 1)
        self.page_info_left_chev:enableDisable(self.page > 1)
        self.page_info_right_chev:enableDisable(self.page < self.page_num)
        self.dimen.w = self.width
        self.dimen.h = self.item_group:getSize().h + self.bordersize * 2 + self.padding
        self:moveFocusTo(self.cur_tab, 1, FocusManager.NOT_FOCUS)
        local fresh = self.is_fresh
        self.is_fresh = false
        UIManager:setDirty((fresh or self.dimen.h >= old.h) and self.show_parent or "all", function()
            return fresh and "flashui" or "ui", old:combine(self.dimen)
        end)
    end

    -- The Aleph tab is a button: it opens Aleph's settings
    -- instead of a list of its own.
    local switch = TouchMenu.switchMenuTab
    function TouchMenu:switchMenuTab(tab_num, ...)
        local tab = self.tab_item_table and self.tab_item_table[tab_num]
        if tab and tab.aleph_button then
            local open = tab.aleph_button
            if self.closeMenu then self:closeMenu() elseif self.close_callback then self.close_callback() end
            UIManager:nextTick(open)
            return
        end
        return switch(self, tab_num, ...)
    end

    local handlers = { TapCloseAllMenus = "tap", Pan = "pan", Swipe = "swipe",
        QuickTopBarHold = "hold", QuickTopBarRelease = "release" }
    for name, kind in pairs(handlers) do
        local method = "on" .. name
        local original = TouchMenu[method]
        TouchMenu[method] = function(self, arg, gesture)
            if gesture and self._qtb_panel and self._qtb_panel:handle(kind, gesture) then return true end
            if original then return original(self, arg, gesture) end
        end
    end
end

local function installMenuClass(class)
    if class.quicktopbar_installed then return end
    class.quicktopbar_installed = true
    local build = class.setUpdateItemTable
    function class:setUpdateItemTable(...)
        local plugin = self.quicktopbar_plugin
        if not plugin then return build(self, ...) end
        local captured = Apps.capture(self, build, ...)
        local apps = Apps.build(self, captured)
        Apps.order(apps, plugin:read("app_order"))
        apps.quicktopbar_owner = plugin
        table.insert(self.tab_item_table, 1, apps)
        table.insert(self.tab_item_table, 1, {
            id = "quicktopbar_controls", icon = "appbar.settings", quicktopbar_owner = plugin,
        })
        -- In a book: Aleph's settings, one tap away, just before
        -- KOReader's main menu tab.
        if self.ui and self.ui.document then
            local at = #self.tab_item_table + 1
            for i, tab in ipairs(self.tab_item_table) do
                if tab.icon == "appbar.menu" then at = i; break end
            end
            table.insert(self.tab_item_table, at, {
                id = "aleph_settings", icon = "appbar.aleph",
                aleph_button = function() QuickTopBar.openBoardSettings(self.ui) end,
            })
        end
    end
end

-- Aleph's settings over the book: the board opens underneath and
-- closes with them, so Back returns to the page.
function QuickTopBar.openBoardSettings(ui)
    local board = ui and ui.aleph
    if not board then
        local ok, found = pcall(function() return require("pluginloader"):getPluginInstance("aleph") end)
        board = ok and found or nil
    end
    if not board or not board.onShowAleph then return end
    local was_open = board.browser and not board.browser.closed
    board:onShowAleph()
    local browser = board.browser
    if not browser then return end
    local ok, page = pcall(function() return require("aleph_settings_page").open(browser) end)
    if not ok then
        require("logger").warn("Aleph: settings from the top bar failed:", page)
        return
    end
    if page and not was_open then
        local previous = page.on_close
        page.on_close = function(p)
            if previous then previous(p) end
            if not browser.closed then browser:onClose() end
        end
    end
end

function QuickTopBar:init()
    if not self.ui or not self.ui.menu then return end
    installTouchMenu()
    local class = self.ui.document and require("apps/reader/modules/readermenu")
        or require("apps/filemanager/filemanagermenu")
    installMenuClass(class)
    self.ui.menu.quicktopbar_plugin = self
    self.ui.menu.tab_item_table = nil
    -- Its settings are in Aleph's: Settings > Top menu (aleph_topmenu_page.lua),
    -- not an entry of their own in KOReader's menu.
end

-- ---------------------------------------------------- Aleph hooks
-- True when the standalone Quick Top Bar plugin is enabled in KOReader.
function QuickTopBar.standalone()
    local ok, enabled = pcall(function() return (require("pluginloader"):loadPlugins()) end)
    for _i, plugin in ipairs(ok and enabled or {}) do
        if plugin.name == "quicktopbar" then return true end
    end
    return false
end

function QuickTopBar.wanted(board)
    return board.settings.topbar ~= false and not QuickTopBar.standalone()
end

-- Adds the Controls and Apps tabs to the top menu of the book or file browser
-- Aleph is running in. The tabs appear the next time the menu opens.
function QuickTopBar.start(board)
    local ui = board.ui
    if not (ui and ui.menu) or ui.menu.quicktopbar_plugin then return end
    board._topbar = QuickTopBar:new{ ui = ui, path = board.path }
end

function QuickTopBar.stop(board)
    local ui = board.ui
    local plugin = board._topbar
    board._topbar = nil
    if not (ui and ui.menu) then return end
    if plugin and ui.menu.registered_widgets then
        for index = #ui.menu.registered_widgets, 1, -1 do
            if ui.menu.registered_widgets[index] == plugin then table.remove(ui.menu.registered_widgets, index) end
        end
    end
    ui.menu.quicktopbar_plugin = nil
    ui.menu.tab_item_table = nil
end

-- Switches it on or off to match the setting (and the standalone plugin).
function QuickTopBar.sync(board)
    if QuickTopBar.wanted(board) then QuickTopBar.start(board) else QuickTopBar.stop(board) end
end

return QuickTopBar
