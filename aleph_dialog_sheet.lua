-- Aleph modification, 2026-11-09: KOReader button dialogs as Reading
-- Board sheets.
--[[--
Shows a KOReader ButtonDialog (a list of buttons in rows, with separators) as a
sheet in the board's style instead: the board's font and sizes, a title row
with close, small section labels with a rule under them (after Annotations
Viewer's Filter & sort), and every button with an icon.

  rows of two or more buttons   outlined tiles, two to a row
  a row of one button           a row in a card, with a chevron

KOReader's own dialog is still built (its buttons close it by name), only
never shown: a tap closes the sheet and runs the button's callback. The
symbols KOReader puts in some labels (a pencil, a bookmark) are dropped for
the board's icons. If the sheet cannot be built, KOReader's dialog is shown.

  DialogSheet.capture(fn)   runs fn; the first ButtonDialog it shows opens
                            as a sheet
]]

local UIManager = require("ui/uimanager")
local _ = require("gettext")

local BoardMetrics = require("aleph_board_metrics")
local BoardUI = require("aleph_board_ui")
local MenuUI = require("aleph_menu_ui")
local SheetUI = require("aleph_sheet_ui")

local INK = BoardMetrics.INK
local px = BoardMetrics.px
local text, vstack, hstack, space, icon = BoardUI.text, BoardUI.vstack, BoardUI.hstack, BoardUI.space, BoardUI.icon

local DialogSheet = {}

-- First match wins: (pattern in the lower-case label, icon).
local ICONS = {
    { "reset", "rotate-ccw" }, { "^all", "list" },
    { "edited", "pen-tool" }, { "style", "highlighter" }, { "colou?r", "palette" },
    { "page bookmark", "bookmark" }, { "^bookmark", "bookmark" },
    { "highlight", "highlighter" }, { "note", "pen-line" },
    { "export", "download" }, { "import", "download" },
    { "current page", "file-text" }, { "latest", "clock" }, { "last", "clock" },
    { "select", "list-checks" }, { "search", "search" }, { "sort", "list-ordered" },
    { "delete", "trash" }, { "remove", "trash" }, { "clear", "x" },
    { "expand", "chevrons-right" }, { "collapse", "chevrons-left" },
    { "setting", "settings" }, { "page", "file-text" },
}

function DialogSheet.iconFor(label)
    local l = label:lower()
    for _i, pair in ipairs(ICONS) do
        if l:find(pair[1]) then return pair[2] end
    end
    return "chevron-right"
end

-- The label without KOReader's symbol-font glyphs (private use area), trimmed,
-- first letter capital.
function DialogSheet.clean(label)
    label = tostring(label or "")
    label = label:gsub("\238[\128-\191][\128-\191]", ""):gsub("\239[\128-\163][\128-\191]", "")
    label = label:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s%s+", " ")
    return (label:gsub("^%l", string.upper))
end

local function enabled(b)
    if b.enabled_func then
        local ok, on = pcall(b.enabled_func)
        return not ok or on ~= false
    end
    return b.enabled ~= false
end

-- The dialog's rows split at its separators (empty rows) into groups, each a
-- list of rows of { label, icon, button }.
function DialogSheet.groups(buttons)
    local groups, current = {}, {}
    for _i, row in ipairs(buttons or {}) do
        local out = {}
        for _j, b in ipairs(row) do
            if type(b) == "table" and (b.text or b.text_func) and (b.callback or b.hold_callback) then
                local raw = b.text
                if b.text_func then pcall(function() raw = b.text_func() end) end
                local label = DialogSheet.clean(raw)
                if label ~= "" then out[#out + 1] = { label = label, icon = DialogSheet.iconFor(label), button = b } end
            end
        end
        if #out > 0 then
            current[#current + 1] = out
        elseif #current > 0 then
            groups[#groups + 1] = current
            current = {}
        end
    end
    if #current > 0 then groups[#groups + 1] = current end
    return groups
end

-- A section label after Annotations Viewer's: small, bold, gray, a rule under it.
local function sectionBar(w, label)
    return vstack({ w = w }, {
        text(label:upper(), { s = 12, b = true, col = INK.g4, w = w }),
        space(nil, px(6)),
        BoardUI.rect(w, math.max(1, px(1.5)), INK.black),
    })
end

-- What a group is about, from its buttons.
local function groupLabel(group, index, title)
    if index == 1 and title and title ~= "" then return title end
    local all = {}
    for _i, row in ipairs(group) do for _j, e in ipairs(row) do all[#all + 1] = e.label:lower() end end
    local s = table.concat(all, " ")
    if s:find("filter") then return _("Filter") end
    if s:find("export") then return _("Export") end
    if s:find("current page") or s:find("latest") then return _("Go to") end
    if s:find("select") or s:find("search") then return _("Tools") end
    return nil
end

local function tile(w, e, action)
    local on = enabled(e.button)
    local h = px(48)
    local b = math.max(1, px(1.25))
    local iw = w - 2 * b - 2 * px(12)
    local content = hstack({ w = iw, h = h - 2 * b, gap = px(10) }, {
        icon(e.icon, px(20), { sw = 2.25, col = on and "black" or "gb" }),
        text(e.label, { s = 14, b = true, col = on and INK.black or INK.gb, w = iw - px(30), data = true }),
    })
    local box = BoardUI.box({ w = w, h = h, radius = px(12), border = b, border_col = on and INK.g6 or INK.gd, bg = INK.white },
        hstack({ w = w - 2 * b, h = h - 2 * b }, { space(px(12), 1), content }))
    return on and BoardUI.hit(box, action) or box
end

local function buildBody(page, w)
    local items = { SheetUI.titleRow(w, page.sheet_title, page.sheet_sub) }
    local gap = px(10)
    for gi, group in ipairs(page.groups) do
        local label = groupLabel(group, gi, page.dialog_title)
        local parts = {}
        if label then parts[#parts + 1] = sectionBar(w, label); parts[#parts + 1] = space(nil, px(10)) end
        local singles = {}
        local function flushSingles()
            if #singles == 0 then return end
            parts[#parts + 1] = MenuUI.group(w, singles)
            parts[#parts + 1] = space(nil, gap)
            singles = {}
        end
        for ri, row in ipairs(group) do
            if #row == 1 then
                local e = row[1]
                local on = enabled(e.button)
                singles[#singles + 1] = MenuUI.row(MenuUI.rowsIn(w), { icon = e.icon, label = e.label, chevron = on, h = 50,
                    action = on and { kind = "button", g = gi, r = ri, c = 1 } or { kind = "noop" } })
            else
                flushSingles()
                -- Two to a row; a row of three or more wraps.
                for start = 1, #row, 2 do
                    local cw = math.floor((w - gap) / 2)
                    local cells = {}
                    for c = start, math.min(#row, start + 1) do
                        cells[#cells + 1] = tile(c == start and cw or (w - gap - cw), row[c], { kind = "button", g = gi, r = ri, c = c })
                    end
                    parts[#parts + 1] = hstack({ w = w, gap = gap }, cells)
                    parts[#parts + 1] = space(nil, gap)
                end
            end
        end
        flushSingles()
        if parts[#parts] then parts[#parts] = nil end -- no gap after the last
        items[#items + 1] = vstack({ w = w }, parts)
    end
    return items
end

-- Opens the sheet for `dialog` (a ButtonDialog that was about to be shown).
function DialogSheet.open(dialog, o)
    o = o or {}
    local groups = DialogSheet.groups(dialog.buttons)
    if #groups == 0 then return nil end
    return SheetUI.open{
        name = "aleph_dialog_sheet",
        groups = groups,
        dialog_title = dialog.title and DialogSheet.clean(dialog.title) or nil,
        sheet_title = o.title or _("Options"),
        sheet_sub = o.sub,
        build = function(page, sw, sh)
            return SheetUI.sheet(page, sw, sh, function(w) return buildBody(page, w) end, { pop_w = 520 })
        end,
        on_action = function(page, action)
            if action.kind ~= "button" then return true end
            local e = page.groups[action.g] and page.groups[action.g][action.r] and page.groups[action.g][action.r][action.c]
            page:close()
            if e and e.button.callback then UIManager:tickAfterNext(e.button.callback) end
            return true
        end,
    }
end

-- Runs fn; the first ButtonDialog it shows opens as a sheet (o: title, sub).
function DialogSheet.capture(fn, o)
    local ButtonDialog = require("ui/widget/buttondialog")
    local own_new = rawget(ButtonDialog, "new")
    local captured
    ButtonDialog.new = function(cls, args)
        ButtonDialog.new = own_new
        captured = ButtonDialog.new(cls, args)
        return captured
    end
    local original_show = UIManager.show
    UIManager.show = function(um, widget, ...)
        if captured and widget == captured then
            UIManager.show = original_show
            local ok, shown = pcall(DialogSheet.open, captured, o)
            if ok and shown then return end
            if not ok then require("logger").warn("Aleph: dialog sheet failed:", shown) end
        end
        return original_show(um, widget, ...)
    end
    local ok, err = pcall(fn)
    ButtonDialog.new = own_new
    UIManager.show = original_show
    if not ok then error(err, 0) end
end

return DialogSheet
