-- Aleph modification, 2026-11-14: Aleph's screens with the direction keys.
--[[--
Home, the library, a book's page and Aleph's panels are made for a finger:
every control is an area that answers a tap. On a device with direction
keys and no touch screen (a Kindle 4, a keyboard Kindle) nothing could be
reached. Here a mark is moved from one tappable area to the next with Up,
Down, Left and Right, and Press taps the marked one.

    KeyNav.install(class)     adds the key handlers to a screen's class
    KeyNav.keys(screen)       in its init: the key events, when wanted
    KeyNav.paint(screen, bb)  at the end of its paintTo: the mark

The screen needs nothing else: what can be tapped is found on the screen
itself (KeyNav.collect: the widgets under screen[1] that answer a tap, and
the hit areas they hold; or screen.hits where the screen keeps its own
list, as panels do), and Press sends the screen a tap at the middle of the
marked area, so it does exactly what a finger there would do. The mark is
kept as a point, not as a widget: these screens build their widgets again
on every change, and the mark lands on whatever is at that point after.

A screen may define navEdge(dx, dy), called when there is nothing further
in that direction (Home turns its page with it).

Wanted when the device has direction keys, or when Settings > About >
Button navigation is on (aleph.key_nav), which is there to try it with a
keyboard or a controller on a touch device. Aleph's menu pages
(aleph_menu_page.lua) had the same from BookOrbit and choose the next area
with KeyNav.next too.
]]

local Geom = require("ui/geometry")
local BoardMetrics = require("aleph_board_metrics")
local Prefs = require("aleph_prefs")

local px = BoardMetrics.px

local KeyNav = {}

function KeyNav.enabled()
    local ok, dpad = pcall(function() return require("device"):hasDPad() end)
    if ok and dpad then return true end
    return Prefs.is("key_nav")
end

local function centre(d)
    return d.x + d.w / 2, d.y + d.h / 2
end

local function inside(d, x, y)
    return x >= d.x and x < d.x + d.w and y >= d.y and y < d.y + d.h
end

local function placed(d)
    return type(d) == "table" and d.x and d.y and d.w and d.h and d.w > 0 and d.h > 0
end

-- The gap between two spans (a start and a length each); 0 when they overlap.
local function gap(a, alen, b, blen)
    if b >= a + alen then return b - (a + alen) end
    if a >= b + blen then return a - (b + blen) end
    return 0
end

-- How far `d` begins beyond `c` in direction (dx, dy): the gap between
-- their facing edges, or nil when d does not lie wholly that way.
local function beyond(c, d, dx, dy)
    local slack = 2
    if dx > 0 then return d.x >= c.x + c.w - slack and d.x - (c.x + c.w) or nil end
    if dx < 0 then return d.x + d.w <= c.x + slack and c.x - (d.x + d.w) or nil end
    if dy > 0 then return d.y >= c.y + c.h - slack and d.y - (c.y + c.h) or nil end
    return d.y + d.h <= c.y + slack and c.y - (d.y + d.h) or nil
end

-- The index of the area to go to from areas[from] in direction (dx, dy).
-- First among the areas lying wholly that way: the nearest, one straight
-- ahead (overlapping it, seen along the direction: a wide tile over two
-- narrow ones is straight above both) before one off to the side. When
-- there is none (an area inside or around this one), the nearest whose
-- middle lies that way. nil when there is nothing. Areas are tables with a
-- `dimen`.
function KeyNav.next(areas, from, dx, dy)
    local current = areas[from]
    if not current or not placed(current.dimen) then return nil end
    local c = current.dimen
    local cx, cy = centre(c)
    local best, best_score, loose, loose_score
    for index, area in ipairs(areas) do
        if index ~= from and placed(area.dimen) then
            local d = area.dimen
            local ax, ay = centre(d)
            local along = (ax - cx) * dx + (ay - cy) * dy
            local edge = beyond(c, d, dx, dy)
            if edge then
                local across
                if dx ~= 0 then across = gap(c.y, c.h, d.y, d.h) else across = gap(c.x, c.w, d.x, d.w) end
                local score = math.max(0, edge) + across * 2 + along * 0.001
                if not best_score or score < best_score then best, best_score = index, score end
            elseif along > 1 then
                local across = math.abs((ax - cx) * dy) + math.abs((ay - cy) * dx)
                local score = along + across * 2
                if not loose_score or score < loose_score then loose, loose_score = index, score end
            end
        end
    end
    return best or loose
end

-- Whether a widget answers a tap of its own.
local function tappable(w)
    local ges = rawget(w, "ges_events")
    if type(ges) ~= "table" then return false end
    for _name, seq in pairs(ges) do
        local range = type(seq) == "table" and seq[1]
        if type(range) == "table" and range.ges == "tap" then return true end
    end
    return false
end

