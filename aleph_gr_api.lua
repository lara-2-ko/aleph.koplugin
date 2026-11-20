-- Aleph modification, 2026-11-18: goodreads_api.lua from advokatb's Goodreads plugin
-- (goodreads.koplugin 0.5.0, MIT licence, see THIRD_PARTY_NOTICES.md), taken into
-- Aleph as aleph_gr_api.lua; changes are marked "Aleph:".
-- goodreads_api.lua
-- API facade for Goodreads. Routes calls to the legacy Rails backend.
-- A second backend can be plugged in later without changing callers.

local _ = require("aleph_gettext") -- Aleph: Aleph's translations

local GoodreadsApiLegacy = require("aleph_gr_legacy")

-- Aleph: N_ marks a text for translation where it is written (it is
-- translated with _ when shown).
local function N_(s) return s end

-- Plugin status codes.
-- Extra exclusive shelves from the account have no fixed code; sidecar uses `shelf`.
local STATUS_KEYS = {
  [0]  = N_("Want to read"),
  [1]  = N_("Finished"),
  [2]  = N_("Currently reading"),
  [3]  = N_("Did not finish"),
}

local SHELF_BY_STATUS = {
  [0] = "to-read",
  [1] = "read",
  [2] = "currently-reading",
  [3] = "did-not-finish",
}

local STATUS_BY_SHELF = {
  ["to-read"]           = 0,
  ["read"]              = 1,
  ["currently-reading"] = 2,
  ["did-not-finish"]    = 3,
}

-- Well-known extra exclusive slug → translated label (only if present on the account).
local KNOWN_EXTRA = {
  ["did-not-finish"] = { label_key = N_("Did not finish") },
  ["paused"]         = { label_key = N_("Paused") },
}

local GoodreadsApi = {
  settings = nil,
  on_error = nil,
}

local function humanize_slug(slug)
  local s = (slug or ""):gsub("%-", " ")
  if s == "" then return slug or "" end
  return s:sub(1, 1):upper() .. s:sub(2)
end

function GoodreadsApi:shelfLabel(shelf_name)
  if not shelf_name or shelf_name == "" then
    return _("Unknown status")
  end
  local code = STATUS_BY_SHELF[shelf_name]
  if code and STATUS_KEYS[code] then
    return _(STATUS_KEYS[code])
  end
  local known = KNOWN_EXTRA[shelf_name]
  if known then
    return _(known.label_key)
  end
  return humanize_slug(shelf_name)
end

function GoodreadsApi:shelfForStatus(status_code)
  return SHELF_BY_STATUS[status_code]
end

function GoodreadsApi:_get_backend()
  local backend = GoodreadsApiLegacy
  backend.settings = self.settings
  backend.on_error = self.on_error
  backend.quiet = self.quiet
  return backend
end

function GoodreadsApi:search(query)
  return self:_get_backend():search(query)
end

function GoodreadsApi:get_book(book_id)
  return self:_get_backend():get_book(book_id)
end

function GoodreadsApi:get_review_state(book_id)
  return self:_get_backend():get_review_state(book_id)
end

--- Set exclusive-shelf status.
-- @param book_id      Goodreads legacy book id
-- @param status       0 / 1 / 2 / 3 (nil when using a custom exclusive shelf)
-- @param _unused      kept for call-site compatibility (no review_id needed)
-- @param rating       Goodreads 1–5 (sent only when the target shelf is `read`)
-- @param shelf_name   exclusive shelf slug (required for custom exclusive shelves)
function GoodreadsApi:set_status(book_id, status, _unused, rating, shelf_name)
  return self:_get_backend():set_status(book_id, status, rating, shelf_name)
end

function GoodreadsApi:set_rating(book_id, rating)
  return self:_get_backend():set_rating(book_id, rating)
end

--- KOReader percent (0–100) → POST /user_status.json. Do not send page at the same time.
function GoodreadsApi:set_progress(book_id, percent)
  return self:_get_backend():set_progress(book_id, percent)
end

return GoodreadsApi
