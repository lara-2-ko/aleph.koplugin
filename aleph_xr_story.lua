-- Aleph modification, 2026-11-14: X-Ray's timeline, the story so far.
--[[--
Beside the names of a book (aleph_xr.lua), what has happened in it: a few
sentences for each chapter read, a short "story so far", and, for a book in
a series, what happened in the book before. For coming back to a book after
a while, or to a series after a year.

All of it is written by a language model, with the reader's own key
(Settings > X-Ray, as for the names' descriptions), and only when asked:
"Update the story" in the X-Ray sheet, or the question Aleph asks when a
book is opened again after a break (Settings > X-Ray > Offer a recap).

What is sent, and this is more than for the names: the TEXT OF THE CHAPTERS
READ and not summarised yet (the chapter being read, up to the page shown),
with the book's title and author. Never a page not read. A long book goes
in several questions of about 110,000 characters each; each chapter is sent
once, its summary kept, so coming back later sends only what was read
since. The story so far is then written from the summaries, not from the
text again.

The book before: when it has a story of its own on this device (X-Ray was
used on it), its chapter summaries are what the model is given. When it has
none, the model is asked what it knows of that book by its title, and the
answer is marked as coming from the model's own knowledge: it can be wrong.

    Story.chapters(ui)          the book's chapters, from its contents
    Story.read(ui)              what is kept: { chapters, recap, previous }
    Story.pending(ui)           the chapters read and not summarised yet
    Story.previous(ui)          the book before in the series, or nil
    Story.update(ui, o, done)   asks; o.previous also asks for the book before
    Story.busy(), Story.progress()
    Story.away(ui)              days since the book was last read
    Story.offer(ui)             the question after a break

Kept in the book's settings folder as aleph_xray_story.lua. The reading of
the chapters and the questions run in a background process (where the
device allows one), so reading goes on meanwhile.
]]

local Prefs = require("aleph_prefs")
local try = require("aleph_try").call

local Story = {}

Story.VERSION = 1
-- Chapter text sent in one question, in characters.
Story.BATCH = 110000
-- Questions in one update, at most (a long book read far in one go).
Story.MAX_BATCHES = 10
-- A chapter shorter than this is a title page: nothing to summarise.
Story.MIN_CHAPTER = 400
-- A table of contents finer than this is cut to its top level.
local MAX_CHAPTERS = 150

local function oneLine(str)
    return (tostring(str or ""):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))
end

