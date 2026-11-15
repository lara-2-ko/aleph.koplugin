-- Aleph modification, 2026-11-14: the Literary clock widget.
--[[--
Tells the time with a line from a book that mentions it: the quote for the
current minute with the time in bold, and the book's title and author under
it. Minutes no book covers get a line written like one, with the time in
words ("twenty-seven minutes to ten").

Adapted from readinpixels' Literary Clock plugin for KOReader (MIT
licence, see THIRD_PARTY_NOTICES.md): its quote lookup, its time in words,
its fallback lines and its word wrapping with a bold time phrase. The
quotes (aleph_literary_clock/en/HH.lua) are its conversion of the
Literature Clock collection, which grew out of The Guardian's
reader-contributed literary clock; they are shared under CC BY-NC-SA 2.5
(see NOTICE).

  data       aleph_literary_clock/en/HH.lua, one file per hour:
             { ["HH:MM"] = { { quote, title, author, sfw }, ... } }
             In a quote, \1...\2 is italic, \3...\4 the time, \n a new line.
             Only the hour on screen is kept in memory.
  the pick   among the quotes for the minute that fit the tile at a readable
             size, the choice moves on from day to day and stays the same
             for the whole minute; the shortest when none fits
  the tile   the quote at the largest size that fills it, the title and
             author under it
  sfw        the quotes the collection marks as not safe for work are left
             out unless the tile's props say otherwise (sfw = false)
]]

local Blitbuffer = require("ffi/blitbuffer")
local Geom = require("ui/geometry")

local LC = {}

local ITALIC, BOLD = 1, 2

local function band(a, b) return math.floor(a / b) % 2 == 1 end

-- ------------------------------------------------------------- the quotes
local DIR = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$")) or "."
LC.dir = DIR .. "/aleph_literary_clock"
local cache_hour, cache_data

local function loadHour(hh)
    if cache_hour == hh then return cache_data end
    local ok, data = pcall(dofile, string.format("%s/en/%s.lua", LC.dir, hh))
    if not ok or type(data) ~= "table" then data = {} end
    cache_hour, cache_data = hh, data
    return data
end

