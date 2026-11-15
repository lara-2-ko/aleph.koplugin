-- Aleph modification, 2026-11-15: Aleph's own translations.
--[[--
KOReader translates only the words it has in its own catalogue, so a
KOReader set to another language showed Aleph half in English. Aleph now
brings its own catalogue for what KOReader does not have:

    l10n/<language>/aleph.po      (pt_BR, es; l10n/aleph.pot lists every text)

    local _ = require("aleph_gettext")
    _("Text")                         -- like KOReader's gettext
    _.ngettext("%1 book", "%1 books", n)
    _.pgettext("Context", "Text")

The language is KOReader's own (Settings > Language). For each text,
KOReader's translation is used when it has one, so Aleph's words match the
rest of KOReader and the texts Aleph looks for on KOReader's buttons stay
the same; Aleph's catalogue fills in the rest, and English is left where
neither has the text. A language Aleph has no file for (pt_PT, es_MX...)
takes the closest one (pt_BR, es).

Adding a language: copy l10n/aleph.pot to l10n/<code>/aleph.po (the code
KOReader uses, as in koreader/l10n) and fill in the msgstr lines.
]]

local GetText = require("gettext")

local M = {}

local catalog          -- [msgid] = msgstr, ["ctx\4msgid"] = msgstr, plurals as tables
local plural_of        -- n -> index of the plural form (0-based)
local loaded_for

local function pluginDir()
    local info = debug.getinfo(1, "S")
    local src = info and info.source or ""
    src = src:gsub("^@", "")
    return src:match("^(.*)[/\\][^/\\]*$") or "."
end

local function exists(path)
    local f = io.open(path, "r")
    if f then f:close() return true end
    return false
end