-- --------------------------------------------------------------- chapters
-- The chapters, from a table of contents: { { i, title, page, last }, ... }
-- with `last` the last page of each. toc: { { page, title, depth }, ... };
-- without one, the book is cut into pieces of 20 pages.
function Story.chaptersFrom(toc, pages)
    local entries = {}
    local top = math.huge
    for _i, item in ipairs(toc or {}) do
        if type(item) == "table" and tonumber(item.page) then
            entries[#entries + 1] = { page = tonumber(item.page), title = oneLine(item.title), depth = tonumber(item.depth) or 1 }
            top = math.min(top, tonumber(item.depth) or 1)
        end
    end
    if #entries > MAX_CHAPTERS then
        local only = {}
        for _i, e in ipairs(entries) do
            if e.depth == top then only[#only + 1] = e end
        end
        entries = only
    end
    table.sort(entries, function(a, b)
        if a.page ~= b.page then return a.page < b.page end
        return a.depth < b.depth
    end)
    local out = {}
    for _i, e in ipairs(entries) do
        local prev = out[#out]
        -- Two entries on one page: the first (the outer one) names it.
        if e.page >= 1 and e.page <= pages and not (prev and prev.page == e.page) then
            out[#out + 1] = { title = e.title, page = e.page }
        end
    end
    if #out < 2 then
        out = {}
        local step = 20
        for page = 1, pages, step do
            out[#out + 1] = { title = string.format("%d – %d", page, math.min(page + step - 1, pages)), page = page, pieces = true }
        end
    end
    for i, c in ipairs(out) do
        c.i = i
        c.last = out[i + 1] and (out[i + 1].page - 1) or pages
    end
    return out
end

function Story.chapters(ui)
    local toc
    try(function()
        if ui.toc and ui.toc.fillToc then ui.toc:fillToc() end
        toc = ui.toc and ui.toc.toc
    end)
    local pages = 1
    try(function() pages = ui.document:getPageCount() end)
    return Story.chaptersFrom(toc, pages)
end

-- ------------------------------------------------------------------ files
local function state(ui)
    local st = ui._aleph_xr
    if not st then
        st = {}
        ui._aleph_xr = st
    end
    return st
end

local function path(ui)
    local dir = require("aleph_xr").dir(ui)
    return dir and (dir .. "/aleph_xray_story.lua") or nil
end

local readFile = require("aleph_file").read

-- What is kept for the open book: { chapters = { [i] = { title, summary,
-- done } }, recap = { text, page, percent, at }, previous = { title, text,
-- at, known } }. Always a table.
function Story.read(ui)
    local st = state(ui)
    if not st.story then
        local data = readFile(path(ui)) or {}
        local chapters = {}
        for _i, c in ipairs(type(data.list) == "table" and data.list or {}) do
            if type(c) == "table" and tonumber(c.i) then chapters[tonumber(c.i)] = c end
        end
        st.story = { chapters = chapters, recap = type(data.recap) == "table" and data.recap or nil,
            previous = type(data.previous) == "table" and data.previous or nil }
    end
    return st.story
end

function Story.save(ui)
    local story = Story.read(ui)
    local file = path(ui)
    if not file then return false end
    local list = {}
    for i, c in pairs(story.chapters) do
        list[#list + 1] = { i = i, title = c.title, summary = c.summary, done = c.done and true or false, upto = tonumber(c.upto) }
    end
    table.sort(list, function(a, b) return a.i < b.i end)
    try(function() require("util").makePath(require("aleph_xr").dir(ui)) end)
    return require("aleph_xr").writeFile(file, { version = Story.VERSION, list = list, recap = story.recap, previous = story.previous })
end

-- --------------------------------------------------------- what to ask for
local function currentPage(ui)
    local page = 1
    try(function() page = ui:getCurrentPage() end)
    return page
end

-- The chapters read and not summarised yet: { { i, title, from, to,
-- partial }, ... } with `to` the page after the last one to send. A chapter
-- being read is sent up to the page shown, and again once it is finished.
function Story.pendingFrom(chapters, kept, page)
    local out = {}
    for _i, c in ipairs(chapters) do
        if c.page > page then break end
        local finished = c.last <= page
        local have = kept[c.i]
        -- A chapter being read is asked about again only once more of it has been read.
        local same = have and not have.done and not finished and (tonumber(have.upto) or 0) >= page
        if not (have and have.done) and not same and (finished or page > c.page or c.last == c.page) then
            out[#out + 1] = { i = c.i, title = c.title, from = c.page, to = math.min(c.last, page) + 1, partial = not finished }
        end
    end
    return out
end

function Story.pending(ui)
    return Story.pendingFrom(Story.chapters(ui), Story.read(ui).chapters, currentPage(ui))
end

-- The chapter summaries kept, in the book's order, up to the page shown:
-- { { i, title, summary }, ... } (chapters with nothing to say left out).
function Story.told(ui)
    local story = Story.read(ui)
    local out = {}
    for _i, c in ipairs(Story.chapters(ui)) do
        local have = story.chapters[c.i]
        if have and have.summary and have.summary ~= "" then
            out[#out + 1] = { i = c.i, title = c.title, page = c.page, summary = have.summary, done = have.done }
        end
    end
    return out
end

-- The book before this one in its series: { series, index, title, path,
-- summaries }, or nil when this book is in no series or is its first.
-- title and path when the book is in Aleph's library; summaries when it
-- has a story of its own on this device.
function Story.previous(ui)
    local props = ui.doc_props or {}
    local series = type(props.series) == "string" and oneLine(props.series) or ""
    local index = tonumber(props.series_index)
    -- "Series #3" in the series field itself.
    if not index and series ~= "" then
        local name, num = series:match("^(.-)%s*#%s*([%d%.]+)$")
        if name then series, index = name, tonumber(num) end
    end
    if series == "" or not index or index <= 1 then return nil end
    local prev = { series = series, index = index }
    try(function()
        local Local = require("aleph_local")
        local lib = Local.shared and Local.shared() or nil
        if not lib then return end
        local best
        for _i, book in ipairs(lib.books or {}) do
            local n = tonumber(book.seriesIndex)
            if type(book.series) == "string" and book.series:lower() == series:lower() and n and n < index
                    and (not best or n > tonumber(best.seriesIndex)) then
                best = book
            end
        end
        if best then
            prev.title, prev.path, prev.number = best.title, best.path, tonumber(best.seriesIndex)
            local dir = require("docsettings"):getSidecarDir(best.path)
            local data = readFile(dir .. "/aleph_xray_story.lua")
            local list = {}
            for _i, c in ipairs(data and type(data.list) == "table" and data.list or {}) do
                if type(c.summary) == "string" and c.summary ~= "" then list[#list + 1] = { title = c.title, summary = c.summary } end
            end
            if #list >= 3 then prev.summaries = list end
        end
    end)
    return prev
end

-- ------------------------------------------------------------ the questions
local function bookLine(book)
    return string.format('Book: "%s"%s.', oneLine(book.title ~= "" and book.title or "untitled"),
        book.author and book.author ~= "" and (" by " .. oneLine(book.author)) or "")
end

-- items: { { i, title, text, partial }, ... }
function Story.chapterPrompt(book, items, recap)
    local lines = {
        "You are helping a reader remember a book they are in the middle of reading.",
        bookLine(book),
        "Below is the text of chapters the reader has just read" .. (items[#items].partial and " (the last one only in part)" or "") .. ".",
        "For each chapter, say what happens in it in 2 to 4 sentences: the events, who is involved, and anything left open."
            .. " Use only the text given. Do not add anything from later in the book, and do not judge or comment.",
        "Answer with a JSON array only, one object per chapter: [{\"c\": <the chapter's number as given>, \"summary\": \"<what happens>\"}]."
            .. " Write in the language of the text.",
    }
    if recap and recap ~= "" then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "For context, the story before these chapters: " .. oneLine(recap)
    end
    for _i, item in ipairs(items) do
        lines[#lines + 1] = ""
        lines[#lines + 1] = string.format('=== Chapter number %d: "%s" ===', item.i, oneLine(item.title))
        lines[#lines + 1] = item.text
    end
    return table.concat(lines, "\n")
end

-- told: { { title, summary }, ... }
function Story.recapPrompt(book, told, percent)
    local lines = {
        "You are helping a reader come back to a book after a break.",
        bookLine(book) .. string.format(" The reader is %d%% of the way through it.", percent),
        "Below is what happened in each chapter read so far.",
        "Write the story so far in at most 200 words: the main thread, where things stand now, and what is still open."
            .. " Use only what is below; reveal nothing beyond it.",
        "Answer with a JSON object only: {\"recap\": \"<the story so far>\"}. Write in the language of the summaries.",
        "",
    }
    for _i, c in ipairs(told) do
        lines[#lines + 1] = "- " .. oneLine(c.title) .. ": " .. oneLine(c.summary)
    end
    return table.concat(lines, "\n")
end

function Story.previousPrompt(book, prev)
    local named = prev.title and ('"' .. oneLine(prev.title) .. '"') or string.format("book %s of the series", tostring(prev.index - 1))
    local lines = {
        "You are helping a reader continue a series of books.",
        bookLine(book) .. string.format(' It is book %s of the series "%s". The book before it is %s.', tostring(prev.index), prev.series, named),
    }
    if prev.summaries then
        lines[#lines + 1] = "Below is what happened in each chapter of that earlier book."
        lines[#lines + 1] = "Write what happened in it in at most 250 words, its ending included, so the reader can go on with the next book. Use only what is below."
    else
        lines[#lines + 1] = "Say what happened in that earlier book in at most 250 words, its ending included, so the reader can go on with the next book."
            .. " If you do not know that book well enough to be sure, answer with an empty recap."
    end
    lines[#lines + 1] = "Answer with a JSON object only: {\"recap\": \"<what happened>\"}. Write in the language of the book's title."
    if prev.summaries then
        lines[#lines + 1] = ""
        for _i, c in ipairs(prev.summaries) do
            lines[#lines + 1] = "- " .. oneLine(c.title) .. ": " .. oneLine(c.summary)
        end
    end
    return table.concat(lines, "\n")
end

-- The chapter summaries in an answer: { [chapter number] = summary }.
function Story.parseChapters(text)
    local out, n = {}, 0
    local from, to = text:find("%[.*%]")
    if not from then return out, 0 end
    local ok, list = pcall(function() return require("json").decode(text:sub(from, to)) end)
    if not ok or type(list) ~= "table" then return out, 0 end
    for _i, item in ipairs(list) do
        local c = type(item) == "table" and tonumber(item.c) or nil
        if c and type(item.summary) == "string" and oneLine(item.summary) ~= "" and not out[c] then
            out[c] = oneLine(item.summary)
            n = n + 1
        end
    end
    return out, n
end

-- The text under `key` in an answer that is a JSON object; the answer
-- itself when it is plain words after all.
function Story.parseText(text, key)
    local from, to = text:find("%b{}")
    if from then
        local ok, obj = pcall(function() return require("json").decode(text:sub(from, to)) end)
        if ok and type(obj) == "table" then
            return type(obj[key]) == "string" and oneLine(obj[key]) or ""
        end
    end
    if text:find("^%s*[%[{]") then return "" end
    return oneLine(text)
end

-- Chapters put together into questions of at most `limit` characters of
-- text each: { { item, item... }, ... }. A chapter longer than the limit
-- goes alone, its text cut (its beginning and its end kept).
function Story.batches(items, limit)
    limit = limit or Story.BATCH
    local out, current, size = {}, {}, 0
    for _i, item in ipairs(items) do
        if #item.text > limit then
            local head = math.floor(limit * 0.6)
            item.text = item.text:sub(1, head):gsub("[\128-\191]*$", "") .. "\n[...]\n" .. item.text:sub(-(limit - head)):gsub("^[\128-\191]*", "")
        end
        if size + #item.text > limit and #current > 0 then
            out[#out + 1] = current
            current, size = {}, 0
        end
        current[#current + 1] = item
        size = size + #item.text
    end
    if #current > 0 then out[#out + 1] = current end
    return out
end

-- ------------------------------------------------------------------- work
-- Runs in the background process (or here, where there can be none): reads
-- the chapters, asks, and writes what came back to `out`.
--   plan: { book, percent, pending, told, recap, previous }
--   ask(prompt) -> text, or nil and why
function Story.work(doc, plan, ask, out, progress)
    local XR = require("aleph_xr")
    local result = { chapters = {} }
    local function note(i, n)
        if not progress then return end
        local f = io.open(progress, "w")
        if f then f:write(i, "/", n); f:close() end
    end
    local items = {}
    for _i, c in ipairs(plan.pending or {}) do
        local ok, text = pcall(function()
            local pages = doc:getPageCount()
            return doc:getTextFromXPointers(doc:getPageXPointer(c.from), doc:getPageXPointer(math.min(c.to, pages)), false)
        end)
        text = ok and type(text) == "string" and text:gsub("[ \t]+", " "):gsub("\n%s*\n+", "\n") or ""
        if #text < Story.MIN_CHAPTER then
            -- A title page, a dedication: nothing to tell, and not asked again.
            if not c.partial then result.chapters[#result.chapters + 1] = { i = c.i, summary = "", partial = false } end
        else
            items[#items + 1] = { i = c.i, title = c.title, text = text, partial = c.partial }
        end
    end
    local batches = Story.batches(items)
    local steps = math.min(#batches, Story.MAX_BATCHES) + 1 + (plan.previous and 1 or 0)
    local told = {}
    for _i, c in ipairs(plan.told or {}) do told[#told + 1] = { i = c.i, title = c.title, summary = c.summary } end
    local recap = plan.recap
    for b = 1, math.min(#batches, Story.MAX_BATCHES) do
        note(b, steps)
        local text, why = ask(Story.chapterPrompt(plan.book, batches[b], recap))
        if not text then result.error = why; break end
        local found, n = Story.parseChapters(text)
        if n == 0 then result.error = "no summaries in the answer"; break end
        for _i, item in ipairs(batches[b]) do
            if found[item.i] then
                result.chapters[#result.chapters + 1] = { i = item.i, summary = found[item.i], partial = item.partial }
                told[#told + 1] = { i = item.i, title = item.title, summary = found[item.i] }
            end
        end
    end
    if #batches > Story.MAX_BATCHES then result.more = true end
    table.sort(told, function(a, b) return a.i < b.i end)
    -- The story so far, from the summaries (the text is not sent again).
    if not result.error and #told > 0 and plan.want_recap ~= false then
        note(steps - (plan.previous and 1 or 0), steps)
        local text, why = ask(Story.recapPrompt(plan.book, told, plan.percent or 0))
        if text then
            local words = Story.parseText(text, "recap")
            if words ~= "" then result.recap = words end
        else
            result.error = why
        end
    end
    if not result.error and plan.previous then
        note(steps, steps)
        local text, why = ask(Story.previousPrompt(plan.book, plan.previous))
        if text then result.previous = Story.parseText(text, "recap") else result.error = why end
    end
    return XR.writeFile(out, result)
end

-- ------------------------------------------------------------------ asking
local job

function Story.busy() return job ~= nil end

-- "2/5" while an update is under way.
function Story.progress()
    if not job or not job.progress then return nil end
    local f = io.open(job.progress, "r")
    if not f then return nil end
    local line = f:read("*l")
    f:close()
    return line
end


-- Puts what came back with the rest and saves it. Returns how many chapters
-- were summarised, and why it stopped when it did.
local function apply(ui, plan, result)
    if not ui.document then return nil, "the book could not be found" end
    local story = Story.read(ui)
    local titles = {}
    for _i, c in ipairs(plan.pending or {}) do titles[c.i] = c.title end
    local n = 0
    for _i, c in ipairs(type(result.chapters) == "table" and result.chapters or {}) do
        if tonumber(c.i) and type(c.summary) == "string" then
            story.chapters[c.i] = { title = titles[c.i], summary = c.summary, done = not c.partial, upto = c.partial and plan.page or nil }
            if c.summary ~= "" then n = n + 1 end
        end
    end
    if type(result.recap) == "string" and result.recap ~= "" then
        story.recap = { text = result.recap, page = plan.page, percent = plan.percent, at = os.time() }
    end
    if plan.previous and type(result.previous) == "string" then
        story.previous = { title = plan.previous.title, text = result.previous, at = os.time(),
            known = plan.previous.summaries == nil, index = plan.previous.index }
    end
    Story.save(ui)
    return n, result.error, result.more
end

-- Asks for what is missing: the chapters read since, the story so far, and
-- with o.previous the book before. done(n, why, more): chapters summarised;
-- why it stopped, if it did; more when a further update is needed.
-- Returns false and why when it cannot start.
function Story.update(ui, o, done)
    o = o or {}
    local AI = require("aleph_xr_ai")
    local XR = require("aleph_xr")
    if job then return false, "busy" end
    if not AI.ready() then return false, "no key" end
    if not XR.supported(ui) then return false, "not supported" end
    local dir = XR.dir(ui)
    if not dir then return false, "no folder" end
    try(function() require("util").makePath(dir) end)
    local story = Story.read(ui)
    local page = currentPage(ui)
    local pages = 1
    try(function() pages = ui.document:getPageCount() end)
    local props = ui.doc_props or {}
    local authors = props.authors
    if type(authors) == "table" then authors = table.concat(authors, ", ") end
    local pending = o.only_previous and {} or Story.pending(ui)
    local previous = o.previous and Story.previous(ui) or nil
    local told = Story.told(ui)
    if #pending == 0 and not previous and (#told == 0 or story.recap) then
        return false, "nothing new"
    end
    local plan = {
        book = { title = props.display_title or props.title or "", author = authors or "" },
        page = page, percent = math.floor(page / math.max(1, pages) * 100 + 0.5),
        pending = pending, told = told, recap = story.recap and story.recap.text or nil,
        previous = previous, want_recap = not o.only_previous,
    }
    local config = AI.config()
    local function ask(prompt)
        local url, headers, body = AI.request(config, prompt)
        local raw, why = AI.post(url, headers, body)
        if not raw then return nil, why end
        return AI.answer(config, raw)
    end
    local out, progress = dir .. "/aleph_xray_story_answer.lua", dir .. "/aleph_xray_story_progress.txt"
    os.remove(out); os.remove(progress)
    local doc = ui.document
    local file = doc.file
    local function finish(why)
        local j = job
        job = nil
        local result = readFile(out)
        os.remove(out); os.remove(progress)
        local n, stopped, more
        if result then n, stopped, more = apply(require("aleph_xr").target(ui, file), plan, result) else stopped = why or "no answer" end
        pcall(function() require("logger").info("Aleph X-Ray: story", tostring(n or 0) .. " chapters", stopped and ("stopped: " .. tostring(stopped)) or "ok") end)
        if done then try(done, n, stopped, more) end
        return j
    end
    local Job = require("aleph_job")
    local pid = Job.start(function() pcall(Story.work, doc, plan, ask, out, progress) end)
    if pid then
        -- Each question may take as long as one is allowed to.
        local wait = AI.WAIT * (math.min(Story.MAX_BATCHES, math.ceil(#pending / 2) + 1) + 2)
        job = { pid = pid, started = os.time(), progress = progress }
        Job.watch(pid, { every = 2, timeout = wait, on_done = function(late)
            if job then finish(late and "took too long" or nil) end
        end })
        return true
    end
    -- No background process on this device: asked here. The screen waits.
    job = { started = os.time() }
    pcall(Story.work, doc, plan, ask, out, nil)
    finish()
    return true
end

-- ---------------------------------------------------------- after a break
-- When the book was last read, noted as it opens (before anything is saved
-- for this session): the time its settings file was last written.
function Story.noteOpened(ui)
    local st = state(ui)
    try(function()
        local DocSettings = require("docsettings")
        local file = DocSettings.findSidecarFile and DocSettings:findSidecarFile(ui.document.file) or nil
        st.last_read = file and require("libs/libkoreader-lfs").attributes(file, "modification") or nil
        local summary = ui.doc_settings and ui.doc_settings:readSetting("summary")
        st.on_hold = type(summary) == "table" and summary.status == "abandoned"
    end)
end

-- Whole days since the book was last read, or nil when that is not known.
function Story.away(ui)
    local st = ui._aleph_xr
    if not st or not st.last_read then return nil end
    return math.floor((os.time() - st.last_read) / 86400)
end

-- After how many days away a recap is offered (0: never).
function Story.offerDays()
    local days = tonumber(Prefs.get().xray_recap_days)
    if days == nil then return 14 end
    return math.max(0, math.floor(days))
end

-- Whether to ask now: a book set aside (its status On hold, or not read
-- for the days chosen), read some way into, with a key to ask with.
function Story.shouldOffer(ui)
    local limit = Story.offerDays()
    if limit <= 0 then return false end
    local st = ui._aleph_xr
    if not st or st.offered then return false end
    local away = Story.away(ui)
    if not ((away and away >= limit) or (st.on_hold and away and away >= 1)) then return false end
    if not require("aleph_xr").supported(ui) or not require("aleph_xr_ai").ready() then return false end
    local page, pages = currentPage(ui), 1
    try(function() pages = ui.document:getPageCount() end)
    -- Hardly begun: nothing to recap.
    return page >= 5 and page / math.max(1, pages) >= 0.03
end

-- The question, once per opening of the book.
function Story.offer(ui)
    if not Story.shouldOffer(ui) then return false end
    local st = ui._aleph_xr
    st.offered = true
    local _ = require("aleph_gettext")
    local T = require("ffi/util").template
    local away = Story.away(ui) or 0
    local story = Story.read(ui)
    local pending = Story.pending(ui)
    local ready = story.recap and #pending == 0
    local label = require("aleph_xr_ai").config().label
    local text
    if ready then
        text = T(_("You last read this book %1 days ago. See the story so far?"), away)
    else
        text = T(_("You last read this book %1 days ago. Get a summary of the story so far? The text of the %2 chapters read and not summarised yet is sent to %3."), away, #pending, label)
    end
    require("aleph_confirm").show{
        title = _("Welcome back"),
        text = text,
        ok_label = ready and _("Show") or _("Summarise"),
        cancel_label = _("Not now"),
        on_ok = function()
            try(function() require("aleph_xr_page").openStory(ui, not ready) end)
        end,
    }
    return true
end

return Story
