-- Aleph modification, 2026-11-08: KOReader's text prompt in the
-- board's style.
--[[--
A subclass of KOReader's InputDialog, so typing, the keyboard, Enter and
cursor handling are all KOReader's. Only the look changes: a rounded panel in
the board's colours, a title in the board's font, a rounded input field and
pill buttons (Cancel, and the main action) instead of KOReader's plain text
buttons.

  Input.prompt{ title, text, hint, ok_label, on_ok(text) }
]]

local InputDialog = require("ui/widget/inputdialog")
local InputText = require("ui/widget/inputtext")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local BoardMetrics = require("aleph_board_metrics")
local BoardUI = require("aleph_board_ui")
local MenuUI = require("aleph_menu_ui")

local INK = BoardMetrics.INK
local px = BoardMetrics.px

-- The text field with rounded corners; KOReader rebuilds its frame on every
-- edit, so the shape is set each time.
local FieldText = InputText:extend{}
function FieldText:initTextBox(...)
    InputText.initTextBox(self, ...)
    local frame = self._frame_textwidget
    if frame then
        frame.radius = px(10)
        frame.color = self.focused and INK.black or INK.g6
    end
end

local Prompt = InputDialog:extend{
    inputtext_class = FieldText,
    ok_label = nil,
    on_ok = nil,
}

function Prompt:init()
    BoardMetrics.refresh()
    self.input_face = BoardMetrics.face(16, "sans")
    self.border_size = 0
    InputDialog.init(self)
    self:_style()
end

function Prompt:_style()
    local frame = self.dialog_frame
    frame.radius = px(16)
    frame.bordersize = math.max(1, px(1.5))
    frame.color = INK.g6
    frame.background = INK.white
    local pad = px(16)
    local inner_w = self.width - 2 * pad
    local group = self.vgroup
    -- Title: the board's font, with room around it.
    local header = BoardUI.vstack({ w = self.width, pad = { pad, pad, 0, pad } }, {
        BoardUI.text(self.title or "", { s = 19, b = true, w = inner_w, data = true }),
    })
    group[1] = header
    -- Space around the field.
    group[2] = BoardUI.space(nil, px(12))
    group[4] = BoardUI.space(nil, px(14))
    -- Pills in place of KOReader's button table.
    local hits
    local row
    row, hits = BoardUI.collectHits(function()
        local gap = px(10)
        local half = math.floor((inner_w - gap) / 2)
        local cancel = MenuUI.pill(_("Cancel"), { kind = "outline", w = half, h = 48, s = 16,
            action = { kind = "cancel" } })
        local ok = MenuUI.pill(self.ok_label or _("OK"), { kind = "dark", w = half, h = 48, s = 16,
            action = { kind = "ok" } })
        return BoardUI.vstack({ w = self.width, pad = { 0, pad, pad, pad } }, {
            BoardUI.hstack({ gap = gap }, { cancel, ok }),
        })
    end)
    self._rb_hits = hits
    group[#group] = row
    group._size, group._offsets = nil, nil
end

function Prompt:_run(kind)
    if kind == "cancel" then
        UIManager:close(self)
    elseif kind == "ok" then
        local text = self:getInputText()
        UIManager:close(self)
        if self.on_ok then self.on_ok(text) end
    end
end

function Prompt:onTap(arg, ges)
    if ges and ges.pos then
        for index = #(self._rb_hits or {}), 1, -1 do
            local area = self._rb_hits[index]
            if area.dimen and ges.pos:intersectWith(area.dimen) then
                self:_run(area.action.kind)
                return true
            end
        end
    end
    return InputDialog.onTap(self, arg, ges)
end

local Input = {}

function Input.prompt(o)
    local dialog
    dialog = Prompt:new{
        title = o.title,
        input = tostring(o.text or ""),
        input_hint = o.hint,
        ok_label = o.ok_label,
        on_ok = o.on_ok,
        enter_callback = function() dialog:_run("ok") end,
        -- KOReader's own buttons are kept (for the keyboard's Enter and for
        -- D-pad devices); the pills are what is drawn.
        buttons = {{
            { text = _("Cancel"), callback = function() dialog:_run("cancel") end },
            { text = o.ok_label or _("OK"), is_enter_default = true, callback = function() dialog:_run("ok") end },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
    return dialog
end

return Input
