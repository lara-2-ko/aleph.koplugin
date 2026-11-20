-- Aleph modification, 2026-11-18: choosing Aleph's fonts.
--[[--
Two choices, from the fonts KOReader has (its own and those in its fonts
folder, the list of its font menu):

  Home and widgets   Settings > Home > Font: Home, its widgets, the
                     library, book pages, sheets and Aleph's windows
                     (aleph.font_home)
  Top menu           Settings > Top menu > Font, "Same as Home" unless
                     chosen (aleph.font_menu); and its Text size, 80% to
                     150% of the rest (aleph.menu_scale), which sizes the
                     whole top menu with it: rows, icons, tabs

A choice is { name = family, file = regular, italic = italic or nil }; no
choice is Noto Sans, KOReader's own. Only the sans faces change: the serif
of quotes (highlights, the literary clock) stays Noto Serif.

Light: KOReader opens a font once and keeps it (a few hundred KB to about
1 MB for one it has not opened already); drawing is no slower with any
font. The list is read from KOReader's own font cache, once per session,
and a page of the picker opens only the fonts it shows.
]]

local lfs = require("libs/libkoreader-lfs")

local Fonts = {}

Fonts.MENU_SCALES = { 0.8, 0.85, 0.9, 0.95, 1, 1.1, 1.2, 1.3, 1.4, 1.5 }

local function prefs()
    local ok, p = pcall(function() return require("aleph_prefs").get() end)
    return ok and type(p) == "table" and p or {}
end

local function fontDir()
    local ok, dir = pcall(function() return require("fontlist").fontdir end)
    return ok and type(dir) == "string" and dir or "./fonts"
end

-- A path KOReader's Font:getFace can open: under its own fonts folder, the
-- part after it (opened directly); elsewhere, the whole path.
local function shortPath(path)
    local dir = fontDir():gsub("/$", "") .. "/"
    if path:sub(1, #dir) == dir then return path:sub(#dir + 1) end
    return path
end

local function exists(file)
    if type(file) ~= "string" or file == "" then return false end
    if file:sub(1, 1) == "/" then return lfs.attributes(file, "mode") == "file" end
    return lfs.attributes(fontDir() .. "/" .. file, "mode") == "file"
end
Fonts.exists = exists

-- KOReader looks for a font it cannot open directly with a Lua pattern of
-- its path: one with pattern characters in it is not offered.
local function safe(path)
    return not path:find("[%%%(%)%[%]%+%*%?%^%$]")
end

local list_cache

-- The fonts, one per family: { name, file, italic }, by name.
function Fonts.list()
    if list_cache then return list_cache end
    local families = {}
    pcall(function()
        local FontList = require("fontlist")
        FontList:getFontList()
        for path, faces in pairs(FontList.fontinfo or {}) do
            local info = type(faces) == "table" and faces[1]
            if type(info) == "table" and type(info.name) == "string" and info.name ~= "" and safe(path) then
                local f = families[info.name] or { name = info.name }
                families[info.name] = f
                if not info.bold and not info.italic then
                    -- Two regulars: the shorter path (the plain one, not a variant)
                    if not f.file or #path < #f.path then f.file, f.path = shortPath(path), path end
                elseif info.italic and not info.bold then
                    f.italic = f.italic or shortPath(path)
                elseif not f.any then
                    f.any = shortPath(path)
                end
            end
        end
    end)
    local out = {}
    for _n, f in pairs(families) do
        f.file = f.file or f.any
        f.any, f.path = nil, nil
        if f.file then out[#out + 1] = f end
    end
    table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
    list_cache = out
    return out
end

function Fonts._resetList() list_cache = nil end

local function valid(choice)
    return type(choice) == "table" and exists(choice.file) and choice or nil
end

-- Home's font: the choice, or nil (Noto Sans).
function Fonts.home() return valid(prefs().font_home) end

-- The top menu's font: its own choice, else Home's, else nil.
function Fonts.menu()
    local own = prefs().font_menu
    if own == "noto" then return nil end
    return valid(own) or Fonts.home()
end

-- The top menu's own setting as chosen: "same", "noto" or a choice.
function Fonts.menuSetting()
    local own = prefs().font_menu
    if own == "noto" then return "noto" end
    return valid(own) or "same"
end

function Fonts.menuScale()
    local v = tonumber(prefs().menu_scale) or 1
    local best = 1
    for _i, s in ipairs(Fonts.MENU_SCALES) do
        if math.abs(s - v) < math.abs(best - v) then best = s end
    end
    return best
end

-- Puts Home's font in force (BoardMetrics' sans faces). At load and after
-- each change.
function Fonts.apply()
    local BoardMetrics = require("aleph_board_metrics")
    local c = Fonts.home()
    BoardMetrics.setSans(c and c.file or nil, c and (c.italic or c.file) or nil)
    -- Measured, laid out and chosen again with the new font.
    local ok, BoardUI = pcall(require, "aleph_board_ui")
    if ok and BoardUI.resetFits then BoardUI.resetFits() end
end

return Fonts
