-- Aleph modification, 2026-11-09: the top menu's settings in Aleph's style.
--[[--
The Controls and Apps tabs Aleph adds to KOReader's top menu (the Quick Top
Bar) were set up from an entry of their own in KOReader's menu, with
KOReader's widgets: a plain grid to pick icons, KOReader's sort list to order
apps, a button dialog on a held app. They are set up from Aleph's settings
now (Settings > Top menu), on pages like the rest of Aleph:

  TopMenu.pickIcon     a page of icons, with a filter and pages
  TopMenu.openApps     every app: shown or hidden, its icon, its place
  TopMenu.appOptions   a held app in the Apps tab: change its icon, hide it

The values are the Quick Top Bar's own (G_reader_settings "quicktopbar"),
so nothing is lost from before.
]]

local Device = require("device")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local T = require("ffi/util").template

local BoardMetrics = require("aleph_board_metrics")
local BoardUI = require("aleph_board_ui")
local MenuPage = require("aleph_menu_page")
local MenuUI = require("aleph_menu_ui")

local INK = BoardMetrics.INK
local px = BoardMetrics.px
local text, vstack, hstack, space, flex = BoardUI.text, BoardUI.vstack, BoardUI.hstack, BoardUI.space, BoardUI.flex
local floor = math.floor

local TopMenu = {}

-- ------------------------------------------------------------- settings
local KEY = "quicktopbar"

function TopMenu.read(key, default)
    local stored = G_reader_settings:readSetting(KEY)
    if type(stored) == "table" and stored[key] ~= nil then return stored[key] end
    return default
end

function TopMenu.save(key, value)
    local stored = G_reader_settings:readSetting(KEY)
    if type(stored) ~= "table" then stored = {} end
    stored[key] = value
    G_reader_settings:saveSetting(KEY, stored)
end

function TopMenu.isHidden(key)
    local hidden = TopMenu.read("hidden_apps")
    return type(hidden) == "table" and hidden[key] == true
end

function TopMenu.setHidden(key, hide)
    local hidden = TopMenu.read("hidden_apps")
    if type(hidden) ~= "table" then hidden = {} end
    hidden[key] = hide and true or nil
    TopMenu.save("hidden_apps", hidden)
end

function TopMenu.hiddenCount()
    local n = 0
    for _k, on in pairs(TopMenu.read("hidden_apps") or {}) do if on then n = n + 1 end end
    return n
end

function TopMenu.iconFile(root, key, default)
    return require("aleph_topbar_icons").path(root, TopMenu.read(key), default)
end

-- The Apps tab's list (every plugin with a menu entry), built the way the
-- top menu builds it when it has not been opened yet. Empty when the tabs
-- are off.
function TopMenu.apps(ui)
    local menu = ui and ui.menu
    if not (menu and menu.quicktopbar_plugin) then return {} end
    if not menu.tab_item_table then pcall(menu.setUpdateItemTable, menu) end
    for _i, tab in ipairs(menu.tab_item_table or {}) do
        if tab.id == "quicktopbar_apps" then return tab end
    end
    return {}
end

-- A picture file (SVG or PNG) at size x size, as KOReader draws icons.
local function picture(file, size)
    return require("ui/widget/iconwidget"):new{ file = file, width = size, height = size, alpha = true }
end
TopMenu.picture = picture

-- ----------------------------------------------------------- shared page
local function turn(page, delta)
    local next_index = math.max(1, math.min(page.count or 1, page.index + delta))
    if next_index == page.index then return end
    page.index = next_index
    page:refresh(Device:hasEinkScreen() and "partial" or "ui")
end

local function pager(w, page)
    if (page.count or 1) <= 1 then return space(nil, px(40)) end
    return require("aleph_text_pages").pager(w, page.index, page.count)
end

