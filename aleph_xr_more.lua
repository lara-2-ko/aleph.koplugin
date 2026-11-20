-- Aleph modification, 2026-11-18: more about a name in X-Ray, after
-- BookOrbit's Constellations.
--[[--
What X-Ray (aleph_xr.lua) can tell about a name from where it is mentioned,
on the device, with no AI:

    More.stats(ui, index)       where it comes up: mentions per chapter of
                                the pages read, the chapter it is first
                                seen in, the one it comes up most in, the
                                latest
    More.oftenWith(ui, index, n)  the names mentioned most often near it
                                (within a few mentions either side, in the
                                pages read)

and, for "Detailed descriptions" (aleph_xr_ai.lua), longer passages around
its mentions:

    More.passages(ui, index, n)   up to n passages of a sentence or two
                                around its mentions: the first, the busiest
                                chapter's, the latest, and some in between

Nothing past the page being read is used (unless "Show the whole book" is
on, as for the rest of X-Ray). The page of each mention is looked up once
and kept while the book is open.
]]

local try = require("aleph_try").call

local More = {}

More.NEAR = 4                 -- mentions either side that count as "near"
More.PASSAGE_BEFORE = 220     -- characters of text kept around a mention
More.PASSAGE_AFTER = 280

local function state(ui)
    local st = ui._aleph_xr
    if not st then
        st = {}
        ui._aleph_xr = st
    end
    return st
end

