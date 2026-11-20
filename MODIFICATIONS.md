# Aleph (formerly Reading Board) — modifications, 2026-11-07 to 2026-11-15

## 2026-11-20 — 1.3.0 (release)

Everything from 1.2.8 to 1.2.59 (see below), released as 1.3.0:

- **Goodreads inside Aleph**: Aleph keeps Goodreads up to date itself (Currently reading, progress, Read with the day and stars, offline queue), never marks a book Read twice, and warns about advokatb's plugin, whose sign-in, settings and book links it takes over.
- **New widgets**: Goals (with rings on a large tile), Daily, Weekly and Monthly goal, Reading DNA, Monthly challenge, Reading rhythm, Year projection, Diversity score, Reading bingo, Weather, Hours read, Time read and Books and pages; every widget in its own colour.
- **X-Ray**: a name's card shows where it comes up (chapters, first seen, most mentions, latest) and who it is often with; Detailed descriptions for main characters with AI.
- **Library**: collections from Calibre's #collections column; rename and delete collections; sort Reading by progress; tap an author on a book's page.
- **Home**: fonts for Home and the top menu; Home's text readable over any wallpaper (Auto, Dark, Light, Outline); the wallpaper picker opens in the device's images folder; Finish forecast from a new book's real pace.
- **Reading**: a way back after any jump (contents, Go to page, links, bookmarks, pins); hold Wi-Fi in the top menu for the networks in range; Bluetooth switch with the Kobo plugin; pages follow the screen when it turns.
- **French and Italian**; Portuguese and Spanish checked.
- **Time read and Books and pages** (new in 1.3.0 itself; after the Reading Log plugin's charts of those names, written for Aleph; aleph_board_widgets.lua W.time_read and W.books_pages, aleph_board_data.lua year_months, aleph_stats_reader.lua Session:monthStats). Statistics, sizes XL and L like Year in reading. **Time read** (blue, picked at random): this year's hours month by month as bars, the year's total beside the title, the current month in the widget's ink with its hours over it, a scale of hours. **Books and pages** (green): books finished and pages read each month as two smooth lines (books on the left scale, pages on the right one, "15k" above 10,000), with the year's totals as the legend. Hours and pages come from KOReader's statistics in one query (each page at most ten minutes; a page counted once per book and month); books from the year's finished books, as the yearly goal counts them. Translated into Portuguese, Spanish, French and Italian. Tests: 113.
- **A colour for each widget** (new in 1.3.0 itself; aleph_board_colour.lua CHOICES, tileKey, choiceName; aleph_board_host.lua boardColourBar; aleph_board_edit.lua edit-colour, edit-colour-set; saved as `colour` with each widget in the layout, aleph_board_store.lua). In Customize Home, a selected widget's bar has **Colour** on a colour screen: Default (the widget's own colour) or Yellow, Orange, Green, Blue, Red, Purple, Gold, Teal, Pink, Brown or Dark blue, shown as swatches with the chosen one ringed. It is kept for that one widget on that page (two shelves can differ) and drawn at once. No cost while drawing: the tile's colour family is looked up as before, from the chosen name first. Hidden with Colour off or on a screen without colour, where a chosen colour does nothing. Translations. Tests: 114.
- **Wallpapers** (the repository's wallpapers folder and aleph-wallpapers.zip, not the plugin): seven, at the Kindle Colorsoft's 1264 × 1680, with Three Kings and St Patrick's Day new.
- **Lighter and steadier**: background work waits when memory is low, Home frees memory when it runs low, a memory diary and the background jobs in crash.log, a fixed timer that piled up while reading, a tap on a text field always brings the keyboard up.

## 2026-11-20 — 1.2.59 Gathering dust shows the book's cover

- **Gathering dust** (aleph_board_decor.lua): the book showed Aleph's made-up title card instead of its cover on the days its cover had not been made yet. Home asks for covers only for the first few books of each list, and the day's dusty book can be anywhere among the unopened ones (a book never opened has often never been shown anywhere else either). The widget now asks for its book's cover itself; when it arrives, Home is drawn again with it.

## 2026-11-20 — 1.2.58 Reading rhythm in orange

- **Reading rhythm** (aleph_board_colour.lua) is orange instead of green.

## 2026-11-20 — 1.2.57 Finish forecast: a new book's pace over the days it has been read

- **Finish forecast** (aleph_board_data.lua, aleph_stats_reader.lua): the minutes a day were the book's reading time in the last 14 days divided by 14, always. For a book started two days before, half read since, that gave about a seventh of the real pace ("4 h 38 min left at ~21 min a day", finishing in two weeks). Now that time is divided by the days from the first time the book was read in those two weeks to today, both counted (1 to 14; `BoardData.paceDays`); a book read for longer is unchanged. Still at least 5 minutes a day.
- Tests: 112 (112: the days counted and a forecast for a book started two days before).

## 2026-11-20 — 1.2.56 Hours read: since when and this year on a narrow tile again

- **Hours read** (aleph_board_widgets.lua): 1.2.55 left out a layout. On the small tile, where the books do not fit on the line and there is no room for a third line, it went down to this year alone. The layout 1.2.54 used there is back in the list: since when, then this year (without the books), tried before the one-line layouts.
- Tests: test111 also draws that tile.

## 2026-11-20 — 1.2.55 Hours read: its lines whole, in any tile

- **Hours read** (aleph_board_widgets.lua): on a tile a little shorter (a medium tile in a short row) the widget fell back to its smallest layout and left out since when and the books; on a narrow one the books were cut ("124 h this year · 1…"). Now a line is used whole or not at all, and the layouts tried are, in turn: since when, then this year · the books; since when, this year and the books on three lines; all three on one line under the number (a wide, short tile); this year · the books; this year; the number alone.
- Tests: test111 also draws a narrow, tall tile (three lines) and a wide, short one (one line).

## 2026-11-20 — 1.2.54 Hours read widget

- **Hours read** (Customize Home → Add widget → Statistics; small or medium; teal, picked at random): all the hours read on this device, since when ("since Mar 2024"), this year's hours and how many books they were spent on. Under 10 hours it shows a decimal (2.5 hours). Tapping it opens Reading insights. Each page counts for at most ten minutes, as in When you read, so a book left open does not add hours. New `Session:totalTime` / `StatsReader.getTotalTime` (one query over KOReader's statistics, kept until the database changes), `W.hours_total`.
- Translated into Portuguese, Spanish, French and Italian.
- Tests: 111 (111: the widget in four sizes, a decimal under 10 hours, the empty tile).

## 2026-11-20 — 1.2.53 A tap on a text field always brings the keyboard up

- **Aleph's text prompts** (search, owner information, collection names, keys and the rest, aleph_input.lua): a tap on the field now brings up the on-screen keyboard on a touchscreen. Reported: the keyboard did not come up to search or to type personal details. KOReader hides the on-screen keyboard, even when the field is tapped, when it thinks a keyboard is attached and Settings > Keyboard > Show virtual keyboard is off. A device with keys counts, and so does anything KOReader's External keyboard plugin takes for a keyboard (some Bluetooth page turners). KOReader's own fields behave the same way there; turning Show virtual keyboard on fixes those too. In Aleph's prompts the keyboard still does not open by itself in that case (for whoever really has a keyboard), but a tap on the field now opens it.

## 2026-11-19 — 1.2.52 Every background job named in crash.log

- **Background jobs started without a name are named after the file that started them** (aleph_job.lua): the test crash.log had "background job started: ?" three times (the library index going to sleep and at exit, the X-Ray descriptions); now "aleph_local", "aleph_xr_ai" and so on.
- Checked in that log (1.2.51, 18:36 to 19:42): the reading memory line came once every 10 minutes (18:55, 19:05, 19:17 after a sleep, 19:27, 19:37), never twice; Home pages 1 to 4 and the X-Ray page built and drawn in portrait and landscape with no error; memory stayed between 280 and 450 MB left all session.

## 2026-11-19 — 1.2.51 Low memory on Home: freed sooner, covers wait

A crash.log: KOReader started with three new books. While Home's first page was built six times in 14 s (covers arriving), the device went from 372 MB left to 141 MB, as the covers were made in other processes, then back to 206 MB; after swiping to Home's second page 63 MB were left, after the third 38 MB, and the next tap froze the device for three minutes (a Kindle with that little left spends its time reading its own programs back from storage). The log does not say what took the memory between the second and third page: KOReader's process or another one.

- **Home's line in crash.log says more** (aleph_board_host.lua, aleph_mem.lua): "Home page 2 built, device has 63 MB left, KOReader uses … MB, of which Lua … MB", so the next log tells whether Aleph's own process grew.
- **Below 120 MB left, a Home page that has just been built frees what is no longer used** (`Mem.relieve`): a full garbage collection (pictures of widgets no longer on screen are freed only then) and Aleph's cover cache down to the covers last drawn; how much that gave back goes into crash.log.
- **Covers wait below 80 MB left** (aleph_cover_job.lua): making them opens each book in another process, which took about 200 MB here; the books are tried again half a minute later.
- **Every background process in crash.log** (aleph_job.lua): "Aleph: background job started: covers (3) - 150 MB left".
- Version numbers go on from 1.2: 1.3.0 is now 1.2.49 and 1.3.1 is 1.2.50 (1.3 is not released yet).
- Tests: 110 (110: freeing on low memory, covers waiting, the summary line).

## 2026-11-19 — 1.2.50 This week's dots in its colour

- **This week** (the goal widget, aleph_board_widgets.lua): the days read are filled with the widget's own colour, the dark purple of its icon, instead of black. Days not read keep their grey ring; on a screen without colour they stay black.

## 2026-11-19 — 1.2.49 Checks before the 1.3 release

Everything from 1.2.8 to 1.2.47, plus a last check before the release:

- **The memory diary's timer piled up** (aleph_mem.lua). A block of the file had been pasted inside `Mem.availableKB()`, so each call defined the module's functions again with fresh state. The 10-minute "while reading" line lost track of its own timer: every book opened added one more that never stopped, and "changes since" compared with nothing. The file is whole again; one timer at a time.
- **Pages follow the screen when it turns** (aleph_menu_page.lua, aleph_panel.lua). KOReader tells only the reader or the file browser that the screen turned, not the windows over them, so a page opened from a book (contents, bookmarks, X-Ray, the reader menu's pages, settings) kept the old size until it was closed. Now a page lays itself out again for the new size when it is next drawn (or hears SetDimensions); a sheet over a picture of the old screen, and a small panel placed for the old shape, close instead.
- **What wakes KOReader many times a second is named** (aleph_redraw_watch.lua). A 1.2.47 crash.log had "not painting 1 covered widget(s)" 16 times a second while Home was open, with no redraw asked (so the watcher wrote nothing). That line is KOReader's, written each time its main loop wakes while Home covers the file browser, drawn or not. There it was a local server on port 8323 that HID Passthrough's page turner sends page turns to: a message queue, which KOReader looks at every 50 ms for as long as it is there (in the reader too, where the line is not written). Not Aleph's, and cheap. The watcher now also counts the loop's wake-ups (wrapping UIManager:_repaint) and, above 8 a second for 5 seconds, writes once which message queues and which scheduled task keep waking it.
- **The Goals widget split up** (aleph_board_widgets.lua): its ring and its cell are functions of their own (`goalRing`, `goalRingArt`, `goalCell`); the widget is the same.
- Checked: every file parses and luacheck finds no errors (53 style warnings: shadowed names and unused placeholders, none a fault); no function was left inside another by an edit; no leftover files; every text in the code is in the catalogue, and Portuguese, Spanish, French and Italian have all 1,670 (placeholders and line breaks match the English).
- Tests: 109, all passing (107: the wallpaper folder; 108: the memory timer and turned pages; 109: the wake-up report).

## 2026-11-19 — 1.2.47 The wallpaper picker opens in the images folder

- **Choose a picture…** (Customize Home → Wallpaper, aleph_wallpaper.lua) now opens in the `images` folder at the root of the device's storage (`/mnt/us/images` on a Kindle, `/mnt/onboard/images` on a Kobo; `Images` works too) instead of KOReader's home folder. After a picture is chosen, the picker opens next time in the folder it came from (kept as `wallpaper_dir`); if that folder is gone it goes back to `images`, and without an `images` folder to KOReader's home folder as before. New `WP.startFolder`.

## 2026-11-19 — 1.2.46 French and Italian; translation fixes

- **French and Italian.** New catalogues `l10n/fr/aleph.po` and `l10n/it/aleph.po`, with every one of Aleph's 1,670 texts (plurals by each language's rule: French counts 0 as singular, Italian as plural). KOReader set to French or Italian now shows Aleph in that language; fr_CA, fr_BE, it_CH and the like use them too. Where KOReader has its own translation of a word, KOReader's is still used first.
- **Portuguese and Spanish checked** against the English, text by text. Fixed: "score de diversidade" → "pontuação de diversidade" (twice); a Bingo text and a sleep text in Spanish; "Go to in book"; "Aqua" in Portuguese; the Goodreads sign-in screen's "a computer reached this e-reader"; "Home" left in English in three Portuguese and Spanish settings ("Igual à Home", "Home e widgets", "Home, widgets…") now "Início"/"Inicio"; Portuguese "Accents" no longer reads like "Highlights".
- `aleph_gettext.lua`'s notes and the README list the four languages.

## 2026-11-19 — 1.2.45 Rename and delete collections

- **The Collection list** (Home's Collections link, or Library → the
  collection button; aleph_browser.lua, aleph_library_view.lua): holding a
  collection offers Rename and Delete, through KOReader's own collections
  (aleph_local.lua), so the file browser shows the same. Deleting keeps the
  books. Favorites, KOReader's own, is neither renamed nor deleted. A line
  under the list says so: "Hold a collection to rename or delete it."
- **A collection from Calibre's #collections column** asks first: Aleph
  fills it from Calibre, so renamed or deleted on the device it comes back
  with its books, beside any new name; the way to change it for good is in
  Calibre. "Change here anyway" goes on; Aleph then forgets what it put in
  it (aleph_calibre_collections.lua, CC.forget), so a renamed collection is
  the device's own and is never emptied by the next run.

## 2026-11-19 — 1.2.44 Reading bingo: medium tile, bigger bold squares

- **Reading bingo widget** (aleph_board_widgets.lua): a 5 × 5 card in a
  medium tile has no room for even the marks-only card, and the tile said
  "Could not draw this widget". It now shows how many are read (3 / 24
  read), a bar, and the bingos (or the rule while there are none); at the
  smallest, the count beside the title.
