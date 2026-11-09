local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local IconWidget = require("ui/widget/iconwidget")
local ImageWidget = require("ui/widget/imagewidget")
local NetworkMgr = require("ui/network/manager")
local Style = require("aleph_topbar_style")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local datetime = require("datetime")
local _ = require("gettext")

local Screen = Device.screen
local black, gray = Blitbuffer.COLOR_BLACK, Blitbuffer.COLOR_GRAY
local dark = Blitbuffer.COLOR_DARK_GRAY
local scale = Style.px
local floor = math.floor

local Panel = WidgetContainer:extend{}

local function rect(bb, x, y, w, h, color)
    if w > 0 and h > 0 then bb:paintRect(x, y, w, h, color) end
end

local function circle(bb, x, y, radius, color, outline)
    local inner = radius - scale(2)
    for dy = -radius, radius do
        local half = floor(math.sqrt(radius * radius - dy * dy))
        local cut = outline and math.abs(dy) < inner
            and floor(math.sqrt(inner * inner - dy * dy))
        if cut then
            rect(bb, x - half, y + dy, half - cut, 1, color)
            rect(bb, x + cut + 1, y + dy, half - cut, 1, color)
        else
            rect(bb, x - half, y + dy, half * 2 + 1, 1, color)
        end
    end
end

function Panel:addText(text, x, y, width, align, color, heading, size)
    local widget = TextWidget:new{
        text = text, face = Style.face(size or (heading and 20 or 13)),
        bold = heading, max_width = width, fgcolor = color or black, padding = 0,
    }
    local remaining = width - widget:getSize().w
    self:addWidget(widget, x + (align == "center" and floor(remaining / 2)
        or align == "right" and remaining or 0), y)
    return widget
end

