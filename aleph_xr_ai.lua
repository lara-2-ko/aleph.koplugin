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

-- items: { { n = index, name, aliases, excerpts = { "...", ... } }, ... }
function AI.prompt(book, items, percent)
    local lines = {
        "You are helping a reader keep track of the names in a book they are reading.",
        string.format('Book: "%s"%s. The reader is %d%% of the way through it.',
            oneLine(book.title ~= "" and book.title or "untitled"),
            book.author and book.author ~= "" and (" by " .. oneLine(book.author)) or "", percent),
        "Below are names found in the book, each with short excerpts from the part already read.",
        "For each name say what it is and describe it in at most two sentences, using only what a reader at this point would know."
            .. " Do not reveal anything that happens later in the book."
            .. " If a name is not a person, place, group or thing of the story (a common word, a nationality, a month), give it the kind \"other\" and an empty description.",
        "Answer with a JSON array only, one object per name: {\"n\": <the name's number>, \"kind\": \"person\" | \"place\" | \"group\" | \"thing\" | \"other\", \"about\": \"<description>\"}."
            .. " Write the descriptions in the language of the excerpts.",
        "",
    }
    for _i, item in ipairs(items) do
        local also = item.aliases and #item.aliases > 0 and (" (also: " .. table.concat(item.aliases, ", ") .. ")") or ""
        lines[#lines + 1] = item.n .. ". " .. oneLine(item.name) .. also
        for _j, excerpt in ipairs(item.excerpts or {}) do
            lines[#lines + 1] = '   - "' .. oneLine(excerpt):gsub('"', "'") .. '"'
        end
    end
    return table.concat(lines, "\n")
end

-- Where to send the question, with what headers and body, for a provider.
function AI.request(config, prompt)
    local json = require("json")
    local headers = { ["Content-Type"] = "application/json", ["Accept"] = "application/json" }
    local url, body
    if config.provider == "anthropic" then
        url = "https://api.anthropic.com/v1/messages"
        headers["x-api-key"] = config.key
        headers["anthropic-version"] = "2023-06-01"
        body = { model = config.model, max_tokens = 4096, messages = { { role = "user", content = prompt } } }
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
            if #about > 600 then about = about:sub(1, 600):gsub("[\128-\191]*$", ""):gsub("%s+%S*$", "") .. "…" end
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

local function subprocess()
    local ok, u = pcall(require, "ffi/util")
    if ok and type(u) == "table" and type(u.runInSubProcess) == "function" and type(u.isSubProcessDone) == "function" then
        return u
    end
end

-- The names to describe: the most mentioned so far, each with two excerpts
-- from the pages read (its first mention and one about half-way).
function AI.items(ui)
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
    local items = {}
    for i = 1, math.min(#ranked, AI.MAX_NAMES) do
        local r = ranked[i]
        local entry = data.names[r.index]
        local list = hits.by[r.index]
        local picks = { 1 }
        if r.seen >= 4 then picks[2] = math.ceil(r.seen / 2) end
        local excerpts = {}
        for _j, nth in ipairs(picks) do
            local before, name, after = XR.snippet(ui, list[nth])
            if before then excerpts[#excerpts + 1] = before .. name .. after end
        end
        items[#items + 1] = { n = r.index, name = entry.name, aliases = entry.aliases, excerpts = excerpts }
    end
    return items
end

-- Puts an answer in the book's names. Returns how many were described, or
-- nil and why.
function AI.apply(ui, config, raw, percent)
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
    data.ai = { at = os.time(), percent = percent, model = config.model, described = n }
    XR.save(ui)
    return n
end

-- Asks for the descriptions. done(n, why): how many names were described,
-- or nil and why not. Returns false (and why) when it cannot start.
function AI.describe(ui, done)
    local XR = require("aleph_xr")
    if job then return false, "busy" end
    if not AI.ready() then return false, "no key" end
    local items = AI.items(ui)
    if #items == 0 then return false, "no names" end
    local config = AI.config()
    local percent = 0
    try(function()
        percent = math.floor((ui:getCurrentPage() / math.max(1, ui.document:getPageCount())) * 100 + 0.5)
    end)
    local props = ui.doc_props or {}
    local authors = props.authors
    if type(authors) == "table" then authors = table.concat(authors, ", ") end
    local prompt = AI.prompt({ title = props.display_title or props.title or "", author = authors or "" }, items, percent)
    local url, headers, body = AI.request(config, prompt)
    local dir = XR.dir(ui)
    local file = ui.document and ui.document.file
    local function finish(raw, why)
        job = nil
        local n, reason
        -- The book may have been reopened by KOReader since the question.
        if raw then n, reason = AI.apply(XR.target(ui, file), config, raw, percent) else reason = why end
        -- In crash.log, so a failure can be told from the log alone.
        pcall(function() require("logger").info("Aleph X-Ray: descriptions", n and (tostring(n) .. " names") or ("failed: " .. tostring(reason)), "| " .. tostring(config.provider), tostring(config.model)) end)
        if done then try(done, n, reason) end
    end
    local u = subprocess()
    if u and dir then
        local out = dir .. "/aleph_xray_answer.txt"
        os.remove(out)
        local ok, pid = pcall(u.runInSubProcess, function()
            local raw, why = post(url, headers, body)
            local f = io.open(out .. ".part", "w")
            if f then
                f:write(raw and "ok\n" or "error\n", raw or tostring(why))
                f:close()
                os.rename(out .. ".part", out)
            end
        end)
        if ok and pid then
            job = { pid = pid, started = os.time() }
            local UIManager = require("ui/uimanager")
            local function poll()
                local j = job
                if not j then return end
                local got, over = pcall(u.isSubProcessDone, j.pid)
                if not got then over = true end
                local late = false
                if not over and os.time() - j.started > AI.WAIT then
                    pcall(function()
                        if u.terminateSubProcess then u.terminateSubProcess(j.pid) end
                        u.isSubProcessDone(j.pid, true)
                    end)
                    over, late = true, true
                end
                if not over then
                    UIManager:scheduleIn(1, poll)
                    return
                end
                local f = io.open(out, "r")
                local content = f and f:read("*a") or nil
                if f then f:close() end
                os.remove(out)
                local status, rest = (content or ""):match("^(%a+)\n(.*)$")
                if status == "ok" then finish(rest)
                else finish(nil, late and "took too long" or (rest ~= "" and rest or "no answer")) end
            end
            UIManager:scheduleIn(1, poll)
            return true
        end
    end
    -- No background process on this device: asked here. The screen waits.
    job = { started = os.time() }
    local raw, why = post(url, headers, body)
    finish(raw, why)
    return true
end

return AI
