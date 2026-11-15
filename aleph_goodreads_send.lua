-- Aleph modification, 2026-11-11: sending a book's status and rating to
-- Goodreads from its page, through the Goodreads plugin by advokatb.
--[[--
The book page's ⋯ menu has "Send to Goodreads" when that plugin is
installed (aleph_goodreads.lua tells). It sends what Aleph has for the book:

  status   Finished -> Read (with the day it was finished as the date read),
           Reading -> Currently reading, Unread -> Want to read,
           On hold -> Did not finish when the account has that shelf
  rating   the stars, when the status sent is Read (Goodreads puts a rated
           book on its Read shelf). A half star is rounded up.

The book does not need to be open. It is found on Goodreads the way the
plugin finds a book it opens: the link already in its sidecar, else the
Goodreads id or ISBN in the EPUB, else a search by title and author whose
results are offered to choose from. The link is kept in the sidecar where
the plugin keeps it, so the plugin knows the book next time it opens.

Everything goes through the plugin's own code (its goodreads_api and
goodreads_identifiers modules, its settings and session cookie): Aleph
holds no Goodreads code of its own beyond choosing what to send.
]]

local try = require("aleph_try").call
local Send = {}

-- The plugin's modules, as it loaded them.
function Send.modules()
    local Api = package.loaded["goodreads_api"]
    local Identifiers = package.loaded["goodreads_identifiers"]
    if type(Api) ~= "table" or type(Api.set_status) ~= "function" then return nil end
    return Api, (type(Identifiers) == "table" and Identifiers or nil)
end

function Send.available(ui)
    local ok, yes = pcall(function()
        return require("aleph_goodreads").available(ui) and Send.modules() ~= nil
    end)
    return ok and yes or false
end

-- What Aleph would send for `book`: { code, shelf, label, rating, date }.
-- settings: the plugin's (to know the account's shelves); may be nil.
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

-- The link the plugin keeps in the book's sidecar, or nil.
function Send.linked(plugin, path)
    local link
    try(function() link = plugin.settings:readBookSettings(path) end)
    if type(link) == "table" and link.edition_id then return link end
    return nil
end

-- Saves a found book as the plugin's link (as its own Link book does).
function Send.saveLink(plugin, path, data)
    plugin.settings:updateBookSetting(path, {
        edition_id = data.edition_id, book_id = data.book_id, review_id = data.review_id,
        title = data.title, authors = data.authors, goodreads_url = data.goodreads_url, pages = data.pages,
    })
    return Send.linked(plugin, path)
end