function Panel:addWidget(widget, x, y)
    self[#self + 1] = widget
    self.positions[#self] = { x, y }
end

-- The white twin of a bundled icon, for a button drawn on a black circle.
local function whiteIcon(file)
    local white = file:gsub("%.svg$", "-white.svg")
    if white ~= file and lfs.attributes(white, "mode") == "file" then return white end
end

function Panel:addTile(tile, x, y, width, height, diameter)
    local inset = scale(4)
    local cx, cy = x + floor(width / 2), y + floor(diameter / 2) + scale(5)
    local outline = self.plugin:read("outline", true)
    local is_active = tile.active
    if type(is_active) == "function" then is_active = is_active() end
    local file = self.plugin:iconPath(tile.key, tile.icon)
    -- On, as in Aleph's quick controls: a black circle and a white
    -- icon; off, a ring. A custom icon with no white twin keeps a gray circle.
    local white = is_active and whiteIcon(file)
    if outline or is_active then
        self.badges[#self.badges + 1] = {
            x = cx, y = cy, r = floor(diameter / 2),
            active = tile.active, outline = outline, solid = white and true or false,
            color = tile.dim and dark or black,
        }
    end
    local size = floor(diameter * 0.64)
    local icon = IconWidget:new{
        file = white or file, width = size, height = size,
        alpha = true, dim = tile.dim,
    }
    self:addWidget(icon, cx - floor(size / 2), cy - floor(size / 2))
    -- A control's name is bold while it is on; an app's name is regular.
    local bold = tile.icon ~= "app" and is_active and true or false
    self:addText(tile.label, x + 2 * inset, y + diameter + scale(7),
        width - 4 * inset, "center", tile.dim and dark, bold, 13)
    self.regions[#self.regions + 1] = {
        x = x, y = y, w = width, h = height, tap = tile.tap,
        hold = tile.hold or function() self.plugin:chooseIcon(self.menu, tile.key, tile.label, tile.icon) end,
    }
end

function Panel:addStatus()
    local right, center = self.dimen.w - scale(12), scale(18)
    local function place(widget, gap)
        local size = widget:getSize()
        right = right - size.w
        self:addWidget(widget, right, center - floor(size.h / 2))
        right = right - scale(gap)
    end
    place(TextWidget:new{
        text = datetime.secondsToHour(os.time(), G_reader_settings:isTrue("twelve_hour_clock")),
        face = Style.face(12), bold = true, padding = 0,
    }, 7)
    if Device:hasBattery() then
        local power = Device:getPowerDevice()
        local level = math.max(0, math.min(100, power:getCapacity() or 0))
        place(TextWidget:new{
            text = tostring(level) .. "%", face = Style.face(12),
            fgcolor = Blitbuffer.COLOR_GRAY_4, padding = 0,
        }, 4)
        local width, height, nub = scale(21), scale(11), scale(2)
        right = right - width - nub
        self.status_battery = {
            x = right, y = center - floor(height / 2),
            w = width, h = height, nub = nub, level = level,
        }
        -- Charging: a thin outlined bolt, as tall as the Wi-Fi icon.
        local charging = false
        pcall(function() charging = power:isCharging() and true or false end)
        if charging then
            local bolt = scale(15)
            right = right - scale(4) - bolt
            self:addWidget(IconWidget:new{
                file = self.plugin.path .. "/icons/zap.svg", width = bolt, height = bolt, alpha = true,
            }, right, center - floor(bolt / 2))
        end
        right = right - scale(7)
    end
    local connected = NetworkMgr:isWifiOn() and NetworkMgr:isConnected()
    place(IconWidget:new{
        file = self.plugin.path .. "/icons/status-wifi" .. (connected and "" or "-off") .. ".svg",
        width = scale(15), height = scale(15), alpha = true,
    }, 0)
end

function Panel:addGrid(tiles, columns, y, height, diameter)
    local cell_width = self.dimen.w / columns
    for i, tile in ipairs(tiles) do
        local column, row = (i - 1) % columns, floor((i - 1) / columns)
        local x = floor(column * cell_width)
        self:addTile(tile, x, y + row * height,
            floor((column + 1) * cell_width) - x, height, diameter)
    end
end

function Panel:addSlider(spec, y)
    local width, edge = self.dimen.w, scale(44)
    self.value_text = self:addText(spec.label .. "  " .. spec.value,
        scale(12), y, width - 2 * scale(12))
    if spec.switch then
        local cell = scale(38)
        self.switch = { x = width - 2 * cell - scale(12), y = y, w = cell, h = scale(24) }
        for index, icon in ipairs({ "light", "warmth" }) do
            local x = self.switch.x + (index - 1) * cell
            local size = scale(17)
            self:addWidget(IconWidget:new{
                file = self.plugin:iconPath("slider_" .. icon, icon),
                width = size, height = size, alpha = true,
            }, x + floor((cell - size) / 2), y + floor((self.switch.h - size) / 2))
            self.regions[#self.regions + 1] = {
                x = x, y = y, w = cell, h = self.switch.h,
                tap = function() spec.switch(index == 2) end,
            }
        end
    end
    -- Room between the title with its light / warmth switch and the rail.
    local bar_y = y + scale(50)
    self.slider = {
        x = edge, y = bar_y, w = width - 2 * edge, h = scale(34), spec = spec,
    }
    local function step(x, name, delta)
        local ring = scale(30)
        local cx, cy = x + floor(edge / 2), bar_y + floor(scale(34) / 2)
        self.badges[#self.badges + 1] = { x = cx, y = cy, r = floor(ring / 2), outline = true, color = black }
        local size = scale(16)
        self:addWidget(IconWidget:new{
            file = self.plugin.path .. "/icons/" .. name .. ".svg", width = size, height = size, alpha = true,
        }, cx - floor(size / 2), cy - floor(size / 2))
        self.regions[#self.regions + 1] = {
            x = x, y = bar_y, w = edge, h = scale(34),
            tap = function() self:setValue(spec.value + delta) end,
        }
    end
    step(0, "minus", -1)
    step(width - edge, "plus", 1)
end

function Panel:addBook(y, available)
    local book = self.plugin:bookSummary()
    local inset = scale(12)
    local cover_h = math.min(scale(170), math.max(scale(110), available),
        floor(self.dimen.w * 0.32))
    local cover_w = math.max(1, math.min(floor(self.dimen.w * 0.24), floor(cover_h * 0.75)))
    local border = scale(1)
    local cover
    if book.cover then
        local ratio = math.min((cover_w - 2 * border) / book.cover:getWidth(),
            (cover_h - 2 * border) / book.cover:getHeight())
        cover = ImageWidget:new{
            image = book.cover,
            width = math.max(1, floor(book.cover:getWidth() * ratio)),
            height = math.max(1, floor(book.cover:getHeight() * ratio)),
        }
    else
        cover = IconWidget:new{
            file = self.plugin:iconPath("book_cover_placeholder", "book"),
            width = cover_w - 2 * border, height = cover_h - 2 * border,
        }
    end
    local frame = FrameContainer:new{ padding = 0, bordersize = border, cover }
    local size = frame:getSize()
    local cover_x = inset + floor((cover_w - size.w) / 2)
    local cover_y = y + floor((cover_h - size.h) / 2)
    self:addWidget(frame, cover_x, cover_y)
    self.regions[#self.regions + 1] = {
        x = inset, y = y, w = cover_w, h = cover_h,
        tap = function() self.plugin:openBookDetails(self.menu) end,
    }

    local x = cover_w + inset * 2
    local width = self.dimen.w - x - inset
    local line_y = y
    local function line(value, heading)
        if type(value) ~= "string" or value == "" then return end
        local text = value:gsub("%s*[\r\n;]+%s*", ", ")
        local widget = self:addText(text, x, line_y, width, nil, nil, heading)
        line_y = line_y + widget:getSize().h + scale(3)
    end
    line(book.title, true)
    line(book.authors)
    line(book.tags)
    line(book.times)
    if book.current and book.total then
        line(string.format(_("Page %d of %d"), book.current, book.total))
    end
    if book.progress then
        local caption = string.format("%d%%", floor(book.progress * 100))
        local widget = self:addText(caption, x, line_y, width)
        local label = widget:getSize()
        local start = x + label.w + scale(8)
        self.book_progress = {
            x = start, y = line_y + floor(label.h / 2), w = x + width - start,
            ratio = book.progress,
        }
        line_y = line_y + label.h
    end
    return math.max(y + cover_h, line_y)
end

function Panel:init()
    self.positions, self.badges, self.regions = {}, {}, {}
    self.dimen = Geom:new{ w = self.menu.item_width, h = 0 }
    self:addStatus()
    local y = scale(34)
    local tile_height, tile_diameter = scale(68), scale(34)
    local tiles, columns, slider
    if self.menu.item_table.id == "quicktopbar_controls" then
        tiles, slider = self.plugin:controls(self.menu)
        -- More room between the status line (Wi-Fi, battery, clock) and the
        -- row of quick actions; everything below moves down with it.
        y = y + scale(16)
        columns = math.max(1, math.min(#tiles, floor(self.dimen.w / scale(48))))
        self.menu.page, self.menu.page_num = 1, 1
    else
        tile_height, tile_diameter = scale(86), scale(50)
        columns = math.max(1, math.min(5, floor(self.dimen.w / scale(55))))
        local limit = self.menu.height or Screen:getHeight()
        local available = limit - self.menu.bar:getSize().h - self.menu.footer:getSize().h
            - self.menu.footer_top_margin:getSize().h - y - scale(12)
        local per_page = columns * math.max(1, math.min(3, floor(available / tile_height)))
        tiles = self.plugin:apps(self.menu, self.target_page, per_page, self.target_item)
        if not tiles then
            self.dimen.h = self:addBook(y + scale(4), available) + scale(8)
            return
        end
        if #tiles == 0 then
            self:addText(_("No apps to show"), 0, y + scale(8), self.dimen.w, "center", nil, true)
            self:addText(_("Choose apps in Tools → QuickTopBar → Show apps."),
                scale(8), y + scale(36), self.dimen.w - scale(16), "center", dark)
            y = y + scale(62)
        end
    end
    local diameter = math.min(tile_diameter, floor(self.dimen.w / columns) - scale(8))
    self:addGrid(tiles, columns, y, tile_height, diameter)
    y = y + math.ceil(#tiles / columns) * tile_height
    if slider then
        -- The slider sits lower, clear of the row of controls above it.
        self:addSlider(slider, y + scale(38))
        y = y + scale(130)
    end
    self.dimen.h = y + scale(5)
end

function Panel:paintSlider(bb, x, y)
    local bar = self.slider
    local spec = bar.spec
    local style = spec.style
    local fraction = (spec.value - spec.min) / math.max(1, spec.max - spec.min)
    local start, center = x + bar.x, y + bar.y + floor(bar.h / 2)
    local width = bar.w
    local filled = floor(fraction * width + 0.5)
    if style == "steps" then
        local count = math.min(24, math.max(1, spec.max - spec.min))
        for i = 1, count do
            local left, right = floor((i - 1) * width / count), floor(i * width / count)
            rect(bb, start + left, center - scale(4), right - left - scale(2),
                scale(8), fraction * count >= i - 0.001 and black or gray)
        end
    elseif style == "bar" then
        rect(bb, start, center - scale(4), width, scale(8), gray)
        rect(bb, start, center - scale(4), filled, scale(8), black)
    elseif style == "dots" then
        for i = 0, 10 do
            circle(bb, start + floor(i * width / 10), center, scale(3),
                fraction * 10 >= i - 0.001 and black or gray)
        end
    else
        rect(bb, start, center, width, scale(1), gray)
        rect(bb, start, center - scale(1), filled, scale(3), black)
        circle(bb, start + filled, center, scale(8), black)
    end
end

function Panel:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    self.painted = true
    if self.status_battery then
        local battery = self.status_battery
        local left, top = x + battery.x, y + battery.y
        local border, pad = math.max(1, scale(1.25)), scale(1.5)
        bb:paintBorder(left, top, battery.w, battery.h, border, black, scale(2.5))
        local fill = math.max(1, floor((battery.w - 2 * border - 2 * pad) * battery.level / 100 + 0.5))
        bb:paintRoundedRect(left + border + pad, top + border + pad,
            fill, battery.h - 2 * border - 2 * pad, black, scale(1))
        rect(bb, left + battery.w, top + floor((battery.h - scale(4.5)) / 2),
            battery.nub, scale(4.5), black)
    end
    for _, badge in ipairs(self.badges) do
        local active = badge.active
        if type(active) == "function" then active = active() end
        if badge.solid and active then
            circle(bb, x + badge.x, y + badge.y, badge.r, black)
        elseif active or badge.outline then
            circle(bb, x + badge.x, y + badge.y, badge.r,
                active and gray or badge.color, not active)
        end
    end
    if self.switch then
        local sw = self.switch
        local left, top = x + sw.x, y + sw.y
        local border = scale(1)
        local active = self.slider.spec.warmth and left + sw.w or left
        rect(bb, active, top, sw.w, sw.h, gray)
        rect(bb, left, top, sw.w * 2, border, black)
        rect(bb, left, top + sw.h - border, sw.w * 2, border, black)
        for _, line in ipairs({ left, left + sw.w, left + sw.w * 2 - border }) do
            rect(bb, line, top, border, sw.h, black)
        end
    end
    for i, widget in ipairs(self) do
        local position = self.positions[i]
        widget:paintTo(bb, x + position[1], y + position[2])
    end
    if self.book_progress then
        local bar = self.book_progress
        local height = scale(4)
        rect(bb, x + bar.x, y + bar.y, bar.w, height, gray)
        rect(bb, x + bar.x, y + bar.y, floor(bar.w * bar.ratio), height, dark)
    end
    if self.slider then self:paintSlider(bb, x, y) end
end

function Panel:setValue(value)
    local spec = self.slider.spec
    value = math.max(spec.min, math.min(spec.max, value))
    if value ~= spec.value then
        spec.set(value)
        spec.value = math.max(spec.min, math.min(spec.max, spec.get()))
        self.value_text:setText(spec.label .. "  " .. spec.value)
        UIManager:setDirty(self.menu.show_parent, "ui", self.dimen)
    end
end

local function inside(region, x, y)
    return x >= region.x and x < region.x + region.w and y >= region.y and y < region.y + region.h
end

function Panel:setPosition(x)
    local bar = self.slider
    local spec = bar.spec
    self:setValue(spec.min + floor((x - bar.x) * (spec.max - spec.min) / bar.w + 0.5))
end

function Panel:handle(kind, gesture)
    if not self.painted or not gesture.pos then return end
    local x, y = gesture.pos.x - self.dimen.x, gesture.pos.y - self.dimen.y
    local bar = self.slider
    if bar and not gesture.mousewheel_direction then
        local on_bar = inside(bar, x, y)
        if kind == "release" or kind == "swipe" then
            local swipe_on_bar = kind == "swipe" and on_bar and gesture.end_pos
                and gesture.direction ~= "north" and gesture.direction ~= "south"
            if self.dragging or swipe_on_bar then
                self.dragging = false
                self:setPosition(gesture.end_pos and gesture.end_pos.x - self.dimen.x or x)
                return true
            end
        elseif kind == "pan" then
            local start = gesture.start_pos or gesture.pos
            if self.dragging or (inside(bar, start.x - self.dimen.x, start.y - self.dimen.y)
                    and gesture.direction ~= "north" and gesture.direction ~= "south") then
                self.dragging = true
                self:setPosition(x)
                return true
            end
        elseif kind == "tap" and on_bar then
            self:setPosition(x)
            return true
        end
    end
    if kind == "tap" or kind == "hold" then
        for _, region in ipairs(self.regions) do
            if inside(region, x, y) and region[kind] then
                region[kind]()
                return true
            end
        end
    end
end

return Panel
