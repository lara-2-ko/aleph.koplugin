-- Aleph modification, 2026-11-14: the X-Ray sheet.
--[[--
What Aleph's X-Ray (aleph_xr.lua) shows, in one sheet with two faces:

  The list     the names of the book mentioned up to the page being read,
               the most mentioned first, a few to a page of the sheet. With
               descriptions (aleph_xr_ai.lua) they can be shown as People,
               Places or Other. Under them: Describe with AI, Underline
               names, Find names again.
  A name       what it is (when described), the other ways it is written,
               and its mentions so far: page, chapter and the words around
               each. A mention goes to its place in the book (KOReader's
               "back" returns).

It opens from the reader menu's This book tab, from the X-Ray button of the
text menu (on the name selected), and from a tap on an underlined name.

    Page.open(ui, text)        the list, or the name found in text
    Page.openEntry(ui, index)  one name
]]

local UIManager = require("ui/uimanager")
local T = require("ffi/util").template
local _ = require("aleph_gettext")

local BoardMetrics = require("aleph_board_metrics")
local BoardUI = require("aleph_board_ui")
local MenuUI = require("aleph_menu_ui")
local SheetUI = require("aleph_sheet_ui")
local XR = require("aleph_xr")
local try = require("aleph_try").call

local INK = BoardMetrics.INK
local px = BoardMetrics.px
local text, hstack, space, flex = BoardUI.text, BoardUI.hstack, BoardUI.space, BoardUI.flex
local floor = math.floor

local Page = {}

local function toast(str, o)
    try(function() require("aleph_toast").show(str, o) end)
end

local FILTERS = { "all", "person", "place", "other" }
local function filterLabels()
    return { _("All"), _("People"), _("Places"), _("Other") }
end

-- Which of the filters a name falls under.
local function groupOf(entry)
    if entry.kind == "person" or (not entry.kind and entry.person) then return "person" end
    if entry.kind == "place" then return "place" end
    return "other"
end

local function kindLabel(entry)
    local kind = entry.kind
    if kind == "person" or (not kind and entry.person) then return _("Person") end
    if kind == "place" then return _("Place") end
    if kind == "group" then return _("Group") end
    if kind == "thing" then return _("Thing") end
    return nil
end

