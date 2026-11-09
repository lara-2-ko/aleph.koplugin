-- Modified for Aleph, 2026-11-07. Unofficial local-only fork. See NOTICE.
--[[--
Customizing the widget dashboard.

Hold any widget (or choose Customize dashboard in the menu) to edit. A tap
selects a widget and shows its bar: Earlier, Later, Size, Page and Remove.
There is no dragging, so editing works on e-ink and on D-pad devices alike.
Add widget opens a sheet of live previews.

The first edit turns the starter layout into the reader's own pages for this
column count. Every change is checked against the board's smallest row
height before it is kept, so a page can never hold more than fits.
]]

local T = require("ffi/util").template
local _ = require("gettext")

local BoardLayout = require("aleph_board_layout")
local BoardMetrics = require("aleph_board_metrics")
local BoardStore = require("aleph_board_store")

local px = BoardMetrics.px

local BoardEdit = {}

-- The widgets a reader can add. Sizes are the codes in BoardLayout.sizeDims;
-- the first is the size a new widget gets.
BoardEdit.LIBRARY = {
    { type = "forecast", name = function() return _("Finish forecast") end, desc = function() return _("When your book ends at your pace") end, sizes = { "M", "S", "L" }, tab = "reading", new = true },
    { type = "heatmap", name = function() return _("Year in reading") end, desc = function() return _("One square a day for a whole year") end, sizes = { "XL", "L" }, tab = "stats", new = true },
    { type = "goalpace", name = function() return _("Goal pace") end, desc = function() return _("Ahead or behind on your yearly goal") end, sizes = { "M", "S" }, tab = "stats", new = true },
    { type = "light", name = function() return _("Light") end, desc = function() return _("Brightness and warmth steppers") end, sizes = { "M", "S" }, tab = "device", new = true },
    { type = "word", name = function() return _("Word of the day") end, desc = function() return _("A word you looked up, in context") end, sizes = { "M", "L" }, tab = "reading", new = true },
    { type = "toggles", name = function() return _("Quick settings") end, desc = function() return _("Wi-Fi, light, night mode, rotate, refresh") end, sizes = { "M", "S" }, tab = "device", new = true },
    { type = "records", name = function() return _("Reading records") end, desc = function() return _("Your longest and average sessions") end, sizes = { "L", "M" }, tab = "stats", new = true },
    { type = "hours", name = function() return _("When you read") end, desc = function() return _("Your reading by hour of the day") end, sizes = { "M", "L" }, tab = "stats", new = true },
    { type = "shelf", name = function() return _("Finished this year") end, desc = function() return _("Covers of the books you finished") end, sizes = { "L", "XL" }, tab = "stats", new = true, props = { source = "finished" } },
    { type = "shelf", name = function() return _("Pick back up") end, desc = function() return _("Books you put down a while ago") end, sizes = { "XL", "L" }, tab = "library", new = true, props = { source = "pick-back-up" } },
    { type = "shelf", name = function() return _("Want to read") end, desc = function() return _("Books waiting for their turn") end, sizes = { "L", "XL" }, tab = "library", new = true, props = { source = "want-to-read" } },
    { type = "hero", name = function() return _("Continue reading") end, desc = function() return _("Your current book with Resume") end, sizes = { "W", "M", "L" }, tab = "reading", chrome = "ink" },
    { type = "also", name = function() return _("Also reading") end, desc = function() return _("The rest of your pile") end, sizes = { "L", "M" }, tab = "reading" },
    { type = "highlight", name = function() return _("Highlight of the day") end, desc = function() return _("One of your highlights, daily") end, sizes = { "L", "M", "W" }, tab = "reading", chrome = "fill" },
    { type = "streak", name = function() return _("Streak") end, desc = function() return _("Days in a row, and your best") end, sizes = { "S", "M" }, tab = "stats" },
    { type = "week", name = function() return _("This week") end, desc = function() return _("Minutes read each day") end, sizes = { "M", "S" }, tab = "stats" },
    { type = "today", name = function() return _("Today") end, desc = function() return _("Minutes read today") end, sizes = { "S" }, tab = "stats" },
    { type = "calendar", name = function() return _("Reading calendar") end, desc = function() return _("This month, one square a day") end, sizes = { "M", "L" }, tab = "stats" },
    { type = "shelf", name = function() return _("Up next in series") end, desc = function() return _("The next book in each series you read") end, sizes = { "L", "XL" }, tab = "library", props = { source = "up-next-in-series" } },
    { type = "shelf", name = function() return _("Discover") end, desc = function() return _("A shuffle of your library") end, sizes = { "XL", "L" }, tab = "library", props = { source = "random", shuffle = true } },
    { type = "shelf", name = function() return _("Recently added") end, desc = function() return _("The newest books in your library") end, sizes = { "XL", "L" }, tab = "library", props = { source = "recently-added" } },
    { type = "link", name = function() return _("Library") end, desc = function() return _("All your books") end, sizes = { "S" }, tab = "library", props = { link = "library" } },
    { type = "link", name = function() return _("Series") end, desc = function() return _("Every series") end, sizes = { "S" }, tab = "library", props = { link = "series" } },
    { type = "link", name = function() return _("Authors") end, desc = function() return _("Every author") end, sizes = { "S" }, tab = "library", props = { link = "authors" } },
    { type = "link", name = function() return _("Collections") end, desc = function() return _("Your collections, and how many") end, sizes = { "S" }, tab = "library", props = { link = "collections" } },
    { type = "link", name = function() return _("History") end, desc = function() return _("Books in progress, newest first") end, sizes = { "S" }, tab = "library", props = { link = "history" } },
    { type = "link", name = function() return _("On device") end, desc = function() return _("Books on this device, and space left") end, sizes = { "S" }, tab = "device", props = { link = "device" } },
    { type = "link", name = function() return _("Search") end, desc = function() return _("Search your library") end, sizes = { "S" }, tab = "library", props = { link = "search" } },
    { type = "clock", name = function() return _("Clock") end, desc = function() return _("Time and date, each minute") end, sizes = { "S", "M" }, tab = "device", chrome = "ink" },
    { type = "silverfish", name = function() return _("Silverfish") end, desc = function() return _("Your companion from the Silverfish plugin") end, sizes = { "L", "M" }, tab = "decor", new = true },
    { type = "buddy", name = function() return _("Reading buddy") end, desc = function() return _("A cat that keeps you company") end, sizes = { "L", "M", "S" }, tab = "decor", new = true },
    { type = "buddy", name = function() return _("Reading dog") end, desc = function() return _("A floppy-eared friend for every chapter") end, sizes = { "L", "M", "S" }, tab = "decor", new = true, props = { animal = "dog" } },
    { type = "buddy", name = function() return _("Reading rabbit") end, desc = function() return _("A quiet companion with a curious nose") end, sizes = { "L", "M", "S" }, tab = "decor", new = true, props = { animal = "rabbit" } },
    { type = "buddy", name = function() return _("Reading owl") end, desc = function() return _("A feathered friend for one more page") end, sizes = { "L", "M", "S" }, tab = "decor", new = true, props = { animal = "owl" } },
    { type = "buddy", name = function() return _("Reading penguin") end, desc = function() return _("A little bookworm in a feathered coat") end, sizes = { "L", "M", "S" }, tab = "decor", new = true, props = { animal = "penguin" } },
    { type = "buddy", name = function() return _("Reading robot") end, desc = function() return _("Recharges with a good book") end, sizes = { "L", "M", "S" }, tab = "decor", new = true, props = { animal = "robot" } },
    { type = "buddy", name = function() return _("Reading vampire") end, desc = function() return _("A tiny night owl with a cape and fangs") end, sizes = { "L", "M", "S" }, tab = "decor", new = true, props = { animal = "vampire" } },
    { type = "buddy", name = function() return _("Reading dragon") end, desc = function() return _("A little dragon guarding a hoard of stories") end, sizes = { "L", "M", "S" }, tab = "decor", new = true, props = { animal = "dragon" } },
    { type = "buddy", name = function() return _("Reading ghost") end, desc = function() return _("A friendly spirit between the pages") end, sizes = { "L", "M", "S" }, tab = "decor", new = true, props = { animal = "ghost" } },
    { type = "buddy", name = function() return _("Reading mimic") end, desc = function() return _("A book that reads you back") end, sizes = { "L", "M", "S" }, tab = "decor", new = true, props = { animal = "mimic" } },
    { type = "buddy", name = function() return _("Reading mummy") end, desc = function() return _("Three thousand years of catching up") end, sizes = { "L", "M", "S" }, tab = "decor", new = true, props = { animal = "mummy" } },
    { type = "buddy", name = function() return _("Reading witch") end, desc = function() return _("Never without her spellbook") end, sizes = { "L", "M", "S" }, tab = "decor", new = true, props = { animal = "witch" } },
    { type = "buddy", name = function() return _("Reading skeleton") end, desc = function() return _("Reads to the bone") end, sizes = { "L", "M", "S" }, tab = "decor", new = true, props = { animal = "skeleton" } },
    { type = "buddy", name = function() return _("Reading candle") end, desc = function() return _("Burns the midnight oil") end, sizes = { "L", "M", "S" }, tab = "decor", new = true, props = { animal = "candle" } },
    { type = "buddy", name = function() return _("Reading alien") end, desc = function() return _("Came a long way for a good book") end, sizes = { "L", "M", "S" }, tab = "decor", new = true, props = { animal = "alien" } },
    { type = "chapters", name = function() return _("Chapter line") end, desc = function() return _("Your book as a line, chapters as stops") end, sizes = { "L", "M", "W", "S" }, tab = "decor", new = true },
    { type = "dust", name = function() return _("Gathering dust") end, desc = function() return _("Books you downloaded and never opened") end, sizes = { "M", "L", "S" }, tab = "decor", new = true },
    { type = "rings", name = function() return _("Tree rings") end, desc = function() return _("A ring for every month you read") end, sizes = { "L", "M" }, tab = "decor", new = true },
    { type = "odometer", name = function() return _("Pages turned") end, desc = function() return _("Every page, on a counter") end, sizes = { "M", "S" }, tab = "decor", new = true },
    { type = "glyph", name = function() return _("Glyph of the day") end, desc = function() return _("One letter from your fonts") end, sizes = { "S", "M", "L" }, tab = "decor", new = true },
    { type = "analog", name = function() return _("Analog clock") end, desc = function() return _("A clock face, each minute") end, sizes = { "S", "M" }, tab = "decor", new = true, chrome = "ink" },
    { type = "moon", name = function() return _("Moon phase") end, desc = function() return _("Tonight's moon") end, sizes = { "S", "M" }, tab = "decor", new = true, chrome = "ink" },
}

