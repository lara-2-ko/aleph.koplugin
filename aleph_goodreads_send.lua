-- Aleph modification, 2026-11-11: sending a book's status and rating to
-- Goodreads from its page (since 1.2.32 with Aleph's own Goodreads,
-- aleph_gr.lua, no longer through advokatb's plugin).
--[[--
The book page's ⋯ menu has "Send to Goodreads". It sends what Aleph has
for the book:

  status   Finished -> Read (with the day it was finished as the date read),
           Reading -> Currently reading, Unread -> Want to read,
           On hold -> Did not finish when the account has that shelf
  rating   the stars, when the status sent is Read (Goodreads puts a rated
           book on its Read shelf). A half star is rounded up.

A book Goodreads already has as Read (its page says so, or the sidecar has
it as Read) is not added to the Read shelf or dated again (Goodreads takes
that for a second reading, "read 2 times"): only its rating is sent. Read
is not sent when what Goodreads has cannot be asked.

The book does not need to be open. It is found on Goodreads by the link
already in its sidecar, else the Goodreads id or ISBN written in it, else a
search by title and author whose results are offered to choose from. The
link is kept in the sidecar under "goodreads" (where the plugin kept it),
so the tracking (aleph_goodreads_track.lua) knows the book when it opens.
]]

local try = require("aleph_try").call
local Send = {}

-- Goodreads' code (aleph_gr_api.lua) with the sign-in of `gr` (Aleph's
-- Goodreads host, aleph_gr.lua), and the identifiers reader.
function Send.modules(gr)
    local Api = require("aleph_gr_api")
    Api.settings = gr.settings
    return Api, require("aleph_gr_ids")
end

-- What Aleph would send for `book`: { code, shelf, label, rating, date }.
-- settings: Goodreads' (to know the account's shelves); may be nil.
function Send.payload(book, settings)
    local status = book.readStatus
    local p = {}
    if status == "read" then p.code, p.shelf, p.label = 1, "read", "Read"
    elseif status == "reading" then p.code, p.shelf, p.label = 2, "currently-reading", "Currently reading"
    elseif status == "on_hold" then
        local has = false
        try(function() has = settings:hasExclusiveShelf("did-not-finish") end)
        if has then p.code, p.shelf, p.label = 3, "did-not-finish", "Did not finish" end
    else p.code, p.shelf, p.label = 0, "to-read", "Want to read" end
    local r = tonumber(book.rating)
    if r and r >= 0.5 then p.rating = math.max(1, math.min(5, math.floor(r + 0.5))) end
    p.rating_held = p.rating and p.shelf ~= "read" or false
    if p.shelf ~= "read" then p.rating = nil end
    if p.shelf == "read" and type(book.finishedOn) == "string" then
        local y, m, d = book.finishedOn:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)")
        if y then p.date = { year = tonumber(y), month = tonumber(m), day = tonumber(d) } end
    end
    return p
end

-- The link kept in the book's sidecar, or nil.
function Send.linked(gr, path)
    local link
    try(function() link = gr.settings:readBookSettings(path) end)
    if type(link) == "table" and link.edition_id then return link end
    return nil
end

-- Whether a saved link is the Goodreads book `gr_id`.
function Send.sameBook(link, gr_id)
    gr_id = tostring(gr_id)
    return tostring(link.edition_id) == gr_id or tostring(link.book_id) == gr_id
end

-- Forgets the saved link and what was kept of that edition (its
-- review, status and shelf).
function Send.forgetLink(gr, path)
    try(function()
        local GS = gr.settings
        GS:updateBookSetting(path, { edition_id = GS.UNSET, book_id = GS.UNSET, review_id = GS.UNSET,
            title = GS.UNSET, authors = GS.UNSET, goodreads_url = GS.UNSET, status = GS.UNSET, shelf = GS.UNSET })
    end)
end

-- Saves a found book as the book's link.
function Send.saveLink(gr, path, data)
    gr.settings:updateBookSetting(path, {
        edition_id = data.edition_id, book_id = data.book_id, review_id = data.review_id,
        title = data.title, authors = data.authors, goodreads_url = data.goodreads_url, pages = data.pages,
    })
    return Send.linked(gr, path)
end

