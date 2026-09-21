#!/bin/sh
# Build, serve on a port of this run's own, probe the wire, stop by pid.
#
#     ./smoke.sh [PORT]
#
# Runs against the INVENTED sample in data/, with a key and a password of
# this run's own, so it passes on a checkout that has never seen the notes.
#
# The four habits a probe of a running server needs, written down once:
# a port nothing else is using, a wait for readiness before the first
# probe, a stop by PID (never by name: another server may be running), and
# an exit status that is the probe's, not the last command's.
set -u

PORT="${1:-$((20000 + $$ % 20000))}"
BASE="http://127.0.0.1:$PORT"
PID=""
JAR="smoke.jar"

fail() {
    echo "smoke: FAIL: $1" >&2
    [ -n "$PID" ] && kill "$PID" 2>/dev/null
    exit 1
}

# The guard. The real notes and the theme map are unpublished; git history
# is permanent, and one `git add -A` with them present publishes them.
for private in data/notes.jsonl data/themes.jsonl; do
    if git ls-files --error-unmatch "$private" >/dev/null 2>&1; then
        fail "$private is TRACKED by git. Remove it from the index and from history before anything is pushed."
    fi
done

uv run m0 build || fail "m0 build"

# Without a key and a password the server must refuse to start (exit 78).
env -u UNOTES_KEY -u UNOTES_PASSWORD bin/server --port "$PORT" >smoke.log 2>&1
code=$?
[ "$code" = 78 ] || fail "with no UNOTES_KEY the server exited $code, not 78: $(cat smoke.log)"

# The sample BY NAME: with no variable the server prefers the real export
# when one is in data/, and this probe asserts the sample's counts.
UNOTES_NOTES=data/sample-notes.jsonl UNOTES_THEMES=data/sample-themes.jsonl \
UNOTES_KEY="smoke-key-0123456789abcdef0123456789" UNOTES_PASSWORD="smoke-pass" \
    bin/server --port "$PORT" >smoke.log 2>&1 &
PID=$!

ready=""
for _ in $(seq 1 50); do
    kill -0 "$PID" 2>/dev/null || fail "the server exited: $(cat smoke.log)"
    if curl -sf --max-time 2 "$BASE/health" >/dev/null; then ready=1; break; fi
    sleep 0.1
done
[ -n "$ready" ] || fail "no /health within 5 s"

# No session: a navigation is sent to the login page, a swap gets 401
# carrying the form, and neither carries a word of the corpus.
code=$(curl -s --max-time 5 -o smoke.body -w '%{http_code}' "$BASE/notes")
[ "$code" = 303 ] || fail "GET /notes with no session answered $code, not 303"
code=$(curl -s --max-time 5 -o smoke.body -w '%{http_code}' -H 'HX-Request-Type: partial' "$BASE/notes/1")
[ "$code" = 401 ] || fail "a partial GET /notes/1 with no session answered $code, not 401"
grep -q '^<section id="unotes"' smoke.body || fail "the 401 is not the bare fragment"
grep -q 'Harrow' smoke.body && fail "a refusal carries corpus text"

# A wrong password is a 401 and sets no cookie; the right one sets it.
rm -f "$JAR"
code=$(curl -s --max-time 5 -c "$JAR" -o /dev/null -w '%{http_code}' -d 'user=reader&password=nope' "$BASE/login")
[ "$code" = 401 ] || fail "a wrong password answered $code, not 401"
grep -q unotes_session "$JAR" && fail "a wrong password set a session cookie"
code=$(curl -s --max-time 5 -c "$JAR" -o /dev/null -w '%{http_code}' -d 'user=reader&password=smoke-pass' "$BASE/login")
[ "$code" = 303 ] || fail "login answered $code, not 303"
grep -q 'HttpOnly.*unotes_session' "$JAR" || fail "login set no HttpOnly session cookie"

# Signed in: a document, the bare fragment, a filter, a note, a theme.
curl -s --max-time 5 -b "$JAR" "$BASE/notes" | grep -q '<!doctype html>' \
    || fail "GET /notes is not a document"
curl -s --max-time 5 -b "$JAR" -H 'HX-Request-Type: partial' "$BASE/notes" >smoke.body
grep -q '^<section id="unotes"' smoke.body || fail "a partial GET /notes is not the bare fragment"
grep -q '12 of 12 notes' smoke.body || fail "the list does not count the sample's 12 notes"
curl -s --max-time 5 -b "$JAR" -H 'HX-Request-Type: partial' \
    "$BASE/notes?era=1890s&institution=Harrow&q=COACH" | grep -q '1 of 12 notes' \
    || fail "era + institution + q did not narrow to one note"
curl -s --max-time 5 -b "$JAR" -H 'HX-Request-Type: partial' "$BASE/notes/12" >smoke.body
grep -q '<script>alert' smoke.body && fail "note 12's markup arrived unescaped"
grep -q '&lt;script&gt;' smoke.body || fail "note 12 is not there escaped"
curl -s --max-time 5 -b "$JAR" -H 'HX-Request-Type: partial' "$BASE/themes/1" \
    | grep -q '4 notes cited' || fail "theme 1 does not cite its four notes"

# A query that is not UTF-8 is answered, and the server is still up after it.
code=$(curl -s --max-time 5 -b "$JAR" -o /dev/null -w '%{http_code}' "$BASE/notes?q=%80%C3%28")
[ "$code" = 200 ] || fail "a non-UTF-8 query answered $code"
curl -sf --max-time 2 "$BASE/health" >/dev/null || fail "the server died on a non-UTF-8 query"

# Logout is a write: refused without the token, accepted with it.
code=$(curl -s --max-time 5 -b "$JAR" -o /dev/null -w '%{http_code}' -d '' "$BASE/logout")
[ "$code" = 403 ] || fail "logout with no token answered $code, not 403"
token=$(curl -s --max-time 5 -b "$JAR" "$BASE/notes" | sed -n 's/.*name="csrf" value="\([^"]*\)".*/\1/p' | head -1)
[ -n "$token" ] || fail "the page carries no CSRF token"
code=$(curl -s --max-time 5 -b "$JAR" -o /dev/null -w '%{http_code}' -d "csrf=$token" "$BASE/logout")
[ "$code" = 303 ] || fail "logout with the token answered $code, not 303"

kill "$PID"
wait "$PID" 2>/dev/null
rm -f smoke.log smoke.body "$JAR"
echo "smoke: ok ($BASE)"
