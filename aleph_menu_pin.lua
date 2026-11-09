-- Modified for Aleph, 2026-11-09. Unofficial local-only fork. See NOTICE.
--[[--
Pins the Aleph entry onto the first page of KOReader's Tools menu,
right below calibre, in the file browser and in books.

After BookOrbit's menu pin (bookorbit_menu_pin.lua), without its menu-bar tab:
the Quick Top Bar already gives Aleph a place in the top menu.

KOReader keeps its bundled menu-order tables cached and lets plugins extend
them before a menu is built, so the shared tables are changed in place. That
keeps the entries every other plugin added, whatever order they load in.
Nothing is written to disk: a menu order you saved yourself
(settings/*_menu_order.lua) still wins, as it always does in KOReader.
]]

local logger = require("logger")

local MENU_ID = "aleph"
local AFTER = "calibre"

local ORDERS = {
    "ui/elements/reader_menu_order",
    "ui/elements/filemanager_menu_order",
}

local MenuPin = { done = false }

local function removeId(list, id)
    for i = #list, 1, -1 do
        if list[i] == id then table.remove(list, i) end
    end
end

-- Aleph once, just below calibre (at the end when there is none).
function MenuPin.place(tools)
    removeId(tools, MENU_ID)
    local insert_at = #tools
    for i, id in ipairs(tools) do
        if id == AFTER then insert_at = i; break end
    end
    table.insert(tools, insert_at + 1, MENU_ID)
    -- The pin badge's place, in books, right under it.
    removeId(tools, MENU_ID .. "_pin_badge")
    removeId(tools, MENU_ID .. "_bookends")
    for i, id in ipairs(tools) do
        if id == MENU_ID then
            table.insert(tools, i + 1, MENU_ID .. "_pin_badge")
            table.insert(tools, i + 2, MENU_ID .. "_bookends")
            break
        end
    end
    return tools
end

local function pinOne(module)
    local ok, order = pcall(require, module)
    if not ok or type(order) ~= "table" or type(order.tools) ~= "table" then
        logger.warn("Aleph: cannot pin to Tools in", module)
        return
    end
    -- Out of any other list it was in, so it is shown once.
    for key, list in pairs(order) do
        if key ~= "tools" and type(list) == "table" then removeId(list, MENU_ID) end
    end
    MenuPin.place(order.tools)
end

function MenuPin.ensure()
    if MenuPin.done then return end
    MenuPin.done = true
    for _i, module in ipairs(ORDERS) do
        local ok, err = pcall(pinOne, module)
        if not ok then logger.warn("Aleph: menu pin failed for", module, err) end
    end
end

return MenuPin
