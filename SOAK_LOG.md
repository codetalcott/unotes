# SOAK_LOG — unotes on `m0`

The running record of building this app on the documented path: every
failure, every doc sentence that was wrong or missing, every time framework
source had to be read to proceed. Kept from the first command. Newest last.

Stack: `m0 0.1.0` from PyPI (published 2026-09-21), `mojo 1.1.0`, macOS
arm64 (M4); `m0 0.2.0` from 2026-09-24 (the first upgrade, below); `m0
0.3.0` from 2026-09-27 (the second); `m0 0.4.0` from 2026-09-30 (the
third). Read before starting, as a new user would: `packaging/m0/QUICKSTART.md`
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

*Upstream, 2026-09-21:* mojo-http #369 adds `Query` beside `url_for`
(`q.add(name, value)`, `q.on(path)`; SPEC N36), with this app's encoder as
its seed. `query_encode` and `_put` stay here until an `m0` release carries
that source.

*Taken, 2026-09-24:* `m0 0.2.0` carries `Query`. `query_encode` and `_put`
are deleted; `list_url` is `Query().add(…)` then `q.on(url_for(NOTES))`, and
the test that pinned this app's URLs passes against it unedited.

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

*Upstream, 2026-09-21:* mojo-http #370 adds `push=True` to `f.el` and
`f.swap` (SPEC N37). Not quite "both vocabularies": `Htmx` writes
`hx-push-url`, and `Datastar` REFUSES, its 1.0.3 bundle having no history
handling for the back button to meet (DECISIONS D46). Only a `get` is
pushed. The hand-typed attribute stays here until an `m0` release.

*Taken, 2026-09-24:* `m0 0.2.0` carries `push=True`. Both hand-typed
attributes are deleted, and a test holds that every swap on four pages is
pushed. The cosmetic half stands: the browser walk on 0.2.0 still pushes
`/notes?q=football&era=1890s&institution=&type=&keyword=`.

### Finding 4 — a swap that changes WHO YOU ARE wants a navigation

First written as the scaffold teaches — every form an `f.el("form", verb,
url, …)` swap. In a browser, signing in left the list under `/login`, and
signing out left the login form under `/notes?q=…`: the fragment swapped,
the address did not. Login and logout are now PLAIN forms (`el("form",
method, action)`), answered with 303. The server still answers both shapes.
**Correction, same day:** this was first logged as a fault the worked
example shares. It does not. `apps/fragment_notes`'s `render_login` IS a
plain `<form method="post">`, with a comment saying exactly why; this app
copied its VIEWS and wrote its own renderer without reading that one. So
the rule exists, in a file the wheel does not ship (finding 6), and not in
the scaffold's AGENTS.md "When a login arrives", which is the page a
scaffolded app's author reads. Candidate: one sentence there — "login and
logout are plain forms answered with a 303; a swap leaves the address bar
behind."

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
- `max_workers() -> 0` with read-only state, exercised: `--workers 2`
  loads the corpus in each worker (the startup line prints twice), and a
  session signed by one verifies on the other — 40 of 40 fresh
  connections answered 200 with one cookie. Stateless sessions are what
  make that free. Under load is owed to the soak.
- `m0 image` not run: no docker daemon on the day. The Dockerfile and
  `.dockerignore` are edited to carry `data/` (the context is the working
  directory, so the gitignored export rides in); unverified until built.

## 2026-09-21 — the image and the deploy

| step | result |
|---|---|
| `uv run m0 image` (colima, aarch64) | ok, first attempt. In the builder `uv sync --frozen` installed `m0==0.1.0` **from the index** — the published wheel's one path no gate in the framework's repository can take — and `m0 build --release` said `built dist/ for generic`. `about.json`: `python: false`, app 4.0 MB (binary, runtime, corpus), image 103 MB unpacked |
| the image, run locally | serves the real corpus (`535 notes, 12 themes from data/notes.jsonl`); with no `UNOTES_KEY` exits 78 with the app's own sentence |
| `fly apps create unotes` | ok; the one name served as directory, repository and Fly app, so the plan's fallback (`unotes-wt`) was not needed |
| `fly secrets set --stage` then `fly deploy -c deploy/fly.toml --remote-only --ha=false` | ok, first attempt, x86-64: `built dist/ for x86-64-v2`, image 24 MB compressed (81 MB unpacked), one machine, health check 1/1 |
| https://unotes.fly.dev | anonymous `/notes` → 303 `/login`; an anonymous swap → 401, no corpus text; login sets a `Secure; HttpOnly` cookie; list, search, themes answer |

Nothing on the documented deploy path failed. Two edits to the scaffold's
files were the app's own: `data/` let into `.dockerignore` and copied
beside the binary, `UNOTES_SECURE` in `fly.toml`. `--ha=false` replaced
the README's "deploy, then `fly scale count 1`" — one step instead of two,
and no moment with two machines; a candidate for `deploy/README.md`.

### The measured claim, on the deploy target: NOT under a millisecond

Same queries, `x-scan-us`, Fly `shared-cpu-1x` (x86-64-v2 baseline build):

| query | M4, default build | Fly shared-cpu-1x, release |
|---|---|---|
| no filter | 5–12 µs | 14 µs |
| `q=the` | 50 µs | 188 µs |
| `q=football` | 430–530 µs | 1,420–1,530 µs |
| `q=zzzzqqqq` (every byte read) | 417 µs | 1,520–2,160 µs |

