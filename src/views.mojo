"""The state, the views and the table that joins them.

The corpus is built once in `make` and never changed, so every view is
`add_read` and `max_workers()` is 0: any number of workers each hold the
same notes. The one write, logout, changes a cookie and no state.

There is no middleware: every view under the session opens with the same
two lines, `session_of` and an early return of `refuse`.
"""

from std.os import getenv
from std.os.path import exists
from std.time import perf_counter_ns

from lightbug_http import HTTPRequest, HTTPResponse
from lightbug_http.http.date import unix_now
from m0_host.host import HostContext, ViewState

from m0_http import (
    SessionVerdict,
    Views,
    form,
    issue_session,
    page_or_fragment,
    reply,
    session_cookie_line,
    vary_on_fragment_headers,
    verify_session,
    wants_fragment,
)

from auth import Auth, SESSION_COOKIE, csrf_refusal, private, session_of
from corpus import Corpus, Filter, load_corpus
from pages import (
    FAVICON, HEALTH, KEYWORD, KEYWORDS, LOGIN, LOGOUT, NOTE, NOTES, ROOT, THEME, THEMES,
    Site,
    render_keywords, render_list, render_login, render_missing, render_note,
    render_theme, render_themes,
)

comptime NOTES_ENV = "UNOTES_NOTES"
comptime THEMES_ENV = "UNOTES_THEMES"
comptime REAL_NOTES = "data/notes.jsonl"
comptime REAL_THEMES = "data/themes.jsonl"
comptime SAMPLE_NOTES = "data/sample-notes.jsonl"
comptime SAMPLE_THEMES = "data/sample-themes.jsonl"


struct App(ViewState):
    """What every view is handed: the notes and the one user."""

    var corpus: Corpus
    var auth: Auth

    def __init__(out self, var corpus: Corpus, var auth: Auth):
        self.corpus = corpus^
        self.auth = auth^

    @staticmethod
    def make(ctx: HostContext) raises -> Self:
        """Which files, in order: the ones the environment names; else the
        real export if it is there (`data/notes.jsonl`, gitignored, and in
        the image only when it was in the working directory that built it);
        else the invented sample, so a checkout with no access to the notes
        still serves. A path the environment names and that cannot be read
        is an error (exit 78), never a quiet fall back. The line printed
        below says which it was."""
        var notes = getenv(NOTES_ENV, "")
        var themes = getenv(THEMES_ENV, "")
        if notes.byte_length() == 0:
            if exists(REAL_NOTES):
                notes = String(REAL_NOTES)
                themes = String(REAL_THEMES) if exists(REAL_THEMES) else String("")
            else:
                notes = String(SAMPLE_NOTES)
                themes = String(SAMPLE_THEMES)
        var corpus = load_corpus(notes, themes)
        print(String(
            "unotes: ", len(corpus), " notes, ", len(corpus.theme_titles),
            " themes from ", notes,
        ), flush=True)
        return App(corpus^, Auth.from_env())

    @staticmethod
    def urls() raises -> Views[Self]:
        return app_urls()

    @staticmethod
    def max_workers() -> Int:
        return 0


# --- the guard -----------------------------------------------------------------


def refuse(req: HTTPRequest, verdict: SessionVerdict) raises -> HTTPResponse:
    """What a request with no usable session gets. A navigation is sent to
    the login page; a swap gets 401 carrying the form as the fragment,
    because a redirect a swap follows would put the login page inside the
    list with no way back."""
    if wants_fragment(req):
        return private(page_or_fragment(
            req, render_login(String("signed out (", verdict.reason, ")")),
            Site("sign in"), 401,
        ))
    return private(vary_on_fragment_headers(reply.redirect(303, LOGIN)))


def filter_of(req: HTTPRequest) -> Filter:
    """The request's query as a `Filter`. Unknown keys are ignored; a page
    that is not a number is page 1."""
    var want = Filter()
    want.q = req.uri.queries.get("q", "")
    want.era = req.uri.queries.get("era", "")
    want.kind = req.uri.queries.get("type", "")
    want.institution = req.uri.queries.get("institution", "")
    want.keyword = req.uri.queries.get("keyword", "")
    want.commented = req.uri.queries.get("commented", "") == "1"
    var page = reply.param_int(req.uri.queries.get("page", "1"))
    want.page = page if page > 0 else 1
    return want^