-- The names to list: { index, entry, seen, total }, the most mentioned so
-- far first. Names not met yet are left out unless Settings shows them all.
function Page.listed(ui, filter)
    local data = XR.names(ui)
    local out = {}
    if not data then return out end
    local all = XR.spoilers()
    for index, entry in ipairs(data.names) do
        if not entry.hidden and (filter == nil or filter == "all" or groupOf(entry) == filter) then
            local seen, total = XR.count(ui, index)
            if seen > 0 or (all and total > 0) then
                out[#out + 1] = { index = index, entry = entry, seen = seen, total = total }
            end
        end
    end
    table.sort(out, function(a, b)
        if a.seen ~= b.seen then return a.seen > b.seen end
        return a.entry.name < b.entry.name
    end)
    return out
end

-- "‹  2 / 7  ›" under a list that has more than one page.
local function pager(w, page, pages, kind)
    if pages <= 1 then return false end
    local left = MenuUI.iconButton("chevron-left", page > 1 and { kind = kind, delta = -1 } or nil, { size = 20 })
    local right = MenuUI.iconButton("chevron-right", page < pages and { kind = kind, delta = 1 } or nil, { size = 20 })
    return hstack({ w = w }, { flex(0), left, space(px(6), 1),
        text(T(_("%1 / %2"), page, pages), { s = 13, col = INK.g4 }), space(px(6), 1), right, flex(0) })
end

local function pagesOf(count, per)
    return math.max(1, math.ceil(count / per))
end

-- --------------------------------------------------------------- the story
-- Names | Story, under the sheet's title.
local function tabs(w, at)
    return MenuUI.segmented(w, { _("Names"), _("Story") }, at, function(i) return { kind = "tab", view = i == 1 and "list" or "story" } end)
end

-- ----------------------------------------------------------------- the list
local function listBody(sheet, w, max_body)
    local ui = sheet.ui
    local iw = MenuUI.rowsIn(w)
    local items = {}
    if not XR.supported(ui) then
        items[#items + 1] = SheetUI.titleRow(w, _("X-Ray"), sheet.book_title)
        items[#items + 1] = SheetUI.note(w, "info", _("X-Ray works with books KOReader lays out itself (EPUB and the like), not with PDFs or comics."), { lines = 3 })
        return items
    end
    local data = XR.names(ui)
    if XR.scanning(ui) then
        items[#items + 1] = SheetUI.titleRow(w, _("X-Ray"), sheet.book_title)
        items[#items + 1] = SheetUI.note(w, "hourglass", _("Reading the book for its names. This takes a minute or two; you can close this and keep reading."), { lines = 3 })
        return items
    end
    if not data then
        items[#items + 1] = SheetUI.titleRow(w, _("X-Ray"), sheet.book_title)
        items[#items + 1] = tabs(w, 1)
        items[#items + 1] = SheetUI.note(w, "info", _("Aleph can read this book once for its names and where each is mentioned. Nothing is sent anywhere."), { lines = 3 })
        items[#items + 1] = SheetUI.pillRow(w, { { label = _("Find names in this book"), icon = "search", action = { kind = "scan" } } })
        return items
    end
    local listed = Page.listed(ui, sheet.filter)
    local every = sheet.filter == "all" and listed or Page.listed(ui, "all")
    items[#items + 1] = SheetUI.titleRow(w, _("X-Ray"),
        XR.spoilers() and T(_("%1 names in the book"), #every) or T(_("%1 names so far"), #every))
    items[#items + 1] = tabs(w, 1)
    -- The filters, once the names have been described.
    if data.ai then
        local at = 1
        for i, id in ipairs(FILTERS) do if id == sheet.filter then at = i end end
        items[#items + 1] = MenuUI.segmented(w, filterLabels(), at, function(i) return { kind = "filter", filter = FILTERS[i] } end)
    end
    -- As many names as the sheet has room for.
    local per = math.max(3, math.min(7, floor(((max_body or px(600)) - px(300)) / px(62))))
    sheet.per = per
    local pages = pagesOf(#listed, per)
    sheet.page = math.max(1, math.min(sheet.page or 1, pages))
    sheet.pages = pages
    if #listed == 0 then
        items[#items + 1] = SheetUI.note(w, "info",
            #every == 0 and _("No names were found in the pages read so far.") or _("None of this kind in the pages read so far."), { lines = 2 })
    else
        local rows = {}
        for i = (sheet.page - 1) * per + 1, math.min(sheet.page * per, #listed) do
            local it = listed[i]
            local sub = it.entry.about
            if not sub or sub == "" then
                sub = #(it.entry.aliases or {}) > 0 and table.concat(it.entry.aliases, ", ") or nil
            end
            rows[#rows + 1] = MenuUI.row(iw, { label = it.entry.name, data = true, sub = sub, sub_data = true, h = sub and 60 or 52,
                value = tostring(it.seen), chevron = true, action = { kind = "entry", index = it.index } })
        end
        items[#items + 1] = MenuUI.group(w, rows)
        local p = pager(w, sheet.page, pages, "page")
        if p then items[#items + 1] = p end
    end
    local AI = require("aleph_xr_ai")
    local ai_sub
    if AI.busy() then ai_sub = _("Asking… you can keep reading")
    elseif not AI.ready() then ai_sub = _("Needs a provider's key: Aleph's Settings > X-Ray")
    elseif data.ai then ai_sub = T(_("Described at %1% of the book · ask again from here"), data.ai.percent or 0)
    else ai_sub = T(_("Who and what each name is, from what you have read · %1"), AI.config().label) end
    items[#items + 1] = MenuUI.group(w, {
        MenuUI.row(iw, { icon = "sparkles", label = _("Describe with AI"), sub = ai_sub, h = 58, chevron = not AI.busy(), action = { kind = "describe" } }),
        MenuUI.row(iw, { icon = "pen-line", label = _("Underline names"), sub = _("Tap an underlined name to open it"), h = 58,
            toggle = XR.underlined(), action = { kind = "underline" } }),
        MenuUI.row(iw, { icon = "refresh-cw", label = _("Find names again"), sub = _("Reads the book again; descriptions are kept"), h = 58, action = { kind = "rescan" } }),
    })
    return items
end

-- ------------------------------------------------------------------ a name
local function entryBody(sheet, w, max_body)
    local ui = sheet.ui
    local iw = MenuUI.rowsIn(w)
    local data = XR.names(ui)
    local entry = data and data.names[sheet.entry]
    if not entry then return { SheetUI.titleRow(w, _("X-Ray"), nil) } end
    local seen, total = XR.count(ui, sheet.entry)
    local kind = kindLabel(entry)
    local counted = XR.spoilers() and T(_("%1 mentions"), total) or T(_("%1 mentions so far"), seen)
    local items = { SheetUI.titleRow(w, entry.name, kind and (kind .. " · " .. counted) or counted) }
    if entry.about and entry.about ~= "" then
        items[#items + 1] = text(entry.about, { s = 15, w = w, lines = 6, data = true })
    end
    if #(entry.aliases or {}) > 0 then
        items[#items + 1] = text(T(_("Also: %1"), table.concat(entry.aliases, ", ")), { s = 13, col = INK.g4, w = w, lines = 2, data = true })
    end
    local per = math.max(2, math.min(5, floor(((max_body or px(600)) - px(250)) / px(76))))
    sheet.mper = per
    local pages = pagesOf(seen, per)
    sheet.mpage = math.max(1, math.min(sheet.mpage or 1, pages))
    sheet.mpages = pages
    if seen > 0 then
        local rows = {}
        for nth = (sheet.mpage - 1) * per + 1, math.min(sheet.mpage * per, seen) do
            local m = XR.mention(ui, sheet.entry, nth)
            if m then
                local where = m.page and T(_("Page %1"), m.page) or _("Mention")
                if m.chapter and m.chapter ~= "" then where = where .. " · " .. m.chapter end
                local before, name, after = XR.snippet(ui, m.hit)
                local words = before and ("…" .. before .. name .. after .. "…"):gsub("%s+", " ") or nil
                rows[#rows + 1] = MenuUI.row(iw, { label = where, data = true, s = 14, sub = words, sub_data = true, sublines = 2,
                    chevron = true, action = { kind = "goto", nth = nth } })
            end
        end
        items[#items + 1] = MenuUI.group(w, rows)
        local p = pager(w, sheet.mpage, pages, "mpage")
        if p then items[#items + 1] = p end
    end
    items[#items + 1] = SheetUI.pillRow(w, {
        { label = _("All names"), icon = "list", kind = "outline", action = { kind = "list" } },
        { label = _("Not a name"), icon = "eye-off", kind = "outline", action = { kind = "hide" } },
    })
    return items
end

local function previousLabel(prev)
    if prev.title and prev.title ~= "" then return prev.title end
    return T(_("Book %1 of %2"), tostring(prev.index - 1), prev.series)
end

-- The story so far, the book before, and the chapters read.
local function storyBody(sheet, w, max_body)
    local ui = sheet.ui
    local iw = MenuUI.rowsIn(w)
    local Story = require("aleph_xr_story")
    local AI = require("aleph_xr_ai")
    local items = { SheetUI.titleRow(w, _("X-Ray"), sheet.book_title), tabs(w, 2) }
    if not XR.supported(ui) then
        items[#items + 1] = SheetUI.note(w, "info", _("X-Ray works with books KOReader lays out itself (EPUB and the like), not with PDFs or comics."), { lines = 3 })
        return items
    end
    local story = Story.read(ui)
    local told = Story.told(ui)
    if Story.busy() then
        local at = Story.progress()
        items[#items + 1] = SheetUI.note(w, "hourglass",
            at and T(_("Reading the chapters and asking (%1). You can close this and keep reading."), at)
                or _("Reading the chapters and asking. You can close this and keep reading."), { lines = 3 })
    end
    if story.recap and story.recap.text then
        items[#items + 1] = text(story.recap.text, { s = 15, w = w, lines = 11, data = true })
        items[#items + 1] = text(T(_("The story up to page %1 (%2%)"), story.recap.page or "?", story.recap.percent or 0), { s = 12, col = INK.g4, w = w })
    elseif not Story.busy() then
        items[#items + 1] = SheetUI.note(w, "info",
            AI.ready() and _("What happened in each chapter you have read, and the story so far, written by the AI provider set in Settings.")
                or _("Needs a provider's key: Aleph's Settings > X-Ray."), { lines = 3 })
    end
    local rows = {}
    local prev = Story.previous(ui)
    if prev then
        rows[#rows + 1] = MenuUI.row(iw, { icon = "book-open", label = _("The book before"), sub = previousLabel(prev), sub_data = true, h = 58,
            chevron = true, action = { kind = "previous" } })
    end
    local pending = Story.pending(ui)
    local sub
    if Story.busy() then sub = _("Asking…")
    elseif not AI.ready() then sub = _("Needs a provider's key: Aleph's Settings > X-Ray")
    elseif #pending > 0 then sub = T(_("Sends the text of %1 chapters read to %2"), #pending, AI.config().label)
    else sub = _("Up to date with the page you are on") end
    rows[#rows + 1] = MenuUI.row(iw, { icon = "sparkles", label = _("Update the story"), sub = sub, h = 58,
        chevron = not Story.busy() and #pending > 0, action = { kind = "story-update" } })
    items[#items + 1] = MenuUI.group(w, rows)
    if #told > 0 then
        local per = math.max(2, math.min(4, floor(((max_body or px(600)) - px(470)) / px(76))))
        local pages = pagesOf(#told, per)
        -- The chapters read last are shown first.
        sheet.spage = math.max(1, math.min(sheet.spage or pages, pages))
        sheet.spages = pages
        local list = {}
        for i = (sheet.spage - 1) * per + 1, math.min(sheet.spage * per, #told) do
            local c = told[i]
            list[#list + 1] = MenuUI.row(iw, { label = c.title ~= "" and c.title or T(_("Chapter %1"), c.i), data = true, s = 14,
                sub = c.summary, sub_data = true, sublines = 2, chevron = true, action = { kind = "chapter", i = c.i } })
        end
        items[#items + 1] = MenuUI.group(w, list)
        local p = pager(w, sheet.spage, pages, "spage")
        if p then items[#items + 1] = p end
    end
    return items
end

-- The chapters summarised just before and after chapter i, in book order.
local function neighbours(ui, i)
    local before, after
    for _j, c in ipairs(require("aleph_xr_story").told(ui)) do
        if c.i < i and (not before or c.i > before) then before = c.i end
        if c.i > i and (not after or c.i < after) then after = c.i end
    end
    return before, after
end

-- One chapter's summary, whole, with the summaries before and after it.
local function chapterBody(sheet, w)
    local ui = sheet.ui
    local Story = require("aleph_xr_story")
    local found
    for _i, c in ipairs(Story.told(ui)) do
        if c.i == sheet.chapter then found = c end
    end
    if not found then return { SheetUI.titleRow(w, _("X-Ray"), nil) } end
    local before, after = neighbours(ui, found.i)
    -- One row: ‹ The story · Go to chapter ›. The arrows are round
    -- buttons with only a chevron; one with nowhere to go is drawn faint
    -- and does nothing.
    local gap = px(10)
    local h = px(44)
    local function arrow(name, to)
        local b = math.max(1, px(1.5))
        local body = hstack({ w = h - 2 * b, h = h - 2 * b }, { flex(0), BoardUI.icon(name, px(20), { sw = 2.5, col = to and "black" or "gb" }), flex(0) })
        local circle = BoardUI.box({ w = h, h = h, radius = math.floor(h / 2), border = b, border_col = to and INK.black or INK.gb, bg = INK.white }, body)
        return to and BoardUI.hit(circle, { kind = "chapter", i = to }) or circle
    end
    local mid = w - 2 * h - 3 * gap
    local half = math.floor((mid - gap) / 2)
    -- Narrow: the words keep the room, the icons go.
    local icons = half >= px(170)
    local row = hstack({ w = w, gap = gap }, {
        arrow("chevron-left", before),
        MenuUI.pill(_("The story"), { icon = icons and "list" or nil, kind = "outline", w = half, pad_x = 12, action = { kind = "tab", view = "story" } }),
        MenuUI.pill(_("Go to chapter"), { icon = icons and "book-open" or nil, kind = "outline", w = mid - half, pad_x = 12, action = { kind = "chapter-go", page = found.page } }),
        arrow("chevron-right", after),
    })
    return {
        SheetUI.titleRow(w, found.title ~= "" and found.title or T(_("Chapter %1"), found.i),
            found.done and _("What happened") or _("What happened, as far as you read")),
        text(found.summary, { s = 15, w = w, lines = 14, data = true }),
        row,
    }
end

-- The book before this one in its series.
local function previousBody(sheet, w)
    local ui = sheet.ui
    local Story = require("aleph_xr_story")
    local AI = require("aleph_xr_ai")
    local prev = Story.previous(ui)
    if not prev then return { SheetUI.titleRow(w, _("X-Ray"), nil) } end
    local story = Story.read(ui)
    local kept = story.previous
    local items = { SheetUI.titleRow(w, previousLabel(prev), T(_("Before this book · %1"), prev.series)) }
    if Story.busy() then
        items[#items + 1] = SheetUI.note(w, "hourglass", _("Asking. You can close this and keep reading."), { lines = 2 })
    elseif kept and kept.text and kept.text ~= "" then
        items[#items + 1] = text(kept.text, { s = 15, w = w, lines = 15, data = true })
        if kept.known then
            items[#items + 1] = SheetUI.note(w, "info", _("From what the AI model itself knows of that book, by its title. It can be wrong."), { lines = 2 })
        end
    elseif kept then
        items[#items + 1] = SheetUI.note(w, "info", _("The AI model did not know that book well enough to say. Use X-Ray's Story on that book itself for a summary made from its text."), { lines = 4 })
    else
        items[#items + 1] = SheetUI.note(w, "info",
            prev.summaries and _("Written from the chapter summaries kept for that book on this device.")
                or _("That book has no story kept on this device, so the AI model is asked what it knows of it by its title. Nothing of the book is sent, and the answer can be wrong."),
            { lines = 4 })
    end
    local pills = { { label = _("The story"), icon = "list", kind = "outline", action = { kind = "tab", view = "story" } } }
    if not Story.busy() and AI.ready() then
        pills[#pills + 1] = { label = kept and _("Ask again") or _("Ask"), icon = "sparkles", action = { kind = "previous-ask" } }
    end
    items[#items + 1] = SheetUI.pillRow(w, pills)
    return items
end

-- Asks for the story (o: see Story.update) and says how it went.
local function updateStory(sheet, o)
    local ui = sheet.ui
    local Story = require("aleph_xr_story")
    local AI = require("aleph_xr_ai")
    if Story.busy() then return end
    if not AI.ready() then
        return toast(_("Add a provider and its key in Aleph's Settings > X-Ray first."), { icon = "info", timeout = 4 })
    end
    require("ui/network/manager"):runWhenOnline(function()
        local started, why = Story.update(ui, o, function(n, stopped, more)
            if stopped then
                toast(T(_("X-Ray: the story stopped (%1)"), tostring(stopped)), { icon = "info", timeout = 5 })
            elseif more then
                toast(_("X-Ray: part of the story is written. Update again for the rest."), { timeout = 4 })
            else
                toast(_("X-Ray: the story is up to date"))
            end
            if not sheet.closed then sheet.spage = nil; sheet:refresh() end
        end)
        if started == false then
            if why == "nothing new" then toast(_("The story is up to date."))
            elseif why ~= "busy" then toast(_("X-Ray could not start."), { icon = "info" }) end
        end
        if not sheet.closed then sheet:refresh() end
    end)
end

-- --------------------------------------------------------------- actions
local function describe(sheet)
    local ui = sheet.ui
    local AI = require("aleph_xr_ai")
    if AI.busy() then return end
    if not AI.ready() then
        return toast(_("Add a provider and its key in Aleph's Settings > X-Ray first."), { icon = "info", timeout = 4 })
    end
    require("ui/network/manager"):runWhenOnline(function()
        local started, why = AI.describe(ui, function(n, reason)
            if n then toast(T(_("X-Ray: %1 names described"), n))
            else toast(T(_("X-Ray: no descriptions (%1)"), tostring(reason or "?")), { icon = "info", timeout = 5 }) end
            if not sheet.closed then sheet:refresh() end
        end)
        if started == false and why == "no names" then toast(_("No names in the pages read so far."), { icon = "info" }) end
        if not sheet.closed then sheet:refresh() end
    end)
end

local function scan(sheet, keep)
    local ui = sheet.ui
    local started = XR.scan(ui, function(ok)
        if ok then
            local data = XR.names(ui)
            toast(T(_("X-Ray: %1 names found"), data and #data.names or 0))
        else
            toast(_("X-Ray could not read this book."), { icon = "info", timeout = 4 })
        end
        if not sheet.closed then sheet.page = 1; sheet:refresh() end
    end, keep)
    if not started then toast(_("X-Ray could not start."), { icon = "info" }) end
    if not sheet.closed then sheet:refresh() end
end

local function onAction(sheet, action)
    local ui = sheet.ui
    local k = action.kind
    if k == "scan" then
        scan(sheet, false)
    elseif k == "rescan" then
        -- The names are found again; what was said about them is kept for
        -- the names that are found again.
        local old = XR.names(ui)
        local kept = {}
        for _i, entry in ipairs(old and old.names or {}) do
            kept[entry.name] = { kind = entry.kind, about = entry.about, hidden = entry.hidden }
        end
        local ai = old and old.ai
        local started = XR.scan(ui, function(ok)
            local data = ok and XR.names(ui) or nil
            if data then
                for _i, entry in ipairs(data.names) do
                    local was = kept[entry.name]
                    if was then entry.kind, entry.about, entry.hidden = was.kind, was.about, was.hidden end
                end
                data.ai = ai
                XR.save(ui)
                toast(T(_("X-Ray: %1 names found"), #data.names))
            else
                toast(_("X-Ray could not read this book."), { icon = "info", timeout = 4 })
            end
            if not sheet.closed then sheet.page = 1; sheet:refresh() end
        end)
        if not started then toast(_("X-Ray could not start."), { icon = "info" }) end
        sheet:refresh()
    elseif k == "filter" then
        sheet.filter, sheet.page = action.filter, 1
        sheet:refresh()
    elseif k == "page" then
        sheet.page = (sheet.page or 1) + action.delta
        sheet:refresh()
    elseif k == "mpage" then
        sheet.mpage = (sheet.mpage or 1) + action.delta
        sheet:refresh()
    elseif k == "entry" then
        sheet.view, sheet.entry, sheet.mpage = "entry", action.index, 1
        sheet:refresh()
    elseif k == "list" then
        sheet.view = "list"
        sheet:refresh()
    elseif k == "goto" then
        local m = XR.mention(ui, sheet.entry, action.nth)
        sheet:close()
        if m then UIManager:nextTick(function() XR.goTo(ui, m) end) end
    elseif k == "hide" then
        local data = XR.names(ui)
        local entry = data and data.names[sheet.entry]
        if entry then
            entry.hidden = true
            XR.save(ui)
            if ui._aleph_xr then ui._aleph_xr.boxes_key = nil end
        end
        sheet.view = "list"
        sheet:refresh()
    elseif k == "underline" then
        require("aleph_prefs").set("xray_underline", not XR.underlined())
        if XR.underlined() then XR.loadForPage(ui) end
        sheet:refresh()
    elseif k == "describe" then
        describe(sheet)
    elseif k == "tab" then
        sheet.view = action.view
        sheet:refresh()
    elseif k == "spage" then
        sheet.spage = (sheet.spage or 1) + action.delta
        sheet:refresh()
    elseif k == "chapter" then
        sheet.view, sheet.chapter = "chapter", action.i
        sheet:refresh()
    elseif k == "chapter-go" then
        sheet:close()
        UIManager:nextTick(function()
            try(function()
                if ui.link and ui.link.addCurrentLocationToStack then ui.link:addCurrentLocationToStack() end
                ui:handleEvent(require("ui/event"):new("GotoPage", action.page))
            end)
        end)
    elseif k == "previous" then
        sheet.view = "previous"
        sheet:refresh()
    elseif k == "previous-ask" then
        updateStory(sheet, { previous = true, only_previous = true })
    elseif k == "story-update" then
        updateStory(sheet, {})
    end
    return true
end

local function openSheet(ui, view, entry)
    local props = ui.doc_props or {}
    local sheet
    sheet = SheetUI.open{
        name = "aleph_xr",
        ui = ui,
        view = view,
        entry = entry,
        filter = "all",
        page = 1,
        mpage = 1,
        book_title = props.display_title or props.title,
        build = function(page, sw, sh)
            return SheetUI.sheet(page, sw, sh, function(w, max_body)
                if page.view == "entry" then return entryBody(page, w, max_body) end
                if page.view == "story" then return storyBody(page, w, max_body) end
                if page.view == "chapter" then return chapterBody(page, w) end
                if page.view == "previous" then return previousBody(page, w) end
                return listBody(page, w, max_body)
            end, { pop_w = 540 })
        end,
        on_action = onAction,
        -- The page keys and a sideways swipe turn the list's pages.
        on_page_key = function(page, delta)
            if page.view == "entry" then
                local to = (page.mpage or 1) + delta
                if to >= 1 and to <= (page.mpages or 1) then page.mpage = to; page:refresh() end
            elseif page.view == "story" then
                local to = (page.spage or 1) + delta
                if to >= 1 and to <= (page.spages or 1) then page.spage = to; page:refresh() end
            elseif page.view == "chapter" then
                -- The summary before or after this one.
                local before, after = neighbours(page.ui, page.chapter or 0)
                local to = delta < 0 and before or after
                if to then page.chapter = to; page:refresh() end
            elseif page.view ~= "list" then
                return
            else
                local to = (page.page or 1) + delta
                if to >= 1 and to <= (page.pages or 1) then page.page = to; page:refresh() end
            end
        end,
        on_swipe = function(page, ges)
            local delta = ges.direction == "west" and 1 or ges.direction == "east" and -1 or nil
            if not delta then return false end
            page.on_page_key(page, delta)
            return true
        end,
    }
    return sheet
end

-- The story so far; with `update`, asked for at once (the question after a
-- break was answered yes).
function Page.openStory(ui, update)
    local sheet = openSheet(ui, "story")
    if update and sheet then updateStory(sheet, {}) end
    return sheet
end

function Page.openEntry(ui, index)
    return openSheet(ui, "entry", index)
end

-- text: a word or a selection; the sheet opens on its name when it is one.
function Page.open(ui, selected)
    if selected and selected ~= "" then
        local entry, index = XR.find(ui, selected)
        if entry and not entry.hidden then return openSheet(ui, "entry", index) end
        if XR.names(ui) then
            local shown = selected:gsub("%s+", " "):sub(1, 40)
            toast(T(_("No X-Ray entry for “%1”."), shown), { icon = "info" })
            return nil
        end
    end
    return openSheet(ui, "list")
end

return Page