-- The page of mention number `hit` (in the book's order), kept.
function More.pageOf(ui, hit)
    local st = state(ui)
    st.hit_pages = st.hit_pages or {}
    local page = st.hit_pages[hit]
    if page == nil then
        local hits = require("aleph_xr").hits(ui)
        local xp = hits and hits.s[hit]
        try(function() page = xp and ui.document:getPageFromXPointer(xp) end)
        st.hit_pages[hit] = page or false
    end
    return page or nil
end

-- The chapter (its index in `chapters`) a page is in.
function More.chapterAt(chapters, page)
    local lo, hi = 1, #chapters
    if hi == 0 or not page then return nil end
    while lo < hi do
        local mid = math.floor((lo + hi + 1) / 2)
        if chapters[mid].page <= page then lo = mid else hi = mid - 1 end
    end
    return chapters[lo].page <= page and lo or 1
end

-- The mentions of name `index` read so far, as positions in the book's
-- list of mentions.
local function readHits(ui, index)
    local XR = require("aleph_xr")
    local hits = XR.hits(ui)
    local list = hits and hits.by[index]
    if not list then return {} end
    local seen = XR.count(ui, index)
    local out = {}
    for i = 1, seen do out[i] = list[i] end
    return out
end

-- { chapters, counts = { [chapter] = n }, first, busiest, busiest_n,
-- latest, current, upto } for name `index` (chapters: Story.chapters,
-- current: the chapter of the page shown, upto: the last chapter to draw).
function More.stats(ui, index, chapters)
    chapters = chapters or require("aleph_xr_story").chapters(ui)
    local out = { chapters = chapters, counts = {}, busiest_n = 0 }
    local page = 1
    try(function() page = ui:getCurrentPage() end)
    out.current = More.chapterAt(chapters, page)
    for _i, hit in ipairs(readHits(ui, index)) do
        local c = More.chapterAt(chapters, More.pageOf(ui, hit))
        if c then
            out.counts[c] = (out.counts[c] or 0) + 1
            out.first = out.first or c
            out.latest = c
            if out.counts[c] > out.busiest_n then out.busiest, out.busiest_n = c, out.counts[c] end
        end
    end
    out.upto = math.max(out.current or 1, out.latest or 1)
    return out
end

-- Names mentioned near name `index`: { { index, name, n }, ... }, the most
-- first. `positions`: its mentions; `n_of`: the name of each mention in
-- the book's order; `limit`: how far the pages read go.
function More.near(n_of, positions, index, limit, near, hidden)
    near = near or More.NEAR
    local counts = {}
    for _i, p in ipairs(positions) do
        local seen_here = {}
        for q = math.max(1, p - near), math.min(limit, p + near) do
            local other = n_of[q]
            if other and other ~= index and not seen_here[other] and not (hidden and hidden[other]) then
                seen_here[other] = true
                counts[other] = (counts[other] or 0) + 1
            end
        end
    end
    local list = {}
    for other, n in pairs(counts) do list[#list + 1] = { index = other, n = n } end
    table.sort(list, function(a, b)
        if a.n ~= b.n then return a.n > b.n end
        return a.index < b.index
    end)
    return list
end

function More.oftenWith(ui, index, count)
    local XR = require("aleph_xr")
    local data, hits = XR.names(ui), XR.hits(ui)
    if not (data and hits) then return {} end
    local hidden = {}
    for i, entry in ipairs(data.names) do
        if entry.hidden or entry.kind == "other" then hidden[i] = true end
    end
    local limit = XR.spoilers() and #hits.n or XR.readSoFar(ui)
    local list = More.near(hits.n, readHits(ui, index), index, limit, More.NEAR, hidden)
    local out = {}
    for i = 1, math.min(count or 4, #list) do
        local e = data.names[list[i].index]
        if e then out[#out + 1] = { index = list[i].index, name = e.name, n = list[i].n } end
    end
    return out
end

-- ------------------------------------------------------------- passages
-- Which of a name's mentions (1..seen) the passages are taken from: the
-- first, two in the chapter it comes up most, the three latest, and some
-- spread in between, n at most, in the book's order.
function More.picks(seen, n, busiest_from, busiest_to)
    local chosen, list = {}, {}
    local function add(i)
        if i >= 1 and i <= seen and not chosen[i] and #list < n then chosen[i] = true; list[#list + 1] = i end
    end
    add(1)
    if busiest_from then
        add(busiest_from)
        add(math.floor((busiest_from + busiest_to) / 2))
    end
    for i = seen, math.max(1, seen - 2), -1 do add(i) end
    local spread = n - #list
    for k = 1, spread do add(math.floor(seen * k / (spread + 1)) + 1) end
    table.sort(list)
    return list
end

-- A passage around `name` in `text`: whole words, starting and ending at a
-- sentence where one is near. `hint`: the words just before the mention
-- (to find the right one when the name is on the page more than once).
function More.cut(text, name, hint, before_n, after_n)
    before_n, after_n = before_n or More.PASSAGE_BEFORE, after_n or More.PASSAGE_AFTER
    text = text:gsub("%s+", " ")
    local at
    if hint and hint ~= "" then
        local tail = hint:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
        tail = tail:match("(%S+%s+%S+)$") or tail
        local found = tail ~= "" and text:find(tail .. " " .. name, 1, true)
        if found then at = found + #tail + 1 end
    end
    at = at or text:find(name, 1, true)
    if not at then return nil end
    local from = math.max(1, at - before_n)
    local to = math.min(#text, at + #name + after_n)
    local piece = text:sub(from, to)
    -- Whole words: drop the cut word at each end.
    if from > 1 then piece = piece:gsub("^%S*%s", "") end
    if to < #text then piece = piece:gsub("%s%S*$", "") end
    -- From the start of a sentence, to the end of one, when one is there.
    local s = piece:find("[%.!?][\"'”’»]*%s+%S")
    if s and s < at - from - 10 then piece = piece:sub(s):gsub("^[%.!?][\"'”’»]*%s+", "") end
    local last
    for q in piece:gmatch("[%.!?][\"'”’»]*()%s") do last = q end
    if last and last > #piece * 0.6 then piece = piece:sub(1, last - 1) end
    piece = piece:gsub("^%s+", ""):gsub("%s+$", "")
    -- Not cut inside a UTF-8 character.
    piece = piece:gsub("^[\128-\191]+", ""):gsub("[\192-\255][\128-\191]*$", function(c)
        local lead = c:byte(1)
        local need = lead >= 240 and 4 or lead >= 224 and 3 or 2
        return #c >= need and c or ""
    end)
    return piece ~= "" and piece or nil
end

function More.passages(ui, index, n, chapters)
    local XR = require("aleph_xr")
    local positions = readHits(ui, index)
    if #positions == 0 then return {} end
    local stats = More.stats(ui, index, chapters)
    -- The busiest chapter's mentions: their first and last number.
    local bf, bt
    if stats.busiest then
        for i, hit in ipairs(positions) do
            if More.chapterAt(stats.chapters, More.pageOf(ui, hit)) == stats.busiest then
                bf = bf or i
                bt = i
            end
        end
    end
    local texts = {}
    local function pageText(page)
        if texts[page] == nil then
            local t
            try(function()
                local doc = ui.document
                local to = math.min(page + 1, doc:getPageCount())
                t = doc:getTextFromXPointers(doc:getPageXPointer(page), doc:getPageXPointer(to), false)
            end)
            texts[page] = type(t) == "string" and t or false
        end
        return texts[page] or nil
    end
    local out = {}
    for _i, nth in ipairs(More.picks(#positions, n, bf, bt)) do
        local hit = positions[nth]
        local page = More.pageOf(ui, hit)
        local before, name = XR.snippet(ui, hit)
        local text = page and pageText(page)
        local piece = text and name and name ~= "" and More.cut(text, name, before) or nil
        if not piece and before then piece = (before .. (name or "") .. select(3, XR.snippet(ui, hit))):gsub("%s+", " ") end
        if piece then
            local c = More.chapterAt(stats.chapters, page)
            out[#out + 1] = { text = piece, chapter = c and stats.chapters[c].title or nil }
        end
    end
    return out
end

return More