BoardEdit.TABS = {
    { id = "new", label = function() return _("New") end },
    { id = "reading", label = function() return _("Reading") end },
    { id = "stats", label = function() return _("Stats") end },
    { id = "library", label = function() return _("Library") end },
    { id = "device", label = function() return _("Device") end },
    { id = "decor", label = function() return _("Decor") end },
}

local function sameProps(a, b)
    a, b = a or {}, b or {}
    return a.source == b.source and a.link == b.link and (a.animal or "cat") == (b.animal or "cat")
end

-- The library entry an item came from, for its supported sizes.
function BoardEdit.entryFor(item)
    local picked = item.type == "shelf" and item.props
        and false
    for _i, entry in ipairs(BoardEdit.LIBRARY) do
        if picked and entry.pick then return entry end
        if entry.type == item.type and (entry.type ~= "shelf" and entry.type ~= "link" and entry.type ~= "buddy" or sameProps(entry.props, item.props)) then
            return entry
        end
    end
    return nil
end

function BoardEdit.sizeCode(item, cols)
    for _i, code in ipairs({ "S", "M", "L", "W", "XL" }) do
        local cw, rh = BoardLayout.sizeDims(code, cols)
        if cw == math.min(item.cw, cols) and rh == item.rh then return code end
    end
    return nil