-- Aleph modification, 2026-11-18: the Goodreads id and ISBN in an OPF's
-- text, as Calibre writes them: <dc:identifier opf:scheme="GOODREADS">123
-- </dc:identifier> (OPF 2) or <dc:identifier>goodreads:123</dc:identifier>
-- (OPF 3); likewise ISBN.
function Send.fromOpfText(xml)
    if type(xml) ~= "string" then return nil, nil end
    local gr_id, isbn
    for attrs, value in xml:gmatch("<dc:identifier([^>]*)>(.-)</dc:identifier>") do
        value = value:gsub("<[^>]+>", ""):gsub("^%s+", ""):gsub("%s+$", "")
        local scheme = (attrs:match('[sS]cheme%s*=%s*["\']([^"\']+)["\']') or ""):lower()
        local prefix, rest = value:match("^([%w_%-]+):%s*(%S+)$")
        if prefix then scheme, value = prefix:lower(), rest end
        if (scheme == "goodreads" or scheme == "goodreads-id" or scheme == "gr") and value:match("^%d+$") then
            gr_id = gr_id or value
        elseif scheme:match("^isbn") then
            local digits = value:gsub("[%s%-]", "")
            if digits:match("^%d%d%d%d%d%d%d%d%d[%dXx]$") or digits:match("^%d%d%d%d%d%d%d%d%d%d%d%d%d$") then isbn = isbn or digits:upper() end
        end
    end
    return gr_id, isbn
end

-- The Goodreads id or ISBN written for the book: in metadata.opf next to it
-- (a Calibre library folder), in its EPUB's OPF (Goodreads' identifiers
-- reader, else Aleph's), or the ISBN Aleph read from it.
function Send.identifiers(book, Identifiers)
    local gr_id, isbn
    try(function()
        local dir = book.path:match("^(.*)/[^/]*$") or ""
        local f = io.open(dir .. "/metadata.opf", "r")
        if f then
            local xml = f:read(262144)
            f:close()
            gr_id, isbn = Send.fromOpfText(xml)
        end
    end)
    if not gr_id and Identifiers then
        try(function()
            local map = Identifiers.fromOpf(book.path)
            if map then
                gr_id = Identifiers.goodreadsIdFromMap(map)
                isbn = isbn or Identifiers.isbnFromMap(map)
            end
        end)
    end
    if not gr_id and type(book.path) == "string" and book.path:lower():match("%.epub$") then
        try(function()
            local g, i = Send.fromOpfText(require("aleph_pages").epubOpf(book.path))
            gr_id, isbn = g, isbn or i
        end)
    end
    if not isbn and type(book.opf) == "table" and book.opf.isbn then isbn = book.opf.isbn end
    return gr_id, isbn
end

function Send.query(book)
    local q = book.title or ""
    if book.authors and book.authors[1] then q = q .. " " .. book.authors[1] end
    return q
end

-- Finds the book on Goodreads. Returns { book = data } when sure, or
-- { choices = list } to choose from (maybe empty).
function Send.find(book, Api, Identifiers)
    local gr_id, isbn = Send.identifiers(book, Identifiers)
    if gr_id then
        local data = Api:get_book(gr_id)
        if data then return { book = data } end
    end
    if isbn then
        local list = Api:search(isbn)
        if list and list[1] then return { book = list[1] } end
    end
    return { choices = Api:search(Send.query(book)) or {} }
end