-- ---------------------------------------------------------- icon picker
-- on_select(value): value is what Icons.path reads (nil for the default).
function TopMenu.pickIcon(root, title, value, default, on_select)
    local Icons = require("aleph_topbar_icons")
    local items = Icons.items(root, default)
    local selected = Icons.path(root, value, default)
    local page = MenuPage:new{
        name = "aleph_topmenu_icons",
        index = 1,
        filter = "",
        build = function(page, sw, sh)
            local mx = MenuUI.mx()
            local w = sw - 2 * mx
            local top, bottom = px(6), px(8)
            local search = MenuUI.iconButton("search", { kind = "filter" }, { size = 22, sw = 2.25 })
            local header = MenuUI.pageHeader(w, title, { sub = _("Top menu"), right = search, right_inset = MenuUI.tapInset(22) })
            local shown = {}
            for _i, item in ipairs(items) do
                if page.filter == "" or item.text:lower():find(page.filter, 1, true) then shown[#shown + 1] = item end
            end
            local head_items = { header, space(nil, px(8)) }
            if page.filter ~= "" then
                head_items[#head_items + 1] = hstack({ w = w, h = px(40), gap = px(10) }, {
                    text(T(_("Names with “%1”: %2"), page.filter, #shown), { s = 14, col = INK.g4, data = true }),
                    flex(0),
                    MenuUI.pill(_("Clear"), { kind = "outline", h = 34, s = 13, pad_x = 12, icon = "x", icon_size = 14, action = { kind = "clear" } }),
                })
                head_items[#head_items + 1] = space(nil, px(8))
            end
            local head_h = 0
            for _i, it in ipairs(head_items) do head_h = head_h + it:getSize().h end
            local gap = px(10)
            local avail = sh - top - bottom - head_h - px(8) - px(40)
            local cols = math.max(3, math.min(6, floor((w + gap) / (px(104) + gap))))
            local cw = floor((w - (cols - 1) * gap) / cols)
            local ch = math.min(px(112), cw)
            local rows = math.max(1, floor((avail + gap) / (ch + gap)))
            local per = cols * rows
            page.count = math.max(1, math.ceil(#shown / per))
            page.index = math.max(1, math.min(page.index, page.count))
            local grid = {}
            if #shown == 0 then
                grid[1] = vstack({ w = w, h = px(120) }, { flex(0), text(_("No icon has that name."), { s = 15, col = INK.g4, w = w, align = "center" }), flex(0) })
            end
            local first = (page.index - 1) * per + 1
            local line = {}
            for n = first, math.min(#shown, first + per - 1) do
                local item = shown[n]
                local on = item.icon_file == selected
                local glyph = math.min(px(40), floor(ch * 0.42))
                local inner = vstack({ w = cw, h = ch, align = "center" }, {
                    flex(0),
                    hstack({ w = cw, h = glyph }, { flex(0), picture(item.icon_file, glyph), flex(0) }),
                    space(nil, px(8)),
                    text(item.text, { s = 12, b = on, w = cw - 2 * px(8), align = "center", data = true }),
                    flex(0),
                })
                local border = on and math.max(2, px(2.5)) or MenuUI.line()
                local tile = BoardUI.overlay(cw, ch, {
                    { widget = BoardUI.box({ w = cw, h = ch, radius = px(12), border = border, border_col = on and INK.black or INK.g8, bg = INK.white }) },
                    { widget = inner, x = 0, y = 0 },
                    on and { widget = MenuUI.check(), x = cw - px(8) - px(24), y = px(8) } or {},
                })
                line[#line + 1] = BoardUI.hit(tile, { kind = "pick", value = item.icon_value })
                if #line == cols or n == math.min(#shown, first + per - 1) then
                    if #grid > 0 then grid[#grid + 1] = space(nil, gap) end
                    grid[#grid + 1] = hstack({ gap = gap, valign = "top" }, line)
                    line = {}
                end
            end
            local items_ = head_items
            items_[#items_ + 1] = vstack({ w = w, h = avail }, { vstack({ w = w }, grid), flex(0) })
            items_[#items_ + 1] = space(nil, px(8))
            items_[#items_ + 1] = pager(w, page)
            return vstack({ w = sw, h = sh, pad = { top, mx, bottom, mx } }, items_)
        end,
        on_action = function(page, action)
            if action.kind == "pick" then
                page:close()
                on_select(action.value)
            elseif action.kind == "page" then
                turn(page, action.delta)
            elseif action.kind == "clear" then
                page.filter, page.index = "", 1
                page:refresh()
            elseif action.kind == "filter" then
                require("aleph_input").prompt{
                    title = _("Filter icons by name"), text = page.filter, hint = _("Icon name"), ok_label = _("Filter"),
                    on_ok = function(value)
                        page.filter, page.index = tostring(value or ""):lower(), 1
                        page:refresh()
                    end,
                }
            end
            return true
        end,
        on_swipe = function(page, ges)
            if ges.direction == "west" then turn(page, 1) return true end
            if ges.direction == "east" then turn(page, -1) return true end
            return false
        end,
        on_page_key = function(page, delta) turn(page, delta) end,
    }
    UIManager:show(page, "ui")
    return page
end

-- ------------------------------------------------------------- the apps
-- Every app of the Apps tab: tap shows or hides it, the pencil changes its
-- icon; in Order, the arrows move it.
function TopMenu.openApps(ui, root, on_close)
    local function saveOrder(tab)
        local order = {}
        for _i, item in ipairs(tab) do order[#order + 1] = item.icon_key end
        TopMenu.save("app_order", order)
    end
    local page = MenuPage:new{
        name = "aleph_topmenu_apps",
        index = 1,
        mode = "show",
        on_close = on_close,
        build = function(page, sw, sh)
            local tab = TopMenu.apps(ui)
            local mx = MenuUI.mx()
            local w = sw - 2 * mx
            local iw = MenuUI.rowsIn(w)
            local top, bottom = px(6), px(8)
            local hidden = 0
            for _i, item in ipairs(tab) do if TopMenu.isHidden(item.icon_key) then hidden = hidden + 1 end end
            local header = MenuUI.pageHeader(w, _("Apps"), { sub = T(_("Top menu · %1 of %2 shown"), #tab - hidden, #tab) })
            local modes = MenuUI.segmented(w, { _("Show and icons"), _("Order") }, page.mode == "order" and 2 or 1,
                function(index) return { kind = "mode", value = index == 2 and "order" or "show" } end)
            local note = text(page.mode == "order" and _("The arrows move an app up or down the Apps tab.")
                or _("Tap an app to show or hide it in the Apps tab. The pencil changes its icon."), { s = 13, col = INK.g4, w = w, lines = 2 })
            local fixed = top + bottom + header:getSize().h + px(8) + modes:getSize().h + px(10) + note:getSize().h + px(10) + px(8) + px(40)
            local avail = sh - fixed
            local row_h = px(60)
            local per = math.max(1, floor((avail - px(8)) / (row_h + MenuUI.hair())))
            page.count = math.max(1, math.ceil(#tab / per))
            page.index = math.max(1, math.min(page.index, page.count))
            local rows = {}
            local first = (page.index - 1) * per + 1
            for n = first, math.min(#tab, first + per - 1) do
                local item = tab[n]
                local key = item.icon_key
                local glyph = picture(TopMenu.iconFile(root, key, "app"), px(24))
                local label = item.launcher_label or item.text or key
                if page.mode == "order" then
                    local up = n > 1 and MenuUI.iconButton("arrow-up", { kind = "move", at = n, delta = -1 }, { size = 20, sw = 2.25 })
                        or hstack({ w = px(44), h = px(44) }, {})
                    local down = n < #tab and MenuUI.iconButton("arrow-down", { kind = "move", at = n, delta = 1 }, { size = 20, sw = 2.25 })
                        or hstack({ w = px(44), h = px(44) }, {})
                    rows[#rows + 1] = MenuUI.row(iw, { icon = glyph, label = n .. ". " .. label, data = true, h = 60,
                        trail = hstack({ gap = px(2) }, { up, down }) })
                else
                    local shown = not TopMenu.isHidden(key)
                    rows[#rows + 1] = MenuUI.row(iw, { icon = glyph, label = label, data = true, h = 60,
                        sub = item.unavailable and _("Not available now") or nil,
                        trail = MenuUI.iconButton("pencil", { kind = "icon", key = key, label = label }, { size = 19, sw = 2.25 }),
                        toggle = shown, action = { kind = "toggle", key = key } })
                end
            end
            local body = #rows > 0 and MenuUI.group(w, rows)
                or MenuUI.card(w, { space(nil, px(12)), text(_("Turn on the Controls and Apps tabs first."), { s = 14, w = iw }), space(nil, px(12)) })
            return vstack({ w = sw, h = sh, pad = { top, mx, bottom, mx } }, {
                header, space(nil, px(8)), modes, space(nil, px(10)), note, space(nil, px(10)),
                vstack({ w = w, h = avail }, { body, flex(0) }),
                space(nil, px(8)), pager(w, page),
            })
        end,
        on_action = function(page, action)
            local k = action.kind
            if k == "page" then turn(page, action.delta)
            elseif k == "mode" then
                if page.mode ~= action.value then page.mode = action.value; page:refresh() end
            elseif k == "toggle" then
                TopMenu.setHidden(action.key, not TopMenu.isHidden(action.key))
                page:refresh()
            elseif k == "icon" then
                TopMenu.pickIcon(root, action.label, TopMenu.read(action.key), "app", function(value)
                    TopMenu.save(action.key, value)
                    if not page.closed then page:refresh() end
                end)
            elseif k == "move" then
                local tab = TopMenu.apps(ui)
                local a, b = action.at, action.at + action.delta
                if tab[a] and tab[b] then
                    tab[a], tab[b] = tab[b], tab[a]
                    saveOrder(tab)
                    page:refresh()
                end
            end
            return true
        end,
        on_swipe = function(page, ges)
            if ges.direction == "west" then turn(page, 1) return true end
            if ges.direction == "east" then turn(page, -1) return true end
            return false
        end,
        on_page_key = function(page, delta) turn(page, delta) end,
    }
    UIManager:show(page, "ui")
    return page
end

-- ---------------------------------------------------------- a held app
-- on_change(): after the icon changed or the app was hidden.
function TopMenu.appOptions(root, item, on_change)
    local SheetUI = require("aleph_sheet_ui")
    local label = item.launcher_label or item.text or item.icon_key
    return SheetUI.open{
        name = "aleph_topmenu_app",
        build = function(page, sw, sh)
            return SheetUI.sheet(page, sw, sh, function(w)
                local iw = MenuUI.rowsIn(w)
                return {
                    SheetUI.titleRow(w, label, _("Apps tab")),
                    MenuUI.group(w, {
                        MenuUI.row(iw, { icon = "pencil", label = _("Change icon"), chevron = true, action = { kind = "icon" } }),
                        MenuUI.row(iw, { icon = "eye-off", label = _("Hide app"), sub = _("Shown again from Aleph's settings, Top menu"), action = { kind = "hide" } }),
                    }),
                }
            end)
        end,
        on_action = function(page, action)
            if action.kind == "icon" then
                page:close()
                TopMenu.pickIcon(root, label, TopMenu.read(item.icon_key), "app", function(value)
                    TopMenu.save(item.icon_key, value)
                    if on_change then on_change() end
                end)
            elseif action.kind == "hide" then
                page:close()
                TopMenu.setHidden(item.icon_key, true)
                if on_change then on_change() end
            end
            return true
        end,
    }
end

return TopMenu