end

local function copyItem(it)
    local props = nil
    if it.props then
        props = {}
        for k, v in pairs(it.props) do props[k] = v end
    end
    return { type = it.type, cw = it.cw, rh = it.rh, chrome = it.chrome, props = props }
end

-- ------------------------------------------------------------- state
function BoardEdit:boardEditing()
    return self.board_edit ~= nil
end

function BoardEdit:boardGeometry()
    local m = BoardMetrics.get()
    local _top, bottom = self:menuChromeHeight()
    return BoardLayout.geometry(px, self.inner_dimen.w, self.inner_dimen.h - bottom, m.LW)
end

-- The pages being edited, as they are currently drawn: the reader's own or
-- the starter layout, fitted to this screen. A saved page that no longer fits
-- (a larger interface size, a shelf grown to two rows) is edited as shown,
-- never as an overfull grid the editor could not change; the widgets it has
-- no room for are kept aside as hidden.
function BoardEdit:boardEditablePages(g)
    local pages = self:boardPages(g.cols)
    local out = {}
    for index = 1, BoardStore.PAGE_COUNT do
        local page = pages[index] or { base = {} }
        local items, hidden = {}, {}
        local packed = BoardLayout.fitPage(g, page.base, page.extras)
        for _i, it in ipairs(packed.placed) do table.insert(items, copyItem(it)) end
        for _i, it in ipairs(packed.dropped) do table.insert(hidden, copyItem(it)) end
        out[index] = { id = page.id, items = items, hidden = hidden }
    end
    return out
end

