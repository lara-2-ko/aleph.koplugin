# Aleph (formerly Reading Board) — modifications, 2026-11-07 to 2026-11-09

## 2026-11-09 — 1.0.0 first release

- Version 1.0.0, kept in one place (`aleph_prefs.lua` VERSION, and
  `_meta.lua` so KOReader's plugin list shows it); Settings, the menu and
  About read it from there. README rewritten at the top for the release.
- `_meta.lua` no longer has a `name` field: KOReader takes the plugin's name
  from main.lua and logged a deprecation warning for it.
- **Faster:**
  - The minute's clock and a battery change redraw only the status corner
    (`BoardUI.refreshStatus`), not the whole board; the page is rebuilt
    only on a new hour (greeting, buddy, date) or when it shows a clock
    tile.
  - Board books are kept between redraws for the same dashboard instead of
    copying every book of the library on each one; "last read" is worked
    out when shown. The year heatmap is kept until the day or the
    statistics change.
  - Library queries test the cheap conditions first and keep each book's
    lower-cased search text between queries (not in the index file).
  - Text fitting (`BoardUI.fitSize`) remembers its answers, so lists do not
    measure the same labels again on every refresh.
  - Page margins: their settings are kept until saved (`Bookends.current`)
    instead of copied twice per page turn, and the chapter marks are worked
    out once per book and drawn as plain rectangles.
  - The icon drawings moved to `aleph_icon_data.lua`, loaded only when an
    icon file has to be written; once the icons in use are cached, they are
    never loaded.
- Final check: every file compiles, no accidental globals, no missing or
  unreferenced modules, no unused locals, no leftover debug output; all 26
  stub tests pass (new: board data, status corner, text fitting, icons).
## 2026-11-09 — 0.1.66 crash at startup with Aleph dialogs on

- **The crash** (crash.log: blitbuffer.lua:601 "attempt to index local
  'color' (a nil value)", from aleph_theme.lua, when KOSyncthing+ showed a
  message right after KOReader started): the dialog-border hook compared a
  frame's colour with nil. KOReader's colours are cdata with their own
  comparison, which fails when the other side is nil, and on a colour screen
  the frame's colour is such a value. The border colour is now read as a gray
  level (`Theme.isBlackBorder`) and never compared with ==, and the hook is
  wrapped so it can never stop a window from opening.

## 2026-11-09 — 0.1.65 KOReader's own windows in Aleph's style

Everything Aleph already restyled stays as it was; this reaches the
KOReader windows it had not touched.

- **`aleph_theme.lua`**, a style layer over the parts KOReader builds its
  windows from, so info messages, questions, button dialogs, text input,
  number and date pickers, the text viewer, sort lists, notifications,
  check boxes and the title bars of full pages come out in Aleph's style:
  - KOReader's named UI fonts at Aleph's sizes (same Noto Sans; book text,
    the status bar's fonts and the keyboard untouched), including the fonts
    some widget classes fetched at startup;
  - Aleph's rounder corners for windows and buttons;
  - a light gray rule under title bars, a gray border around dialogs;
  - close, chevrons, check, plus, edit, info, question, warning, bookmark
    and move arrows drawn with Aleph's icons.
  Nothing is built twice and nothing is copied: only sizes, fonts and icon
  files change, before a window is built. Follows Settings > Opening >
  Aleph dialogs (off puts KOReader's values back) and the interface size.
- **Sheets cost less memory.** A sheet's dimmed background was a full copy
  of the screen at the screen's depth; it is now kept in gray, a quarter of
  the size on a colour screen (about 2 MB instead of about 8.5 MB on a
  Colorsoft), drawn back by KOReader's fast blitter.

## 2026-11-09 — 0.1.64 Top menu settings in Aleph

- **Settings > Top menu** replaces KOReader's Tools > QuickTopBar entry
  (removed): the Controls and Apps tabs on or off (moved from Opening),
  Apps, Outline around icons, the Controls and Apps tab icons (with a
  preview of the one in use), and the brightness and warmth slider styles
  as segmented controls. Same stored values as before ("quicktopbar").
- **Apps page** (`aleph_topmenu_page.lua`): every app with its icon, a
  toggle to show or hide it and a pencil to change its icon; an Order mode
  moves apps with arrows. Replaces KOReader's checklist, its sort list and
  the per-app icon submenu.
- **Icon picker** rebuilt as an Aleph page: header with search, a filter
  chip with Clear, rounded tiles with the one in use checked, Aleph's pager
  and swipes. Replaces aleph_topbar_icon_grid.lua (removed).
- A held app in the Apps tab opens an Aleph sheet (Change icon, Hide app)
  instead of KOReader's button dialog; Restart asks in Aleph's dialog.
- **Top menu over Settings:** Aleph's full pages took every swipe, so
  nothing could open KOReader's top menu while Settings (or another full
  page) was open. A swipe down from the top edge now opens it, as on the
  board.
- New icons: arrow-up, pencil, panel-top, square.

## 2026-11-09 — 0.1.63 picture pins found again after the rename

- **Picture pins showed "…" forever.** A picture pin keeps the path of its
  saved picture, and pins made before 0.1.60 pointed into
  cache/readingboard/pins, which the rename moved to cache/aleph/pins.
  `Pins.imageFile` now finds such a picture by its file name in the new
  folder and corrects the path in the book's settings.
- **No more retry loop:** a picture that cannot be loaded was decoded again
  on every redraw of the drawer (13 failed attempts in one log). It is now
  tried once; the drawer says the file is missing, and tapping the picture
  no longer tries to open it full screen.
- **Removing a pin** showed the removed pin's picture for the next one (the
  drawer kept pictures by place in the list); pictures are drawn again from
  the new list.

## 2026-11-09 — 0.1.62 code review: faster board, less memory

- **Library scan only reads what changed.** Opening the board scanned every
  book's KOReader sidecar each time. Each entry now remembers its sidecar's
  stamp; an unchanged book is taken from the index as it is, so a scan of an
  unchanged library is a file-date check per book. When nothing visible
  changed, the board is neither rebuilt nor redrawn and the index file is not
  written.
- **Statistics answers are kept** until KOReader's statistics database (or
  its write-ahead log) changes: the whole-history query behind the streak,
  the heatmap, hours, records and the finish forecast no longer runs on
  every board build.
- **Cover cache bounded by memory**, 12 MB as well as 48 covers, least
  recently drawn first (it was first-in first-out by count only).
- **The bottom reader menu** keeps only the few fields it shows of each book
  for the reading session, instead of the whole library index with every
  highlight and description.
- **Memory handed back** after the board, the page browser and the pin
  drawer close (a garbage collection once the screen underneath is drawn).
- **Clean-up:** 25 unused requires and dead locals removed (fewer modules
  loaded at startup); six copies of the "Aleph style for dialogs" check now
  share `aleph_prefs.lua`.
