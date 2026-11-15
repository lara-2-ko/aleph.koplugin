-- Aleph modification, 2026-11-14: KOReader's fonts and tab icons answered
-- with Aleph's, for as long as one of its own windows is being built.
--[[--
KOReader's windows ask for their fonts by name (Font:getFace("cfont", 22))
and size their tab icons from one constant. To restyle a window without
copying it, Aleph answers those questions differently while the window
builds itself, then puts KOReader's own answers back, also when the build
fails. Five files each had their own copy of this; they call here now.

    Override.fonts(names, size_of, fn, ...)
        runs fn(...) with the fonts named in the set `names` answered by
        Aleph's sans face; size_of(size), when given, gives the size to use
        instead of the one asked for. Returns what fn returns.

    Override.tabIcons(size, fn, ...)
        runs fn(...) with KOReader's tab icon size (DGENERIC_ICON_SIZE,
        scaled) answered by `size` (pixels). Returns what fn returns.

An error in fn is raised again once KOReader's own are back.
]]

local BoardMetrics = require("aleph_board_metrics")

local Override = {}

local unpack_ = table.unpack or unpack
local function pack(...) return { n = select("#", ...), ... } end

-- Runs fn(...), then `restore`, then returns fn's results or raises its error.
local function guarded(restore, fn, ...)
    local results = pack(pcall(fn, ...))
    restore()
    if not results[1] then error(results[2], 0) end
    return unpack_(results, 2, results.n)
end

function Override.fonts(names, size_of, fn, ...)
    local Font = require("ui/font")
    local original = Font.getFace
    local file = BoardMetrics.faceFile("sans")
    Font.getFace = function(font, name, size, ...)
        if names[name] then
            name = file
            if size_of and size then size = size_of(size) end
        end
        return original(font, name, size, ...)
    end
    return guarded(function() Font.getFace = original end, fn, ...)
end

function Override.tabIcons(size, fn, ...)
    local Screen = require("device").screen
    local ok, full = pcall(function() return G_defaults:readSetting("DGENERIC_ICON_SIZE") end)
    full = ok and full or 48
    -- The screen's own scaleBySize, if it has one of its own (it usually
    -- inherits it): that is what is put back.
    local own = rawget(Screen, "scaleBySize")
    local original = Screen.scaleBySize
    Screen.scaleBySize = function(screen, n)
        if n == full then return size end
        return original(screen, n)
    end
    return guarded(function() Screen.scaleBySize = own end, fn, ...)
end

return Override