-- The Goodreads id or ISBN written in the book (its EPUB's OPF), or the
-- ISBN Aleph read from it.
function Send.identifiers(book, Identifiers)
    local gr_id, isbn
    if Identifiers then
        try(function()
            local map = Identifiers.fromOpf(book.path)
            if map then
                gr_id = Identifiers.goodreadsIdFromMap(map)
                isbn = Identifiers.isbnFromMap(map)
            end
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
function Send.send(plugin, Api, book, link, payload)
    Api.settings = Api.settings or plugin.settings
    local id = link.edition_id
    local backend = Api._get_backend and Api:_get_backend() or nil
    local result
    if not payload.code then return false, {}, "no-status" end
    if payload.shelf == "read" and backend and backend._add_to_shelf and backend.set_date_finished then
        -- The plugin's set_status would date the reading today; the book's
        -- own finished day is sent instead.
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
    local sent = { status = payload.label }
    if payload.rating then
        local r = Api:set_rating(id, payload.rating)
        if r and r.ok then sent.rating = payload.rating
        else sent.rating_error = r and r.error_text or "rating" end
    end
    -- What the plugin keeps of the book's Goodreads state.
    try(function()
        local update = { status = payload.code, shelf = payload.shelf }
        if sent.rating then update.rating = sent.rating end
        plugin.settings:updateBookSetting(book.path, update)
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
    local _ = require("gettext")
    local GR = require("aleph_goodreads")
    local ui = browser.plugin and browser.plugin.ui
    local plugin = GR.plugin(ui)
    local Api, Identifiers = Send.modules()
    if not (plugin and Api) then return browser:message(_("The Goodreads plugin could not be found.")) end
    local has_cookie = false
    try(function() has_cookie = plugin.settings:hasCookie() end)
    if not has_cookie then
        return require("aleph_confirm").show{
            title = _("Send to Goodreads"),
            text = _("The Goodreads plugin is not signed in. Send its cookie from your computer first (Settings → Library → Goodreads sign-in)."),
            ok_label = _("Open"), cancel_label = _("Close"),
            on_ok = function() GR.open(ui) end,
        }
    end
    require("ui/network/manager"):runWhenOnline(function()
        Api.settings = plugin.settings
        local link = Send.linked(plugin, book.path)
        if link then return Send.confirm(browser, plugin, Api, book, link) end
        local ok, found = busy(_("Looking for the book on Goodreads…"), function() return Send.find(book, Api, Identifiers) end)
        if not ok or not found then return browser:message(_("Goodreads could not be reached. Check the connection and try again.")) end
        if found.book then
            local saved = Send.saveLink(plugin, book.path, found.book)
            return Send.confirm(browser, plugin, Api, book, saved)
        end
        Send.choose(browser, plugin, Api, book, found.choices or {}, Send.query(book))
    end)
end

-- Offers search results in the book page's sheet.
function Send.choose(browser, plugin, Api, book, list, query)
    browser.detail_sheet = { kind = "goodreads-pick", choices = list, query = query, page = 1,
        on_pick = function(data)
            local saved = Send.saveLink(plugin, book.path, data)
            Send.confirm(browser, plugin, Api, book, saved)
        end,
        on_search = function()
            local _ = require("gettext")
            browser:input(_("Search on Goodreads"), query, function(q)
                q = (q or ""):gsub("^%s+", ""):gsub("%s+$", "")
                if q == "" then return end
                local ok, more = busy(_("Searching Goodreads…"), function() return Api:search(q) end)
                Send.choose(browser, plugin, Api, book, ok and more or {}, q)
            end, _("Search"))
        end,
    }
    browser:updateItems()
end

-- The sheet's model for the choices (Browser:detailSheetModel).
function Send.sheetModel(sheet, book)
    local _ = require("gettext")
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
function Send.confirm(browser, plugin, Api, book, link)
    local _ = require("gettext")
    local T = require("ffi/util").template
    local p = Send.payload(book, plugin.settings)
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
    lines[#lines + 1] = _("What Goodreads has for this book is replaced.")
    require("aleph_confirm").show{
        title = _("Send to Goodreads"), text = table.concat(lines, "\n"), lines = 16,
        ok_label = _("Send"),
        extra_label = _("Not this book? Choose another…"),
        on_extra = function()
            -- Wrong match: forget the link and search.
            try(function()
                local GS = plugin.settings
                GS:updateBookSetting(book.path, { edition_id = GS.UNSET, book_id = GS.UNSET, review_id = GS.UNSET,
                    title = GS.UNSET, authors = GS.UNSET, goodreads_url = GS.UNSET, status = GS.UNSET, shelf = GS.UNSET })
            end)
            local ok, list = busy(_("Searching Goodreads…"), function() return Api:search(Send.query(book)) end)
            Send.choose(browser, plugin, Api, book, ok and list or {}, Send.query(book))
        end,
        on_ok = function()
            local ok, done, sent, err = busy(_("Sending to Goodreads…"), function() return Send.send(plugin, Api, book, link, p) end)
            if not ok or not done then
                return browser:message(T(_("Goodreads did not take it.\n%1"), tostring(err or sent or "")))
            end
            if sent.rating_error then
                return browser:message(T(_("Status sent, but the rating was not: %1"), tostring(sent.rating_error)))
            end
            toast(sent.rating and T(_("Sent to Goodreads: %1, %2 stars"), _(sent.status), sent.rating) or T(_("Sent to Goodreads: %1"), _(sent.status)))
        end,
    }
end

return Send
