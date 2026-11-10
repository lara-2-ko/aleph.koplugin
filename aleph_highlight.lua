-- Aleph modification, 2026-11-08: one sheet for a highlight's style and
-- color, in the board's style.
--[[--
KOReader edits a highlight in two plain pop-ups, a list of four styles and a
list of nine colors. This replaces both with one panel:

  Style  four tiles that show what each does, drawn in the highlight's own
         color: Lighten, Underline, Strikethrough, Invert
  Color  nine swatches, each with its name (the name is what tells colors
         apart on a black and white screen)

Hold a color's name to rename it. Hold its swatch to pick a new color on a
wheel. Names and colors are saved and apply in the whole of KOReader:
the colors are KOReader's own highlight colors, only their definition changes.

The highlight dialog's Style and Color buttons become one, which opens this.
The prompts shown while making a new highlight are left as KOReader's.
]]

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Event = require("ui/event")
local Geom = require("ui/geometry")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local BoardMetrics = require("aleph_board_metrics")
local BoardUI = require("aleph_board_ui")
local MenuUI = require("aleph_menu_ui")
local Panel = require("aleph_panel")

local INK = BoardMetrics.INK
local px = BoardMetrics.px
local floor = math.floor

local Highlight = {}
local Handles = require("aleph_handles") -- the drag posts
local placeAway -- where to put a menu beside a highlight, defined below

-- ------------------------------------------------------------- palette
local Palette = {}
local defaults

local function saved()
    local stored = G_reader_settings:readSetting("aleph")
    if type(stored) ~= "table" then
        stored = {}
        G_reader_settings:saveSetting("aleph", stored)
    end
    stored.highlight_palette = stored.highlight_palette or {}
    return stored.highlight_palette
end

local function capture(class)
    if defaults then return end
    defaults = { hex = {}, name = {} }
    for id, hex in pairs(Blitbuffer.HIGHLIGHT_COLORS) do defaults.hex[id] = hex end
    for _i, entry in ipairs(class.highlight_colors) do defaults.name[entry[2]] = entry[1] end
end

-- Puts the saved names and colors into KOReader's own tables.
function Palette.apply(class)
    capture(class)
    local custom = saved()
    for _i, entry in ipairs(class.highlight_colors) do
        local id = entry[2]
        local mine = custom[id]
        entry[1] = (mine and mine.name) or defaults.name[id]
        Blitbuffer.HIGHLIGHT_COLORS[id] = (mine and mine.hex) or defaults.hex[id]
    end
end

function Palette.name(class, id)
    for _i, entry in ipairs(class.highlight_colors) do
        if entry[2] == id then return entry[1] end
    end
    return id
end

function Palette.hex(id)
    -- Gray has no entry of its own: KOReader draws it as a plain gray.
    return Blitbuffer.HIGHLIGHT_COLORS[id] or "#CCCCCC"
end

local function update(class, id, change)
    local custom = saved()
    local mine = custom[id] or {}
    change(mine)
    custom[id] = (mine.name or mine.hex) and mine or nil
    Palette.apply(class)
    pcall(function() G_reader_settings:flush() end)
end

