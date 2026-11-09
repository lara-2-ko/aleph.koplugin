-- Aleph modification, 2026-11-08: the "Opening file" message in the
-- board's style.
--[[--
KOReader shows a plain message ("Opening file '...'") while it loads a book.
This replaces it with an Aleph card: the cover when the board has made
one, the title and the author. It is shown by the same call and closed the
same way as KOReader's, so the timing is unchanged.

It is installed once, as a hook on ReaderUI:showReaderCoroutine, and only for
that one message; every other message stays KOReader's.
]]

local Device = require("device")
local Geom = require("ui/geometry")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local BoardMetrics = require("aleph_board_metrics")
local BoardUI = require("aleph_board_ui")

local Screen = Device.screen
local INK = BoardMetrics.INK
local px = BoardMetrics.px

local Opening = {}

-- The title and author KOReader has for the file, else the file's name.
local function describe(file)
    local title, author
    local ok, props = pcall(function()
        local DocSettings = require("docsettings")
        if DocSettings:hasSidecarFile(file) then
            return DocSettings:open(file):readSetting("doc_props")
        end
    end)
    if ok and type(props) == "table" then
        title = props.title
        author = props.authors
    end
    if not title or title == "" then
        title = file:match("([^/]+)$") or file
        title = title:gsub("%.[%w]+$", "")
    end
    if type(author) == "string" then author = author:gsub("\n", ", ") end
    return title, author
end

-- The cover thumbnail the board made for this file, if it has one. The name
-- is built the way Local:cover builds it.
local function thumb(file)
    local ok, path = pcall(function()
        local lfs = require("libs/libkoreader-lfs")
        local attr = lfs.attributes(file)
        if not attr then return end
        local h = Screen:getHeight()
        local th = math.max(360, math.min(720, math.floor(h * 0.4)))
        local DataStorage = require("datastorage")
        local key = require("ffi/sha2").md5(file .. ":" .. attr.modification .. ":" .. attr.size .. ":" .. th)
        local candidate = DataStorage:getDataDir() .. "/cache/aleph/thumbs/" .. key .. ".png"
        if lfs.attributes(candidate, "mode") == "file" then return candidate end
    end)
    return ok and path or nil
end

local Card = InputContainer:extend{
    name = "aleph_opening",
    file = nil,
    timeout = nil,
}

function Card:init()
    BoardMetrics.refresh()
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    local title, author = describe(self.file)
    local w = math.min(px(420), sw - 2 * px(20))
    local pad = px(16)
    local cover_h = px(110)
    local cover_w = math.floor(cover_h * 2 / 3 + 0.5)
    local text_w = w - 2 * pad - cover_w - px(16)
    local path = thumb(self.file)
    local cover = BoardUI.cover({ title = title }, cover_w, cover_h, { path = path, border = math.max(1, px(1)), border_col = INK.g6, valign = "top" })
    local items = {
        BoardUI.text(_("Opening"), { s = 12, b = true, col = INK.g4, w = text_w }),
        BoardUI.space(nil, px(4)),
        BoardUI.text(title, { s = 18, b = true, lines = 3, w = text_w, data = true }),
    }
    if author and author ~= "" then
        table.insert(items, BoardUI.space(nil, px(4)))
        table.insert(items, BoardUI.text(author, { s = 14, col = INK.g3, w = text_w, data = true }))
    end
    local column = BoardUI.vstack({ w = text_w }, items)
    local body_h = math.max(cover_h, column:getSize().h)
    local h = body_h + 2 * pad
    local content = BoardUI.vstack({ w = w, h = h, pad = pad }, {
        BoardUI.hstack({ gap = px(16), valign = "top" }, { cover, column }),
    })
    local card = BoardUI.box({ w = w, h = h, radius = px(16), bg = INK.white, border = math.max(1, px(1.5)), border_col = INK.g6 }, content)
    local x, y = math.floor((sw - w) / 2), math.floor((sh - h) / 2)
    self.dimen = Geom:new{ x = x, y = y, w = w, h = h }
    self.card = card
    self[1] = card
end

function Card:paintTo(bb, x, y)
    self.card:paintTo(bb, self.dimen.x, self.dimen.y)
end

function Card:onShow()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
    -- Closes itself the way KOReader's own message does.
    if self.timeout then
        self._timeout_func = function()
            self._timeout_func = nil
            UIManager:close(self)
        end
        UIManager:scheduleIn(self.timeout, self._timeout_func)
    end
    return true
end

function Card:onCloseWidget()
    if self._timeout_func then
        UIManager:unschedule(self._timeout_func)
        self._timeout_func = nil
    end
end

-- KOReader asks the message for this when it decides what to repaint.
function Card:getVisibleArea()
    return self.dimen
end

local function styled()
    local stored = G_reader_settings:readSetting("aleph")
    return not (type(stored) == "table" and stored.style_dialogs == false)
end

function Opening.install()
    local ReaderUI = require("apps/reader/readerui")
    if ReaderUI._aleph_opening then return end
    ReaderUI._aleph_opening = true
    local original = ReaderUI.showReaderCoroutine
    function ReaderUI:showReaderCoroutine(file, provider, seamless)
        if seamless or not styled() then return original(self, file, provider, seamless) end
        local InfoMessage = require("ui/widget/infomessage")
        local own_new = rawget(InfoMessage, "new")
        -- The first message built during this call is the "Opening file" one.
        InfoMessage.new = function(cls, o)
            InfoMessage.new = own_new
            if type(o) == "table" and o.timeout == 0.0 and not o.invisible then
                local ok, card = pcall(Card.new, Card, { file = file, timeout = o.timeout })
                if ok and card then return card end
                require("logger").warn("Aleph: opening card failed:", card)
            end
            return InfoMessage:new(o)
        end
        require("logger").info("Aleph: opening card for a book")
        local ok, err = pcall(original, self, file, provider, seamless)
        InfoMessage.new = own_new
        if not ok then error(err, 0) end
    end
end

return Opening
