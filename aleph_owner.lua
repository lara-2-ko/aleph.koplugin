-- Aleph modification, 2026-11-15: the owner's contact details.
--[[--
Menu > Owner information: a name, an email address and a phone number, so
that whoever finds a lost e-reader can reach its owner. The page shows them
large under "If you find this e-reader", with rows to change each.

Kept in Aleph's settings (key "owner": { name, email, phone }), on this
device only; nothing is sent anywhere.
]]

local _ = require("gettext")

local Owner = {}

Owner.FIELDS = {
    { key = "name", icon = "user", label = function() return _("Name") end },
    { key = "email", icon = "mail", label = function() return _("Email") end },
    { key = "phone", icon = "phone", label = function() return _("Phone") end },
}

local function trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

function Owner.get()
    local stored = require("aleph_prefs").get().owner
    local out = {}
    for _i, f in ipairs(Owner.FIELDS) do
        local v = type(stored) == "table" and trim(stored[f.key]) or ""
        out[f.key] = v ~= "" and v or nil
    end
    return out
end

function Owner.set(key, value)
    local Prefs = require("aleph_prefs")
    local o = Owner.get()
    local v = trim(value)
    o[key] = v ~= "" and v or nil
    local any = false
    for _k, x in pairs(o) do if x then any = true end end
    Prefs.set("owner", any and o or nil)
end

-- The menu row's line: the name, or what the page is for.
function Owner.summary()
    local o = Owner.get()
    if o.name then return o.name end
    if o.email or o.phone then return o.email or o.phone end
    return _("Your contact details, in case this device is lost")
end

-- The page. `browser` (Home) for its text prompt.
function Owner.open(browser)
    local BoardMetrics = require("aleph_board_metrics")
    local BoardUI = require("aleph_board_ui")
    local MenuPage = require("aleph_menu_page")
    local MenuUI = require("aleph_menu_ui")
    local UIManager = require("ui/uimanager")
    local INK, px = BoardMetrics.INK, BoardMetrics.px
    local text, vstack, space = BoardUI.text, BoardUI.vstack, BoardUI.space
    local page
    page = MenuPage:new{
        name = "aleph_owner",
        build = function(p, sw, sh)
            local mx = MenuUI.mx()
            local w = sw - 2 * mx
            local iw = MenuUI.rowsIn(w)
            local o = Owner.get()
            local header = MenuUI.pageHeader(w, _("Owner information"), { sub = _("If this device is lost") })
            -- What a finder reads first.
            local shown = {}
            for _i, f in ipairs(Owner.FIELDS) do
                if o[f.key] then
                    shown[#shown + 1] = text(o[f.key], { s = f.key == "name" and 22 or 18, b = f.key == "name", w = iw, data = true, lines = 2 })
                    shown[#shown + 1] = space(nil, px(4))
                end
            end
            local card_items = { space(nil, px(14)),
                text(_("If you find this e-reader, please contact:"), { s = 14, col = INK.g4, w = iw }),
                space(nil, px(10)) }
            if #shown == 0 then
                card_items[#card_items + 1] = text(_("Nothing here yet. Add your name and a way to reach you below."), { s = 16, w = iw, lines = 3 })
            else
                for _i, x in ipairs(shown) do card_items[#card_items + 1] = x end
            end
            card_items[#card_items + 1] = space(nil, px(14))
            local rows = {}
            for _i, f in ipairs(Owner.FIELDS) do
                rows[#rows + 1] = MenuUI.row(iw, { icon = f.icon, label = f.label(), sub = o[f.key] or _("Not set"), sub_data = o[f.key] ~= nil,
                    chevron = true, action = { kind = "owner-edit", key = f.key } })
            end
            return vstack({ w = sw, h = sh, pad = { px(6), mx, px(12), mx } }, {
                header, space(nil, px(8)),
                MenuUI.card(w, card_items, { strong = true }),
                space(nil, px(16)),
                MenuUI.section(w, _("Change"), MenuUI.group(w, rows)),
                space(nil, px(12)),
                text(_("Kept on this device only."), { s = 13, col = INK.g4, w = w }),
            })
        end,
        on_action = function(p, action)
            if action.kind ~= "owner-edit" then return end
            local field
            for _i, f in ipairs(Owner.FIELDS) do if f.key == action.key then field = f end end
            if not field then return end
            local current = Owner.get()[field.key] or ""
            local function save(v)
                Owner.set(field.key, v)
                if not p.closed then p:refresh() end
            end
            if browser and browser.input then
                browser:input(field.label(), current, save)
            else
                require("aleph_input").prompt{ title = field.label(), text = current, ok_label = _("Save"), on_ok = save }
            end
        end,
    }
    UIManager:show(page, "ui")
    return page
end

return Owner
