-- Aleph modification, 2026-11-14: Aleph's own X-Ray, the names of a book.
--[[--
Finds the proper names of a book from its text alone: no network, no
dictionary. A name is a word written with a capital where a sentence does
not ask for one, again and again, and hardly ever written without it:

    "... and then Elizabeth said ..."      a capital mid-sentence: evidence
    "Elizabeth said ..."                   a capital at a sentence's start: none
    "the house", "The house"               written lower-case elsewhere: not a name

Words that stand together with capitals ("Elizabeth Bennet", "Mr Darcy",
"San Francisco") are taken as one name, and the single words of it as other
ways to say it, when they belong to that name only.

    local Names = require("aleph_xr_names")
    local state = Names.new()
    Names.feed(state, text)            -- the book, a piece at a time
    local list = Names.finish(state)   -- { { name, aliases = {...}, count, person }, ... }

The list is sorted by how often a name was seen, the most often first, and
cut at Names.MAX. `person` is true when the name was seen after a title
(Mr, Mrs, Don, Dr...). What the names are (who is a person, what is a
place) is otherwise not known here: that is what the optional descriptions
(aleph_xr_ai.lua) add.

Works for scripts that have capitals: Latin (accents included), Greek,
Cyrillic. A book in a script without them gives an empty list.

Pure Lua, no KOReader: it runs in the background process that reads the
book (aleph_xr.lua), and in the tests.
]]

local Names = {}

-- How many names are kept.
Names.MAX = 120
-- A name must be seen mid-sentence at least this often.
Names.MIN_SEEN = 3

-- Titles before a name: they are not part of the name, and say it is a person's.
local TITLES = {}
for word in ([[Mr Mrs Ms Miss Mister Missus Dr Doctor Sir Lady Lord Madam Madame Mademoiselle Monsieur Mme Mlle
    Captain Capt Colonel Col General Major Sergeant Lieutenant Professor Prof Father Mother Brother Sister
    Uncle Aunt Auntie Cousin King Queen Prince Princess Duke Duchess Count Countess Baron Baroness Saint St
    Don Doña Dona Señor Señora Señorita Sr Sra Srta Tío Tía Tio Tia Padre Madre Fray Sor Capitán Coronel
    Herr Frau Fräulein Signor Signora Signorina Senhor Senhora]]):gmatch("%S+") do
    TITLES[word] = true
end

-- Words written with a capital mid-sentence that are not names of the book.
local STOP = {}
for word in ([[I I'm I'll I've I'd Im Ill Ive Id OK Okay Oh Ah Yes No God Lord Christmas Easter
    Monday Tuesday Wednesday Thursday Friday Saturday Sunday
    January February March April May June July August September October November December
    Chapter Part Book Volume Section Prologue Epilogue Contents Appendix
    Dios Navidad Capítulo Capitulo Parte Libro Prólogo Epílogo
    Chapitre Kapitel Capitolo Dieu Gott]]):gmatch("%S+") do
    STOP[word] = true
end

-- Small words that may stand inside a name between two capitals.
local PARTICLES = { de = true, del = true, la = true, las = true, los = true, da = true, di = true, du = true,
    van = true, von = true, der = true, den = true, of = true, the = true, le = true, y = true, e = true }