-- Hidden widgets are saved after the ones on screen, so a smaller interface
-- size shows them again.
function BoardEdit:boardSavePages(g, pages)
    local m = BoardMetrics.get()
    local saved = {}
    for index, page in ipairs(pages) do
        local items = {}
        for _i, it in ipairs(page.items or {}) do table.insert(items, it) end
        for _i, it in ipairs(page.hidden or {}) do table.insert(items, it) end
        saved[index] = { id = page.id, items = items }
    end
    self:persistSetting(BoardStore.SETTING_KEY, BoardStore.withCustomPages(self.settings, g.cols, saved, m.w > m.h))
end

function BoardEdit:boardPageFits(g, items)
    if #items == 0 then return true end
    local packed = BoardLayout.pack(items, g.cols)
    return BoardLayout.rowHeight(g, packed.rows) >= g.min_row
end

function BoardEdit:boardEnterEdit(select_index)
    if not self:dashboardMode() then return end
    local g = self:boardGeometry()
    self.board_edit = {
        pages = self:boardEditablePages(g),
        selected = select_index,
        sheet = false,
        sheet_tab = "new",
        sheet_page = 1,
        cols = g.cols,
    }
    self:updateItems(nil, true)
end

function BoardEdit:boardExitEdit()
    local edit = self.board_edit
    if not edit then return end
    self.board_edit = nil
    if edit.changed then
        self:boardSavePages(self:boardGeometry(), edit.pages)
    end
    self:boardRefreshIfMissing()
end

-- Redraws the board, then fetches the dashboard again only when it now shows
-- a shelf or a list of names the cached body does not hold. Drawing first
-- keeps the screen current while offline; covers stay cached either way.

local function full(text)
    require("aleph_toast").error(text)
end

