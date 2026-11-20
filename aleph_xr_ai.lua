-- Aleph modification, 2026-11-14: X-Ray's optional descriptions.
--[[--
The names of a book are found from its text, with no network
(aleph_xr_names.lua). What each one is, in a sentence or two, is what this
file adds, for the books where it is wanted: one question to a language
model, asked when the reader taps "Describe with AI", answered in the
background while reading goes on.

It uses the reader's own account with a provider (a key typed once in
Settings > X-Ray): Claude (Anthropic), OpenAI, Gemini (Google), or any
service that speaks OpenAI's chat format at an address of one's own (a
local model, OpenRouter...).

What is sent: the book's title and author, how far the reader is, and, for
each of the names most mentioned so far, the name and two short excerpts
(a few words around it) from the pages already read. Never the whole book,
and nothing from the pages not read yet: the model is asked to describe
each name from what a reader at this point knows, so the descriptions do
not give away what comes later. They can be asked for again further on.

    AI.config()             provider, model, key and address, from Settings
    AI.ready()              a key is there
    AI.describe(ui, done)   asks, and puts the answer in the book's names
    AI.busy()               a question is out

The request runs in a process of its own where the device allows one, so
the screen answers meanwhile; where it does not, the screen waits for it.

Aleph modification, 2026-11-18 (1.2.37): "Detailed descriptions" (Settings >
X-Ray, off unless turned on), for accounts with a larger allowance. The
question then also holds, more than three times as long:

  - the chapter summaries already written for the story so far
    (aleph_xr_story.lua), when there are any;
  - for the AI.MAIN names mentioned most, AI.PASSAGES passages of a
    sentence or two each (the first mention, the chapter it comes up most
    in, the latest, some between; aleph_xr_more.lua) and the names most
    often near it;

and asks for 3 to 4 sentences about each of those: who they are, their
role, their relationships, what they have done so far. The other names are
described as before. Still nothing from a page not read yet. The passages
are read from the book in the background process with the question.
]]

local Prefs = require("aleph_prefs")
local try = require("aleph_try").call

local AI = {}

-- The models are only where to start: providers rename and retire theirs,
-- and Settings > X-Ray > Model takes any name.
AI.PROVIDERS = {
    { id = "anthropic", label = "Claude", model = "claude-haiku-5-5" },
    { id = "openai", label = "OpenAI", model = "gpt-5.4-mini" },
    { id = "gemini", label = "Gemini", model = "gemini-3.5-flash" },
    { id = "custom", label = "Other", model = "" },
}
-- How many names are described in one question.
AI.MAX_NAMES = 60
-- Detailed descriptions: the names given more, the passages for each, and
-- how much of the chapter summaries is sent at most.
AI.MAIN = 15
AI.PASSAGES = 8
AI.STORY_CHARS = 16000

function AI.rich() return Prefs.is("xray_ai_rich") end
AI.KINDS = { person = true, place = true, group = true, thing = true, other = true }
-- How long an answer may take.
AI.WAIT = 240

function AI.provider(id)
    for _i, p in ipairs(AI.PROVIDERS) do
        if p.id == id then return p end
    end
    return AI.PROVIDERS[1]
end

function AI.config()
    local s = Prefs.get()
    local provider = AI.provider(s.xray_ai_provider)
    local model = type(s.xray_ai_model) == "string" and s.xray_ai_model ~= "" and s.xray_ai_model or provider.model
    return {
        provider = provider.id,
        label = provider.label,
        model = model,
        key = type(s.xray_ai_key) == "string" and s.xray_ai_key or "",
        url = type(s.xray_ai_url) == "string" and s.xray_ai_url or "",
    }
end

function AI.ready()
    local c = AI.config()
    if c.provider == "custom" then return c.url ~= "" and c.model ~= "" end
    return c.key ~= ""
end

-- ------------------------------------------------------------ the question
local function oneLine(str)
    return (tostring(str or ""):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))
end

