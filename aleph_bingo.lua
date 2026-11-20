-- Aleph modification, 2026-11-18: Reading bingo.
--[[--
A bingo card of reading challenges: 12 books (4 x 3) or 24 (5 x 5 with a
free space in the middle), half genre challenges, a quarter geographical or
cultural, a quarter literary experimentation, drawn from the pools below
and mixed across the card. A full row or column (or, on the 5 x 5 card, a
diagonal) is a bingo.

A finished book fills a square (Bingo.onFinished, when a book is marked
Finished in Aleph or closes finished):
  1. Calibre says which: a #bingo column (a list like tags, or text split
     on commas) or tags "bingo: <square>", naming squares by their text (or
     part of it) or id. Read from the book's OPF or metadata.opf, as for
     collections (aleph_calibre_collections.lua), and from its tags.
  2. Else a square whose rule the book meets (its genres or tags, its
     format, its page count, its release year) is filled, the first such on
     the card, and a note says so.
  3. Else Aleph asks which open square it fills, if any (aleph_bingo_page).
A book fills one square; the card page changes any of it.

Settings: aleph.bingo = { size, started, cells = { { id, cat, text?, free?,
path?, title? } } }, cells in reading order.
]]

local _ = require("aleph_gettext")

local Bingo = {}

Bingo.CATS = {
    genre = function() return _.pgettext("Bingo", "Genre") end,
    place = function() return _.pgettext("Bingo", "Places and cultures") end,
    form = function() return _.pgettext("Bingo", "Literary experiment") end,
}

