local PluginLoader = require("pluginloader")
local datetime = require("datetime")
local logger = require("logger")
local _ = require("gettext")

local Book = {}

local function positive(value)
    value = tonumber(value)
    if value and value > 0 and value < math.huge then return value end
end

function Book.summary(ui)
    local props = ui.doc_props or {}
    local footer = ui.view and ui.view.footer
    local current = footer and positive(footer.pageno)
    local total = footer and positive(footer.pages)
    local progress = current and total and current / total
    if progress and footer.getBookProgress then
        local ok, ratio = pcall(footer.getBookProgress, footer)
        if ok and type(ratio) == "number" and ratio == ratio then progress = ratio end
    elseif ui.doc_settings then
        progress = tonumber(ui.doc_settings:readSetting("percent_finished"))
    end
    if progress and progress == progress then progress = math.max(0, math.min(1, progress))
    else progress = nil end

    local read_time, remaining
    local stats = ui.statistics
    if stats and stats.settings and stats.settings.is_enabled and stats.id_curr_book then
        local function duration(seconds)
            return datetime.secondsToClockDuration("classic", seconds, true)
        end
        local seconds = (tonumber(stats.book_read_time) or 0) + (tonumber(stats.mem_read_time) or 0)
        if seconds > 0 and seconds < math.huge then
            read_time = string.format(_("Read: %s"), duration(seconds))
        end
        local average = positive(stats.avg_time)
        if average and total and progress and read_time then
            remaining = string.format(_("Remaining: %s"), duration(total * (1 - progress) * average))
        end
    end

    local cover
    if ui.bookinfo and ui.bookinfo.getCoverImage then
        local ok, image = pcall(ui.bookinfo.getCoverImage, ui.bookinfo, ui.document)
        if ok then cover = image end
    end
    return {
        title = props.title and props.title ~= "" and props.title
            or ui.document.file:match("[^/]+$") or _("Book information"),
        authors = props.authors,
        tags = props.keywords,
        progress = progress,
        current = current,
        total = total,
        times = read_time and remaining and (read_time .. " / " .. remaining) or read_time,
        cover = cover,
    }
end

local function showBookshelf(ui)
    local repository = require("lib/bookshelf_book_repository")
    local widget = require("lib/bookshelf_widget")
    if type(repository.buildBook) ~= "function" or type(widget._showBookDetail) ~= "function" then
        return false
    end
    local book = repository.buildBook(ui.document.file)
    if not book then return false end

    -- The modal uses methods from the shelf widget. A detached host can
    -- provide them without starting the shelf or replacing the open reader.
    local host = setmetatable({
        _rebuild = function() end,
        _openBook = function() end, -- This is already the open book.
    }, { __index = widget })
    host:_showBookDetail(book)
    return true
end

function Book.showDetails(ui)
    -- Aleph's book page, when it is installed and has the book.
    local board = PluginLoader:getPluginInstance("aleph")
    if board and type(board.showBookPage) == "function" then
        local ok, shown = pcall(board.showBookPage, board, ui.document.file)
        if ok and shown then return end
        if not ok then logger.warn("QuickTopBar: could not open Aleph's book page", shown) end
    end
    if PluginLoader:getPluginInstance("bookshelf") then
        local ok, shown = pcall(showBookshelf, ui)
        if ok and shown then return end
        if not ok then logger.warn("QuickTopBar: could not open Bookshelf book details", shown) end
    end
    if ui.bookinfo then ui.bookinfo:onShowBookInfo() end
end

return Book
