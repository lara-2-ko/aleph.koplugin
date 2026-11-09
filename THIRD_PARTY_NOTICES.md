# Third-party notices

The native board and companion artwork derive from BookOrbit. Its original notices and additional terms accompany this package in `NOTICE`, `LICENSE` and `ADDITIONAL_TERMS.md`.

Parts of the highlight posts and the pinned-pages badge are adapted from ZenOS (GNU GPL v3); see `ZENOS_NOTICE.md` and `LICENSE-GPL-3.0.md`.

The inline icon paths derive from Lucide (https://lucide.dev), including Feather-derived icons.

## Lucide — ISC License

Copyright (c) 2026 Lucide Icons and Contributors

Permission to use, copy, modify, and/or distribute this software for any purpose with or without fee is hereby granted, provided that the above copyright notice and this permission notice appear in all copies.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

## Feather-derived icons — MIT License

Copyright (c) 2013-present Cole Bemis

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

## Bookends (bookends.koplugin 5.31.0) — GNU AGPL-3.0

`aleph_bookends.lua` and `aleph_bookends_page.lua` (2026-11-09)
follow Bookends' design: its set of page stats and where each is read from
(KOReader statistics' average page time for time left, ReaderToc's pages left
in the chapter, the power device for battery and front light), hiding
KOReader's own status bar with applyFooterMode(off), not painting in the
forked thumbnail renderer, and a minute refresh that waits while the reader is
covered. The code is Reading Board's own and much smaller (no token language,
presets or icon fonts). Bookends is licensed under the GNU Affero General
Public License 3.0, the same licence as Reading Board.