-- The pools. rule: tags (words in the book's genres or tags), comics (a
-- comic file or tag), pages_lt / pages_gt, year_lt. No rule: asked.
-- N_ marks a text for translation where it is written (the extractor reads
-- it); _ translates it where it is shown, so the English is kept too (Calibre
-- may name a square in English).
local function N_(s) return s end
local function P(id, en, rule) return { id = id, en = en, text = function() return _(en) end, rule = rule } end
Bingo.POOLS = {
    genre = {
        P("sf", N_("A literary science fiction novel"), { tags = { "science fiction", "sci-fi", "scifi", "sf" } }),
        P("fantasy", N_("A fantasy novel"), { tags = { "fantasy" } }),
        P("gothic", N_("A Gothic novel written before 1900"), { tags = { "gothic" }, year_lt = 1900 }),
        P("horror", N_("A literary horror novel"), { tags = { "horror" } }),
        P("mystery", N_("A mystery with literary ambitions"), { tags = { "mystery", "crime", "detective" } }),
        P("short", N_("A collection of short stories"), { tags = { "short stories", "short story", "stories" } }),
        P("historical", N_("A historical novel"), { tags = { "historical fiction", "historical" } }),
        P("magical", N_("A magical realism novel"), { tags = { "magical realism" } }),
        P("romance", N_("A love story"), { tags = { "romance" } }),
        P("poetry", N_("A book of poetry"), { tags = { "poetry", "poems" } }),
        P("graphic", N_("A graphic novel or memoir"), { comics = true, tags = { "graphic novel", "graphic novels", "comics", "manga" } }),
        P("memoir", N_("A memoir"), { tags = { "memoir", "memoirs", "autobiography" } }),
        P("dystopia", N_("A dystopian novel"), { tags = { "dystopia", "dystopian" } }),
        P("society", N_("A nonfiction book about society"), { tags = { "sociology", "social science", "society" } }),
        P("woman_classic", N_("A classic by a woman writer")),
        P("thriller", N_("A thriller"), { tags = { "thriller", "suspense" } }),
        P("western", N_("A western"), { tags = { "western", "westerns" } }),
        P("satire", N_("A comic or satirical novel"), { tags = { "satire", "humor", "humour", "comedy" } }),
        P("essays", N_("A book of essays"), { tags = { "essays", "essay" } }),
        P("biography", N_("A biography"), { tags = { "biography" } }),
        P("myth", N_("A retelling of a myth"), { tags = { "mythology", "myth", "retelling" } }),
        P("fairy", N_("Fairy tales or folklore"), { tags = { "fairy tales", "fairy tale", "folklore" } }),
        P("drama", N_("A play"), { tags = { "drama", "plays", "theatre", "theater" } }),
        P("cozy", N_("A cosy mystery"), { tags = { "cozy mystery", "cosy mystery", "cozy", "cosy" } }),
        P("adventure", N_("An adventure story"), { tags = { "adventure" } }),
        P("war", N_("A novel about war"), { tags = { "war", "war fiction", "military fiction" } }),
        P("coming", N_("A coming-of-age novel"), { tags = { "coming of age", "coming-of-age", "bildungsroman" } }),
        P("science", N_("A popular science book"), { tags = { "popular science", "science nonfiction" } }),
        P("philosophy", N_("A book of philosophy"), { tags = { "philosophy" } }),
        P("travel", N_("Travel writing"), { tags = { "travel", "travel writing" } }),
        P("children", N_("A children's classic"), { tags = { "children's", "children", "juvenile fiction" } }),
        P("ya", N_("A young adult novel"), { tags = { "young adult", "ya" } }),
        P("old", N_("A book published before 1800"), { year_lt = 1800 }),
        P("climate", N_("Climate fiction"), { tags = { "climate fiction", "cli-fi" } }),
        P("working", N_("A novel about the working class")),
        P("queer", N_("A queer literary classic"), { tags = { "lgbt", "lgbtq", "queer" } }),
    },
    place = {
        P("africa", N_("A novel set in Africa"), { tags = { "africa", "african", "african literature" } }),
        P("asian_tr", N_("A book translated from an Asian language")),
        P("arabic", N_("A novel originally written in Arabic"), { tags = { "arabic literature", "arabic" } }),
        P("indigenous", N_("A book by an Indigenous author"), { tags = { "indigenous", "native american", "first nations" } }),
        P("unfamiliar", N_("A book from a country you have never read from")),
        P("memoir_culture", N_("A memoir from a different culture")),
        P("latin", N_("A book from Latin America"), { tags = { "latin america", "latin american", "south america" } }),
        P("nordic", N_("A Nordic book"), { tags = { "nordic", "scandinavian" } }),
        P("russian", N_("A Russian classic"), { tags = { "russian literature", "russian" } }),
        P("caribbean", N_("A book from the Caribbean"), { tags = { "caribbean" } }),
        P("middle_east", N_("A book set in the Middle East"), { tags = { "middle east", "middle eastern" } }),
        P("japan", N_("A Japanese novel"), { tags = { "japanese literature", "japanese", "japan" } }),
        P("india", N_("A book from the Indian subcontinent"), { tags = { "indian literature", "india", "pakistan", "bangladesh", "sri lanka" } }),
        P("ireland", N_("An Irish novel"), { tags = { "irish literature", "irish", "ireland" } }),
        P("prize_tr", N_("A contemporary prizewinning translation")),
        P("eastern_europe", N_("A book from Eastern Europe"), { tags = { "eastern europe", "polish", "czech", "hungarian", "romanian", "ukrainian" } }),
        P("oceania", N_("A book from Australia or the Pacific"), { tags = { "australia", "australian", "new zealand", "pacific" } }),
        P("other_lang", N_("A book translated from a language you don't speak")),
        P("diaspora", N_("A book by a diaspora or immigrant writer"), { tags = { "diaspora", "immigration", "immigrant" } }),
        P("dream_place", N_("A book set somewhere you would like to visit")),
        P("china", N_("A Chinese novel"), { tags = { "chinese literature", "chinese", "china" } }),
        P("korea", N_("A Korean novel"), { tags = { "korean literature", "korean", "korea" } }),
        P("island", N_("A book set on an island"), { tags = { "island" } }),
        P("home_place", N_("A book set where you live")),
    },
    form = {
        P("unreliable", N_("A book with an unreliable narrator"), { tags = { "unreliable narrator" } }),
        P("second", N_("A book told in the second person"), { tags = { "second person" } }),
        P("letters", N_("A novel told in letters"), { tags = { "epistolary", "epistolary fiction" } }),
        P("verse_novel", N_("A novel in verse"), { tags = { "novel in verse", "verse novel" } }),
        P("nonlinear", N_("A story told out of order"), { tags = { "nonlinear", "non-linear" } }),
        P("narrators", N_("A book with several narrators"), { tags = { "multiple narrators", "multiple pov" } }),
        P("short_book", N_("A book under 150 pages"), { pages_lt = 150 }),
        P("long_book", N_("A book over 700 pages"), { pages_gt = 700 }),
        P("experimental", N_("An experimental literary novel"), { tags = { "experimental", "experimental fiction" } }),
        P("meta", N_("A novel about writing a novel"), { tags = { "metafiction" } }),
        P("stream", N_("A stream-of-consciousness novel"), { tags = { "stream of consciousness", "modernism", "modernist" } }),
        P("footnotes", N_("A book with footnotes that matter")),
        P("novella", N_("A novella"), { tags = { "novella", "novellas" } }),
        P("one_day", N_("A story that takes place in one day")),
        P("anthology", N_("An anthology by many writers"), { tags = { "anthology", "anthologies" } }),
        P("illustrated", N_("An illustrated book"), { tags = { "illustrated" } }),
        P("nameless", N_("A book with a nameless narrator")),
        P("frame", N_("A story within a story"), { tags = { "frame story" } }),
        P("fragments", N_("A book written in fragments"), { tags = { "fragmentary", "fragments" } }),
        P("debut", N_("A debut novel"), { tags = { "debut", "debut novel" } }),
        P("small_press", N_("A book from a small press")),
        P("autofiction", N_("A work of autofiction"), { tags = { "autofiction" } }),
        P("hybrid", N_("A book that mixes genres or forms"), { tags = { "hybrid", "genre-bending" } }),
        P("oulipo", N_("A novel written under a constraint"), { tags = { "oulipo", "constrained writing" } }),
    },
}

