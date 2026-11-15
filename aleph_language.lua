-- Aleph modification, 2026-11-10: a book's language by its name.
--[[--
Books give their language as a code: "en", "en-US" (Calibre writes those),
"eng", "fre"... This turns the code into the language's name ("English"), in
KOReader's language when KOReader has it translated (ui/data/isolanguage).
The region is left out: en-US, en-GB and en all read "English". Anything
that is not a code it knows (a name already, a typo) is shown as it is.
]]

local Language = {}

-- ISO 639-1 (two letters) to ISO 639-3, as in KOReader's isolanguage.lua.
local TWO = { aa = "aar", af = "afr", ar = "ara", as = "asm", az = "aze", ba = "bak", be = "bel", bg = "bul", bn = "ben", bo = "bod", br = "bre", cs = "ces", cu = "chu", cy = "cym", da = "dan", de = "deu", dv = "div", el = "ell", en = "eng", eo = "epo", es = "spa", et = "est", eu = "eus", fa = "fas", fi = "fin", fo = "fao", fr = "fra", fy = "fry", ga = "gle", gd = "gla", gl = "glg", gv = "glv", ha = "hau", he = "heb", hi = "hin", ht = "hat", hu = "hun", hy = "hye", ia = "ina", id = "ind", io = "ido", is = "isl", it = "ita", ja = "jpn", jv = "jav", ka = "kat", ki = "kik", kk = "kaz", kl = "kal", km = "khm", kn = "kan", ko = "kor", ks = "kas", ku = "kur", kw = "cor", ky = "kir", la = "lat", lb = "ltz", lo = "lao", lt = "lit", lv = "lav", mg = "mlg", mh = "mah", mi = "mri", mk = "mkd", ml = "mal", mn = "mon", mr = "mar", ms = "msa", mt = "mlt", my = "mya", nb = "nob", nl = "nld", nn = "nno", no = "nor", nv = "nav", oc = "oci", om = "orm", pa = "pan", pi = "pli", pl = "pol", ps = "pus", pt = "por", qu = "que", rm = "roh", ro = "ron", ru = "rus", sa = "san", sh = "hbs", sk = "slk", sl = "slv", sq = "sqi", sr = "srp", ss = "ssw", su = "sun", sv = "swe", sw = "swa", ta = "tam", te = "tel", tg = "tgk", th = "tha", tl = "tgl", tr = "tur", tt = "tat", ug = "uig", uk = "ukr", ur = "urd", uz = "uzb", vi = "vie", vo = "vol", wa = "wln", xh = "xho", yi = "yid", yo = "yor", za = "zha", zh = "zho", zu = "zul" }

-- ISO 639-2/B codes some books use, to the ISO 639-3 ones.
local B = {
    alb = "sqi", arm = "hye", baq = "eus", bur = "mya", chi = "zho", cze = "ces",
    dut = "nld", fre = "fra", geo = "kat", ger = "deu", gre = "ell", ice = "isl",
    mac = "mkd", mao = "mri", may = "msa", per = "fas", rum = "ron", slo = "slk",
    tib = "bod", wel = "cym",
}

local cache = {}

function Language.name(code)
    if type(code) ~= "string" then return nil end
    local raw = code:match("^%s*(.-)%s*$")
    if raw == "" then return nil end
    if cache[raw] ~= nil then return cache[raw] end
    local base, rest = raw:match("^(%a+)(.*)$")
    local out = raw
    -- A code: two or three letters, maybe a region or script after - or _.
    if base and #base <= 3 and (rest == "" or rest:match("^[-_]")) then
        base = base:lower()
        local iso3 = #base == 2 and TWO[base] or (B[base] or base)
        local ok, name = pcall(function()
            return require("ui/data/isolanguage"):getLocalizedLanguage(iso3)
        end)
        if ok and type(name) == "string" and name ~= "" and name ~= iso3 then out = name end
    end
    cache[raw] = out
    return out
end

return Language
