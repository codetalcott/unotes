#!/bin/sh
# Serve the notes on this machine, for reading, on loopback only:
#
#     ./serve.sh [PORT]        # http://localhost:8080 unless PORT
#
# It works from any directory. What it settles, so that a run cannot get
# it wrong:
#
# - 127.0.0.1 only. The host's default is 0.0.0.0, every interface, which
#   puts the real notes on the local network behind nothing but the login
#   (SOAK_LOG, finding 13).
# - UNOTES_SECURE=0: this is plain http, and since m0 0.4.0 the server
#   refuses to start with it unstated.
# - A fresh UNOTES_KEY each run unless one is set, so a restart signs you
#   out.
# - A build first, but only when src/, pyproject.toml or uv.lock is newer
#   than bin/server.
#
# Where the notes live, and the password, come from .env.local: shell
# assignments, one a line. It is gitignored, and smoke.sh and CI fail if it
# is ever tracked, because this repository is public and never says where
# the notes are:
#
#     UNOTES_NOTES=$HOME/PATH/notes.sqlite
#     UNOTES_THEMES=$HOME/PATH/ideas/theme-map.md
#     UNOTES_PASSWORD=...
#
# Without the two paths the server reads data/notes.sqlite and
# data/theme-map.md when they are there, else the invented sample, and
# says which. The environment wins over the file, so
#
#     UNOTES_NOTES=data/sample.sql UNOTES_THEMES=data/sample-theme-map.md ./serve.sh
#
# serves the sample without an edit.
set -u

cd "$(dirname "$0")" || exit 1
PORT="${1:-8080}"

# A refusal is exit 78 and one line naming the fix, as the server's are.
refuse() {
    echo "serve: $1" >&2
    exit 78
}

if [ -f .env.local ]; then
    notes=${UNOTES_NOTES-} themes=${UNOTES_THEMES-} password=${UNOTES_PASSWORD-}
    set -a
    . ./.env.local
    set +a
    UNOTES_NOTES=${notes:-${UNOTES_NOTES-}}
    UNOTES_THEMES=${themes:-${UNOTES_THEMES-}}
    UNOTES_PASSWORD=${password:-${UNOTES_PASSWORD-}}
fi
[ -n "${UNOTES_PASSWORD-}" ] \
    || refuse "no UNOTES_PASSWORD: set it in .env.local (you sign in as ${UNOTES_USER:-reader})"

if [ ! -x bin/server ] || [ -n "$(find src pyproject.toml uv.lock -newer bin/server | head -1)" ]; then
    uv run m0 build || exit $?
fi

UNOTES_KEY=${UNOTES_KEY:-$(openssl rand -hex 32)}
UNOTES_SECURE=0
export UNOTES_NOTES UNOTES_THEMES UNOTES_PASSWORD UNOTES_KEY UNOTES_SECURE
echo "serve: sign in as ${UNOTES_USER:-reader} at http://localhost:$PORT (Ctrl-C stops it)"
exec bin/server --host 127.0.0.1 --port "$PORT"
