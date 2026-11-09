-- Modified for Aleph, 2026-11-07. Unofficial local-only fork. See NOTICE.
--[[--
Aleph settings: one level deep, every value visible where it is
changed. The root lists the groups with their current values and each group
is one page.

Adapted from BookOrbit's settings page (its layout, rows, toggles and
segmented controls) with the server, sync and download groups left out and a
Profile group for the user's name and yearly goal added. The shortcut picker
(Opening > Shortcut) is BookOrbit's, binding "Aleph: open".
]]

local Device = require("device")
local Geom = require("ui/geometry")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local T = require("ffi/util").template

local BoardMetrics = require("aleph_board_metrics")
local BoardStore = require("aleph_board_store")
local BoardUI = require("aleph_board_ui")
local MenuPage = require("aleph_menu_page")
local MenuUI = require("aleph_menu_ui")
local Shortcut = require("aleph_shortcut")

local INK = BoardMetrics.INK
local px = BoardMetrics.px
local text, vstack, hstack, flex, space, icon = BoardUI.text, BoardUI.vstack, BoardUI.hstack, BoardUI.flex, BoardUI.space, BoardUI.icon

local Settings = {}

local VERSION = require("aleph_prefs").VERSION
local PRESETS = { "reader", "stats", "library" }
local TILES = { "outline", "soft", "ink" }
local COLOURS = BoardStore.COLOURS

local function scaleLabel(value)
    return string.format("%.2f", value):gsub("0$", "") .. "x"
end

local function indexOf(list, value, fallback)
    for index, v in ipairs(list) do
        if v == value then return index end
    end
    return fallback
end

local function folderName(path)
    local name = tostring(path or ""):gsub("/+$", ""):match("([^/]+)$")
    return name or path
end

local PRESET_LABELS = { reader = function() return _("Reader") end, stats = function() return _("Stats") end, library = function() return _("Library") end }

-- ------------------------------------------------------------- summaries
local function portraitsSummary(settings)
    if not settings.author_portraits then return _("Off") end
    local ok, Portraits = pcall(require, "aleph_portraits")
    local n = ok and Portraits.count() or 0
    return n == 1 and _("On, 1 portrait") or T(_("On, %1 portraits"), n)
end

local function shortcutLabel(page)
    local g = Shortcut.find(Shortcut.current(page.gestures_data))
    return g and g.label() or _("no shortcut")
end

local function openingSummary(settings, page)
    local first = settings.open_home and _("Opens when the file browser starts") or _("Open it from KOReader's menu")
    if not page or not Device:isTouchDevice() then return first end
    return first .. " · " .. shortcutLabel(page)
end

local function homeSummary(settings)
    local state = BoardStore.read(settings)
    return T(_("%1 layout, %2 size"),
        (PRESET_LABELS[state.preset] or PRESET_LABELS.reader)(),
        scaleLabel(BoardMetrics.normalizeUserScale(settings.ui_scale)))
end

local function profileSummary(settings)
    local name = settings.display_name
    local goal = tonumber(settings.year_goal) or 12
    local goal_text = T(_("%1 books a year"), goal)
    if name and name ~= "" then return name .. " · " .. goal_text end
    return goal_text
end

local function libraryRoots(settings)
    return settings.library_roots or {}
end