- **The card's page** (aleph_bingo_page.lua): the challenges one size
  bigger (11 on a 5 × 5 card, 13 on a 4 × 3 one) and in bold.

## 2026-11-19 — 1.2.43 Edit Home's buttons without the wallpaper text outline

- **Edit Home** (aleph_board_host.lua): with "Text over the wallpaper" set
  to Outline (or Light), the Done button at the top and the Add widget and
  wallpaper buttons at the bottom took the outline (or the light colour)
  meant for Home's text over the picture. They are buttons on their own
  background, so they are now drawn as usual; the page title, its hint,
  the page name and Pages keep the wallpaper's text style.

## 2026-11-19 — 1.2.42 Goals rings: clear of the ring, names above

- **Goals, large** (aleph_board_widgets.lua): "/ 30 min" under the count was
  drawn from the left edge of the ring's inside and touched the ring; the
  count and the goal are now centred in the middle three quarters of the
  ring, the goal a size smaller or without its unit when it would not fit.
  Each goal's name is centred above its ring instead of under it, with the
  check right beside the name once the goal is met.

## 2026-11-19 — 1.2.41 Goodreads: its answer in crash.log; a book it will not shelve found again

- **What Goodreads answered** (aleph_gr_legacy.lua, aleph_gr.lua,
  aleph_goodreads_track.lua). A crash.log showed Milk Fed never put on
  Currently reading, with only "Could not parse the Goodreads response".
  Now every answer of 400 or more to a change is written to crash.log with
  its address, code and the start of its text ("POST /shelf/add_to_shelf
  answered HTTP 404: Page not found"), and the failure lines of the
  background tracking and of the waiting list end with it.
- **A book Goodreads will not shelve under its id** (the Goodreads id from
  Calibre, here 54310688): when shelving fails for a reason other than the
  sign-in, Goodreads is searched for the same title (up to a subtitle) and
  one of the author's names; a match on no shelf there is shelved instead,
  and the book linked to it. The id given up is kept in the book's link as
  unshelvable, so Send to Goodreads no longer goes back to it from Calibre's
  id. Logged as "Aleph: Goodreads: relinked … (Goodreads would not shelve …)".

## 2026-11-19 — 1.2.40 Colours for Reading DNA, Reading rhythm and Year projection

- **Colours** (aleph_board_colour.lua): Reading DNA teal, Reading rhythm
  green, Year projection orange. Monthly challenge, Reading bingo and
  Weather stay blue, now named so instead of falling back to it.

## 2026-11-19 — 1.2.39 Goals and Diversity score in their own colours; rings on a large Goals

- **Colours** (aleph_board_colour.lua): the widgets added since 1.2.24 had
  no colour family and all fell back to blue. Daily goal is now gold (like
  Pick back up), Weekly goal violet (like Series), Monthly goal rose (like
  Word of the day), Goals and Diversity score gold (like On device).
- **Goals, large** (aleph_board_widgets.lua): a ring for each goal that
  fills as the goal is reached (whole once met), done and / goal inside it,
  its name under it with a check once met; two by two on a tall tile, in
  one row on a wide, short one. Smaller tiles keep the bars and lines.

## 2026-11-18 — 1.2.38 Startup: covers never made while the screen waits; cleanup

- **Covers** (aleph_cover_job.lua, aleph_browser.lua). A crash.log showed
  KOReader stopping for 5 minutes 35 seconds just after starting, while
  Aleph drew a screen of covers, with the device so busy that drawing one
  small icon took 11 seconds. When the background process that makes
  covers could not be started once (memory short as KOReader starts, for
  example), Aleph gave it up for the whole run and made every missing cover
  in KOReader's own process, one after another every 0.02 seconds, the
  screen waiting each time. Now a failed start is written to crash.log and
  tried again after 30 seconds; covers are made in KOReader's process only
  on a device that has no background processes at all, then one each half
  second, with any cover taking 2 seconds or more written to crash.log.
- **Startup tasks that never ran** (main.lua). The Goodreads plugin warning
  and the memory diary's first line were in Board:onFileManagerReady, which
  KOReader never sends to Aleph: they now run from the file browser's
  first build, once a start.
- **Cleanup** (checked with luacheck): functions nothing called (Statistics
  reader's sync helpers from BookOrbit and their SQL, a title-bar
  stand-in, Settings' old Library folders menu, a pinned-shelf adder,
  a ZenOS check, a "time ago" formatter, an app-hiding setter, a cover
  aspect helper and its cache, a font helper), unused imports and
  variables, a list of name particles X-Ray never used, a duplicate icon
  definition, two unused icon files (chevron-first, chevron-last), and the
  translations of the removed menu.

## 2026-11-18 — 1.2.37 X-Ray: detailed descriptions; where a name comes up and who with

- **Detailed descriptions** (Settings → X-Ray, off unless turned on;
  aleph_xr_ai.lua), after BookOrbit's Constellations, whose character
  descriptions read better: ours came from two excerpts of a few words for
  each of up to 60 names, in at most two sentences. With it on, the
  question also holds the Story's chapter summaries (the latest 16,000
  characters of them, when there are any), and for the 15 names mentioned
  most: eight passages of a sentence or two each (the first mention, two in
  the chapter it comes up most, the three latest, some between) and the
  four names most often near it. Those 15 get 3–4 sentences (who, role,
  relationships, what they have done so far); the others as before. The
  question is several times longer: for accounts with a larger allowance.
  Nothing from a page not read is sent. The passages are read from the
  book in the background process with the question.
- **A name's card** (aleph_xr_page.lua, aleph_xr_more.lua), on the device
  with no AI, so not under the option: **Where it comes up**, a bar for each
  chapter read (grouped past 40 chapters; the chapter being read in grey)
  with First seen, Most mentions and Latest; **Often with**, the four names
  most often within four mentions of it, each opening its own card. The
  description shows up to 10 lines.

## 2026-11-18 — 1.2.36 Goodreads sign-in row says whether it is signed in

- **Settings → Library → Goodreads sign-in** shows "Signed in" or "Not
  signed in" underneath (a sign-in saved, by Aleph or by advokatb's plugin,
  in the shared Goodreads settings). Tapping it still opens the screen that
  receives a new sign-in from the computer.

## 2026-11-18 — 1.2.35 Who keeps asking for redraws; the Goodreads warning stays

- **aleph_redraw_watch.lua**: two crash.logs showed "not painting 1 covered
  widget(s)" about 16 times a second for as long as Home was open (once 37
  minutes in a row): something kept asking KOReader to redraw a screen
  hidden under another, keeping KOReader busy, and KOReader does not log who.
  Aleph now counts UIManager:setDirty calls; when they stay above 8 a second
  for 3 seconds, the next 40 are traced and the most frequent caller is
  written to crash.log once, as "Aleph: redraw asked N times a second …,
  mostly by <file:line> for widget "<name>"; traceback: …". Each caller once
  a run, five at most.
- **The "Goodreads is now part of Aleph" warning** (aleph_gr.lua) closes only
  with its Turn off / Later buttons: a tap outside it (a page turn, when it
  shows over a book) closed it before it was read. aleph_confirm.lua has a
  `modal` option for this.

## 2026-11-18 — 1.2.34 A memory diary in crash.log

- **aleph_mem.lua**: a crash.log showed KOReader killed as the Kindle went to
  sleep, with the memory left falling from about 340 MB to 46 MB over 44
  minutes of reading, and nothing to tell what took it. Aleph now writes a
  line when a book opens and closes, every 10 minutes while reading, as the
  device goes to sleep and wakes up, and when the file browser is ready:
  the memory the device has left, what KOReader's own process holds and how
  much of that is Lua, each with the change since the previous line (for
  example "Aleph: memory while reading: device has 260 MB left (-40),
  KOReader uses 150 MB (+30), of which Lua 20 MB — changes since 18:01").
  Memory falling while KOReader stays the same points at something outside
  KOReader; KOReader growing points at a plugin; Lua growing points at a
  plugin's Lua code. Below 50 MB the line is a warning.
- **Bottom line** (aleph_bookends.lua): the last page of the last chapter
  no longer leaves a warning in crash.log (KOReader gives no pages-left
  number there).

## 2026-11-18 — 1.2.33 Goodreads: warning about advokatb's plugin; only Aleph's own

- **A warning while advokatb's Goodreads plugin is on** (aleph_gr.lua,
  Core.warnPlugin): each time KOReader starts, a moment after the file
  browser or a book is ready, "Goodreads is now part of Aleph" says the
  plugin is no longer needed and that Aleph sends nothing while it is on.
  **Turn off** turns it off as Plugin management does and offers to restart;
  **Later** leaves it until the next start. Settings → Library has the same.
- **Aleph no longer works through the plugin at all.** Removed: the
  background tracking that stood in for the plugin's own calls (Track in the
  background, its setting and the code swapping the plugin's functions);
  sending the sign-in, Send to Goodreads and the reader menu's Goodreads
  button through the plugin's code. All of them use Aleph's own Goodreads.
  aleph_goodreads_track.lua now only tracks the open book for Aleph (and no
  longer sends Read from the percentage: Read goes with the book's status).
  Send to Goodreads is always in a book's ⋯ menu.
- Unused parts of the plugin's code taken in 1.2.32 removed (its menu's
  settings, status lists, removing a book from Goodreads, the connection
  test, reading identifiers from the open document).
- Tested end to end: opening, progress, Finished heard twice sent once,
  re-finishing a Read book sends nothing, stars, offline queue, failures.

## 2026-11-18 — 1.2.32 Goodreads inside Aleph

- **Aleph keeps Goodreads up to date itself** (aleph_gr.lua), in place of
  advokatb's Goodreads plugin, whose Goodreads code is taken in under MIT
  (aleph_gr_api, aleph_gr_legacy, aleph_gr_parser, aleph_gr_ids,
  aleph_gr_settings; THIRD_PARTY_NOTICES.md). It uses the plugin's own
  files, so the sign-in, settings, book links and anything waiting to be
  sent carry over as they are.
- **Why**: the plugin marked a finished book Read twice ("Read 2 times"):
  once from the end of the book, again from the status change, each time
  shelving and dating it. Aleph now asks Goodreads first, every time: a book
  that is Read there gets its stars only and is never shelved or dated
  again, and nothing moves a book off Read automatically. The same change
  heard twice (Aleph and KOReader) is put on the list once.
- What is sent, always in a background process: a book linked on opening by
  the Goodreads id in the book (Calibre) or its ISBN; Currently reading
  (asked first, as before); the percentage at most once a minute and when
  the book closes; status changes from the book page, Home or KOReader
  (Finished → Read with the day and the stars, Reading → Currently reading,
  On hold → Did not finish if the account has that shelf, Unread → Want to
  read only for a book Goodreads does not have); stars changed on a Read
  book. Not for many books changed at once.
- Offline: changes wait and go when Goodreads can be reached (Wi-Fi is not
  turned on); five failures put one aside. Settings → Library → Goodreads →
  Waiting to send shows them, sends now, or drops the failed ones.
- **Settings → Library → Goodreads**: Keep Goodreads up to date, Track every
  book, Send the percentage, Send the stars. While the plugin is still on,
  Aleph sends nothing and offers **Turn the plugin off** (as Plugin
  management does, then a restart).
- **The reader menu's Goodreads button**: this book on Goodreads, Send
  progress now, Track / Stop tracking this book.
- The background tracking of the plugin (while it is on) also asks Goodreads
  before marking Read now.
- Fixed in the plugin's code: the ISBN check (a pattern Lua does not
  understand, and a list that stopped at the first missing name).

## 2026-11-18 — 1.2.31 Goodreads: the book's own Goodreads id wins

