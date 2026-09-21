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

## 2026-09-21 — the app: corpus, login, pages, views

Built in one sitting on the documented path: `corpus.mojo` (load, facets,
the scan), `auth.mojo`, `pages.mojo`, `views.mojo`; 22 tests, a rewritten
`smoke.sh`, a browser walk (`tools/browse.py`). The first full build of four
new modules compiled at the first attempt but for one deprecation warning
(a nested `@parameter` closure — replaced with a plain function).

**Timings on this app** (M4): `m0 test` 7.1 s for two files (it was 3.9 s
for the scaffold's one — it grows by the file, each a separate `mojo run`);
`m0 build` 12.5 s after an edit. The test loop was the loop, as AGENTS.md
says: every logic error below was found there, none by a build.

### The measured claim: the in-memory scan

535 real notes, 800 KB of haystack, `x-scan-us` on every list response and
the same figure in the page:

| query | matches | scan |
|---|---|---|
| no filter | 535 | 5–12 µs |
| facet only (`/keywords/athletics`) | 41 | 8 µs |
| `q=the` (matches early in nearly every note) | 526 | 50 µs |
| `era=1930s&type=Students&q=chapel` | 5 | 90 µs |
| `q=football` | 39 | 439–534 µs |
| `q=zzzzqqqq` (no match: every byte read) | 0 | 417 µs |

Worst case is about half a millisecond, a naive byte scan, a default
(non-release) build, one worker. Whole requests measured by curl on
loopback: 0.5–1.2 ms. The plan's "comfortably under a millisecond" holds;
FTS5 would not have been faster at this size, only more to deploy.

### Finding 2 — no public way to build a query string

`url_for` encodes path parameters and nothing else. A filtered list's URL
(`/notes?q=a%20b&era=1890s`) needs a percent-encoder, and the framework's
is private (`router._percent_encode_into`). The app wrote its own
`query_encode` (20 lines, tested). Any app with a GET filter form will
write this. Candidate: `url_for(PATTERN, params..., query=...)` or a public
`query_string` helper.

### Finding 3 — the vocabulary cannot move the address bar

`Fragment[Htmx]` generates the swap and nothing about history. A filter
that swaps without changing the URL cannot be linked to or reloaded, which
for a research tool is the feature. AGENTS.md says never to type an `hx-`
swap attribute by hand; this app types ONE, `hx-push-url="true"`, through
the `attrs` slot of `f.el(...)` — on every link and on the filter form. It
works in htmx 4.0.0 (browser-verified: URL moves, back restores the list
AND the form's values). This is D17's territory (`HX-*` setters, not
built) seen from the element side. Candidate: a `push=True` on `f.el` /
`swap`, which both vocabularies can honour in their own spelling.

Cosmetic, same place: a GET form sends every field, so the pushed URL is
`/notes?q=football&era=1890s&institution=&type=&keyword=`. The app's own
`list_url` writes only what is set; the browser's form does not.

### Finding 4 — a swap that changes WHO YOU ARE wants a navigation

First written as the scaffold teaches — every form an `f.el("form", verb,
url, …)` swap. In a browser, signing in left the list under `/login`, and
signing out left the login form under `/notes?q=…`: the fragment swapped,
the address did not. Login and logout are now PLAIN forms (`el("form",
method, action)`), answered with 303. The server still answers both shapes.
`apps/fragment_notes` (the worked example this login was copied from)
swaps its login; it has the same fault, unnoticed because its gate reads
the wire and not the address bar. Nothing in AGENTS.md's "When a login
arrives" says which to use. Candidate: one sentence there.

### Finding 5 — a test cannot give a request a cookie the documented way

A view that reads `req.cookies` sees nothing from a `Cookie` header on a
hand-built `HTTPRequest`: only the server's parser fills the jar. Seven of
twelve view tests failed on it (every signed-in one answered 303/401).
Fixed by reading framework source (`lightbug_http/cookie/request_cookie_jar.mojo`,
`http/request.mojo`): build a `RequestCookieJar`, `add_pairs("name=value")`,
pass `cookies=`. The scaffold's test file has helpers for GET and POST and
none for a cookie, and AGENTS.md's login section names the session module
but not how to test a view behind it. **First time framework source had to
be read to proceed.** Candidate: a `_with_cookie` helper in the scaffold's
test, or the two lines in AGENTS.md.

### Finding 6 — the worked example the scaffold points at is not installed

AGENTS.md: "`apps/fragment_notes` in the framework's repository is the
worked example." The wheel ships the five source trees and no `apps/`, so
the login's only reference is a GitHub URL the page does not give. Read
from a local checkout here. Candidate: the URL, or the example's auth as a
third template (see the next entry).

### D44's question: was the second login a copy of the first?

**Yes.** `auth.mojo` is `apps/fragment_notes`'s login with the names
changed: `Auth.from_env` (fail closed, key ring with a previous key, TTL,
`Secure`), `accepts` over digests, `session_of`, `private` (`no-store`),
`csrf_refusal` with its fail-closed first line, and in `views.mojo` the
`refuse` pair (303 for a navigation, 401 + the form for a swap) and the
two-line guard opening every view. About 150 lines, of which perhaps ten
are this app's own decisions (cookie name, a 12-hour TTL, a 32-byte key
floor, plain-form login). Eleven views open with the same two lines.
That is the evidence D38/D44 were waiting for: an auth template, or a
`m0_http` helper holding `Auth` + `session_of` + `refuse` + `csrf_refusal`,
is the next value. Proposed, not built here.

### Smaller things

- The editor cannot resolve `m0_http`/`lightbug_http`/`m0_host` (every
  import is a red squiggle) — known: the scaffold writes no LSP settings
  because `mojo.lsp.includeDirs` takes only absolute paths. `uv run m0
  include` prints the path to paste. A new user meets this in minute one.
- The host turns a `make` that raises into exit 78 with the app's own
  sentence (`UNOTES_KEY must be at least 32 bytes…`). `smoke.sh` asserts
  it. This worked exactly as documented and cost nothing to get.
- `max_workers() -> 0` with read-only state: not yet exercised at
  `--workers 2`; owed to the soak.
- `m0 image` not run: no docker daemon on the day. The Dockerfile and
  `.dockerignore` are edited to carry `data/` (the context is the working
  directory, so the gitignored export rides in); unverified until built.