def _listed(
    req: HTTPRequest, app: App, want: Filter, session: SessionVerdict, title: String
) raises -> HTTPResponse:
    """Scan, time the scan, render. The cost is in the page and in a header,
    because "is the in-memory scan fast enough" is this app's measured claim."""
    var started = perf_counter_ns()
    var matches = app.corpus.select(want)
    var scan_us = Int((perf_counter_ns() - started) // 1000)
    var resp = page_or_fragment(
        req,
        render_list(app.corpus, want, matches, scan_us, session.subject, session.csrf),
        Site(title),
    )
    resp.headers["x-scan-us"] = String(scan_us)
    return private(resp^)


# --- views ---------------------------------------------------------------------


def login_form(req: HTTPRequest, params: List[String], app: App) raises -> HTTPResponse:
    """GET /login — the one page outside the session."""
    return page_or_fragment(req, render_login(String("")), Site("sign in"))


def login(req: HTTPRequest, params: List[String], app: App) raises -> HTTPResponse:
    """POST /login — `user` and `password`; sets the session cookie."""
    var maybe = form(req)
    if not maybe:
        return reply.problem(
            400, "Invalid Login",
            "the request body must be application/x-www-form-urlencoded", LOGIN,
        )
    var f = maybe.take()
    if not app.auth.accepts(f.first("user"), f.first("password")):
        return private(page_or_fragment(
            req, render_login(String("wrong user or password")), Site("sign in"), 401,
        ))
    var value = issue_session(app.auth.keys, app.auth.user, unix_now() + app.auth.ttl)
    var resp: HTTPResponse
    if wants_fragment(req):
        var session = verify_session(Span(value.as_bytes()), app.auth.keys, unix_now())
        resp = _listed(req, app, Filter(), session, String("notes"))
    else:
        resp = vary_on_fragment_headers(reply.redirect(303, NOTES))
    resp.cookies.add_raw(
        session_cookie_line(SESSION_COOKIE, value, app.auth.ttl, app.auth.secure)
    )
    return private(resp^)


def logout(req: HTTPRequest, params: List[String], app: App) raises -> HTTPResponse:
    """POST /logout — expires the cookie. A write, so it carries the token."""
    var session = session_of(req, app.auth)
    if not session.ok:
        return refuse(req, session)
    var refused = csrf_refusal(req, form(req), session, LOGOUT)
    if refused:
        return refused.take()
    var resp: HTTPResponse
    if wants_fragment(req):
        resp = page_or_fragment(req, render_login(String("signed out")), Site("sign in"))
    else:
        resp = vary_on_fragment_headers(reply.redirect(303, LOGIN))
    resp.cookies.add_raw(
        session_cookie_line(SESSION_COOKIE, String(""), Int64(0), app.auth.secure)
    )
    return private(resp^)


def index(req: HTTPRequest, params: List[String], app: App) raises -> HTTPResponse:
    """GET /notes — the filtered list."""
    var session = session_of(req, app.auth)
    if not session.ok:
        return refuse(req, session)
    return _listed(req, app, filter_of(req), session, String("notes"))


def detail(req: HTTPRequest, params: List[String], app: App) raises -> HTTPResponse:
    """GET /notes/:id — one note."""
    var session = session_of(req, app.auth)
    if not session.ok:
        return refuse(req, session)
    var id = reply.param_int(params[0])
    var i = app.corpus.find(id) if id >= 0 else -1
    if i < 0:
        return private(page_or_fragment(
            req, render_missing(String("no note with this id"), session.subject, session.csrf),
            Site("not found"), 404,
        ))
    return private(page_or_fragment(
        req, render_note(app.corpus, i, session.subject, session.csrf),
        Site(String("note ", id)),
    ))


def keywords(req: HTTPRequest, params: List[String], app: App) raises -> HTTPResponse:
    """GET /keywords — every keyword with its count."""
    var session = session_of(req, app.auth)
    if not session.ok:
        return refuse(req, session)
    return private(page_or_fragment(
        req, render_keywords(app.corpus, session.subject, session.csrf), Site("keywords")
    ))


def keyword(req: HTTPRequest, params: List[String], app: App) raises -> HTTPResponse:
    """GET /keywords/:k — the list, filtered by one keyword. An unknown
    keyword is an empty list, not a 404: it is a filter, not a resource."""
    var session = session_of(req, app.auth)
    if not session.ok:
        return refuse(req, session)
    var want = filter_of(req)
    want.keyword = params[0]
    return _listed(req, app, want, session, params[0])


def themes(req: HTTPRequest, params: List[String], app: App) raises -> HTTPResponse:
    """GET /themes — the theme map's titles."""
    var session = session_of(req, app.auth)
    if not session.ok:
        return refuse(req, session)
    return private(page_or_fragment(
        req, render_themes(app.corpus, session.subject, session.csrf), Site("themes")
    ))


def theme(req: HTTPRequest, params: List[String], app: App) raises -> HTTPResponse:
    """GET /themes/:n — one theme and the notes it cites."""
    var session = session_of(req, app.auth)
    if not session.ok:
        return refuse(req, session)
    var n = reply.param_int(params[0])
    var t = app.corpus.find_theme(n) if n >= 0 else -1
    if t < 0:
        return private(page_or_fragment(
            req, render_missing(String("no theme with this number"), session.subject, session.csrf),
            Site("not found"), 404,
        ))
    return private(page_or_fragment(
        req, render_theme(app.corpus, t, session.subject, session.csrf),
        Site(app.corpus.theme_titles[t]),
    ))


def root(req: HTTPRequest, params: List[String]) -> HTTPResponse:
    return reply.redirect(303, NOTES)


def health(req: HTTPRequest, params: List[String]) -> HTTPResponse:
    return reply.json(200, "OK", '{"status":"ok"}')


def favicon(req: HTTPRequest, params: List[String]) -> HTTPResponse:
    """No icon, said once: every browser asks, and a 404 per page is noise."""
    return reply.no_content()


def app_urls() raises -> Views[App]:
    """The whole URL-to-view mapping. Everything is a read: the corpus never
    changes, and login and logout change a cookie, not the state."""
    var v = Views[App]()
    v.add_loop("GET", HEALTH, health)
    v.add_loop("GET", ROOT, root)
    v.add_loop("GET", FAVICON, favicon)
    v.add_read("GET", LOGIN, login_form)
    v.add_read("POST", LOGIN, login)
    v.add_read("POST", LOGOUT, logout)
    v.add_read("GET", NOTES, index)
    v.add_read("GET", NOTE, detail)
    v.add_read("GET", KEYWORDS, keywords)
    v.add_read("GET", KEYWORD, keyword)
    v.add_read("GET", THEMES, themes)
    v.add_read("GET", THEME, theme)
    return v^