- Checked: every file compiles, no accidental globals, every Aleph module
  required exists, 19 stub tests pass (new: incremental scan, statistics
  memo, picture memory).

## 2026-11-09 — 0.1.61 picture pins no longer run KOReader out of memory

- **The crash** (crash.log ending in "Killed", after closing a picture pin):
  the pin drawer, the page browser and the reader sheet rebuild their
  widgets on every refresh, and each picture widget made its own scaled copy
  of the bitmap that was never freed. Zoomed in on a picture pin the copy was
  the whole picture at up to 4× (tens of megabytes) per step or swipe; the
  page browser left about three screen-size copies per page turned. Memory
  piled up until the next big allocation got KOReader killed.
- **`aleph_picture.lua`**: draws only the part of a bitmap that shows, at the
  size it fills (a zoomed picture now costs about its size on screen), and
  frees each screen's pictures before it is rebuilt and when it closes.
- **Picture pins** are decoded once and kept no bigger than the screen (the
  full-screen viewer: 1.5× the screen), instead of at the photo's full size.

## 2026-11-09 — 0.1.60 the folder and files renamed to Aleph

- **Folder and files:** `readingboard.koplugin` → `aleph.koplugin`, every
  `readingboard_*.lua` → `aleph_*.lua`, `readingboard_pets/` → `aleph_pets/`,
  `icons/tab-readingboard.svg` → `icons/tab-aleph.svg`. Inside: the plugin
  name, settings key, events, gesture actions (`aleph_open`, `aleph_pins`,
  `aleph_page_browser`, `aleph_this_book`), widget names, cache folder
  (`cache/aleph`) and library index (`settings/aleph_index.lua`).
- **Migration** (`aleph_migrate.lua`), run before anything reads a setting:
  copies the `readingboard` settings to `aleph`; renames
  `settings/readingboard_index.lua` and `cache/readingboard`; renames
  `readingboard_*` actions in the Gestures plugin's bindings (reader and file
  browser); moves a book's `readingboard_pins` to `aleph_pins` when it is
  opened. Nothing is deleted except the moved pins key.
- If `readingboard.koplugin` is still installed alongside, a one-time message
  asks to delete it.

## 2026-11-09 — 0.1.59 finding X-Ray, KOSyncthing+ and Reading insights

- **One way to find other plugins** (`aleph_plugins.lua`), the way
  Reading log does and more: the reader or file browser Aleph is on, then
  every open ReaderUI / FileManager, by the plugin's name and among their
  modules by the names KOReader gives them ("xray", "readerxray",
  "filemanagerxray"); then PluginLoader; then, if the plugin's code is
  loaded, its gesture actions through the Dispatcher with the reader /
  file browser listening. A miss is logged with what was searched.
- **X-Ray** (`aleph_xray.lua`): found that way; with only its code
  loaded, a stand-in runs its actions (xray_characters, xray_timeline,
  xray_historical_figures, xray_locations, xray_terms,
  xray_open_image_gallery, xray_full_menu), so the X-Ray row, its sheet and
  the author link show whenever X-Ray is installed and on.
- **KOSyncthing+** (`aleph_integrations.lua`), names from its source
  (kosyncthing_plus.koplugin: isRunning, runManualStart, onSyncthingQuickSync,
  _G.KOSyncthingPlusAPI, toggle_syncthing_server, syncthing_quick_sync):
  found the same way, then its public API, then its actions. The Quick
  controls button now **syncs**: while Syncthing runs it asks for a quick
  sync ("Syncing now…"); while it does not, it starts it (which syncs).
- Reading insights uses the same lookup.

Checked: every file parses; KOSyncthing+ found by module name, through its
API and through its actions (start and quick sync), X-Ray found by module
name and as a stand-in, Reading insights unchanged, all with stand-in
objects. Not tested on a device.

## 2026-11-09 — 0.1.58 the plugin is now called Aleph

- Every name shown to the reader says **Aleph** instead of Reading Board:
  the Tools entry, page and sheet titles, settings, the reader menu, gesture
  action titles ("Aleph: open", "Aleph: this book", "Aleph: page browser",
  "Aleph: pinned pages"), messages and the plugin manager (`_meta.lua`:
  fullname and description). The portrait lookup's user agent says Aleph.
- Kept on purpose: the folder `aleph.koplugin`, the plugin and module
  names, the settings key `aleph`, gesture action ids, cache folders
  and file names, so settings, layouts, pins, shortcuts and gestures carry
  over.
- Icon (`icons/tab-aleph.svg`): the filled tile on the right page is
  now a four-pointed star, the aleph, the point where everything is seen.
- README and NOTICE say so; older entries below keep the old name.

Checked: every file parses; no "Reading Board" is left in any Lua file.

## 2026-11-09 — 0.1.57 Reading Board button in the reader's top menu

- In a book, the top menu (with the Quick Top Bar on) has a Reading Board
  tab just before KOReader's main menu tab (`aleph_topbar.lua`). It is
  a button: a tap closes the menu and opens Reading Board's settings over
  the book (`QuickTopBar.openBoardSettings`); the board opened underneath
  closes with them, so Back returns to the page. Hooked in
  TouchMenu:switchMenuTab; other tabs are unchanged.
- New icon `icons/tab-aleph.svg`, the plugin's mark: an open book
  with a ribbon bookmark and one filled tile of the board on its right page,
  drawn on Lucide's 24-unit grid and 2-unit stroke like the other tab icons.

Checked: the file parses. Not tested on a device.

## 2026-11-09 — 0.1.56 X-Ray in the reader menu

- **X-Ray sheet** (`aleph_xray.lua`), when the X-Ray plugin
  (xray.koplugin) is installed and on: six tiles, two to a row, each with
  its icon, name and how many entries X-Ray has — Characters, Timeline,
  Historical Figures, Locations, Glossary, Images & Maps — then About the
  author and All X-Ray options (its full menu: fetch, update, settings).
  Without X-Ray data yet, a note and Fetch X-Ray data sit above the tiles.
  Each opens X-Ray's own view after the sheet closes; only X-Ray's methods
  are called, guarded.
- **Reader menu** (`aleph_reader_sheet.lua`): This book gains an
  X-Ray row under Book details (with "42 characters · 12 locations"), and
  the author's name at the top, with a chevron, opens X-Ray's author info.
  Without X-Ray neither appears.
- Icons users, map-pin, landmark and image added (Lucide).

Checked: every file parses; the X-Ray row, its summary, the sheet, a tile
and the author link tested with stand-in objects. Not tested on a device.

## 2026-11-09 — 0.1.55 book margins: stats at the top and bottom of pages