function Palette.setName(class, id, name)
    name = (name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    update(class, id, function(mine) mine.name = (name ~= "" and name ~= defaults.name[id]) and name or nil end)
end

function Palette.setHex(class, id, hex)
    update(class, id, function(mine) mine.hex = hex ~= defaults.hex[id] and hex or nil end)
end

function Palette.resetHex(class, id)
    update(class, id, function(mine) mine.hex = nil end)
end

local function colorOf(hex)
    return Blitbuffer.colorFromString(hex)
end

-- Dark swatches get a white check, light ones a black one.
local function luminance(hex)
    local r, g, b = tostring(hex):match("#?(%x%x)(%x%x)(%x%x)")
    if not r then return 1 end
    return (0.299 * tonumber(r, 16) + 0.587 * tonumber(g, 16) + 0.114 * tonumber(b, 16)) / 255
end

-- ----------------------------------------------------------- change it
local function applyChange(hl, index, field, value)
    local item = hl.ui.annotation.annotations[index]
    if not item then return end
    hl:writePdfAnnotation("delete", item)
    item[field] = value
    if hl.ui.paging then
        hl:writePdfAnnotation("save", item)
        if item.note then hl:writePdfAnnotation("content", item, item.note) end
    end
    UIManager:setDirty(hl.dialog, "ui")
    hl.ui:handleEvent(Event:new("AnnotationsModified", { item }))
end

-- ---------------------------------------------------------- the pieces
-- What a style does, shown on a word: Lighten a tinted band, Underline and
-- Strikethrough a line in the color, Invert white on black.
local function styleSample(id, w, h, hex)
    local invert = id == "invert"
    local word = BoardUI.text("Abc", { s = 20, b = true, col = invert and INK.white or INK.black })
    local tw, th = word:getSize().w, word:getSize().h
    local x, y = floor((w - tw) / 2), floor((h - th) / 2)
    local tint = colorOf(hex)
    local line = math.max(2, px(2.5))
    local layers = {}
    if invert then
        table.insert(layers, { widget = BoardUI.rect(tw + px(12), th, INK.black, px(3)), x = x - px(6), y = y })
    elseif id == "lighten" then
        table.insert(layers, { widget = BoardUI.rect(tw + px(10), th - px(2), tint, px(3)), x = x - px(5), y = y + px(1) })
    end
    table.insert(layers, { widget = word, x = x, y = y })
    if id == "underscore" then
        table.insert(layers, { widget = BoardUI.rect(tw + px(4), line, tint), x = x - px(2), y = y + th - line - px(1) })
    elseif id == "strikeout" then
        table.insert(layers, { widget = BoardUI.rect(tw + px(8), line, tint), x = x - px(4), y = y + floor(th / 2) })
    end
    return BoardUI.overlay(w, h, layers)
end

local function styleTile(style, tw, th, selected, hex)
    local border = selected and math.max(2, px(2.5)) or math.max(1, px(1))
    local sample = styleSample(style[2], tw - 2 * border, px(42), hex)
    local name = BoardUI.text(style[1], { s = 12, b = selected, w = tw - px(8), align = "center", data = true })
    local inner = BoardUI.vstack({ w = tw - 2 * border, h = th - 2 * border, pad = { px(6), 0, px(4), 0 }, align = "center" },
        { sample, BoardUI.flex(px(2)), name })
    local box = BoardUI.box({ w = tw, h = th, radius = px(10), border = border, border_col = selected and INK.black or INK.g9, bg = INK.white }, inner)
    return BoardUI.hit(box, { kind = "style", id = style[2] })
end

local function colorCell(class, id, cw, chh, selected, muted)
    local hex = Palette.hex(id)
    local d = px(32)
    local mark = selected and BoardUI.icon("check", px(18), { col = luminance(hex) > 0.6 and "black" or "white", sw = 3 }) or BoardUI.space(1, 1)
    local swatch = BoardUI.circle(d, { bg = colorOf(hex), border = math.max(1, px(1.25)), border_col = INK.black }, mark)
    local touch_w = px(46)
    local swatch_box = BoardUI.hit(BoardUI.hstack({ w = touch_w, h = chh }, { BoardUI.flex(0), swatch, BoardUI.flex(0) }),
        { kind = "color", id = id, hold = "wheel" })
    local name_w = cw - touch_w - px(8)
    local name = BoardUI.text(Palette.name(class, id), { s = 14, b = selected, col = muted and INK.g6 or INK.black, w = name_w, data = true })
    local name_box = BoardUI.hit(BoardUI.hstack({ w = name_w, h = chh }, { name, BoardUI.flex(0) }),
        { kind = "color", id = id, hold = "rename" })
    local border = selected and math.max(2, px(2.5)) or math.max(1, px(1))
    return BoardUI.box({ w = cw, h = chh, radius = px(10), border = border, border_col = selected and INK.black or INK.g9, bg = INK.white },
        BoardUI.hstack({ w = cw - 2 * border, h = chh - 2 * border, gap = 0 }, { BoardUI.space(px(4), 1), swatch_box, name_box }))
end

-- --------------------------------------------------------------- sheet
local function sheetPosition(hl, index, ph)
    local sh = Device.screen:getHeight()
    local where = G_reader_settings:readSetting("highlight_dialog_position", "center")
    local pad = px(8)
    if where == "top" then return pad end
    if where == "bottom" then return sh - ph - pad end
    if where == "gesture" then
        local fake = { getContentSize = function() return { h = ph } end }
        local ok, anchor, pop_down = pcall(hl._getDialogAnchor, hl, fake, index)
        if ok and anchor and anchor.y then
            local y = pop_down and anchor.y or (anchor.y - ph)
            return math.max(pad, math.min(sh - ph - pad, y))
        end
    end
    return floor((sh - ph) / 2)
end

-- opts.new: the highlight is being made (KOReader's "Highlight prompt" setting):
-- the sheet edits the selection, and closing it makes the highlight, as
-- KOReader's own prompts do. opts.only: "style" or "color" to show just that.
function Highlight.openSheet(hl, index, opts)
    opts = opts or {}
    local class = require("apps/reader/modules/readerhighlight")
    local function item()
        if opts.new then return hl.selected_text end
        return hl.ui.annotation.annotations[index]
    end
    if not item() then return end
    local styles = class.getHighlightStyles()
    local show_style, show_color = opts.only ~= "color", opts.only ~= "style"
    local finished = false
    local function finish()
        if finished then return end
        finished = true
        local made = hl:saveHighlight(true)
        hl:clear()
        if opts.caller_callback then opts.caller_callback(made) end
    end
    local function change(field, value)
        if opts.new then item()[field] = value else applyChange(hl, index, field, value) end
    end
    local panel
    panel = Panel:new{
        build = function(p, sw, sh)
            local it = item()
            if not it then p:close(); return BoardUI.overlay(sw, sh, {}) end
            local w = math.min(px(500), sw - 2 * px(12))
            local pad = px(16)
            local iw = w - 2 * pad
            local drawer = it.drawer or hl.view.highlight.saved_drawer
            local color_id = it.color or hl.view.highlight.saved_color
            local muted = drawer == "invert"
            local header = BoardUI.hstack({ w = iw, h = px(44) }, {
                BoardUI.text(opts.new and _("New highlight") or _("Highlight"), { s = 20, b = true }), BoardUI.flex(0), MenuUI.iconButton("x", { kind = "close" }),
            })
            local function label(str) return BoardUI.text(str, { s = 13, b = true, col = INK.g4, w = iw }) end
            -- Styles.
            local gap = px(8)
            local tile_w = floor((iw - 3 * gap) / 4)
            local tiles = {}
            for _i, style in ipairs(styles) do
                table.insert(tiles, styleTile(style, tile_w, px(78), drawer == style[2], Palette.hex(color_id)))
            end
            -- Colors, three to a row.
            local cols = 3
            local cgap = px(8)
            local cw = floor((iw - (cols - 1) * cgap) / cols)
            local rows = {}
            local row = {}
            for _i, entry in ipairs(class.highlight_colors) do
                table.insert(row, colorCell(class, entry[2], cw, px(50), entry[2] == color_id, muted))
                if #row == cols then
                    table.insert(rows, BoardUI.hstack({ w = iw, gap = cgap }, row))
                    row = {}
                end
            end
            if #row > 0 then table.insert(rows, BoardUI.hstack({ w = iw, gap = cgap }, row)) end
            local items = { header, BoardUI.space(nil, px(6)) }
            if show_style then
                table.insert(items, label(_("Style")))
                table.insert(items, BoardUI.space(nil, px(6)))
                table.insert(items, BoardUI.hstack({ w = iw, gap = gap }, tiles))
            end
            if show_color then
                if show_style then table.insert(items, BoardUI.space(nil, px(14))) end
                table.insert(items, label(_("Color")))
                for _i, r in ipairs(rows) do
                    table.insert(items, BoardUI.space(nil, px(8)))
                    table.insert(items, r)
                end
                table.insert(items, BoardUI.space(nil, px(12)))
                table.insert(items, BoardUI.text(
                    (muted and show_style) and _("Invert has no color. Hold a name to rename it, a swatch to change it.")
                        or _("Hold a name to rename it. Hold a swatch to change the color."),
                    { s = 12, col = INK.g4, w = iw, lines = 2 }))
            end
            if opts.new then
                table.insert(items, BoardUI.space(nil, px(12)))
                table.insert(items, MenuUI.pill(_("Highlight"), { kind = "dark", w = iw, h = 48, s = 16, action = { kind = "done" } }))
            end
            local content = BoardUI.vstack({ w = w, pad = pad }, items)
            local border = math.max(1, px(1.5))
            local ph = content:getSize().h + 2 * border
            local widget = BoardUI.box({ w = w, h = ph, radius = px(16), bg = INK.white, border = border, border_col = INK.g6 }, content)
            local x, y = floor((sw - w) / 2), sheetPosition(hl, index, ph)
            p.panel_rect = Geom:new{ x = x, y = y, w = w, h = ph }
            return BoardUI.overlay(sw, sh, { { widget = widget, x = x, y = y } })
        end,
        on_action = function(p, action)
            if action.kind == "style" then
                change("drawer", action.id)
                p:refresh()
            elseif action.kind == "color" then
                change("color", action.id)
                p:refresh()
            elseif action.kind == "done" then
                p:close()
            end
        end,
        on_close = function()
            if opts.new then finish() end
        end,
        on_hold = function(p, action)
            if action.kind ~= "color" then return end
            local id = action.id
            if action.hold == "rename" then
                require("aleph_input").prompt{
                    title = _("Rename color"), text = Palette.name(class, id), ok_label = _("Save"),
                    on_ok = function(text)
                        Palette.setName(class, id, text)
                        p:refresh()
                    end,
                }
            else
                require("aleph_color_wheel").open{
                    title = Palette.name(class, id), hex = Palette.hex(id),
                    on_use = function(hex)
                        Palette.setHex(class, id, hex)
                        UIManager:setDirty(hl.dialog, "ui")
                        p:refresh()
                    end,
                    on_reset = function()
                        Palette.resetHex(class, id)
                        UIManager:setDirty(hl.dialog, "ui")
                        p:refresh()
                    end,
                }
            end
        end,
    }
    panel:show()
    return panel
end


-- ------------------------------------------------------ the highlight menu
-- KOReader's menu for an existing highlight (tap one in the text): delete,
-- style and color, note, details, more, and the four arrows that move the
-- ends of the highlight. Same actions, in the board's style. Tap an arrow to
-- move by the current step (a word or a letter); hold one to switch the step
-- and move a letter, as KOReader does.
-- The Pin button the pins add to KOReader's text menu, if they did.
function Highlight.pinButton(hl)
    local buttons = hl._highlight_buttons
    return type(buttons) == "table" and buttons["13_rb_pin"] or nil
end

-- "Pin" or "Unpin" for the page a highlight is on, as that button says.
function Highlight.pinLabel(hl, it)
    local make = Highlight.pinButton(hl)
    local saved = hl.selected_text
    hl.selected_text = it
    local ok, button = pcall(make, hl)
    hl.selected_text = saved
    return ok and type(button) == "table" and button.text or _("Pin")
end

-- Pins (or unpins) the page of a highlight, through that same button.
function Highlight.pin(hl, it)
    local make = Highlight.pinButton(hl)
    if not make then return end
    hl.selected_text = require("util").tableDeepCopy(it)
    local ok, button = pcall(make, hl)
    if ok and type(button) == "table" and button.callback then
        local done, err = pcall(button.callback)
        if not done then require("logger").warn("Aleph: pin from highlight failed:", err) end
    end
    hl.selected_text = nil
end

function Highlight.openActions(hl, index)
    local util = require("util")
    local function item() return hl.ui.annotation.annotations[index] end
    if not item() then return end
    local by_letter = false
    local panel
    panel = Panel:new{
        build = function(p, sw, sh)
            local it = item()
            if not it then p:close(); return BoardUI.overlay(sw, sh, {}) end
            local w = math.min(px(500), sw - 2 * px(12))
            local pad = px(12)
            local iw = w - 2 * pad
            local movable = not it.text_edited
            -- The actions, each an icon over its name; Pin when pins are on.
            local actions = {
                { "trash", _("Delete"), "delete" }, { "palette", _("Style"), "style" },
                { "pen-line", _("Note"), "note" },
            }
            if Highlight.pinButton(hl) then actions[#actions + 1] = { "pin", Highlight.pinLabel(hl, it), "pin" } end
            actions[#actions + 1] = { "info", _("Details"), "details" }
            actions[#actions + 1] = { "ellipsis", _("More"), "more" }
            local n = #actions
            local gap = px(6)
            local cw = floor((iw - (n - 1) * gap) / n)
            local ch = px(58)
            local border = math.max(1, px(1.25))
            local cells = {}
            for i, a in ipairs(actions) do
                local this_w = i == n and (iw - (n - 1) * (cw + gap)) or cw
                local inner = BoardUI.vstack({ w = this_w - 2 * border, h = ch - 2 * border, align = "center" }, {
                    BoardUI.flex(0), BoardUI.icon(a[1], px(20), { sw = 2.25 }), BoardUI.space(nil, px(4)),
                    BoardUI.text(a[2], { s = 12, b = true, w = this_w - px(6), align = "center", data = true }), BoardUI.flex(0),
                })
                table.insert(cells, BoardUI.hit(BoardUI.box({ w = this_w, h = ch, radius = px(12), border = border, border_col = INK.g6, bg = INK.white }, inner),
                    { kind = a[3] }))
            end
            -- The arrows: start and end, each earlier or later, with the step
            -- (a word or a letter) between them, all on one line.
            local function arrow(side, dir)
                local name = dir < 0 and "chevron-left" or "chevron-right"
                local aw, ah = px(42), px(36)
                local box = BoardUI.box({ w = aw, h = ah, radius = px(10), border = border, border_col = movable and INK.g6 or INK.gd, bg = INK.white },
                    BoardUI.hstack({ w = aw - 2 * border, h = ah - 2 * border }, { BoardUI.flex(0),
                        BoardUI.icon(name, px(18), { col = movable and "black" or "gb", sw = 2.5 }), BoardUI.flex(0) }))
                return movable and BoardUI.hit(box, { kind = "move", side = side, dir = dir }) or box
            end
            local function lab(str) return BoardUI.text(str, { s = 12, b = true, col = INK.g4 }) end
            local moves = BoardUI.hstack({ w = iw, gap = px(6) }, {
                lab(_("Start")), arrow(0, -1), arrow(0, 1), BoardUI.flex(0),
                MenuUI.pill(by_letter and _("Letter") or _("Word"), { kind = "outline", h = 32, s = 12, pad_x = 12, action = { kind = "step" } }),
                BoardUI.flex(0),
                arrow(1, -1), arrow(1, 1), lab(_("End")),
            })
            local items = { BoardUI.hstack({ w = iw, gap = gap }, cells), BoardUI.space(nil, px(10)), moves }
            if not movable then
                table.insert(items, BoardUI.space(nil, px(8)))
                table.insert(items, BoardUI.text(_("The text of this highlight was edited, so its ends cannot be moved."), { s = 12, col = INK.g4, w = iw, lines = 2 }))
            end
            local content = BoardUI.vstack({ w = w, pad = pad }, items)
            local b2 = math.max(1, px(1.5))
            local ph = content:getSize().h + 2 * b2
            local widget = BoardUI.box({ w = w, h = ph, radius = px(16), bg = INK.white, border = b2, border_col = INK.g6 }, content)
            local x, y = floor((sw - w) / 2), placeAway(hl, index, ph) or sheetPosition(hl, index, ph)
            p.panel_rect = Geom:new{ x = x, y = y, w = w, h = ph }
            return BoardUI.overlay(sw, sh, { { widget = widget, x = x, y = y } })
        end,
        on_action = function(p, action)
            local k = action.kind
            if k == "delete" then p:close(); hl:deleteHighlight(index)
            elseif k == "style" then p:close(); Highlight.openSheet(hl, index)
            elseif k == "note" then p:close(); hl:editNote(index)
            elseif k == "details" then p:close(); hl.ui.bookmark:showBookmarkDetails(index)
            elseif k == "pin" then
                local it = item()
                p:close()
                if it then Highlight.pin(hl, it) end
            elseif k == "more" then
                local it = item()
                p:close()
                if it then
                    hl.selected_text = util.tableDeepCopy(it)
                    hl:onShowHighlightMenu(index)
                end
            elseif k == "move" then hl:updateHighlight(index, action.side, action.dir, by_letter)
            elseif k == "step" then by_letter = not by_letter; p:refresh()
            end
        end,
        on_hold = function(p, action)
            if action.kind == "move" then
                by_letter = not by_letter
                hl:updateHighlight(index, action.side, action.dir, true)
                p:refresh()
            end
        end,
    }
    -- Posts at both ends of the highlight; dragging one hides this menu so
    -- the text is in view, and the menu returns when the finger lifts.
    Handles.attach(hl, panel, index, function() Highlight.openActions(hl, index) end)
    panel:show()
    return panel
end


-- ------------------------------------------------- the selection / More menu
-- KOReader's menu for selected text and, from a highlight's More, the same
-- list: Extend, Highlight, Copy, Add note, Wikipedia, Dictionary, Translate,
-- Search and whatever plugins add. Same buttons, two to a row, each with an
-- icon.
local MENU_ICONS = {
    ["01_select"] = "arrow-right", ["02_highlight"] = "highlighter", ["03_copy"] = "files", ["04_add_note"] = "pen-line",
    ["05_wikipedia"] = "wikipedia", ["06_dictionary"] = "book-open-text", ["07_translate"] = "arrow-left-right",
    ["08_share_text"] = "corner-up-right", ["09_view_html"] = "scroll-text", ["10_user_dict"] = "book-marked",
    ["11_follow_link"] = "arrow-up-right", ["12_search"] = "search", ["12_generate_qr_code"] = "layout-grid",
    ["12_0_make_handmade_toc_item"] = "list-ordered", ["13_rb_pin"] = "pin",
}

local function buttonEnabled(b)
    if b.enabled_func then return b.enabled_func() ~= false end
    return b.enabled ~= false
end

function Highlight.openMenu(hl, index, entries)
    local panel
    panel = Panel:new{
        build = function(p, sw, sh)
            local w = math.min(px(500), sw - 2 * px(12))
            local pad = px(14)
            local iw = w - 2 * pad
            local gap = px(8)
            local cw = floor((iw - gap) / 2)
            local ch = px(52)
            local border = math.max(1, px(1.25))
            local rows, row = {}, {}
            local function flush()
                if #row == 0 then return end
                if #row == 1 then table.insert(row, BoardUI.space(cw, ch)) end
                if #rows > 0 then table.insert(rows, BoardUI.space(nil, gap)) end
                table.insert(rows, BoardUI.hstack({ w = iw, gap = gap }, row))
                row = {}
            end
            for i, e in ipairs(entries) do
                local b = e.button
                local on = buttonEnabled(b)
                local label = b.text or (b.text_func and b.text_func()) or ""
                local name = MENU_ICONS[e.id]
                local items = {}
                if name then table.insert(items, BoardUI.icon(name, px(20), { col = on and "black" or "gb", sw = 2.25 })) end
                table.insert(items, BoardUI.text(label, { s = 14, b = true, col = on and INK.black or INK.gb, w = cw - 2 * px(10) - (name and px(28) or 0), data = true }))
                local inner = BoardUI.hstack({ w = cw - 2 * border, h = ch - 2 * border }, {
                    BoardUI.flex(0), BoardUI.hstack({ gap = px(8) }, items), BoardUI.flex(0) })
                local box = BoardUI.box({ w = cw, h = ch, radius = px(12), border = border, border_col = on and INK.g6 or INK.gd, bg = INK.white }, inner)
                table.insert(row, on and BoardUI.hit(box, { kind = "button", i = i }) or box)
                if #row == 2 then flush() end
            end
            flush()
            -- From a highlight's More: a way back to its menu.
            if index and hl.ui.annotation.annotations[index] then
                local back = BoardUI.hstack({ h = px(32), gap = px(4) }, {
                    BoardUI.icon("chevron-left", px(18), { sw = 2.5 }),
                    BoardUI.text(_("Back"), { s = 14, b = true }),
                })
                table.insert(rows, 1, BoardUI.space(nil, px(6)))
                table.insert(rows, 1, BoardUI.hstack({ w = iw }, { BoardUI.hit(back, { kind = "back" }), BoardUI.flex(0) }))
            end
            local content = BoardUI.vstack({ w = w, pad = pad }, rows)
            local b2 = math.max(1, px(1.5))
            local ph = content:getSize().h + 2 * b2
            local widget = BoardUI.box({ w = w, h = ph, radius = px(16), bg = INK.white, border = b2, border_col = INK.g6 }, content)
            local x, y = floor((sw - w) / 2), sheetPosition(hl, index, ph)
            p.panel_rect = Geom:new{ x = x, y = y, w = w, h = ph }
            return BoardUI.overlay(sw, sh, { { widget = widget, x = x, y = y } })
        end,
        on_action = function(p, action)
            if action.kind == "back" then
                p:close()
                hl.highlight_dialog = nil
                hl.selected_text = nil
                Highlight.openActions(hl, index)
                return
            end
            local e = entries[action.i]
            if e and e.button.callback then e.button.callback() end
        end,
        on_hold = function(p, action)
            local e = entries[action.i]
            if e and e.button.hold_callback then e.button.hold_callback() end
        end,
        -- A tap outside: KOReader's own behaviour for this dialog.
        on_close = function()
            if hl.hold_pos then hl:clear() end
        end,
    }
    hl.highlight_dialog = panel
    Handles.attach(hl, panel, index, function() hl:onShowHighlightMenu(index) end)
    panel:show()
    return panel
end


local wanted -- defined with the install code below
-- The screen boxes of a highlight's text, for placing a menu beside it.
local function highlightBoxes(hl, item)
    if not hl.ui.rolling or type(item.pos0) ~= "string" then return nil end
    local ok, boxes = pcall(hl.ui.document.getScreenBoxesFromPositions, hl.ui.document, item.pos0, item.pos1, true)
    if ok and type(boxes) == "table" and #boxes > 0 then return boxes end
end

-- Next to the highlight, not over it, so the posts stay in view.
placeAway = function(hl, index, ph)
    if not hl.ui.rolling then return nil end
    local item = hl.ui.annotation.annotations[index]
    local boxes = item and highlightBoxes(hl, item)
    if not boxes then return nil end
    local top, bottom = math.huge, 0
    for _i, b in ipairs(boxes) do
        top, bottom = math.min(top, b.y), math.max(bottom, b.y + b.h)
    end
    local screen_h = Device.screen:getHeight()
    local gap = px(36)
    if screen_h - bottom - gap >= ph then return bottom + gap end
    if top - gap - ph >= px(8) then return top - gap - ph end
    return nil
end

-- -------------------------------------------------------------- install
wanted = function()
    local stored = G_reader_settings:readSetting("aleph")
    return not (type(stored) == "table" and stored.style_dialogs == false)
end

-- One button where there were Style and Color.
local function mergeButtons(buttons)
    local row = buttons and buttons[1]
    if not row then return end
    local C_ = _.pgettext
    local style_text, color_text = C_("Highlight", "Style"), C_("Highlight", "Color")
    local style_at, color_at
    for i, button in ipairs(row) do
        if button.text == style_text then style_at = i elseif button.text == color_text then color_at = i end
    end
    if style_at and color_at then
        row[style_at].text = _("Style & color")
        table.remove(row, color_at)
    end
end

-- For the other restyled screens (the bookmark filters, the page background).
Highlight.palette = Palette
Highlight.colorOf = colorOf
Highlight.styleSample = styleSample

-- What the drag posts need from the rest of the reader (adapted from ZenOS):
-- the page margins in scroll mode, a short pause on page taps after a drag
-- or a menu so the finger that let go does not also turn the page, and
-- closing the posts with the selection or the document.
function Highlight.installHandles(class)
    local time = require("ui/time")
    local Viewport = require("aleph_viewport")
    local ReaderView = require("apps/reader/modules/readerview")
    if not ReaderView._rb_viewport then
        ReaderView._rb_viewport = true
        local paint = ReaderView.paintTo
        ReaderView.paintTo = function(self, bb, x, y)
            paint(self, bb, x, y)
            if wanted() then Viewport.paintMargins(self, bb, x, y) end
        end
    end
    local ReaderUI = require("apps/reader/readerui")
    if not ReaderUI._rb_tap_guard then
        ReaderUI._rb_tap_guard = true
        local handle = ReaderUI.handleEvent
        ReaderUI.handleEvent = function(self, event)
            if event.handler == "onGesture" and wanted() then
                local highlight = self.highlight
                local deadline = highlight and highlight._rb_highlight_tap_until
                if deadline then
                    local ges = event.args and event.args[1]
                    if time.now() >= deadline then
                        highlight._rb_highlight_tap_until = nil
                    elseif ges and (ges.ges == "tap" or ges.ges == "double_tap") then
                        return true
                    end
                end
            end
            return handle(self, event)
        end
    end
    local hold_release = class.onHoldRelease
    if hold_release then
        class.onHoldRelease = function(self, ...)
            if wanted() and self.selected_text then Handles.suppressReaderTaps(self) end
            return hold_release(self, ...)
        end
    end
    for _i, method in ipairs({ "clear", "onClose", "onCloseDocument", "onSetDimensions", "onSuspend" }) do
        local original = class[method]
        class[method] = function(self, ...)
            self._rb_highlight_viewport = nil
            local controller = self._rb_highlight_handles
            if (method == "clear" or method == "onClose") and wanted()
                    and (self.hold_pos or self.highlight_dialog or controller) then
                Handles.suppressReaderTaps(self)
            end
            if controller then
                controller:close()
                if controller.dialog and controller.dialog.closeQuiet then controller.dialog:closeQuiet() end
            end
            if original then return original(self, ...) end
        end
    end
end

function Highlight.install()
    local class = require("apps/reader/modules/readerhighlight")
    if class._aleph_hooked then return end
    class._aleph_hooked = true
    Palette.apply(class)
    Highlight.installHandles(class)

    local function reroute(name)
        local original = class[name]
        class[name] = function(self, index)
            if not wanted() then return original(self, index) end
            local ok, err = pcall(Highlight.openSheet, self, index)
            if not ok then
                require("logger").warn("Aleph: highlight sheet failed:", err)
                return original(self, index)
            end
        end
    end
    reroute("editHighlightStyle")
    reroute("editHighlightColor")

    -- The highlight prompt setting (Gear > Taps and gestures > Long-press on
    -- text > Highlight prompt: style, color, or both) opens the same sheet.
    local original_prompt = class.showHighlightPrompt
    function class:showHighlightPrompt(caller_callback, prompt)
        local chosen = prompt or G_reader_settings:readSetting("highlight_prompt")
        if not wanted() or not chosen then return original_prompt(self, caller_callback, prompt) end
        if self.highlight_dialog then
            UIManager:close(self.highlight_dialog)
            self.highlight_dialog = nil
        end
        if self.hold_pos and not self.selected_text then self:highlightFromHoldPos() end
        if not (self.selected_text and self.selected_text.pos0 and self.selected_text.pos1) then return end
        local only = chosen == "style" and "style" or chosen == "color" and "color" or nil
        local ok, err = pcall(Highlight.openSheet, self, nil, { new = true, only = only, caller_callback = caller_callback })
        if not ok then
            require("logger").warn("Aleph: highlight prompt failed:", err)
            return original_prompt(self, caller_callback, prompt)
        end
    end

    local original_menu = class.onShowHighlightMenu
    function class:onShowHighlightMenu(index)
        if not wanted() then return original_menu(self, index) end
        if not self.selected_text then return end
        local entries = {}
        for idx, fn_button in require("ffi/util").orderedPairs(self._highlight_buttons) do
            local button = fn_button(self, index)
            if not button.show_in_highlight_dialog_func or button.show_in_highlight_dialog_func() then
                table.insert(entries, { id = idx, button = button })
            end
        end
        local ok, err = pcall(Highlight.openMenu, self, index, entries)
        if not ok then
            require("logger").warn("Aleph: highlight menu failed:", err)
            return original_menu(self, index)
        end
    end

    local original_dialog = class.showHighlightDialog
    function class:showHighlightDialog(index)
        if not wanted() then return original_dialog(self, index) end
        local shown, why = pcall(Highlight.openActions, self, index)
        if shown then return end
        require("logger").warn("Aleph: highlight menu failed:", why)
        local ButtonDialog = require("ui/widget/buttondialog")
        local own_new = rawget(ButtonDialog, "new")
        ButtonDialog.new = function(cls, o)
            ButtonDialog.new = own_new
            if type(o) == "table" then pcall(mergeButtons, o.buttons) end
            return ButtonDialog:new(o)
        end
        local ok, err = pcall(original_dialog, self, index)
        ButtonDialog.new = own_new
        if not ok then error(err, 0) end
    end
end

return Highlight