-- The quotes for "HH:MM": { text, title, author, sfw } each.
function LC.quotesAt(hhmm, sfw_only)
    local list = loadHour(hhmm:sub(1, 2))[hhmm] or {}
    if not sfw_only then return list end
    local out = {}
    for _i, q in ipairs(list) do if q[4] then out[#out + 1] = q end end
    return out
end

-- The quote for `now`: among those `fits` accepts, one that moves on from
-- day to day; the shortest when none fits; nil for a minute with none.
function LC.pick(now, sfw_only, fits)
    local hhmm = os.date("%H:%M", now)
    local list = LC.quotesAt(hhmm, sfw_only)
    local n = #list
    if n == 0 then return nil end
    local day = tonumber(os.date("%j", now)) + tonumber(os.date("%Y", now)) * 366
    local start = day % n
    for i = 0, n - 1 do
        local q = list[(start + i) % n + 1]
        if not fits or fits(q) then return q end
    end
    local best
    for _i, q in ipairs(list) do
        if not best or #q[1] < #best[1] then best = q end
    end
    return best
end

-- --------------------------------------------------------- time in words
local ONES = {
    [0] = "zero", "one", "two", "three", "four", "five", "six", "seven",
    "eight", "nine", "ten", "eleven", "twelve", "thirteen", "fourteen",
    "fifteen", "sixteen", "seventeen", "eighteen", "nineteen",
}
local TENS = { [2] = "twenty", [3] = "thirty", [4] = "forty", [5] = "fifty" }

function LC.number(n)
    if n < 20 then return ONES[n] end
    local t, o = math.floor(n / 10), n % 10
    if o == 0 then return TENS[t] end
    return TENS[t] .. "-" .. ONES[o]
end

local function hour12(h)
    h = h % 12
    return h == 0 and 12 or h
end

-- Every way the quotes say h:m (12-hour clock).
function LC.timeForms(h, m)
    local hw, nw = LC.number(hour12(h)), LC.number(hour12(h + 1))
    local out = {}
    local function add(s) out[#out + 1] = s end
    if m == 0 then
        add(hw .. " o'clock"); add(hw)
        if h == 0 then add("midnight") end
        if h == 12 then add("noon") end
        return out
    end
    add(hw .. (m < 10 and " oh " or " ") .. LC.number(m))
    if m == 15 then add("a quarter past " .. hw); add("quarter past " .. hw)
    elseif m == 30 then add("half past " .. hw)
    elseif m == 45 then add("a quarter to " .. nw); add("quarter to " .. nw)
    elseif m < 30 then
        add(LC.number(m) .. (m == 1 and " minute" or " minutes") .. " past " .. hw)
        if m % 5 == 0 then add(LC.number(m) .. " past " .. hw) end
    else
        local to = 60 - m
        add(LC.number(to) .. (to == 1 and " minute" or " minutes") .. " to " .. nw)
        if to % 5 == 0 then add(LC.number(to) .. " to " .. nw) end
    end
    return out
end

-- ------------------------------------------------- minutes with no quote
-- Two kinds take turns: a narrator for whom nothing happened, and the
-- minute left to the reader. Never the same line twice in a row.
LC.FALLBACKS = {
    {
        "At {time} nothing happened that anyone cared to record.",
        "At {time} the world went on, unremarked.",
        "Nothing worth writing down occurred at {time}.",
        "At {time} the story paused, as stories sometimes do.",
        "It was {time}, and for once nobody was watching.",
    },
    {
        "{time}. No author has claimed this minute yet. Perhaps you will.",
        "It is {time}, and this page is still blank. It's yours.",
        "{time}: an unwritten minute, waiting for someone to fill it.",
        "No one has written about {time} yet. Go on, then.",
        "{time}, and the line is left open for you.",
    },
}
local filler = { kind = 1, last = {}, minute = nil, text = nil }

function LC.fillerText(template, words)
    local s = template:gsub("{time}", function() return "\3" .. words .. "\4" end)
    return (s:gsub("^([\1-\4]*)(%l)", function(marks, c) return marks .. c:upper() end))
end

function LC.filler(now)
    local minute = math.floor(now / 60)
    if filler.minute == minute then return filler.text end
    pcall(require, "random")
    local h, m = tonumber(os.date("%H", now)), tonumber(os.date("%M", now))
    local forms = LC.timeForms(h, m)
    local words = forms[math.random(#forms)]
    local kind = filler.kind
    filler.kind = kind % #LC.FALLBACKS + 1
    local list = LC.FALLBACKS[kind]
    local i = math.random(#list)
    if #list > 1 and i == filler.last[kind] then i = i % #list + 1 end
    filler.last[kind] = i
    filler.minute, filler.text = minute, LC.fillerText(list[i], words)
    return filler.text
end

-- ------------------------------------------------------------- the layout
-- KOReader's text boxes draw a block in one style, so the words are wrapped
-- here and each styled piece painted with RenderText.
function LC.tokenize(s)
    local items, word, buf, style = {}, nil, {}, 0
    local function flushSeg()
        if #buf > 0 then
            word = word or { segs = {} }
            word.segs[#word.segs + 1] = { text = table.concat(buf), style = style }
            buf = {}
        end
    end
    local function flushWord()
        flushSeg()
        if word then items[#items + 1] = word; word = nil end
    end
    for i = 1, #s do
        local c = s:sub(i, i)
        if c == "\1" then flushSeg(); if not band(style, ITALIC) then style = style + ITALIC end
        elseif c == "\2" then flushSeg(); if band(style, ITALIC) then style = style - ITALIC end
        elseif c == "\3" then flushSeg(); if not band(style, BOLD) then style = style + BOLD end
        elseif c == "\4" then flushSeg(); if band(style, BOLD) then style = style - BOLD end
        elseif c == " " then flushWord()
        elseif c == "\n" then flushWord(); items[#items + 1] = { nl = true }
        else buf[#buf + 1] = c end
    end
    flushWord()
    return items
end

local FILES = {
    [0] = "NotoSerif-Regular.ttf", [ITALIC] = "NotoSerif-Italic.ttf",
    [BOLD] = "NotoSerif-Bold.ttf", [ITALIC + BOLD] = "NotoSerif-BoldItalic.ttf",
}
local face_cache = {}

-- The faces of nominal size n (Aleph's interface size applied), with a
-- regular face drawn bold where a bold file is missing.
local function faces(n)
    local key = n .. ":" .. tostring(require("aleph_board_metrics").fontSize(1))
    local f = face_cache[key]
    if f then return f end
    local BoardMetrics = require("aleph_board_metrics")
    local RenderText = require("ui/rendertext")
    f = { faces = {}, fake_bold = {} }
    for style, file in pairs(FILES) do
        local face = BoardMetrics.fileFace(file, n)
        if not face then
            local plain = band(style, ITALIC) and FILES[ITALIC] or FILES[0]
            face = BoardMetrics.fileFace(plain, n) or BoardMetrics.face(n)
            f.fake_bold[style] = band(style, BOLD)
        end
        f.faces[style] = face
    end
    local h, asc = f.faces[0].ftsize:getHeightAndAscender()
    f.line_h = math.ceil(h)
    f.ascender = math.floor(asc + 0.5)
    f.space_w = RenderText:sizeUtf8Text(0, false, f.faces[0], " ", true).x
    face_cache[key] = f
    return f
end
LC._faces = faces

local function width(f, style, s)
    local RenderText = require("ui/rendertext")
    return RenderText:sizeUtf8Text(0, false, f.faces[style], s, true, f.fake_bold[style] or false).x
end

-- Greedy wrap: lines of placed words, and whether a word alone is too wide.
local function wrap(items, f, w)
    local lines, overflow = {}, false
    local cur = { w = 0, words = {} }
    for _i, it in ipairs(items) do
        if it.nl then
            lines[#lines + 1] = cur
            cur = { w = 0, words = {} }
        else
            local ww, segs = 0, {}
            for _j, seg in ipairs(it.segs) do
                segs[#segs + 1] = { text = seg.text, style = seg.style, x = ww }
                ww = ww + width(f, seg.style, seg.text)
            end
            if ww > w then overflow = true end
            local gap = #cur.words > 0 and f.space_w or 0
            if #cur.words > 0 and cur.w + gap + ww > w then
                lines[#lines + 1] = cur
                cur = { w = 0, words = {} }
                gap = 0
            end
            cur.words[#cur.words + 1] = { x = cur.w + gap, w = ww, segs = segs }
            cur.w = cur.w + gap + ww
        end
    end
    lines[#lines + 1] = cur
    return lines, overflow
end
LC._wrap = wrap

local function ellipsis(line, f, w)
    local ew = width(f, 0, "…")
    while #line.words > 1 and line.w + ew > w do
        table.remove(line.words)
        local last = line.words[#line.words]
        line.w = last.x + last.w
    end
    local last = line.words[#line.words]
    if last then
        last.segs[#last.segs + 1] = { text = "…", style = 0, x = last.w }
        last.w = last.w + ew
        line.w = last.x + last.w
    end
end

-- The attribution: "Title, Author", the title in italics.
local function attribution(title, author)
    title = (title and title ~= "") and title or nil
    author = (author and author ~= "") and author or nil
    if title and author then return "\1" .. title .. "\2, " .. author end
    if title then return "\1" .. title .. "\2" end
    return author
end

-- The quote laid out at size n: lines, the attribution's lines, the height.
local function layoutAt(p, n)
    local qf = faces(n)
    local lines, overflow = wrap(p.items, qf, p.w)
    local res = { n = n, qf = qf, lines = lines, overflow = overflow, quote_h = #lines * qf.line_h }
    res.h = res.quote_h
    if p.attr_items then
        local an = math.max(p.min_attr or 10, math.min(p.max_attr or 14, math.floor(n * 0.62 + 0.5)))
        local af = faces(an)
        res.af = af
        res.attr_lines = wrap(p.attr_items, af, p.w)
        -- At most two lines of title and author.
        if #res.attr_lines > 2 then
            for i = #res.attr_lines, 3, -1 do res.attr_lines[i] = nil end
            ellipsis(res.attr_lines[2], af, p.w)
        end
        res.gap = math.floor(qf.line_h * 0.45)
        res.h = res.h + res.gap + #res.attr_lines * af.line_h
    end
    return res
end

local function prepare(p)
    if not p.items then
        p.items = LC.tokenize(p.quote or "")
        local attr = attribution(p.title, p.author)
        p.attr_items = attr and LC.tokenize(attr) or nil
    end
end

-- Whether the quote fits w x h at size n or larger.
function LC.fitsAt(p, n, h)
    prepare(p)
    local res = layoutAt(p, n)
    return res.h <= h and not res.overflow
end

-- The largest size from lo to hi that fits h (binary search), else lo
-- with the quote cut short.
function LC.layout(p, h, lo, hi)
    prepare(p)
    local best
    while lo <= hi do
        local mid = math.floor((lo + hi) / 2)
        local r = layoutAt(p, mid)
        if r.h <= h and not r.overflow then best = r; lo = mid + 1 else hi = mid - 1 end
    end
    local res = best or layoutAt(p, p.min or 10)
    if res.h > h then
        local attr_h = res.h - res.quote_h
        local room = math.max(1, math.floor((h - attr_h) / res.qf.line_h))
        if room < #res.lines then
            for i = #res.lines, room + 1, -1 do res.lines[i] = nil end
            ellipsis(res.lines[room], res.qf, p.w)
            res.quote_h = room * res.qf.line_h
            res.h = res.quote_h + attr_h
            res.clamped = true
        end
    end
    return res
end

-- ------------------------------------------------------------- the widget
local Widget = require("ui/widget/widget")
local QuoteWidget = Widget:extend{ dimen = nil, ops = nil }

function QuoteWidget:getSize() return self.dimen end

function QuoteWidget:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local RenderText = require("ui/rendertext")
    for _i, op in ipairs(self.ops) do
        RenderText:renderUtf8Text(bb, x + op.x, y + op.baseline, op.face, op.text, true, op.bold, op.color)
    end
end

local function emit(ops, lines, f, top, w, align, colour)
    for i, line in ipairs(lines) do
        local lx = 0
        if align == "right" then lx = w - line.w elseif align == "center" then lx = math.floor((w - line.w) / 2) end
        local baseline = top + (i - 1) * f.line_h + f.ascender
        for _j, word in ipairs(line.words) do
            for _k, seg in ipairs(word.segs) do
                ops[#ops + 1] = { x = lx + word.x + seg.x, baseline = baseline, face = f.faces[seg.style],
                    bold = f.fake_bold[seg.style] or false, text = seg.text, color = colour(seg.style) }
            end
        end
    end
end

-- A widget of exactly w x h: the quote filling it, the attribution under it.
-- o: quote, title, author, w, h, min, max (sizes), fg, accent, muted,
-- valign ("center" or "top").
function LC.widget(o)
    local p = { quote = o.quote, title = o.title, author = o.author, w = o.w, min = o.min or 10,
        min_attr = o.min_attr, max_attr = o.max_attr }
    local res = LC.layout(p, o.h, o.min or 10, o.max or 34)
    local fg = o.fg or Blitbuffer.COLOR_BLACK
    local accent = o.accent or fg
    local muted = o.muted or Blitbuffer.COLOR_DARK_GRAY
    local top = o.valign == "top" and 0 or math.max(0, math.floor((o.h - res.h) / 2))
    local ops = {}
    emit(ops, res.lines, res.qf, top, o.w, "left", function(style) return band(style, BOLD) and accent or fg end)
    if res.attr_lines then
        emit(ops, res.attr_lines, res.af, top + res.quote_h + res.gap, o.w, "right", function() return muted end)
    end
    return QuoteWidget:new{ dimen = Geom:new{ x = 0, y = 0, w = o.w, h = o.h }, ops = ops }, res
end

-- ---------------------------------------------------------------- the tile
-- What changes the tile: the minute (for the board's picked-variant memo).
function LC.sig(ctx)
    return os.date("%H:%M", (ctx and ctx.d and ctx.d.now) or os.time())
end

function LC.tile(ctx, w, hh, props)
    local BoardMetrics = require("aleph_board_metrics")
    local BoardUI = require("aleph_board_ui")
    local INK, px = BoardMetrics.INK, BoardMetrics.px
    props = props or {}
    local now = os.time()
    local pad = hh < px(130) and px(10) or px(16)
    local iw, ih = w - 2 * pad, hh - 2 * pad
    local dark = BoardUI.surface == INK.black
    -- Small tiles read at smaller sizes; large ones not below a size a quote
    -- is comfortable at.
    local big = ih > px(220)
    local min = big and 12 or 10
    local legible = big and 15 or 11
    local max = big and 34 or 22
    local q = LC.pick(now, props.sfw ~= false, function(cand)
        return LC.fitsAt({ quote = cand[1], title = cand[2], author = cand[3], w = iw, min_attr = 10, max_attr = big and 14 or 12 }, legible, ih)
    end)
    local quote, title, author
    if q then
        quote, title, author = q[1], q[2], q[3]
    else
        quote = LC.filler(now)
    end
    local widget = LC.widget{
        quote = quote, title = title, author = author, w = iw, h = ih, min = min, max = max,
        min_attr = 10, max_attr = big and 14 or 12,
        fg = dark and INK.white or INK.g1, accent = dark and INK.white or INK.black,
        muted = dark and INK.gc or INK.g4,
    }
    return BoardUI.overlay(w, hh, { { widget = widget, x = pad, y = pad } })
end

-- For tests: forget the hour read and the fallback state.
function LC._reset()
    cache_hour, cache_data = nil, nil
    filler = { kind = 1, last = {}, minute = nil, text = nil }
    face_cache = {}
end

return LC
