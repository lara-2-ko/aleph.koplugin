-- Aleph modification, 2026-11-08: the full screen image viewer in the
-- board's style.
--[[--
KOReader's image viewer keeps everything it does (pinch and spread to zoom,
drag to pan, swiping through several images, the progress bar). Its row of
buttons at the bottom (Original size / Scale, Rotate, Close) becomes rounded
cells with an icon and the board's font. The viewer shows them when you tap the
image, as before.
]]

local BoardMetrics = require("aleph_board_metrics")
local BoardUI = require("aleph_board_ui")
local Cell = require("aleph_cell")

local px = BoardMetrics.px
local floor = math.floor

local Viewer = {}

local ICONS = { scale = "maximize", rotate = "rotate-cw-square", close = "x" }

function Viewer.restyle(self)
    local layout = self.button_table and self.button_table.buttons_layout
    if not layout or not layout[1] or not self.button_container then return end
    BoardMetrics.refresh()
    local by_button = {}
    for id, button in pairs(self.button_table.button_by_id or {}) do by_button[button] = id end
    local pad, gap = px(14), px(8)
    local row_buttons = layout[1]
    local n = #row_buttons
    local cw = floor((self.width - 2 * pad - (n - 1) * gap) / n)
    local cells = {}
    for _i, button in ipairs(row_buttons) do
        cells[#cells + 1] = Cell:new{ w = cw, h = px(46), icon_name = ICONS[by_button[button]] or "x",
            show_label = true, source = button, label_size = 14 }
    end
    local row = BoardUI.vstack({ w = self.width, pad = { px(8), pad, px(14), pad } }, {
        BoardUI.hstack({ gap = gap }, cells),
    })
    local container = self.button_container
    if container[1] and container[1].free and container[1] ~= self.button_table then pcall(container[1].free, container[1]) end
    container[1] = row
    container.dimen.h = row:getSize().h
    -- The rest of the viewer is laid out again around the new row.
    self:update()
end

local wanted = require("aleph_prefs").styleDialogs

function Viewer.install()
    local ImageViewer = require("ui/widget/imageviewer")
    if ImageViewer._aleph_hooked then return end
    ImageViewer._aleph_hooked = true
    local original_init = ImageViewer.init
    function ImageViewer:init(...)
        original_init(self, ...)
        if not wanted() then return end
        local ok, err = pcall(Viewer.restyle, self)
        if not ok then require("logger").warn("Aleph: image viewer restyle failed:", err) end
    end
end

return Viewer
