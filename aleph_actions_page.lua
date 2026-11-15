-- Aleph modification, 2026-11-10: the page to choose what the Quick settings
-- buttons and the widgets do (aleph_actions.lua).
--[[--
Settings > Widget actions. Two tabs:

  Quick settings  the widget's buttons, up to five. Tap one to change what
                  it does, its icon or its name, or to remove it; Add a
                  button; Reset to the usual five.
  Widget taps     every widget, with what a tap on it opens. Tap one to
                  choose: its usual page, nothing, or any action.

Choosing an action opens a list in two tabs, Aleph (its own) and KOReader
(KOReader's and every installed plugin's gesture actions), with a search.
Choosing an icon opens a grid of Aleph's icons, with a search.
]]

local Device = require("device")
local UIManager = require("ui/uimanager")
local T = require("ffi/util").template
local _ = require("gettext")

local Actions = require("aleph_actions")
local BoardMetrics = require("aleph_board_metrics")
local BoardUI = require("aleph_board_ui")
local MenuPage = require("aleph_menu_page")
local MenuUI = require("aleph_menu_ui")
local SheetUI = require("aleph_sheet_ui")
local try = require("aleph_try").call

local INK = BoardMetrics.INK
local px = BoardMetrics.px
local text, vstack, hstack, space, flex, icon = BoardUI.text, BoardUI.vstack, BoardUI.hstack, BoardUI.space, BoardUI.flex, BoardUI.icon
local floor = math.floor

local Page = {}

local function hasLight()
    local ok, on = pcall(function() return Device:hasFrontlight() end)
    return ok and on and true or false
end

local function turn(page, delta)
    local to = math.max(1, math.min(page.count or 1, (page.index or 1) + delta))
    if to == page.index then return end
    page.index = to
    page:refresh(Device:hasEinkScreen() and "partial" or "ui")
end

local function pager(w, page)
    if (page.count or 1) <= 1 then return space(nil, px(40)) end
    return require("aleph_text_pages").pager(w, page.index, page.count)
end

