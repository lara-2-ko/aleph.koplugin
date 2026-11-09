-- Aleph modification, 2026-11-09: finding other plugins, one way for all.
--[[--
Reading insights, X-Ray and KOSyncthing+ were each looked for in one place
only, and missed on the Kindle whenever they sat somewhere else. Every lookup
now goes through here, the way Reading log does it (its D.hasPlugin and
D.dispatch), and more:

  1. the reader or file browser Aleph was opened from, then every reader and
     file browser KOReader has open (ReaderUI.instance, FileManager.instance),
     by the plugin's name — and among their modules by the name KOReader
     gives a module ("xray", "readerxray", "filemanagerxray");
  2. PluginLoader:getPluginInstance(name);
  3. if the plugin is loaded but none of that finds it, its gesture actions,
     run through KOReader's Dispatcher with the reader / file browser set to
     listen for the length of the call (Aleph's sheets sit on top, and
     KOReader sends an action's event to the top window first).

`check(plugin)` says whether a candidate is the right one (it has the method
that will be called). Every miss is written to crash.log with what was
looked at, so a report says where a plugin went missing.
]]

local logger = require("logger")

local Plugins = {}

-- Every reader and file browser KOReader has open, `ui` first.
function Plugins.hosts(ui)
    local out, seen = {}, {}
    local function add(h)
        if type(h) == "table" and not seen[h] then seen[h] = true; out[#out + 1] = h end
    end
    add(ui)
    for _i, mod in ipairs({ "apps/reader/readerui", "apps/filemanager/filemanager" }) do
        local ok, UI = pcall(require, mod)
        if ok and type(UI) == "table" then add(UI.instance) end
    end
    return out
end

local function accept(candidate, check)
    if type(candidate) ~= "table" then return false end
    if not check then return true end
    local ok, yes = pcall(check, candidate)
    return ok and yes and true or false
end

-- The plugin called `name`, or nil.
function Plugins.find(name, ui, check)
    local hosts = Plugins.hosts(ui)
    for _i, host in ipairs(hosts) do
        local direct
        pcall(function() direct = host[name] end)
        if accept(direct, check) then return direct end
    end
    -- Among the modules, by the name KOReader gives a module.
    local names = { [name] = true, ["reader" .. name] = true, ["filemanager" .. name] = true }
    for _i, host in ipairs(hosts) do
        local found
        pcall(function()
            for _k, module in pairs(host) do
                if type(module) == "table" then
                    local n = rawget(module, "name") or module.name
                    if names[n] and accept(module, check) then found = module; break end
                end
            end
        end)
        if found then return found end
    end
    local ok, instance = pcall(function() return require("pluginloader"):getPluginInstance(name) end)
    if ok and accept(instance, check) then return instance end
    logger.info("Aleph: plugin", name, "not found among", #hosts, "readers / file browsers")
    return nil
end

-- Whether a plugin's code is loaded at all (a module whose name ends with
-- `suffix`, e.g. "xray_ui"), even when no instance can be found.
function Plugins.loaded(suffix)
    for key in pairs(package.loaded) do
        if type(key) == "string" and (key == suffix or key:sub(-#suffix - 1) == "/" .. suffix or key:sub(-#suffix - 1) == "." .. suffix) then
            return true
        end
    end
    return false
end

-- Runs a KOReader action with the readers and file browsers listening.
function Plugins.dispatch(ui, action)
    local ok, Dispatcher = pcall(require, "dispatcher")
    if not ok or not Dispatcher then return false end
    local listening = {}
    for _i, host in ipairs(Plugins.hosts(ui)) do
        listening[#listening + 1] = { host, host.is_always_active }
        host.is_always_active = true
    end
    local done, err = pcall(Dispatcher.execute, Dispatcher, { [action] = true })
    for _i, l in ipairs(listening) do l[1].is_always_active = l[2] end
    if not done then logger.warn("Aleph: action failed:", action, err) end
    return done
end

return Plugins
