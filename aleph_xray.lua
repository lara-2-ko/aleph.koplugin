-- Aleph modification, 2026-11-09: X-Ray (xray.koplugin) in the reader
-- menu, in the board's style.
--[[--
When the X-Ray plugin is installed and on, the reader menu's This book tab has
an X-Ray row (with what it knows about the book), and the author's name at the
top of the menu opens X-Ray's author info.

The X-Ray sheet: six tiles, two to a row, each with its icon, name and how
many entries X-Ray has:

  Characters   Timeline   Historical Figures   Locations   Glossary
  Images & Maps

then About the author and All X-Ray options (its own full menu: fetching,
updating, settings). A tile opens X-Ray's own list for it; the sheet closes
first. Without X-Ray data for the book yet, the tiles stay and a note with
Fetch X-Ray data sits above them.

Only X-Ray's own methods are called (showCharacters, showTimeline,
showHistoricalFigures, showLocations, showTerms, showImages, showAuthorInfo,
showFullXRayMenu, fetchFromAI, getMenuCounts), each guarded; nothing of
X-Ray is changed.
]]

local UIManager = require("ui/uimanager")
local T = require("ffi/util").template
local _ = require("gettext")

local BoardMetrics = require("aleph_board_metrics")
local BoardUI = require("aleph_board_ui")
local MenuUI = require("aleph_menu_ui")
local SheetUI = require("aleph_sheet_ui")

local INK = BoardMetrics.INK
local px = BoardMetrics.px
local text, vstack, hstack, space, flex, icon = BoardUI.text, BoardUI.vstack, BoardUI.hstack, BoardUI.space, BoardUI.flex, BoardUI.icon
local floor = math.floor

local Xray = {}

Xray.SECTIONS = {
    { id = "characters", count = "characters", icon = "users", method = "showCharacters", label = function() return _("Characters") end },
    { id = "timeline", count = "timeline", icon = "hourglass", method = "showTimeline", label = function() return _("Timeline") end },
    { id = "historical", count = "historical_figures", icon = "landmark", method = "showHistoricalFigures", label = function() return _("Historical Figures") end },
    { id = "locations", count = "locations", icon = "map-pin", method = "showLocations", label = function() return _("Locations") end },
    { id = "glossary", count = "terms", icon = "book-marked", method = "showTerms", label = function() return _("Glossary") end },
    { id = "images", count = "images", icon = "image", method = "showImages", label = function() return _("Images & Maps") end },
}

-- X-Ray's gesture actions, for when its code is loaded but its instance
-- cannot be reached: the same views, opened through KOReader's Dispatcher.
local ACTIONS = {
    showCharacters = "xray_characters", showTimeline = "xray_timeline",
    showHistoricalFigures = "xray_historical_figures", showLocations = "xray_locations",
    showTerms = "xray_terms", showImages = "xray_open_image_gallery",
    showFullXRayMenu = "xray_full_menu", showAuthorInfo = "xray_full_menu",
    fetchFromAI = "xray_full_menu",
}

-- The X-Ray plugin of this reader, when it is installed and on: its instance
-- (found the way aleph_plugins.lua finds plugins), or, when only its
-- code is loaded, a stand-in that runs its gesture actions.
function Xray.plugin(ui)
    local Plugins = require("aleph_plugins")
    local plugin = Plugins.find("xray", ui, function(p) return type(p.showCharacters) == "function" end)
    if plugin then return plugin end
    if not (Plugins.loaded("xray_ui") or Plugins.loaded("xray_data")) then return nil end
    local proxy = { _proxy = true }
    for method, action in pairs(ACTIONS) do
        proxy[method] = function() Plugins.dispatch(ui, action) end
    end
    proxy.hasXRayData = function() return true end
    proxy.getMenuCounts = function() return {} end
    return proxy
end

function Xray.counts(plugin)
    local ok, counts = pcall(function() return plugin:getMenuCounts() end)
    return ok and type(counts) == "table" and counts or {}
end

