-- Aleph modification, 2026-11-11: deleting a book from its page.
--[[--
The book's page, ⋯ menu, two ways:

  Delete book, keep its data   only the book's file. Its sidecar (highlights,
                               notes, bookmarks, last page, status, rating)
                               stays where it was: put the same file back in
                               the same place and KOReader picks it up again.
  Delete book and its data     the file and its sidecar, custom cover and
                               custom metadata, as KOReader's own Delete does.

Either way KOReader's reading statistics are kept (they are apart from the
books), a finished book stays on Aleph's record of finished books
(aleph_finished_log.lua), the file browser's cache, history and collections
are told, as KOReader does when it deletes a file, and the book leaves
Aleph's library at once. A book open in the reader is not deleted.
]]

local try = require("aleph_try").call
local Delete = {}

-- Whether `path` is the book open in a reader.
local function openInReader(path)
    local open = false
    try(function()
        local ReaderUI = require("apps/reader/readerui")
        local ui = ReaderUI.instance
        open = ui and ui.document and ui.document.file == path or false
    end)
    return open
end
Delete.openInReader = openInReader

-- Deletes `book` (a library entry). with_data: its sidecar too. Returns
-- true, or false and why ("open", "missing" or the error).
function Delete.run(lib, book, with_data)
    local path = book and book.path
    if type(path) ~= "string" then return false, "missing" end
    if openInReader(path) then return false, "open" end
    local lfs = require("libs/libkoreader-lfs")
    if lfs.attributes(path, "mode") ~= "file" then return false, "missing" end
    -- On the record first: a finished book keeps counting.
    try(function() require("aleph_finished_log").update(book) end)
    local ok, err = os.remove(path)
    if not ok then return false, tostring(err) end
    try(function() require("ui/widget/booklist").resetBookInfoCache(path) end)
    if with_data then
        -- KOReader's own clean-up after a delete: the sidecar folder, a
        -- custom cover and custom metadata.
        try(function() require("docsettings").updateLocation(path) end)
    end
    try(function() require("readhistory"):fileDeleted(path) end)
    try(function() require("readcollection"):removeItem(path) end)
    -- Out of Aleph's library now, not at the next scan.
    if lib and type(lib.books) == "table" then
        for i = #lib.books, 1, -1 do
            if lib.books[i].path == path then table.remove(lib.books, i) end
        end
        lib._group_cache = nil
        try(function()
            if lib.touch then lib:touch() end
            if lib.saveIndex then lib:saveIndex() else
                lib.cache:saveSetting("books", lib.books)
                lib.cache:flush()
            end
        end)
    end
    return true
end

return Delete