About 3.5x the laptop, steady over repeats (the first request was the
slowest). The plan's bar — "comfortably under a millisecond; if not, say
so" — holds on the M4 and does NOT hold on the smallest Fly machine: a
worst-case search costs 1.5–2 ms of a shared vCPU. It is invisible in use
(the round trip from here is 40–57 ms) and it bounds one loop at roughly
500 worst-case searches a second. The scan is the naive one — a byte loop
with a first-byte test — and the obvious next step (a SIMD first-byte
search, the idiom the framework's own parser uses) was not taken, because
nothing about one reader needs it. What this does say: "sub-millisecond in
Mojo" is a claim about a core, and the docs' index page should name the
machine when it makes it.

## 2026-09-21 — synthetic soak (local; the deployed instance gets the real use)

**Which traffic this is: synthetic.** mojo-http's `scripts/soak.py` speaks
plain HTTP, so it ran against a local `bin/server --workers 2` on the real
corpus, M4, default build. `tools/soak_manifest.json` is the manifest. The
capture was recorded from the same binary one request at a time, then every
response under load was compared to it — status, headers, a digest of the
body with the scan figure and the CSRF token normalised. The claim tested:
a byte served under load is the byte served alone.

| phase | shape | result |
|---|---|---|
| B, 180 s | 6 keep-alive bursts, 4 signed-in sessions, SIGTERM + restart every 40 s with everything in flight | **1,739,529 verified, 0 failures**; 4 restarts, drain ≤ 3 ms, exit 0 each; RSS 16.6 → 16.7 MB; fds and threads flat |
| A, 12 s ×4 (two workers) + ×1 (one) | the above plus an abandoner: leaves mid-body (FIN and RST alternating) and at once reuses the slot | ~100,000 verified per run; **1 failure in ~40,000 abandonments**, below |

**The one failure, observed once and not explained.** In the first phase-A
run the abandoning client got `ConnectionResetError` reading from its own
fresh connection. Every ANSWERED response in that run was byte-exact, the
server logged nothing, the kernel counted 0 listen-queue overflows, and the
shape did not recur in four more runs (three at two workers, one at one).
At ~820 new connections a second it may be the client, the kernel or a
server close with unread input; one occurrence cannot say. Recorded because
a rerun that passes is not an explanation.

*2026-09-30:* `m0 0.4.0` fixes a mechanism that fits it; see "the
synthetic soak's one failure, revisited", under the third upgrade.

**Two findings about the instrument, neither about the server:**

- Its abandoner is unpaced: it leaves after 4 KB or a time window, and
  against a server that answers 42 KB in under a millisecond the byte count
  always wins, so it opens ~515 connections a second. Two attempts at a
  180 s mixed run exhausted the CLIENT's ephemeral ports inside 25 s
  (203,993 `OSError 49`s; `gh` on the same machine failed at the same
  moment). Through both, the server verified 736,955 responses with none
  wrong. Hence two phases. Candidate for soak.py: a pause between
  abandonments.
  *Upstream, 2026-09-21:* mojo-http #368, `--abandon-pause` (50 ms).
  Measured against this app, two abandoners, 6 s: paced, 212 abandonments
  and 0 failures; unpaced, 16,339 and 597 `OSError 49`.
- `body_sub` runs on decoded text. A page that echoes a non-UTF-8 query
  into its form does not decode, keeps its CSRF token, and fails the digest
  for the driver's reason. That route is out of the manifest and stays in
  `test_views.mojo` and `smoke.sh`.

Smaller, and the app's own: that page DOES emit the query's raw bytes inside
a `text/html; charset=utf-8` body. `attr()` escapes markup, not encoding. A
browser shows replacement characters; nothing breaks. Noted, not changed.

Not covered here and owed to the use window: the deployed instance under
real use (a phone that sleeps and reconnects), and a Fly deploy while a
reader is mid-session.

*Taken, 2026-09-24:* both, on the deployed instance, in "the real use the
log owed" below — the phone emulated, and said so.

## 2026-09-24 — the first upgrade: `m0 0.1.0` → `0.2.0`

`m0 0.2.0` reached PyPI at 01:49 UTC on 2026-09-25 (framework 1.6.0, commit
`5a683eb`), gated on the same `mojo 1.1.0`. It is the first `m0` upgrade an
application outside the framework's repository has taken: everything above
was built on one version.

| step | result |
|---|---|
| the pin, `m0==0.1.0` → `0.2.0`, then `uv lock` and `uv sync` | ok; `uv.lock` names `m0 0.2.0` from pypi.org. `mojo` did not move — 0.2.0 is gated on 1.1.0, as 0.1.0 was — so `pyproject.toml`'s "move them together" was a move of one |
| `uv run m0 doctor` | ok, every check |
| `uv run m0 test`, the app unedited | 22 of 22 |
| `uv run m0 build`, the app unedited | ok, 13.1 s, no warning |
| `./smoke.sh`, the app unedited | ok |

The version alone changed nothing this app could see. The change 0.2.0 says
a call site must handle — `m0-datastar`'s frame builders now raise — is in
a tree this app does not import, and a request that now reaches a view as
its client sent it (no invented `Content-Length`, `Connection` or `Host`)
changes no header this app reads: it reads its CSRF header and its cookie.

### What the upgrade let the app delete

- `query_encode` and `_put`, 28 lines, for `Query` (finding 2). `list_url`
  is seven `q.add(…)` and a `q.on(url_for(NOTES))`, and the URLs it writes
  are byte for byte the ones its test pinned on 0.1.0. The test's `é` case
  moved from the deleted encoder to `list_url`.
- Both hand-typed `hx-push-url` attributes, and the module docstring's
  paragraph excusing them, for `push=True` on `_link` and on the filter form
  (finding 3). The vocabulary writes the attribute after the swap's three
  rather than before them; nothing reads the order. A new test,
  `test_every_swap_moves_the_address_bar`, counts `hx-push-url="true"`
  against `hx-get=` on four pages and finds no `hx-post`; with `push=True`
  taken off `_link` it fails.
- `src/pages.mojo` 381 → 347 lines; 23 tests; `./smoke.sh` ok. The browser
  walk (`tools/browse.py`, real corpus) reads as it did on 0.1.0: the filter
  and each link move the address bar, back restores the list and the form's
  `q`, one `section` in the DOM.
- Framework source read: `Query` in `m0_http/router.mojo` and `Fragment.el`
  in `html.mojo` (`push` is a keyword after `*children`), before editing
  rather than after a failure. The CHANGELOG and 0.2.0's `AGENTS.md` name
  both; the read was a check, and may not have been needed.

### Finding 7 — an upgrade brings the framework, not the page an agent reads first

This app's `AGENTS.md` was byte for byte what 0.1.0's `m0 new` wrote.
0.2.0's template is 25 lines longer, and five of its additions came from
this log: `Query` (finding 2), `push=True` (3), login as plain forms (4), a
cookie in a test (5), the worked example's URL (6); a sixth covers
`read_signals`. `uv sync` updates the source trees and not a word of that
page, so an app upgraded the documented way keeps an `AGENTS.md` that says
"never build a path by hand" and nothing of a query string, and points at a
worked example that is not installed. No `m0` command refreshes it, and none
says it is stale. Taken here by hand — the 0.2.0 wheel's
`m0/templates/_common/AGENTS.md` rendered with the app's name, its one
placeholder — which was safe only because this app never edited its copy.
Of everything else `m0 new` writes, only the `live` template's
`src/pages.mojo` differs between the two wheels, so a `views` app has
nothing more to take. Candidate: `m0 doctor` names a scaffold-written file
that differs from the installed wheel's template — a warning, not a merge.

### Finding 8 — nothing deployed says which `m0` built it

The image's `about.json` records the APP's version (`"version":"0.1.0"`,
this app's own, which the upgrade did not touch); `--doctor` prints the
host's configuration and no framework version. What built a binary is in
`uv.lock`, in git, and in `_build_info.json` in whichever venv built it, so
"is the deployed app on the latest `m0`?" was answered from a release date.
Candidate: `m0 build` carries `_build_info.json`'s `m0`, `framework` and
`commit` into the binary's `--doctor`, and `m0 image` into `about.json`.

### The image and the deploy, on 0.2.0

| step | result |
|---|---|
| `fly deploy -c deploy/fly.toml --remote-only --build-only --push --image-label m0-0.2.0` | ok, 63 s. The builder's `uv sync --frozen` installed `m0==0.2.0` from the index; `built dist/ for x86-64-v2`; `about.json`: `python: false`, app 4.46 MB, image 81 MB unpacked, 24 MB compressed |
| `fly deploy -c deploy/fly.toml --image registry.fly.io/unotes:m0-0.2.0 --ha=false`, under a reader (below) | ok, 18 s; release v2, one machine |
| the scan on the deploy target, `x-scan-us`, six of each | no filter 5–8 µs, `q=the` 184–284, `q=football` 1,243–1,611, `q=zzzzqqqq` 1,171–1,690 — 0.1.0's figures, give or take what six samples on a shared vCPU can tell apart |

Building apart from the rollout was this entry's choice, so that the
reader's window held the machine swap and not a remote compile.

## 2026-09-24 — the real use the log owed

### A deploy while a reader is mid-session

**Which traffic this is: real, on the deployed instance, from one laptop.**
Two clients held the site across the rollout above: a signed-in Chrome
(`tools/reader.py … hold 200`) tapping a nav link every ~2.3 s, and
`tools/probe.sh`, a signed-in swap of `/notes/25` back to back (about three
a second). `fly logs` recorded the machine. The password is the deployed
secret, copied off the machine (`fly ssh console -C 'printenv …'`) into a
file that was never printed.

| UTC | event |
|---|---|
| 03:06:24 | `fly deploy --image` starts |
| 03:06:26 | the machine starts pulling the image. The probe's last answer from the old binary is at 03:06:26.4; its next request, sent at 03:06:26.7, is not answered until the new binary is up |
| 03:06:28 | SIGINT to `/app/server` (Fly's default); the proxy logs `PC01 instance refused connection` — a request tried against the closed listener and retried, not failed: no client saw it |
| 03:06:29 | the old server exits 0 |
| 03:06:30 | the new one listens, corpus loaded ("Machine created and started in 4.282s") |
| 03:06:31.2 | the reader's held tap is answered: 200, after 2,382 ms |
| 03:06:32.3 | the probe's held request is answered: 200, the fragment, after 5,586 ms |
| 03:06:42 | `fly deploy` exits 0 |

- **Nothing failed and no one was signed out.** The probe: 435 of 435
  answered 200 with the fragment. The reader: 85 taps, 89 requests, none
  failed, none answered ≥ 400, no reload. Its session was signed before the
  deploy and verified after it, because the key is a secret the deploy does
  not touch — the second thing stateless sessions made free (the first was
  two workers, above).
- **A deploy is one slow tap**: 2.4 s for the reader, 5.6 s for the probe,
  which was further into the hold. With one machine there is none to route
  to, and Fly's proxy holds and retries rather than fails. Whether any
  request was in flight at the SIGINT this run cannot say — the host logs
  nothing when it drains — but none was lost, and the old server exited 0
  within the second, well inside the 5 s kill timeout.

### Finding 9 — a request with no answer is a dead link, silently

Rehearsed first on loopback, with nothing in front: the same reader, and a
server that was simply gone (SIGINT, restarted 8 s later). Three taps in the
gap each failed at once (`ERR_CONNECTION_REFUSED`), and the page did
nothing — no message, no change, the link dead until the server was back,
when the next tap worked in the same session. htmx 4 swaps every ANSWER; a
request that gets none fires `htmx:error`, which nothing here listens to.
Behind Fly's proxy a reader does not meet this (it holds, above). On a host
with nothing in front, or a gap longer than the proxy will hold, the silent
dead link is what they get, and on a phone it reads as a missed tap.
Candidate: the scaffold's shell carries the one listener that puts "the
server did not answer — try again" in the fragment.

### A phone that sleeps and reconnects

**Which traffic this is: an EMULATED phone, on the deployed instance and on
loopback.** `tools/reader.py … sleep N --phone` is Chrome's Pixel 7
emulation (viewport, touch, user agent) on the laptop. It signs in, filters,
opens a note, then sleeps: the context goes offline and the page is frozen
through DevTools (`Page.setWebLifecycleState`) for N seconds; then it wakes
and taps. It is not a phone: no radio goes down, no OS discards the tab, and
the connection pool is desktop Chrome's. What it does exercise is the app's
side of waking — a page left open, a connection gone idle, a tap.

**Asleep ten minutes on the deployed instance** (03:09:20 → 03:19:20 UTC,
inside the twelve-hour session). The reader went to sleep on `/notes/25`,
reached through a filter:

| on waking | answer | address bar | shown |
|---|---|---|---|
| tap Themes | 200 `/themes`, 86 ms | `/themes` | the themes |
| back | 200 `/notes/25`, 38 ms | `/notes/25` | Note 25 |
| reload | 200 `/notes/25`, 18 ms | `/notes/25` | Note 25 |

Nine requests, none failed, none answered ≥ 400. The first tap took 86 ms
against 21–62 ms for every warm tap in this entry; whether that was a new
connection to Fly's edge, this run does not say. Inside the session's
lifetime, waking is invisible. Past it, it is not:

**Past the session's lifetime** — loopback, `UNOTES_TTL=8`, asleep 12 s:
the case a phone meets overnight, since a session lasts twelve hours. The
reader was on `/notes/25`.

| on waking | answer | address bar | shown |
|---|---|---|---|
| tap Themes | 401 `/themes` | `/themes` | the login form, "signed out (no cookie)" |
| back | 303 `/notes/25` → 200 `/login` | `/notes/25` | the login form |
| reload | 303 → 200 `/login` | `/login` | the login form |
| sign in | 303 `/notes` | `/notes` | the unfiltered list |

### Finding 10 — a refusal is pushed, and signing in forgets where the reader was

The refusal itself is right: a swap gets 401 and the form, as `refuse`
intends. Two things around it are not.

- **`push=True` pushes a 401.** htmx 4.0.0 decides history without looking
  at the status (`#resolveHistoryAction`), so the address bar says `/themes`
  over a login form, and history holds an entry that shows what it does not
  name. Finding 4 from the other side: there a swap failed to move the
  address bar when it should; here it moves it when it should not.
  `push=True` is a claim about the view a swap arrives at, and a refusal is
  not that view. htmx honours `HX-Push-Url: false` on a response (it
  normalises `"false"` to no push). Candidate upstream: a refusal answered to
  a swap carries it — `page_or_fragment` at any status ≥ 400. This app's
  `refuse` could set the header by hand today, against D17's "`HX-*`
  setters, not built".
- **Signing in always lands on `/notes`.** The login form posts to `/login`,
  which answers 303 `/notes` whatever was open, so a phone that slept on a
  note wakes to the unfiltered list. Candidate — this app's, and the auth
  template's that the D44 entry proposes: the refusal renders the
  form with a hidden `next` naming the request's own path, and a sign-in
  answers 303 to it; a local path only, or it is an open redirect.

Smaller, same place: "signed out (no cookie)" is what a person reads. The
browser dropped the cookie at its `Max-Age`, so the server never saw one,
and the reason reads like a fault. "Your session ended; sign in again."

### Smaller things

- `HEAD` is 405 on every view route (`Allow: GET, OPTIONS`), `/health`
  included, on 0.1.0's deploy and on 0.2.0's. That is SPEC N2 as written — a
  method a view does not take is 405 with `Allow` — and HEAD is such a
  method; K12, K13 and L27 hold HEAD for the WSGI and ASGI bridges only.
  RFC 9110 wants HEAD wherever GET is, and an uptime check that sends one
  would call this app down. Candidate: a route that takes GET answers HEAD
  as its GET, the body dropped.

  *Taken upstream in `m0 0.3.0` (N38); see the second upgrade, below.*

## 2026-09-27 — the second upgrade: `m0 0.2.0` → `0.3.0`

`m0 0.3.0` reached PyPI at 18:08 UTC on 2026-09-27 (framework 1.7.0, commit
`1946db3`), gated on the same `mojo 1.1.0`, and on `max-core 26.6.0` for an
application that installs it; this one does not. Two of its changes began
here: the HEAD fix, which its CHANGELOG credits to this app's deploy, and
`m0_http.login`, whose docstring calls it the login `apps/fragment_notes`
wrote by hand "and that the first application outside this repository
copied with its names changed".

| step | result |
|---|---|
| the pin, `m0==0.2.0` → `0.3.0`, then `uv lock` and `uv sync` | ok; `mojo` did not move |
| `uv run m0 doctor` | ok, every check. Two lines are new: `max-gated` (absent, optional, naming the `uv add`) and `scaffold`, naming seven files (below) |
| `uv run m0 test`, the app unedited | 23 of 23 |
| `uv run m0 build`, the app unedited | ok, 14.5 s, no warning |
| `./smoke.sh`, the app unedited | ok |

As with 0.2.0, the version alone changed nothing the app could see except
on the wire: HEAD.

### What the upgrade let the app delete

- `src/auth.mojo`, all 156 lines, for `m0_http.login`. The layer's `Login`
  is this file's `Auth` with the cookie's name added; `accepts` and its
  digest compares, `csrf_refusal` and `private` (now `no_store`) are line
  for line but for a message. The question the deleted file's docstring asked — whether the
  second hand-rolled login is a copy of the first — was answered upstream
  by setting the two side by side, and now neither app has one. What stays,
  in `views.mojo`, is policy: the prefix `UNOTES`, the cookie
  `unotes_session`, the user `reader`, twelve hours — four constants and
  `login_from_env`, which passes them.
- `refuse` is one call to `refuse_signed_out`. `login` is `sign_in` and
  `set_cookie` where it was `accepts`, `issue_session`, `verify_session` and
  a hand-built cookie line; `logout` is `sign_out`; the hidden CSRF field is
  `csrf_input`. The swapped sign-in that answers the list still works:
  `SignIn.session` is the verdict the page renders behind.
- `src/` 1,184 → 1,055 lines.
- `main` now reads the login before `serve`, as the `auth` template's does
  and the new `AGENTS.md` says to, so `bin/server --doctor` refuses a
  missing `UNOTES_KEY` (78) where before only a run did; `smoke.sh` holds
  it. The price is that `uv run m0 doctor` on a machine with a built binary
  needs the two variables, or exits 78 on its app line. CI's does not: it
  runs before anything is built.

The configuration is stricter, all of it from `Login.from_env`:

- `UNOTES_SECURE` is `1` or `0`, and `true` is refused. The hand-written
  policy read anything but `1` as off, so `true` behind TLS dropped
  `Secure` without a word. The deploy sets `1`.
- `UNOTES_KEY_PREV` must be 32 bytes, as the key must; `UNOTES_TTL` is at
  most 400 days; `UNOTES_USER` must be a name a session can carry.
- A CSRF refusal's detail now reads "the request did not carry this
  session's CSRF token".

Two tests are new. `test_the_login_policy_is_read_from_unotes_variables`
pins the four names and defaults through the environment, and the `true`
refusal. `test_a_get_route_answers_head_as_its_get` covers five routes
and the guard. That makes 25 tests. `./smoke.sh` is ok, now probing HEAD and
`--doctor`. The browser walk (`tools/browse.py`, the real corpus,
loopback) reads as it did on 0.2.0: a wrong password is the alert at
`/login`, a sign-in lands on `/notes`, the filter and a note move the
address bar, back restores the list and the form's `q`, and signing out
lands on `/login`, with one `section` in the DOM. The one console line is
the wrong password's 401.

Framework source read, before editing and not after a failure:
`m0_http/login.mojo`, whole, and the `auth` template's `views.mojo` and
`server.mojo`, written into a scratch directory with `m0 new --template
auth` as the worked example. The CHANGELOG named both.

### What closed upstream, and what did not

- HEAD (smaller things, above): N38. On loopback `HEAD /health` is 200
  and a signed-in HEAD of a note 200; through the table a signed-out one
  is 303, as the GET.
- Finding 7 (an upgrade brings the framework, not the page): the doctor's
  `scaffold` line (N42). This upgrade is its first use; finding 11 is what
  it found.
- Findings 4–6 went into 0.2.0's `AGENTS.md` as prose. The worked example
  is now installed as `m0_http.login` and the `auth` template.

Not closed: 8, since `--doctor` still names no `m0` and `about.json` no
framework. Not 9: no template's shell listens for `htmx:error`. Not 10:
`refuse_signed_out` sets no `HX-Push-Url: false` and takes no `next`, so a
401 is still pushed and a sign-in still lands on `/notes`. The refusal now
lives in the layer, so each candidate is one edit there rather than one
per app. "signed out (no cookie)" is still what a person reads, and the
`auth` template writes the same words.

### What the scaffold line named, and what was taken

`uv run m0 doctor` named seven files. To tell which differ because `m0`
changed them and which because this app did, BOTH versions' scaffolds went
into a scratch directory (`uvx --from m0==0.2.0 m0 new unotes`, and
0.3.0's), and each file was diffed three ways:

| file | `m0` changed it | this app had edited it | taken |
|---|---|---|---|
| `AGENTS.md` | yes: the login, storage, MAX, upgrading | no | verbatim |
| `deploy/README.md` | yes: `libsqlite3`, a volume, `M0_THREADS` | no | the `M0_THREADS` sentence, and a paragraph on what was declined |
| `deploy/Dockerfile` | yes: `libsqlite3-0`, `/app/data`, `M0_DB`, `libs` in `about.json` | yes: the corpus `COPY` | a comment saying why nothing was |
| `deploy/fly.toml` | yes: a commented-out `[mounts]` | yes: `UNOTES_SECURE` | nothing |
| `.gitignore` | yes: `*.db` | yes: the corpus | nothing |
| `.dockerignore` | no | yes | — |
| `.github/workflows/test.yml` | no | yes | — |

`pyproject.toml`, which the doctor does not compare, gained a comment on
the `max-core` pin; taken, since the new `AGENTS.md` points at it.

Everything `m0` changed outside `AGENTS.md` was for SQLite, and this app
opens none; its input is the JSONL export (finding 1, which `m0_sqlite` in
the wheel now answers: the app could open `notes.sqlite` itself). Taking the Dockerfile as written would have broken
the build: its `RUN mkdir /app/data` follows this app's `COPY data/
/app/data/`, and `mkdir` fails on a directory that exists. The template now
claims `/app/data` as the writable database directory, and this app ships
its corpus there, read-only. And the `AGENTS.md` taken verbatim says
"`libsqlite3-0` is in the image already", which for this image is false:
the page's claim rests on a Dockerfile the app declined.

### Finding 11 — the scaffold line cannot tell an upgrade's change from the app's own

The line is the upgrade path's one signal, and it names a file whichever
side moved. Of the seven here, two were named for this app's edits alone,
two for `m0`'s alone, and three for both, and the line reads the same for
all seven. D52 chose this ("only the application can tell which") and
declined a record of what the old `m0` wrote: that base "is recorded
nowhere", and a version stamp "would make every upgrade report every
file". What it took here was the old scaffold, which is recoverable from
PyPI for any published `m0`, given which one wrote the project, and that
only `uv.lock`'s history says. `AGENTS.md` says to write the NEW scaffold,
not the old. After this upgrade the line names the same seven again, five
of them for decisions already made, so at 0.4.0 it will not say which of
them 0.4.0 changed. Candidates, the cheap one first: the upgrading section
says to write the old scaffold too (`uvx --from m0==OLD m0 new`) and diff
three ways. Or `m0 new` records each file's hash: unlike a version stamp,
a hash moves only when that file's content does, so the doctor could say
"edited here", "changed upstream" or both, and stay quiet on the rest.

### A latent refusal: `url_for` and a dot

`url_for` now raises on a `.` or `..` parameter (N5). The one `url_for`
parameter here that comes from data is a keyword: `url_for(KEYWORD, k)` on
every note page that carries it and on `/keywords`. Before, such a keyword
was a link a browser resolved somewhere else. Now it is a raise inside the
render, and the view goes with it. Checked: none of the real corpus's 164
keywords or the sample's 15 is either. `tools/export.py` does not filter
them, so the day one is exported, its notes stop rendering. Noted, not
changed.

## 2026-09-27 — the export step, dropped

Finding 1 was that an application could not open its own SQLite database,
so `tools/export.py` turned `notes.sqlite` and `theme-map.md` into JSON
lines and the app read those. `m0 0.3.0` ships `m0_sqlite`, which opens
libsqlite3 at run time and links nothing, so the app now reads both files
itself and the export is deleted. The database is opened with
`open_readonly`: it is the owner's working database, and the app never
writes it.

| step | result |
|---|---|
| `src/sources.mojo`: the export's rules, in Mojo | 530 lines, docstrings included, against the export's 134. Mojo has no regex, and six patterns became byte scanners. Compiled at the first attempt |
| the sample | `data/sample.sql` and `data/sample-theme-map.md`, invented, replacing `data/sample-*.jsonl`. Stored as FileMaker left the real data: repeating values split at a line feed, CR LF or vertical tab, `::` comments, entered dates in all three shapes, a non-breaking space. Read by the OLD export, it gives the old sample exactly, keyword order aside |
| tests | 36, up from 25. `test_sources.mojo` is new, with 12. Each of nine rules, reverted in turn, fails a test |
| equivalence, on the real data | 4,851 fields byte for byte identical to the export's (535 notes × 9, 12 themes × 3), and the export's one warning, row 520's date, word for word |
| the database, after reading it | untouched: mtime, size and hash the same, and no journal, `-wal` or `-shm` beside it |
| startup to `/health`, the real corpus | 26–43 ms from `notes.sqlite`, 43–45 ms from the JSON lines, three runs each |
| `bin/server` | 1,354,368 → 1,472,528 bytes: +118 KB for the SQLite bindings |
| `uv run m0 build` | 13.8 s |
| `./smoke.sh`; the browser walk on the real corpus | ok; the walk reads as the JSONL one did, count for count |

The data exercised the rules, so "identical" is not vacuous. 141 rows
have repeating separators in `type`, `institution` or `era`, 249 entered
dates come from the squeezed field alone, and 3 comments open with `::`.
One rule it did not exercise: no cell the app reads has whitespace at
either end. Mojo's `String.strip()` knows ASCII whitespace only, and
Python's `str.strip()`, which shaped the export, knows 29 characters. So
`strip_space` keeps Python's set, and today that is insurance rather than
a fix.

Framework source read, before editing: `m0_sqlite`'s `__init__.mojo` (its
exports), `conn.mojo` (`open`, `open_readonly`, `open_memory`, `execute`),
`stmt.mojo` (`column_text` answers "" for NULL and does not check UTF-8)
and `lib.mojo` (where it looks for libsqlite3).

### Finding 1, revisited

What the export cost, as finding 1 listed it:

- **134 lines.** Now 530 in the app, docstrings included. The export is
  gone, and so is the step, but not the work: the rules moved rather than
  disappeared, at about four lines of Mojo for each of Python's.
- **The flat reader shapes the format.** Gone. Lists go straight into the
  corpus, and the refusal of a value holding `|` went with the format.
- **A second copy of the data, stale without a word.** Gone locally: the
  app reads the database where it lives. For an image one copy remains,
  since a build context cannot reach it. `VACUUM INTO` makes the copy,
  because a `.backup` of a WAL database stays WAL, and a WAL file cannot
  be opened read-only in the image's read-only `/app/data`. Measured on a
  scratch database: `.backup` keeps header bytes 18–19 at 2, and
  `VACUUM INTO` writes 1.
- What it bought: no C dependency, a binary that links nothing, and a real
  file swappable for an invented one. The binary still links nothing: the
  image installs `libsqlite3-0` (so the scaffold's runtime-libraries line,
  declined at the second upgrade, is taken now) and `m0_sqlite` opens it.
  The sample is SQL text, still invented and still swappable, and still no
  binary in git.

What it costs that the export did not:

- **The image carries the whole database**: `fm_id`, FileMaker's own
  `keywords` text (483 rows), the stray record's source description and
  "Finish notes" in `field_9–11` (its three cells are the only ones there;
  `field_4` is empty), and the full-text index. The export carried a
  projection of it. An image built with the
  real files already belonged in a private registry; now it holds more.
- **The move from one input to the other has a trap.** A working
  directory with the old export and no database would have served the
  invented sample in place of the notes, saying so only in a startup line.
  The server now refuses that case (78), and the image build fails while
  the old export is in `data/`, so `fly deploy` stops before it touches a
  machine.

### Finding 12 — the page an agent reads first sends a reader of someone else's database to `open`

`AGENTS.md`'s storage section names two constructors: "`open(path)` puts
the file in WAL mode … `open_memory()` is for tests." Following it here
would have switched the owner's research database to WAL, which persists
in the file's header, and left `-wal` and `-shm` files beside it. That is a
write to a database this app has no business writing, made by opening it.
`open_readonly(path)` exists, and leaves the journal mode alone. It creates
nothing, and a missing file is refused rather than created. It was found in
the package's exports, not on the page. This app also uses `open_memory()`
outside tests, for the sample. Candidate: one line in that section: "a
database the app only reads (another tool's, or its input) is
`open_readonly(path)`: no WAL switch, no create".

*Correction to the entry above:* its keyword counts, first written as 48
and 22, were distinct characters, not keywords. The check iterated the
joined string, and so it examined no keyword at all. Recounted: 164 in the
real corpus and 15 in the sample, none of them `.` or `..`. The entry was
corrected before either was published.

## 2026-09-27 — the deploy, on 0.3.0 and the database

**Which traffic this is: none generated.** No reader was signed in. The
checks are the machine's own log and five probes without a session, since
the password is a secret this session did not read. A signed-in page on the
deploy, and the scan's figures on its CPU (measured for 0.2.0 above), are
owed.

The order mattered because `fly deploy` builds the working directory, not
what GitHub holds. The one bad combination was the new data with the old
code: 0.2.0's server, finding no `data/notes.jsonl`, would have served the
invented sample without a word. So the steps were these:

1. The PR was merged with GitHub's "Rebase and merge". It carried six
   commits, two of them the 0.2.0 upgrade's, which had never been pushed.
   The rebase rewrote every SHA, and `git pull --rebase` then dropped the
   local originals as already upstream.
2. `data/` was swapped. The old export was deleted, and
   `sqlite3 -readonly … "VACUUM INTO 'data/notes.sqlite'"` made the copy,
   in rollback-journal mode. The theme map was copied beside it.
3. A local run said `535 notes, 12 themes from data/notes.sqlite`.
4. The build and the rollout ran apart, as at the first upgrade.

| step | result |
|---|---|
| `fly secrets list` | `UNOTES_KEY` and `UNOTES_PASSWORD` only, so 0.3.0's stricter `Login.from_env` had nothing new to refuse |
| `fly deploy -c deploy/fly.toml --remote-only --build-only --push --image-label m0-0.3.0-sqlite` | ok, 117 s. `libsqlite3-0` 3.40.1 installed, the old-export guard passed, `built dist/ for x86-64-v2`. `about.json`: `"libs":"libsqlite3-0"`, `python: false`, app 5.32 MB, image 83.5 MB unpacked (0.2.0's: 4.46 MB and 81 MB) |
| `fly deploy -c deploy/fly.toml --image registry.fly.io/unotes:m0-0.3.0-sqlite --ha=false` | ok, 18 s. Release v3, the same one machine, its check passing |
| the machine's startup lines | `unotes: WARNING row 520 …`, then `unotes: 535 notes, 12 themes from data/notes.sqlite`. The database, not the sample |
| probes | `GET /health` 200. `HEAD /health` 200, where every earlier deploy answered 405: N38, on the deploy target. `/notes` without a session is a 303 to `/login`, a swap without one a 401, and `/login` a 200 |

### Finding 13 — the line that catches the eye names an address a browser will not open

The server's first line is the app's, `unotes on http://localhost:8080`,
and it is right. The next is the framework's, with the emoji and the word
"listening": `🔥🐝 Lightbug is listening on http://0.0.0.0:8080`. That is
the bind address, `M0_HOST`'s default. On the local check before this
deploy, the owner opened it. The browser refused it as a restricted port:
since the 2024 "0.0.0.0 Day" fix, Safari and Chrome both block `0.0.0.0` as
a destination. The app's own line was there, first, and was missed on the
first read, because the framework's line is the one that looks like the
answer.

The default bind costs a second thing. `0.0.0.0` is every interface, so a
local run with the real notes was reachable from the local network, behind
the login, until it was restarted with `--host 127.0.0.1`.

The image already sets `M0_HOST=0.0.0.0` itself, in its `ENV`. So the
binary's own default could be loopback without moving a deploy.
Candidates: `127.0.0.1` as the host's default; and the listening line
naming `base_url` beside the bind address, never `0.0.0.0` alone as a URL.

Smaller, same place: `Ready to accept connections...` is printed before
the handler's `make` runs. So a refused start reads "ready" and then
"refused". The old-export refusal did exactly that: `Ready to accept
connections...`, then `host: the handler's make raised, so this
configuration is refused: …`.

## 2026-09-30 — the third upgrade: `m0 0.3.0` → `0.4.0`

`m0 0.4.0` reached PyPI at 03:38 UTC on 2026-09-30 (framework 1.8.0, commit
`b1dca5b`), gated on the same `mojo 1.1.0`, and on the same `max-core
26.6.0` for an application that installs it; this one does not. Most of
1.8.0 is what a review of the whole tree found on 2026-09-28. Its entry for
`m0` names one change an application must act on: `Login.from_env` refuses
an unset `PREFIX_SECURE` (N43), which here is `UNOTES_SECURE`. The CHANGELOG
credits nothing in the release to this app.

The CHANGELOG is not in the wheel. It was read at the release commit in a
local checkout of mojo-http (`git show b1dca5b:CHANGELOG.md`; the wheel's
`_build_info.json` names the commit), and the two wheels were unpacked side
by side to diff the framework's source and the templates.

| step | result |
|---|---|
| `uv add --dev 'm0==0.4.0'`, the upgrading section's command | ok. It moved the pin and nothing else in `pyproject.toml`, comments included; `uv.lock` names `m0 0.4.0` from pypi.org. `mojo` did not move |
| `uv run m0 doctor` | ok, every toolchain check. The `scaffold` line named the same seven files as at the second upgrade (below). The `app` line ran the old binary: finding 14 |
| `uv run m0 test`, the app unedited | 36 of 36 |
| `uv run m0 build`, the app unedited | ok, 13.1 s, no warning. `bin/server` 1,472,528 → 1,429,104 bytes, 42 KB less: the fork's removed code |
| `./smoke.sh`, the app unedited | **FAIL**: `the server exited: unotes: UNOTES_SECURE is not set: 1 when the application is served over HTTPS (the session cookie then carries Secure), 0 over plain http such as http://localhost` |

At the first two upgrades the version alone changed nothing the app could
see, but for HEAD on the wire at the second. This one stopped the server
from starting. It was the change the CHANGELOG names first, and it arrived
as one line naming the fix. CI would have failed at the same step: its `m0
doctor` runs before anything is built, so `./smoke.sh` is the first thing
there that starts a server.

### What the upgrade asked of the app

`UNOTES_SECURE` was optional, and unset read as off. The deploy has stated
`1` in `fly.toml`'s `[env]` since the login was written; no local run ever
stated it. Now every place that starts the server states it:

- `smoke.sh` runs the server with `UNOTES_SECURE=0`, since it serves plain
  http on 127.0.0.1. A new probe gives `--doctor` the key and the password
  but no `UNOTES_SECURE`, and wants 78 and the variable's name. It asks
  `--doctor`, which starts nothing, so a regression fails the probe rather
  than serving on the run's port. Against 0.3.0's binary it exits 0.
- A new test, `test_unotes_secure_is_stated_or_the_server_does_not_start`:
  unset is refused, naming the variable; `0` is off; `1` is on. `m0`
  refuses to run outside the project's own venv, so `uvx --from m0==0.3.0`
  could not run it against the old layer. A scratch copy of the project
  pinned to 0.3.0 could, and there the test fails: "Didn't raise". That
  makes 37 tests.
- `test_the_login_policy_is_read_from_unotes_variables` cleared
  `UNOTES_SECURE` before its short-key check. That still passed, but only
  because `from_env` reads the key first, and the empty value is now a
  refusal of its own. The check now sets `1` first.
- The words: the README's command for the real notes and its paragraph on
  the variables, `deploy/README.md` (below), `fly.toml`'s comment, and the
  docstrings of `server.mojo` and `LOGIN_ENV`, which listed the variable as
  optional.

The deploy needs nothing new. The deploy entry above found the key and the
password in `fly secrets list`, and `fly.toml` states the third.

Nothing was deleted this time. In `src/`, two docstrings changed.

### Finding 14 — the upgrade's two steps do not reach the change an application must act on

The upgrading section is two steps: take the newer `m0`, then run `m0
doctor`. At 0.4.0 neither step could show N43.

- **The doctor's `app` line runs whatever `bin/server` is.** After `uv
  add`, that is the binary the OLD `m0` built. Run with the key and the
  password exported, which the README says the doctor needs, and without
  `UNOTES_SECURE`, the doctor passed every line: `ok app: 0.0.0.0:8080,
  single, 1 loops, 0 handler threads`. The same command after `m0 build`
  exits 78, naming the variable. Nothing in the first report says the
  binary predates the `m0` beside it. That is finding 8 from the inside:
  no binary knows what built it.
- **The scaffold line cannot show it.** It compares the files every
  template shares, not `smoke.sh` and not `test/`. The change a `views`
  app with a login needs is in those two, and `m0` made it only in the
  `auth` template's copies.

What did show it was the smoke's failure line, which named the fix, and
the CHANGELOG, whose entry for `m0` opens with "What an application must
act on". The CHANGELOG is not in the wheel, and `AGENTS.md` does not
mention it. Candidates: the upgrading section runs `m0 build` before `m0
doctor`, and points at the CHANGELOG's must-act list for each version
crossed; and the doctor names a `bin/server` built by another `m0`, which
finding 8's stamp would let it do.

### What the scaffold line named, and what was taken

The line named the same seven files as at the second upgrade, as finding
11 said it would, so the three-way diff was taken again. 0.3.0's and
0.4.0's scaffolds were each written with `uvx --from m0==X m0 new unotes`
into a scratch directory, and each named file was compared with both.

| file | `m0` changed it | this app had edited it | taken |
|---|---|---|---|
| `AGENTS.md` | yes: `APP_SECURE` in the login section | no | verbatim |
| `deploy/README.md` | yes: a login's variables in `docker run`, and a login's Fly secrets | yes | both, with the `UNOTES_` names |
| `deploy/fly.toml` | yes: `APP_SECURE = "1"` and a comment | yes: it already states `UNOTES_SECURE = "1"` | the comment's reasons, in the app's comment |
| `.gitignore`, `.dockerignore`, `.github/workflows/test.yml`, `deploy/Dockerfile` | no | yes | — |

Four of the seven were named for this app's edits alone, two for both, and
one, `AGENTS.md`, for `m0`'s alone. Taken, it left the line, which now
names six. `pyproject.toml`, which the doctor does not compare, is byte for
byte what 0.4.0's `m0 new unotes` writes.

The `docker run` line in `deploy/README.md` had never worked for this app:
without the key and the password the server has exited 78 since the login
was written. The template's new paragraph is the first to say what to
pass. The rendered `fly.toml` states `APP_SECURE`, because `m0 new` fills
in the app's name but not a login's prefix, so its line was not taken as
written.

### The wire, 0.3.0 against 0.4.0

Both binaries ran on loopback, side by side, on the invented sample.
0.3.0's was built from `dca6795` before the pin moved.

The pages are the same bytes. Every route and state the app answers (21
requests: signed in and out, document and fragment, 200, 204, 303, 401,
403 and 404, and a HEAD) and ten list pages (five queries, each as document
and as fragment) were compared: status line, reason phrase, headers and
body, with `Date`, the cookie's value, the CSRF token and the scan's
measured time set aside. None differed.

| check | 0.3.0 | 0.4.0 |
|---|---|---|
| a session cookie the other binary signed, with the same key | 200, the fragment | 200, the fragment |
| A23: a sign-in POST on a keep-alive connection, 35 s idle (the idle timeout is 60 s), then a GET on it | EOF: the server had closed it | 200 |
| A25: `kill -PIPE` | died, −13 (a shell's 141) | survived; `/health` 200 |
| A25: 2,000 pipelined `GET /health`, none read, then an RST 5 ms later; 100 times | **died 4 times** | died 0 times |

What this means for the deploy:

- A reader signed in on 0.3.0 stays signed in on 0.4.0, and on a rollback.
  `session.mojo` was rewritten around a token reader it now shares with
  `grant.mojo`, and the cookie did not change.
- The browser walk was not repeated, since the pages are the same bytes.
  `html.mojo`, `fragment.mojo`, `router.mojo` and `views.mojo` are
  unchanged between the wheels.
- A23 applied to this app. Its sign-in and sign-out are POSTs whose small
  bodies arrive with the headers, and 0.3.0 closed such a connection 30 s
  later, whatever it was doing. Nothing recorded above was traced to it.
- A25 applied too. Upstream's probe resets during a 300 ms view, and no
  view here is that slow, so the probe here was a burst still being
  answered when its client reset. It killed 0.3.0 four times in a hundred,
  and on macOS the whole process went with it. Whether it reached the
  Linux build the deploy runs, this entry did not measure.

### The synthetic soak's one failure, revisited

Phase A on 2026-09-21 recorded one failure it could not explain: under
`--workers 2` on macOS, a client's fresh connection was reset, and the
server logged nothing. 1.8.0 fixes two mechanisms that could produce that.

- A25 fits it worse. 0.1.0's supervisor, the one the soak ran, prints
  `[parent] worker pid=… killed by signal 13` when SIGPIPE kills a worker,
  and the entry says the server logged nothing.
- E16 fits it better. On macOS, a connection passed between workers was
  flushed in transit whenever any process on the machine closed a
  Unix-domain socket. The worker that received it read nothing and closed
  it, "so the client got an empty reply or a reset", and nothing was
  logged.

The soak was not re-run, so the failure is still unexplained. It now has a
candidate a test could check.

### What closed upstream, and what did not

None of this log's open findings closed in 0.4.0:

- 8: the binary's `--doctor` report carries its platform and no `m0` or
  framework (finding 14), and the Dockerfile template, unchanged, writes
  neither into `about.json`.
- 9: no template's shell listens for `htmx:error`.
- 10: `refuse_signed_out` is unchanged. A 401 is still pushed, and a
  sign-in still lands on `/notes`.
- 11: the upgrading section is unchanged. It still says to write only the
  NEW scaffold, and this entry needed the old one too.
- 12: the storage section still names `open` and `open_memory`, and not
  `open_readonly`.
- 13: the first lines are unchanged: `🔥🐝 Lightbug is listening on
  http://0.0.0.0:PORT`, then `Ready to accept connections...` before
  `make` runs. A refused start still reads "ready" and then "refused".

What 1.8.0 fixed that this app never found: A23 and A25, above, and G1 and
G2. A response head now refuses CR, LF and NUL on every path, and
`reply.redirect` percent-encodes a control byte. No header or redirect here
carries request data today. G2 makes a `next` taken from the query safe in
a redirect's head, which is finding 10's candidate. It does not make that
`next` local, which the candidate still has to check.

Framework source read, before editing and not after a failure: the diffs
of the two wheels' `m0_http/login.mojo`, `session.mojo` and `reply.mojo`,
`m0_host/host.mojo` and `flags.mojo`, `m0/new.py` and the templates. The
CHANGELOG named the login's change; the rest was read to find what else
this app touches.

## 2026-09-30 — the deploy, on 0.4.0

**Which traffic this is: a probe, and no reader.** A signed-out `GET
/health` every quarter second held the site across the rollout, and seven
probes without a session followed. The password is a secret this session
did not read, so a signed-in page on the deploy, and the scan's cost on its
CPU, are still owed.

The data did not move. `data/` held the copies the last deploy shipped: the
owner's `notes.sqlite` was last written on 2026-05-22, before its `VACUUM
INTO` copy of 2026-09-27, and the theme map is byte for byte its copy. So
this deploy changed the framework and nothing else. It was deployed from the
branch `m0-0.4.0` before a push, since `fly deploy` builds the working
directory, not what GitHub holds.

| step | result |
|---|---|
| `fly secrets list` | `UNOTES_KEY` and `UNOTES_PASSWORD`; `UNOTES_SECURE` comes from `fly.toml` |
| `fly deploy -c deploy/fly.toml --remote-only --build-only --push --image-label m0-0.4.0` | ok, 70 s. The builder's `uv sync --frozen` installed `m0==0.4.0` and `mojo==1.1.0`; the old-export guard passed; `built dist/ for x86-64-v2`. `about.json`: `"libs":"libsqlite3-0"`, `python: false`, app 5.21 MB, image 83.4 MB unpacked (0.3.0's: 5.32 MB and 83.5 MB). It still names no framework (finding 8) |
| `fly deploy -c deploy/fly.toml --image registry.fly.io/unotes:m0-0.4.0 --ha=false` | ok, 19 s. Release v4, the same one machine, its check passing |
| the machine's lines | SIGINT at 17:33:23 UTC, and the 0.3.0 server exited 0. At 17:33:25 the 0.4.0 server printed `unotes: WARNING row 520 …`, then `unotes: 535 notes, 12 themes from data/notes.sqlite`. It started, so `UNOTES_SECURE` reached it |
| the poller, 17:33:13 → 17:34:53 UTC | 312 requests, all answered 200. The one sent at 17:33:21 was held across the swap and answered after 5.5 s; no other took more than 0.15 s |
| probes without a session | `GET /health` 200 and `HEAD /health` 200. `/notes` is a 303 to `/login`, a swap a 401, `/login` a 200 and a wrong password a 401. `http://` is a 301 to `https://` |

A deploy is still one slow request and no failed one, as at 0.2.0. The way
back is `fly deploy -c deploy/fly.toml --image
registry.fly.io/unotes:m0-0.3.0-sqlite --ha=false`, release v3's image, and
a session signed by either version is good on the other (the wire, above).

## 2026-10-02 — the soak, re-run on 0.4.0, and the two things owed

**Which traffic this is: synthetic, then a signed-in probe of the deploy.**
The record is mojo-http's `docs/REAL_APP_VALIDATION.md`, "The application
layer", which this entry is the source of.

`scripts/soak.py` from mojo-http's `main` against `bin/server` at `21673f2`
(`m0` 0.4.0, framework 1.8.0), the real corpus, M4. The capture was taken
from the same binary one request at a time. Six bursts, four sessions, two
abandoners paced at 50 ms, a SIGTERM and restart every 40 s:

| row | seconds | verified | failures | restarts | worst drain | RSS |
|---|---|---|---|---|---|---|
| `--workers 2` | 180 | 1,748,962 | 0 | 4, exit 0 each | 3 ms | 17,296 → 17,312 kB |
| `--threads 2` | 90 | 864,732 | 0 | 2, exit 0 each | 38 ms | 23,072 → 23,072 kB |

The flags that matter: `--burst 6 --sessions 4 --bulk 0 --stream 0 --ws 0
--abandon 2 --abandon-pause 0.05 --churn-every 40`. The server ran with
`OS_ACTIVITY_MODE=disable`, since a forked worker opens SQLite after the
fork on macOS.

**Finding 15: the manifest does not pace the driver's logins.** A first
attempt left soak.py's `bulk` population on. With a login block and no
`min_interval_seconds`, it signs in as fast as it can, about 170 times a
second here, and the client ran out of local ports inside 15 s: 232,946
failures at two workers and 132,239 at two threads, every one `OSError 49`
on a connect. 668,856 and 338,161 responses were verified in those runs
and none was wrong. The instrument again, as on 2026-09-21, and the fix is
this manifest's: an interval in its login block, or `--bulk 0` as above.

The abandonment failure of 2026-09-21 did not recur in 9,722 abandonments
across the two rows. That is still not an explanation of it.

**The two things owed since the deploy on 0.4.0**, taken with the password
from `.env.local`, which is also the deploy's:

- A signed-in page on the deploy: `/notes`, `/notes/25` and `/themes` each
  200; `/notes` signed out, 303.
- The scan on its CPU, `x-scan-us`, six of each: no filter 6–9 µs (60 on
  the first request), `q=the` 164–189 (573 on the first), `q=football`
  1,227–1,517, `q=zzzzqqqq` 1,256–1,595. The figures of 0.1.0 and 0.3.0.

## 2026-10-02 — the fourth upgrade: `m0 0.4.0` → `0.5.0`, and what of it fits

`m0 0.5.0` reached PyPI on 2026-10-02 (framework 1.9.0, commit `e2a88d7`),
on the same `mojo 1.1.0`. What it adds for an application is a resource
over a table: `Views.resource`, `Connection.data_version()`, and `Cached`
with `conditional`. This app was named as the round's first user outside
the tree.

| step | result |
|---|---|
| the pin, `uv sync` | `m0==0.5.0` from pypi.org |
| `m0 doctor` | every check as on 0.4.0; `scaffold` names the six files this app edited, as before |
| `m0 build`, `m0 test`, `smoke.sh` | built, 3 of 3 files, ok; nothing to act on |
| the names 0.5.0 removed | none imported here |

**`resource`: taken.** The table's six lines for the notes, the keywords
and the themes are three, `v.resource(NOTES, list=index, show=detail)` and
its two siblings, and each row's pattern is its collection's and
`RESOURCE_ITEM`. The captures were `:id`, `:k` and `:n` and are all `:id`
now; nothing read the names. Held to the capture taken from the 0.4.0
build, under load at two workers for 30 s: 285,194 responses, 0 failures,
1,087 abandonments. The same bytes.

**Finding 16: `conditional` has nothing to say to a page that is
`no-store`.** Every page here is behind the session and leaves through
`no_store`, as `m0_http.login` advises: a private page is not one to keep.
A browser that may not store a response never sends its tag back, so the
304 has no request to answer. Taking it means changing the policy to
`private, no-cache`, which lets the reader's own browser keep the page and
ask before showing it. That is a decision about the notes, not about the
code, and it is the owner's. The layer's note says the same of
`apps/fragment_notes`; this is the second application to meet it, and the
first where the saving would be real: the list is 23 KB and a search scans
for 1.2–1.6 ms on the deploy's CPU.

**Finding 17: the clock has nothing to watch on the deploy.** The corpus
is read once in `make` into lists and never again; the image carries a copy
of the database that no one writes. `data_version` would matter only where
`serve.sh` reads the live `notes.sqlite`, to re-read the corpus when the
notes change instead of at the next restart. That is a change of shape,
every view becoming one that may write, for a file last written in May.
Not taken. The sample, a `.sql` script run into memory, has no second
connection to ask at all.

So of the three pieces this app takes one. The other two were built
against a table that changes under a public page (`apps/table_notes`), and
this is a private reader over a table that does not.

## 2026-10-02 — the deploy, on 0.5.0

**Which traffic this is: a probe, then a signed-in check.** Merged to
`main` at `5433286` and deployed from it. The image was built remotely and
pushed as `m0-0.5.0` (25 MB), then released to the same one machine,
release v5. A signed-out `GET /health` every quarter second held the site
across the rollout: 352 of 352 answered 200.

Signed in afterwards, with the password from `.env.local`: `/notes`,
`/notes/25`, `/keywords`, `/keywords/athletics`, `/themes` and `/themes/7`
each 200, the six routes `resource` now registers. The pages are still
`no-store`: the owner chose to leave the policy as it is (finding 16).
The data did not move; the image carries the copies of 2026-09-27.

## 2026-10-06 — the soak on framework 1.11.0, before `m0` 0.7.0 reached the index

**Which traffic this is: synthetic.** The record is mojo-http's
`docs/REAL_APP_VALIDATION.md`, "The application layer", which this entry
is the source of. It was run for mojo-http's 1.11.0 release: the layer's
milestone wants this soak no more than two minors behind the framework,
and the 2026-10-02 run was on 1.8.0.

**What was built.** This repository at `97b3c1c`, unchanged, in a scratch
clone whose pin moved from `m0==0.5.0` to `m0==0.7.0`: the wheel cut from
mojo-http's release branch at `3e64f2a` (framework 1.11.0), reached
through `find-links` before it was uploaded. `main` here still pins 0.5.0.
The clone was thrown away, and taking 0.7.0 from the index is an upgrade
of its own (below).

| step | result |
|---|---|
| `m0 doctor` | framework 1.11.0; `scaffold` names the same six files this app edited |
| `m0 build`, `m0 test`, `smoke.sh` | built, 3 of 3 files (16 tests), ok |

**The soak.** `scripts/soak.py` from mojo-http's release branch against
that `bin/server`, the real corpus, an M4 on macOS 27. The capture was
taken from the same binary one request at a time, and the flags were
2026-10-02's: `--burst 6 --sessions 4 --bulk 0 --stream 0 --ws 0
--abandon 2 --abandon-pause 0.05 --churn-every 40`, with
`OS_ACTIVITY_MODE=disable`. The driver is mojo-http's
`bench/soak/2026-10-06/layer_unotes.sh`.

| row | seconds | verified | failures | restarts | worst drain | RSS |
|---|---|---|---|---|---|---|
| `--workers 2` | 180 | 1,409,040 | 0 | 4, exit 0 each | 4 ms | 17,296 → 17,296 kB |
| `--threads 2` | 90 | 814,210 | 0 | 2, exit 0 each | 45 ms | 23,024 → 23,152 kB |

The two rows had 6,005 and 3,037 abandonments. 11,035 and 6,397 requests
met a restart; each was counted apart, never more than 525 ms from one.
Fewer responses were verified than on 2026-10-02 (1,748,962 and 864,732).
Another session's process held a core throughout, and the rows assert
bytes, not rate.

**Owed: the fifth upgrade, `m0 0.5.0` → `0.7.0`.** Both reached the index
on 2026-10-06, and mojo-http's CHANGELOG says what each changes for an
application. Nothing here is touched by either:

- this app serves no `StaticFiles`;
- it reads no access log;
- its `ViewState` declares none of the stream hooks or the `tick` that
  0.6.0 began calling.

The scratch build above is that upgrade's evidence, but it was not made
here, because an upgrade is this log's own entry.

## 2026-10-06 — the fifth upgrade: `m0 0.5.0` → `0.7.0`

`m0 0.7.0` (framework 1.11.0) is on PyPI, on the same `mojo 1.1.0`, and
this is the upgrade the entry above said was still to do. It skips 0.6.0:
`uv` takes the newer pin in one step, and both changelog entries were
read against this app before it moved.

| step | result |
|---|---|
| the pin, `uv sync` | `m0==0.7.0` from pypi.org; `pyproject.toml` and `uv.lock` the only files changed |
| `m0 doctor` | every toolchain check ok; `app` ok once `UNOTES_KEY`, `UNOTES_PASSWORD` and `UNOTES_SECURE` are set, and refused (78) without them, as designed; `scaffold` names the same six files this app edited |
| `m0 build`, `m0 test`, `smoke.sh` | built (15 s), 3 of 3 files (16 tests), ok |
| what 0.6.0 and 0.7.0 ask an application to change | none applies: no `ViewState` method named `tick` or `sse_*`, no `StaticFiles`, and nothing here or in `deploy/` sets or reads `M0_ACCESS_LOG` |

Neither release adds anything this app takes. 0.6.0's stamps and `Feed`
answer a table that changes, and finding 17 still holds: the corpus is
read once and the image carries a copy no one writes. 0.7.0's changes are
to static files and the access log, and this app uses neither. The soak
above was run on the same framework and stands as this build's load
evidence. It was taken from a scratch clone at `97b3c1c`, which differs
from this commit only in the pin. The deploy is still on 0.5.0.

## 2026-10-06 — the deploy, on 0.7.0

**Which traffic this is: a probe, then a signed-in check.** Pushed to
`main` at `adda4d2` and deployed from it. The data did not move: the
owner's `notes.sqlite` was last written on 2026-05-22, and the theme map
is byte for byte the copy in `data/`, so this deploy changed the framework
and nothing else.

| step | result |
|---|---|
| `fly secrets list` | `UNOTES_KEY` and `UNOTES_PASSWORD`, as before |
| `fly deploy -c deploy/fly.toml --remote-only --build-only --push --image-label m0-0.7.0` | ok, 99 s. The builder installed `m0==0.7.0` and `mojo==1.1.0`; `built dist/ for x86-64-v2`. `about.json`: `"libs":"libsqlite3-0"`, `python: false`, app 5.27 MB, image 83.5 MB unpacked; 25 MB pushed |
| `fly deploy -c deploy/fly.toml --image registry.fly.io/unotes:m0-0.7.0 --ha=false` | ok, 19 s. Release v6, the same one machine, its check passing |
| the machine's lines | SIGINT at 21:41:48 UTC, and the 0.5.0 server exited 0. At 21:41:50 the 0.7.0 server printed `unotes: WARNING row 520 …`, then `unotes: 535 notes, 12 themes from data/notes.sqlite` |
| the poller, 21:41:33 → 21:43:21 UTC | 306 signed-out `GET /health`, all answered 200. The one sent at 21:41:46 was held across the swap and answered after 7.5 s; no other took more than 0.15 s |

Signed in afterwards, with the password from `.env.local`: the login a
303 to `/notes`, then `/notes`, `/notes/25`, `/keywords`,
`/keywords/athletics`, `/themes` and `/themes/7` each 200 with the page,
in 46–67 ms. Signed out, `/notes` is a 303 to `/login` and a swap a 401.
The pages are still `no-store` (finding 16). The way back is release v5's
image, `registry.fly.io/unotes:m0-0.5.0`.

## 2026-10-10 — the sixth upgrade: `m0 0.7.0` → `0.11.0`

`m0 0.11.0` (framework 1.14.0) is on PyPI, on the same `mojo 1.1.0`. It
skips 0.8.0, 0.9.0, 0.9.1 and 0.10.0: `uv` takes the newer pin in one
step, and the four changelog entries in between (1.12.0, 1.12.1, 1.13.0,
1.14.0) were read against this app before it moved.

| step | result |
|---|---|
| the pin, `uv add --dev 'm0==0.11.0'` | from pypi.org; `pyproject.toml` and `uv.lock` the only files changed, and `mojo-gated` still `mojo 1.1.0`, so nothing else moves |
| `m0 doctor` | every toolchain check ok; `app` ok once `UNOTES_KEY`, `UNOTES_PASSWORD` and `UNOTES_SECURE` are set, and refused (78) without them, as designed. `--doctor` now runs the `port` check first (1.13.0) |
| `m0 build`, `m0 test`, `smoke.sh` | built (14 s), 3 of 3 files (37 tests: 9, 12, 16), ok. The entry above counted only the last file's 16 |
| what 1.12.0–1.14.0 ask an application to change | none applies: no import here names a fork or `m0_http` name these releases moved, renamed or removed (`server_is_tls`, `URIParseError`, `GrantKeys.keys`, the descriptor helpers, `recv`/`send`, `from_parsed`, the client and response-parser code), and nothing passes `--port 0` or `M0_PORT=0` |
| `scaffold` | named seven files, `AGENTS.md` new among them: 0.9.1 changed the template's copy. The other six are byte for byte what 0.7.0 wrote, so this app's edits to them stand |

`AGENTS.md` is taken from the 0.11.0 `views` template, as at 0.2.0, 0.3.0
and 0.4.0; this app's copy had no edits of its own. It names the two
reference pages ahead of the installed source, `--host 127.0.0.1` for a
run on this machine alone, the signatures of `reply`, `void` for a void
element, Datastar 1.0's 200-only rule, and `on_loop=True` and the bus for
streams. After it, the doctor's `scaffold` names the same six files this
app edited.

Nothing in the four releases is a feature this app takes. 1.12.0's replay
journal is for held streams, and this app has none. The rest is fixes in
the server's HTTP core, the security fixes of 1.12.1 among them (a header
value that could split a response built in Mojo, a bare-LF head that put
the parser and the loop's framing out of step), which this app takes by
rebuilding. The framework's own release record soaked this app on 1.14.0
(`docs/REAL_APP_VALIDATION.md`, "The application layer", 2026-10-09):
`45a1cdd`, the pin moved in a scratch clone to the 0.11.0 wheel cut from
the release branch ahead of its upload, 1,762,770 and 881,953 responses
verified byte for byte across two workers and two loops, with no failure.
That stands as this build's load evidence. The deploy is still on 0.7.0.