function Names.new()
    return {
        mid = {},      -- word -> times seen with a capital mid-sentence
        start = {},    -- word -> times seen with a capital at a sentence's start
        low = {},      -- word, lower-cased -> times seen without a capital
        runs = {},     -- "Word Word" -> { n = times, start = times at a sentence's start }
        titled = {},   -- word -> times seen right after a title
    }
end

-- Typographic punctuation made plain, so that what is left of the bytes
-- above 127 is letters.
local function plain(text)
    text = text:gsub("\226\128[\152\153]", "'")      -- ‘ ’
    text = text:gsub("\226\128[\156\157\158]", '"')  -- “ ” „
    text = text:gsub("\226\128[\144-\149]", " - ")   -- hyphens and dashes
    text = text:gsub("\226\128\166", "...")           -- …
    text = text:gsub("\194[\171\187]", '"')           -- « »
    text = text:gsub("\194[\160-\191]", " ")          -- no-break space, ¡ ¿ and other signs
    text = text:gsub("[\226-\239][\128-\191][\128-\191]", " ") -- any other three-byte sign or letter
    text = text:gsub("[\240-\247][\128-\191][\128-\191][\128-\191]", " ")
    return text
end
Names.plain = plain

-- The code point of a word's first letter and how many bytes it takes.
local function firstCode(word)
    local a = word:byte(1)
    if not a then return nil, 0 end
    if a < 128 then return a, 1 end
    local b = word:byte(2)
    if a >= 194 and a <= 223 and b then return (a - 192) * 64 + (b - 128), 2 end
    return nil, 1
end

-- The lower-case code point of a capital letter, or nil when cp is not one.
local function lowerOf(cp)
    if cp >= 65 and cp <= 90 then return cp + 32 end
    if cp >= 0xC0 and cp <= 0xDE and cp ~= 0xD7 then return cp + 32 end
    if cp >= 0x100 and cp <= 0x17F then
        local odd_capitals = (cp >= 0x139 and cp <= 0x148) or (cp >= 0x179 and cp <= 0x17E)
        if odd_capitals then
            if cp % 2 == 1 then return cp + 1 end
        elseif cp % 2 == 0 and cp ~= 0x138 then
            return cp + 1
        end
        return nil
    end
    if cp >= 0x391 and cp <= 0x3A9 and cp ~= 0x3A2 then return cp + 32 end
    if cp >= 0x410 and cp <= 0x42F then return cp + 32 end
    if cp >= 0x400 and cp <= 0x40F then return cp + 80 end
    return nil
end

local function utf8char(cp)
    if cp < 128 then return string.char(cp) end
    return string.char(192 + math.floor(cp / 64), 128 + cp % 64)
end

-- Whether a word begins with a capital, and the word with that capital
-- lowered (nil when it does not).
local function lowered(word)
    local cp, len = firstCode(word)
    if not cp then return nil end
    local lower = lowerOf(cp)
    if not lower then return nil end
    return utf8char(lower) .. word:sub(len + 1)
end
Names.lowered = lowered

-- A word in capitals throughout (a heading, a shout): no evidence either way.
local function allCapitals(word)
    return #word > 1 and not word:find("[a-z\128-\255]") and word:find("%u%u") ~= nil
end

-- A word as it is counted: the possessive and stray marks taken off.
local function clean(word)
    word = word:gsub("'[sS]$", ""):gsub("^[%-']+", ""):gsub("[%-']+$", "")
    return word
end

function Names.feed(state, text)
    text = plain(text)
    local mid, start, low, runs, titled = state.mid, state.start, state.low, state.runs, state.titled
    local prev_end = 1
    local run, run_start = nil, false
    local last_title = false
    local function closeRun()
        if run and #run >= 2 and #run <= 4 then
            local key = table.concat(run, " ")
            local r = runs[key]
            if not r then r = { n = 0, start = 0 }; runs[key] = r end
            r.n = r.n + 1
            if run_start then r.start = r.start + 1 end
        end
        run = nil
    end
    for s, raw, e in text:gmatch("()([%a\128-\255][%a\128-\255'%-]*)()") do
        local gap = text:sub(prev_end, s - 1)
        prev_end = e
        -- A sentence starts after its end marks, a quote, a dash of dialogue,
        -- a bracket or a new line; and so does a piece of text.
        local sentence_start = s == 1 or gap:find("[%.%!%?:;\"%(%)%[%]\n\r]") ~= nil or gap:find(" %- ") ~= nil
        local word = clean(raw)
        if word ~= "" then
            local lower = lowered(word)
            if lower and not allCapitals(word) then
                local bare = word:gsub("%.$", "")
                if TITLES[bare] then
                    -- A title: not counted, and the name after it is a person's.
                    closeRun()
                    last_title = true
                else
                    if sentence_start then start[word] = (start[word] or 0) + 1
                    else mid[word] = (mid[word] or 0) + 1 end
                    if last_title then
                        titled[word] = (titled[word] or 0) + 1
                        -- After a title a capital is a name wherever it stands.
                        if sentence_start then
                            start[word] = start[word] - 1
                            mid[word] = (mid[word] or 0) + 1
                        end
                    end
                    last_title = false
                    -- Words standing together with capitals, one space apart.
                    if run and gap == " " then
                        run[#run + 1] = word
                    else
                        closeRun()
                        run, run_start = { word }, sentence_start
                    end
                end
            else
                last_title = false
                if not allCapitals(word) then
                    low[word] = (low[word] or 0) + 1
                end
                closeRun()
            end
        end
    end
    closeRun()
end

local function isName(state, word)
    if STOP[word] or #word < 2 then return false end
    local seen = state.mid[word] or 0
    if seen < Names.MIN_SEEN then return false end
    local lower = lowered(word)
    local plain_uses = lower and state.low[lower] or 0
    -- Written without its capital more than a little: a common word.
    return plain_uses * 5 <= seen + (state.start[word] or 0)
end

function Names.finish(state, max)
    max = max or Names.MAX
    local names = {}
    for word in pairs(state.mid) do
        if isName(state, word) then names[word] = true end
    end
    -- Names of several words: every word a name, or a small word between two.
    local phrases = {}
    for key, r in pairs(state.runs) do
        local words = {}
        for w in key:gmatch("%S+") do words[#words + 1] = w end
        -- A first word that only opens sentences ("The Bennets") is not part of the name.
        if r.start == r.n and not names[words[1]] then table.remove(words, 1) end
        local ok = #words >= 2
        for _i, w in ipairs(words) do
            if not names[w] then ok = false; break end
        end
        if ok then
            local phrase = table.concat(words, " ")
            phrases[phrase] = (phrases[phrase] or 0) + r.n
        end
    end
    -- Which phrases each single name belongs to.
    local owners = {}
    local kept = {}
    for phrase, n in pairs(phrases) do
        if n >= 2 then
            kept[phrase] = n
            for w in phrase:gmatch("%S+") do
                owners[w] = owners[w] or {}
                table.insert(owners[w], phrase)
            end
        end
    end
    local function total(word) return (state.mid[word] or 0) + (state.start[word] or 0) end
    local entries, by_name = {}, {}
    for phrase, n in pairs(kept) do
        local entry = { name = phrase, aliases = {}, count = n, person = false }
        entries[#entries + 1] = entry
        by_name[phrase] = entry
    end
    for word in pairs(names) do
        local own = owners[word]
        if own and #own == 1 then
            -- Part of one name only: another way to say it.
            local entry = by_name[own[1]]
            table.insert(entry.aliases, word)
            entry.count = math.max(entry.count, total(word))
            if (state.titled[word] or 0) > 0 then entry.person = true end
        else
            -- A name by itself, or shared by several (a family's surname).
            local entry = { name = word, aliases = {}, count = total(word), person = (state.titled[word] or 0) > 0 }
            entries[#entries + 1] = entry
            by_name[word] = entry
        end
    end
    for _i, entry in ipairs(entries) do table.sort(entry.aliases) end
    table.sort(entries, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.name < b.name
    end)
    for i = #entries, max + 1, -1 do entries[i] = nil end
    return entries
end

-- A name as it is looked up: trimmed, its possessive off, one space between
-- words, its capitals lowered as far as this file knows how.
function Names.key(str)
    str = plain(tostring(str or "")):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    str = str:gsub("^[%p]+", ""):gsub("[%p]+$", ""):gsub("'[sS]$", "")
    local out = {}
    for word in str:gmatch("%S+") do
        out[#out + 1] = (lowered(word) or word):lower()
    end
    return table.concat(out, " ")
end

return Names