-- Sends the payload for a linked book. Returns ok, what was sent, error.
function Send.send(gr, Api, book, link, payload)
    Api.settings = gr.settings
    local id = link.edition_id
    local backend = Api:_get_backend()
    local result
    if not payload.code then return false, {}, "no-status" end
    local _ = require("aleph_gettext")
    -- What Goodreads already has. A book it already has as Read must not be
    -- added to the Read shelf again: Goodreads takes that as another time the
    -- book was read ("Read 2 times").
    local state
    try(function() state = Api:get_review_state(id) end)
    local known = type(state) == "table" and state.ok
    try(function()
        require("logger").info("Aleph: Goodreads state before sending:", known and tostring(state.shelf) or "unknown",
            "readings", known and tostring(state.session_count) or "?", "review", known and tostring(state.review_id) or "?")
    end)
    -- Aleph modification, 2026-11-17: Read is never sent on a guess. The
    -- book counts as Read already when Goodreads' page says so, or when the
    -- sidecar has it as Read (sent before): Goodreads' page can come
    -- back without the shelf when its layout changes, and shelving and
    -- dating it again made a second reading. Nothing is sent when what
    -- Goodreads has cannot be asked at all.
    local local_read = false
    try(function()
        local st = gr.settings:readBookSetting(book.path, "status")
        local sh = gr.settings:readBookSetting(book.path, "shelf")
        local_read = tonumber(st) == 1 or sh == "read"
    end)
    if payload.shelf == "read" and not known then
        return false, {}, _("Could not see what Goodreads has for this book, so nothing was sent. Try again in a moment.")
    end
    local already_read = payload.shelf == "read" and ((known and state.shelf == "read")
        or (local_read and not (known and state.shelf and state.shelf ~= "read")))
    if already_read then
        -- Its rating only: no shelving, no date. A reading Goodreads already
        -- has is not added to (an extra date is the second reading).
        result = { ok = true }
    elseif payload.shelf == "read" then
        -- set_status would date the reading today; the book's own finished
        -- day is sent instead. That date is added only
        -- when the book has no reading on Goodreads yet.
        result = backend:_add_to_shelf(id, "read", "")
        if result and result.ok then
            local when = payload.date or os.date("*t")
            try(function() backend:set_date_finished(id, when) end)
        end
    else
        result = Api:set_status(id, payload.code, nil, nil, payload.shelf)
    end
    if not (result and result.ok) then
        return false, {}, result and result.error_text or "status"
    end
    local sent = { status = payload.label, already = already_read or nil }
    if payload.rating then
        if already_read and known and tonumber(state.rating) == payload.rating then
            sent.rating = payload.rating -- Goodreads has this rating already
        else
            local r = Api:set_rating(id, payload.rating)
            if r and r.ok then sent.rating = payload.rating
            else sent.rating_error = r and r.error_text or "rating" end
        end
    end
    -- What is kept of the book's Goodreads state.
    try(function()
        local update = { status = payload.code, shelf = payload.shelf }
        if sent.rating then update.rating = sent.rating end
        gr.settings:updateBookSetting(book.path, update)
    end)
    return true, sent
end

-- ------------------------------------------------------------ from the page
local function toast(text, icon)
    try(function() require("aleph_toast").show(text, { icon = icon or "check" }) end)
end

-- Busy message while the network calls run (they block).
local function busy(text, fn)
    local UIManager = require("ui/uimanager")
    local InfoMessage = require("ui/widget/infomessage")
    local msg = InfoMessage:new{ text = text }
    UIManager:show(msg)
    UIManager:forceRePaint()
    local ok, a, b, c = pcall(fn)
    UIManager:close(msg)
    if not ok then require("logger").warn("Aleph: Goodreads:", a) end
    return ok, a, b, c
end

-- The whole flow from the book page. browser: the Browser (for its sheet,
-- messages and prompts).
function Send.start(browser, book)
    local _ = require("aleph_gettext")
    local GR = require("aleph_goodreads")
    local ui = browser.plugin and browser.plugin.ui
    local gr = require("aleph_gr").host()
    local Api, Identifiers = Send.modules(gr)
    local has_cookie = false
    try(function() has_cookie = gr.settings:hasCookie() end)
    if not has_cookie then
        return require("aleph_confirm").show{
            title = _("Send to Goodreads"),
            text = _("Goodreads is not signed in. Send the sign-in from your computer first (Settings → Library → Goodreads sign-in)."),
            ok_label = _("Open"), cancel_label = _("Close"),
            on_ok = function() GR.open(ui) end,
        }
    end
    require("ui/network/manager"):runWhenOnline(function()
        local link = Send.linked(gr, book.path)
        -- Aleph modification, 2026-11-18: the Goodreads id written for the
        -- book (Calibre) wins over a link saved before to another edition:
        -- the link is made again to it, so there are no duplicates.
        local gr_id = Send.identifiers(book, Identifiers)
        -- (Not one Goodreads would not shelve: aleph_gr.lua relinked it.)
        if link and gr_id and not Send.sameBook(link, gr_id) and tostring(link.unshelvable) ~= tostring(gr_id) then
            local ok, data = busy(_("Looking for the book on Goodreads…"), function() return Api:get_book(gr_id) end)
            if ok and data then
                require("logger").info("Aleph: Goodreads link changed to the book's own id", gr_id, "from", tostring(link.edition_id))
                Send.forgetLink(gr, book.path)
                return Send.confirm(browser, gr, Api, book, Send.saveLink(gr, book.path, data))
            end
        end
        if link then return Send.confirm(browser, gr, Api, book, link) end
        local ok, found = busy(_("Looking for the book on Goodreads…"), function() return Send.find(book, Api, Identifiers) end)
        if not ok or not found then return browser:message(_("Goodreads could not be reached. Check the connection and try again.")) end
        if found.book then
            local saved = Send.saveLink(gr, book.path, found.book)
            return Send.confirm(browser, gr, Api, book, saved)
        end
        Send.choose(browser, gr, Api, book, found.choices or {}, Send.query(book))
    end)
