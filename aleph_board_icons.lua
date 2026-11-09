-- Modified for Aleph, 2026-11-07. Unofficial local-only fork. See NOTICE.
--[[--
Icons for the widget dashboard, drawn from Lucide (https://lucide.dev, ISC
license) path data so they match the web app.

KOReader renders SVG files, so each icon is written once per colour, stroke
width and fill into the plugin's cache directory and reused after that. An
icon is a few hundred bytes; a full board needs a few dozen.
]]

local DataStorage = require("datastorage")
local IconWidget = require("ui/widget/iconwidget")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")

local BoardIcons = {}

-- The drawings (aleph_icon_data.lua), loaded only when an icon's file has to
-- be written: after the first run the icons in use are all in the cache.
local NODES
local function nodes()
    if not NODES then NODES = require("aleph_icon_data") end
    return NODES
end

local dir = nil
local written = {}
local missing = {}

local function cacheDir()
    if not dir then
        dir = DataStorage:getDataDir() .. "/cache/aleph/icons"
        util.makePath(dir)
    end
    return dir
end

local function attrs(tbl)
    local keys = {}
    for k in pairs(tbl) do table.insert(keys, k) end
    table.sort(keys)
    local out = {}
    for _, k in ipairs(keys) do
        table.insert(out, k .. '="' .. tbl[k] .. '"')
    end
    return table.concat(out, " ")
end

-- The SVG source for one icon. fill colours the closed shapes too (the play
-- triangle, a filled quote).
function BoardIcons.svg(name, color, stroke_width, fill)
    local list = nodes()[name]
    if not list then return nil end
    local body = {}
    for _, node in ipairs(list) do
        table.insert(body, "<" .. node[1] .. " " .. attrs(node[2]) .. "/>")
    end
    return string.format(
        '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="%s" stroke="%s" stroke-width="%s" stroke-linecap="round" stroke-linejoin="round">%s</svg>',
        fill and color or "none", color, tostring(stroke_width), table.concat(body))
end

-- Path to the cached SVG file, written on first use.
function BoardIcons.file(name, color, stroke_width, fill)
    color = color or "#000000"
    stroke_width = stroke_width or 2
    local key = string.format("%s-%s-%s%s", name, color:gsub("#", ""), tostring(stroke_width):gsub("%.", "_"), fill and "-f" or "")
    local path = cacheDir() .. "/" .. key .. ".svg"
    if written[path] then return path end
    if missing[name] then return nil end
    if lfs.attributes(path, "mode") ~= "file" then
        local svg = BoardIcons.svg(name, color, stroke_width, fill)
        if not svg then missing[name] = true; return nil end
        local f = io.open(path, "w")
        if not f then return nil end
        f:write(svg)
        f:close()
    end
    written[path] = true
    return path
end

-- An IconWidget of size px. opts: color (hex), sw (stroke width), fill.
function BoardIcons.widget(name, size, opts)
    opts = opts or {}
    local path = BoardIcons.file(name, opts.color, opts.sw or 2, opts.fill)
    return IconWidget:new{
        file = path,
        width = size,
        height = size,
        alpha = true,
    }
end

function BoardIcons.has(name)
    return nodes()[name] ~= nil
end

-- An icon as SVG elements on its 24 grid, for drawing inside a larger
-- picture (a medal). Nil when the plugin does not have it.
function BoardIcons.markup(name)
    local list = nodes()[name]
    if not list then return nil end
    local body = {}
    for _, node in ipairs(list) do
        table.insert(body, "<" .. node[1] .. " " .. attrs(node[2]) .. "/>")
    end
    return table.concat(body)
end

return BoardIcons
