-- Modified for Aleph, 2026-11-07. Unofficial local-only fork. See NOTICE.
--[[--
The book page, laid out after BookOrbit's: the cover beside the series, title,
author, rating and status, where you stand and the Read / Details actions;
then the key facts, the description, genre chips, a shelf of similar books and
a pager through the list the page was opened from.

Everything comes from the local index (and KOReader's own sidecar data). There
is no download, sync or server state. Sections are fitted to the screen by
priority and the description takes the room that is left, so the page never
scrolls. Every tappable part is a BoardUI hit area, handled by the Browser.
]]

local UI = require("aleph_board_ui")
local Metrics = require("aleph_board_metrics")
local _ = require("gettext")

local INK = Metrics.INK
local px, lh = Metrics.px, Metrics.lh
local text, hstack, vstack, flex, space, icon = UI.text, UI.hstack, UI.vstack, UI.flex, UI.space, UI.icon

local Detail = {}

local function wOf(widget) return widget:getSize().w end
local function hOf(widget) return widget:getSize().h end
local function hair() return math.max(1, px(0.75)) end
local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- A vertical stack with a gap between its present items.
local function stack(o, items)
    if o.gap then
        local spaced = {}
        for _i, item in ipairs(items) do
            if item then
                if #spaced > 0 then spaced[#spaced + 1] = space(nil, o.gap) end
                spaced[#spaced + 1] = item
            end
        end
        items = spaced
    end
    return vstack(o, items)
end

local function textWidth(str, o)
    local t = text(str, o)
    local width = wOf(t)
    if t.free then t:free() end
    return width
end

local function rule(w, col)
    return UI.rect(w, hair(), col or INK.gc)
end

local STATUS = {
    unread = { label = _("Unread"), icon = "bookmark" },
    reading = { label = _("Reading"), icon = "book-open" },
    read = { label = _("Finished"), icon = "book-check" },
    on_hold = { label = _("On hold"), icon = "circle-pause" },
}

-- Plain text for a description: HTML removed, stray markdown emphasis
-- (**bold**, *italic*) dropped, paragraphs run together.
local function cleanDescription(str)
    if type(str) ~= "string" or str == "" then return nil end
    local ok, plain = pcall(require("util").htmlToPlainTextIfHtml, str)
    if ok and type(plain) == "string" then str = plain end
    str = str:gsub("%*%*(.-)%*%*", "%1")
    str = str:gsub("%*(.-)%*", "%1")
    str = str:gsub("%s*\n+%s*", " ")
    str = str:gsub("^%s+", ""):gsub("%s+$", "")
    return str ~= "" and str or nil
end

local function seriesIndexText(index)
    local value = tonumber(index)
    if not value then return nil end
    if value == math.floor(value) then return tostring(math.floor(value)) end
    return (string.format("%.2f", value):gsub("0+$", ""):gsub("%.$", ""))
end

local function shortDate(t)
    if not t or t <= 0 then return nil end
    return os.date("%b %d", t)
end

-- ----------------------------------------------------------------- pieces
-- A pill button. o: kind ("solid" or "outline"), icon, label, w, h, s.
local function pill(o)
    local h = o.h or px(46)
    local solid = o.kind == "solid"
    local fg = solid and "white" or "black"
    local items = {}
    if o.icon then
        items[#items + 1] = icon(o.icon, px(o.icon_size or 18), { col = fg, sw = 2.25, fill = o.icon == "play" })
    end
    if o.label then
        items[#items + 1] = text(o.label, { s = o.s or 15, b = true, col = solid and INK.white or INK.black })
    end
    if o.trail then items[#items + 1] = icon(o.trail, px(14), { col = fg, sw = 2.5 }) end
    local ring = solid and 0 or math.max(1, px(1.5))
    local inner = hstack({ gap = px(8) }, items)
    local pad = o.label and px(o.icon and 16 or 20) or 0
    local w = o.w or (o.label and (2 * pad + wOf(inner)) or h)
    local content = hstack({ w = w - 2 * ring, h = h - 2 * ring }, { flex(0), inner, flex(0) })
    return UI.box({ w = w, h = h, radius = math.floor(h / 2), border = ring, border_col = INK.black,
        bg = solid and INK.black or INK.white }, content)
end

-- Five stars, each its own tap target: tapping a star gives that rating,
-- tapping the current rating again clears it.
local function starsRow(book, size, gap)
    local items = {}
    for i = 1, 5 do
        local on = i <= (book.rating or 0)
        local star = icon("star", size, { sw = 1.75, col = on and "black" or "g8", fill = on })
        items[#items + 1] = UI.hit(hstack({ w = size + gap, h = px(40) }, { star, flex(0) }),
            { kind = "rate", book = book, rating = i })
    end
    return hstack({}, items)
end

-- Stars, then the status; the stars shrink and the status loses its icon
-- before anything collides.
local function verdictRow(b, w)
    local st = STATUS[b.readStatus] or STATUS.unread
    local function build(star, no_icon)
        local stars = starsRow(b, px(star), px(star >= 20 and 6 or 4))
        -- The status opens a list to change it, hence the chevron.
        local status = UI.hit(pill({ kind = "outline", icon = not no_icon and st.icon or nil, label = st.label,
            h = px(36), s = 13, icon_size = 16, trail = "chevron-down" }), { kind = "status-menu", book = b })
        return stars, status
    end
    local choice = { 16, true }
    for _i, variant in ipairs({ { 20, false }, { 20, true }, { 17, true } }) do
        local stars, status = build(variant[1], variant[2])
        if wOf(stars) + wOf(status) + px(10) <= w then choice = variant; break end
    end
    local stars, status = build(choice[1], choice[2])
    return hstack({ w = w, gap = px(10) }, { stars, flex(0), status })
end

-- Where the reader stands: a big percentage with the last read day, how it
-- ended, or that it is not started.
local function standing(b, w)
    local pct = math.floor((b.progressPercentage or 0) + 0.5)
    local function two(a, c)
        local items = { text(a, { s = 14, b = true, w = w }) }
        if c then items[#items + 1] = text(c, { s = 12, col = INK.g3, w = w }) end
        return vstack({ w = w }, items)
    end
    if b.readStatus == "read" then
        local done = type(b.finishedOn) == "string" and b.finishedOn:sub(1, 10) or nil
        return two(_("Finished"), done)
    end
    if pct <= 0 then return two(_("Not started"), nil) end
    local big = text(pct .. "%", { s = 26, b = true })
    local rw = math.max(px(40), w - wOf(big) - px(12))
    local first = b.readStatus == "on_hold" and _("On hold") or _("In progress")
    local last = shortDate(b.last_open)
    local items = { text(first, { s = 14, b = true, w = rw }) }
    if last then items[#items + 1] = text(_("Last read") .. " " .. last, { s = 12, col = INK.g3, w = rw }) end
    return vstack({ w = w }, {
        hstack({ w = w, gap = px(12) }, { big, vstack({ w = rw }, items) }),
        space(nil, px(8)),
        UI.bar(w, px(6), pct, { track = INK.gd, fill = INK.black, r = px(3) }),
    })
end

-- ----------------------------------------------------------------- header
function Detail.header(br, back_label, w)
    local box = px(44)
    local maxw = math.floor(w * 0.45)
    local label = text(back_label, { s = 15, b = true, data = true })
    if wOf(label) > maxw then label = text(back_label, { s = 15, b = true, w = maxw, data = true }) end
    local back = UI.hit(hstack({ h = box, gap = px(2) }, {
        icon("chevron-left", px(24), { sw = 2.25 }), label, space(px(8), 1),
    }), { kind = "back" })
    local more = UI.hit(hstack({ w = box, h = box }, { flex(0), icon("ellipsis", px(24), { sw = 2.25 }), flex(0) }), { kind = "detail-menu" })
    local status = UI.statusCluster({ clock = os.date("%H:%M") })
    return hstack({ w = w, h = px(48) }, { back, flex(0), status, space(px(10), 1), more })
end

-- ----------------------------------------------------------------- jacket
local function columnItems(br, b, tw)
    local items = {}
    if b.series and b.series ~= "" then
        local index = seriesIndexText(b.seriesIndex)
        local label = (index and (_("Book") .. " " .. index .. " · ") or "") .. b.series
        local chev = icon("chevron-right", px(14), { sw = 2.5, col = "g3" })
        local t = text(label, { s = 13, b = true, col = INK.g3, data = true })
        if wOf(t) + px(2) + px(14) > tw then
            t = text(label, { s = 13, b = true, col = INK.g3, w = tw - px(2) - px(14), data = true })
        end
        items[#items + 1] = UI.hit(hstack({ w = tw }, { t, space(px(2), 1), chev, flex(0) }),
            { kind = "books", params = { series = b.series, sort = "series" }, title = b.series })
        items[#items + 1] = space(nil, px(5))
    end
    local tf = UI.fitTitle(b.title, { b = true }, tw, { 24, 22, 20, 18, 17 }, 3)
    items[#items + 1] = text(b.title, { s = tf.s, b = true, lines = tf.lines > 1 and tf.lines or nil, w = tw, data = true })
    items[#items + 1] = space(nil, px(4))
    local authors = table.concat(b.authors or {}, ", ")
    if authors == "" then
        items[#items + 1] = text(_("Author unknown"), { s = 15, col = INK.g5, i = true, w = tw })
    else
        items[#items + 1] = text(authors, { s = 15, col = INK.g2, w = tw, data = true })
    end
    items[#items + 1] = space(nil, px(10))
    items[#items + 1] = verdictRow(b, tw)
    items[#items + 1] = flex(px(12))
    items[#items + 1] = standing(b, tw)
    items[#items + 1] = space(nil, px(12))
    -- The action and Details side by side; Details folds to an icon when narrow.
    local gap, h = px(8), px(44)
    local full = pill({ kind = "outline", icon = "info", label = _("Details"), h = h, s = 14, icon_size = 18 })
    local det = (tw - wOf(full) - gap < px(120)) and pill({ kind = "outline", icon = "info", h = h, icon_size = 18 }) or full
    local pct = b.progressPercentage or 0
    local verb = b.readStatus == "read" and _("Read again") or (pct > 0 and _("Resume") or _("Read"))
    local primary = UI.hit(pill({ kind = "solid", icon = "play", label = verb, w = tw - wOf(det) - gap, h = h, s = 14 }),
        { kind = "open", book = b })
    items[#items + 1] = hstack({ w = tw, gap = gap }, { primary, UI.hit(det, { kind = "info", book = b }) })
    return items
end

function Detail.jacket(br, b, w)
    local gut = px(16)
    local box_w = math.min(px(150), math.floor(w * 0.36 + 0.5))
    local box_h = math.floor(box_w * 1.5 + 0.5)
    local tw = w - box_w - gut
    -- A measuring pass: its hit areas are dropped again.
    local mark = UI.hitMark()
    local col_h = hOf(vstack({ w = tw }, columnItems(br, b, tw)))
    UI.hitTrim(mark)
    local column = vstack({ w = tw, h = math.max(box_h, col_h) }, columnItems(br, b, tw))
    br:prepareCover(b)
    local cover = UI.cover(b, box_w, box_h, { path = b.cover_path, border = math.max(1, px(1)), border_col = INK.g6, valign = "top" })
    return hstack({ w = w, valign = "top", gap = gut }, { cover, column })
end

-- ------------------------------------------------------------------ facts
function Detail.facts(b, w)
    local cw = math.floor(w / 3)
    local pad = px(12)
    local size = b.size and string.format("%.1f MB", b.size / 1048576) or nil
    local cells = {
        { os.date("%b %Y", b.added or os.time()), _("Added") },
        { (b.props and b.props.language and b.props.language ~= "") and b.props.language or "—", _("Language") },
        { (b.format and b.format ~= "" and b.format or "—") .. (size and (" · " .. size) or ""), _("On this device") },
    }
    local cell_h = lh(16) + lh(13) + px(4)
    local parts = {}
    for i, c in ipairs(cells) do
        local inner_w = cw - (i > 1 and (hair() + pad) or 0)
        local col = vstack({ w = inner_w }, {
            text(c[1], { s = 16, b = true, w = inner_w, data = true }),
            text(c[2], { s = 13, col = INK.g4, w = inner_w, data = true }),
        })
        if i > 1 then
            parts[#parts + 1] = UI.rect(hair(), cell_h, INK.gc)
            parts[#parts + 1] = space(pad, 1)
        end
        parts[#parts + 1] = col
    end
    local row = hstack({ w = w, h = cell_h }, parts)
    return vstack({ w = w }, { rule(w), space(nil, px(8)), row, space(nil, px(8)), rule(w) })
end

-- ------------------------------------------------------------------ chips
-- Genre chips on one row, then "+N" for the ones that did not fit.
function Detail.chips(b, w)
    local genres = b.genres or {}
    if #genres == 0 then return nil end
    local h = px(34)
    local ring = math.max(1, px(1.25))
    local gap, padx, plus_w = px(8), px(14), px(46)
    local parts, used, shown = {}, 0, 0
    for i, g in ipairs(genres) do
        local label = text(g, { s = 13, data = true })
        local cw = wOf(label) + 2 * padx
        local next_used = used + (shown > 0 and gap or 0) + cw
        local reserve = (i < #genres) and (gap + plus_w) or 0
        if next_used + reserve > w then
            if shown > 0 then break end
            cw = w - reserve
            label = text(g, { s = 13, w = math.max(px(16), cw - 2 * padx), data = true })
            next_used = cw
        end
        parts[#parts + 1] = UI.hit(UI.box({ w = cw, h = h, radius = math.floor(h / 2), border = ring, border_col = INK.black, bg = INK.white },
            hstack({ w = cw - 2 * ring, h = h - 2 * ring }, { flex(0), label, flex(0) })),
            { kind = "books", params = { genre = g, sort = "title" }, title = g })
        used, shown = next_used, shown + 1
    end
    if shown < #genres then
        local plus = text("+" .. (#genres - shown), { s = 13, b = true })
        parts[#parts + 1] = UI.hit(UI.box({ w = plus_w, h = h, radius = math.floor(h / 2), bg = INK.ge },
            hstack({ w = plus_w, h = h }, { flex(0), plus, flex(0) })), { kind = "genres-sheet", book = b })
    end
    parts[#parts + 1] = flex(0)
    return hstack({ w = w, h = h, gap = gap }, parts)
end

-- ----------------------------------------------------------------- shelf
local function shelfSize(w)
    local gap = px(10)
    local cw = math.floor((w - 4 * gap) / 5)
    local ch = math.floor(cw * 1.5)
    return gap, cw, ch, lh(14) + px(8) + ch
end

function Detail.shelf(br, label, books, w)
    local gap, cw, ch = shelfSize(w)
    local cells = {}
    for i = 1, 5 do
        local book = books[i]
        if book then
            cells[#cells + 1] = UI.hit(br:cover(book, cw, ch), { kind = "detail", book_id = book.id, list = { label = label, books = books } })
        else
            cells[#cells + 1] = space(cw, ch)
        end
    end
    return stack({ w = w, gap = px(8) }, { text(label, { s = 14, b = true, w = w, data = true }), hstack({ w = w, gap = gap }, cells) })
end

-- Books sharing this one's genres; failing that, the author's other books.
local function shelfBooks(br, b)
    local similar = br.local_library:similar(b, 5)
    if #similar > 0 then return _("Similar books"), similar end
    local author = b.authors and b.authors[1]
    if author then
        local others = {}
        for _i, x in ipairs(br.local_library:query({ author = author, sort = "title" })) do
            if x.id ~= b.id then others[#others + 1] = x end
        end
        if #others > 0 then
            local top = {}
            for i = 1, math.min(5, #others) do top[i] = others[i] end
            return _("More by") .. " " .. author, top
        end
    end
end

-- ------------------------------------------------------------------ pager
function Detail.pager(br, b, w)
    local list = br.detail_list
    if not list or not list.books or #list.books < 2 then return nil end
    local idx
    for i, x in ipairs(list.books) do
        if x.id == b.id then idx = i; break end
    end
    if not idx then return nil end
    local fh = px(48)
    local label = list.label or ""
    local mid_w = math.floor(clamp(textWidth(label, { s = 11 }) + px(12), px(92), w * 0.36) + 0.5)
    local side_w = math.floor((w - mid_w) / 2)
    local function side(dir)
        local other = list.books[idx + dir]
        if not other then return space(side_w, 1) end
        local chev = icon(dir < 0 and "chevron-left" or "chevron-right", px(20), { sw = 2.5 })
        local room = side_w - px(20) - px(4)
        local t = text(other.title, { s = 13, b = true, data = true })
        if wOf(t) > room then t = text(other.title, { s = 13, b = true, w = room, data = true }) end
        local items = dir < 0 and { chev, t, flex(0) } or { flex(0), t, chev }
        return UI.hit(hstack({ w = side_w, h = fh, gap = px(4) }, items), { kind = "detail-go", delta = dir })
    end
    local mid = vstack({ w = mid_w, align = "center" }, {
        text(idx .. " " .. _("of") .. " " .. #list.books, { s = 13, b = true }),
        text(label, { s = 11, col = INK.g4, w = mid_w, align = "center", data = true }),
    })
    local row = hstack({ w = w, h = fh - hair() }, { side(-1), mid, side(1) })
    return vstack({ w = w }, { rule(w, INK.gb), row })
end

-- ------------------------------------------------------------------- page
function Detail.build(br, m)
    local b = br.by_id[br.detail_book.id] or br.detail_book
    local margin = px(20)
    local w = m.w - 2 * margin
    local g = px(14)
    local back_label = br.detail_from == "home" and _("Home") or (br.library_title or _("Library"))

    local header = Detail.header(br, back_label, w)
    local jacket = Detail.jacket(br, b, w)
    local facts = Detail.facts(b, w)
    local pager = Detail.pager(br, b, w)

    local avail = m.h - 2 * margin - (hOf(header) + g + hOf(jacket) + g + hOf(facts) + (pager and (g + hOf(pager)) or 0))
    local line_h = lh(14)
    local desc_text = cleanDescription(b.props and b.props.description)
    local min_desc = desc_text and (g + 2 * line_h) or 0

    local chips = Detail.chips(b, w)
    if chips then
        if avail - min_desc >= g + hOf(chips) then avail = avail - g - hOf(chips) else chips = nil end
    end
    local shelf
    local _gap, _cw, _ch, shelf_h = shelfSize(w)
    if avail - min_desc >= g + shelf_h then
        local label, books = shelfBooks(br, b)
        if label then
            shelf = Detail.shelf(br, label, books, w)
            avail = avail - g - shelf_h
        end
    end

    local items = { header, jacket, facts }
    if desc_text then
        -- Cut short, the description ends in "Read all", and either opens
        -- About this book with the whole of it, page by page.
        local lines = clamp(math.floor((avail - g) / line_h), 1, 7)
        local more_h = lh(14) + px(2)
        local cut = false
        pcall(function() cut = require("aleph_text_pages").linesNeeded(desc_text, { s = 14 }, w) > lines end)
        local show_more = cut and avail - g >= lines * line_h + more_h
        if cut and not show_more and lines > 1 then lines, show_more = lines - 1, true end
        local about = text(desc_text, { s = 14, w = w, lines = lines, data = true })
        if show_more then
            local more = hstack({ gap = px(2) }, { text(_("Read all"), { s = 13, b = true }), icon("chevron-right", px(15), { sw = 2.5 }) })
            about = vstack({ w = w }, { about, space(nil, px(2)), more })
        end
        items[#items + 1] = UI.hit(about, { kind = "about", book = b })
    else
        items[#items + 1] = text(_("No description in this book's metadata."), { s = 14, col = INK.g5, i = true, w = w })
    end
    if chips then items[#items + 1] = chips end
    if shelf then items[#items + 1] = shelf end
    items[#items + 1] = flex(0)
    if pager then items[#items + 1] = pager end
    return stack({ w = m.w, h = m.h, pad = { margin, margin, margin, margin }, gap = g }, items)
end

return Detail