end

-- Offers search results in the book page's sheet.
function Send.choose(browser, gr, Api, book, list, query)
    browser.detail_sheet = { kind = "goodreads-pick", choices = list, query = query, page = 1,
        on_pick = function(data)
            local saved = Send.saveLink(gr, book.path, data)
            Send.confirm(browser, gr, Api, book, saved)
        end,
        on_search = function()
            local _ = require("aleph_gettext")
            browser:input(_("Search on Goodreads"), query, function(q)
                q = (q or ""):gsub("^%s+", ""):gsub("%s+$", "")
                if q == "" then return end
                local ok, more = busy(_("Searching Goodreads…"), function() return Api:search(q) end)
                Send.choose(browser, gr, Api, book, ok and more or {}, q)
            end, _("Search"))
        end,
    }
    browser:updateItems()
end

-- The sheet's model for the choices (Browser:detailSheetModel).
function Send.sheetModel(sheet, book)
    local _ = require("aleph_gettext")
    local rows = {}
    for i, c in ipairs(sheet.choices or {}) do
        if i > 12 then break end
        local by = (c.authors and c.authors ~= "") and (" · " .. c.authors) or ""
        rows[#rows + 1] = { label = (c.title or "?") .. by, icon = "book", chevron = true, action = { kind = "gr-pick", index = i } }
    end
    return { title = _("Which book is it on Goodreads?"), sub = book.title, rows = rows, page = sheet.page,
        empty = _("Nothing found. Search with other words below."),
        foot = { { label = _("Search with other words…"), icon = "search", action = { kind = "gr-search" } } } }
end

-- What will be sent, then sending.
function Send.confirm(browser, gr, Api, book, link)
    local _ = require("aleph_gettext")
    local T = require("ffi/util").template
    local p = Send.payload(book, gr.settings)
    if not p.code then
        return browser:message(_("This book is On hold here, and the Goodreads account has no Did not finish shelf to put it on."))
    end
    local lines = { T(_("Goodreads book: %1"), (link.title or "?") .. ((link.authors and link.authors ~= "") and (" · " .. link.authors) or "")), "" }
    lines[#lines + 1] = T(_("Status: %1"), _(p.label))
    if p.shelf == "read" then
        lines[#lines + 1] = p.date and T(_("Date read: %1"), string.format("%04d-%02d-%02d", p.date.year, p.date.month, p.date.day)) or _("Date read: today")
    end
    if p.rating then lines[#lines + 1] = T(_("Rating: %1 stars"), p.rating)
    elseif p.rating_held then lines[#lines + 1] = _("Rating: not sent (Goodreads takes ratings for read books)") end
    lines[#lines + 1] = ""
    lines[#lines + 1] = _("What Goodreads has for this book is replaced. A book that is already Read there is not shelved again, so it does not count as read twice; its rating is sent.")
    require("aleph_confirm").show{
        title = _("Send to Goodreads"), text = table.concat(lines, "\n"), lines = 16,
        ok_label = _("Send"),
        extra_label = _("Not this book? Choose another…"),
        on_extra = function()
            -- Wrong match: forget the link and search.
            Send.forgetLink(gr, book.path)
            local ok, list = busy(_("Searching Goodreads…"), function() return Api:search(Send.query(book)) end)
            Send.choose(browser, gr, Api, book, ok and list or {}, Send.query(book))
        end,
        on_ok = function()
            local ok, done, sent, err = busy(_("Sending to Goodreads…"), function() return Send.send(gr, Api, book, link, p) end)
            if not ok or not done then
                return browser:message(T(_("Goodreads did not take it.\n%1"), tostring(err or sent or "")))
            end
            if sent.rating_error then
                return browser:message(T(_("Status sent, but the rating was not: %1"), tostring(sent.rating_error)))
            end
            if sent.already then
                return toast(sent.rating and T(_("Already Read on Goodreads: rating %1 stars"), sent.rating)
                    or _("Already Read on Goodreads: nothing to add"))
            end
            toast(sent.rating and T(_("Sent to Goodreads: %1, %2 stars"), _(sent.status), sent.rating) or T(_("Sent to Goodreads: %1"), _(sent.status)))
        end,
    }
end

return Send