- **Send to Goodreads** (aleph_goodreads_send.lua). The Goodreads id
  written for the book (Calibre's goodreads identifier) now always decides
  which Goodreads book is used. A link saved before to another edition (a
  search result, or a match made before the id was added) used to win and
  could put the book on Goodreads twice; now, when the id differs from the
  saved link, the book is looked up by its id, the old link and what the
  Goodreads plugin kept of that edition (review, status, shelf) are
  forgotten, and the new link is saved, so the plugin uses the right
  edition from then on too. Logged in crash.log.
- The id (and ISBN) is read from metadata.opf next to the book as well as
  from the EPUB's OPF, in both of Calibre's forms (opf:scheme="GOODREADS"
  and "goodreads:123"), so it works for books in a Calibre library folder
  and for other formats beside one.

## 2026-11-18 — 1.2.30 Tap an author on a book's page

- **A book's page** (aleph_detail.lua): tapping the author's name opens the
  list of that author's books, as "More by …" in the ⋯ menu does. With
  several authors that fit on the line, each name opens its own; otherwise
  the whole line opens the first author's.

## 2026-11-18 — 1.2.29 Low memory: background work waits; memory in crash.log

- **aleph_mem.lua**: memory available (MemAvailable in /proc/meminfo, or
  MemFree + Buffers + Cached), and "low" below 50 MB. A crash.log showed a
  Kindle at 23 MB drawing Home in 55 seconds (2 seconds an icon) and then
  stopping: out of memory, everything swapping.
- **Optional background work waits while memory is low** (aleph_job.lua,
  Job.start(fn, { optional = true })): the weather update, Collections from
  Calibre and Goodreads in the background are not started then (each
  background process is a copy of KOReader's), and are tried again later
  as usual (the weather after 15 minutes, collections at the next Home,
  Goodreads at its next step). Work you ask for (X-Ray, covers, the library
  index) is not held back.
- **crash.log** gets a line each time a Home page is built: the memory
  available and the widgets on it ("Aleph: Home page 1 built, memory
  available 212 MB: hero, weather, light, ..."), and one each time
  background work is put off.

## 2026-11-18 — 1.2.28 Reading bingo

- **Reading bingo** (Customize Home > Add widget > Stats; sizes L, XL, M;
  aleph_bingo.lua, aleph_bingo_page.lua, W.bingo). A card of 12 (4 x 3) or
  24 (5 x 5, free centre) challenges: half genre, a quarter places and
  cultures, a quarter literary experiments, drawn from pools of 36, 24 and
  24 and mixed so no row is all one kind; rows, columns and (5 x 5)
  diagonals are bingos. The widget shows the card (the challenges, or
  marks on a small tile; filled squares with the book's cover or title and
  a check; bingo lines framed heavier) and "7/24 read · 1 bingo". The full
  card page: per square Choose a book…, Another challenge, Write my own…,
  Empty this square; New card (12 or 24). Saved in aleph.bingo.
- **Filled by itself** when a book is finished (Local:setStatus, and
  Local.refreshClosing when a book closes finished): first a square named
  by Calibre, a #bingo column (read from the book's OPF, metadata.opf or
  USB metadata.calibre, with aleph_calibre_collections.lua, now asked for
  any column) or "bingo: …" tags (matched to a square's text, part of it,
  its English text or its id; these tags no longer count as genres); then
  a square whose rule the book meets (whole words among its genres and
  tags, comic files, page count, release year); else a question listing
  the open squares, with Not now. Several books marked Finished at once are
  placed but never asked about.
- Translatable pool texts are marked with N_ (the extractor reads them) and
  translated where shown, so Calibre can name squares in English too.
- New icon: grid-3x3 (Lucide). Translations (pt_BR, es).

## 2026-11-18 — 1.2.27 Monthly challenge, Reading rhythm, Year projection, Diversity score

- Four widgets after BookOrbit 3.8.0's of those names (Customize Home >
  Add widget > Stats; aleph_more_stats.lua for the rules, from BookOrbit's
  dashboard-widget.calculations.ts and .repository.ts; aleph_board_widgets.lua
  W.challenge, W.rhythm, W.projection, W.diversity):
  - **Monthly challenge** (M, S): one of BookOrbit's six, chosen from those
    that suit how you read and kept for the month (aleph.challenge): Quick
    Read, Genre Explorer, Clear the Backlog, Streak Builder, New Voice, Page
    Turner. Its title, what to do, a bar and done / target, or Complete!
    Genre Explorer and New Voice count only genres and authors you had not
    finished before (BookOrbit counts any of the month's).
  - **Reading rhythm** (M, W, L): the last 14 days as bars (a short line on
    a day without reading, the day's initials under them), active days, the
    consistency (their share) and the average a day.
  - **Year projection** (M, L): at the last 30 days' pace, books by the end
    of the year (finished so far plus the rest), pages and hours over a
    year; trending up or down when that pace is 15% above or below the
    year's own so far (BookOrbit's trend has nothing to compare with yet).
  - **Diversity score** (L, M): the average of genres read of the library's,
    authors per book, the span of release years (only when known, from the
    extra filters; left out of the average otherwise) and languages; the
    four as bars, a label (Deep Specialist to Literary Adventurer), from
    three finished books.
- Data: the dashboard hands over its finished and in-progress books (not
  copied) and the library's genre count; pages read come from one new
  statistics query (aleph_stats_reader.lua, pagesSince: distinct pages
  since the month's start and the last 30 days), the days from the year's
  heatmap. Each is worked out only when its widget is on Home.
- New icons: trending-up, trending-down, move-right, telescope (Lucide).
  Translations (pt_BR, es), close to BookOrbit's own.

## 2026-11-18 — 1.2.26 Reading DNA widget

- **Reading DNA** (Customize Home > Add widget > Stats; sizes L and M;
  aleph_dna.lua, aleph_board_widgets.lua W.dna). After BookOrbit 3.8.0's
  widget: the rules (scores, words and archetypes) are BookOrbit's
  computeReadingDna (server/src/modules/dashboard/
  dashboard-widget.calculations.ts), checked against BookOrbit's own test
  cases. A name in quotes ("Rapid Explorer"), five bars between the
  trait and its word (Length, Variety, Rhythm, Time, Speed), and "Based on
  N books". Shown once five books are finished, as in BookOrbit; a small
  tile shows the name alone. A tap opens Reading insights.
- Fed from this device: the finished books' average page count (Calibre's
  or KOReader's) and distinct genres from the library index (the
  dashboard's dnaBooks); the share of the last 182 days with reading
  (the year's heatmap); the hour read most in the last 90 days and pages an
  hour over the last year (already read for When you read and Reading
  records). Computed only when the widget is on Home.
- New icon: dna (Lucide). Translations (pt_BR, es), the trait names as
  BookOrbit's own Portuguese and Spanish have them.

## 2026-11-18 — 1.2.25 Daily, weekly and monthly goal widgets

- **Daily goal, Weekly goal, Monthly goal** (Customize Home > Add widget >
  Stats; sizes S and M; aleph_board_widgets.lua goalOne). Each goal of the
  Goals widget on its own (the yearly one is Goal pace): the label (Today,
  This week, the month's name) with a target, or a check once met; done /
  goal large; a bar; and what is left: "18 min to go", "2 days to go",
  "1 book to go · 12 days left" (the month's days left), or Goal met.
  The weekly one adds the week's days as dots under their initials:
  filled where you read, ringed where you did not, faint for days to come,
  today's initial in bold. Smaller tiles drop the line, then the bar.
  A goal set to 0 says where to set it; a tap opens Settings > Profile.
- aleph_board_data.lua: the week's goal also keeps each day of the week
  (read, not, to come), its initials and today's place.
- Translations (pt_BR, es); Spanish goal wording made "objetivo" throughout,
  as Goal pace has it.

## 2026-11-18 — 1.2.24 Goals widget: day, week, month and year

- **Goals** (Customize Home > Add widget > Stats; sizes L and M;
  aleph_board_widgets.lua W.goals). Four goals together, laid out like
  Reading records: minutes read today, days read this week, books finished
  this month and this year. Each shows done / goal, a bar and a check once
  met; a short tile shows one line a goal. A goal set to 0 is left out;
  with none set, the tile says where to set them. A tap opens
  Settings > Profile.
- **Settings > Profile > Goals widget**: Daily goal (minutes, 5 to 1440 in
  steps of 5), Weekly goal (days, 1 to 7), Monthly goal (books, 1 to 100);
  − below the least turns one off, + turns it on again, and the number can
  be typed. Defaults 30 minutes, 5 days, 2 books. The yearly goal is the
  Annual reading goal above them.
- Data: aleph_local.lua (Local.goalSetting; the dashboard's readingGoal
  gains the three goals and this month's finished books) and
  aleph_board_data.lua (BoardData.goals: today's minutes, this week's days
  with reading from this device's statistics, the week starting on the
  first day KOReader's statistics calendar uses, Monday unless set). No
  extra reading of the statistics.
- Translations (pt_BR, es); "day" and "book" now have their plurals.

## 2026-11-18 — 1.2.23 Sort by progress in Reading

- **Library > Sort and filter** (aleph_browser.lua, sortsFor; the sheet in
  aleph_library_view.lua). With Show set to Reading, Sort by has a sixth
  choice, Progress, ordered Most read or Least read first (the library's
  own progress sort, Local:query). Its toolbar label says which. Showing
  anything else again puts Progress back to Last read. The six labels are
  set a size smaller so they fit.
- Translations (pt_BR, es).

## 2026-11-18 — 1.2.22 Hold Wi-Fi in the top menu: networks in range

- **Holding the Wi-Fi tile** in the top menu's Controls tab
  (aleph_topbar.lua, TopBar:controls) does what holding KOReader's own
  Wi-Fi item does instead of opening the icon chooser: with Wi-Fi off it
  comes on and the list of networks in range follows (NetworkMgr's long
  press); with it on, the list at once (reconnectOrShowNetworkMenu with the
  long-press flag). The other tiles still change their icon when held.
- **Settings > Top menu > Wi-Fi icon** changes that tile's icon now
  (aleph_settings_page.lua, same setting as before).
- Translations (pt_BR, es).

## 2026-11-18 — 1.2.21 Fonts for Home and the top menu

- **Settings > Home > Font** (aleph_fonts.lua; aleph.font_home). The font
  of Home, its widgets, the library, book pages, sheets and Aleph's
  windows, from KOReader's fonts (its own and its fonts folder, read from
  its font cache, one per family, with its italic when there is one). Each
  name is shown in its own font, a page at a time, so only the fonts on the
  page are opened. Noto Sans unless chosen; a font no longer there falls
  back to it. Only the sans faces change; quotes keep Noto Serif.
  - aleph_board_metrics.lua: setSans swaps the sans faces; a line's height
    follows the font (measured once against Noto Sans, never shorter than
    Noto's, at most 1.9 em) so tall letters are not cut. font_gen counts
    changes.
  - aleph_board_ui.lua: BoardUI.resetFits forgets measured sizes and chosen
    layouts after a change; text() takes a face (the picker's previews).
- **Settings > Top menu > Font and Text size** (aleph.font_menu: Same as
  Home unless chosen; aleph.menu_scale, 80% to 150%). The size scales the
  whole top menu with its text (aleph_topbar_style.lua, Style.px and
  Style.face): rows, icons, tabs and the Controls and Apps panels, whose
  columns already follow the width. Takes effect the next time the menu
  opens.
- Light: KOReader opens a font once and keeps it; drawing is no slower.
- New icon: a-large-small (Lucide). Translations (pt_BR, es).

## 2026-11-18 — 1.2.20 Bluetooth switch with the Kobo plugin

- **The reader menu's Bluetooth switch** (aleph_reader_sheet.lua,
  Sheet.bluetooth) now also works with OGKevin's Kobo plugin
  (kobo.koplugin), which turns a Kobo's own Bluetooth on and off and
  handles page turners itself. On a Kobo it supports Bluetooth on (Libra 2
  and the MTK models: its KoboBluetooth:isDeviceSupported), the switch shows
  whether Bluetooth is on (isBluetoothEnabled) and a tap calls its
  toggleBluetooth; elsewhere, BT Manager - HID Passthrough as before.
  Turning on runs in the background in the plugin (a few seconds, Wi-Fi on
  for it as the plugin does), so the switch is checked again after 3.5 and
  7 seconds rather than at once. Nothing of the plugin is changed.

## 2026-11-18 — 1.2.19 Home's text over a dark wallpaper

- **Text over the wallpaper** (aleph_wallpaper.lua sheet: Auto, Dark,
  Light; Outline). Home's own text, drawn straight over the wallpaper and
  not on a widget (the greeting, date, Wi-Fi, battery, clock, search and
  menu at the top; the arrows, page dots and page name at the foot, and the
  same in Customize Home), was always black, so a dark picture hid it.
  - **Auto** (the default) looks once at how light the picture is behind
    the top and behind the foot, as drawn after the wallpaper opacity, and
    uses light text over a dark part. Dark and Light choose it.
  - **Outline** draws an edge in the other colour round each text, icon and
    dot: the same thing painted in that colour a pixel away in eight
    directions, then itself. No images or fonts are made.
  - Done by an "ink" the board's drawing parts follow while only the header
    and the foot are built (aleph_board_ui.lua: BoardUI.withInk, inkCol,
    inkHex, Halo): grays inverted, colour-scheme colours kept. Nothing
    changes without a wallpaper or with dark text and no outline; the
    status corner's redraw each minute keeps the ink it was built with.
  - Settings: aleph.wallpaper.text ("dark", "light"; none for Auto),
    aleph.wallpaper.outline.
- Widgets keep their own background, so their text is unchanged; over a
  dark picture, a higher Widget opacity keeps them light.

## 2026-11-18 — 1.2.18 Goodreads: Read never sent twice

- **Send to Goodreads** (aleph_goodreads_send.lua, Send.send). A finished
  book sent from its page could still show as read twice. Read is now
  never sent on a guess:
  - The book counts as Read already when Goodreads' page says so, or when
    the Goodreads plugin has it as Read in the sidecar (marked by the
    plugin or by Aleph's background tracking when the book was finished),
    unless Goodreads' page says it is on another shelf. Goodreads' page can
    come back without its shelf when its layout changes, which let Aleph
    shelve and date the book again.
  - A book already Read gets its rating only: no shelving and no date, not
    even when no reading date is found (an extra date is the second
    reading).
  - When what Goodreads has cannot be asked at all, nothing is sent and the
    page says so.
  - What Goodreads had before sending (shelf, number of readings, review)
    is written to crash.log, to tell what happened if it happens again.

## 2026-11-17 — 1.2.17 Collections from Calibre; Aleph above Bookshelf

- **Collections from Calibre** (aleph_calibre_collections.lua; Settings >
  Library > Collections from Calibre, on unless turned off). A Calibre
  column with the lookup name "collections" (#collections; "collection"
  too), a list like tags or text split on commas, puts each book in the
  KOReader collections of those names (made when missing), which are
  Aleph's collections. Read from metadata.opf next to the book, the OPF
  inside an EPUB (written by Calibre when it sends, saves or polishes with
  metadata, OPF 2 and OPF 3), or Calibre's USB metadata.calibre. Calibre
  is mirrored for what Aleph placed: a book sent again without a collection
  leaves it; books added on the device and collections made there are never
  touched. Each book is read once and again only when its file (or its
  metadata.opf) changes, in a background process (sliced on the UI loop
  where there is none), after each library scan and when Home opens, at
  most once a minute; state in settings/aleph_calibre_collections.lua.
- **Aleph stays up with Bookshelf** (aleph_shelf_guard.lua; main.lua
  Board:onShowAleph). Bookshelf stays under a book opened from it and puts
  itself back on top when that book closes, so Aleph Home from the reader
  menu flashed Aleph and returned to Bookshelf. When Aleph is asked for
  (reader menu, "Aleph: open" gesture, menu item, top-bar tab), Bookshelf's
  screen is closed if it is above Aleph, then and for 3 seconds after, the
  way Bookshelf's own "Bookshelf: open or close" closes it. Not at startup
  (Bookshelf's Start with decides), not while Bookshelf has a book parked
  under its screen, and nothing at all without Bookshelf loaded.
- Translations (pt_BR, es).

## 2026-11-16 — 1.2.16 Weather widget

- **Weather** (aleph_weather.lua; Customize Home > + Add widget > Device >
  Weather; sizes S, M, W). The temperature now, the sky in words and an
  icon (sun or moon at night, cloud, rain, drizzle, snow, fog, storm),
  today's high and low; a wide tile adds the next two days. A tap opens
  Update now, the place (typed once and picked from Open-Meteo's places)
  and °C or °F.
- **Kept light.** The module is loaded only when the widget is on Home. It
  never turns Wi-Fi on: it asks only when Home is drawn with Wi-Fi already
  connected, at most once an hour (not again for 15 minutes after a
  failure), in a background process (aleph_job.lua) so Home never waits.
  No timers. The answer (about 1 KB) is kept in settings/aleph_weather.lua
  and shown with its time when it is more than 6 hours old.
- **Privacy.** Data from Open-Meteo (open-meteo.com, no account or key,
  CC BY 4.0). Only the place's latitude and longitude, rounded to about a
  kilometre, and the units are sent.
- Seven Lucide weather icons added (aleph_icon_data.lua). Translations
  (pt_BR, es); the weather words have the context "Weather" so "Clear"
  does not clash with the button.

## 2026-11-16 — 1.2.15 Go to most recent page after any jump

- **A way back after every jump in a book** (aleph_search.lua,
  Search.installJumpBack; Settings > Reader > Way back after a jump, on
  unless turned off). The strip that searching leaves at the foot of the
  page ("‹ Go to most recent page", "From page 102 to 1688", then "Return
  to page 102 ›") now also comes after any jump KOReader keeps in its Go
  back history: the table of contents, Go to page, a link or footnote, a
  bookmark or highlight, a pin, the page browser, an X-Ray mention, a
  chapter's "Go to chapter". KOReader notes the place left just before
  each of them (ReaderLink:addCurrentLocationToStack); Aleph notes it too
  and, once the jump is done and the page changed, shows the strip. Its
  chevron, a tap on the page or a page turn put it away. While searching,
  the search's own bar and way back are used instead.
- New icon (Lucide, ISC): undo-2.

## 2026-11-16 — 1.2.14 Time left: one estimate for Home and the book

- **Continue reading and the book's own status bar now agree on the time
  left** (aleph_stats_reader.lua, aleph_board_data.lua, aleph_bookends.lua).
  They were worked out two ways:
  - In the book, KOReader's statistics (and Aleph's "time left in book"):
    the time on each page of the book's present layout, each page counted
    at most 2 minutes (KOReader's "max_sec" setting), divided by the pages
    read, times the pages after the one shown.
  - On Home: every reading event counted up to 10 minutes, divided by the
    page numbers ever read whatever the layout, times the largest page
    count the book ever had. A long pause on a page, or a change of font
    size (other page numbers), made it drift from the book's figure. It
    was also worked out once a day, so it did not follow the reading.
  KOReader's way is the fairer one (a pause on a page does not count as
  reading, and pages are those of the layout read now), so Home now uses
  it: the same capped time per page from the statistics' page_stat view,
  the book's present page count, and the pages after the one reached. It
  is worked out again whenever the statistics change. Aleph's own margin
  counted the page shown as still to read; it now counts as KOReader does.

## 2026-11-16 — 1.2.12 Goodreads: no second reading; Calibre page count

- **Send to Goodreads no longer makes a book "read 2 times"**
  (aleph_goodreads_send.lua). The Goodreads plugin marks a book Read when it
  is finished. Sending from the book page then added it to the Read shelf
  again, which Goodreads keeps as another reading. Aleph now asks Goodreads
  for the book's state first (the plugin's own get_review_state); a book
  already Read is not shelved again: its rating is sent when it differs, and
  its finished day only when it has no reading session yet (the plugin's
  set_date_finished adds a session only then). A book not yet Read is sent
  as before. Books already doubled on Goodreads are not touched: delete the
  extra reading on goodreads.com (the book's page, Reading sessions).

- **Calibre's page count is found in an OPF that writes `<opf:meta>`**
  (aleph_pages.lua, Pages.fromOpf). The parser looked only for `<meta`, so an
  OPF whose Calibre columns are in `<opf:meta property="calibre:user_metadata">`
  was missed and KOReader's own count (1,137 for one book) was shown instead of
  Calibre's (306). A namespace prefix on the tag is accepted now, for both the
  one-blob form (OPF 3) and the one-tag-per-column form (OPF 2).
  A second fault was behind it: the first column whose name mentions "page" was
  taken, and Calibre users often have "#npages", a text column of page-count
  buckets whose value is "300s"; its leading digits were read as 300. A
  column's value must now be a plain number, and a column named just "pages"
  wins over one that only mentions pages. Tried on the OPF of the book above
  (306) and on both forms, with and without the prefix.

## 2026-11-16 — 1.2.11 (testing)

Speed and battery:

- **The reading page's minute tick repaints only when a line changed**
  (aleph_bookends.lua, Bookends.stale). With battery, Wi-Fi or light on the
  top or bottom line but no clock, the e-ink refresh every minute is gone;
  with a clock it still happens each minute.
- **The page turner's battery is asked without waiting** (new
  aleph_local_get.lua; aleph_page_turner.lua). HID Passthrough's daemon was
  asked from KOReader's own process, holding it up to two seconds when the
  daemon was slow; now the question goes out and the answer is looked for
  from KOReader's loop, the bottom line drawn again if the level changed.
- **Without HID Passthrough, no page-turner work at all**
  (aleph_page_turner.lua): a few seconds after a book opens Aleph looks
  once; with the plugin not installed nothing is asked, nor looked for on
  touches or paints, for that book.
- **One paint hook for the page** (new aleph_reader_paint.lua): the margins
  in scroll mode, the top and bottom lines, the pin badge and X-Ray's
  underlines each wrapped KOReader's page paint; they now share one, in the
  same order, and a part that fails no longer stops the others.

Code shape (nothing meant to look or work differently):

- **Background jobs and data files in one place** (new aleph_job.lua and
  aleph_file.lua): X-Ray's scan, descriptions and story, Goodreads
  tracking, covers, portraits and the library index each had their own
  copy of starting a background process, watching it and stopping one that
  takes too long, and four their own file reader and writer.
- **Long functions split**: none is over 100 lines now (21 were, the
  longest 299: Home's book being read). Among them the sync chain (one
  function per step), the pin drawer and badge placer, the highlight sheet
  and actions menu, the dictionary's restyling, the reader menu's buttons
  (one function each instead of one long chain), Home's Add a widget
  sheet, the series page, the bookmarks page and filter bar, the wallpaper
  sheet, the Goodreads cookie receiver, the icon picker and the hero, link,
  heatmap, forecast, goal and badge tiles. Nothing is nested deeper than
  seven levels (three functions were at eight or nine).
- **Long lines**: 71 lines over 200 characters broken after commas (the
  rest are single texts to translate, kept whole).

How this was checked: every reworked part was driven through its cases
(screen sizes, tabs, data, taps, gestures, failures) in both 1.2.10 and
1.2.11 and every widget it built and call it made recorded; the twelve
recordings (about 400,000 lines) are identical. The line breaks change no
token of the program.

## 2026-11-15 — 1.2.10 (testing)

GitHub issue #5 (N9TailedFOX, Kobo Libra Colour):

- **Goal pace said only how far behind pace** (aleph_board_widgets.lua). The
  count was right (pace is where the goal says you should be by today: 12
  books a year is about 10.5 by 15 November, so 2 read is 8 behind pace)
  but read as if it were what is left. It now says both when there is
  room: "10 to go · 8 behind pace" (and "ahead"), down to "8 behind" when
  narrow.
- **Customize Home's bar at a large interface size** (aleph_board_host.lua):
  the Pages button, right of + Add wallpaper, went off the screen. When the
  bar does not fit, the page's name and the word "Pages" go first (an icon
  is left), then + Add wallpaper becomes an icon.
- **Empty pages are skipped** (aleph_board_store.lua, aleph_board_host.lua,
  aleph_browser.lua): outside Customize Home a page with no widgets is not
  turned to and has no dot (the first page always shows). Customizing still
  shows all four, so widgets can be put on an empty one.
- **Rename a page** (aleph_board_edit.lua): Customize Home > Pages > Rename
  this page. The name is kept in Aleph's settings (page_names) and shows
  under Home and on the dots' line; an empty name brings the usual one back.

## 2026-11-15 — 1.2.9 (testing)

- **Pins survive KOReader's Reset** (aleph_pins.lua). Pins are kept in the
  book's own settings, which KOReader's Reset (book information or the file
  browser: "document settings, progress, bookmarks, highlights, notes")
  deletes, its .old backup included; a pin was lost with them. Aleph now
  keeps a copy of every book's pins in settings/aleph_pins_backup.lua, by
  the book's checksum (partial_md5_checksum), updated whenever a pin is
  added or removed, and made the first time a book with pins opens. A book
  that opens with no pins but a copy asks "Bring back this book's pins?":
  Bring back restores them (picture pins too, their files being in
  cache/aleph/pins), Forget them drops the copy, a tap outside asks again
  next time. Removing pins by hand updates the copy, so it never asks for
  pins that were removed on purpose.

## 2026-11-15 — 1.2.8 (testing)

- **X-Ray Story: the story so far, whole** (aleph_xr_page.lua). On the
  Story tab the story so far is cut at 11 lines with "…", and nothing
  showed the rest. Now a tap on it, or "Read all ›" beside "The story up to
  page …" (shown only when it is cut), opens it whole: titled "The story so
  far", with the page it reaches, in pages when it is longer than the sheet
  holds (cut between sentences; the arrows, a swipe or the page keys turn
  them), and The story to go back.

## 2026-11-15 — 1.2.7 (release)

Released as 1.2.7: everything from 1.2.1 to 1.2.7 below, since the 1.2.0
release.

- **X-Ray Story: one row of buttons under a chapter's summary**
  (aleph_xr_page.lua): ‹ · The story · Go to chapter · ›, instead of two
  rows (Previous chapter / Next chapter, then The story / Go to chapter).
  The arrows are round buttons with a chevron only; an arrow with no
  summary that way is drawn faint and does nothing. On a narrow screen the
  two middle buttons drop their icons to keep their words. The summary
  shows up to 14 lines again. Swipes and the page keys still go to the
  summary before or after.

## 2026-11-15 — 1.2.6 (testing)

- **Settings at a large interface size** (GitHub issue #4, a Kobo Libra
  Colour at 1.2x and up): the Settings list itself, and Shortcut, had no
  pages; taller than the screen, the page was centred by KOReader's
  container (LeftContainer centres what overflows), so its top, with the
  back arrow, went off the screen and Settings could not be left.
  - Every Settings view now comes in pages when too tall (aleph_settings_page.lua),
    the list included; the version line under it shows when there is room.
  - A group of rows taller than a page is cut into smaller groups
    (MenuUI.splitGroup; MenuUI.group and MenuUI.section keep their rows for
    it), so a page can always be made to fit.
  - BoardUI.vstack takes `top = true`: content taller than its box is drawn
    from the top. Every full page (Settings, Book margins, Widget actions,
    Top menu, Goodreads import, Bookmarks, Owner information, search results,
    the page browser, long texts) uses it, so a header and its back arrow
    stay on screen whatever the size.
  - Book margins (aleph_bookends_page.lua) comes in pages too when too tall,
    with the arrows at its foot and the page keys (swipes still change tab).

## 2026-11-15 — 1.2.5 (testing)

- **Book margins could not be turned on again once off** (GitHub issue #3,
  reported by tomdolhs, who also found the line): aleph_bookends_page.lua
  stored `action.value and nil or false`, which in Lua is always false. On
  is now kept as no setting (the default) and off as false.
- The same slip in two other places, found by looking for it:
  - **Tapping a book's current rating did not clear it** (aleph_browser.lua,
    rateBook), as the README says it does.
  - **Tapping the selected widget in Customize Home did not unselect it**
    (aleph_board_edit.lua).
  - Goodreads tracking in the background passed a missing Goodreads status
    as nothing instead of "none" (aleph_goodreads_track.lua); the same
    result either way, now written plainly.

## 2026-11-15 — 1.2.4 (testing)

- **Reader menu** (aleph_reader_sheet.lua): the Contents tile is now
  **Search**, which opens the book's search (Aleph's prompt and results
  page with Search like a Kindle on, KOReader's search box with it off). The
  table of contents opens from a tap on the card's Chapter line (the
  chapter and its pages left).

## 2026-11-15 — 1.2.3 (testing)

- **X-Ray Story: the chapter before and after** (aleph_xr_page.lua). A
  chapter's summary has "‹ Previous chapter" and "Next chapter ›" under it,
  to the summaries just before and after it in the book (only those that
  exist: the first has no Previous, the last read no Next). A sideways
  swipe and the page keys do the same. The summary shows up to 12 lines
  (14 before) to leave room for them. Translated into Portuguese and
  Spanish.

## 2026-11-15 — 1.2.2 (testing)

- **Search like a Kindle** (new aleph_search.lua; main.lua; Settings >
  Reader > Search like a Kindle, on unless turned off). KOReader's search
  goes from match to match, or lists them in a plain menu. Now:
  - Aleph's prompt ("Search this book") replaces KOReader's box, from the
    page browser's search, a gesture or the top menu; selected text's
    Search does the same. Both find every match (KOReader's findAllText,
    case ignored), in KOReader's background process that a tap cancels.
  - The results come on a page of their own: "46 results", tabs
    Annotations (highlights and notes holding the words) and Text, each
    match with two lines around it, the word in bold, its chapter and page.
    Swipes, ‹ › and the page keys turn its pages. Holding the search button
    opens KOReader's own search box with its options.
  - A result opens the book there with the match highlighted, and a bar at
    the foot of the page: the page, ‹ Result 3 of 46 ›, ×. Holding an arrow
    goes to the first or last result. The page still turns under it (taps
    and keys go on to the book); "Result 3 of 46" brings the list back at
    that result, whose back arrow returns to the bar.
  - × closes the bar. When the page is not the one being read before the
    search, a strip offers "Go to most recent page" with "From page 53 to
    11"; once there it turns into "Return to page 53". Its chevron, a tap
    on the page or a page turn put it away. The first result opened is also
    put on KOReader's own Go back list.
  - Off, or if the page cannot be shown, KOReader's own search is used.
  - New icon (Lucide, ISC): arrow-left.
- Bookmarks page: the day of each bookmark ("13 Sep") in the reader's
  language too (aleph_dates.lua).
- The new texts are in the Portuguese and Spanish catalogues.

## 2026-11-15 — 1.2.1 (testing)

- **Aleph in Brazilian Portuguese and Spanish** (new aleph_gettext.lua,
  l10n/pt_BR/aleph.po, l10n/es/aleph.po, l10n/aleph.pot). KOReader's gettext
  only translates the texts KOReader itself has, so with KOReader set to
  another language Aleph showed half its screens in English. Aleph now has a
  catalogue of its own for every one of its texts (1,302), in KOReader's .po
  format. Every file requires aleph_gettext instead of gettext (_meta.lua
  excepted: it is read before the plugin's folder is on the path). For each
  text KOReader's translation is used first when it has one, so Aleph's
  words match the rest of KOReader and the texts Aleph looks for on
  KOReader's buttons keep matching; the catalogue fills in the rest.
  The language is KOReader's (Settings > Language); pt_PT takes pt_BR and
  es_* takes es. Plural forms (ngettext) and contexts (pgettext) are read.
  The catalogue is read once, when the first text is asked for.
- The two places that compare Aleph's words with the text on KOReader's own
  buttons (aleph_bookmark.lua, the highlight menu in aleph_highlight.lua)
  ask KOReader's gettext directly.
- **Dates in the reader's language** (new aleph_dates.lua): os.date wrote
  month and day names in English (the bottom line's date, a book's Added
  and last-read dates, highlight dates, Goodreads import days, finished
  dates). Names now come from KOReader's translated tables and the order
  from the catalogue ("15 de nov." / "15 nov"). BoardData's weekday and
  month helpers use the same module.
- "Read" has three meanings in Aleph; the button that opens a book, the
  library's Sort by and the Read widget now each have a context of their
  own, so they can be translated apart.
- Texts made from tables (the book margins' samples, page-count bands,
  Goodreads statuses, the X-Ray provider "Other") are in the catalogue too;
  the provider names in Settings > X-Ray are now translated where shown.
- Not translated on purpose: the legal notices in About, the requests sent
  to an AI provider (they ask for answers in the book's language), and the
  Literary clock's quotes.
- Adding a language: copy l10n/aleph.pot to l10n/<KOReader's code>/aleph.po
  and fill in the msgstr lines.

## 2026-11-15 — 1.2.0 (release)

1.1.60, released as 1.2.0: everything from 1.1.1 to 1.1.60 below, since the
1.1.0 release. For the release only:

- The version is 1.2.0 (_meta.lua); the modification date in README.md, the
  About box (aleph_browser.lua) and the title of this file is 15 November
  2026.
- README.md: the screenshots from the repository's page; the features added
  since 1.1.0 (Literary clock, Owner information, Page turner battery, Night
  profile) in their sections instead of at the end; Night profile, By the
  clock and Owner information in the settings table; Author by first or last
  name in the library's sorting; the Literary Clock's code and quotes in the
  credits.
- A stray compiled file (texluac.out) left at the plugin's top level by a
  syntax check is gone.

## 2026-11-15 — 1.1.60 (testing)

- **Owner information moved** (aleph_menu_sheet.lua): in the menu it now
  comes between Settings and About.

## 2026-11-15 — 1.1.59 (testing)

- **Owner information** (aleph_owner.lua, aleph_menu_sheet.lua,
  aleph_browser.lua, aleph_icon_data.lua): the menu has "Owner
  information" after Settings and About (between them from 1.1.60). Its page shows the owner's name,
  email and phone large under "If you find this e-reader, please contact:",
  with a row to change each (Aleph's text prompt). The menu row shows the
  name once set. Kept in Aleph's settings ("owner"), on the device only;
  emptied fields are removed. New icons (Lucide, ISC): mail, phone,
  contact.

## 2026-11-15 — 1.1.58 (testing)

- **Goodreads tracking in the background** (new aleph_goodreads_track.lua;
  main.lua, onReaderReady; aleph_settings_page.lua): Settings > Library >
  Track in the background, off unless turned on, shown with advokatb's
  Goodreads plugin (0.5.0). That plugin asks goodreads.com from KOReader's
  own process on page turns, on opening and on closing a book; in a log,
  on Wi-Fi with no internet behind it, the reader stood still 15 to 47
  seconds eight times in seven minutes. With the switch on, the plugin's
  automatic calls for the open book (_maybeAutoTrackProgress,
  _runPendingEnsure, _refreshRemoteState, _sendProgress when not asked by
  hand, _flushQueue) are answered by Aleph on that running copy only: one
  question a minute at most, asked in a background process with the
  plugin's own code and sign-in, the answer written to the plugin's
  records after. A failure waits 5, 10, 20, then 30 minutes; a refused
  sign-in is said once and nothing more is asked until it is renewed; a
  book on another shelf on the site asks once, as the plugin does. Asked
  by hand, the plugin works as before. Its files are not changed, and a
  version without those functions is left alone.
- One line per background question in crash.log
  ("Aleph: Goodreads in the background: 34% sent").

## 2026-11-15 — 1.1.57 (testing)

- **X-Ray: "the book is closed" with the book open** (aleph_xr.lua,
  XR.target; aleph_xr_ai.lua; aleph_xr_story.lua): KOReader closes and
  reopens a book by itself when its layout changes; in the log, the night
  profile turned bolder text on at 22:00 while Describe with AI was waiting
  for its answer, and the answer then came back to a reader that no longer
  existed. Results of Describe with AI, Update the story and Find names now
  go to the reader showing that book when they arrive; with the book
  closed in the meantime they are saved with the book all the same.
- **X-Ray writes its outcome to crash.log** (one line per request:
  how many names or chapters, or why it failed, with provider and model).

## 2026-11-14 — 1.1.56 (testing)

- **X-Ray: Story** (new aleph_xr_story.lua; aleph_xr_page.lua): the X-Ray
  sheet has two tabs, Names and Story. Update the story reads the chapters
  up to the page shown (never past it) in a background process, sends
  their text to the AI provider set in Settings, and keeps a summary of
  each chapter and "the story so far" in the book's settings folder
  (aleph_xray_story.lua). A later update sends only the chapters read
  since, with the story so far for context; a chapter being read is
  summarised as far as it was read and done again once finished. Chapters
  come from the book's contents (top level only when there are more than
  150 entries; pieces of 20 pages when there are none). A long book is
  asked about in up to 10 requests per update; a note says to update again
  for the rest. A failure keeps what was already written.
- **X-Ray: The book before** (aleph_xr_story.lua, Story.previous): for a
  book with a series number above 1. Written from the earlier book's own
  chapter summaries when it is in the library and has them; otherwise the
  model is asked what it knows by title, is told it may say it does not
  know, and the answer is marked "can be wrong".
- **X-Ray: recap after a break** (aleph_xr_story.lua, Story.offer;
  aleph_xr.lua; aleph_settings_page.lua): opening a book last read more
  than "Offer a recap after a break" ago (Never, 1 week, 2 weeks, 1 month;
  2 weeks unless changed), or one that was On hold, asks once "Welcome
  back" three seconds after it opens. Only with X-Ray on and a key set,
  and past the book's first pages. Yes opens the Story tab and updates it.
- Nothing is added to page turns; with X-Ray off none of it is loaded.

## 2026-11-14 — 1.1.55 (testing)

- **X-Ray: Describe with AI gave up after 20 seconds** (aleph_xr_ai.lua):
  with Gemini it ended in "no descriptions (no answer (wantread))". A model
  sends nothing until its whole answer is written, and the wait for the
  first byte was 20 seconds. It is now as long as the wait for the answer
  (3.5 minutes; the question is stopped at 4). A wait that runs out says
  "the provider took too long to answer". Gemini is asked for its answer as
  JSON (responseMimeType), so nothing comes around the list.

## 2026-11-14 — 1.1.54 (testing)

- **Night profile page fits** (aleph_settings_page.lua): with the profile
  and By the clock both on, the page was taller than the screen and its
  foot (Bolder text at night) was cut off. The page now tightens up like the
  others when it does not fit (the notes under the rows go, rows are lower).
- **Settings pages in pages** (aleph_settings_page.lua, Settings.split,
  Settings.turn): any Settings page still too tall once tightened (a large
  interface size, a long page) is shown in pages, never cut: groups are
  kept whole, a page does not start with a gap, and the arrows at the foot,
  a swipe left or right, or the page keys turn them. Each page of Settings
  opens at its first.

## 2026-11-14 — 1.1.53 (testing)

- **Night mode by the clock** (aleph_night.lua, aleph_settings_page.lua,
  main.lua): Settings > Home > Night profile > By the clock. "Turn night
  mode on by itself" with From and To times (steps of 15 minutes, 21:00 to
  07:00 by default; a period over midnight is the usual one). As each
  period starts, night mode is set to match (SetNightMode, the event
  KOReader's own controls use), so the night profile follows if it is on;
  night mode switched by hand in between stays as it is until the next
  period starts. Looked at on the minute a period starts, when the device
  wakes (a period that started while it slept is set then) and when
  KOReader starts. Works with the night profile on or off. The Home
  settings row shows the times.

## 2026-11-14 — 1.1.52 (testing)

- **Night profile** (aleph_night.lua, aleph_settings_page.lua, main.lua):
  Settings > Home > Night profile. When KOReader's night mode turns on, the
  front light goes to a night brightness and warmth, and the text of books
  KOReader lays out itself is drawn a little bolder; when it turns off, the
  light goes back to what it was and the text to its own weight. After the
  "Night Profile" user patch (2-night-profile.lua), made into settings:
  the profile on or off (off by default); Change the light; Night
  brightness (5–100 %, steps of 5) and Night warmth (0–100, on devices with
  warm light), shown on the screen at once when night mode is on; Use the
  light as it is now; Remember changes made at night (light changed while
  night mode is on becomes the night light next time); Bolder text at night
  (Off, +0.5, +1, +1.5). A light that is off stays off. Every way of
  switching night mode goes through Screen:toggleNightMode, which is
  watched; the weight chosen in the reader is kept and the boost added on
  top only at night (CreDocument:setFontBaseWeight). While the patch is
  installed in koreader/patches, the profile stays off and the page says
  so, so the two never act at once.

## 2026-11-14 — 1.1.51 (testing)

- **Up next in series waits for the book before** (aleph_local.lua,
  Local.upNext): the shelf showed the book after the one being read (book 2
  while book 1 was Reading). It now shows, for each series with a book
  already finished, the first book in series order that is not finished,
  and only when that book is unread and every earlier book of the series on
  the device is finished. A series whose next book is Reading or On hold
  shows nothing until that book is finished; a series with nothing finished
  shows nothing. Books finished and deleted since (the record of finished
  books) count as finished; earlier books never on the device do not hold a
  series back; books without a series number are left out. Series read
  most recently come first.

## 2026-11-14 — 1.1.50 (testing)

- **Library sorted by author's last name** (aleph_local.lua,
  aleph_browser.lua, aleph_library_view.lua): in the library's Sort and
  filter, choosing Author shows a First name / Last name row under it. Last
  name (sort "author_last") orders books by their first author's surname,
  the way Authors' "Last name" does (Local.surnameOf: "Ursula K. Le Guin"
  under L, "Martin Luther King Jr." under K, "Austen, Jane" under A), then
  the whole name, then the title; A–Z and Z–A as before. The letters down
  the side go by surname, the toolbar says "Last name A–Z", and the choice
  is saved with the library's other sorting. The filter rows are a little
  lower while that row shows, so the sheet still fits with the extra
  filters on.

## 2026-11-14 — 1.1.49 (testing)

- **X-Ray, Aleph's own** (aleph_xr.lua, aleph_xr_names.lua,
  aleph_xr_page.lua, aleph_xr_ai.lua, main.lua, aleph_reader_sheet.lua,
  aleph_highlight.lua, aleph_settings_page.lua): the people, places and
  other names of the book being read, and where each was mentioned up to
  the page one is on. Off unless turned on (Settings > X-Ray); off, none
  of its code is loaded. For books KOReader lays out itself (EPUB and the
  like), not PDFs or comics.
  - *Made not to slow reading.* Nothing runs when a page is turned. A book
    is read for its names once, when asked ("Find names in this book"), by
    a background process, as covers are; what it finds is three small files
    in the book's settings folder (aleph_xray.lua, aleph_xray_hits.lua,
    aleph_xray_text.lua), loaded only when X-Ray is opened.
  - *Names from the text alone* (aleph_xr_names.lua): a name is a word
    written with a capital where a sentence does not ask for one, again and
    again, and hardly ever without it. Words that stand together with
    capitals are one name ("Elizabeth Bennet"), a title before a name marks
    a person (Mr, Doña...). Latin with accents, Greek and Cyrillic; no
    network, no dictionary. Up to 120 names a book.
  - *Where they are mentioned*: found with KOReader's own search
    (findAllText), the way the xray.koplugin by Jimmy Pautz (MIT) does; no
    code of it is used. Mentions are kept in the book's order, so "up to
    this page" is a few comparisons, not a pass through the book.
  - *The sheet* (aleph_xr_page.lua): the names met so far, the most
    mentioned first; a name's card with its other spellings and its
    mentions (page, chapter, the words around); a mention goes to its place
    and KOReader's "back" returns. "Not a name" hides a wrong one. Opens
    from the reader menu (This book > X-Ray), from the X-Ray button of the
    text menu on the word selected, from the gesture "Aleph: X-Ray", and
    from a tap on an underlined name. With the xray.koplugin also
    installed, its row is named "X-Ray plugin".
  - *Underlined names*, an option (Settings > X-Ray, or the sheet): a thin
    line under each name on the page; a tap on one opens it. A turned page
    then looks up its own names only (found by halving the list, a position
    asked for each), once per page. Off by default.
  - *Show the whole book*, an option: names and mentions from pages not
    read yet too.
  - *Descriptions with AI*, optional (aleph_xr_ai.lua): "Describe with AI"
    in a book's X-Ray asks a language model, once, what each name met so
    far is. It uses one's own key with Claude, OpenAI, Gemini, or any
    service speaking OpenAI's chat format at an address of one's own
    (Settings > X-Ray). Sent: the book's title and author, how far one is,
    and for up to 60 names two short excerpts from the pages already read;
    never the whole book or pages not read. Asked by a background process;
    the answer adds a kind (person, place, group, thing) and a sentence or
    two to each name, and the sheet's People / Places / Other filters. The
    key is kept in KOReader's settings file, as typed.

## 2026-11-14 — 1.1.48 (testing)

- **Page turner battery** (aleph_page_turner.lua, aleph_bookends.lua,
  aleph_bookends_page.lua, main.lua): with BT Manager / HID Passthrough
  running a Bluetooth page turner, the bottom line's right-hand slot ends
  with " · <bluetooth> 80%". It is added after what the slot already shows
  (time left, by default), and neither the dot nor the level appears while no
  device reports a battery. The level is HID Passthrough's own reading or
  Aleph's look at its daemon (GET /status, the lowest battery_level of the
  devices connected): every 5 minutes while a book is open, and, while no
  level is known, at most every 20 seconds as pages turn, so a page turner
  that was asleep when the book opened shows its level with its first page
  turn instead of 5 minutes later (HID Passthrough asks only 2 seconds after
  a book opens, then every 5 minutes). A page turner that goes away
  disappears at the next look. With the daemon down, only the 5-minute look
  runs. Book margins > Page turner battery turns it off.

## 2026-11-14 — 1.1.47 (testing)

- **Changing books and quitting no longer wait for the library index**
  (aleph_local.lua, main.lua, aleph_delete.lua, aleph_goodreads_import.lua):
  since 1.1.45 the index (aleph_index.lua: every book, with its description
  and highlights) was written when KOReader saved its settings, which it
  does as every book closes and as it quits. On a Kindle with several
  hundred books that took about 12 seconds each time (crash.log: "close
  widget: ReaderUI", then nothing for 11–12 s). Now:
  - it is not written as a book closes; the library kept in memory is what
    Home shows meanwhile;
  - it is written as the device goes to sleep, and as KOReader quits or
    restarts (after the open book closes, so its new state is in);
  - it is written by a background process (KOReader's runInSubProcess, as
    for covers), so nothing waits for it; where none can be started it is
    written in place;
  - it is written by Aleph's own writer (Local.indexText), compact and in
    one go, to a new file put in place of the old one when complete,
    instead of KOReader's LuaSettings:flush, which sorts every table's keys,
    checks each table against the ones around it, indents every line and
    copies the old file aside first (about 2.5 times slower on a test
    library of 900 books). Two writes never run at once: one asked for
    while another runs follows it.
  An index that missed a write (a crash, the battery running out) is put
  right by the scan at the start of the next session, as before.

## 2026-11-14 — 1.1.46 (testing)

Tidying after the review of 1.1.44, and the direction keys. Nothing looks
different on a touch screen.

- **One name** (across the plugin, aleph_migrate.lua): what was still named after
  the projects Aleph grew out of is Aleph's now. In the code: `_rb_*` and
  `_qtb_*` fields are `_aleph_*` and `_aleph_topbar_*`; `QuickTopBar` is
  `TopBar` and its `quicktopbar_*` marks `aleph_topbar_*`;
  `BookOrbitStatsReader` is `StatsReader`; `CatalogBoard` is `BoardHost`;
  aleph_catalog_util.lua is aleph_board_util.lua; the event
  `RBSetPageBackground` is `AlephSetPageBackground`. Credits to BookOrbit,
  ZenOS and the others stay as they were. What is saved is moved once, and
  never over a newer value (Migrate.names, Migrate.pageBackground):
  `catalog_board` → `board_layout` (Home's layout), `catalog_board_dust` →
  `board_dust`, `catalog_dashboard_tap_resumes` → `board_tap_resumes`; the
  top menu's settings are copied from `quicktopbar` to `aleph_topbar` (the
  Quick Top Bar plugin keeps its own); the page background option
  `rb_page_background` → `aleph_page_background`, in KOReader's default, in
  each book as it opens, and in gestures bound to it. Custom top menu icons
  are looked for in koreader/aleph-topbar-icons, and in
  koreader/quicktopbar-icons when only that folder is there.
- **Helpers written once** (aleph_prefs.lua, aleph_override.lua,
  aleph_board_ui.lua): Aleph's settings are read, checked and set through
  aleph_prefs.lua (Prefs.get, table, on, is, set) where files each did it
  their own way; KOReader's fonts and tab icon size are answered
  with Aleph's through aleph_override.lua (Override.fonts, tabIcons) in the
  five files that each patched and restored them; the battery is drawn by
  BoardUI.battery in Home's header and in a book's top and bottom lines.
  aleph_catalog_widgets.lua (a wrapper that did nothing here) is gone.
- **Long chains split** (aleph_browser.lua, aleph_settings_page.lua,
  aleph_board_data.lua): Home's actions (boardRun) and Settings' (onAction)
  were one long if-chain each (about 35 and 40 branches); each kind now has a function of its
  own in a table (BOARD_ACTIONS, ACTIONS). BoardData.build is four named
  parts (boardBooks, readingWeek, setFingerprint, lazyFields) and what
  joins them.
- **Translation** (aleph_browser.lua, aleph_local.lua, main.lua,
  aleph_migrate.lua, aleph_bookends_page.lua): about 200 pieces of text on
  Home, the library and a book's page were plain English strings; they go
  through KOReader's translation call like the rest, and sentences put
  together from pieces ("3 results for …") are whole sentences with places
  for the values. aleph_browser.lua and aleph_local.lua used `_` for values
  they threw away; those are `_i` now, so `_` is the translation call there
  as everywhere else. (KOReader only has translations for its own text, so
  most of Aleph's still shows in English.)
- **Direction keys** (aleph_keynav.lua, aleph_browser.lua, aleph_panel.lua,
  aleph_menu_page.lua, aleph_settings_page.lua): on a device with Up, Down,
  Left, Right and Press, a mark moves between everything that can be tapped
  on Home, in the library, on a book's page and in Aleph's panels, and
  Press taps it (the menu pages already had this). Past the left or right
  edge Home turns its page. On by itself where the device has the keys;
  Settings > About > Button navigation turns it on elsewhere, to try it with
  a keyboard or a controller. Menu pages choose the next control the same
  way now: one straight ahead before one off to the side.

## 2026-11-14 — 1.1.45 (testing)

Speed and battery work after a review of 1.1.44. Nothing looks different,
except one new switch in Settings > About.

- **The library is read once per session** (aleph_local.lua,
  aleph_reader_sheet.lua): Home is opened again each time a book closes, and
  each time it read aleph_index.lua (every book's description and
  highlights) from storage. Local.new now gives the same library for the
  whole session. It stays in memory while a book is read.
- **The book that closes is read again by itself** (main.lua,
  aleph_local.lua, aleph_browser.lua): as a book closes, its entry is made
  again from the reader's own settings (Local.refreshClosing), so Home is
  right the first time it is drawn: it was drawn with the old progress, the
  whole library scanned, then drawn again. The scan of the whole library on
  opening Home now runs only when it is due (Local.scanDue): the first time
  in a session, ten minutes after the last one, or when a library folder
  itself changed. Settings > Library > Refresh, a change of folders and the
  sync button still scan at once.
- **The index file is written less** (aleph_local.lua, aleph_delete.lua,
  main.lua): a change of state (a book read further, a status, a rating)
  marks the index instead of writing every book again; it is written when
  KOReader saves its settings (as the device goes to sleep). Books added or
  removed are still written at once. An index that missed a write (a crash)
  is put right by the next scan.
- **Covers stay decoded when Home closes** (aleph_board_ui.lua,
  aleph_browser.lua): the 16 drawn last (6 MB at most) are kept for the next
  time Home opens, instead of all being decoded again.
- **The page's top and bottom lines keep their widgets**
  (aleph_bookends.lua): each slot's widget is kept until what it shows
  changes, instead of being made on every paint (every page turn, every
  step of a text selection). Only widgets are kept, not a picture, so they
  are still drawn over whatever the page has under them.
- **Covers and author portraits are made in a background process**
  (aleph_cover_job.lua, aleph_local.lua, aleph_browser.lua,
  aleph_portraits.lua): a book was opened for its cover, and the network
  asked for a portrait, in KOReader's own process, and the screen waited.
  Both now run in a process of their own (KOReader's runInSubProcess, as its
  Cover browser and Wikipedia lookups use); where one cannot be started,
  they are done as before.
- **Less work per redraw of Home** (aleph_browser.lua, aleph_board_data.lua):
  the lookup of every book by its id and Home's lists of board books are
  kept until a cover arrives or the library's entries change
  (Browser:boardEpoch, Local.revision); they were made on every tap.
- **Minute ticks stop when not needed** (aleph_bookends.lua, aleph_browser.lua,
  main.lua): the reader's tick runs only while the lines show something
  that changes with time; it and Home's stop while the device sleeps and
  start again on waking.
- **Troubleshooting log, behind a switch** (aleph_debug.lua, main.lua,
  aleph_settings_page.lua): the two lines written to crash.log for each
  step of opening a book are written only while Settings > About >
  Troubleshooting log is on (aleph.debug_log; off by default). Failures are
  always written.

Fixes:

- A cover that could not be made once was never tried again (the "no cover"
  mark was saved in the index): it is now tried again each session.
- A cover whose file is gone (KOReader's cache folder cleared) stayed gray:
  it is made again.
- Opening a book wrote an empty list of pins into its settings: the list is
  now written with the first pin.
- The version number is written in one place (_meta.lua); aleph_prefs.lua
  reads it from there.
- The dates in README.md, the legal notice and this file's title; _meta.lua
  no longer says "Local only" (author portraits and the Goodreads cookie
  screen, both optional, use the network).

## 2026-11-14 — 1.1.44 (testing)

- **Safety nets that speak** (aleph_try.lua, 37 files): the 163 protected
  calls whose failure was thrown away (`pcall(...)` as a statement) now use
  `try(...)`, which works the same but writes the failure to crash.log as
  "Aleph: <file>:<line> failed: <error>". Each place and message is written
  once per session and at most 200 lines in all, so a failure on every page
  turn or every minute cannot flood the log. Left silent: closing files,
  databases and sockets, freeing pictures and fonts, and the optional
  "random" module, whose failures mean nothing.
- **Needless ones removed**: reading Aleph's own settings and bookmark
  colours (aleph_bookmarks.lua, aleph_reader_sheet.lua,
  aleph_goodreads_import.lua, aleph_remote_progress.lua) is no longer
  wrapped: those cannot fail, and a mistake there should show.

## 2026-11-14 — 1.1.43 (testing)

Tidying, no change in behaviour:

- **One name in crash.log**: every log line Aleph writes now starts with
  "Aleph:" (the statistics reader, chapter map, board data, board art and
  widget messages said "BookOrbit:", the top bar's "QuickTopBar:", now
  "Aleph: Quick Top Bar:"; the layout debug lines "Aleph: BOARDFIT").
- **One code style**: aleph_browser.lua and main.lua, written in a compact
  style (a=b, f(a,b), {w=w}), are spaced like the other files (a = b,
  f(a, b), { w = w }). Only spaces inside lines changed: the compiled code
  is identical (checked by comparing the bytecode of the old and new files).
  The install function of aleph_board_host.lua is indented by four spaces.

## 2026-11-14 — 1.1.42 (testing)

Speed work, nothing that looks different:

- **Clock widgets redrawn on their own** (aleph_browser.lua,
  aleph_board_host.lua, aleph_board_data.lua, aleph_board_widgets.lua): with
  a Clock, Analog clock or Literary clock on Home, each minute rebuilt the
  whole page and refreshed the whole screen. Now each clock widget sits in a
  slot (TileSlot) that remembers where it was painted; the minute tick moves
  the board's time (BoardData.tickTime), builds a new tile for each clock
  widget only, and refreshes only their rectangles and the header's clock.
  The whole page is still built on the hour (greeting, date, reading buddy)
  and whenever the in-place redraw cannot be done.
- **Home's lists kept between refreshes** (aleph_local.lua): Local:dashboard
  sorted the library about six times and searched it again for every series
  being read on each refresh (back to Home, closing a book, a goal change).
  Those lists (dashboardLists) are now kept with the author and series lists
  until the books change: a scan or a saved status drops them, and a number
  made from each book's status, progress, last opened, added and finished
  day (stateSignature) catches changes made in place. Discover is still
  shuffled on every refresh; the reading streak, the record of finished
  books and the collections are still read each time. The next book in each
  series is now found from one pass over the library.
- **"60% on Colorsoft" without rereading Syncery's titles**
  (aleph_remote_progress.lua): the index of Syncery's title.txt files was
  rebuilt every minute while the library was open; it is now rebuilt only
  when Syncery's folder or one of its shard folders changed, and every ten
  minutes in any case.
- **Sorting** (aleph_local.lua): lists sorted by name (books after a scan,
  authors and series, collections, genres, similar books) work out each
  lower-cased name once instead of on every comparison (Local.sortByKey).
  A partial rescan that replaced books in place now also drops the author
  and series lists made from the old entries.
- **Widget opacity** (aleph_wallpaper.lua): one scratch picture is kept and
  reused for every widget drawn over the wallpaper, instead of one made and
  freed per widget per redraw; it is freed with the wallpaper.

## 2026-11-14 — 1.1.41 (testing)

- **Literary clock widget** (aleph_literary_clock.lua, aleph_literary_clock/,
  aleph_board_widgets.lua, aleph_board_edit.lua, aleph_browser.lua): a Decor
  widget (sizes L, W, XL, M) showing the quote for the current minute with
  the time in bold and the title and author under it, filling the tile at
  the largest size that fits (Noto Serif; Aleph's interface size applies).
  Among a minute's quotes it picks one readable in the tile, moving on from
  day to day; not-safe-for-work quotes are left out (props.sfw = false shows
  them); minutes with no quote get a fallback line with the time in words.
  Redrawn each minute with the other clocks. Adapted from readinpixels'
  Literary Clock (MIT); the quotes (1.1 MB, one file per hour, only the
  current hour in memory) are CC BY-NC-SA 2.5: credits in NOTICE,
  THIRD_PARTY_NOTICES.md and aleph_literary_clock/NOTICE.md.

## 2026-11-13 — 1.1.40 (testing)

- **Reader menu closes with the top menu** (aleph_reader_sheet.lua): when a
  swipe or tap opens KOReader's top menu, KOReader also opens the bottom
  menu (its "Auto-show bottom menu" setting), which Aleph's reader menu
  stands in for. KOReader closes the bottom menu as soon as an item of the
  top menu runs (a plugin's window, such as Capitulares) or the top menu is
  closed by a tap outside it, but Aleph's reader menu stayed open and hid
  the page under that window. It now closes then too.

## 2026-11-13 — 1.1.39 (testing)

- **Goodreads import: choosing finished dates** (aleph_goodreads_import.lua):
  books Finished both here and on Goodreads but on different days are
  listed on the import's summary ("N were finished on another day here than
  on Goodreads: … keep this device's day, … take Goodreads'"), with a
  "Choose finished dates" button. Its page shows each book with both days
  (Here: 3 Mar 2024 / Goodreads: 10 Mar 2024) to pick one, All from this
  device / All from Goodreads, pages for long lists, and Done back to the
  summary. This device's day is kept unless Goodreads' is chosen. A book
  Finished here with no day now gets Goodreads' Date Read.

## 2026-11-13 — 1.1.38 (testing)

- **Goodreads sign-in moved** (aleph_settings_page.lua): receiving the
  Goodreads cookie is no longer a row of its own on Settings; it is
  "Goodreads sign-in" in Settings → Library → Goodreads, under Import from
  Goodreads (still shown only with advokatb's Goodreads plugin installed).

## 2026-11-13 — 1.1.37 (testing)

- **Bookmarks filtered by colour** (aleph_bookmarks.lua): on the bookmarks
  page's Bookmarks tab the colour dots are the bookmarks' own colours (Red,
  Orange, Yellow, Green, Aqua, Blue, Purple, Pink) and the highlight styles
  are hidden; a dot shows the bookmarks of that colour (tap it again for
  all). On All, a highlight colour now also shows the bookmarks of the same
  colour (Aqua counts as Cyan; Pink has no highlight colour). A colour chosen
  carries across when switching between the tabs where both sets have it.
  Bookmarks made before the colours count as Blue.

## 2026-11-13 — 1.1.36 (testing)

- **Bookmark colours from the page** (aleph_bookmark_colors.lua): adding a
  bookmark by tapping the page's top-right corner (or any gesture bound to
  "Toggle bookmark") now shows the list of colours. The list was opened but
  never put on the e-ink screen: it was shown without a refresh of its own,
  and only the reader menu closing (which refreshes that part of the screen)
  made it appear. It now refreshes its own rectangle. The wallpaper sheet
  (aleph_wallpaper.lua) is shown the same way.

## 2026-11-13 — 1.1.35 (testing)

- **Larger interface sizes** (aleph_board_metrics.lua, aleph_settings_page.lua,
  aleph_topbar_style.lua): Settings → Home → Interface size now goes from 1x
  to 1.5x (1, 1.05, 1.1, 1.15, 1.2, 1.25, 1.3, 1.4, 1.5) for readers who find
  the text too small. With nine sizes the row is a − / + stepper instead of
  segments; − stops at 1x and + at 1.5x. Layout choices (columns, margins)
  stay those of the device at 1x, so a larger size draws the same layout
  bigger. A size saved by another version is taken to the nearest one
  offered (1.25, which older versions turned into 1.2, is now kept). The
  top bar style follows the same sizes without Aleph's metrics loaded.

## 2026-11-13 — 1.1.34 (testing)

- **Wallpaper on Home** (aleph_wallpaper.lua): Customize Home has "+ Add
  wallpaper" beside "+ Add widget". Its sheet picks a picture on the device
  (JPG, PNG, WebP, GIF, BMP, SVG; copied to settings/aleph_wallpaper.*),
  and sets Fit (Fill: the screen, edges trimmed; Whole: all of it, white
  around), Wallpaper opacity (10–100%: faded toward white) and Widget
  opacity (40–100%: each widget mixed with the wallpaper under it), Change
  picture and Remove. The picture is drawn behind every page of Home,
  scaled once per screen size and freed when Aleph closes; widgets keep
  their tap areas (painted in place, then mixed by Blitbuffer.addblitFrom).
  Settings: aleph.wallpaper = { file, fit, opacity, widgets }.

## 2026-11-13 — 1.1.33 (testing)

- **Authors by last name:** the Authors list's Sort and filter offers First
  name, Last name and Most books (A–Z / Z–A for the first two), saved for
  the list. The surname is the part before a comma ("Collins, Suzanne"),
  else the last word, with Jr., Sr., II… set aside and particles kept
  ("Le Guin", "van Gogh") (Local.surnameOf). The letter rail and Jump follow
  the surname's first letter; the names are shown as they are.

## 2026-11-13 — 1.1.32 (testing)

- **Read widget** (Customize Home > Add widget > Library > Read, small):
  like Library, but with the share of the library finished ("37%", "<1%"
  for a start, 100% only when every book is) over "of your books", and the
  covers of finished books. A tap opens the library with every finished
  book (Browser:loadReadBooks: all of them, the library's saved filters
  left aside, so the list holds what the percentage counts).
  The dashboard counts finished books (browseCounts.read) and keeps them as
  a "read" shelf.

## 2026-11-13 — 1.1.31 (testing)

- Bookmark colours, tidied: the reader menu's Bookmark colour row is gone.
  Adding a bookmark with the menu's switch closes the menu first, so the
  list of colours stands alone under the ribbon. A bookmark added on the
  page itself (corner tap, gesture, or any call for the page shown, also
  when the page is passed explicitly) always brings up the list (unless
  turned off in Settings > Reader).

## 2026-11-13 — 1.1.30 (testing)

- **Coloured bookmarks**, as in the Kindle app (aleph_bookmark_colors.lua):
  Red, Orange, Yellow, Green, Aqua, Blue, Purple, Pink.
  - KOReader's dog-ear in the top-right corner is drawn as a ribbon in the
    page bookmark's colour (grey shades on black-and-white screens).
  - A new bookmark of the page shown (corner tap, gesture, the reader
    menu's switch) takes the colour used last, and the list of colours
    drops from the ribbon, with the current one ticked and Remove bookmark
    at its foot. Settings > Reader > Choose a colour when bookmarking turns
    the list off.
  - The bookmarks page draws each page bookmark's icon in its colour.
  - Kept on KOReader's bookmark itself (annotation field aleph_color);
    older bookmarks show the default colour (Blue).

## 2026-11-13 — 1.1.29 (testing)

- **The reader menu's "Bookmark this page" switch shows the bookmark.** It
  asked KOReader for isCurrentPageBookmarked, which does not exist, so it
  always read "off": each tap did add or remove the bookmark, but the switch
  never moved, and the menu looked stuck (the crash log shows seven taps,
  each toggling the bookmark). Now asked with ReaderBookmark:isPageBookmarked
  (what the dog-ear uses); the chip ("page bookmarked") follows too.

## 2026-11-13 — 1.1.28 (testing)

- **Aleph Home (and All books) from the reader menu leave the book.** They
  opened Aleph over the book, which stayed open underneath, so the top menu
  was still the reader's (Typeset, Navigation…). Now the book closes the
  way KOReader's own Home does, the file browser comes back and Aleph opens
  over it, whatever "When KOReader starts" is set to (aleph_opening.lua,
  Opening.goHome; main.lua's openOver takes the request). The book reopens
  at the same page from Resume or Continue reading.

## 2026-11-13 — 1.1.27 (testing)

- Reader menu, the row of plugin buttons:
  - **Sync now** is shown with Syncery and/or KOSyncthing+ installed and
    does what Home's Sync button does: the whole chain with Syncery
    (aleph_sync_chain.lua), Syncthing started with KOSyncthing+ alone,
    Syncery's own Sync now with Syncery alone.
  - **Goodreads** replaces Syncery's Progress button: shown only with the
    Goodreads plugin by advokatb installed, it sends the reading progress to
    Goodreads through the plugin's own Update progress (Wi-Fi turned on as
    it does); a book not linked yet goes through its Link book first.

## 2026-11-13 — 1.1.26 (testing)

- **Discover offers books to start** (Local.discoverable): only unread books
  (not finished, being read or on hold), and in a series only the next one
  to read: every earlier book of the series on the device must be finished
  (series names compared without case or spaces around them). Earlier books
  not on the device do not hold a series back; books without a series
  number are offered as they are. The same list feeds the "Pick a book to
  start" card. Before, Discover was a shuffle of the whole library.

## 2026-11-12 — 1.1.25 (testing)

- **The cover in the reader menu opens the book's page** (Aleph's book
  information: details, stars, status, highlights, ⋯ menu), over the book;
  Back returns to the page being read (Board:showBookPage). A book not yet
  in the library index says so.

## 2026-11-11 — 1.1.24 (testing)

- **The yearly goal answers at once.** The crash log showed each tap on − or
  + rebuilding the whole Home behind the Settings page (dashboard and every
  widget, about a second on a Kindle), one after another for a burst of
  taps. Now the page shows the new number at once and Home is rebuilt once,
  1.5 seconds after the last tap.
- **Type the goal:** tapping the number opens a number prompt (1 to 100,000).
  MenuUI.stepper takes an optional action for its number; the Aleph prompt
  and Browser:input take an input type.

## 2026-11-11 — 1.1.23 (testing)

- **Sync with Syncery's cloud** (Dropbox, WebDAV or FTP): the one-tap chain
  follows Syncery's transports. Cloud only: Wi-Fi with internet, Syncery's
  Sync now, then a wait until its cloud sync has finished
  (`_sync_all_in_progress`), then the jump check or the library rescan;
  Syncthing is not started. Cloud and Syncthing: a nearby device is looked
  for 20 seconds only, then the cloud carries it. The chain is offered with
  Syncery's cloud on even without KOSyncthing+.

## 2026-11-11 — 1.1.22 (testing)

- **Sync e-readers in one tap** (aleph_sync_chain.lua), with KOSyncthing+
  and Syncery both installed: the Quick settings Sync button and the reader
  menu's Sync now run one chain, shown step by step in a panel with Stop:
  Wi-Fi; Syncthing started and waited for; Syncery's Sync now (saves the
  open book's position); Syncthing scans its folders and waits for another
  device of them (up to 3 minutes: tap Sync on the other e-reader); waits
  until the files are exchanged both ways (Syncthing's db/status and
  db/completion, up to 3 minutes); in a book, Syncery's checkRemote (its
  jump offer), on the home screen a library rescan; Syncthing stopped again
  if the chain started it. Found from two crash logs: the e-readers' Syncthing
  never ran at the same time, Syncery's pushes ran out of retries, and its
  Quick Sync ran 20 seconds with no peer.
- **The other e-reader's progress** (aleph_remote_progress.lua): the library
  (row and grid) and the book's page show "60% on Colorsoft" when another
  device is further on, read from Syncery's syncery-progress.json (hash or
  sdr storage). Found by KOReader's partial MD5; when the two e-readers hold
  different copies of the file, by the title Syncery writes beside it, and
  the page adds "another copy of the file". A book not started here says
  "Not started here".

## 2026-11-11 — 1.1.21 (testing)

- **Send to Goodreads** from a book's page (⋯ menu, aleph_goodreads_send.lua),
  only with the Goodreads plugin by advokatb installed. Sends the book's
  status (Finished → Read with the day it was finished as the date read,
  Reading → Currently reading, Unread → Want to read, On hold → Did not
  finish when the account has that shelf) and, for a read book, its stars
  (a half star rounded up). The book need not be open: it is found by the
  link the plugin keeps in its sidecar, else the Goodreads id or ISBN in
  the EPUB, else a search by title and author with the results to choose
  from in the page's sheet (and a search with other words). The link is
  saved where the plugin keeps it. A confirmation shows the Goodreads book
  and what will be sent, with "Not this book? Choose another…". All calls go
  through the plugin's own modules and session; asks to receive the cookie
  first when it has none.
- aleph_confirm takes a third, full-width choice (`extra_label`, `on_extra`).

## 2026-11-11 — 1.1.20 (testing)

- **Import from Goodreads** (Settings → Library → Goodreads,
  aleph_goodreads_import.lua), for everyone, with or without a Goodreads
  plugin. Reads Goodreads' library export (goodreads_library_export.csv,
  or the same file saved from Excel as .xlsx or as CSV with semicolons),
  found in the home folder, the library's folders, the Kindle's documents
  or a Downloads folder, or chosen by hand. Shows what it would change, and
  on Import:
  - Books on the device, found by ISBN (when their OPF was read) or by
    title and author's surname (accents, subtitles, series notes and
    leading articles ignored): only what is empty is filled in. A book still
    unread here takes Goodreads' shelf (Read → Finished with Date Read as
    the finished day, Currently reading → Reading, a "did not finish"-like
    shelf → On hold); a book with no rating here takes Goodreads' stars.
  - Books read on Goodreads and not on the device go on the record of
    finished books (aleph_finished_log.lua, keys "goodreads:<id>") with
    their Date Read, so they count in that year's goal. Read books without
    a date are left out; a book already on the record (read and deleted)
    is not added twice, and one imported that later arrives on the device
    counts once, as the device's book. Importing again updates, never
    duplicates.
- The library's OPF reading also keeps the ISBN (aleph_pages.lua), for
  matching.
- aleph_confirm takes `lines` for longer texts.

## 2026-11-11 — 1.1.19 (testing)

- **Extra highlight styles** (added by a user patch or a modified KOReader file, e.g. Crosshatch, Wavy underline, Outline thick): the Highlight sheet, the bookmarks page filter and KOReader's own bookmarks list filter no longer squeeze every style into one row. Each shows as many style tiles as fit; when there are more, the row scrolls (swipe it sideways) and its last tile, More…, opens every style in a grid (`aleph_highlight.lua`: `styleWindow`, `moreTile`, `openStylePicker`; `aleph_bookmarks.lua`: `lookRows`; `aleph_menu_skin.lua`). Samples for styles Aleph does not know are guessed from their name (underline, double, dashed or wavy line, strike, outline, or a tinted fill).
  (Made in a separate chat on top of 1.1.16 and released there as 1.1.17;
  joined here with the Goodreads cookie work of 1.1.17 and 1.1.18.)

## 2026-11-11 — 1.1.18 (testing)

- **Receive Goodreads cookie works when the browser keeps extensions off the
  local network.** A normal tab could reach the e-reader but the extension
  could not (Chrome's Local Network Access, Firefox's mixed-content rules).
  The screen now also serves a small page of its own (/aleph); extension
  1.0.2 opens it in a background tab, sends the cookie from inside it as
  that page (an ordinary same-origin request), and closes the tab. It tries
  the direct way first. Needs the new "scripting" permission.
- Extension 1.0.3: when the direct request is left hanging (not only when
  it is refused), it also goes the background-tab way, after 4 seconds.

## 2026-11-11 — 1.1.17 (testing)

- **Receive Goodreads cookie, easier to troubleshoot:** the screen says when
  a computer reaches it ("A computer reached this e-reader at …"), and
  crash.log records the address it listens on, the Kindle firewall commands'
  results and every request that arrives, with where it came from.
- Extension 1.0.1: it first checks that the e-reader answers, then sends.
  When it can't, it says whether the e-reader never answered (network: VPN,
  guest network, router isolation, e-reader asleep) or the connection was
  refused at once (browser or computer firewall), with the error, and how
  to test the address in a normal tab.

## 2026-11-11 — 1.1.16 (testing)

- **Receive Goodreads cookie** (aleph_goodreads.lua): Settings → Goodreads,
  shown only when the Goodreads plugin by advokatb (goodreads.koplugin
  0.5.0) is installed, recognised by its settings object keeping the cookie
  under "session_cookie".
  - The screen listens on the local network (port 8769, or the next free one
    of five) with the device's address and a random four-digit code, turning
    Wi-Fi on first if needed. On a Kindle the firewall is opened for the
    port and closed after, the way KOReader's HTTP inspector does it.
  - The companion browser extension (aleph-goodreads-cookie.zip, Chrome,
    Edge and Firefox, Manifest V3) reads the browser's cookies for
    www.goodreads.com, HttpOnly ones included, drops jwt_token, and sends
    them with the code (POST /goodreads-cookie).
  - Aleph saves them through the plugin's own setCookie, in every open
    instance, clears its cached user id, resets its CSRF token and lets it
    flush its queue, as its Session cookies menu does.
  - Stops on success, after five wrong codes, after ten minutes, or when the
    screen closes. The cookies cross the network unencrypted; the screen and
    the extension say so.

## 2026-11-11 — 1.1.15 (testing)

- **Half stars** on a book's page: the left half of a star gives a half
  star, the right half the whole star; tapping the current rating clears
  it. KOReader keeps whole stars, so its own rating (summary.rating) holds
  the whole stars below and the half is kept beside it
  (summary.aleph_rating): KOReader's screens show 4 for 4.5, and a rating
  changed in KOReader later wins over Aleph's half.

## 2026-11-11 — 1.1.14 (testing)

- The book page's ⋯ menu has one **Delete book** entry, which opens a sheet
  with the two ways (keep its data, or with its data); each still asks
  before deleting.
- **Filter lists fit their contents:** a list too long for one column is
  split into two of about the same length (15 decades: 8 and 7, not 14 and
  1), so the sheet is only as tall as it needs to be.

## 2026-11-11 — 1.1.13 (testing)

- **Turning the screen redraws the board at once.** The log showed two
  causes. KOReader rebuilds the whole file browser when the screen turns
  (its cover grid decoded and scaled again, about a second) though the
  board covers it; and the board itself never heard of the turn (KOReader
  tells only the file browser and its plugins), so it stayed laid out for
  the old shape until the next tap or the clock's minute.
  - While the board is up, the file browser is only told the new size;
    it is rebuilt when the board closes (main.lua, FileManager.rotate).
  - Aleph's plugin passes the turn on: the board is laid out again with a
    full refresh, full pages of Aleph (Settings and the like) are resized,
    and sheets over the board (they keep a picture of the old screen) close.

## 2026-11-11 — 1.1.12 (testing)

- **Deleting a book from its page** (⋯ menu, aleph_delete.lua), two ways,
  each with a warning first that says what goes, what stays and that it
  cannot be undone:
  - Delete book, keep its data: only the file. The sidecar (highlights,
    notes, bookmarks, last page, status, rating) stays; the same file put
    back in the same folder finds it again.
  - Delete book and its data: the file, its sidecar, custom cover and
    custom metadata, as KOReader's own Delete.
  Either way the reading statistics stay, a finished book stays on the
  record of finished books, KOReader's file browser cache, history and
  collections are told, and the book leaves the library at once; the page
  goes back to where it was opened from. A book open in the reader is not
  deleted (the warning says to close it first).

## 2026-11-11 — 1.1.11 (testing)

- **Finished books stay counted after they are deleted**
  (aleph_finished_log.lua). The books finished this year (the yearly goal,
  Goal pace, Finished this year) were counted from the books on the device,
  and KOReader deletes a book's sidecar with it, so deleting books once
  read made the count go down. Every book seen finished is now kept in
  settings/aleph_finished.lua (title, authors, series, the day it was
  finished, rating, and what finds its saved cover), written on each
  library scan and when a finished book is closed in the reader (for a
  book deleted before the next scan). An entry stays when the file is
  gone; while the book is on the device its own status decides, so
  marking it unread or reading again takes it off. Books are told apart by
  KOReader's MD5, so a moved or renamed book stays one.
- A deleted book on the Finished this year shelf keeps its cover (when
  Aleph had made one); a tap says when it was finished and offers "Remove
  from record". Reading statistics were never affected (KOReader keeps them
  apart from the books).

## 2026-11-10 — 1.1.10 (testing)

- Settings > Library folders is now **Library**: it holds the folders, the
  library refresh, Covers and the extra filters. The folders have a
  Folders heading, and the line in the list adds the cover shape and the
  extra filters when they are set ("Books · covers filled · extra
  filters").

## 2026-11-10 — 1.1.9 (testing)

- **Settings > Reader**, a category of its own for what Aleph adds to a
  book's screens: Reader menu at the bottom, Page browser on swipe up and
  Pinned pages (they were under Opening Aleph > Dialogs). Its line in the
  list says which reader menu is used and whether the swipe is on.
- **Aleph dialogs** moved to Settings > Home, under Look.
- Opening Aleph keeps When KOReader starts and Shortcut. The categories
  are in this order: Profile, Opening Aleph, Home, Widget actions, Reader,
  Book margins, Top menu, Library folders, Author portraits.

## 2026-11-10 — 1.1.8 (testing)

- Settings > Buttons and taps is now **Widget actions**: it sets what the
  widgets do, the Quick settings widget's buttons included ("What each
  widget and Quick settings button opens").

## 2026-11-10 — 1.1.7 (testing)

- **Page-turn buttons turn the board's pages** (the Home pages, the
  library, authors, series and a book's neighbours), on a Kobo Libra
  Colour, a Kindle Oasis or a keyboard. The board listened for keys named
  "PageForward" and "PageBack", which no device has; it now uses KOReader's
  own page-key groups (RPgFwd / LPgFwd, RPgBack / LPgBack).
- **Covers all the same size** (Settings > Library folders > Covers):
  Whole (as before: each cover at its own shape, one close to the box's
  shape still fills it), Fill (every cover fills its box; the edges of
  other shapes are trimmed) or Stretch (every cover is stretched to its
  box, nothing trimmed). Everywhere covers are drawn; changing it clears
  the cover cache.

## 2026-11-10 — 1.1.6 (testing)

- **Settings > Widget actions** (aleph_actions.lua, aleph_actions_page.lua),
  after the idea in Neo QuickSettings (neo_quicksetting.koplugin):
  - Quick settings: the widget's buttons, up to five. For each: its action,
    its icon (a grid of Aleph's icons, with a search) and its name (the
    action's own unless one is typed); move it earlier or later, remove it,
    add a button, reset to Wi-Fi, Light, Night, Rotate and Sync / Refresh.
  - Widget taps: every widget, with what a tap on it opens where no button
    of its own is under the finger: its usual page, nothing, or an action.
  - Actions: Aleph's own (the five above, Library, Series, Authors,
    Collections, History, Search, the Aleph menu) and every plain gesture
    action of KOReader and its installed plugins that works outside a book,
    read from KOReader's Dispatcher as Neo QuickSettings reads it, and run
    with the file browser listening (aleph_plugins.dispatch). An action
    whose plugin was removed shows "Missing" and does nothing.
- The Quick settings widget draws the chosen buttons; Wi-Fi, Night and Sync
  still light up while on. In the 2x2 size it shows the first four.

## 2026-11-10 — 1.1.5 (testing)

- **Crash opening Sort and filter** (crash.log: aleph_local.lua:776
  "invalid order function for sorting", in languages()). The language
  list was sorted with "a and b or c", which is not a valid order when
  counts differ; LuaJIT's sort stopped with an error. Now an explicit
  comparison: most books first, then by name.
- **The extra filters are opt-in:** Settings > Library folders > Extra
  filters > "Language, pages and release date", off by default. Turning it
  on asks first, with a warning: Aleph reads every book's details once,
  which takes time, memory and battery the first time, more so with a big
  library (the warning gives the book count); then a library scan starts.
  While it is off, no book's OPF is opened and Language, Pages and
  Released are not in Sort and filter. Turning it off clears those filters.

## 2026-11-10 — 1.1.4 (testing)

- **Library filters: Language, Pages and Released**, in the sort and
  filter sheet under Format, remembered like the others.
  - Language: the languages in the library by name (en, en-US and eng
    are all English), most books first.
  - Pages: Under 200, 200–399, 400–599, 600 or more. Calibre's page
    count where there is one, KOReader's otherwise.
  - Released: by decade (2020s, 2010s… Before 1900), from the book's
    publication date (dc:date in metadata.opf or the EPUB's OPF, not a
    modification date; Calibre's "no date" is left out), or a comic's
    ComicInfo Year.
  - Each list shows only what the library has, with counts. The rows are
    a little lower so the sheet still fits.
- The library index keeps each book's page count and release year
  (book.opf, read once per file). The first scan after updating reads
  every EPUB's OPF once, so it takes longer that one time.

## 2026-11-10 — 1.1.3 (testing)

- **Page count on the book's page**, between Language and the file
  (aleph_pages.lua). From Calibre first: a custom column whose name says
  pages (Count Pages' "#pages", "#page_count"...), read from metadata.opf
  next to the book, else from the OPF inside an EPUB (Calibre writes its
  columns there when it sends a book), else from Calibre's metadata.calibre
  in a folder above the book. Without one, KOReader's own count, captioned
  "Pages in KOReader" (it changes with font and margins). Looked up when a
  book's page opens and kept until the files change.

## 2026-11-10 — 1.1.2 (testing)

- **Languages by name.** Book details showed the language as the book's
  code ("en-US", as Calibre writes it, or "eng", "fre"). It now shows the
  language's name, "English", in KOReader's language where KOReader has it
  translated (aleph_language.lua, over KOReader's own ISO 639 list). The
  region is left out, so en-US, en-GB and en all read English; anything
  that is not a known code shows as it is.

## 2026-11-10 — 1.1.1 (testing)

- **New highlights came out yellow, now and then, whatever colour was
  picked** (long-press set to select, with the style and colour prompt).
  KOReader's saveHighlight(true) first stretches the selection to whole
  words and sentence ends, by replacing the selection with the stretched
  one, which has no style or colour; whenever the stretch changed something
  (a selection starting or ending inside a word), the highlight took the
  default colour. Aleph now does the stretch first, keeping the chosen
  style, colour and note, then saves it; and checks the saved highlight
  carries the choice. The log records each new highlight's choice and what
  was saved ("Aleph: new highlight").

## 2026-11-10 — 1.1.0

Everything since 1.0.1, tested as 1.0.2 to 1.0.7.

- **Reader menu shortcuts to other plugins.** With BT Manager - HID
  Passthrough installed, the reader menu has a small Bluetooth button with a
  switch that starts or stops its daemon (the plugin's own toggle, with its
  messages; the switch is checked again once it is done). With Syncery
  installed, Sync now and Progress (its progress browser) sit beside it.
  They sit in one row under Style, Contents, Bookmarks and Pages, only for
  the plugins installed; with neither, the menu is as before.
- **Book margins: text colour and weight.** Settings > Book margins > Look
  has two new choices: Text colour (Light gray, Gray as before, Black, and on
  a colour screen a colour of one's own from the colour wheel; one too light
  to read is refused) and Text weight (Regular or Bold). The preview and the
  book's top and bottom lines follow them; icons and the battery take the
  same colour. A custom colour shows as its gray on a black-and-white screen.
- **Top menu slider:** at full or lowest brightness (or warmth) the knob
  touched the + and - buttons. The rail is now a little shorter at both
  ends, so the knob keeps clear of them; touches near the ends still move it.
- **Comic books (CBZ) and their metadata.** KOReader reads no metadata from
  comic archives, so comics showed as their file names. The library now
  reads the ComicInfo.xml most comic tools put inside the archive: title
  (or "Series #Number" when an issue has none), series and number, writers,
  genres, summary and language. Each archive is read once and kept in the
  library's index until the file changes. CBZ, CBR, CB7 and CBT.
- **Series and titles of opened books.** Once a book had been opened, the
  library used only what KOReader stored when opening it, which for a
  comic has no title or series: comics marked Reading or Finished dropped
  out of the Series view and lost their titles. That stored data is now
  completed from the book's other sources (ComicInfo.xml, KOReader's book
  information) instead of replacing them.
- **Metadata set by hand in KOReader** (Book information > Set custom) is
  now used by the library for every book, as KOReader's own book
  information does, and a change to it is picked up on the next scan.
- The reader menu shows the library's title, so an open comic shows its
  ComicInfo title rather than its file name.
- **Book margins: the bottom line sat too high.** It is placed above
  KOReader's own status bar, and KOReader keeps that bar's height even when
  the bar shows nothing (every item and the progress bar turned off). An
  empty bar is now left out, so the line goes back to the foot of the page.
- **Book margins: distance from the edge.** The Top and Bottom tabs have a
  Distance from the top / from the bottom setting with − and + (steps of 2,
  from 6 nearer the edge to 40 further in).
- **Highlight menu, trimmer:** the five buttons are smaller and joined by
  Pin (Unpin when the page is pinned); the start and end arrows and the
  Word / Letter step share one line; the two hint lines are gone (holding
  an arrow still moves by a letter, and the posts can still be dragged).
- **More, from a highlight:** a Back button at the top returns to the
  highlight's menu.
- **Wikipedia's icon** is a serif W (in the text menu and the dictionary)
  instead of the globe.
- **Dictionary: Highlight did nothing visible.** KOReader's Highlight
  button in the dictionary only marks the word, to be highlighted when the
  pop-up closes, and shows it by changing its words to "Unhighlight". In
  Aleph's row of icons those words never show, so a tap seemed to do
  nothing, and the next tap took it back (the log shows three taps on it,
  each one turning it on or off). A tap now highlights the word and closes
  the pop-up, so the highlight is on the page at once.
- **A warning when ZenOS or Simple UI is on.** ZenOS (or Zen UI) replaces the same parts
  of KOReader as Aleph (the home screen built when a book closes, the
  reader's menus, the page browser, the dictionary, the status bars); with
  both on, closing a book builds two home screens and their covers at once,
  and a Kobo Clara Colour was reported freezing and crashing. Simple UI
  also puts its own home screen over the file browser (ZenOS's own check
  turns it off for that reason). At startup Aleph now says so
  (aleph_conflicts.lua), once per start of KOReader, one warning naming
  whichever is on, with "Don't show again" kept for each. Nothing else
  changes: Aleph runs as usual.
- The board's confirmation (aleph_confirm.lua) can run something for its
  cancel button (used for "Don't show again").
- **README: Other plugins.** Not compatible: ZenOS and Simple UI. Works
  alongside: Bookshelf (use one of them as the start-up screen), Project:
  Title and the Cover browser (the list view uses less memory), the
  Bookends plugin. Menu restyling plugins: turn off Aleph dialogs.
- README: the new features in their sections; Bluetooth (HID Passthrough)
  and Syncery among the optional integrations.

## 2026-11-10 — 1.0.1 fixes

- **Silverfish: the whole speech.** When the Silverfish widget's bubble has
  to cut its text short, a tap opens a sheet in Aleph's style with the
  companion drawn larger and everything it says, plus "Open Silverfish" for
  its own screen. When the text fits, a tap opens Silverfish as before.
- **Page colour and night mode:** a book with a page colour chosen in
  Reading settings > Background kept that colour in night mode, where
  KOReader inverts the whole screen; a black custom colour came out as a
  white page that flashed on every turn, for that book only. The page is now
  KOReader's own white in night mode (the colour comes back when night mode
  is switched off), and a colour too dark to read on is never used (the
  colour wheel says so).
- **Top menu check marks** no longer touch their text: KOReader sizes the
  mark's slot to its own check glyph, narrower than Aleph's round mark at
  Aleph's font sizes. The slot now holds the mark and a gap, and the text
  gives up the room. A submenu row's "▸" is also removed as a whole
  character (it was matched byte by byte and could be cut in half).

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