-- Every area under `root` a tap would do something on, as { dimen = ... },
-- in the order they are painted: the hit areas a tappable widget holds
-- (a tile's buttons and covers), and the widget itself when it has an
-- action of its own. An area lying under a widget painted later (a sheet
-- over the page) is left out: the tap would go to the sheet.
function KeyNav.collect(root)
    local found, containers, seen = {}, {}, {}
    local seq = 0
    local function walk(w, depth)
        if type(w) ~= "table" or seen[w] or depth > 80 then return end
        seen[w] = true
        if tappable(w) and placed(w.dimen) then
            seq = seq + 1
            local mine = seq
            containers[#containers + 1] = { dimen = w.dimen, seq = mine }
            local inner = {}
            for _i, hit in ipairs(type(w.hits) == "table" and w.hits or {}) do
                if type(hit) == "table" and placed(hit.dimen) then
                    found[#found + 1] = { dimen = hit.dimen, owner = mine }
                    inner[#inner + 1] = hit.dimen
                end
            end
            local own = w.action or (type(w.item) == "table" and w.item.action) or nil
            if type(own) == "table" and own.kind == "noop" then own = nil end
            if own or (#inner == 0 and w.action == nil and w.item == nil) then
                -- Its own action is what a tap at its middle does, unless
                -- one of its hit areas lies there.
                local cx, cy = centre(w.dimen)
                local taken = false
                for _i, d in ipairs(inner) do
                    if inside(d, cx, cy) then taken = true; break end
                end
                if not taken then found[#found + 1] = { dimen = w.dimen, owner = mine } end
            end
        end
        for i = 1, #w do walk(w[i], depth + 1) end
    end
    walk(root, 0)
    local out = {}
    for _i, t in ipairs(found) do
        local cx, cy = centre(t.dimen)
        local covered = false
        for _j, c in ipairs(containers) do
            if c.seq > t.owner and inside(c.dimen, cx, cy) then
                -- A later widget inside this area's own widget (a nested
                -- one) does not cover it unless it is larger than the area.
                if c.dimen.w * c.dimen.h >= t.dimen.w * t.dimen.h then covered = true; break end
            end
        end
        if not covered then out[#out + 1] = { dimen = t.dimen } end
    end
    return out
end

function KeyNav.targets(screen)
    if type(screen.hits) == "table" then
        local out = {}
        for _i, area in ipairs(screen.hits) do
            if type(area) == "table" and placed(area.dimen) then out[#out + 1] = area end
        end
        return out
    end
    return KeyNav.collect(screen[1])
end

-- The area the mark is on: the smallest one holding the point, else the
-- one whose middle is nearest to it.
local function markedIndex(areas, point)
    if not point then return nil end
    local best, best_size
    for index, area in ipairs(areas) do
        local d = area.dimen
        if inside(d, point.x, point.y) and (not best_size or d.w * d.h < best_size) then
            best, best_size = index, d.w * d.h
        end
    end
    if best then return best end
    local best_dist
    for index, area in ipairs(areas) do
        local ax, ay = centre(area.dimen)
        local dist = (ax - point.x) ^ 2 + (ay - point.y) ^ 2
        if not best_dist or dist < best_dist then best, best_dist = index, dist end
    end
    return best
end
KeyNav.markedIndex = markedIndex

-- Where to start: the area nearest the top left corner.
local function firstIndex(areas)
    local best, best_score
    for index, area in ipairs(areas) do
        local score = area.dimen.y * 4 + area.dimen.x
        if not best_score or score < best_score then best, best_score = index, score end
    end
    return best
end

local function ring()
    return math.max(2, px(2.5))
end

local function grown(d)
    local r = ring()
    return Geom:new{ x = d.x - r, y = d.y - r, w = d.w + 2 * r, h = d.h + 2 * r }
end

function KeyNav.move(screen, dx, dy)
    local UIManager = require("ui/uimanager")
    local areas = KeyNav.targets(screen)
    if #areas == 0 then return true end
    local from = markedIndex(areas, screen._nav_point)
    local to
    if not from then
        to = firstIndex(areas)
    else
        to = KeyNav.next(areas, from, dx, dy)
        if not to then
            if screen.navEdge then screen:navEdge(dx, dy) end
            return true
        end
    end
    local old = from and areas[from].dimen
    local new = areas[to].dimen
    local x, y = centre(new)
    screen._nav_point = { x = x, y = y }
    if old then
        local region = grown(old)
        UIManager:setDirty(screen, function() return "ui", region end)
    end
    local region = grown(new)
    UIManager:setDirty(screen, function() return "ui", region end)
    return true
end

-- A tap at the middle of the marked area.
function KeyNav.press(screen)
    local areas = KeyNav.targets(screen)
    local at = markedIndex(areas, screen._nav_point)
    if not at then return true end
    local x, y = centre(areas[at].dimen)
    x, y = math.floor(x), math.floor(y)
    screen._nav_point = { x = x, y = y }
    local Event = require("ui/event")
    screen:handleEvent(Event:new("Gesture", { ges = "tap", pos = Geom:new{ x = x, y = y, w = 0, h = 0 } }))
    return true
end

-- The mark, drawn over the screen once it has painted itself.
function KeyNav.paint(screen, bb)
    if not screen._nav_point then return end
    local areas = KeyNav.targets(screen)
    local at = markedIndex(areas, screen._nav_point)
    if not at then return end
    local d = areas[at].dimen
    local r = ring()
    bb:paintBorder(d.x - r, d.y - r, d.w + 2 * r, d.h + 2 * r, r, BoardMetrics.INK.black, px(8))
end

-- The mark taken off (a finger is being used again).
function KeyNav.forget(screen)
    screen._nav_point = nil
end

function KeyNav.keys(screen)
    if not KeyNav.enabled() then return false end
    screen.key_events = screen.key_events or {}
    screen.key_events.NavUp = { { "Up" } }
    screen.key_events.NavDown = { { "Down" } }
    screen.key_events.NavLeft = { { "Left" } }
    screen.key_events.NavRight = { { "Right" } }
    screen.key_events.NavPress = { { "Press" } }
    return true
end

function KeyNav.install(class)
    function class:onNavUp() return KeyNav.move(self, 0, -1) end
    function class:onNavDown() return KeyNav.move(self, 0, 1) end
    function class:onNavLeft() return KeyNav.move(self, -1, 0) end
    function class:onNavRight() return KeyNav.move(self, 1, 0) end
    function class:onNavPress() return KeyNav.press(self) end
end

return KeyNav
