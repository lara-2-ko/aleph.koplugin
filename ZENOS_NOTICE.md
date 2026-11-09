# ZenOS notice

Parts of this plugin are adapted from ZenOS (the `zenos.koplugin` package),
which is licensed under the GNU General Public License, version 3. The full
license text accompanies this package as `LICENSE-GPL-3.0.md`.

Adapted files (each carries a header saying so):

- `aleph_handles.lua` — from `modules/reader/highlight_handles.lua`: the
  drag posts at both ends of a highlight or a new selection (hit testing, the
  draft copy that is committed on release, corner scrolling, paging and
  scroll-mode support).
- `aleph_viewport.lua` — from `modules/reader/highlight_viewport.lua`:
  the text area the posts may move within.
- `aleph_pins.lua` — the structure of the pinned-pages badge (painted by
  ReaderView, reached through touch zones, KOReader's own pin actions routed
  to these pins) follows `modules/reader/pin_footer.lua` and
  `modules/reader/references.lua`. The look and the code are Reading Board's.
- `aleph_page_browser.lua` (2026-11-09) — after
  `modules/reader/patches/page_browser.lua` and
  `modules/reader/page_browser_widget.lua`: the Kindle-style page browser
  (tabs above, a three-page carousel with the middle page two thirds of the
  screen wide, the chapter and "Page X of Y · Z%" with grid and search, a
  slider between chevrons), the bottom swipe zone with its overrides, and the
  location-stack jump. Drawn with Reading Board's parts instead of ZenOS's
  widgets and KOReader's PageBrowserWidget; the tabs open Reading Board's own
  pages.
- `aleph_bookends.lua` (2026-11-09) — after
  `modules/reader/patches/reader_top_status_bar.lua`: a three-zone header
  painted after ReaderView, in page view only. Its items, sizes and look are
  Reading Board's (see THIRD_PARTY_NOTICES.md for Bookends).
- `aleph_highlight.lua`, `aleph_panel.lua` — the hooks that feed
  the posts (tap guard after a drag, closing with the selection or document).

Changes from ZenOS: the posts attach to Reading Board's menu panel, not to a
KOReader ButtonDialog; the panel draws them and gives them every touch first,
and hides itself while a post is dragged; colors, sizes and menus follow Reading
Board. These files are not BookOrbit material and are not subject to
BookOrbit's additional terms; the rest of the plugin is unchanged in its
licensing.
