local PluginLoader = require("pluginloader")

local Apps = {}

local function hasAction(item)
    return type(item) == "table"
        and (item.callback or item.callback_func or item.sub_item_table
            or item.sub_item_table_func or item.tap_input or item.tap_input_func)
end

-- Observe normal menu registration once. Some plugins do real work in
-- addToMainMenu, so calling it again with a dummy table can have side effects.
function Apps.capture(menu, build, ...)
    local enabled = PluginLoader:loadPlugins()
    local names, paths, instances = {}, {}, {}
    for _, plugin in ipairs(enabled) do
        names[plugin.name:lower()] = plugin.name
        if plugin.path then paths[plugin.path] = plugin.name end
        local instance = menu.ui[plugin.name]
        if type(instance) == "table" then instances[instance] = plugin.name end
    end
    local captured, restore = {}, {}
    for _, widget in ipairs(menu.registered_widgets or {}) do
        local name = instances[widget] or paths[widget.path]
            or (type(widget.name) == "string" and names[widget.name:lower()])
        local original = widget.addToMainMenu
        if name and name ~= "quicktopbar" and type(original) == "function" and not restore[widget] then
            restore[widget] = { rawget(widget, "addToMainMenu") }
            widget.addToMainMenu = function(instance, items)
                if items ~= menu.menu_items then return original(instance, items) end
                local before = {}
                for key, value in pairs(items) do before[key] = value end
                original(instance, items)
                local entries = captured[name] or {}
                for key, value in pairs(items) do
                    if before[key] ~= value and hasAction(value) then
                        entries[key] = value
                    end
                end
                captured[name] = entries
            end
        end
    end
    local ok, err = pcall(build, menu, ...)
    for widget, previous in pairs(restore) do widget.addToMainMenu = previous[1] end
    if not ok then error(err, 0) end
    return captured
end

local function storefrontAction(menu, plugin)
    local instance = menu.ui[plugin.name]
    if type(instance) ~= "table" then
        for _, widget in ipairs(menu.registered_widgets or {}) do
            if plugin.path and widget.path == plugin.path then
                instance = widget
                break
            end
        end
    end
    if type(instance) == "table" and type(instance.showBrowser) == "function" then
        return { callback = function() instance:showBrowser() end }
    end
end

function Apps.build(menu, captured)
    local enabled, disabled = PluginLoader:loadPlugins()
    local tab = { id = "quicktopbar_apps", icon = "appbar.tools", ignored_by_menu_search = true }
    local function add(plugin, is_enabled)
        if plugin.name == "quicktopbar" then return end
        local entries, keys = captured[plugin.name] or {}, {}
        for key in pairs(entries) do keys[#keys + 1] = key end
        if #keys == 0 and is_enabled and plugin.name:lower() == "storefront" then
            local action = storefrontAction(menu, plugin)
            if action then entries.Storefront, keys[1] = action, "Storefront" end
        end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        local item = { text = plugin.fullname or plugin.name, icon_key = "app_" .. plugin.name }
        if #keys == 1 then
            for key, value in pairs(entries[keys[1]]) do item[key] = value end
            item.launcher_label = plugin.fullname or plugin.name
            if not item.text and not item.text_func then item.text = item.launcher_label end
        elseif #keys > 1 then
            item.sub_item_table = {}
            for _, key in ipairs(keys) do
                item.sub_item_table[#item.sub_item_table + 1] = entries[key]
            end
        else
            item.unavailable = true
        end
        item.launcher_label = item.launcher_label or item.text
        tab[#tab + 1] = item
    end
    for _, plugin in ipairs(enabled or {}) do add(plugin, true) end
    for _, plugin in ipairs(disabled or {}) do add(plugin, false) end
    table.sort(tab, function(a, b)
        if a.unavailable ~= b.unavailable then return not a.unavailable end
        local left, right = a.launcher_label:lower(), b.launcher_label:lower()
        if left == right then return a.icon_key < b.icon_key end
        return left < right
    end)
    return tab
end

function Apps.order(tab, saved)
    if type(saved) ~= "table" then return end
    local ranks, positions = {}, {}
    for index, key in ipairs(saved) do ranks[key] = index end
    for index, item in ipairs(tab) do positions[item] = index end
    table.sort(tab, function(a, b)
        local left = ranks[a.icon_key] or math.huge
        local right = ranks[b.icon_key] or math.huge
        if left == right then return positions[a] < positions[b] end
        return left < right
    end)
end

return Apps