- **Book margins** (`aleph_bookends.lua`): a header and a footer
  painted after ReaderView in the page's margins, each with left, middle
  and right slots of up to three items joined by " · ": progress, page,
  page of pages, pages / time left in the chapter, time left in the book,
  chapter, title, author, clock, date, battery (the board's drawn battery),
  Wi-Fi, front light, time read this sitting. Optional line under the top:
  a hairline with the read part inked, or with chapter ticks. Defaults copy
  the Bookends layout in the photos (progress · clock · battery over a
  progress line; time left in chapter · this sitting · time left in book).
  Page view only (as ZenOS's header); never in the forked thumbnail
  renderer; KOReader's own status bar can be hidden (applyFooterMode off).
  Nothing is painted while the Bookends plugin is on.
- A minute tick (aligned to the clock's minute) repaints the two bands whole,
  page included, and only while the reader is uncovered: no old clock is left
  beside a new one (the ghost clock seen with Bookends).
- **Settings** (`aleph_bookends_page.lua`): a page with a live preview
  of a book page and tabs Top / Bottom / Look; a slot opens a sheet of chips,
  tapped in the order to show them (up to three). Opened from Settings >
  Book margins and from a book's Tools > Book margins (pinned under Reading
  Board); in a book the page follows each change.
- The pin badge sits above the bottom line when it shows.
- Designs from Bookends 5.31 and ZenOS; see THIRD_PARTY_NOTICES.md and
  ZENOS_NOTICE.md.

Checked: every file parses; every item's value, time formats, slots and
their limits, line ticks, staying off while Bookends is on, the repaint
regions and the settings page (tabs, picker, reset) tested with stand-in
objects. Not tested on a device.

## 2026-11-09 — 0.1.54 Controls tab: room under the status line

- Quick Top Bar's Controls tab (`aleph_topbar_panel.lua`): the quick
  actions, the brightness/warmth switch and the slider sit 16 lower, so
  there is more space between them and the Wi-Fi, battery and clock line.
  The Apps tab is unchanged.

Checked: the file parses. Not tested on a device.

## 2026-11-09 — 0.1.53 goal widget opens the finished books

- A tap on the **goal** widget (Goal pace, "2026 goal") opens the library
  with the books finished this year — the ones that count toward the goal —
  through the same "shelf" action as the Finished this year shelf
  (`aleph_board_host.lua`), instead of Reading insights.

Checked: the file parses. Not tested on a device.

## 2026-11-09 — 0.1.52 reader menu: each tab its own height

- The reader menu kept the height of the tallest tab it had shown, so after
  Also reading the This book tab had an empty band at the bottom. Each tab
  now sizes the sheet (`aleph_reader_sheet.lua`); MenuPage repaints
  the whole screen, backdrop included, when the sheet changes height.

Checked: the file parses. Not tested on a device.

## 2026-11-09 — 0.1.51 Statistics widgets: finding Reading insights

- Every Statistics widget said to install Reading insights: the plugin was
  only looked for on the board's own file browser (and PluginLoader). Now
  (`aleph_integrations.lua`), the way Reading log does it: on the
  board's file browser, then `FileManager.instance` and `ReaderUI.instance`,
  then PluginLoader. If found under other method names, its gesture action
  runs through KOReader's Dispatcher with the file browser / reader set to
  listen for the call (Reading log's readerpanel trick: the board is the top
  window). Without Reading insights, KOReader's own Reading statistics opens:
  its calendar (Streak, Year in reading, Reading calendar, When you read) or
  Reading progress (This week, Goal pace, Today, Reading records). Only with
  neither plugin does the tap say so. A line in crash.log says whether Reading
  insights was found.

Checked: every file parses; found on FileManager.instance, the statistics
fallback and the message tested with stand-in objects. Not tested on a
device.

## 2026-11-09 — 0.1.50 reader menu at the bottom

- **Reader menu** (`aleph_reader_sheet.lua`), after BookOrbit's "This
  book" sheet: replaces KOReader's bottom menu (ReaderConfig:onShowConfigMenu,
  so a tap at the bottom of the page and the bottom swipe while the page
  browser's swipe is off). A sheet over the dimmed page: the cover, title,
  author and a progress chip; a card with the book (18%, page 214 of 542) and
  the chapter (title, pages left); tabs **This book** and **Also reading**.
  This book: tiles for Style (KOReader's own bottom menu: fonts, margins,
  contrast…), Contents, Bookmarks and Pages (the page browser); Bookmark this
  page (switch); Book details (the Reading Board page, with highlight and
  bookmark counts); Reading Board Home. Also reading: up to four other books
  in progress from the library index, newest first, with cover, author,
  progress and a bar — tap to switch to it (ReaderUI:switchDocument) — and
  All books (the library). Swipe sideways to change tab, down to close. The
  sheet keeps the taller tab's height.
- The index is read again only when its file changed. `Local.cachedCover`
  finds a cover already on disk without opening the book.
- Settings > Opening > Dialogs > **Reader menu at the bottom** (on by
  default) brings KOReader's own menu back. The page browser's Aa tab opens
  KOReader's menu directly.

Checked: every file parses; data (progress, chapter, counts, other books),
both tabs and the bookmark switch tested with stand-in objects. Not tested
on a device.

## 2026-11-09 — 0.1.49 page browser opens without flashing

- Each preview that arrived redrew the whole screen (a "partial" full-screen
  refresh), three in a row as the browser opened, which flashed the e-ink
  screen. Now (`aleph_page_browser.lua`) a preview is drawn in its
  own rectangle only, with KOReader's quiet "ui" refresh, and previews
  arriving within 0.15 s share one repaint. The first preview is asked for
  at once (no 0.3 s wait) so the middle page shows sooner; later ones still
  wait for moving to stop.

Checked: every file parses; the repaint regions tested with stand-in
objects. Not tested on a device.

## 2026-11-09 — 0.1.48 more Statistics widgets open Reading insights

- `aleph_board_host.lua` boardItemAction: **Reading records** opens
  Records, **When you read** Reading habits, **Reading calendar** Reading
  calendar, **Goal pace** and **Today** the Reading insights popup (Goal pace
  used to open the In progress list). Same `Integrations.openInsights` path
  as 0.1.45; without the plugin the tap says to install or enable it.

Checked: every file parses. Not tested on a device.

## 2026-11-09 — 0.1.47 page browser: memory, ⋮, swipe up

- **Crash** (supplied crash.log, ends in "Killed": the kernel ended KOReader
  for memory). The page browser kept a full-size color copy of every page
  preview it had shown and asked for two more on each step; after scrolling
  through the book, and with renders still running after it closed (the log
  shows pages 1530–1534 and 875–877 being drawn behind KOReader's menu),
  memory ran out. Now (`aleph_page_browser.lua`) only the middle page
  and its two neighbours are kept, others are freed at once; previews are
  asked for one at a time, middle page first, 0.3 s after the browser stops
  moving; pending renders are cancelled and everything freed on close.
- **⋮** opened KOReader's main menu straight away. It now opens a "More"
  sheet: Go to page…, This book (its Reading Board page), Reading Board, and
  KOReader menu.
- **Swipe up** opened KOReader's style menu: the touch zone lost to
  KOReader's own. As ZenOS does, `ReaderConfig.onSwipeShowConfigMenu` is now
  hooked (`PageBrowser.install`, from the reader steps in `main.lua`): a
  swipe up opens the page browser while the setting is on; other swipes and
  the setting off keep KOReader's behaviour.

Checked: every file parses; previews kept, freed and requested one at a time
across 30 quick steps tested with stand-in objects. Not tested on a device.

## 2026-11-09 — 0.1.46 pin badge anywhere on the page

- **Pin badge position** (`aleph_pins.lua`, `Pins.openPlacer`): a
  panel with a small page and its eight places (corners and edge middles),
  arrows that move the badge 8 at a time from there, the side the drawer
  opens on, Reset and Done. Saved as `pins_badge = { anchor, dx, dy }`
  (default: the bottom corner on the drawer's side, as before). Over a book
  the page stays in view and the badge moves as you choose; the panel keeps
  to the half away from it. The badge's tap and hold zones follow it.
- Reached from Tools > **Pin badge position** in a book (pinned right under
  Reading Board) and from Settings > Opening > Dialogs > **Pinned pages**,
  which replaces the "panel on the left" switch (now in the same panel).

Checked: every file parses; placement at every anchor, nudging, keeping on
screen, saving and labels tested with stand-in objects. Not tested on a
device.

## 2026-11-09 — 0.1.45 Statistics widgets open Reading insights

- A tap on **Streak** opens Reading insights' Reading calendar, on **Year in
  reading** its Reading habits, on **This week** its Reading insights popup
  (`aleph_board_host.lua` boardItemAction, `aleph_browser.lua`
  "insights" action, `Integrations.openInsights` in
  `aleph_integrations.lua`). The plugin is found on the file
  browser / reader (`ui.readinginsights`, else PluginLoader) and its own
  methods are called, the same ones its Tools menu uses; its popups open over
  the board. Without the plugin the tap says to install or enable it.
  Records, Reading shelf and Achievements are mapped too, ready for widgets.

Checked: every file parses. Not tested on a device.

## 2026-11-09 — 0.1.44 bookmarks page: its own options

- ≡ on the bookmarks page (`aleph_bookmarks.lua`) no longer swaps to
  KOReader's list (which looked like the page had reverted). It opens a
  sheet in the board's style: **Find** (Search bookmarks — passages, notes and
  chapters — and Clear search), **Go to** (Current page: page order, at the
  item nearest the reading position; Latest bookmark: its page and its
  sheet), **More** (Export annotations through KOReader's exporter; Select,
  edited text and more in KOReader's own list, the only way there now).
- A search in force shows as a chip under the colors; tap it to clear.

Checked: every file parses; search filtering and clearing tested with
stand-in objects. Not tested on a device.

## 2026-11-09 — 0.1.43 page browser

- **Page browser** (`aleph_page_browser.lua`), after ZenOS's (see
  ZENOS_NOTICE.md), in Reading Board's parts, font and sizes: ⋮ (KOReader's
  menu), a tab bar (Pages, Reading settings, Bookmarks, Highlights, Contents,
  Pinned pages; the active tab inked), × ; a carousel of KOReader page
  thumbnails (focused page two thirds of the width with its number on a
  dark pill, neighbours cropped at the sides); the chapter and "Page X of Y ·
  Z%", the page grid (KOReader's own page browser) and search; a slider
  between ‹ ›. Swipe or tap a side page to move, tap the middle page to read
  from it, tap the slider to jump, hold ‹ › for the previous / next chapter,
  swipe down or Back to close. Tabs close the browser and open Reading
  Board's bookmarks page (on Bookmarks or Highlights), its table of contents,
  the pins list, or KOReader's reading settings.
- Opened by a swipe up from the bottom seventh of a book (ZenOS's zone,
  overriding KOReader's bottom swipes; Settings > Opening > Dialogs > Page
  browser on swipe up, on by default) or the "Reading Board: page browser"
  action. Zone registered on ReaderReady.
- `Bookmarks.open` takes an initial type; `MenuPage` keeps `last_tap`.

Checked: every file parses; progress text, slider positions, stepping,
chapter skips, thumbnails arriving and opening a page tested with stand-in
objects. Not tested on a device.

## 2026-11-09 — 0.1.42 bookmarks page, sort, header fix

- **Bookmarks page** (`aleph_bookmarks.lua`, installed from
  `aleph_menu_skin.lua`), after Annotations Viewer's list: each item
  whole — chapter · day and the page, the passage in its highlight color (a
  tint for Lighten/Invert, a colored rule for Underline/Strikeout), the note
  under it; over six lines it ends in "…". Pages are packed by measured
  height. Filters (type with counts, styles, colors, centred rows) are the
  page's own. Tap an item: a sheet with the whole passage, paged when long,
  the note, **Edit** (KOReader's details) and **Go to in book**; hold an item
  to go straight there. ≡ opens KOReader's own list (select, export, search,
  its filters); while one of its filters, a search or a selection is on,
  KOReader reopens its own list as before.
- **Sort**: the header's sort button cycles Page order, Newest first, Oldest
  first (remembered as `bookmarks_sort`). In page order the list opens at the
  item nearest the reading position.
- **KOReader's list**: its header keeps the subtitle line even when empty, so
  a style or color filter (which adds "Highlight style: …") no longer makes
  the header taller than the list was laid out for (the gray rule over the
  first item); more space under the color row.
- `MenuPage` takes `on_hold`.

Checked: every file parses; entries, filters, counts, sorting, paging and
opening near the reading position tested with stand-in objects. Not tested
on a device.

## 2026-11-09 — 0.1.41 pin drawer: zoom and a large size

- **Zoom in the drawer** (`aleph_pins.lua`): − level + under the
  picture (1×, 1.5×, 2×, 3×, 4×); spread and pinch on the picture step the
  zoom too, a swipe on a zoomed picture moves around it (never past an
  edge), and tapping the level returns to the whole page. Drawn with
  KOReader's ImageWidget (scale factor and centre ratios) from one bitmap
  rendered at the screen's size, so zoom stays sharp. Changing pin resets it.
- **Large drawer**: the resize icon in the header switches between the small
  drawer (240) and a large one (440, at most 80% of the screen width, the
  picture up to 62% of its height); remembered as `pins_large`. The expand
  icon and a tap on the picture still open the full screen viewer.
- `Panel` takes `on_gesture` (swipe, pinch, spread). Icons zoom-in,
  zoom-out, maximize-2 and minimize-2 added (Lucide).

Checked: every file parses; zoom steps and keeping the view inside the
picture tested with stand-in objects. Not tested on a device.

## 2026-11-09 — 0.1.40 bookmarks list: pager, filter rows, options sheet

- **Pager** (`aleph_menu_skin.lua`, `MenuSkin.pageLabel`): the table
  of contents' and bookmarks list's "Page 4 of 4" is painted as "4 / 4" in
  the board's font (14, bold). KOReader's button keeps its size, text and tap
  (type a page number); only its painting changed. Replaces 0.1.39's
  setText, which did not take.
- **Quick filter**: the style samples (larger, 64 x 40) on one row and the
  nine colors (40) on the row below, each row centred.
- **Options sheet** (`aleph_dialog_sheet.lua`): the ≡ button's
  KOReader dialog (bookmarks: type filters, edited / style / color filters,
  export, current page, latest bookmark, select, search; the table of
  contents' own options too) opens as a Reading Board sheet: title and close,
  section labels with a rule under them after Annotations Viewer's Filter &
  sort, rows of two buttons as outlined tiles and single buttons as card
  rows, an icon on every button, KOReader's font-symbols dropped. The dialog
  is still built (its buttons close it by name) but never shown; taps run
  its callbacks. Falls back to the dialog if the sheet fails.

Checked: every file parses; label cleaning, icons, grouping at separators
and the capture (dialog replaced, empty dialog shown as before) tested with
stand-in objects. Not tested on a device.

## 2026-11-09 — 0.1.39 posts under menus, table of contents panel, one-row dictionary buttons

- **Highlight posts** (`aleph_panel.lua`): the posts are painted
  before the panel, so where a post runs under the highlight menu or the
  More list the menu covers it. Touches on the menu were already the menu's.
- **Table of contents** (`aleph_toc.lua`, installed from
  `aleph_menu_skin.lua`): ReaderToc:onShowToc opens a Reading Board
  panel laid out like the Genre picker: a bordered panel with margins over the
  dimmed page, Back / title / ≡, the chapters in outlined cards with
  hairlines (two columns when every title fits on one line), the page as a
  plain number on the right, "‹ 1 / 7 ›" below. Opens on the current
  chapter's page (bold); nested entries indented; swipes and page keys turn
  pages. Jumps as KOReader does (location stack, GotoXPointer / GotoPage).
  ≡ opens KOReader's own table of contents (settings, expand, hold), which
  also falls back if the panel fails; it now has no dotted leaders, and its
  pager and the bookmarks list's read "1 / 7".
- **Dictionary** (`aleph_dictionary.lua`, `aleph_cell.lua`):
  buttons with words (Add to vocabulary builder, plugin buttons) each on a
  full-width row with the words centred; every icon button (dictionaries back
  and forward, Wikipedia, Highlight, Search, Close) in one row of bare icons
  (split into two rows only past seven); hairlines between rows. The pop-up
  is shorter by the row it no longer needs. `Cell` gained `center`.

Checked: every file parses; the table of contents' paging, columns, current
page and jumps tested with stand-in objects. Not tested on a device.

## 2026-11-09 — 0.1.38 this-book action, gesture shortcut, Tools pin, highlight drawer and text pages

Five features compared with BookOrbit's plugin and brought over:

- **"Reading Board: this book"** (`main.lua`): a reader action that opens the
  open book's page through `aleph_topbar_book.showDetails`, the same
  path as the Quick Top Bar's cover (Bookshelf's page or KOReader's Book
  information for a book outside the library).
- **Gesture shortcut** (`aleph_shortcut.lua`, from
  `bookorbit_shortcut.lua`): Settings > Opening > Shortcut binds one of four
  gestures to "Reading Board: open" through the running Gestures plugin, names
  what a gesture did before and asks before replacing it. Gesture drawings
  added to `MenuUI.gesture` (cache: `cache/aleph/icons`). On a short
  screen the Opening page shows the shortcut as a row.
- **Tools pin** (`aleph_menu_pin.lua`, from `bookorbit_menu_pin.lua`):
  the entry goes right below calibre in Tools, reader and file browser, by
  changing KOReader's cached menu-order tables in place. BookOrbit's menu-bar
  tab is left out (the Quick Top Bar covers it) and, unlike BookOrbit, no menu
  order file is written or migrated.
- **Highlight of the day drawer** (`aleph_highlight_sheet.lua`, from
  `bookorbit_highlight_sheet.lua`): the Home tile opens a sheet with the whole
  passage, paged, plus its chapter, date and note and a Book details button.
- **Text pages** (`aleph_text_pages.lua`, from
  `bookorbit_text_pages.lua`): About this book (from the description, opened
  by tapping it or its new "Read all"), Highlights (replaces KOReader's text
  viewer, which stays as the fallback) and Genres & tags (from "+N" on the
  book page; its chips list a genre's books, as the page's own chips do).
  The sheet parts they use are in `aleph_sheet_ui.lua`, taken from
  `bookorbit_dialog_ui.lua`.
- The index now keeps each highlight's date, and its chapter under the name
  the Home tile reads (`chapterTitle`), so the tile's chapter line shows; the
  next library scan fills them in for existing books.

Checked: every file parses; menu pin, shortcut binding/describe/apply, page
packing, highlight view and page windows tested with stand-in objects. Not
tested on a device.

## 2026-11-09 — 0.1.37 Quick Top Bar built in

Quick Top Bar 0.1.3 (the user's own plugin) is part of Reading Board:
`aleph_topbar.lua` and `aleph_topbar_*.lua` (the plugin's files,
renamed, with `require` names updated), and the line icons in `icons/`. Reading
Board starts it from `Board:init`, in the file browser and in a book, and
Settings > Opening > Quick top bar turns it on or off (on by default; the tabs
come and go the next time the top menu opens). The saved choices of the
standalone plugin (`quicktopbar` in settings, `quicktopbar-icons/`) are read as
they are. If the standalone quicktopbar plugin is enabled it keeps the top
menu and the setting says so; remove or disable one of the two to avoid
duplicate tabs. Added `QuickTopBar.start/stop/sync/standalone/wanted`; nothing
else in the plugin changed. Checked with stand-in objects (app discovery by
instance, path and name, start/stop/sync); not on a device.

## 2026-11-09 — 0.1.36 highlight posts and pins after ZenOS

Compared with ZenOS's highlight handles and pinned pages and rebuilt both the
same way, in Reading Board's look (see ZENOS_NOTICE.md):

- Posts (`aleph_handles.lua`, `aleph_viewport.lua`): a post is
  drawn by the menu panel and the panel offers it every gesture first
  (`Panel:handleEvent`); there is no window of its own over the page. A drag
  works on a draft copy (the highlight is redrawn live from it) and is written
  to the annotation once, on release, with the same AnnotationsModified event
  KOReader's own editing sends. The menu is hidden while a post is dragged and
  shown again, placed for the new highlight, afterwards. Dragging to a corner
  scrolls or turns the page; scroll mode and PDF/CBZ are handled; text-edited
  highlights show no posts. A short pause on page taps after a drag or menu
  stops the finger that lifted from also turning the page.
- Pins (`aleph_pins.lua`): the edge tab and its window are replaced by a
  badge (pin and count) painted by ReaderView above the status bar and reached
  through touch zones, as ZenOS does for its footer count: a tap opens the
  drawer, a hold the list. KOReader's own Pin page and Go to pinned page use
  these pins. The drawer, list and image viewer keep their look.
- Tested with stand-in objects only (drag, release, crossing ends, taps passing
  through); not on a device.

## 2026-11-08 — 0.1.35 highlight posts: no freeze, menu steps aside

Cause of the freeze, read from the supplied log (no Lua error; touches were
still detected but nothing repainted or reacted): the drag posts were a
full-screen window shown on top of the highlight menu. KOReader sends a touch
only to the topmost window, and the posts used only hold and pan, so every tap
and swipe was swallowed and the reader looked frozen. The posts are no longer a
window: the menu panel draws them and passes its touches to them
(`Panel.extra`), so taps and swipes reach the menu again.

Dragging a highlight's post (`Handles` in `aleph_highlight.lua`) now
hides the highlight menu (`Panel:setHidden`) so the whole text is in view; the
menu returns, placed again beside the highlight, when the finger lifts.
Finger positions are no longer handled one by one: the latest is kept and one
update runs every 0.05 s, and the word lookup only moves the end positions.
The text, page and chapter are worked out once on release. The screen boxes of
the highlight are cached per pair of ends. Errors in a drag step are caught.
Not tested on a device.

## 2026-11-08 — 0.1.32 bottom-corner pin panel

Anchor the expanded pin panel to the bottom-right screen edges instead of
centering it vertically. The existing left-side preference mirrors it to
the bottom-left. Panel size and controls are retained. The collapsed badge
still sits above the status bar. Includes the 0.1.30 redraw correction and
0.1.31 thumbnail callback crash fix.

## 2026-11-08 — 0.1.31 pin thumbnail crash

The supplied crash log identifies aleph_pins.lua:158: attempt to call
method 'copy' (a nil value). ReaderThumbnail passes a TileCacheItem to its
callback, with the image in tile.bb. The plugin incorrectly treated the
item itself as a bitmap. Copy tile.bb instead, preserving ownership of the
cached original and handling nil tiles on generation failure.

The corrected mock uses KOReader's TileCacheItem callback format. It
reproduces the logged crash on 0.1.30 and tests delayed delivery after X,
immediate cache hits, failed generation, and repeated open/close cycles.
The 0.1.30 redraw correction is retained, but was not a fix for this crash.
All Lua files are syntax checked; physical-device behavior remains untested.

## 2026-11-08 — 0.1.30 pin close redraw

Based on the local 0.1.29 pin-badge ZIP. Repaint the underlying reader as well
as the transparent dock when its panel changes size or closes. Previously
only the dock was repainted, leaving the old panel visible with inactive
controls. The refresh region covers both the old panel and the new badge.
Dock teardown now releases its view before its thumbnail cache and is safe
to call twice.

All 61 Lua files compile with LuaJIT. Mocked regression tests exercise the
real open/close actions, the X tap, the old-panel refresh region, page tap
passthrough after closing, late thumbnail delivery, ten repeated open/close
cycles, and teardown. The close repaint assertion fails on 0.1.29 and passes
on this version. Physical-device behavior and the reported full freeze have
not been reproduced; a crash log is needed if unresponsiveness persists.

## 2026-11-08 — 0.1.29 pin badge

Based on the supplied local 0.1.28 syntax-fix package. The pin dock is now
shown on the next UI tick, after ReaderUI has been shown, so the reader cannot
cover the badge during startup. Removed the separate plain-text "Pins N"
footer contribution. The rounded badge uses a filled diagonal pushpin, the
page background colour, and the selected left/right side. Its existing
position above the status bar is retained; the reading percentage remains
KOReader's own footer content.

Pending startup display is cancelled on detach; late thumbnail callbacks
cannot revive a closed dock. LuaJIT syntax checks pass for all 61 Lua files,
with mocked lifecycle/stacking and badge tests. Physical-device rendering
has not been verified.

## 2026-11-08 — 0.1.12 KOSyncthing+ button

When the KOSyncthing+ plugin is installed and enabled, the Refresh button of the quick-controls widget is labelled Sync and runs KOSyncthing+ > Start Syncthing (`Integrations.startSyncthing`, which calls the plugin's own `onToggleSyncthingServer` only when Syncthing is not running; it never stops it). The button is drawn lit while Syncthing runs. Without the plugin the button still rescans the library; the Settings row "Look for new, moved and removed books" always does.

## 2026-11-08 — 0.1.11 charging indicator

The original BookOrbit plugin never showed charging. The status cluster (`BoardUI.statusCluster`) now draws a filled bolt in front of the battery while `powerd:isCharging()` is true. The board redraws its header on KOReader's Charging, NotCharging and Charged events (`Browser:chargingChanged`), and the once-a-minute clock redraw covers a missed event.

## 2026-11-08 — 0.1.10 light-popup fix

Brightness is now converted between KOReader's raw device levels (`powerd.fl_max`, about 24 on a Kindle) and the 0-100 scale used by the bars (`BoardData.light`, `BoardData.adjustLight`), so the bar fills at maximum and each tap moves at least one level. The light popup repaints its panel with a "ui" refresh instead of "partial" plus a second colour refresh, which removes the flashing. The dashboard Light tile uses the same helpers. The popup also has a Frontlight on/off switch (a `MenuUI.row` with the menu's toggle in a card, `BoardData.toggleLight`); raising brightness while the light is off turns it on first.

## 2026-11-08 — 0.1.9 light-popup patch

Based on the supplied 0.1.8 about/genres/icons package. Added
`aleph_light_sheet.lua`, reusing the existing Light tile and MenuPage modal
for the quick-controls sun button. Brightness/warmth changes are local and clamped
to 0–100. The popup redraws itself after a change and refreshes the dashboard when
closed. The browser closes its popup when it is closed. Other runtime files from
the supplied package are unchanged.

This is a modified version of BookOrbit and is not an official BookOrbit release.

Based on the user's saved `koreader-plugin/bookorbit.koplugin` source, whose main module reports plugin version 2.1.0, and the accompanying BookOrbit 3.6.0 distribution's license notices.

- Replaced the lifecycle/controller with `main.lua`, `aleph_browser.lua` and `aleph_local.lua`.
- Reused and namespaced the native board drawing, geometry, editing, themes, icons, companion sprites, chapter maps and read-only statistics helpers.
- Omitted the API, authentication, provisioning, server catalog, download/upload, sync/conflict handling and update modules.
- Replaced remote navigation with local indexing, book details, author/series grouping, search, sorting and filters.
- Replaced the sync action with local refresh. Removed server-only widget choices and starter tiles. Read statistics exclusively from KOReader's local database.
- Added cancel-safe indexing, local cover extraction and caching, separate settings, tests and packaging scripts.

The original downloaded source folders are reference material and are not part of the installable plugin. The distributed Lua files are the exact runtime source; no compiled application or hidden server component is required.
- Added an optional Silverfish widget (`aleph_silverfish.lua`, `aleph_integrations.lua`) that reads the separately installed Silverfish plugin.
- Added genre filtering and a Genres list using book tags (EPUB subjects or Calibre metadata.opf).
- Faster first load: time-sliced library scan, cover thumbnails (cache/aleph/thumbs), next-page cover prefetch and progressive cover redraw.
- Swipe down from the top edge opens KOReader's top menu while the board is open.
- Rebuilt the book page after the BookOrbit detail layout without any server state (`aleph_detail.lua`); holding a cover opens it; Book information shows a progress notice and reports failures; the back button returns to where the page was opened.
- Rebuilt the library page after BookOrbit's list page (`aleph_library_view.lua`, `aleph_list_data.lua`; adapted from BookOrbit's list view and list data, modified 2026-11-07): header with Wi-Fi, battery and clock, Search and menu; toolbar with Sort, Filter and Collection buttons and the List / Grid switch; A–Z thumb index; pager with Jump; top sheets for sort and filter. The Collection button (BookOrbit's Library button) chooses the whole library or one of KOReader's collections.
- `aleph_local.lua`: query now takes `order`, `collection` and `format`, sorts by series then volume, and reports collections and formats.
- `main.lua`: "Open at file browser startup" no longer waits for a FileManagerReady event (KOReader does not send one); the plugin opens the board itself shortly after it loads inside the file browser, which also covers returning from a book.
- `aleph_list_data.lua`: a finished book's date is converted before it is parsed (fixes a crash when opening the library).
- Series page: opening a series now shows BookOrbit's series page instead of the plain library grid (`aleph_library_view.lua`: `seriesLayout`, `seriesBody`, `stackFit`, adapted from BookOrbit's list pages and list view, modified 2026-11-07; `aleph_list_data.lua`: `distinctTitles`; `aleph_browser.lua`: `buildSeriesPage`). It shows the stacked covers, "x of N read" with one ruler segment per book, Up next with Continue, and the numbered Reading order list or grid.
- Menu and settings restyled after BookOrbit: the menu button opens a BookOrbit-style sheet (`aleph_menu_sheet.lua`, `aleph_menu_page.lua`, `aleph_menu_ui.lua`, adapted from BookOrbit's menu sheet, menu page and menu UI kit, modified 2026-11-07) with Customize/History/Files tiles, a Go to card with counts and Settings and About rows. Settings is now a BookOrbit-style page (`aleph_settings_page.lua`, adapted from BookOrbit's settings page): groups for Profile (your name, yearly goal), Opening, Home (layout, tile style, colour, interface size, reset), Library folders and About. `aleph_browser.lua`: `showMenu`, `menuRun`, `loadHistory`, `showSettings` now use them.
- Authors and Series lists: opening Authors or Series from the menu or Home now shows BookOrbit's index pages instead of a plain pop-up list (`aleph_library_view.lua`: `authorRow`, `seriesRow`, `authorCell`, `seriesCell`, `groupsGeometry`, `groupsBody`, `fan`, `seriesStrip`, `seriesBar`; `aleph_list_data.lua`: series and author rules; `aleph_local.lua`: `groupEntries`; `aleph_browser.lua`: `loadIndex`, `buildIndexPage`, `indexRun`; adapted from BookOrbit's list view, list pages and list data, modified 2026-11-07). Rows show stacked covers, a status or series progress bar on the right, the A–Z thumb index with letter marks, Sort (Name A–Z, Name Z–A, Most books) and Show (Everyone / Reading now / Read, All series / In progress / Finished) controls, the List / Grid switch and the Jump pager. Back from an author's or series' books returns to the list.
- Book page: the stars and the status are tappable. A star sets the rating (the same star again clears it) and the status opens Unread / Reading / Finished / On hold; both are written to KOReader's own sidecar through `Local:setRating` and `Local:setStatus`. Unread is stored as KOReader's own "new" status.
- `main.lua`: opening at startup and after closing a book now waits until the file browser is the topmost screen (checked every quarter second for up to 15 seconds) instead of opening after a fixed delay, and also starts when a book is closed. The Opening setting is written to disk as soon as it is changed.
- Book page: the status and the … menu are Reading Board sheets (`ListView.optionsSheet` / `ListView.withSheet` in `aleph_library_view.lua`) instead of KOReader's plain menus; added Add to collection (switches per collection, New collection…) through KOReader's own collections (`Local:setInCollection`, `Local:createCollection`). Not in the original BookOrbit plugin, whose collections live on its server. Collections and History link tiles are back in the widget catalog and the default Library pages, with counts and names.
- `main.lua`: opening at startup and after closing a book now follows ZenOS: a class-level hook on KOReader's `FileManager:showFiles` shows the board right after the file browser is built, plus one opening from the plugin's own start for the first browser of a session. Each file browser opens the board once. If opening fails, a message with the reason is shown.
- Select several books: in the library list, holding a book starts a selection, tapping others adds or removes them (checkboxes on covers and rows, "N selected" header, ✕ ends it, Back closes the menu then ends the selection). The "…" in the header opens a Reading Board sheet (same style as the book page's) with Reading status (Unread / Reading / Finished / On hold for all selected), Add to collection (a switch per collection, showing "2 of 3" when only some are in it, plus New collection…) and Select all. `aleph_browser.lua`: `selectHold`, `selectRun`, `selectSheetModel`; `aleph_library_view.lua`: books pass `select`/`selected` to rows and covers, the header menu uses the "…" icon; `aleph_local.lua`: `collectionCounts`, `setManyInCollection`.
- Menu sheet: the title is now "Dashboard" (it showed the user's name); the name still greets on Home.
- Home and library headers: the Wi-Fi icon is larger with a heavier stroke, the battery outline is a solid line of at least 2 px with square fill edges and a darker percentage (`aleph_board_ui.lua`, `statusCluster`). Silverfish widget: the bubble text is centred vertically (`aleph_silverfish.lua` measured the text with a fixed height before, which kept it at the top).
- About page: the pill reads "Based on BookOrbit's plugin" (still links to the BookOrbit project) because Reading Board does not use BookOrbit's server; the Legal notices keep the required "Powered by BookOrbit" notice unchanged. Library filter: the Genre, Collection and Format pick sheets are paged (two columns per page, a pager under the list) so long lists fit the screen (`ListView.pickSheet`, `Browser:libraryRun`). Status icons: the Wi-Fi icon is a little smaller (15) so its top and bottom line up with the battery.
- Dialogs in the board's style: `aleph_panel.lua` (a pop-up host that draws only its panel, over a book too), `aleph_opening.lua` (the "Opening file" message becomes a card with cover, title and author, through a hook on `ReaderUI:showReaderCoroutine`), `aleph_input.lua` (a subclass of KOReader's InputDialog with a rounded panel, field and pill buttons; used for the search prompt and the board's other prompts), `aleph_highlight.lua` and `aleph_color_wheel.lua` (one sheet for a highlight's style and color with icon tiles, renamable colors and a color wheel; the highlight dialog's Style and Color buttons are merged). A Dialogs switch in Settings turns it off.
- Select several books also works on a series page: hold a book to start, tap others to add or remove them, the same "…" menu sets the reading status of all, adds them to a collection or selects the whole series. The Continue button rests while selecting (`aleph_browser.lua`: `buildSeriesPage`; `aleph_library_view.lua`: `seriesBody`). Opening another list ends a selection.
- Quick controls: the Syncthing button now lights while Syncthing runs even when KOSyncthing+'s isRunning says no (the process list is checked, kept 3 seconds), and the board looks again 2, 5, 10 and 20 seconds after Start Syncthing (`aleph_integrations.lua`: `syncthingRunning`, `watchSyncthing`).
- Dictionary pop-up restyled (`aleph_dictionary.lua`, hook on `DictQuickLookup:init`): board font and frame, header, pencil, rounded button cells with icons for Previous / Next dictionary, Highlight, Wikipedia, Search and Close. `BoardMetrics.faceFile` added.
- Highlight menu restyled (`aleph_highlight.lua`: `openActions`, replaces `ReaderHighlight:showHighlightDialog`), and the highlight prompt setting (style, color, style and color) opens the style and color sheet for a new highlight (`showHighlightPrompt` hook; `openSheet` with `new`).
- Author portraits (optional, Settings > Author portraits): `aleph_portraits.lua` looks authors up on Open Library and Wikipedia, caches the photos and draws them round; the Authors list (`aleph_library_view.lua`: `authorRow`, `authorCell`; `aleph_browser.lua`: `buildIndexPage`) shows them; Settings has the switch, Download all, Stop and Remove.
- Header status: the Wi-Fi and battery icons are BookOrbit's again; the charging bolt is a thin outline as tall as the Wi-Fi icon (`BoardUI.statusCluster`).
- Highlight More / selected-text menu (`aleph_highlight.lua`: `openMenu`, replaces `ReaderHighlight:onShowHighlightMenu`) and the highlight Details viewer (`aleph_bookmark.lua`, restyles KOReader's TextViewer for bookmark details only) in the board's style; the tappable cell is shared (`aleph_cell.lua`).
- A diagonal swipe on a Reading Board page does a full screen refresh (`Browser:onSwipe`).
- Start Syncthing (quick controls): the call to KOSyncthing+ now passes something that works as both its touch menu and a callback, uses only the plugin's own isRunning to decide Syncthing is already up (the process list only lights the button), tries the plugin's plain start if the menu routine fails, shows the error text if both fail, and says after 8 seconds if Syncthing is still not running (`aleph_integrations.lua`).
- Start Syncthing (quick controls) now calls KOSyncthing+'s start-only `runManualStart` (the menu entry's toggle can stop Syncthing, so it is no longer used); KOSyncthing+ itself shows its progress and any error. Reviewed against KOSyncthing+'s source.
- KOReader's Exit and Restart now also close the board (and its open pages, sheets and panels): the board was keeping KOReader running because it stayed on screen after the file browser closed (`main.lua`: `Board:onCloseWidget`).
- Start Syncthing (quick controls): the page is no longer redrawn every few seconds after the tap, only when Syncthing's state changes; the tap now shows "Starting Syncthing…" (or says it is already starting or running); KOSyncthing+ is also found by its methods when it is not registered under its usual name.
- KOSyncthing+ is also found through its global interface (`KOSyncthingPlusAPI`), not only on the file browser; the button says when it is not found and rescans the library instead (`aleph_integrations.lua`: `syncthing`).
- Author portrait questions use a Reading Board dialog (`aleph_confirm.lua`). The dictionary pop-up is docked to the bottom of the screen and set in the board's body size, and footnote popups use the board's font and size (`aleph_dictionary.lua`, reading KOReader's settings through an override only while they are built). Pinned pages (`aleph_pins.lua`): Pin in the text menu, Pin image on pictures, a side dock, a list, a full screen viewer through KOReader's image viewer, a gesture action and a status bar count; the newest pin is KOReader's own pinned page. Existing highlights can be stretched or shortened by holding an end and dragging (`aleph_highlight.lua`: `installDrag`). A vertical swipe on the left or right edge of any board page changes brightness or warmth (`Browser:adjustLight`).
- Pinned pages: a picture can be pinned again (a bitmap is a cdata, which the pin code did not recognise), and the collapsed dock is a chip with a pin and the count at the bottom right of the page, above the status bar (`aleph_pins.lua`). Highlights: while a highlight's menu is open a post and knob marks each end (`Handles` in `aleph_highlight.lua`) and dragging a knob stretches or shrinks the highlight; the menu is placed beside the highlight, not over it. The earlier hold-the-edge hook was removed.
- Reader screens in the board's style: the image viewer's button row (`aleph_imageviewer.lua`), the table of contents and the bookmarks list with a quick type, style and color filter (`aleph_menu_skin.lua`), and the reader controls panel with a new Background tab (`aleph_config.lua`: tab icons, fonts, choice buttons, White / Paper / Sepia / Gray / Custom page color). `aleph_cell.lua` gained active, swatch and sample cells. Icons settings, crop, type and contrast added.
- `Board:showBookPage(path)` and `Browser:openBookPage` open the board's book page over the reader for one book (used by QuickTopBar's cover); Back closes the board.
- Reader hang hunt (no cause confirmed): the pinned pages dock is now a window only while the book has pins (before, every book got an invisible full-screen window over the page); it appears when the first pin is added and closes with the last (`aleph_pins.lua`: `Pins.ensureDock`). Each step Reading Board takes when a book opens is logged to koreader/crash.log as "Reading Board: reader step <name>" and "... done", so the last line before a hang names the step (`main.lua`, `aleph_opening.lua`).
- Pinned pages dock: its window now covers only the chip or the open panel (`Dock:syncArea`), not the whole screen, so it no longer sits in front of every gesture on the page. Found while reading a crash log: the earlier "attempt to call method copy" crash when a pinned page's thumbnail arrived is the one `Pins.render` already fixes by copying `tile.bb`.
