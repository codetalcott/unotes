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

`corpus.mojo` holds the notes and the scan, `auth.mojo` the login policy,
`pages.mojo` the rendering, `views.mojo` the state and the table. The input
is `tools/export.py`'s: UNOTES_NOTES and UNOTES_THEMES name the files, and
without them the invented sample in `data/` is served. UNOTES_KEY (32+
bytes) and UNOTES_PASSWORD are required; the server refuses to start
without them.

Build it:  uv run m0 build      Test it:  uv run m0 test
"""

from m0_host.flags import host_config
from m0_host.host import ViewsApp, serve

from views import App


def main() raises:
    var config = host_config()
    print(String("unotes on ", config.base_url), flush=True)
    serve[ViewsApp[App]](config)
