-- Aleph modification, 2026-11-18: goodreads_identifiers.lua from advokatb's Goodreads plugin
-- (goodreads.koplugin 0.5.0, MIT licence, see THIRD_PARTY_NOTICES.md), taken into
-- Aleph as aleph_gr_ids.lua; changes are marked "Aleph:".
-- goodreads_identifiers.lua
-- Extract a Goodreads book id and ISBN from an EPUB's OPF
-- (META-INF/container.xml + content.opf from the EPUB zip).
-- Aleph: only from the file (aleph_goodreads_send.lua also reads Calibre's
-- metadata.opf beside the book); the plugin also read the open document.

local logger = require("logger")

local GoodreadsIdentifiers = {}

local function trim(s)
  return s and s:match("^%s*(.-)%s*$") or ""
end

function GoodreadsIdentifiers.goodreadsIdFromMap(map)
  if not map then return nil end
  local id = map.goodreads or map["goodreads-id"] or map.gr
  if id and id:match("^%d+$") then
    return id
  end
  return nil
end

local function digits_only(s)
  return (tostring(s or ""):gsub("[%s%-]", ""))
end

--- ISBN-13 preferred, else ISBN-10. Hyphens/spaces stripped.
function GoodreadsIdentifiers.isbnFromMap(map)
  if not map then return nil end
  -- Aleph: by name (ipairs over a list with holes stopped at the first missing one).
  for _, key in ipairs({ "isbn13", "isbn-13", "isbn_13", "isbn", "isbn10", "isbn-10", "isbn_10" }) do
    local n = digits_only(map[key])
    if n:match("^%d%d%d%d%d%d%d%d%d%d%d%d%d$") or n:match("^%d%d%d%d%d%d%d%d%d[%dXx]$") then -- Aleph: Lua patterns have no {n}
      return n
    end
  end
  return nil
end

local function isEpubPath(path)
  if not path or path == "" then return false end
  local lower = path:lower()
  return lower:match("%.epub$") or lower:match("%.epub%.zip$")
end

local function findArchiveEntry(arc, wanted)
  local wanted_lower = wanted:lower():gsub("\\", "/")
  for _, entry in ipairs(arc.entries or {}) do
    if type(entry) == "table" and entry.path then
      local p = entry.path:gsub("\\", "/"):lower()
      if p == wanted_lower or p:sub(-#wanted_lower) == wanted_lower then
        return entry.path
      end
    end
  end
  return nil
end

local function readZipEntry(filepath, inner_path)
  local ok, Archiver = pcall(require, "ffi/archiver")
  if not ok or not Archiver or not Archiver.Reader then
    logger.dbg("Goodreads: ffi/archiver not available")
    return nil
  end

  local arc = Archiver.Reader:new()
  if not arc:open(filepath) then
    logger.dbg("Goodreads: failed to open EPUB zip: " .. tostring(filepath))
    return nil
  end

  for _ in arc:iterate() do end

  local key = findArchiveEntry(arc, inner_path) or inner_path
  local content = arc:extractToMemory(key)
  arc:close()
  return content
end

local function parseOpfIdentifiers(opf_xml)
  local map = {}
  if not opf_xml or opf_xml == "" then return map end

  for tag in opf_xml:gmatch("<dc:identifier[^>]*>.-</dc:identifier>") do
    local inner = tag:match(">(.-)<") or ""
    local value = trim(inner:gsub("%s+", " "):gsub("<[^>]+>", ""))
    if value ~= "" then
      local scheme = tag:match('[sS]cheme=["\']([^"\']+)["\']')
      if not scheme then
        scheme = tag:match('%sid=["\']([^"\']+)["\']')
      end
      if scheme then
        map[scheme:lower()] = value
      end
      local prefixed_scheme, prefixed_value = value:match("^([%w_%-]+):(%S+)$")
      if prefixed_scheme and prefixed_value then
        map[prefixed_scheme:lower()] = prefixed_value
      end
    end
  end
  return map
end

function GoodreadsIdentifiers.fromOpf(filepath)
  if not isEpubPath(filepath) then return nil end

  local container = readZipEntry(filepath, "META-INF/container.xml")
  if not container then return nil end

  local opf_path = container:match('full%-path=["\']([^"\']+)["\']')
  if not opf_path or opf_path == "" then
    logger.dbg("Goodreads: container.xml has no rootfile path")
    return nil
  end

  local opf = readZipEntry(filepath, opf_path)
  if not opf then
    logger.dbg("Goodreads: failed to read OPF " .. opf_path)
    return nil
  end

  return parseOpfIdentifiers(opf)
end

return GoodreadsIdentifiers