-- ------------------------------------------------------------- actions
function BoardEdit:boardEditRun(action)
    local edit = self.board_edit
    if not edit then return end
    local g = self:boardGeometry()
    local page = self:boardPage()
    local items = edit.pages[page].items
    local kind = action.kind
    if kind == "edit-done" then
        return self:boardExitEdit()
    elseif kind == "edit-select" then
        edit.selected = edit.selected == action.index and nil or action.index
    elseif kind == "edit-move" then
        local i = edit.selected
        local j = i and i + action.delta
        if i and j and j >= 1 and j <= #items then
            items[i], items[j] = items[j], items[i]
            edit.selected = j
            edit.changed = true
        end
    elseif kind == "edit-size" then
        local it = items[edit.selected or 0]
        if it then
            local cw, rh = BoardLayout.sizeDims(action.code, g.cols)
            local old_cw, old_rh = it.cw, it.rh
            it.cw, it.rh = cw, rh
            if not self:boardPageFits(g, items) then
                it.cw, it.rh = old_cw, old_rh
                return full(_("There is not enough room on this page for that size."))
            end
            edit.changed = true
        end
    elseif kind == "edit-remove" then
        local i = action.index or edit.selected
        if i and items[i] then
            table.remove(items, i)
            edit.selected = nil
            edit.changed = true
        end
    elseif kind == "edit-page" then
        local i = edit.selected
        if i and items[i] then
            local target = page % BoardStore.PAGE_COUNT + 1
            local moved = items[i]
            local dest = edit.pages[target].items
            table.insert(dest, moved)
            if not self:boardPageFits(g, dest) then
                table.remove(dest)
                return full(T(_("%1 is full. Remove a widget there first."), BoardStore.pageNames(edit.pages)[target]))
            end
            table.remove(items, i)
            edit.selected = nil
            edit.changed = true
            full(T(_("Moved to %1."), BoardStore.pageNames(edit.pages)[target]))
        end
    elseif kind == "edit-add" then
        edit.sheet = true
        edit.sheet_page = 1
    elseif kind == "sheet-close" then
        edit.sheet = false
    elseif kind == "sheet-tab" then
        edit.sheet_tab = action.tab
        edit.sheet_page = 1
    elseif kind == "sheet-page" then
        edit.sheet_page = math.max(1, (edit.sheet_page or 1) + action.delta)
    elseif kind == "sheet-add" and action.entry.pick then
        edit.sheet = false
        self:updateItems(nil, true)
        return self:boardPickShelfSource()
    elseif kind == "sheet-add" then
        local entry = action.entry
        local cw, rh = BoardLayout.sizeDims(entry.sizes[1], g.cols)
        local item = { type = entry.type, cw = cw, rh = rh, chrome = entry.chrome or "line", props = entry.props and copyItem(entry).props or nil }
        table.insert(items, item)
        if not self:boardPageFits(g, items) then
            -- Try the smallest size it offers before giving up.
            local smallest = entry.sizes[#entry.sizes]
            item.cw, item.rh = BoardLayout.sizeDims(smallest, g.cols)
            for _i, code in ipairs(entry.sizes) do
                local tcw, trh = BoardLayout.sizeDims(code, g.cols)
                if tcw * trh < item.cw * item.rh then item.cw, item.rh = tcw, trh end
            end
            if not self:boardPageFits(g, items) then
                table.remove(items)
                return full(_("This page is full. Remove a widget first, or add it on another page."))
            end
        end
        edit.sheet = false
        edit.selected = #items
        edit.changed = true
    elseif kind == "edit-pages" then
        return self:boardShowPagesMenu()
    end
    self:updateItems(nil, true)
end

-- Which list to pick a shelf from. The list opens in pick mode: tapping an
-- entry adds it as a shelf instead of opening it.

-- The picked list becomes a full-width shelf on the page being edited.
function BoardEdit:boardAddPickedShelf(source)
    self:onReturn()
    while self.stack and #self.stack > 0 and not self:dashboardMode() do self:onReturn() end
    local edit = self.board_edit
    if not edit or not self:dashboardMode() then return end
    local g = self:boardGeometry()
    local items = edit.pages[self:boardPage()].items
    local params = {}
    for k, v in pairs(source.params or {}) do params[k] = v end
    table.insert(items, { type = "shelf", cw = g.cols, rh = 2, chrome = "line",
        props = { source = source.type, params = params, title = source.sourceName } })
    if not self:boardPageFits(g, items) then
        table.remove(items)
        self:updateItems(nil, true)
        return full(_("This page is full. Remove a widget first, or add it on another page."))
    end
    edit.selected = #items
    edit.changed = true
    -- The new shelf's books are fetched now, not when editing ends.
    self:boardRefreshIfMissing()
end

function BoardEdit:boardShowPagesMenu()
    local DialogUI = require("aleph_dialog_ui")
    DialogUI.actions{
        title = _("Pages"),
        rows = {
            { icon = "rotate-ccw", label = _("Reset this page"), sub = _("Back to how it started"), run = function()
                self:boardResetPage(self:boardPage())
            end },
            { icon = "rotate-ccw", label = _("Reset all pages"), sub = _("Every page back to how it started"), run = function()
                DialogUI.confirm{
                    title = _("Reset all pages?"),
                    text = _("Every page goes back to its starting layout."),
                    ok_label = _("Reset"),
                    on_ok = function() self:boardResetAll() end,
                }
            end },
        },
    }
end

function BoardEdit:boardResetPage(page)
    local edit = self.board_edit
    if not edit then return end
    local g = self:boardGeometry()
    local state = BoardStore.read(self.settings)
    local m = BoardMetrics.get()
    local starter = BoardStore.starterPages(g.cols, state.preset, self:boardHasLight(), m.w > m.h)[page]
    local packed = BoardLayout.fitPage(g, starter.base, starter.extras)
    local items = {}
    for _i, it in ipairs(packed.placed) do table.insert(items, copyItem(it)) end
    edit.pages[page].items = items
    edit.selected = nil
    edit.changed = true
    self:updateItems(nil, true)
end

function BoardEdit:boardResetAll()
    local state = BoardStore.read(self.settings)
    self:persistSetting(BoardStore.SETTING_KEY, BoardStore.withPreset(self.settings, state.preset))
    self.board_edit = nil
    self:boardRefreshIfMissing()
end

-- Shelves a reader picked for the old four-slot dashboard (one library,
-- collection, SmartScope, author or series) carry over onto the board once it
-- has started, on the first page with room for them. The old setting is then
-- dropped, so this runs once. Returns true when it ran.

-- ------------------------------------------------------------- settings
function BoardEdit:boardSetTiles(tiles)
    self:persistSetting(BoardStore.SETTING_KEY, BoardStore.withTiles(self.settings, tiles))
    if self:dashboardMode() then self:updateItems(nil, true) end
end

function BoardEdit:boardSetColour(colour)
    self:persistSetting(BoardStore.SETTING_KEY, BoardStore.withColour(self.settings, colour))
    require("aleph_board_ui").clearSnapshots()
    if self:dashboardMode() then self:updateItems(nil, true) end
end

function BoardEdit.install(Catalog)
    for name, fn in pairs(BoardEdit) do
        if name ~= "install" and type(fn) == "function" and name:match("^board") then
            Catalog[name] = fn
        end
    end
end

return BoardEdit
