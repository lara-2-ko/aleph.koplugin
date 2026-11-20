-- Aleph modification, 2026-11-17: Aleph stays up when asked for, with
-- Bookshelf installed.
--[[--
Bookshelf (AndyHazz/bookshelf.koplugin) stays under a book opened from it
and, when that book closes, puts itself back on top a moment later: its
"return to where you came from". Aleph Home from the reader closes the book
too, so Aleph opened and Bookshelf covered it at once (Aleph flashed, then
Bookshelf).

When Aleph is asked for (the reader menu's Aleph Home, the "Aleph: open"
gesture, its menu item or top-bar tab), Bookshelf's screen is closed if it
is above Aleph, now and for the next three seconds (its re-show comes on
the next tick). That is what Bookshelf's own "Bookshelf: open or close"
does, so Bookshelf is left as it expects. Not at startup, where Bookshelf's
"Start with" decides, and never while Bookshelf holds a book parked under
its screen (closing it would show that book).
]]

local UIManager = require("ui/uimanager")
local logger = require("logger")

local Guard = {}

Guard.SECONDS = 3
Guard.EVERY = 0.2

local function isShelf(widget)
    return type(widget) == "table" and widget.name == "bookshelf"
end

-- Bookshelf's screens above `widget` on KOReader's window stack.
function Guard.above(widget)
    local stack = UIManager._window_stack or {}
    local at
    for i, win in ipairs(stack) do
        if win.widget == widget then at = i end
    end
    local out = {}
    if not at then return out end
    for i = at + 1, #stack do
        if isShelf(stack[i].widget) then out[#out + 1] = stack[i].widget end
    end
    return out
end

local function parked()
    local Park = package.loaded["lib/bookshelf_reader_park"]
    if type(Park) ~= "table" or type(Park.isParked) ~= "function" then return false end
    local ok, yes = pcall(Park.isParked)
    return ok and yes and true or false
end

-- Closes Bookshelf's screens above `browser`. How many were closed.
function Guard.clear(browser)
    if not browser or browser.closed or parked() then return 0 end
    local list = Guard.above(browser)
    for _i, shelf in ipairs(list) do
        pcall(UIManager.close, UIManager, shelf)
    end
    if #list > 0 then
        logger.info("Aleph: Bookshelf was above Aleph; closed it")
        UIManager:setDirty(browser, "full")
    end
    return #list
end

-- Keeps Aleph above Bookshelf for a few seconds. Nothing at all without
-- Bookshelf loaded.
function Guard.keep(browser)
    if not browser or not package.loaded["lib/bookshelf_widget"] then return false end
    Guard.clear(browser)
    local deadline = os.time() + Guard.SECONDS
    local function check()
        if browser.closed then return end
        Guard.clear(browser)
        if os.time() <= deadline then UIManager:scheduleIn(Guard.EVERY, check) end
    end
    UIManager:nextTick(check)
    return true
end

return Guard