-- "42 characters · 12 locations", or nil when X-Ray has nothing yet.
function Xray.summary(plugin)
    local c = Xray.counts(plugin)
    local parts = {}
    local function add(n, one, many)
        n = tonumber(n) or 0
        if n > 0 then parts[#parts + 1] = n == 1 and one or T(many, n) end
    end
    add(c.characters, _("1 character"), _("%1 characters"))
    add(c.locations, _("1 location"), _("%1 locations"))
    add(c.terms, _("1 term"), _("%1 terms"))
    if #parts == 0 then return nil end
    while #parts > 2 do table.remove(parts) end
    return table.concat(parts, " · ")
end

function Xray.hasData(plugin)
    local ok, has = pcall(function() return plugin:hasXRayData() end)
    if ok then return has and true or false end
    return Xray.summary(plugin) ~= nil
end

-- Runs one of X-Ray's methods after the sheet has closed.
local function run(plugin, method)
    UIManager:nextTick(function()
        local fn = plugin[method]
        if type(fn) ~= "function" then return end
        local ok, err = pcall(fn, plugin)
        if not ok then require("logger").warn("Aleph: X-Ray", method, "failed:", err) end
    end)
end
Xray.run = run

-- ----------------------------------------------------------------- tiles
local function tile(w, section, n)
    local h = px(78)
    local b = math.max(1, px(1.25))
    local iw = w - 2 * b - 2 * px(12)
    local count = (tonumber(n) or 0) > 0 and tostring(n) or "—"
    local inner = vstack({ w = iw }, {
        space(nil, px(10)),
        hstack({ w = iw }, { icon(section.icon, px(22), { sw = 2.25 }), flex(0), text(count, { s = 15, b = true, col = (tonumber(n) or 0) > 0 and INK.black or INK.g6 }) }),
        space(nil, px(8)),
        text(section.label(), { s = 14, b = true, w = iw, data = true }),
    })
    local box = BoardUI.box({ w = w, h = h, radius = px(12), border = b, border_col = INK.g6, bg = INK.white },
        hstack({ w = w - 2 * b, h = h - 2 * b, valign = "top" }, { space(px(12), 1), inner }))
    return BoardUI.hit(box, { kind = "section", id = section.id })
end

local function body(sheet, w)
    local plugin = sheet.plugin
    local counts = Xray.counts(plugin)
    local items = { SheetUI.titleRow(w, _("X-Ray"), sheet.book_title) }
    if not Xray.hasData(plugin) then
        items[#items + 1] = SheetUI.note(w, "info", _("No X-Ray data for this book yet. Fetch it once, then everything below fills in."), { col = INK.g3 })
        items[#items + 1] = SheetUI.pillRow(w, { { label = _("Fetch X-Ray data"), icon = "download", action = { kind = "fetch" } } })
    end
    local gap = px(10)
    local cw = floor((w - gap) / 2)
    for i = 1, #Xray.SECTIONS, 2 do
        local a, b = Xray.SECTIONS[i], Xray.SECTIONS[i + 1]
        items[#items + 1] = hstack({ w = w, gap = gap }, {
            tile(cw, a, counts[a.count]),
            b and tile(w - gap - cw, b, counts[b.count]) or false,
        })
    end
    local iw = MenuUI.rowsIn(w)
    local author = sheet.author and sheet.author ~= "" and T(_("About %1"), sheet.author) or _("About the author")
    items[#items + 1] = MenuUI.group(w, {
        MenuUI.row(iw, { icon = "feather", label = author, sub = _("X-Ray's author info"), chevron = true, h = 58, action = { kind = "author" } }),
        MenuUI.row(iw, { icon = "sliders-horizontal", label = _("All X-Ray options"), sub = _("Fetch, update and settings"), chevron = true, h = 58, action = { kind = "full" } }),
    })
    return items
end

-- book_title, author: as the reader menu shows them.
function Xray.open(ui, o)
    local plugin = Xray.plugin(ui)
    if not plugin then return nil end
    o = o or {}
    return SheetUI.open{
        name = "aleph_xray",
        plugin = plugin,
        book_title = o.title,
        author = o.author,
        build = function(sheet, sw, sh)
            return SheetUI.sheet(sheet, sw, sh, function(w) return body(sheet, w) end, { pop_w = 540 })
        end,
        on_action = function(sheet, action)
            local k = action.kind
            if k == "section" then
                for _i, s in ipairs(Xray.SECTIONS) do
                    if s.id == action.id then sheet:close(); run(plugin, s.method) end
                end
            elseif k == "author" then sheet:close(); run(plugin, "showAuthorInfo")
            elseif k == "full" then sheet:close(); run(plugin, "showFullXRayMenu")
            elseif k == "fetch" then sheet:close(); run(plugin, "fetchFromAI")
            end
            return true
        end,
    }
end

return Xray