-- items: { { n = index, name, aliases, excerpts = { "...", ... }, main,
-- often = { "name", ... } }, ... }. story: { { title, summary }, ... } or
-- nil (detailed descriptions only).
function AI.prompt(book, items, percent, story)
    local main = false
    for _i, item in ipairs(items) do if item.main then main = true end end
    local lines = {
        "You are helping a reader keep track of the names in a book they are reading.",
        string.format('Book: "%s"%s. The reader is %d%% of the way through it.',
            oneLine(book.title ~= "" and book.title or "untitled"),
            book.author and book.author ~= "" and (" by " .. oneLine(book.author)) or "", percent),
    }
    if story and #story > 0 then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "What has happened so far, chapter by chapter (summaries written earlier from the pages read):"
        for _i, c in ipairs(story) do
            lines[#lines + 1] = "- " .. oneLine(c.title) .. ": " .. oneLine(c.summary)
        end
        lines[#lines + 1] = ""
    end
    lines[#lines + 1] = "Below are names found in the book, each with excerpts from the part already read."
    if main then
        lines[#lines + 1] = "For each name say what it is. Names marked MAIN are the most important so far: describe each of them in three to four sentences"
            .. " (who they are, their role in the story, their relationships to the other names, and what they have done so far)."
            .. " Describe every other name in at most two sentences."
    else
        lines[#lines + 1] = "For each name say what it is and describe it in at most two sentences."
    end
    lines[#lines] = lines[#lines] .. " Use only what a reader at this point would know."
        .. " Do not reveal anything that happens later in the book."
        .. " If a name is not a person, place, group or thing of the story (a common word, a nationality, a month), give it the kind \"other\" and an empty description."
    lines[#lines + 1] = "Answer with a JSON array only, one object per name: {\"n\": <the name's number>, \"kind\": \"person\" | \"place\" | \"group\" | \"thing\" | \"other\", \"about\": \"<description>\"}."
        .. " Write the descriptions in the language of the excerpts."
    lines[#lines + 1] = ""
    for _i, item in ipairs(items) do
        local also = item.aliases and #item.aliases > 0 and (" (also: " .. table.concat(item.aliases, ", ") .. ")") or ""
        local often = item.often and #item.often > 0 and (" — often near: " .. table.concat(item.often, ", ")) or ""
        lines[#lines + 1] = item.n .. ". " .. (item.main and "MAIN " or "") .. oneLine(item.name) .. also .. often
        for _j, excerpt in ipairs(item.excerpts or {}) do
            lines[#lines + 1] = '   - "' .. oneLine(excerpt):gsub('"', "'") .. '"'
        end
    end
    return table.concat(lines, "\n")
end

-- The chapter summaries to send: the latest ones when they are too long
-- together, in the book's order.
function AI.storyFor(told, limit)
    limit = limit or AI.STORY_CHARS
    local out, used = {}, 0
    for i = #told, 1, -1 do
        local c = told[i]
        local size = #(c.title or "") + #(c.summary or "") + 4
        if used + size > limit then break end
        table.insert(out, 1, { title = c.title, summary = c.summary })
        used = used + size
    end
    return out
end

-- Where to send the question, with what headers and body, for a provider.
function AI.request(config, prompt, max_tokens)
    local json = require("json")
    local headers = { ["Content-Type"] = "application/json", ["Accept"] = "application/json" }
    local url, body
    if config.provider == "anthropic" then
        url = "https://api.anthropic.com/v1/messages"
        headers["x-api-key"] = config.key
        headers["anthropic-version"] = "2023-06-01"
        body = { model = config.model, max_tokens = max_tokens or 4096, messages = { { role = "user", content = prompt } } }
    elseif config.provider == "gemini" then
        url = "https://generativelanguage.googleapis.com/v1beta/models/" .. config.model .. ":generateContent"
        headers["x-goog-api-key"] = config.key
        -- The answer asked for as JSON, so no words come around the list.
        body = { contents = { { parts = { { text = prompt } } } }, generationConfig = { responseMimeType = "application/json" } }
    else
        url = config.provider == "custom" and config.url or "https://api.openai.com/v1/chat/completions"
        if config.key ~= "" then headers["Authorization"] = "Bearer " .. config.key end
        body = { model = config.model, messages = { { role = "user", content = prompt } } }
    end
    return url, headers, json.encode(body)
end

-- The text of a provider's answer, or nil and why.
function AI.answer(config, raw)
    local ok, data = pcall(function() return require("json").decode(raw) end)
    if not ok or type(data) ~= "table" then return nil, "the answer could not be read" end
    local err = data.error
    if type(err) == "table" then return nil, tostring(err.message or err.type or "refused") end
    if type(err) == "string" then return nil, err end
    local text
    if config.provider == "anthropic" then
        local parts = {}
        for _i, block in ipairs(type(data.content) == "table" and data.content or {}) do
            if type(block) == "table" and type(block.text) == "string" then parts[#parts + 1] = block.text end
        end
        text = table.concat(parts)
    elseif config.provider == "gemini" then
        local first = type(data.candidates) == "table" and data.candidates[1]
        local parts = {}
        for _i, part in ipairs(type(first) == "table" and type(first.content) == "table" and type(first.content.parts) == "table" and first.content.parts or {}) do
            if type(part) == "table" and type(part.text) == "string" then parts[#parts + 1] = part.text end
        end
        text = table.concat(parts)
    else
        local first = type(data.choices) == "table" and data.choices[1]
        text = type(first) == "table" and type(first.message) == "table" and first.message.content or nil
    end
    if type(text) ~= "string" or text == "" then return nil, "the answer was empty" end
    return text
end

-- The descriptions in an answer: { [index] = { kind, about } }, and how many.
function AI.parse(text, count)
    local from, to = text:find("%[.*%]")
    if not from then return {}, 0 end
    local ok, list = pcall(function() return require("json").decode(text:sub(from, to)) end)
    if not ok or type(list) ~= "table" then return {}, 0 end
    local out, n = {}, 0
    for _i, item in ipairs(list) do
        local index = type(item) == "table" and tonumber(item.n) or nil
        if index and index >= 1 and index <= count and index % 1 == 0 and not out[index] then
            local kind = type(item.kind) == "string" and item.kind:lower() or "other"
            if not AI.KINDS[kind] then kind = "other" end
            local about = type(item.about) == "string" and oneLine(item.about) or ""
            if #about > 1000 then about = about:sub(1, 1000):gsub("[\128-\191]*$", ""):gsub("%s+%S*$", "") .. "…" end
            out[index] = { kind = kind, about = about }
            n = n + 1
        end
    end
    return out, n
end

-- ---------------------------------------------------------------- asking
-- Sends the question; returns the provider's answer as it came, or nil and
-- why. Blocks until it is back: run in the background process.
local function post(url, headers, body)
    local ltn12 = require("ltn12")
    local socketutil = require("socketutil")
    local sink = {}
    headers["Content-Length"] = tostring(#body)
    -- A model writes its whole answer before sending any of it, which can
    -- take a minute or more: the wait for the first byte is as long as the
    -- wait for the answer. (It was 20 seconds until 1.1.54, and a slower
    -- model was given up on: "no answer (wantread)".)
    socketutil:set_timeout(AI.WAIT - 30, AI.WAIT - 30)
    local ok, code = pcall(function()
        local https = url:match("^https:") and require("ssl.https") or require("socket.http")
        local _r, status = https.request{
            url = url, method = "POST", headers = headers,
            source = ltn12.source.string(body), sink = ltn12.sink.table(sink),
        }
        return status
    end)
    socketutil:reset_timeout()
    local raw = table.concat(sink)
    if not ok then return nil, tostring(code) end
    if raw == "" then
        -- "wantread" and "timeout" are how the connection says it waited
        -- in vain.
        local reason = tostring(code)
        if reason == "wantread" or reason == "wantwrite" or reason == "timeout" then
            return nil, "the provider took too long to answer"
        end
        return nil, "no answer (" .. reason .. ")"
    end
    return raw, code
end
AI.post = post

local job

function AI.busy() return job ~= nil end


-- The names to describe: the most mentioned so far, each with two excerpts
-- from the pages read (its first mention and one about half-way). rich:
-- the AI.MAIN most mentioned get AI.PASSAGES longer passages and the names
-- most often near them (aleph_xr_more.lua) instead.
function AI.items(ui, rich)
    local XR = require("aleph_xr")
    local data = XR.names(ui)
    local hits = XR.hits(ui)
    if not data or not hits then return {} end
    local ranked = {}
    for index, entry in ipairs(data.names) do
        if not entry.hidden then
            local seen = XR.count(ui, index)
            if seen > 0 then ranked[#ranked + 1] = { index = index, seen = seen } end
        end
    end
    table.sort(ranked, function(a, b)
        if a.seen ~= b.seen then return a.seen > b.seen end
        return a.index < b.index
    end)
    local More, chapters
    if rich then
        More = require("aleph_xr_more")
        chapters = require("aleph_xr_story").chapters(ui)
    end
    local items = {}
    for i = 1, math.min(#ranked, AI.MAX_NAMES) do
        local r = ranked[i]
        local entry = data.names[r.index]
        local item = { n = r.index, name = entry.name, aliases = entry.aliases, excerpts = {} }
        if rich and i <= AI.MAIN then
            item.main = true
            for _j, p in ipairs(More.passages(ui, r.index, AI.PASSAGES, chapters)) do
                item.excerpts[#item.excerpts + 1] = (p.chapter and (p.chapter .. ": ") or "") .. p.text
            end
            item.often = {}
            for _j, o in ipairs(More.oftenWith(ui, r.index, 4)) do item.often[#item.often + 1] = o.name end
        else
            local list = hits.by[r.index]
            local picks = { 1 }
            if r.seen >= 4 then picks[2] = math.ceil(r.seen / 2) end
            for _j, nth in ipairs(picks) do
                local before, name, after = XR.snippet(ui, list[nth])
                if before then item.excerpts[#item.excerpts + 1] = before .. name .. after end
            end
        end
        items[#items + 1] = item
    end
    return items
end

-- The whole question: { url, headers, body }. Reads the book for the
-- passages when rich (in the background process where there is one).
function AI.question(ui, config, percent, rich)
    local props = ui.doc_props or {}
    local authors = props.authors
    if type(authors) == "table" then authors = table.concat(authors, ", ") end
    local items = AI.items(ui, rich)
    local story
    if rich then
        try(function() story = AI.storyFor(require("aleph_xr_story").told(ui)) end)
    end
    local prompt = AI.prompt({ title = props.display_title or props.title or "", author = authors or "" }, items, percent, story)
    local url, headers, body = AI.request(config, prompt, rich and 8192 or nil)
    return url, headers, body
end

-- Puts an answer in the book's names. Returns how many were described, or
-- nil and why.
function AI.apply(ui, config, raw, percent, rich)
    local XR = require("aleph_xr")
    local data = XR.names(ui)
    if not data then return nil, "this book's names could not be read" end
    local text, why = AI.answer(config, raw)
    if not text then return nil, why end
    local found, n = AI.parse(text, #data.names)
    if n == 0 then return nil, "no descriptions in the answer" end
    for index, d in pairs(found) do
        local entry = data.names[index]
        entry.kind = d.kind
        if d.about ~= "" then entry.about = d.about end
    end
    data.ai = { at = os.time(), percent = percent, model = config.model, described = n, rich = rich or nil }
    XR.save(ui)
    return n
end

-- Asks for the descriptions. done(n, why): how many names were described,
-- or nil and why not. Returns false (and why) when it cannot start.
function AI.describe(ui, done)
    local XR = require("aleph_xr")
    if job then return false, "busy" end
    if not AI.ready() then return false, "no key" end
    if #AI.items(ui) == 0 then return false, "no names" end
    local config = AI.config()
    local rich = AI.rich()
    local percent = 0
    try(function()
        percent = math.floor((ui:getCurrentPage() / math.max(1, ui.document:getPageCount())) * 100 + 0.5)
    end)
    local dir = XR.dir(ui)
    local file = ui.document and ui.document.file
    local function finish(raw, why)
        job = nil
        local n, reason
        -- The book may have been reopened by KOReader since the question.
        if raw then n, reason = AI.apply(XR.target(ui, file), config, raw, percent, rich) else reason = why end
        -- In crash.log, so a failure can be told from the log alone.
        pcall(function() require("logger").info("Aleph X-Ray: descriptions",
            n and (tostring(n) .. " names") or ("failed: " .. tostring(reason)), "| " .. tostring(config.provider),
            tostring(config.model), rich and "detailed" or "") end)
        if done then try(done, n, reason) end
    end
    local Job = require("aleph_job")
    if Job.available() and dir then
        local out = dir .. "/aleph_xray_answer.txt"
        os.remove(out)
        local pid = Job.start(function()
            local raw, why
            local ok, url, headers, body = pcall(AI.question, ui, config, percent, rich)
            if ok then raw, why = post(url, headers, body) else why = "could not prepare: " .. tostring(url) end
            local f = io.open(out .. ".part", "w")
            if f then
                f:write(raw and "ok\n" or "error\n", raw or tostring(why))
                f:close()
                os.rename(out .. ".part", out)
            end
        end)
        if pid then
            job = { pid = pid, started = os.time() }
            Job.watch(pid, { timeout = AI.WAIT, on_done = function(late)
                if not job then return end
                local f = io.open(out, "r")
                local content = f and f:read("*a") or nil
                if f then f:close() end
                os.remove(out)
                local status, rest = (content or ""):match("^(%a+)\n(.*)$")
                if status == "ok" then finish(rest)
                else finish(nil, late and "took too long" or (rest ~= "" and rest or "no answer")) end
            end })
            return true
        end
    end
    -- No background process on this device: asked here. The screen waits.
    job = { started = os.time() }
    local raw, why
    local ok, url, headers, body = pcall(AI.question, ui, config, percent, rich)
    if ok then raw, why = post(url, headers, body) else why = "could not prepare: " .. tostring(url) end
    finish(raw, why)
    return true
end

return AI
