local DataStorage = require("datastorage")
local lfs = require("libs/libkoreader-lfs")
local _ = require("gettext")

local Icons = {}
local data = DataStorage:getDataDir()
local directories = {
    core = "resources/icons/mdlight",
    legacy = "resources/icons",
    user = data .. "/icons",
    custom = data .. "/quicktopbar-icons",
}

-- The files QuickTopBar draws its own controls with, which are not choices.
local technical = {
    "^check%-white", "^chevron%-", "^sub%-arrow", "^minus", "^plus", "^close", "^status%-", "^tab%-", "^zap", "%-white%.",
}

local function fileName(name)
    return name and not name:find("[/\\]") and (name:lower():match("%.svg$")
        or name:lower():match("%.png$"))
end

function Icons.path(root, value, default)
    if type(value) == "string" then
        local source, name = value:match("^([^:]+):(.+)$")
        local dir = source == "bundled" and root .. "/icons" or directories[source]
        local path
        if dir and fileName(name) then
            path = dir .. "/" .. name
        elseif value:match("^[%w_%-]+$") then
            path = root .. "/icons/" .. value .. ".svg"
        end
        if path and lfs.attributes(path, "mode") == "file" then return path end
    end
    return root .. "/icons/" .. default .. ".svg"
end

-- Every icon on offer, the default first: { text, icon_file, icon_value }.
function Icons.items(root, default)
    local items = {}
    local function add(text, path, id)
        items[#items + 1] = { text = text, icon_file = path, icon_value = id }
    end
    add(_("Default icon"), Icons.path(root, nil, default))

    local function list(dir, source, skip)
        if lfs.attributes(dir, "mode") ~= "directory" then return end
        local names = {}
        for name in lfs.dir(dir) do
            local skipped = false
            for _, pattern in ipairs(skip or {}) do
                if name:find(pattern) then skipped = true; break end
            end
            if not skipped and fileName(name) and lfs.attributes(dir .. "/" .. name, "mode") == "file" then
                names[#names + 1] = name
            end
        end
        table.sort(names)
        for _, name in ipairs(names) do
            local stem = name:gsub("%.[^.]+$", "")
            add(stem, dir .. "/" .. name, source .. ":" .. name)
        end
    end
    list(directories.user, "user")
    list(directories.custom, "custom")
    list(root .. "/icons", "bundled", technical)
    list(directories.core, "core")
    list(directories.legacy, "legacy")
    return items
end

-- The icon picker, a page in Aleph's style (aleph_topmenu_page.lua).
function Icons.show(root, label, value, default, onSelect)
    require("aleph_topmenu_page").pickIcon(root, label, value, default, onSelect)
end

return Icons