-- The file for `lang`, else one of the same language.
local function poFor(lang)
    local dir = pluginDir() .. "/l10n/"
    if not lang or lang == "" or lang == "C" or lang:match("^en") then return nil end
    lang = lang:gsub("%..*$", ""):gsub("-", "_")
    local tries = { lang }
    local base = lang:match("^(%a+)_")
    if base then tries[#tries + 1] = base end
    base = base or lang
    -- The variant Aleph has for this language.
    for _i, v in ipairs({ "pt_BR", "es" }) do
        if v:match("^(%a+)") == base then tries[#tries + 1] = v end
    end
    for _i, code in ipairs(tries) do
        local p = dir .. code .. "/aleph.po"
        if exists(p) then return p, code end
    end
    return nil
end

local ESC = { n = "\n", t = "\t", r = "\r", ['"'] = '"', ["\\"] = "\\" }
local function unquote(s)
    return (s:gsub("\\(.)", function(c) return ESC[c] or c end))
end

-- Plural rules of the Plural-Forms header that Aleph's languages use.
local function pluralRule(header)
    local expr = header and header:match("plural%s*=%s*([^;\n]+)") or "n != 1"
    expr = expr:gsub("%s+", "")
    if expr == "(n>1)" or expr == "n>1" then
        return function(n) return n > 1 and 1 or 0 end
    end
    return function(n) return n ~= 1 and 1 or 0 end
end

function M.parse(text)
    local out, header = {}, nil
    local entry, field
    local function finish()
        if entry and entry.msgid and not entry.fuzzy then
            if entry.msgid == "" then
                header = entry.msgstr
            elseif entry.plural then
                local forms, any = {}, false
                for i = 0, 9 do
                    local s = entry["msgstr" .. i]
                    if s and s ~= "" then forms[i] = s; any = true end
                end
                if any then out[(entry.ctx and (entry.ctx .. "\4") or "") .. entry.msgid] = forms end
            elseif entry.msgstr and entry.msgstr ~= "" then
                out[(entry.ctx and (entry.ctx .. "\4") or "") .. entry.msgid] = entry.msgstr
            end
        end
        entry, field = nil, nil
    end
    local fuzzy_next = false
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        line = line:gsub("\r$", "")
        if line:match("^%s*$") then
            finish()
        elseif line:match("^#,") then
            if line:match("fuzzy") then fuzzy_next = true end
        elseif line:match("^#") then
            -- a comment
        else
            local key, rest = line:match("^(msg[%w_%[%]]+)%s+\"(.*)\"%s*$")
            if key then
                local same = key ~= "msgctxt" and key ~= "msgid"
                    or (key == "msgid" and entry and entry.ctx and not entry.msgid)
                if not same then
                    finish()
                    entry = { fuzzy = fuzzy_next }
                    fuzzy_next = false
                end
                entry = entry or {}
                if key == "msgctxt" then field = "ctx"
                elseif key == "msgid" then field = "msgid"
                elseif key == "msgid_plural" then field = "plural"
                elseif key == "msgstr" then field = "msgstr"
                else
                    local n = key:match("^msgstr%[(%d)%]$")
                    field = n and ("msgstr" .. n) or nil
                end
                if field then entry[field] = unquote(rest) end
            else
                local more = line:match("^%s*\"(.*)\"%s*$")
                if more and entry and field then entry[field] = entry[field] .. unquote(more) end
            end
        end
    end
    finish()
    return out, header
end

local function field(name)
    return type(GetText) == "table" and rawget(GetText, name) or nil
end

local function language()
    local lang
    pcall(function() lang = G_reader_settings and G_reader_settings:readSetting("language") end)
    if type(lang) ~= "string" or lang == "" then lang = field("current_lang") end
    return type(lang) == "string" and lang or nil
end

local function load()
    local lang = language()
    if catalog and loaded_for == lang then return end
    loaded_for = lang
    catalog, plural_of = {}, pluralRule(nil)
    local path = poFor(lang)
    if not path then return end
    local ok = pcall(function()
        local f = io.open(path, "r")
        local text = f:read("*a")
        f:close()
        local header
        catalog, header = M.parse(text)
        plural_of = pluralRule(header)
    end)
    if not ok then catalog = {} end
end

local function lookup(key)
    load()
    return catalog[key]
end

-- KOReader's translation when it has one, else Aleph's, else the English.
local function translate(msgid)
    if type(msgid) ~= "string" or msgid == "" then return msgid end
    local ko = GetText(msgid)
    if type(ko) ~= "string" then ko = msgid end
    if ko ~= msgid then return ko end
    local s = lookup(msgid)
    if type(s) == "table" then s = s[0] end
    return s or msgid
end

function M.ngettext(msgid, msgid_plural, n)
    local english = (n == 1) and msgid or msgid_plural
    local ko = field("ngettext") and field("ngettext")(msgid, msgid_plural, n) or english
    if ko ~= english then return ko end
    local forms = lookup(msgid)
    if type(forms) == "table" then
        local s = forms[plural_of(tonumber(n) or 0)] or forms[0]
        if s then return s end
    end
    return english
end

function M.pgettext(ctx, msgid)
    local ko = field("pgettext") and field("pgettext")(ctx, msgid) or msgid
    if ko ~= msgid then return ko end
    local s = lookup(ctx .. "\4" .. msgid)
    if type(s) == "string" then return s end
    return translate(msgid)
end

function M.npgettext(ctx, msgid, msgid_plural, n)
    local english = (n == 1) and msgid or msgid_plural
    local ko = field("npgettext") and field("npgettext")(ctx, msgid, msgid_plural, n) or english
    if ko ~= english then return ko end
    local forms = lookup(ctx .. "\4" .. msgid)
    if type(forms) == "table" then
        local s = forms[plural_of(tonumber(n) or 0)] or forms[0]
        if s then return s end
    end
    return M.ngettext(msgid, msgid_plural, n)
end

-- The language Aleph's texts are in now ("pt_BR", "es"), or nil for English.
function M.language()
    load()
    local _p, code = poFor(language())
    return code
end

-- For tests: forget the catalogue so the next text loads it again.
function M._reset() catalog, loaded_for = nil, nil end

return setmetatable(M, { __call = function(_self, msgid) return translate(msgid) end })
