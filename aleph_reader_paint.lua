-- Aleph modification, 2026-11-15: one hook on the reader's paint for all of
-- Aleph's page decorations.
--[[--
Four parts of Aleph draw on the page after KOReader has painted it: the
margins kept clear in scroll mode (aleph_viewport.lua), the lines at the top
and bottom (aleph_bookends.lua), the pin badge (aleph_pins.lua) and X-Ray's
underlines (aleph_xr.lua). Each used to wrap ReaderView.paintTo itself, four
wrappers one inside the other. Now there is one:

    require("aleph_reader_paint").add("bookends", 20, function(view, bb, x, y) ... end)

Painters run after KOReader's own paint, lowest number first (the order the
four wrappers ran in: margins 10, lines 20, pins 30, X-Ray 40). Adding a name
again replaces its painter. Each runs protected: one that fails is written
to the log once (aleph_try.lua) and the others still paint.
]]

local Paint = {}

local painters = {}     -- { name, order, fn }, sorted by order
local installed = false

local function install()
    if installed then return end
    local View = require("apps/reader/modules/readerview")
    if rawget(View, "_aleph_paint") then installed = true; return end
    local Try = require("aleph_try")
    local paint = View.paintTo
    View._aleph_paint = true
    View.paintTo = function(self, bb, x, y)
        paint(self, bb, x, y)
        for i = 1, #painters do
            local p = painters[i]
            local ok, err = pcall(p.fn, self, bb, x, y)
            if not ok then Try.report("page painter " .. p.name, err) end
        end
    end
    installed = true
end

function Paint.add(name, order, fn)
    for i = #painters, 1, -1 do
        if painters[i].name == name then table.remove(painters, i) end
    end
    painters[#painters + 1] = { name = name, order = order, fn = fn }
    table.sort(painters, function(a, b) return a.order < b.order end)
    install()
end

function Paint.has(name)
    for _i, p in ipairs(painters) do
        if p.name == name then return true end
    end
    return false
end

-- For tests: the names in the order they paint.
function Paint.names()
    local out = {}
    for i, p in ipairs(painters) do out[i] = p.name end
    return out
end

return Paint
