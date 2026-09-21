# SOAK_LOG — unotes on `m0`

The running record of building this app on the documented path: every
failure, every doc sentence that was wrong or missing, every time framework
source had to be read to proceed. Kept from the first command. Newest last.

Stack: `m0 0.1.0` from PyPI (published 2026-09-21), `mojo 1.1.0`, macOS
arm64 (M4). Read before starting, as a new user would: `packaging/m0/QUICKSTART.md`
(the site's `/mojo/` pages were not yet deployed), then the scaffold's
`AGENTS.md`.

## 2026-09-21 — scaffold and baseline

| step | result |
|---|---|
| `uvx m0 new unotes` | ok, 1.4 s, 17 files, template `views` |
| `uv sync` | ok; `uv.lock` names `m0 0.1.0` from pypi.org |
| `uv run m0 build` (first) | ok, 12.9 s, no warning |
| `uv run m0 test` | ok, 3.9 s, 6 tests |
| `./smoke.sh` | ok |

Nothing on the documented path failed. No framework source read yet.

## Finding 1 — an app author cannot open their own SQLite database

The corpus is `notes.sqlite`. The wheel ships five trees and m0-sqlite is
not one; `m0 build` has no way to pass `-lsqlite3`. So the input is prepared
outside the app: `tools/export.py` (stdlib `sqlite3` + `json`) writes
`data/notes.jsonl`, and the app reads that.

What the export step cost — the evidence for or against a sixth tree:

- **134 lines**, over the ~100 the plan allowed, about an hour and a half
  including the data findings below. Most of it is refusals, not copying.
- **The flat reader shapes the format.** `m0_core.json_parse` reads string,
  int, number and bool fields of ONE object — no arrays, no nesting. So
  every multi-valued field (keywords, type, institution, era, a theme's
  note ids) is one string joined with `|`, which the app splits, and the
  export must refuse a value holding `|` (zero do today).
- **A second copy of the data exists** and must be regenerated when the
  database changes; nothing tells the app its file is stale.
- What it bought: the app has no C dependency, the binary links nothing,
  and the real data is a file that can be swapped for an invented one —
  which is what lets this repository be public.

## Findings about the corpus (the owner's repository, not fixed from here)

Measured while writing the export; each is a row to look at in
`public-practice/research-notes`:

- `type` is multi-valued (FileMaker repeating values, newline-joined) — as
  planned — **and so are `institution` and `era`**: row 404 is
  `U Chicago` + `Other` and `1990s` + `1960s`. The export splits all three.
  The split belongs in `build_notes_db.py`, the way `keywords` already is.
- Row 3's `type` holds a whole sentence (a lecture's title and description),
  which becomes a one-note facet value. Exported as it is.
- Row 520's entered date is `8/1/999`, a typo with no squeezed twin. The
  export reports it by row and leaves `entered` blank.
- The plan measured entered dates as 1995–1999. They run to **2001**
  (rows 529–535), in `M/D/YYYY`. And the squeezed form's ambiguous shape —
  five digits opening with `1` — is REAL, not hypothetical: `12600` is
  12/6/00 and `11501` is 1/15/01. Every such row also has the slashed
  date, which wins, so the parse is still total; the refusal stays.
- One row (the plan's "stray record") holds a source description and
  "Finish notes" in `field_9–11`. Those columns are dropped.
- The theme map cites notes as `[N]` and `[N]–[M]`; `N` is `notes.row_id`.
  12 themes, 6–81 notes each, every cited id exists. One `[359-431]` in a
  quotation is a page range, not a citation; it is outside the paragraph
  the export reads.
