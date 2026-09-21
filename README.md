# unotes

A reader for a research-notes corpus — faceted, searched in memory, behind
one login. One compiled Mojo binary on the [`m0`](https://m0serve.dev/mojo/)
framework, server-rendered and swapped in place by htmx 4; no Python at run
time. Scaffolded with `uvx m0 new unotes` from the published `m0 0.1.0`.

This repository holds **no notes**. `data/sample-*.jsonl` is invented and is
what the tests, `smoke.sh` and CI read. The real corpus is exported into
`data/notes.jsonl` and `data/themes.jsonl`, both gitignored; `smoke.sh` and
CI fail if either is ever tracked.

    uv sync
    uv run m0 test                  # 22 tests, no link, no server
    ./smoke.sh                      # build, serve the sample, probe the wire

    # with the real database (stdlib Python; the app never opens SQLite):
    python3 tools/export.py PATH/notes.sqlite PATH/theme-map.md

    UNOTES_KEY=$(python3 -c "import secrets;print(secrets.token_hex(24))") \
    UNOTES_PASSWORD=... bin/server --port 8080

The server prefers `data/notes.jsonl` when it exists, else the sample, and
prints which; `UNOTES_NOTES`/`UNOTES_THEMES` name other files. It refuses to
start (exit 78) without `UNOTES_KEY` (32+ bytes) and `UNOTES_PASSWORD`.
`UNOTES_USER` (default `reader`), `UNOTES_TTL` (seconds, default 12 h),
`UNOTES_SECURE=1` (behind TLS) and `UNOTES_KEY_PREV` (rotation) are optional.

`src/server.mojo`'s docstring has the routes. `AGENTS.md` is the framework's
rules for an agent; `SOAK_LOG.md` is the running record of building this on
the documented path — what failed, what the docs got wrong, what was
measured. `tools/browse.py BASE_URL` walks the app in a real browser
(`uv run --no-project --with playwright python tools/browse.py …`; it signs
in as `reader` / `probe-pass`). `deploy/README.md` has the image and Fly.
