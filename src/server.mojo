"""`unotes` — a reader for a research-notes corpus: faceted, searched in
memory, behind one login. Server-rendered, swapped in place by htmx 4.

    GET  /                 303 to /notes
    GET  /login            the form          POST /login    sets the cookie
    POST /logout           expires it; carries the CSRF token
    GET  /notes            the list: ?q= &era= &type= &institution=
                           &keyword= &commented=1 &page=
    GET  /notes/:id        one note
    GET  /keywords         every keyword      GET /keywords/:k  the list by one
    GET  /themes           the theme map      GET /themes/:n    one theme
    GET  /health           {"status":"ok"}, answered on the loop, no session

Every page is a whole document or the bare `#unotes` fragment, decided from
the request's headers; everything but /login and /health needs the session.

`corpus.mojo` holds the notes and the scan, `pages.mojo` the rendering,
`views.mojo` the state, the login's policy and the table; the login itself
is `m0_http.login`. The input is `tools/export.py`'s: UNOTES_NOTES and
UNOTES_THEMES name the files, and without them the invented sample in
`data/` is served. UNOTES_KEY (32+ bytes) and UNOTES_PASSWORD are required;
the server refuses to start without them, and so does `--doctor`.

Build it:  uv run m0 build      Test it:  uv run m0 test
"""

from std.sys import exit

from m0_host.flags import host_config
from m0_host.host import ViewsApp, serve

from views import App, login_from_env


def main() raises:
    var config = host_config()
    # The login's configuration, read BEFORE `serve`: a missing variable is
    # then refused under `--doctor` too, which reaches no `make`. `App.make`
    # reads it again.
    try:
        _ = login_from_env()
    except e:
        print(String("unotes: ", e), flush=True)
        exit(78)
    print(String("unotes on ", config.base_url), flush=True)
    serve[ViewsApp[App]](config)