-- Rows that fit in `avail`, in pages: sets page.count, returns this page's.
local function paged(page, rows, avail, row_h)
    local per = math.max(1, floor(avail / row_h))
    page.count = math.max(1, math.ceil(#rows / per))
    page.index = math.max(1, math.min(page.index or 1, page.count))
    local out = {}
    for i = (page.index - 1) * per + 1, math.min(#rows, page.index * per) do out[#out + 1] = rows[i] end
    return out
end

-- A search line under the header while a filter is set.
local function filterLine(w, filter, count)
    return hstack({ w = w, h = px(40), gap = px(10) }, {
        text(T(_("“%1”: %2"), filter, count), { s = 14, col = INK.g4, data = true }),
        flex(0),
        MenuUI.pill(_("Clear"), { kind = "outline", h = 34, s = 13, pad_x = 12, icon = "x", icon_size = 14, action = { kind = "clear" } }),
    })
end

local function askFilter(page, title)
    require("aleph_input").prompt{
        title = title, text = page.filter, ok_label = _("Search"),
        on_ok = function(value)
            page.filter, page.index = tostring(value or ""):lower(), 1
            page:refresh()
        end,
    }
end

-- ------------------------------------------------------------ the pickers
-- Every action, in two tabs. o: title, current, widget (adds Default and
-- Nothing, with default_label naming the usual page), on_select(id).
function Page.pickAction(o)
    local page = MenuPage:new{
        name = "aleph_actions_pick",
        tab = (o.current and o.current:sub(1, 3) == "ko:") and "ko" or "aleph",
        index = 1, filter = "",
        build = function(page, sw, sh)
            local mx = MenuUI.mx()
            local w = sw - 2 * mx
            local iw = MenuUI.rowsIn(w)
            local search = MenuUI.iconButton("search", { kind = "filter" }, { size = 22, sw = 2.25 })
            local header = MenuUI.pageHeader(w, o.title, { sub = _("Choose an action"), right = search, right_inset = MenuUI.tapInset(22) })
            local tabs = MenuUI.segmented(w, { _("Aleph"), _("KOReader and plugins") }, page.tab == "ko" and 2 or 1,
                function(i) return { kind = "tab", tab = i == 2 and "ko" or "aleph" } end)
            local list = {}
            if page.tab == "aleph" then
                if o.widget then
                    list[#list + 1] = { id = "default", label = _("Default"), sub = o.default_label }
                    list[#list + 1] = { id = "none", label = _("Nothing"), sub = _("A tap does nothing") }
                end
                for _i, a in ipairs(Actions.ALEPH) do
                    list[#list + 1] = { id = a.id, label = a.label(), sub = a.sub and a.sub() or nil, icon = a.icon }
                end
            else
                list = Actions.koreader()
            end
            local shown = {}
            for _i, a in ipairs(list) do
                if page.filter == "" or a.label:lower():find(page.filter, 1, true) then shown[#shown + 1] = a end
            end
            local rows = {}
            for _i, a in ipairs(shown) do
                rows[#rows + 1] = MenuUI.row(iw, { icon = a.icon, label = a.label, sub = a.sub, sub_data = true, data = true, h = 60,
                    radio = a.id == o.current, action = { kind = "pick", id = a.id } })
            end
            local top = { header, space(nil, px(8)), tabs, space(nil, px(10)) }
            if page.filter ~= "" then top[#top + 1] = filterLine(w, page.filter, #shown); top[#top + 1] = space(nil, px(8)) end
            local used = 0
            for _i, it in ipairs(top) do used = used + it:getSize().h end
            local avail = sh - px(6) - px(8) - used - px(48) - px(24)
            local body
            if #rows == 0 then
                local msg = page.tab == "ko" and page.filter == "" and _("KOReader did not list any actions.") or _("No action has that name.")
                body = vstack({ w = w, h = px(120) }, { flex(0), text(msg, { s = 15, col = INK.g4, w = w, align = "center" }), flex(0) })
            else
                body = MenuUI.group(w, paged(page, rows, avail, px(60) + MenuUI.hair()))
            end
            local items = top
            items[#items + 1] = vstack({ w = w, h = avail + px(24) }, { body, flex(0) })
            items[#items + 1] = pager(w, page)
            return vstack({ w = sw, h = sh, pad = { px(6), mx, px(8), mx } }, items)
        end,
        on_action = function(page, action)
            local k = action.kind
            if k == "pick" then page:close(); o.on_select(action.id)
            elseif k == "tab" then page.tab, page.index = action.tab, 1; page:refresh()
            elseif k == "page" then turn(page, action.delta)
            elseif k == "clear" then page.filter, page.index = "", 1; page:refresh()
            elseif k == "filter" then askFilter(page, _("Search actions"))
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

-- Aleph's icons in a grid. on_select(name).
local icon_names
local function iconNames()
    if icon_names then return icon_names end
    local names = {}
    try(function()
        for name in pairs(require("aleph_icon_data")) do
            if not name:match("^bo%-") then names[#names + 1] = name end
        end
    end)
    table.sort(names)
    icon_names = names
    return names
end

function Page.pickIcon(title, current, on_select)
    local page = MenuPage:new{
        name = "aleph_actions_icon",
        index = 1, filter = "",
        build = function(page, sw, sh)
            local mx = MenuUI.mx()
            local w = sw - 2 * mx
            local search = MenuUI.iconButton("search", { kind = "filter" }, { size = 22, sw = 2.25 })
            local header = MenuUI.pageHeader(w, title, { sub = _("Choose an icon"), right = search, right_inset = MenuUI.tapInset(22) })
            local shown = {}
            for _i, name in ipairs(iconNames()) do
                if page.filter == "" or name:find(page.filter, 1, true) then shown[#shown + 1] = name end
            end
            local top = { header, space(nil, px(8)) }
            if page.filter ~= "" then top[#top + 1] = filterLine(w, page.filter, #shown); top[#top + 1] = space(nil, px(8)) end
            local used = 0
            for _i, it in ipairs(top) do used = used + it:getSize().h end
            local gap = px(10)
            local avail = sh - px(6) - px(8) - used - px(48)
            local cols = math.max(3, math.min(6, floor((w + gap) / (px(96) + gap))))
            local cw = floor((w - (cols - 1) * gap) / cols)
            local ch = math.min(px(96), cw)
            local rows_n = math.max(1, floor((avail + gap) / (ch + gap)))
            local per = cols * rows_n
            page.count = math.max(1, math.ceil(#shown / per))
            page.index = math.max(1, math.min(page.index, page.count))
            local grid, line = {}, {}
            local first = (page.index - 1) * per + 1
            local last = math.min(#shown, first + per - 1)
            for n = first, last do
                local name = shown[n]
                local on = name == current
                local inner = vstack({ w = cw, h = ch, align = "center" }, {
                    flex(0),
                    hstack({ w = cw }, { flex(0), icon(name, px(30), { sw = 2 }), flex(0) }),
                    space(nil, px(6)),
                    text(name, { s = 11, b = on, w = cw - px(10), align = "center", data = true }),
                    flex(0),
                })
                local tile = BoardUI.box({ w = cw, h = ch, radius = px(12), border = on and math.max(2, px(2.5)) or MenuUI.line(),
                    border_col = on and INK.black or INK.g8, bg = INK.white }, inner)
                line[#line + 1] = BoardUI.hit(tile, { kind = "pick", name = name })
                if #line == cols or n == last then
                    if #grid > 0 then grid[#grid + 1] = space(nil, gap) end
                    grid[#grid + 1] = hstack({ gap = gap }, line)
                    line = {}
                end
            end
            if #shown == 0 then
                grid[1] = vstack({ w = w, h = px(120) }, { flex(0), text(_("No icon has that name."), { s = 15, col = INK.g4, w = w, align = "center" }), flex(0) })
            end
            local items = top
            items[#items + 1] = vstack({ w = w, h = avail }, { vstack({ w = w }, grid), flex(0) })
            items[#items + 1] = space(nil, px(8))
            items[#items + 1] = pager(w, page)
            return vstack({ w = sw, h = sh, pad = { px(6), mx, px(8), mx } }, items)
        end,
        on_action = function(page, action)
            local k = action.kind
            if k == "pick" then page:close(); on_select(action.name)
            elseif k == "page" then turn(page, action.delta)
            elseif k == "clear" then page.filter, page.index = "", 1; page:refresh()
            elseif k == "filter" then askFilter(page, _("Search icons"))
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

-- ------------------------------------------------------- a button's sheet
local function buttonGlyph(b, size)
    return BoardUI.circle(px(size), { bg = INK.white, border = math.max(1, px(1.5)) },
        icon(Actions.buttonIcon(b), floor(px(size) * 0.46 + 0.5), { sw = 2.25 }))
end

local function editButton(main, index)
    local function current()
        local list = Actions.buttons(hasLight())
        return list, list[index]
    end
    local function save(list)
        Actions.saveButtons(list)
        main.changed = true
        main:refresh()
    end
    return SheetUI.open{
        name = "aleph_actions_button",
        build = function(sheet, sw, sh)
            return SheetUI.sheet(sheet, sw, sh, function(w)
                local list, b = current()
                if not b then return { SheetUI.titleRow(w, _("Button")) } end
                local iw = MenuUI.rowsIn(w)
                local pills = { { label = _("Remove"), icon = "trash", kind = "outline", action = { kind = "remove" } } }
                if index > 1 then pills[#pills + 1] = { label = _("Earlier"), icon = "chevron-left", kind = "outline", action = { kind = "move", delta = -1 } } end
                if index < #list then pills[#pills + 1] = { label = _("Later"), icon = "chevron-right", kind = "outline", action = { kind = "move", delta = 1 } } end
                return {
                    SheetUI.titleRow(w, T(_("Button %1"), index), _("Quick settings")),
                    hstack({ w = w, h = px(72) }, { flex(0), buttonGlyph(b, 52), space(px(14), 1),
                        text(Actions.buttonLabel(b), { s = 16, b = true, data = true }), flex(0) }),
                    MenuUI.group(w, {
                        MenuUI.row(iw, { icon = "zap", label = _("Action"), sub = Actions.label(b.action) or _("Missing"), sub_data = true, chevron = true, action = { kind = "action" } }),
                        MenuUI.row(iw, { icon = "palette", label = _("Icon"), sub = b.icon and Actions.buttonIcon(b) or _("The action's own"), sub_data = true, chevron = true, action = { kind = "icon" } }),
                        MenuUI.row(iw, { icon = "pen-line", label = _("Name"), sub = (b.label and b.label ~= "") and b.label or _("The action's own"), sub_data = true, chevron = true, action = { kind = "name" } }),
                    }),
                    SheetUI.pillRow(w, pills),
                }
            end, { pop_w = 520 })
        end,
        on_action = function(sheet, action)
            local list, b = current()
            if not b then sheet:close(); return true end
            local k = action.kind
            if k == "action" then
                Page.pickAction{ title = T(_("Button %1"), index), current = b.action, on_select = function(id)
                    list[index].action = id
                    save(list); sheet:refresh()
                end }
            elseif k == "icon" then
                Page.pickIcon(T(_("Button %1"), index), Actions.buttonIcon(b), function(name)
                    list[index].icon = name
                    save(list); sheet:refresh()
                end)
            elseif k == "name" then
                require("aleph_input").prompt{
                    title = _("Button name"), text = b.label or "", hint = Actions.label(b.action), ok_label = _("Save"),
                    on_ok = function(value)
                        value = tostring(value or ""):match("^%s*(.-)%s*$")
                        list[index].label = value ~= "" and value or nil
                        save(list); sheet:refresh()
                    end,
                }
            elseif k == "remove" then
                table.remove(list, index)
                if #list == 0 then Actions.resetButtons(); main.changed = true; main:refresh() else save(list) end
                sheet:close()
            elseif k == "move" then
                local to = index + action.delta
                list[index], list[to] = list[to], list[index]
                save(list)
                sheet:close()
            end
            return true
        end,
    }
end

-- ----------------------------------------------------------- the main page
-- Every widget that can be put on the board, once each.
local function widgetEntries()
    local out, seen = {}, {}
    for _i, entry in ipairs(require("aleph_board_edit").LIBRARY) do
        local key = Actions.widgetKey(entry)
        if not seen[key] then
            seen[key] = true
            out[#out + 1] = { key = key, name = entry.name(), type = entry.type, props = entry.props }
        end
    end
    return out
end

-- What a widget opens by itself, in words.
local USUAL = {
    hero = function() return _("Your current book") end, forecast = function() return _("Your current book") end,
    chapters = function() return _("Your current book") end, also = function() return _("Books in progress") end,
    highlight = function() return _("The highlight") end, shelf = function() return _("Its books") end,
    link = function() return _("Its page") end, word = function() return _("The dictionary") end,
    silverfish = function() return _("Silverfish") end, goalpace = function() return _("Books finished this year") end,
    dust = function() return _("The book") end, yearago = function() return _("The book") end,
    streak = function() return _("Reading insights") end, heatmap = function() return _("Reading insights") end,
    week = function() return _("Reading insights") end, today = function() return _("Reading insights") end,
    records = function() return _("Reading insights") end, hours = function() return _("Reading insights") end,
    calendar = function() return _("Reading insights") end,
}
local function usualOf(t) return USUAL[t] and USUAL[t]() or _("Nothing") end

local function buttonsBody(page, w, avail)
    local iw = MenuUI.rowsIn(w)
    local list, custom = Actions.buttons(hasLight())
    local rows = {}
    for i, b in ipairs(list) do
        rows[#rows + 1] = MenuUI.row(iw, { icon = buttonGlyph(b, 34), label = Actions.buttonLabel(b), data = true,
            sub = Actions.label(b.action) or _("Its plugin is no longer installed"), sub_data = true, h = 64,
            trail = icon("pen-line", px(20), { sw = 2 }), action = { kind = "button", index = i } })
    end
    local more = {}
    if #list < Actions.MAX_BUTTONS then
        more[#more + 1] = MenuUI.row(iw, { icon = "plus", label = _("Add a button"), sub = T(_("Up to %1"), Actions.MAX_BUTTONS), action = { kind = "add" } })
    end
    if custom then
        more[#more + 1] = MenuUI.row(iw, { icon = "rotate-ccw", label = _("Reset"), sub = _("Wi-Fi, Light, Night, Rotate and Sync / Refresh"), action = { kind = "reset" } })
    end
    local items = { MenuUI.group(w, rows) }
    if #more > 0 then items[#items + 1] = space(nil, px(14)); items[#items + 1] = MenuUI.group(w, more) end
    items[#items + 1] = space(nil, px(10))
    items[#items + 1] = text(_("The buttons of the Quick settings widget. An action from KOReader or a plugin runs as its gesture does."), { s = 13, col = INK.g4, w = w, lines = 3 })
    page.count, page.index = 1, 1
    return items
end

local function widgetsBody(page, w, avail)
    local iw = MenuUI.rowsIn(w)
    local rows = {}
    for _i, e in ipairs(widgetEntries()) do
        local chosen = Actions.widgetTap(e.key)
        local sub
        if chosen == "default" then sub = T(_("Default: %1"), usualOf(e.type))
        else sub = Actions.label(chosen) or _("Its plugin is no longer installed") end
        rows[#rows + 1] = MenuUI.row(iw, { label = e.name, sub = sub, sub_data = true, h = 60, value_bold = chosen ~= "default",
            chevron = true, action = { kind = "widget", key = e.key, name = e.name, type = e.type } })
    end
    return { MenuUI.group(w, paged(page, rows, avail - px(16), px(60) + MenuUI.hair())) }
end

function Page.open(browser)
    Actions.forget()
    local page
    page = MenuPage:new{
        name = "aleph_actions_page",
        tab = "buttons", index = 1,
        build = function(p, sw, sh)
            local mx = MenuUI.mx()
            local w = sw - 2 * mx
            local header = MenuUI.pageHeader(w, _("Widget actions"), { sub = _("Settings") })
            local tabs = MenuUI.segmented(w, { _("Quick settings"), _("Widget taps") }, p.tab == "widgets" and 2 or 1,
                function(i) return { kind = "tab", tab = i == 2 and "widgets" or "buttons" } end)
            local used = header:getSize().h + px(8) + tabs:getSize().h + px(12)
            local avail = sh - px(6) - px(8) - used - px(48)
            local body = p.tab == "widgets" and widgetsBody(p, w, avail) or buttonsBody(p, w, avail)
            local items = { header, space(nil, px(8)), tabs, space(nil, px(12)) }
            items[#items + 1] = vstack({ w = w, h = avail }, { vstack({ w = w }, body), flex(0) })
            items[#items + 1] = pager(w, p)
            return vstack({ w = sw, h = sh, pad = { px(6), mx, px(8), mx } }, items)
        end,
        on_action = function(p, action)
            local k = action.kind
            if k == "tab" then p.tab, p.index = action.tab, 1; p:refresh()
            elseif k == "page" then turn(p, action.delta)
            elseif k == "button" then editButton(p, action.index)
            elseif k == "add" then
                Page.pickAction{ title = _("New button"), on_select = function(id)
                    local list = Actions.buttons(hasLight())
                    list[#list + 1] = { action = id }
                    Actions.saveButtons(list)
                    p.changed = true
                    p:refresh()
                end }
            elseif k == "reset" then
                Actions.resetButtons(); p.changed = true; p:refresh()
            elseif k == "widget" then
                Page.pickAction{ title = action.name, current = Actions.widgetTap(action.key), widget = true,
                    default_label = usualOf(action.type), on_select = function(id)
                        Actions.setWidgetTap(action.key, id)
                        p.changed = true
                        p:refresh()
                    end }
            end
            return true
        end,
        on_swipe = function(p, ges)
            if ges.direction == "west" and p.tab == "widgets" then turn(p, 1) return true end
            if ges.direction == "east" and p.tab == "widgets" then turn(p, -1) return true end
            return false
        end,
        on_page_key = function(p, delta) turn(p, delta) end,
        on_close = function(p)
            -- The board shows the new buttons and taps.
            if p.changed and browser and not browser.closed then pcall(function() browser:updateItems() end) end
        end,
    }
    UIManager:show(page, "ui")
    return page
end

return Page
