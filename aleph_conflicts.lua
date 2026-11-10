-- Aleph modification, 2026-11-10: a warning when a plugin that replaces the
-- same screens as Aleph is running too.
--[[--
Two plugins do what Aleph's board does, a home screen of their own over the
file browser, and more:

  ZenOS (or Zen UI)  the home screen it opens when a book closes, the reader's
                     menus, the page browser, the dictionary, the status bars.
                     With both on, closing a book builds two home screens and
                     their covers at once; a Kobo Clara Colour was reported
                     freezing and crashing.
  Simple UI          a home screen and a bottom bar over the file browser.
                     ZenOS's own check turns it off for the same reason.

Aleph changes nothing about how it runs: it only says so, once per start of
KOReader, until "Don't show again" is chosen (each plugin on its own).
Project: Title, Bookshelf and the menu restyling plugins are not warned about:
they do not build a home screen over Aleph's (see the README).
]]

local _ = require("gettext")

local Conflicts = { shown = false }

-- Each plugin: the names it registers under, a module only it loads, and
-- what the warning calls it.
Conflicts.PLUGINS = {
    -- ZenOS's _meta.lua: "zenos", or "zen_ui" when installed as zen_ui.koplugin.
    { id = "zenos", label = "ZenOS", names = { "zenos", "zen_ui" }, module = "common/zen_logger" },
    -- The module ZenOS itself looks for to find Simple UI.
    { id = "simpleui", label = "Simple UI", names = { "simpleui" }, module = "sui_core" },
}

local function running(ui, plugin)
    for _i, name in ipairs(plugin.names) do
        if type(ui and rawget(ui, name)) == "table" then return true end
    end
    local found = false
    pcall(function()
        local loader = require("pluginloader")
        for _i, name in ipairs(plugin.names) do
            if loader:getPluginInstance(name) then found = true end
        end
    end)
    if found then return true end
    return plugin.module ~= nil and package.loaded[plugin.module] ~= nil
end
Conflicts.running = running

function Conflicts.zenosRunning(ui) return running(ui, Conflicts.PLUGINS[1]) end

local function stored()
    local s = G_reader_settings:readSetting("aleph")
    return type(s) == "table" and s or nil
end

local function dismissed(id)
    local s = stored()
    if not s then return false end
    if id == "zenos" and s.zenos_warning_off == true then return true end
    return type(s.conflict_warnings_off) == "table" and s.conflict_warnings_off[id] == true
end

-- The plugins running alongside Aleph whose warning was not turned off.
function Conflicts.found(ui)
    local out = {}
    for _i, plugin in ipairs(Conflicts.PLUGINS) do
        if not dismissed(plugin.id) and running(ui, plugin) then out[#out + 1] = plugin end
    end
    return out
end

local function message(list)
    if #list == 1 and list[1].id == "zenos" then
        return _("ZenOS is also on"),
            _("Aleph and ZenOS replace the same parts of KOReader: the home screen, the reader's menus, the page browser, the dictionary and the status bars. Running both can make KOReader freeze or crash, most often when a book is closed.\n\nTo use Aleph, turn ZenOS off in Plugin management and restart KOReader.")
    end
    if #list == 1 then
        local T = require("ffi/util").template
        return T(_("%1 is also on"), list[1].label),
            T(_("Aleph and %1 both put their own home screen over KOReader's file browser. Running both can make KOReader slow, freeze or crash, most often when a book is closed.\n\nTo use Aleph, turn %1 off in Plugin management and restart KOReader."), list[1].label)
    end
    local names = {}
    for i, p in ipairs(list) do names[i] = p.label end
    local T = require("ffi/util").template
    local joined = table.concat(names, _(" and "))
    return T(_("%1 are also on"), joined),
        T(_("These plugins replace the same screens as Aleph, starting with its home screen. Running them together can make KOReader slow, freeze or crash, most often when a book is closed.\n\nTo use Aleph, turn %1 off in Plugin management and restart KOReader."), joined)
end

function Conflicts.check(ui)
    if Conflicts.shown then return false end
    local list = Conflicts.found(ui)
    if #list == 0 then return false end
    Conflicts.shown = true
    local UIManager = require("ui/uimanager")
    local title, text = message(list)
    require("logger").warn("Aleph: also running:", title)
    UIManager:scheduleIn(1.5, function()
        local ok = pcall(function()
            require("aleph_confirm").show{
                title = title, text = text,
                cancel_label = _("Don't show again"),
                on_cancel = function() Conflicts.dismiss(list) end,
                ok_label = _("OK"),
            }
        end)
        if not ok then
            UIManager:show(require("ui/widget/infomessage"):new{ text = title .. "\n\n" .. text })
        end
    end)
    return true
end

-- "Don't show again": for the plugins this warning named (all known ones
-- when none is given).
function Conflicts.dismiss(list)
    local s = G_reader_settings:readSetting("aleph")
    if type(s) ~= "table" then s = {} end
    s.conflict_warnings_off = type(s.conflict_warnings_off) == "table" and s.conflict_warnings_off or {}
    for _i, p in ipairs(list or Conflicts.PLUGINS) do s.conflict_warnings_off[p.id] = true end
    G_reader_settings:saveSetting("aleph", s)
end

return Conflicts