local function librarySummary(settings)
    local roots = libraryRoots(settings)
    if #roots == 0 then return _("No folders yet") end
    if #roots == 1 then return folderName(roots[1]) end
    return T(_("%1 folders"), #roots)
end

local function marginsSummary()
    local ok, text_ = pcall(function()
        local Bookends = require("aleph_bookends")
        if not Bookends.enabledHere() then return _("Off") end
        local c = Bookends.config()
        local parts = {}
        if c.top then parts[#parts + 1] = _("top") end
        if c.bottom then parts[#parts + 1] = _("bottom") end
        if #parts == 0 then return _("Nothing shown") end
        return T(_("Stats at the %1 of pages"), table.concat(parts, _(" and ")))
    end)
    return ok and text_ or ""
end

-- The top menu's Controls and Apps tabs (the built-in Quick Top Bar).
local function topbarState(settings)
    local standalone = false
    pcall(function() standalone = require("aleph_topbar").standalone() end)
    return settings.topbar ~= false and not standalone, standalone
end

local function topMenuSummary(settings)
    local on, standalone = topbarState(settings)
    if standalone then return _("Kept by the separate Quick Top Bar plugin") end
    if not on then return _("KOReader's own top menu") end
    local hidden = require("aleph_topmenu_page").hiddenCount()
    if hidden == 0 then return _("Controls and Apps tabs · every app shown") end
    return T(_("Controls and Apps tabs · %1 apps hidden"), hidden)
end

local CATEGORIES = {
    { id = "profile", icon = "circle-user-round", label = function() return _("Profile") end, sub = function(page) return profileSummary(page.browser.settings) end },
    { id = "opening", icon = "door-open", label = function() return _("Opening Aleph") end, sub = function(page) return openingSummary(page.browser.settings, page) end },
    { id = "topmenu", icon = "panel-top", label = function() return _("Top menu") end, sub = function(page) return topMenuSummary(page.browser.settings) end },
    { id = "home", icon = "layout-grid", label = function() return _("Home") end, sub = function(page) return homeSummary(page.browser.settings) end },
    { id = "library", icon = "library", label = function() return _("Library folders") end, sub = function(page) return librarySummary(page.browser.settings) end },
    { id = "margins", icon = "file-text", label = function() return _("Book margins") end, sub = function() return marginsSummary() end },
    { id = "portraits", icon = "user-round", label = function() return _("Author portraits") end, sub = function(page) return portraitsSummary(page.browser.settings) end },
}

local function titleOf(view)
    for _i, cat in ipairs(CATEGORIES) do
        if cat.id == view then return cat.label() end
    end
    if view == "about" then return _("About") end
    if view == "shortcut" then return _("Shortcut") end
    return _("Settings")
end

-- ----------------------------------------------------------------- lists
local function settingsList(page, w)
    local iw = MenuUI.rowsIn(w)
    local rows = {}
    for _i, cat in ipairs(CATEGORIES) do
        table.insert(rows, MenuUI.row(iw, {
            icon = cat.icon, label = cat.label(), sub = cat.sub(page), sub_data = true,
            chevron = true, action = { kind = "view", view = cat.id },
        }))
    end
    return {
        MenuUI.group(w, rows),
        space(nil, px(16)),
        MenuUI.section(w, _("Help"), MenuUI.group(w, {
            MenuUI.row(iw, { icon = "circle-help", label = _("About"),
                sub = T(_("Version %1 · legal notices"), VERSION), chevron = true, action = { kind = "view", view = "about" } }),
        })),
    }
end

-- ---------------------------------------------------------------- bodies
local function segRow(w, label, sub, options, selected, action_for, tight)
    local pad = px(tight and 8 or 12)
    return vstack({ w = w, pad = { pad, 0, pad, 0 } }, {
        text(label, { s = 16, w = w }),
        sub and text(sub, { s = 13, col = INK.g4, w = w }) or false,
        space(nil, px(8)),
        MenuUI.segmented(w, options, selected, action_for),
    })
end

local function profileBody(page, w)
    local settings = page.browser.settings
    local iw = MenuUI.rowsIn(w)
    local name = settings.display_name
    local goal = tonumber(settings.year_goal) or 12
    return {
        MenuUI.group(w, {
            MenuUI.row(iw, { icon = "user", label = _("Your name"),
                sub = (name and name ~= "") and name or _("Not set"), sub_data = true,
                chevron = true, action = { kind = "edit-name" } }),
            MenuUI.row(iw, { icon = "target", label = _("Annual reading goal"), sub = _("Books to finish each year"), h = 64,
                trail = MenuUI.stepper(goal, _("books"), { kind = "goal", delta = -1 }, { kind = "goal", delta = 1 }) }),
        }),
        space(nil, px(12)),
        MenuUI.card(w, { space(nil, px(12)), text(_("Your name is shown in the greeting on Home."), { s = 13, col = INK.g4, w = iw, lines = 2 }), space(nil, px(12)) }, { fill = true }),
    }
end

-- --------------------------------------------------------------- shortcut
-- The gesture that opens Aleph: its drawing, name and Change.
local function shortcutCard(page, w)
    local iw = MenuUI.rowsIn(w)
    if not Device:isTouchDevice() then
        return MenuUI.card(w, { space(nil, px(12)), text(_("This device has no touchscreen. KOReader's keyboard shortcuts can open Aleph: its action is \"Aleph: open\"."), { s = 14, w = iw, lines = 3 }), space(nil, px(12)) })
    end
    local g = Shortcut.find(Shortcut.current(page.gestures_data))
    local pill = MenuUI.pill(g and _("Change") or _("Pick one"), { kind = "outline", h = 36, s = 14, pad_x = 14, action = { kind = "view", view = "shortcut" } })
    local illus = MenuUI.gesture(g and g.kind or "none", px(44))
    local mid_w = iw - illus:getSize().w - pill:getSize().w - 2 * px(14)
    local sub = g and (g.reader_only and _("Opens Aleph from any book") or _("Opens Aleph from the file browser and from any book")) or _("Pick a gesture to open Aleph")
    local sub_lines = 2
    pcall(function() sub_lines = math.max(2, math.min(3, require("aleph_text_pages").linesNeeded(sub, { s = 13 }, mid_w))) end)
    local mid = vstack({ w = mid_w }, {
        text(g and g.label() or _("No shortcut"), { s = 16, b = true, w = mid_w }),
        text(sub, { s = 13, col = INK.g4, w = mid_w, lines = sub_lines }),
    })
    return BoardUI.hit(MenuUI.card(w, {
        hstack({ w = iw, h = math.max(px(84), mid:getSize().h + px(16)), gap = px(14) }, { illus, mid, pill }),
    }), { kind = "view", view = "shortcut" })
end

-- Every gesture on offer as a card, the one in use checked, each naming what
-- it would replace.
local function shortcutCards(page, w, illus_max, with_note)
    local options = Shortcut.available(Device:hasMultitouch())
    local current = Shortcut.current(page.gestures_data)
    local W = BoardMetrics.layoutW()
    local total = #options + 1
    local cols = W >= 900 and math.min(total, 5) or W >= 700 and 3 or 2
    local gap = px(10)
    -- A card keeps room for its two-line name: a larger interface size takes
    -- a column away rather than squeeze them.
    while cols > 2 and math.floor((w - (cols - 1) * gap) / cols) < px(170) do cols = cols - 1 end
    local cw = math.floor((w - (cols - 1) * gap) / cols)
    local illus = math.min(px(illus_max), math.floor(cw * 0.42))
    local pad = px(14)
    local name_of = function(binding)
        local ok, name = pcall(function() return require("dispatcher"):menuTextFunc(binding) end)
        return ok and name or _("another action")
    end
    local entries = {}
    for _i, g in ipairs(options) do table.insert(entries, { id = g.id, kind = g.kind, label = g.label() }) end
    table.insert(entries, { id = false, kind = "none", label = _("No shortcut") })
    local inners = {}
    for _i, e in ipairs(entries) do
        local on = (e.id or nil) == current
        local note, warn
        if e.id then
            note, warn = Shortcut.describe(page.gestures_data, e.id, name_of)
        else
            note = _("KOReader's menu only")
        end
        local iw = cw - 2 * pad
        local note_row = hstack({ w = iw, gap = px(5), valign = "top" }, {
            warn and icon("triangle-alert", px(14), { sw = 2.25 }) or false,
            text(note, { s = 12, col = INK.g4, b = warn, lines = 2, w = iw - (warn and px(19) or 0), data = true }),
        })
        local inner = vstack({ w = iw, pad = { pad, 0, pad, 0 } }, {
            MenuUI.gesture(e.kind, illus),
            space(nil, px(10)),
            text(e.label, { s = 15, b = true, lines = 2, w = iw }),
            space(nil, px(10)),
            note_row,
        })
        table.insert(inners, { inner = inner, entry = e, on = on, warn = warn, note = note })
    end
    -- The cards of a row share the height of the tallest one.
    local row_h = {}
    for index, it in ipairs(inners) do
        local r = math.floor((index - 1) / cols)
        row_h[r] = math.max(row_h[r] or 0, it.inner:getSize().h)
    end
    local cards = {}
    for index, it in ipairs(inners) do
        local h = row_h[math.floor((index - 1) / cols)]
        local border = it.on and math.max(2, px(2.5)) or MenuUI.line()
        local card = BoardUI.overlay(cw, h, {
            { widget = BoardUI.box({ w = cw, h = h, radius = px(12), border = border, border_col = it.on and INK.black or INK.g8, bg = INK.white }) },
            { widget = it.inner, x = pad, y = 0 },
            it.on and { widget = MenuUI.check(), x = cw - px(10) - px(24), y = px(10) } or {},
        })
        table.insert(cards, BoardUI.hit(card, { kind = "shortcut", id = it.entry.id, replaces = it.warn and it.note or nil }))
    end
    local rows = {}
    for start = 1, #cards, cols do
        local items = {}
        for index = start, math.min(#cards, start + cols - 1) do table.insert(items, cards[index]) end
        if #rows > 0 then table.insert(rows, space(nil, gap)) end
        table.insert(rows, hstack({ gap = gap, valign = "top" }, items))
    end
    local iw = MenuUI.rowsIn(w)
    if not with_note then return { vstack({ w = w }, rows) } end
    return {
        vstack({ w = w }, rows),
        space(nil, px(16)),
        MenuUI.card(w, {
            hstack({ w = iw, gap = px(12), valign = "top" }, {
                vstack({}, { space(nil, px(12)), icon("info", px(20), { sw = 2 }) }),
                vstack({ w = iw - px(20) - px(12), pad = { px(12), 0, px(12), 0 } }, {
                    text(_("Top-left hold and top-right tap work in books only. Other choices also work in the file browser. A gesture that already does something is named before it is replaced. The \"Aleph: this book\" action can be given a gesture in KOReader's Taps and gestures."), { s = 13, col = INK.g4, lines = 5, w = iw - px(20) - px(12), bg = INK.ge }),
                }),
            }),
        }, { fill = true }),
    }
end

-- The cards and the note at the largest drawing that fits avail: smaller
-- gesture drawings first, then without the note.
local function shortcutBody(page, w, avail)
    local function height(items)
        local h = 0
        for _i, item in ipairs(items) do h = h + item:getSize().h end
        return h
    end
    for _i, illus in ipairs({ 64, 48, 36 }) do
        -- A draft in a sink of its own, so its cards are not tappable.
        local items = BoardUI.collectHits(function() return shortcutCards(page, w, illus, true) end)
        if height(items) <= avail then return shortcutCards(page, w, illus, true) end
        for _j, item in ipairs(items) do if item.free then item:free() end end
    end
    return shortcutCards(page, w, 36, false)
end

local function pinsPlace()
    local ok, label = pcall(function() return require("aleph_pins").placeLabel():lower() end)
    return ok and label or _("bottom right")
end

local function openingBody(page, w, compact)
    local settings = page.browser.settings
    local iw = MenuUI.rowsIn(w)
    local on = settings.open_home == true
    local choices = {
        { _("Show the file browser"), _("Open Aleph from KOReader's menu"), false },
        { _("Open Aleph"), _("At startup, and whenever you close a book"), true },
    }
    local radios = {}
    for _i, c in ipairs(choices) do
        table.insert(radios, MenuUI.row(iw, { label = c[1], sub = c[2], radio = on == c[3], h = 64, action = { kind = "open-home", value = c[3] } }))
    end
    local styled = settings.style_dialogs ~= false
    local pins_left = settings.pins_left == true
    return {
        MenuUI.section(w, _("When KOReader starts"), MenuUI.group(w, radios, { inset = 0 })),
        space(nil, px(12)),
        MenuUI.section(w, _("Shortcut"), compact and Device:isTouchDevice() and MenuUI.group(w, {
            MenuUI.row(iw, { icon = "smartphone", label = _("Gesture"), sub = shortcutLabel(page), sub_data = true, chevron = true, action = { kind = "view", view = "shortcut" } }),
        }) or shortcutCard(page, w)),
        space(nil, px(12)),
        MenuUI.section(w, _("Dialogs"), MenuUI.group(w, {
            MenuUI.row(iw, { icon = "palette", label = _("Aleph dialogs"),
                sub = _("Opening a book, search, highlights and KOReader's own windows use Aleph's style"), h = 64,
                toggle = styled, action = { kind = "style-dialogs", value = not styled } }),
            MenuUI.row(iw, { icon = "sliders-horizontal", label = _("Reader menu at the bottom"),
                sub = _("This book, style, contents, bookmarks and your other books; off for KOReader's own"), h = 64,
                toggle = settings.reader_sheet ~= false, action = { kind = "reader-sheet", value = settings.reader_sheet == false } }),
            MenuUI.row(iw, { icon = "book-open", label = _("Page browser on swipe up"),
                sub = _("Swipe up from the bottom edge of a book for pages, contents, bookmarks and more"), h = 64,
                toggle = settings.page_browser_swipe ~= false, action = { kind = "page-browser-swipe", value = settings.page_browser_swipe == false } }),
            MenuUI.row(iw, { icon = "pin", label = _("Pinned pages"),
                sub = T(_("Badge: %1 · drawer on the %2"), pinsPlace(), pins_left and _("left") or _("right")), h = 64,
                chevron = true, action = { kind = "pins-place" } }),
        }, { inset = 0 })),
    }
end

-- Settings > Top menu: what was KOReader's "QuickTopBar" entry.
local SLIDERS = { "knob", "bar", "steps", "dots" }

local function topMenuBody(page, w, compact)
    local settings = page.browser.settings
    local iw = MenuUI.rowsIn(w)
    local TopMenu = require("aleph_topmenu_page")
    local root = page.browser.plugin and page.browser.plugin.path
    local on, standalone = topbarState(settings)
    local items = {
        MenuUI.group(w, {
            MenuUI.row(iw, { icon = "panel-top", label = _("Controls and Apps tabs"),
                sub = standalone and _("The separate Quick Top Bar plugin is enabled; turn it off in Plugin management to use this one")
                    or _("Quick controls and your apps at the start of KOReader's top menu"), h = 64,
                toggle = on, action = (not standalone) and { kind = "topbar", value = not on } or nil }),
        }, { inset = 0 }),
    }
    if not on then return items end
    local function iconRow(label, key, default)
        local preview = root and TopMenu.picture(TopMenu.iconFile(root, key, default), px(24)) or nil
        return MenuUI.row(iw, { icon = "image", label = label, h = 56, trail = preview, chevron = true,
            action = { kind = "topmenu-tab-icon", key = key, default = default, label = label } })
    end
    local hidden = TopMenu.hiddenCount()
    table.insert(items, space(nil, px(12)))
    table.insert(items, MenuUI.section(w, _("Apps tab"), MenuUI.group(w, {
        MenuUI.row(iw, { icon = "layout-grid", label = _("Apps"),
            sub = hidden > 0 and T(_("%1 hidden · show, hide, order, icons"), hidden) or _("Show, hide, order and change icons"),
            chevron = true, action = { kind = "topmenu-apps" } }),
    })))
    local slider_labels = { _("Knob"), _("Bar"), _("Notched"), _("Dots") }
    local function sliderRow(label, key)
        local current = TopMenu.read(key, "knob")
        local r = segRow(iw, label, nil, slider_labels, indexOf(SLIDERS, current, 1),
            function(index) return { kind = "topmenu-slider", key = key, value = SLIDERS[index] } end, compact)
        r._no_icon = true
        return r
    end
    local look = {
        MenuUI.row(iw, { icon = "square", label = _("Outline around icons"), h = 56,
            toggle = TopMenu.read("outline", true) ~= false, action = { kind = "topmenu-outline" } }),
        iconRow(_("Controls tab icon"), "tab_controls", "controls"),
        iconRow(_("Apps tab icon"), "tab_apps", "apps"),
    }
    if Device:hasFrontlight() then
        table.insert(look, sliderRow(_("Brightness slider"), "brightness_style"))
        if Device:hasNaturalLight() then table.insert(look, sliderRow(_("Warmth slider"), "warmth_style")) end
    end
    table.insert(items, space(nil, px(12)))
    table.insert(items, MenuUI.section(w, _("Look"), MenuUI.group(w, look, { inset = 0 })))
    return items
end

local function homeBody(page, w, compact)
    local settings = page.browser.settings
    local state = BoardStore.read(settings)
    local iw = MenuUI.rowsIn(w)
    local top = MenuUI.group(w, {
        MenuUI.row(iw, { icon = "layout-grid", label = _("Customize Home"), sub = _("Move, resize, add and remove widgets"), chevron = true, action = { kind = "customize" } }),
    })
    local preset_labels = { _("Reader"), _("Stats"), _("Library") }
    local tile_labels = { _("Outline"), _("Soft"), _("Ink") }
    -- Colour only on a screen that shows it.
    local colour_labels = Device.screen:isColorEnabled() and { _("Accents"), _("Tinted"), _("Off") } or nil
    local scale_labels = {}
    for index, scale in ipairs(BoardMetrics.UI_SCALES) do scale_labels[index] = scaleLabel(scale) end
    local function sub(str) return (not compact) and str or nil end
    local rows = {
        segRow(iw, _("Starting layout"), sub(_("Replaces your pages with a starter set")), preset_labels, indexOf(PRESETS, state.preset, 1),
            function(index) return { kind = "preset", value = PRESETS[index] } end, compact),
        segRow(iw, _("Tile style"), nil, tile_labels, indexOf(TILES, state.tiles, 1),
            function(index) return { kind = "tiles", value = TILES[index] } end, compact),
    }
    if colour_labels then
        table.insert(rows, segRow(iw, _("Colour"), nil, colour_labels, indexOf(COLOURS, state.colour, 1),
            function(index) return { kind = "colour", value = COLOURS[index] } end, compact))
    end
    table.insert(rows, segRow(iw, _("Interface size"), sub(_("Text and controls across Aleph")), scale_labels,
        indexOf(BoardMetrics.UI_SCALES, BoardMetrics.normalizeUserScale(settings.ui_scale), 1),
        function(index) return { kind = "ui-scale", value = BoardMetrics.UI_SCALES[index] } end, compact))
    for _i, r in ipairs(rows) do r._no_icon = true end
    local look = MenuUI.group(w, rows, { inset = 0 })
    local reset = MenuUI.group(w, {
        MenuUI.row(iw, { icon = "rotate-ccw", label = _("Reset Home"), sub = _("Back to the starting layout and outline tiles"), action = { kind = "reset-home" } }),
    })
    return {
        top,
        space(nil, px(16)),
        MenuUI.section(w, _("Look"), look),
        space(nil, px(16)),
        reset,
    }
end

local function libraryBody(page, w)
    local settings = page.browser.settings
    local iw = MenuUI.rowsIn(w)
    local rows = {}
    for index, path in ipairs(libraryRoots(settings)) do
        table.insert(rows, MenuUI.row(iw, { icon = "folder-open", label = folderName(path), data = true, sub = path, sub_data = true, sublines = 2,
            trail = icon("trash", px(20), { sw = 2 }), action = { kind = "folder-remove", index = index } }))
    end
    local items = {}
    if #rows > 0 then
        table.insert(items, MenuUI.group(w, rows))
        table.insert(items, space(nil, px(16)))
    end
    table.insert(items, MenuUI.group(w, {
        MenuUI.row(iw, { icon = "plus", label = _("Add folder"), sub = _("Books in it and below it are indexed"), chevron = true, action = { kind = "folder-add" } }),
        MenuUI.row(iw, { icon = "refresh-cw", label = page.browser.scanning and _("Cancel library scan") or _("Refresh local library"),
            sub = _("Look for new, moved and removed books"), action = { kind = "refresh" } }),
    }))
    return items
end

-- Author portraits: optional, looked up on the internet.
local function authorNames(browser)
    local names = {}
    for _i, a in ipairs(browser.local_library:groupEntries("authors", "name")) do names[#names + 1] = a.title end
    return names
end

local function portraitsBody(page, w)
    local settings = page.browser.settings
    local iw = MenuUI.rowsIn(w)
    local on = settings.author_portraits == true
    local Portraits = require("aleph_portraits")
    local items = {
        MenuUI.group(w, {
            MenuUI.row(iw, { icon = "user-round", label = _("Show author portraits"),
                sub = _("Looked up as authors are shown in the Authors list"), h = 64,
                toggle = on, action = { kind = "portraits-toggle", value = not on } }),
        }),
        space(nil, px(12)),
        MenuUI.card(w, { space(nil, px(12)), text(_("Turning this on uses the internet. Only an author's name is sent, to Open Library and Wikipedia, and the photos are saved on this device. Authors without a photo keep showing their covers."), { s = 13, col = INK.g4, w = iw, lines = 5 }), space(nil, px(12)) }, { fill = true }),
    }
    if on then
        local names = authorNames(page.browser)
        local pending = Portraits.pending(names)
        local running, done, total = Portraits.running()
        table.insert(items, space(nil, px(16)))
        local rows = {}
        if running then
            table.insert(rows, MenuUI.row(iw, { icon = "x", label = _("Stop downloading"), sub = T(_("%1 of %2 looked up"), done, total), h = 64, action = { kind = "portraits-cancel" } }))
        else
            table.insert(rows, MenuUI.row(iw, { icon = "download", label = _("Download all portraits"),
                sub = pending > 0 and T(_("%1 authors not looked up yet"), pending) or _("Every author has been looked up"), h = 64,
                action = pending > 0 and { kind = "portraits-download", pending = pending } or { kind = "noop" } }))
        end
        table.insert(rows, MenuUI.row(iw, { icon = "trash", label = _("Remove downloaded portraits"),
            sub = T(_("%1 saved on this device"), Portraits.count()), h = 64, action = { kind = "portraits-clear" } }))
        table.insert(items, MenuUI.group(w, rows))
    end
    return items
end

local function aboutBody(page, w)
    local iw = MenuUI.rowsIn(w)
    local pill = MenuUI.pill(_("Based on BookOrbit's plugin"), { kind = "outline", h = 36, s = 14, pad_x = 14, action = { kind = "link" } })
    local mid_w = iw - pill:getSize().w - px(12)
    return {
        MenuUI.card(w, {
            hstack({ w = iw, h = px(76), gap = px(12) }, {
                vstack({ w = mid_w }, {
                    text(_("Aleph"), { s = 16, b = true, w = mid_w }),
                    text(T(_("Version %1"), VERSION), { s = 13, col = INK.g4, w = mid_w }),
                }),
                pill,
            }),
        }),
        space(nil, px(16)),
        MenuUI.group(w, {
            MenuUI.row(iw, { icon = "file-text", label = _("Legal notices"), sub = _("Licence, credits and what was changed"), chevron = true, action = { kind = "legal" } }),
        }),
    }
end

local function bodyFor(page, view, w, compact)
    if view == "profile" then return profileBody(page, w) end
    if view == "opening" then return openingBody(page, w, compact) end
    if view == "home" then return homeBody(page, w, compact) end
    if view == "topmenu" then return topMenuBody(page, w, compact) end
    if view == "library" then return libraryBody(page, w) end
    if view == "portraits" then return portraitsBody(page, w) end
    return aboutBody(page, w)
end

-- ------------------------------------------------------------------ build
local function heightOf(items)
    local h = 0
    for _i, item in ipairs(items) do
        if item and not item._flex then h = h + item:getSize().h end
    end
    return h
end

local function build(page, sw, sh)
    local mx = MenuUI.mx()
    local top, bottom = px(6), px(12)
    local w = sw - 2 * mx
    local avail = sh - top - bottom
    local view = page.stack[#page.stack]
    local items
    if view == "root" then
        local header = MenuUI.pageHeader(w, _("Settings"), { sub = _("Aleph") })
        local footer = text(T(_("Aleph %1"), VERSION), { s = 13, col = INK.g4, w = w, align = "center" })
        items = { header, space(nil, px(8)) }
        for _i, item in ipairs(settingsList(page, w)) do table.insert(items, item) end
        table.insert(items, flex(px(8)))
        table.insert(items, footer)
    elseif view == "shortcut" then
        local header = MenuUI.pageHeader(w, _("Shortcut"), { sub = _("Choose where to open Aleph") })
        items = { header, space(nil, px(8)) }
        for _i, item in ipairs(shortcutBody(page, w, avail - header:getSize().h - px(8))) do table.insert(items, item) end
    else
        local header = MenuUI.pageHeader(w, titleOf(view), { sub = _("Settings") })
        local body = bodyFor(page, view, w, false)
        -- A page too tall for the screen drops its notes and tightens up.
        if header:getSize().h + px(8) + heightOf(body) > avail then
            for _i, item in ipairs(body) do if item and item.free then item:free() end end
            body = bodyFor(page, view, w, true)
        end
        items = { header, space(nil, px(8)) }
        for _i, item in ipairs(body) do table.insert(items, item) end
    end
    page.panel_rect = Geom:new{ x = 0, y = 0, w = sw, h = sh }
    return vstack({ w = sw, h = sh, pad = { top, mx, bottom, mx } }, items)
end

-- ---------------------------------------------------------------- actions
-- A question in the board's style (aleph_confirm.lua); KOReader's own
-- box if that cannot be built.
local function confirm(title, body, ok_text, ok)
    local built = pcall(function()
        require("aleph_confirm").show{ title = title, text = body, ok_label = ok_text, on_ok = ok }
    end)
    if not built then
        UIManager:show(require("ui/widget/confirmbox"):new{ text = title .. "\n\n" .. body, ok_text = ok_text, ok_callback = ok })
    end
end

local function onAction(page, action)
    local browser = page.browser
    local settings = browser.settings
    local kind = action.kind
    if kind == "view" and action.view == "margins" then
        -- A page of its own (it also opens from a book's Tools menu).
        require("aleph_bookends_page").open(browser.plugin and browser.plugin.ui)
    elseif kind == "view" then
        table.insert(page.stack, action.view)
        page:refresh()
    elseif kind == "edit-name" then
        browser:input(_("Your name"), settings.display_name, function(v)
            browser:persistSetting("display_name", v)
            browser:refreshData()
            page:refresh()
        end)
    elseif kind == "goal" then
        local goal = math.max(1, math.min(10000, (tonumber(settings.year_goal) or 12) + action.delta))
        browser:persistSetting("year_goal", goal)
        browser:refreshData()
        page:refresh()
    elseif kind == "open-home" then
        browser:persistSetting("open_home", action.value)
        page:refresh()
    elseif kind == "portraits-toggle" then
        browser:persistSetting("author_portraits", action.value)
        if not action.value then require("aleph_portraits").cancel() end
        page:refresh()
    elseif kind == "portraits-download" then
        local minutes = math.max(1, math.ceil(action.pending / 60))
        confirm(_("Download author portraits"),
            T(_("This looks up %1 authors on Open Library and Wikipedia, about one a second (around %2 minutes), and needs Wi-Fi to stay on. Only the names are sent. You can stop it any time, and the Authors list shows portraits as they arrive."), action.pending, minutes),
            _("Download"), function()
                require("ui/network/manager"):runWhenOnline(function()
                    local Portraits = require("aleph_portraits")
                    Portraits.downloadAll(authorNames(browser), function() if not page.closed then page:refresh() end end, function(found, total)
                        pcall(function() require("aleph_toast").show(T(_("Author portraits: %1 found, %2 looked up"), found, total)) end)
                        if not page.closed then page:refresh() end
                    end)
                    page:refresh()
                end)
            end)
    elseif kind == "portraits-cancel" then
        require("aleph_portraits").cancel()
        page:refresh()
    elseif kind == "portraits-clear" then
        confirm(_("Remove portraits"), _("The downloaded portraits are deleted from this device. They can be downloaded again."), _("Remove"), function()
            require("aleph_portraits").clear()
            page:refresh()
        end)
    elseif kind == "shortcut" then
        local apply = function()
            local gestures = browser.plugin and browser.plugin.ui and browser.plugin.ui.gestures
            if not Shortcut.apply(gestures, action.id or nil) then
                pcall(function() require("aleph_toast").show(_("Turn on KOReader's Gestures plugin first: Settings, Taps and gestures.")) end)
                return
            end
            page.gestures_data = gestures.data
            page:refresh()
        end
        if action.replaces then
            confirm(_("Use this gesture for Aleph?"), T(_("%1."), action.replaces), _("Use it"), apply)
        else
            apply()
        end
    elseif kind == "topbar" then
        browser:persistSetting("topbar", action.value)
        pcall(function() require("aleph_topbar").sync(browser.plugin) end)
        page:refresh()
    elseif kind == "topmenu-apps" then
        require("aleph_topmenu_page").openApps(browser.plugin and browser.plugin.ui, browser.plugin.path,
            function() if not page.closed then page:refresh() end end)
    elseif kind == "topmenu-tab-icon" then
        local TopMenu = require("aleph_topmenu_page")
        TopMenu.pickIcon(browser.plugin.path, action.label, TopMenu.read(action.key), action.default, function(value)
            TopMenu.save(action.key, value)
            if not page.closed then page:refresh() end
        end)
    elseif kind == "topmenu-outline" then
        local TopMenu = require("aleph_topmenu_page")
        TopMenu.save("outline", TopMenu.read("outline", true) == false)
        page:refresh()
    elseif kind == "topmenu-slider" then
        require("aleph_topmenu_page").save(action.key, action.value)
        page:refresh()
    elseif kind == "reader-sheet" then
        browser:persistSetting("reader_sheet", action.value)
        page:refresh()
    elseif kind == "page-browser-swipe" then
        browser:persistSetting("page_browser_swipe", action.value)
        page:refresh()
    elseif kind == "pins-place" then
        require("aleph_pins").openPlacer(nil, function() if not page.closed then page:refresh() end end)
    elseif kind == "pins-left" then
        browser:persistSetting("pins_left", action.value)
        page:refresh()
    elseif kind == "style-dialogs" then
        browser:persistSetting("style_dialogs", action.value)
        pcall(function() require("aleph_theme").sync() end)
        page:refresh()
    elseif kind == "customize" then
        page:close()
        browser.mode = "home"
        browser:updateItems()
        browser:boardEnterEdit()
    elseif kind == "preset" then
        if BoardStore.read(settings).preset == action.value then return true end
        confirm(_("Start Home from this layout?"), _("Your pages are replaced by this layout's pages."), _("Replace"), function()
            browser:persistSetting(BoardStore.SETTING_KEY, BoardStore.withPreset(settings, action.value))
            browser:updateItems()
            page:refresh()
        end)
    elseif kind == "tiles" then
        browser:boardSetTiles(action.value)
        page:refresh()
    elseif kind == "colour" then
        browser:boardSetColour(action.value)
        page:refresh()
    elseif kind == "ui-scale" then
        if settings.ui_scale == action.value then return true end
        browser:persistSetting("ui_scale", BoardMetrics.setUserScale(action.value))
        pcall(function() require("aleph_theme").sync() end)
        browser:updateItems()
        page:refresh()
    elseif kind == "reset-home" then
        confirm(_("Reset Home?"), _("Your pages and tile style go back to how they started."), _("Reset"), function()
            local state = BoardStore.withPreset(settings, BoardStore.read(settings).preset)
            state.tiles = "outline"
            browser:persistSetting(BoardStore.SETTING_KEY, state)
            browser:updateItems()
            page:refresh()
        end)
    elseif kind == "folder-add" then
        UIManager:show(require("ui/widget/pathchooser"):new{
            select_directory = true, path = settings.library_roots[1],
            onConfirm = function(path)
                for _i, p in ipairs(settings.library_roots) do if p == path then return end end
                table.insert(settings.library_roots, path)
                browser:persistSetting("library_roots", settings.library_roots)
                browser:startScan()
                page:refresh()
            end,
        })
    elseif kind == "folder-remove" then
        local path = settings.library_roots[action.index]
        if not path then return true end
        confirm(_("Remove this folder?"), path .. "\n\n" .. _("Its books leave the library index. The files stay where they are."), _("Remove"), function()
            table.remove(settings.library_roots, action.index)
            browser:persistSetting("library_roots", settings.library_roots)
            browser:startScan()
            page:refresh()
        end)
    elseif kind == "refresh" then
        if browser.scanning then browser:cancelScan() else browser:startScan() end
        page:refresh()
    elseif kind == "legal" then
        browser:showAbout()
    elseif kind == "link" then
        if Device.openLink then Device:openLink("https://github.com/bookorbit/bookorbit")
        else browser:message("https://github.com/bookorbit/bookorbit") end
    end
    return true
end

-- Back steps out of a group before it closes Settings.
local function onBack(page)
    if #page.stack > 1 then
        table.remove(page.stack)
        page:refresh()
        return true
    end
    return false
end

-- The running Gestures plugin's bindings, nil when it is off.
local function gesturesData(browser)
    local ui = browser.plugin and browser.plugin.ui
    local gestures = ui and ui.gestures
    return gestures and gestures.data or nil
end

-- view: nil for the root, or a group id ("profile", "opening", "topmenu",
-- "home", "library", "about", "shortcut").
function Settings.open(browser, view)
    local stack = { "root" }
    if view and view ~= "root" then table.insert(stack, view) end
    local page = MenuPage:new{
        name = "aleph_settings",
        build = build,
        on_action = onAction,
        on_back = onBack,
        browser = browser,
        stack = stack,
        gestures_data = gesturesData(browser),
    }
    UIManager:show(page, "ui")
    return page
end

return Settings
