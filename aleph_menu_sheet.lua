-- Modified for Aleph, 2026-11-07. Unofficial local-only fork. See NOTICE.
--[[--
The Aleph menu: the sheet the menu button opens on every page.

Adapted from BookOrbit's menu sheet. Where you are, the three things done
most (customize or go Home, History, leave), every place in the library with
its count, then Settings and About. A full-width sheet from the top on phones
and 6-7" readers; a popover under the button on tablets and in landscape.
Built from the local library, so opening it never waits.
]]

local datetime = require("datetime")
local _ = require("gettext")
local T = require("ffi/util").template

local BoardMetrics = require("aleph_board_metrics")
local BoardUI = require("aleph_board_ui")
local MenuPage = require("aleph_menu_page")
local MenuUI = require("aleph_menu_ui")

local INK = BoardMetrics.INK
local px = BoardMetrics.px
local text, vstack, hstack, flex, space, icon = BoardUI.text, BoardUI.vstack, BoardUI.hstack, BoardUI.flex, BoardUI.space, BoardUI.icon

local MenuSheet = {}

local NAV = {
    { link = "library", icon = "book-copy", label = function() return _("Library") end, count = "library" },
    { link = "authors", icon = "feather", label = function() return _("Authors") end, count = "authors" },
    { link = "series", icon = "layers-2", label = function() return _("Series") end, count = "series" },
    { link = "collections", icon = "folder-open", label = function() return _("Collections") end, count = "collections" },
    { link = "genres", icon = "tag", label = function() return _("Genres") end, count = "genres" },
    { link = "history", icon = "clock", label = function() return _("History") end, count = "history" },
}

-- Which Go to entry the browser is showing, so the sheet can mark it.
local function currentPlace(browser)
    if browser.mode == "library" then
        local p = browser.params or {}
        if p.series then return "series" end
        if p.author then return "authors" end
        if p.genre then return "genres" end
        if p.ids and p.sort == "last_read" then return "history" end
        if p.search or p.ids then return nil end
        return "library"
    end
    return nil
end

local function count(list)
    return list and #list or nil
end

function MenuSheet.data(browser)
    local lib = browser.local_library
    local opened = 0
    for _i, b in ipairs(lib.books) do if (b.last_open or 0) > 0 then opened = opened + 1 end end
    local on_home = browser.mode == "home"
    return {
        name = _("Dashboard"),
        clock = datetime.secondsToHour(os.time(), G_reader_settings:isTrue("twelve_hour_clock")),
        books = #lib.books,
        counts = {
            library = #lib.books,
            authors = count(lib:groups("authors")),
            series = count(lib:groups("series")),
            collections = count(lib:collections()),
            genres = count(lib:genres()),
            history = opened,
        },
        on_home = on_home,
        place = currentPlace(browser),
        version = require("aleph_prefs").VERSION,
    }
end

local function tile(w, h, glyph, label, sub, action, data)
    local pad = px(14)
    local iw = w - 2 * pad
    local inner = vstack({ w = iw, h = h }, {
        flex(0),
        icon(glyph, px(24), { sw = 2 }),
        space(nil, px(6)),
        text(label, { s = 15, b = true, w = iw }),
        text(sub, { s = 12, col = INK.g4, w = iw, data = data }),
        flex(0),
    })
    return BoardUI.hit(MenuUI.card(w, { inner }, { pad = 14 }), action)
end

