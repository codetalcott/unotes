# unotes

A reader for a research-notes corpus — faceted, searched in memory, behind
one login. One compiled Mojo binary on the [`m0`](https://m0serve.dev/mojo/)
framework, server-rendered and swapped in place by htmx 4; no Python at run
time. Scaffolded with `uvx m0 new unotes` from the published `m0 0.1.0`;
on `m0 0.3.0` since 2026-09-27, whose `m0_http.login` is the login.
Deployed at https://unotes.fly.dev (one Fly machine; the login is the owner's).

This repository holds **no notes**. `data/sample.sql` and
`data/sample-theme-map.md` are invented, and are what the tests, `smoke.sh`
and CI read. The real input is the owner's `notes.sqlite` and
`theme-map.md`, which the app reads itself through `m0_sqlite` — the
database read-only, never written. Their copies in `data/` are gitignored,
and `smoke.sh` and CI fail if either is ever tracked.

    uv sync
    uv run m0 test                  # 36 tests, no link, no server
    ./smoke.sh                      # build, serve the sample, probe the wire

    # the real notes, read where they live:
    UNOTES_NOTES=PATH/notes.sqlite UNOTES_THEMES=PATH/ideas/theme-map.md \
    UNOTES_KEY=$(python3 -c "import secrets;print(secrets.token_hex(24))") \
    UNOTES_PASSWORD=... bin/server --port 8080

With neither variable the server reads `data/notes.sqlite` and
`data/theme-map.md` when they are there, else the sample, and prints which.
An image needs them there. `VACUUM INTO` makes the database's copy: one
consistent file in rollback-journal mode, which the image's read-only
directory can open (a `.backup` of a WAL database stays WAL, and cannot):

    rm -f data/notes.sqlite
    sqlite3 PATH/notes.sqlite "VACUUM INTO 'data/notes.sqlite'"
    cp PATH/ideas/theme-map.md data/theme-map.md

`tools/export.py` is gone, and with it the export's `data/notes.jsonl` and
`data/themes.jsonl`: delete them. While the old export is there and the
database is not, the server refuses to start rather than serve the sample
in its place; an image refuses to build while the old export is in `data/`
at all. libsqlite3 is opened at run time: macOS has one, the image
installs `libsqlite3-0`, and `M0_LIBSQLITE3` names another.

The server refuses to start (exit 78) without `UNOTES_KEY` (32+ bytes) and
`UNOTES_PASSWORD`, and `--doctor` refuses the same, so `uv run m0 doctor`
needs them once `bin/server` exists.
`UNOTES_USER` (default `reader`), `UNOTES_TTL` (seconds, default 12 h, at
most 400 days), `UNOTES_SECURE` (`1` behind TLS, or `0`; anything else is
refused) and `UNOTES_KEY_PREV` (rotation, 32+ bytes) are optional.

`src/server.mojo`'s docstring has the routes. `AGENTS.md` is the framework's
rules for an agent; `SOAK_LOG.md` is the running record of building this on
the documented path — what failed, what the docs got wrong, what was
measured. `tools/browse.py BASE_URL` walks the app in a real browser
(`uv run --no-project --with playwright python tools/browse.py …`; it signs
in as `reader` / `probe-pass`). `deploy/README.md` has the image and Fly.
