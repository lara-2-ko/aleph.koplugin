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
local try = require("aleph_try").call

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

local function readerSummary(settings)
    local parts = {}
    parts[#parts + 1] = settings.reader_sheet ~= false and _("Aleph's reader menu") or _("KOReader's reader menu")
    if settings.page_browser_swipe ~= false then parts[#parts + 1] = _("page browser on swipe up") end
    return table.concat(parts, " · ")
end

-- X-Ray (aleph_xr.lua): the names of a book, off unless turned on.
local function xraySummary(settings)
    if settings.xray_enabled ~= true then return _("Off · the names of a book, as you read") end
    local parts = { _("On") }
    if settings.xray_underline == true then parts[#parts + 1] = _("names underlined") end
    if type(settings.xray_ai_key) == "string" and settings.xray_ai_key ~= "" then parts[#parts + 1] = _("descriptions with AI") end
    return table.concat(parts, " · ")
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

-- Settings > Library: its folders, how covers are drawn, the extra filters.
local function librarySummary(settings)
    local roots = libraryRoots(settings)
    local parts = {}
    if #roots == 0 then parts[1] = _("No folders yet")
    elseif #roots == 1 then parts[1] = folderName(roots[1])
    else parts[1] = T(_("%1 folders"), #roots) end
    if settings.cover_shape == "fill" then parts[#parts + 1] = _("covers filled")
    elseif settings.cover_shape == "stretch" then parts[#parts + 1] = _("covers stretched") end
    if settings.extra_filters == true then parts[#parts + 1] = _("extra filters") end
    return table.concat(parts, " · ")
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
    try(function() standalone = require("aleph_topbar").standalone() end)
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
    { id = "home", icon = "layout-grid", label = function() return _("Home") end, sub = function(page) return homeSummary(page.browser.settings) end },
    { id = "actions", icon = "zap", label = function() return _("Widget actions") end, sub = function() return _("What each widget and Quick settings button opens") end },
    { id = "reader", icon = "book-open", label = function() return _("Reader") end, sub = function(page) return readerSummary(page.browser.settings) end },
    { id = "margins", icon = "file-text", label = function() return _("Book margins") end, sub = function() return marginsSummary() end },
    { id = "topmenu", icon = "panel-top", label = function() return _("Top menu") end, sub = function(page) return topMenuSummary(page.browser.settings) end },
    { id = "library", icon = "library", label = function() return _("Library") end, sub = function(page) return librarySummary(page.browser.settings) end },
    { id = "portraits", icon = "user-round", label = function() return _("Author portraits") end, sub = function(page) return portraitsSummary(page.browser.settings) end },
    { id = "xray", icon = "sparkles", label = function() return _("X-Ray") end, sub = function(page) return xraySummary(page.browser.settings) end },
}

local function titleOf(view)
    for _i, cat in ipairs(CATEGORIES) do
        if cat.id == view then return cat.label() end
    end
    if view == "about" then return _("About") end
    if view == "night" then return _("Night profile") end
    if view == "shortcut" then return _("Shortcut") end
    return _("Settings")
end

-- ----------------------------------------------------------------- lists
local function settingsList(page, w)
    local iw = MenuUI.rowsIn(w)
    local rows = {}
    for _i, cat in ipairs(CATEGORIES) do
        if not cat.when or cat.when(page) then table.insert(rows, MenuUI.row(iw, {
            icon = cat.icon, label = cat.label(), sub = cat.sub(page), sub_data = true,
            chevron = true, action = { kind = "view", view = cat.id },
        })) end
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
            MenuUI.row(iw, { icon = "target", label = _("Annual reading goal"), sub = _("Tap the number to type one"), h = 64,
                trail = MenuUI.stepper(goal, _("books"), { kind = "goal", delta = -1 }, { kind = "goal", delta = 1 }, { kind = "goal-type" }) }),
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
    try(function() sub_lines = math.max(2, math.min(3, require("aleph_text_pages").linesNeeded(sub, { s = 13 }, mid_w))) end)
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
    return {
        MenuUI.section(w, _("When KOReader starts"), MenuUI.group(w, radios, { inset = 0 })),
        space(nil, px(12)),
        MenuUI.section(w, _("Shortcut"), compact and Device:isTouchDevice() and MenuUI.group(w, {
            MenuUI.row(iw, { icon = "smartphone", label = _("Gesture"), sub = shortcutLabel(page), sub_data = true, chevron = true, action = { kind = "view", view = "shortcut" } }),
        }) or shortcutCard(page, w)),
    }
end

-- Settings > Reader: what Aleph adds to a book's screens.
local function readerBody(page, w, compact)
    local settings = page.browser.settings
    local iw = MenuUI.rowsIn(w)
    local pins_left = settings.pins_left == true
    return {
        MenuUI.group(w, {
            MenuUI.row(iw, { icon = "sliders-horizontal", label = _("Reader menu at the bottom"),
                sub = _("This book, style, contents, bookmarks and your other books; off for KOReader's own"), h = 64,
                toggle = settings.reader_sheet ~= false, action = { kind = "reader-sheet", value = settings.reader_sheet == false } }),
            MenuUI.row(iw, { icon = "book-open", label = _("Page browser on swipe up"),
                sub = _("Swipe up from the bottom edge of a book for pages, contents, bookmarks and more"), h = 64,
                toggle = settings.page_browser_swipe ~= false, action = { kind = "page-browser-swipe", value = settings.page_browser_swipe == false } }),
            MenuUI.row(iw, { icon = "pin", label = _("Pinned pages"),
                sub = T(_("Badge: %1 · drawer on the %2"), pinsPlace(), pins_left and _("left") or _("right")), h = 64,
                chevron = true, action = { kind = "pins-place" } }),
            MenuUI.row(iw, { icon = "bookmark", label = _("Choose a colour when bookmarking"),
                sub = _("The list of colours drops from the ribbon; off: the colour used last"), h = 64,
                toggle = settings.bookmark_color_ask ~= false, action = { kind = "bookmark-color-ask", value = settings.bookmark_color_ask == false } }),
        }, { inset = 0 }),
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
    -- Nine sizes, 1x to 1.5x: a stepper rather than nine segments.
    local scale_now = BoardMetrics.normalizeUserScale(settings.ui_scale)
    local scales = BoardMetrics.UI_SCALES
    table.insert(rows, MenuUI.row(iw, { label = _("Interface size"), sub = sub(_("Text and controls across Aleph")), h = compact and 56 or 64,
        trail = MenuUI.stepper(scaleLabel(scale_now), nil,
            scale_now > scales[1] and { kind = "ui-scale", delta = -1 } or nil,
            scale_now < scales[#scales] and { kind = "ui-scale", delta = 1 } or nil) }))
    for _i, r in ipairs(rows) do r._no_icon = true end
    local look = MenuUI.group(w, rows, { inset = 0 })
    local styled = settings.style_dialogs ~= false
    local dialogs = MenuUI.group(w, {
        MenuUI.row(iw, { icon = "palette", label = _("Aleph dialogs"),
            sub = sub(_("Opening a book, search, highlights and KOReader's own windows use Aleph's style")), h = compact and 52 or 64,
            toggle = styled, action = { kind = "style-dialogs", value = not styled } }),
    }, { inset = 0 })
    -- The night profile (aleph_night.lua): light and text when night mode is on.
    local night = MenuUI.group(w, {
        MenuUI.row(iw, { icon = "moon", label = _("Night profile"), sub = require("aleph_night").summary(),
            h = compact and 52 or 64, chevron = true, action = { kind = "view", view = "night" } }),
    })
    local reset = MenuUI.group(w, {
        MenuUI.row(iw, { icon = "rotate-ccw", label = _("Reset Home"), sub = sub(_("Back to the starting layout and outline tiles")), action = { kind = "reset-home" } }),
    })
    return {
        top,
        space(nil, px(compact and 10 or 16)),
        MenuUI.section(w, _("Look"), look),
        space(nil, px(compact and 10 or 16)),
        dialogs,
        space(nil, px(compact and 10 or 16)),
        night,
        space(nil, px(compact and 10 or 16)),
        reset,
    }
end

-- Settings > Home > Night profile (aleph_night.lua).
local function nightBody(page, w, compact)
    local Night = require("aleph_night")
    local c = Night.config()
    local iw = MenuUI.rowsIn(w)
    local items = {}
    -- Tight (the page does not fit): notes under the rows left out.
    local function sub(str) return (not compact) and str or nil end
    local rh = compact and 52 or 64
    local gap = px(compact and 10 or 16)
    if Night.patchInstalled() then
        table.insert(items, MenuUI.card(w, { space(nil, px(12)),
            text(_("The Night Profile patch (2-night-profile.lua) is installed: it does the same, so this stays off while it is there. Delete it from koreader/patches and restart KOReader to use the settings here."),
                { s = 13, col = INK.g2, w = iw, lines = 5 }), space(nil, px(12)) }, { fill = true }))
        table.insert(items, space(nil, px(12)))
    end
    table.insert(items, MenuUI.group(w, {
        MenuUI.row(iw, { icon = "moon", label = _("Night profile"),
            sub = sub(_("When night mode turns on: your night light and bolder text. When it turns off: your day light back")), h = rh, sublines = (not compact) and 2 or nil,
            toggle = c.on == true, action = { kind = "night-set", key = "on", value = not c.on } }),
    }, { inset = 0 }))
    -- Night mode by the clock: on by itself from one time to another.
    local clock_rows = {
        MenuUI.row(iw, { icon = "clock", label = _("Turn night mode on by itself"),
            sub = sub(_("On at the first time, off at the second. Switched by hand, it stays until the next one")), h = rh, sublines = (not compact) and 2 or nil,
            toggle = c.auto == true, action = { kind = "night-set", key = "auto", value = not c.auto } }),
    }
    if c.auto then
        local step = Night.TIME_STEP
        for _i, k in ipairs({ { "from", _("From"), "moon" }, { "to", _("To"), "sunrise" } }) do
            clock_rows[#clock_rows + 1] = MenuUI.row(iw, { icon = k[3], label = k[2], h = rh,
                trail = MenuUI.stepper(Night.timeLabel(c[k[1]]), nil,
                    { kind = "night-time", key = k[1], delta = -step }, { kind = "night-time", key = k[1], delta = step }) })
        end
    end
    table.insert(items, space(nil, gap))
    table.insert(items, MenuUI.section(w, _("By the clock"), MenuUI.group(w, clock_rows)))
    if not c.on then return items end
    local Device = require("device")
    local light_rows = {}
    if Device:hasFrontlight() then
        light_rows[#light_rows + 1] = MenuUI.row(iw, { icon = "sun-moon", label = _("Change the light"),
            sub = sub(_("A light that is off stays off")), h = rh,
            toggle = c.light == true, action = { kind = "night-set", key = "light", value = not c.light } })
        if c.light then
            local step = Night.STEP
            light_rows[#light_rows + 1] = MenuUI.row(iw, { icon = "sunrise", label = _("Night brightness"), h = rh,
                trail = MenuUI.stepper(c.brightness .. "%", nil,
                    c.brightness > step and { kind = "night-step", key = "brightness", delta = -step } or nil,
                    c.brightness < 100 and { kind = "night-step", key = "brightness", delta = step } or nil) })
            if Night.hasWarmth() then
                light_rows[#light_rows + 1] = MenuUI.row(iw, { icon = "thermometer-sun", label = _("Night warmth"), h = rh,
                    trail = MenuUI.stepper(tostring(c.warmth), nil,
                        c.warmth > 0 and { kind = "night-step", key = "warmth", delta = -step } or nil,
                        c.warmth < 100 and { kind = "night-step", key = "warmth", delta = step } or nil) })
            end
            light_rows[#light_rows + 1] = MenuUI.row(iw, { icon = "sliders-horizontal", label = _("Use the light as it is now"),
                sub = sub(_("Takes the brightness and warmth set right now as the night ones")), h = rh, sublines = (not compact) and 2 or nil,
                action = { kind = "night-take" } })
            light_rows[#light_rows + 1] = MenuUI.row(iw, { icon = "refresh-cw", label = _("Remember changes made at night"),
                sub = sub(_("Light changed while night mode is on becomes the night light next time")), h = rh, sublines = (not compact) and 2 or nil,
                toggle = c.remember == true, action = { kind = "night-set", key = "remember", value = not c.remember } })
        end
        table.insert(items, space(nil, gap))
        table.insert(items, MenuUI.section(w, _("Light"), MenuUI.group(w, light_rows)))
    end
    local labels, at = {}, 1
    for i, b in ipairs(Night.BOOSTS) do
        labels[i] = b == 0 and _("Off") or ("+" .. (b == math.floor(b) and string.format("%d", b) or tostring(b)))
        if b == c.boost then at = i end
    end
    table.insert(items, space(nil, gap))
    table.insert(items, MenuUI.section(w, _("Text"), MenuUI.group(w, {
        segRow(iw, _("Bolder text at night"), _("Books KOReader lays out itself (EPUB and the like), so light letters on black stay crisp"),
            labels, at, function(index) return { kind = "night-set", key = "boost", value = Night.BOOSTS[index] } end),
    }, { inset = 0 })))
    return items
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
        table.insert(items, MenuUI.section(w, _("Folders"), MenuUI.group(w, rows)))
        table.insert(items, space(nil, px(16)))
    end
    table.insert(items, MenuUI.group(w, {
        MenuUI.row(iw, { icon = "plus", label = _("Add folder"), sub = _("Books in it and below it are indexed"), chevron = true, action = { kind = "folder-add" } }),
        MenuUI.row(iw, { icon = "refresh-cw", label = page.browser.scanning and _("Cancel library scan") or _("Refresh local library"),
            sub = _("Look for new, moved and removed books"), action = { kind = "refresh" } }),
    }))
    -- Covers of another shape than their box: whole, or all the same size.
    local shape = settings.cover_shape == "fill" and 2 or settings.cover_shape == "stretch" and 3 or 1
    table.insert(items, space(nil, px(16)))
    table.insert(items, MenuUI.section(w, _("Covers"), MenuUI.segmented(w, { _("Whole"), _("Fill"), _("Stretch") }, shape,
        function(i) return { kind = "cover-shape", value = i == 2 and "fill" or i == 3 and "stretch" or "fit" } end)))
    table.insert(items, space(nil, px(6)))
    table.insert(items, text(shape == 1 and _("Each cover at its own shape.")
        or shape == 2 and _("Every cover the same size; the edges of other shapes are trimmed.")
        or _("Every cover the same size; other shapes are stretched to fit."), { s = 13, col = INK.g4, w = w, lines = 2 }))
    -- Language, Pages and Released in Sort and filter: off until asked for,
    -- since the first time reads every book's details.
    local extra = settings.extra_filters == true
    table.insert(items, space(nil, px(16)))
    table.insert(items, MenuUI.section(w, _("Extra filters"), MenuUI.group(w, {
        MenuUI.row(iw, { icon = "list-filter", label = _("Language, pages and release date"),
            sub = extra and _("In the library's Sort and filter") or _("Off: reads every book's details the first time"),
            h = 64, toggle = extra, action = { kind = "extra-filters" } }),
    })))
    -- Goodreads' library export (aleph_goodreads_import.lua).
    table.insert(items, space(nil, px(16)))
    -- Below it, the sign-in cookie for advokatb's Goodreads plugin, only
    -- with that plugin installed (aleph_goodreads.lua).
    local cookie, background = false, false
    try(function()
        if require("aleph_goodreads").available(page.browser.plugin and page.browser.plugin.ui) then
            cookie = MenuUI.row(iw, { icon = "key-round", label = _("Goodreads sign-in"),
                sub = _("Receive the sign-in cookie from your computer's browser"),
                h = 64, chevron = true, action = { kind = "view", view = "goodreads" } })
            -- The plugin's automatic tracking, asked in the background
            -- (aleph_goodreads_track.lua).
            local status = require("aleph_goodreads_track").status(page.browser.plugin and page.browser.plugin.ui)
            if status == "unsupported" then
                background = MenuUI.row(iw, { icon = "refresh-cw", label = _("Track in the background"),
                    sub = _("Not with this version of the Goodreads plugin: it tracks its own way"), h = 64 })
            elseif status then
                background = MenuUI.row(iw, { icon = "refresh-cw", label = _("Track in the background"),
                    sub = status == "on" and _("Goodreads is updated without holding up the page")
                        or _("Off: the Goodreads plugin asks while you wait, slow on bad Wi-Fi"),
                    h = 64, toggle = status == "on", action = { kind = "goodreads-background", value = status ~= "on" } })
            end
        end
    end)
    table.insert(items, MenuUI.section(w, _("Goodreads"), MenuUI.group(w, {
        MenuUI.row(iw, { icon = "download", label = _("Import from Goodreads"),
            sub = _("Status, finished dates and ratings from Goodreads' library export"),
            h = 64, chevron = true, action = { kind = "goodreads-import" } }),
        cookie,
        background,
    })))
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

-- Settings > X-Ray. Aleph's own X-Ray (aleph_xr.lua): the switch, what it
-- shows, and the optional descriptions (aleph_xr_ai.lua).
local function xrayBody(page, w)
    local settings = page.browser.settings
    local iw = MenuUI.rowsIn(w)
    local on = settings.xray_enabled == true
    local items = {
        MenuUI.group(w, {
            MenuUI.row(iw, { icon = "sparkles", label = _("X-Ray"),
                sub = _("The people and places of a book and where they were mentioned so far. Off: nothing of it is loaded"), h = 64,
                toggle = on, action = { kind = "xray-set", key = "xray_enabled", value = not on } }),
        }, { inset = 0 }),
    }
    if not on then return items end
    local AI = require("aleph_xr_ai")
    local config = AI.config()
    local labels, at = {}, 1
    for i, p in ipairs(AI.PROVIDERS) do
        labels[i] = p.label
        if p.id == config.provider then at = i end
    end
    local key_sub = config.key ~= "" and T(_("Saved · ends in %1"), config.key:sub(-4)) or _("Not set")
    local recap_days = tonumber(settings.xray_recap_days) or 14
    table.insert(items, space(nil, px(16)))
    table.insert(items, MenuUI.section(w, _("In a book"), MenuUI.group(w, {
        MenuUI.row(iw, { icon = "pen-line", label = _("Underline names"),
            sub = _("A thin line under each name; tap one to open it. Turn off if pages turn slower"), h = 64,
            toggle = settings.xray_underline == true, action = { kind = "xray-set", key = "xray_underline", value = settings.xray_underline ~= true } }),
        MenuUI.row(iw, { icon = "eye", label = _("Show the whole book"),
            sub = _("Names and mentions from pages not read yet too. Off: only up to the page you are on"), h = 64,
            toggle = settings.xray_show_all == true, action = { kind = "xray-set", key = "xray_show_all", value = settings.xray_show_all ~= true } }),
    })))
    table.insert(items, space(nil, px(16)))
    table.insert(items, MenuUI.section(w, _("Descriptions with AI (optional)"), vstack({ w = w }, {
        text(_("Asked from a book's X-Ray, never by itself, with your own key. Names: sends the book's title and a few words around each name. Story: sends the text of the chapters you have read. Never a page not read yet."),
            { s = 13, col = INK.g4, w = w, lines = 5 }),
        space(nil, px(10)),
        MenuUI.segmented(w, labels, at, function(index) return { kind = "xray-provider", id = AI.PROVIDERS[index].id } end),
        space(nil, px(10)),
        MenuUI.group(w, {
            MenuUI.row(iw, { icon = "key-round", label = _("Key"), sub = key_sub, sub_data = true, chevron = true, action = { kind = "xray-input", key = "xray_ai_key" } }),
            MenuUI.row(iw, { icon = "sliders-horizontal", label = _("Model"), sub = config.model ~= "" and config.model or _("Not set"), sub_data = true,
                chevron = true, action = { kind = "xray-input", key = "xray_ai_model" } }),
            MenuUI.row(iw, { icon = "calendar-clock", label = _("Offer a recap after a break"),
                sub = _("Opening a book not read for this long asks whether to summarise the story so far"), h = 64,
                value = ({ [0] = _("Never"), [7] = _("1 week"), [14] = _("2 weeks"), [30] = _("1 month") })[recap_days] or T(_("%1 days"), recap_days),
                action = { kind = "xray-recap-days" } }),
            config.provider == "custom" and MenuUI.row(iw, { icon = "globe", label = _("Address"),
                sub = config.url ~= "" and config.url or _("An OpenAI-style chat address (…/v1/chat/completions)"), sub_data = config.url ~= "",
                chevron = true, action = { kind = "xray-input", key = "xray_ai_url" } }) or nil,
        }),
    })))
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
        space(nil, px(16)),
        -- The troubleshooting log (aleph_debug.lua): extra lines in
        -- KOReader's crash.log, for tracking a problem down.
        MenuUI.section(w, _("Troubleshooting"), MenuUI.group(w, {
            MenuUI.row(iw, { icon = "activity", label = _("Troubleshooting log"),
                sub = page.browser.settings.debug_log == true and _("On: each step of opening a book is written to crash.log")
                    or _("Off: only failures are written to crash.log"),
                h = 64, toggle = page.browser.settings.debug_log == true, action = { kind = "debug-log" } }),
            -- Aleph's screens with the direction keys (aleph_keynav.lua): on by
            -- itself where the device has them; this turns it on elsewhere.
            MenuUI.row(iw, { icon = "list-filter", label = _("Button navigation"),
                sub = page.browser.settings.key_nav == true and _("On: Up, Down, Left, Right and Press move and tap. Reopen Home to apply")
                    or _("Automatic: on devices with direction keys"),
                h = 64, toggle = page.browser.settings.key_nav == true, action = { kind = "key-nav" } }),
        })),
    }
end

local function bodyFor(page, view, w, compact)
    if view == "profile" then return profileBody(page, w) end
    if view == "opening" then return openingBody(page, w, compact) end
    if view == "home" then return homeBody(page, w, compact) end
    if view == "topmenu" then return topMenuBody(page, w, compact) end
    if view == "reader" then return readerBody(page, w, compact) end
    if view == "library" then return libraryBody(page, w) end
    if view == "portraits" then return portraitsBody(page, w) end
    if view == "xray" then return xrayBody(page, w) end
    if view == "night" then return nightBody(page, w, compact) end
    return aboutBody(page, w)
end

-- ------------------------------------------------------------------ build
-- A page's items in pages of at most `room` high, kept whole (a group is
-- never cut in two); a page does not start with a gap.
function Settings.split(body, room)
    local pages, cur, h = {}, {}, 0
    for _i, item in ipairs(body) do
        if item then
            local ih = item._flex and 0 or item:getSize().h
            -- A gap (an empty span) at the top of a page is left out.
            local gap = item._flex or item.width ~= nil and item[1] == nil and item.dimen == nil
            if #cur > 0 and h + ih > room then
                pages[#pages + 1] = cur
                cur, h = {}, 0
            end
            if not (#cur == 0 and gap) then
                cur[#cur + 1] = item
                h = h + ih
            end
        end
    end
    if #cur > 0 then pages[#pages + 1] = cur end
    if #pages == 0 then pages[1] = {} end
    return pages
end

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
        local room = avail - header:getSize().h - px(8)
        if heightOf(body) > room then
            -- Still too tall (a large interface size, a long page): in pages,
            -- turned with the arrows at the foot or a swipe.
            local pager_h = px(40) + px(8)
            local pages = Settings.split(body, room - pager_h)
            local key = view .. "#" .. #page.stack
            page.sub_pages = page.sub_pages or {}
            local at = math.max(1, math.min(#pages, page.sub_pages[key] or 1))
            page.sub_pages[key], page.sub_count, page.sub_key = at, #pages, key
            for _i, item in ipairs(pages[at]) do table.insert(items, item) end
            table.insert(items, flex(px(8)))
            table.insert(items, require("aleph_text_pages").pager(w, at, #pages))
        else
            page.sub_count, page.sub_key = 1, nil
            for _i, item in ipairs(body) do table.insert(items, item) end
        end
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

-- The yearly goal can be typed: as ambitious as wanted, within reason.
local GOAL_MAX = 100000

-- Home's numbers again, once: 1.5 seconds after the last change.
local home_refresh
local function refreshHomeSoon(browser)
    if home_refresh then UIManager:unschedule(home_refresh) end
    home_refresh = function()
        home_refresh = nil
        if not browser.closed then browser:refreshData() end
    end
    UIManager:scheduleIn(1.5, home_refresh)
end

-- The next or previous page of a Settings page in pages.
function Settings.turn(page, delta)
    local key = page.sub_key
    if not key or (page.sub_count or 1) <= 1 then return end
    local at = math.max(1, math.min(page.sub_count, (page.sub_pages[key] or 1) + (delta or 0)))
    if at == page.sub_pages[key] then return end
    page.sub_pages[key] = at
    page:refresh()
end

-- What a tap in Settings does, by the action's kind: one function each,
-- given the page, the action, Home (the browser) and its settings. onAction
-- finds the kind's function here.
local ACTIONS = {}

ACTIONS["page"] = function(page, action, browser, settings)
    Settings.turn(page, action.delta or 0)
end

ACTIONS["edit-name"] = function(page, action, browser, settings)
    browser:input(_("Your name"), settings.display_name, function(v)
        browser:persistSetting("display_name", v)
        browser:refreshData()
        page:refresh()
    end)
end

ACTIONS["goal"] = function(page, action, browser, settings)
    -- The page answers at once; Home (rebuilt whole, about a second on
    -- a Kindle) only once the taps stop, not once per tap.
    local goal = math.max(1, math.min(GOAL_MAX, (tonumber(settings.year_goal) or 12) + action.delta))
    browser:persistSetting("year_goal", goal)
    page:refresh()
    refreshHomeSoon(browser)
end

ACTIONS["goal-type"] = function(page, action, browser, settings)
    browser:input(_("Annual reading goal"), tostring(tonumber(settings.year_goal) or 12), function(v)
        local n = tonumber((tostring(v or ""):gsub("[^%d]", "")))
        if not n or n < 1 then return browser:message(_("Type a whole number of books, 1 or more.")) end
        n = math.min(GOAL_MAX, math.floor(n))
        browser:persistSetting("year_goal", n)
        page:refresh()
        refreshHomeSoon(browser)
    end, _("Save"), _("Books to finish this year"), "number")
end

ACTIONS["open-home"] = function(page, action, browser, settings)
    browser:persistSetting("open_home", action.value)
    page:refresh()
end

-- Settings > X-Ray.
ACTIONS["xray-set"] = function(page, action, browser, settings)
    browser:persistSetting(action.key, action.value)
    page:refresh()
end

-- Another provider: the model named for the one before is not this one's.
ACTIONS["xray-provider"] = function(page, action, browser, settings)
    if settings.xray_ai_provider ~= action.id then
        browser:persistSetting("xray_ai_provider", action.id)
        browser:persistSetting("xray_ai_model", nil)
    end
    page:refresh()
end

-- Never, 1 week, 2 weeks, 1 month, and round again.
ACTIONS["xray-recap-days"] = function(page, action, browser, settings)
    local steps = { 0, 7, 14, 30 }
    local now = tonumber(settings.xray_recap_days) or 14
    local at = 1
    for i, v in ipairs(steps) do if v == now then at = i end end
    browser:persistSetting("xray_recap_days", steps[at % #steps + 1])
    page:refresh()
end

ACTIONS["xray-input"] = function(page, action, browser, settings)
    local titles = { xray_ai_key = _("Provider key"), xray_ai_model = _("Model"), xray_ai_url = _("Address") }
    local current = settings[action.key]
    if action.key == "xray_ai_model" and (current == nil or current == "") then current = require("aleph_xr_ai").config().model end
    browser:input(titles[action.key], current or "", function(v)
        v = tostring(v or ""):gsub("^%s+", ""):gsub("%s+$", "")
        browser:persistSetting(action.key, v ~= "" and v or nil)
        page:refresh()
    end)
end

ACTIONS["portraits-toggle"] = function(page, action, browser, settings)
    browser:persistSetting("author_portraits", action.value)
    if not action.value then require("aleph_portraits").cancel() end
    page:refresh()
end

ACTIONS["portraits-download"] = function(page, action, browser, settings)
    local minutes = math.max(1, math.ceil(action.pending / 60))
    confirm(_("Download author portraits"),
        T(_("This looks up %1 authors on Open Library and Wikipedia, about one a second (around %2 minutes), and needs Wi-Fi to stay on. Only the names are sent. You can stop it any time, and the Authors list shows portraits as they arrive."), action.pending, minutes),
        _("Download"), function()
            require("ui/network/manager"):runWhenOnline(function()
                local Portraits = require("aleph_portraits")
                Portraits.downloadAll(authorNames(browser), function() if not page.closed then page:refresh() end end, function(found, total)
                    try(function() require("aleph_toast").show(T(_("Author portraits: %1 found, %2 looked up"), found, total)) end)
                    if not page.closed then page:refresh() end
                end)
                page:refresh()
            end)
        end)
end

ACTIONS["portraits-cancel"] = function(page, action, browser, settings)
    require("aleph_portraits").cancel()
    page:refresh()
end

ACTIONS["portraits-clear"] = function(page, action, browser, settings)
    confirm(_("Remove portraits"), _("The downloaded portraits are deleted from this device. They can be downloaded again."), _("Remove"), function()
        require("aleph_portraits").clear()
        page:refresh()
    end)
end

ACTIONS["shortcut"] = function(page, action, browser, settings)
    local apply = function()
        local gestures = browser.plugin and browser.plugin.ui and browser.plugin.ui.gestures
        if not Shortcut.apply(gestures, action.id or nil) then
            try(function() require("aleph_toast").show(_("Turn on KOReader's Gestures plugin first: Settings, Taps and gestures.")) end)
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
end

ACTIONS["topbar"] = function(page, action, browser, settings)
    browser:persistSetting("topbar", action.value)
    try(function() require("aleph_topbar").sync(browser.plugin) end)
    page:refresh()
end

ACTIONS["topmenu-apps"] = function(page, action, browser, settings)
    require("aleph_topmenu_page").openApps(browser.plugin and browser.plugin.ui, browser.plugin.path,
        function() if not page.closed then page:refresh() end end)
end

ACTIONS["topmenu-tab-icon"] = function(page, action, browser, settings)
    local TopMenu = require("aleph_topmenu_page")
    TopMenu.pickIcon(browser.plugin.path, action.label, TopMenu.read(action.key), action.default, function(value)
        TopMenu.save(action.key, value)
        if not page.closed then page:refresh() end
    end)
end

ACTIONS["topmenu-outline"] = function(page, action, browser, settings)
    local TopMenu = require("aleph_topmenu_page")
    TopMenu.save("outline", TopMenu.read("outline", true) == false)
    page:refresh()
end

ACTIONS["topmenu-slider"] = function(page, action, browser, settings)
    require("aleph_topmenu_page").save(action.key, action.value)
    page:refresh()
end

ACTIONS["reader-sheet"] = function(page, action, browser, settings)
    browser:persistSetting("reader_sheet", action.value)
    page:refresh()
end

ACTIONS["bookmark-color-ask"] = function(page, action, browser, settings)
    browser:persistSetting("bookmark_color_ask", action.value)
    page:refresh()
end

ACTIONS["page-browser-swipe"] = function(page, action, browser, settings)
    browser:persistSetting("page_browser_swipe", action.value)
    page:refresh()
end

ACTIONS["pins-place"] = function(page, action, browser, settings)
    require("aleph_pins").openPlacer(nil, function() if not page.closed then page:refresh() end end)
end

ACTIONS["pins-left"] = function(page, action, browser, settings)
    browser:persistSetting("pins_left", action.value)
    page:refresh()
end

ACTIONS["style-dialogs"] = function(page, action, browser, settings)
    browser:persistSetting("style_dialogs", action.value)
    try(function() require("aleph_theme").sync() end)
    page:refresh()
end

ACTIONS["customize"] = function(page, action, browser, settings)
    page:close()
    browser.mode = "home"
    browser:updateItems()
    browser:boardEnterEdit()
end

ACTIONS["preset"] = function(page, action, browser, settings)
    if BoardStore.read(settings).preset == action.value then return true end
    confirm(_("Start Home from this layout?"), _("Your pages are replaced by this layout's pages."), _("Replace"), function()
        browser:persistSetting(BoardStore.SETTING_KEY, BoardStore.withPreset(settings, action.value))
        browser:updateItems()
        page:refresh()
    end)
end

ACTIONS["tiles"] = function(page, action, browser, settings)
    browser:boardSetTiles(action.value)
    page:refresh()
end

ACTIONS["colour"] = function(page, action, browser, settings)
    browser:boardSetColour(action.value)
    page:refresh()
end

-- The night profile's settings (aleph_night.lua): saved, and shown at once
-- when night mode is on.
ACTIONS["night-set"] = function(page, action, browser, settings)
    local Night = require("aleph_night")
    local c = Night.config()
    local was_on = c.on
    c[action.key] = action.value
    Night.save(c)
    if action.key == "auto" then Night.scheduleChanged()
    elseif action.key == "on" and was_on ~= c.on then Night.toggled(c.on)
    elseif action.key == "boost" then Night.applyText()
    elseif action.key == "light" then Night.preview(c) end
    page:refresh()
end
ACTIONS["night-time"] = function(page, action, browser, settings)
    local Night = require("aleph_night")
    local c = Night.config()
    c[action.key] = (c[action.key] + action.delta) % 1440
    Night.save(c)
    Night.scheduleChanged()
    page:refresh()
end
ACTIONS["night-step"] = function(page, action, browser, settings)
    local Night = require("aleph_night")
    local c = Night.config()
    local lo = action.key == "brightness" and Night.STEP or 0
    c[action.key] = math.max(lo, math.min(100, (c[action.key] or 0) + action.delta))
    Night.save(c)
    Night.preview(c)
    page:refresh()
end
ACTIONS["night-take"] = function(page, action, browser, settings)
    local Night = require("aleph_night")
    local c = Night.config()
    local light = Night.readLight()
    local Device = require("device")
    local pd = Device:hasFrontlight() and Device:getPowerDevice()
    if light and light.intensity and pd then
        c.brightness = Night.toPercent(light.intensity, pd.fl_min, pd.fl_max)
        if light.warmth and Night.hasWarmth() then c.warmth = math.floor(light.warmth / Night.STEP + 0.5) * Night.STEP end
        Night.save(c)
        try(function() require("aleph_toast").show(_("Night light set from the light now"), { icon = "check" }) end)
    end
    page:refresh()
end

ACTIONS["ui-scale"] = function(page, action, browser, settings)
    local value = action.value
    if action.delta then value = BoardMetrics.stepUserScale(settings.ui_scale, action.delta) end
    if BoardMetrics.normalizeUserScale(settings.ui_scale) == value and settings.ui_scale ~= nil then return true end
    browser:persistSetting("ui_scale", BoardMetrics.setUserScale(value))
    try(function() require("aleph_theme").sync() end)
    browser:updateItems()
    page:refresh()
end

ACTIONS["reset-home"] = function(page, action, browser, settings)
    confirm(_("Reset Home?"), _("Your pages and tile style go back to how they started."), _("Reset"), function()
        local state = BoardStore.withPreset(settings, BoardStore.read(settings).preset)
        state.tiles = "outline"
        browser:persistSetting(BoardStore.SETTING_KEY, state)
        browser:updateItems()
        page:refresh()
    end)
end

ACTIONS["goodreads-background"] = function(page, action, browser, settings)
    browser:persistSetting("goodreads_background", action.value and true or false)
    -- A book open behind Settings follows at once; otherwise the next one opened.
    try(function()
        local ReaderUI = package.loaded["apps/reader/readerui"]
        local ui = ReaderUI and rawget(ReaderUI, "instance")
        if ui then require("aleph_goodreads_track").sync(ui) end
    end)
    page:refresh()
end

ACTIONS["goodreads-import"] = function(page, action, browser, settings)
    require("aleph_goodreads_import").start(browser)
end

ACTIONS["folder-add"] = function(page, action, browser, settings)
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
end

ACTIONS["folder-remove"] = function(page, action, browser, settings)
    local path = settings.library_roots[action.index]
    if not path then return true end
    confirm(_("Remove this folder?"), path .. "\n\n" .. _("Its books leave the library index. The files stay where they are."), _("Remove"), function()
        table.remove(settings.library_roots, action.index)
        browser:persistSetting("library_roots", settings.library_roots)
        browser:startScan()
        page:refresh()
    end)
end

ACTIONS["refresh"] = function(page, action, browser, settings)
    if browser.scanning then browser:cancelScan() else browser:startScan() end
    page:refresh()
end

ACTIONS["cover-shape"] = function(page, action, browser, settings)
    browser:persistSetting("cover_shape", action.value ~= "fit" and action.value or nil)
    try(function() require("aleph_board_ui").clearCoverCache() end)
    browser:updateItems()
    page:refresh()
end

ACTIONS["extra-filters"] = function(page, action, browser, settings)
    if settings.extra_filters == true then
        browser:persistSetting("extra_filters", false)
        browser:dropExtraFilters()
        page:refresh()
    else
        local count = #(browser.local_library.books or {})
        confirm(_("Turn on the extra filters?"),
            T(_("Language, Pages and Released will be added to the library's Sort and filter.\n\nTo find each book's page count and release date, Aleph opens every book once and reads its details. The first time this takes a lot of time, memory and battery, more so with a big library (yours has %1 books): it can take several minutes, and the device may feel slow until it finishes. Keep it plugged in if you can. After that, a book is only read again when its file changes."), count),
            _("Turn on"), function()
                browser:persistSetting("extra_filters", true)
                if browser.scanning then browser:cancelScan() end
                browser:startScan()
                page:refresh()
            end)
    end
end

ACTIONS["key-nav"] = function(page, action, browser, settings)
    browser:persistSetting("key_nav", not (settings.key_nav == true))
    page:refresh()
end

ACTIONS["debug-log"] = function(page, action, browser, settings)
    browser:persistSetting("debug_log", not (settings.debug_log == true))
    page:refresh()
end

ACTIONS["legal"] = function(page, action, browser, settings)
    browser:showAbout()
end

ACTIONS["link"] = function(page, action, browser, settings)
    if Device.openLink then Device:openLink("https://github.com/bookorbit/bookorbit")
    else browser:message("https://github.com/bookorbit/bookorbit") end
end

-- A row that opens another page of Settings, or a page of its own.
ACTIONS["view"] = function(page, action, browser, settings)
    if action.view == "margins" then
        -- A page of its own (it also opens from a book's Tools menu).
        require("aleph_bookends_page").open(browser.plugin and browser.plugin.ui)
    elseif action.view == "actions" then
        require("aleph_actions_page").open(browser)
    elseif action.view == "goodreads" then
        require("aleph_goodreads").open(browser.plugin and browser.plugin.ui)
    else
        if page.sub_pages then page.sub_pages[action.view .. "#" .. (#page.stack + 1)] = nil end
        table.insert(page.stack, action.view)
        page:refresh()
    end
end

local function onAction(page, action)
    local browser = page.browser
    local handler = ACTIONS[action.kind]
    if handler then
        local result = handler(page, action, browser, browser.settings)
        if result ~= nil then return result end
    end
    return true
end

-- Back steps out of a group before it closes Settings.
local function onBack(page)
    if #page.stack > 1 then
        if page.sub_pages then page.sub_pages[page.stack[#page.stack] .. "#" .. #page.stack] = nil end
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
        -- A page of Settings too tall for the screen comes in pages.
        on_swipe = function(p, ges)
            if (p.sub_count or 1) <= 1 then return false end
            if ges.direction == "west" then Settings.turn(p, 1) return true end
            if ges.direction == "east" then Settings.turn(p, -1) return true end
            return false
        end,
        on_page_key = function(p, delta) Settings.turn(p, delta) end,
        browser = browser,
        stack = stack,
        gestures_data = gesturesData(browser),
    }
    UIManager:show(page, "ui")
    return page
end

return Settings