local function navGrid(w, d, ncols)
    local pad = px(16)
    local iw = w - 2 * pad
    local gap = px(24)
    local cw = math.floor((iw - (ncols - 1) * gap) / ncols)
    local rh = px(50)
    local rows = {}
    for start = 1, #NAV, ncols do
        local cells = {}
        for index = start, math.min(#NAV, start + ncols - 1) do
            local entry = NAV[index]
            local here = d.place == entry.link or (d.place == "shelves" and (entry.link == "collections" or entry.link == "scopes"))
            local count = d.counts[entry.count]
            local right = here and MenuUI.chip(_("Here"), { h = 22 })
                or text(count and tostring(count) or "", { s = 14, col = INK.g4 })
            local label_w = cw - px(20) - 2 * px(12) - right:getSize().w
            local label_s = BoardUI.fitSize(entry.label(), { s = 15, b = here }, label_w, 13)
            -- In a narrow cell the Here tag gives way; the bold label and
            -- icon still mark the current place.
            if here and text(entry.label(), { s = label_s, b = true }):getSize().w > label_w then
                right = space(1, 1)
                label_w = cw - px(20) - 2 * px(12) - 1
                label_s = BoardUI.fitSize(entry.label(), { s = 15, b = true }, label_w, 13)
            end
            local cell = hstack({ w = cw, h = rh, gap = px(12) }, {
                icon(entry.icon, px(20), { sw = here and 2.5 or 2 }),
                text(entry.label(), { s = label_s, b = here, w = label_w }),
                right,
            })
            table.insert(cells, BoardUI.hit(cell, { kind = "link", link = entry.link }))
        end
        if #rows > 0 then table.insert(rows, BoardUI.rect(iw, MenuUI.hair(), INK.gb)) end
        table.insert(rows, hstack({ w = iw, h = rh, gap = gap }, cells))
    end
    local card = MenuUI.card(w, rows)
    local layers = { { widget = card } }
    local h = card:getSize().h
    for k = 1, ncols - 1 do
        table.insert(layers, { widget = BoardUI.rect(MenuUI.hair(), h - 2 * px(10), INK.gb), x = pad + k * cw + math.floor((k - 0.5) * gap), y = px(10) })
    end
    return BoardUI.overlay(w, h, layers)
end

-- The sheet's content at width w. o.popover drops the status cluster and
-- search (the page behind keeps them in view); o.cols lays places out wider.
function MenuSheet.body(d, w, o)
    o = o or {}
    local inset = MenuUI.tapInset(24)
    local sub = { { t = T(_("%1 on this device"), d.books == 1 and _("1 book") or T(_("%1 books"), d.books)) } }
    local right = {}
    if not o.popover then
        table.insert(right, BoardUI.statusCluster(d))
        table.insert(right, space(px(6), 1))
        table.insert(right, MenuUI.iconButton("search", { kind = "search" }))
    end
    table.insert(right, MenuUI.iconButton("x", { kind = "close" }))
    local right_group = hstack({}, right)
    local title_w = w - right_group:getSize().w + inset
    local header = hstack({ w = w + inset, h = px(64) }, {
        vstack({ w = title_w }, {
            text(d.name, { s = 22, b = true, w = title_w }),
            BoardUI.runs(sub, { s = 13, col = INK.g4, w = title_w, data = true }),
        }),
        right_group,
    })

    local gap = px(10)
    local tw = math.floor((w - 2 * gap) / 3)
    local th = px(o.popover and 80 or 84)
    local first = d.on_home and tile(tw, th, "layout-grid", _("Customize"), _("Edit this board"), { kind = "customize" })
        or tile(tw, th, "house", _("Home"), _("Your board"), { kind = "home" })
    local second = tile(tw, th, "clock", _("History"), _("Books you opened"), { kind = "link", link = "history" })
    local last_w = w - 2 * tw - 2 * gap
    local third = tile(last_w, th, "folder-open", _("Files"), _("Close Aleph"), { kind = "exit" })
    local tiles = hstack({ w = w, gap = gap }, { first, second, third })

    -- side_rows: a short screen sets the rows beside Go to, not under it.
    local nav_w = o.side_rows and math.floor((w - px(20)) * 0.6) or w
    local rows_w = o.side_rows and (w - nav_w - px(20)) or w
    local iw = MenuUI.rowsIn(rows_w)
    local rows = {
        MenuUI.row(iw, { icon = "sliders-horizontal", label = _("Settings"),
            sub = not o.side_rows and _("Opening, layout, goal, interface size") or nil, chevron = true, action = { kind = "settings" } }),
        MenuUI.row(iw, { icon = "circle-help", label = _("About"),
            sub = not o.side_rows and T(_("Version %1 · legal notices"), d.version) or nil, chevron = true, action = { kind = "about" } }),
    }

    return {
        BoardUI.overlay(w, px(64), { { widget = header, x = 0, y = 0 } }),
        space(nil, px(8)),
        tiles,
        space(nil, px(16)),
        o.side_rows and hstack({ w = w, gap = px(20), valign = "top" }, {
            MenuUI.section(nav_w, _("Go to"), navGrid(nav_w, d, 2)),
            -- Level with the Go to grid under its label.
            vstack({ w = rows_w }, { space(nil, MenuUI.label(rows_w, _("Go to")):getSize().h + px(8)), MenuUI.group(rows_w, rows) }),
        }) or MenuUI.section(w, _("Go to"), navGrid(w, d, o.cols or 2)),
        not o.side_rows and space(nil, px(16)) or false,
        not o.side_rows and MenuUI.group(w, rows) or false,
    }
end

-- Builds the whole screen: the sheet or popover over the lightened backdrop.
local function build(page, sw, sh)
    local d = page.sheet_data
    local mx = MenuUI.mx()
    if MenuUI.wide() then
        local pw = math.min(px(MenuUI.landscape() and 620 or 460), sw - 2 * mx)
        local pad = px(18)
        local function contentFor(width, side_rows)
            return vstack({ w = width - 2 * MenuUI.line(), pad = { px(4), pad - MenuUI.line(), pad, pad - MenuUI.line() } },
                MenuSheet.body(d, width - 2 * pad, { popover = true, cols = MenuUI.landscape() and 3 or 2, side_rows = side_rows }))
        end
        local mark = BoardUI.hitMark()
        local content = contentFor(pw, false)
        -- Taller than a short, wide screen: wider, with the rows beside Go to.
        if content:getSize().h + 2 * MenuUI.line() > sh - px(16) and MenuUI.landscape() then
            content:free()
            BoardUI.hitTrim(mark)
            pw = math.min(math.floor(pw * 1.5 + 0.5), sw - 2 * mx)
            content = contentFor(pw, true)
        end
        local ph = content:getSize().h + 2 * MenuUI.line()
        local panel = BoardUI.box({ w = pw, h = ph, radius = px(16), border = math.max(1, px(1.5)), border_col = INK.black, bg = INK.white }, content)
        -- Under the button it came from: top right on Home and on the lists,
        -- raised as far as it needs to stay on a short screen.
        local x = sw - mx - pw
        local y = math.max(px(8), math.min(px(52), sh - px(8) - ph))
        page.panel_rect = require("ui/geometry"):new{ x = x, y = y, w = pw, h = ph }
        return BoardUI.overlay(sw, sh, { { widget = panel, x = x, y = y } })
    end
    local w = sw - 2 * mx
    local content = vstack({ w = sw, pad = { px(6), mx, px(18), mx } }, MenuSheet.body(d, w))
    local ph = content:getSize().h
    local line = math.max(1, px(1.5))
    local r = px(16)
    -- Square at the top edge, rounded at the bottom with a black rule along it.
    local layers = {
        { widget = BoardUI.rect(sw, ph, INK.black, r) },
        { widget = BoardUI.rect(sw, r, INK.black) },
        { widget = BoardUI.rect(sw, ph - line, INK.white, r) },
        { widget = BoardUI.rect(sw, r, INK.white) },
        { widget = content },
    }
    page.panel_rect = require("ui/geometry"):new{ x = 0, y = 0, w = sw, h = ph }
    return BoardUI.overlay(sw, sh, layers)
end

-- on_action(page, action) runs everything the sheet does not do itself.
function MenuSheet.open(browser, on_action)
    local page = MenuPage:new{
        name = "aleph_menu_sheet",
        backdrop = true,
        dismiss_outside = true,
        build = build,
        on_action = on_action,
        sheet_data = MenuSheet.data(browser),
    }
    require("ui/uimanager"):show(page, "ui")
    return page
end

return MenuSheet