local BY_ID = {}
for cat, pool in pairs(Bingo.POOLS) do
    for _i, p in ipairs(pool) do p.cat = cat; BY_ID[p.id] = p end
end
Bingo.byId = BY_ID

-- --------------------------------------------------------------- state
local function prefs() return require("aleph_prefs") end

function Bingo.card()
    local c = prefs().get().bingo
    if type(c) ~= "table" or type(c.cells) ~= "table" or #c.cells == 0 then return nil end
    return c
end

function Bingo.save(card)
    prefs().set("bingo", card)
end

-- The shape: columns and rows, and the free cell's index (or nil).
function Bingo.shape(size)
    if size == 12 then return 4, 3, nil end
    return 5, 5, 13
end

-- A cell's text, as shown.
function Bingo.text(cell)
    if not cell then return "" end
    if cell.free then return _("Free space") end
    if type(cell.text) == "string" and cell.text ~= "" then return cell.text end
    local p = BY_ID[cell.id]
    return p and p.text() or ""
end

-- ---------------------------------------------------------------- cards
local function shuffle(list, rand)
    for i = #list, 2, -1 do
        local j = rand(i)
        list[i], list[j] = list[j], list[i]
    end
    return list
end

local function draw(cat, n, used, rand)
    local pool = {}
    for _i, p in ipairs(Bingo.POOLS[cat]) do if not used[p.id] then pool[#pool + 1] = p end end
    shuffle(pool, rand)
    local out = {}
    for i = 1, math.min(n, #pool) do out[i] = pool[i]; used[pool[i].id] = true end
    return out
end

-- A new card of `size` (12 or 24): half genre, a quarter each of the
-- others, mixed so that no row is all of one kind. rand(n): 1..n.
function Bingo.newCard(size, rand)
    rand = rand or function(n) return math.random(n) end
    size = size == 12 and 12 or 24
    local cols, rows, free = Bingo.shape(size)
    local used = {}
    local picks = {}
    for _i, p in ipairs(draw("genre", size / 2, used, rand)) do picks[#picks + 1] = p end
    for _i, p in ipairs(draw("place", size / 4, used, rand)) do picks[#picks + 1] = p end
    for _i, p in ipairs(draw("form", size / 4, used, rand)) do picks[#picks + 1] = p end
    local order
    for _try = 1, 60 do
        order = {}
        for i, p in ipairs(picks) do order[i] = p end
        shuffle(order, rand)
        -- No row of one kind only.
        local ok = true
        local k = 0
        for r = 1, rows do
            local kinds, n = {}, 0
            for c = 1, cols do
                local index = (r - 1) * cols + c
                if index ~= free then
                    k = k + 1
                    local cat = order[k].cat
                    if not kinds[cat] then kinds[cat] = true; n = n + 1 end
                end
            end
            if n < 2 then ok = false end
        end
        if ok then break end
    end
    local cells, k = {}, 0
    for index = 1, cols * rows do
        if index == free then
            cells[index] = { free = true }
        else
            k = k + 1
            cells[index] = { id = order[k].id, cat = order[k].cat }
        end
    end
    return { size = size, started = os.date("%Y-%m-%d"), cells = cells }
end

-- Another challenge of the same kind for an empty cell.
function Bingo.redraw(card, index, rand)
    rand = rand or function(n) return math.random(n) end
    local cell = card.cells[index]
    if not cell or cell.free or cell.path then return false end
    local used = {}
    for _i, c in ipairs(card.cells) do if c.id then used[c.id] = true end end
    local cat = cell.cat or (BY_ID[cell.id] and BY_ID[cell.id].cat) or "genre"
    local pick = draw(cat, 1, used, rand)[1]
    if not pick then return false end
    card.cells[index] = { id = pick.id, cat = cat }
    return true
end

-- --------------------------------------------------------------- lines
-- Every line of the card: rows, columns and, 5 x 5, the diagonals.
function Bingo.lines(size)
    local cols, rows = Bingo.shape(size)
    local lines = {}
    for r = 1, rows do
        local l = {}
        for c = 1, cols do l[#l + 1] = (r - 1) * cols + c end
        lines[#lines + 1] = l
    end
    for c = 1, cols do
        local l = {}
        for r = 1, rows do l[#l + 1] = (r - 1) * cols + c end
        lines[#lines + 1] = l
    end
    if cols == rows then
        local a, b = {}, {}
        for i = 1, cols do a[#a + 1] = (i - 1) * cols + i; b[#b + 1] = (i - 1) * cols + (cols - i + 1) end
        lines[#lines + 1] = a
        lines[#lines + 1] = b
    end
    return lines
end

local function filled(cell) return cell and (cell.free or cell.path) and true or false end

-- { read, total, bingos, in_line = { [index] = true } }.
function Bingo.progress(card)
    local read, total = 0, 0
    for _i, cell in ipairs(card.cells) do
        if not cell.free then
            total = total + 1
            if cell.path then read = read + 1 end
        end
    end
    local bingos, in_line = 0, {}
    for _i, line in ipairs(Bingo.lines(card.size)) do
        local all = true
        for _j, index in ipairs(line) do if not filled(card.cells[index]) then all = false; break end end
        if all then
            bingos = bingos + 1
            for _j, index in ipairs(line) do in_line[index] = true end
        end
    end
    return { read = read, total = total, bingos = bingos, in_line = in_line }
end

-- ------------------------------------------------------------- matching
local function norm(s)
    s = tostring(s or ""):lower():gsub("[%p]", " "):gsub("%s+", " ")
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- The book's own words: its genres and tags, lowercase.
local function bookTags(book)
    local tags = {}
    for _i, g in ipairs(type(book.genres) == "table" and book.genres or {}) do tags[#tags + 1] = norm(g) end
    local kw = book.props and book.props.keywords
    if type(kw) == "string" then
        for s in kw:gmatch("[^\n;,]+") do tags[#tags + 1] = norm(s) end
    end
    return tags
end

local function hasWord(tags, word)
    word = norm(word)
    for _i, t in ipairs(tags) do
        if t == word then return true end
        local pattern = "%f[%w]" .. word:gsub("[%-%.%+%*%?%^%$%(%)%[%]%%]", "%%%0") .. "%f[%W]"
        if t:find(pattern) then return true end
    end
    return false
end

-- Whether `book` meets a pool challenge's rule.
function Bingo.meets(book, p)
    local rule = p and p.rule
    if not rule then return false end
    local pages = tonumber(book.pages) or tonumber(book.koreader_pages)
    local year = tonumber(book.year)
    if rule.year_lt and not (year and year < rule.year_lt) then return false end
    if rule.pages_lt then return pages ~= nil and pages < rule.pages_lt end
    if rule.pages_gt then return pages ~= nil and pages > rule.pages_gt end
    local tags = bookTags(book)
    if rule.comics and (book.comic or tostring(book.format or ""):match("^CB[ZRT7]$")) then return true end
    if rule.tags then
        for _i, w in ipairs(rule.tags) do if hasWord(tags, w) then return true end end
        return false
    end
    return rule.year_lt ~= nil
end

-- The squares Calibre names for `book`: its "bingo: ..." tags and its
-- #bingo column (read from the file, as collections are).
function Bingo.calibreNames(book)
    local names = {}
    local kw = book.props and book.props.keywords
    local list = {}
    if type(kw) == "table" then list = kw
    elseif type(kw) == "string" then for s in kw:gmatch("[^\n;,]+") do list[#list + 1] = s end end
    for _i, s in ipairs(list) do
        local name = tostring(s):match("^%s*[Bb][Ii][Nn][Gg][Oo]%s*:%s*(.-)%s*$")
        if name and name ~= "" then names[#names + 1] = name end
    end
    if type(book.path) == "string" then
        pcall(function()
            local CC = require("aleph_calibre_collections")
            local got = CC.read(book.path, function(key) return tostring(key):lower():gsub("^#", "") == "bingo" end, "bingo")
            for _i, n in ipairs(type(got) == "table" and got or {}) do names[#names + 1] = n end
        end)
    end
    return names
end

-- The open cell a name stands for: its id, its text, or a part of either.
function Bingo.cellFor(card, name)
    local n = norm(name)
    if n == "" then return nil end
    local best
    for index, cell in ipairs(card.cells) do
        if not cell.free and not cell.path then
            local t = norm(Bingo.text(cell))
            local english = cell.id and BY_ID[cell.id] and norm(Bingo.englishText(cell.id)) or nil
            if n == norm(cell.id or "") or n == t or n == english then return index end
            if not best and (t:find(n, 1, true) or (english and english:find(n, 1, true)) or (#t > 0 and n:find(t, 1, true))) then
                best = index
            end
        end
    end
    return best
end

-- A pool challenge's English text, for names written in Calibre in English.
function Bingo.englishText(id)
    local p = BY_ID[id]
    return p and p.en or ""
end

function Bingo.onCard(card, path)
    for index, cell in ipairs(card.cells) do if cell.path == path then return index end end
    return nil
end

function Bingo.fill(card, index, book)
    local cell = card.cells[index]
    if not cell or cell.free then return false end
    cell.path, cell.title, cell.on = book.path, book.title, os.date("%Y-%m-%d")
    return true
end

function Bingo.clear(card, index)
    local cell = card.cells[index]
    if not cell then return end
    cell.path, cell.title, cell.on = nil, nil, nil
end

-- What a finished book does to the card: { index, how = "calibre" |
-- "rule" } when it fills a square, { ask = true } when Aleph should ask,
-- or nil (no card, the card is full, the book is on it already).
function Bingo.match(card, book)
    if not card or not book or not book.path or Bingo.onCard(card, book.path) then return nil end
    local open = false
    for _i, cell in ipairs(card.cells) do if not cell.free and not cell.path then open = true; break end end
    if not open then return nil end
    for _i, name in ipairs(Bingo.calibreNames(book)) do
        local index = Bingo.cellFor(card, name)
        if index then return { index = index, how = "calibre" } end
    end
    for index, cell in ipairs(card.cells) do
        if not cell.free and not cell.path and Bingo.meets(book, BY_ID[cell.id]) then
            return { index = index, how = "rule" }
        end
    end
    return { ask = true }
end

-- A book has just been finished: fill its square, or ask.
-- opts.no_ask: fill by Calibre or a rule only (many books at once).
function Bingo.onFinished(book, opts)
    local card = Bingo.card()
    local m = Bingo.match(card, book)
    if not m or (m.ask and opts and opts.no_ask) then return end
    local UIManager = require("ui/uimanager")
    if m.index then
        Bingo.fill(card, m.index, book)
        Bingo.save(card)
        local T = require("ffi/util").template
        local p = Bingo.progress(card)
        UIManager:scheduleIn(1, function()
            pcall(function()
                local msg = T(_("Reading bingo: %1"), Bingo.text(card.cells[m.index]))
                if p.bingos > 0 and p.in_line[m.index] then msg = _("Bingo!") .. " " .. msg end
                require("aleph_toast").show(msg, { icon = "grid-3x3", timeout = 4 })
            end)
        end)
        return
    end
    -- After the book has closed and Home is drawn.
    UIManager:scheduleIn(1.5, function()
        pcall(function() require("aleph_bingo_page").ask(book) end)
    end)
end

return Bingo
