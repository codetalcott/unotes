"""The state, the views and the table that joins them.

The corpus is built once in `make` and never changed, so every view is
`add_read` and `max_workers()` is 0: any number of workers each hold the
same notes. The one write, logout, changes a cookie and no state.

There is no middleware: every view under the session opens with the same
two lines, `session_of` and an early return of `refuse`. The login itself —
the configuration, the credential check, the cookie, the CSRF check and the
refusals — is `m0_http.login`, the layer's copy of what this app and
`apps/fragment_notes` each wrote by hand (SOAK_LOG.md, the second upgrade).
What is here is the POLICY: the names, the one user, how long a session
lasts.
"""

from std.os import getenv
from std.os.path import exists
from std.time import perf_counter_ns

from lightbug_http import HTTPRequest, HTTPResponse
from m0_host.host import HostContext, ViewState

from m0_http import (
    Login,
    SessionVerdict,
    Views,
    csrf_refusal,
    form,
    no_store,
    page_or_fragment,
    refuse_signed_out,
    reply,
    vary_on_fragment_headers,
    wants_fragment,
)

from corpus import Corpus, Filter
from pages import (
    FAVICON, HEALTH, KEYWORD, KEYWORDS, LOGIN, LOGOUT, NOTE, NOTES, ROOT, THEME, THEMES,
    Site,
    render_keywords, render_list, render_login, render_missing, render_note,
    render_theme, render_themes,
)
from sources import load_corpus

comptime NOTES_ENV = "UNOTES_NOTES"
comptime THEMES_ENV = "UNOTES_THEMES"
comptime REAL_NOTES = "data/notes.sqlite"
comptime REAL_THEMES = "data/theme-map.md"
comptime SAMPLE_NOTES = "data/sample.sql"
comptime SAMPLE_THEMES = "data/sample-theme-map.md"
comptime OLD_EXPORT = "data/notes.jsonl"

comptime LOGIN_ENV = "UNOTES"
"""The login's prefix: `UNOTES_KEY` (32+ bytes), `UNOTES_PASSWORD` and
`UNOTES_SECURE` (`1` behind HTTPS, `0` over plain http) required;
`UNOTES_USER`, `UNOTES_TTL` and `UNOTES_KEY_PREV` optional."""
comptime SESSION_COOKIE = "unotes_session"
comptime DEFAULT_USER = "reader"
comptime SESSION_TTL_DEFAULT = 43200
"""Twelve hours: a working day, not a week."""


def login_from_env() raises -> Login:
    """The one user and the session's keys, or an error naming the variable
    that cannot be served. Fail closed: these notes quote unpublished
    archival work, and a server that quietly served everyone because a
    deployment forgot a variable is worse than one that did not start."""
    return Login.from_env(
        LOGIN_ENV, SESSION_COOKIE,
        default_user=DEFAULT_USER, default_ttl=SESSION_TTL_DEFAULT,
    )


struct App(ViewState):
    """What every view is handed: the notes and the one user."""

    var corpus: Corpus
    var login: Login

    def __init__(out self, var corpus: Corpus, var login: Login):
        self.corpus = corpus^
        self.login = login^

    @staticmethod
    def make(ctx: HostContext) raises -> Self:
        """Which files, in order: the ones the environment names; else the
        real database if it is there (`data/notes.sqlite`, gitignored, and
        in the image only when it was in the working directory that built
        it) with `data/theme-map.md` beside it; else the invented sample, so
        a checkout with no access to the notes still serves. A path the
        environment names and that cannot be read is an error (exit 78),
        never a quiet fall back. The line printed below says which it was.

        The one refusal among the defaults: the old export with no database
        beside it. Serving the sample there would put invented notes where
        the real ones were, with nothing but that line to say so."""
        var notes = getenv(NOTES_ENV, "")
        var themes = getenv(THEMES_ENV, "")
        if notes.byte_length() == 0:
            if exists(REAL_NOTES):
                notes = String(REAL_NOTES)
                themes = String(REAL_THEMES) if exists(REAL_THEMES) else String("")
            elif exists(OLD_EXPORT):
                raise Error(String(
                    OLD_EXPORT, " is tools/export.py's output, which unotes no",
                    " longer reads: put the database at ", REAL_NOTES, " and the",
                    " theme map at ", REAL_THEMES, " (README), and delete the export",
                ))
            else:
                notes = String(SAMPLE_NOTES)
                themes = String(SAMPLE_THEMES)
        var corpus = load_corpus(notes, themes)
        for i in range(len(corpus.warnings)):
            print(String("unotes: WARNING ", corpus.warnings[i]), flush=True)
        print(String(
            "unotes: ", len(corpus), " notes, ", len(corpus.theme_titles),
            " themes from ", notes,
        ), flush=True)
        return App(corpus^, login_from_env())

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
    return refuse_signed_out(
        req, LOGIN, render_login(String("signed out (", verdict.reason, ")"))
    )


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
    return no_store(resp^)


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
    var signed = app.login.sign_in(f.first("user"), f.first("password"))
    if not signed:
        return no_store(page_or_fragment(
            req, render_login(String("wrong user or password")), Site("sign in"), 401,
        ))
    var resp: HTTPResponse
    if wants_fragment(req):
        resp = _listed(req, app, Filter(), signed.value().session, String("notes"))
    else:
        resp = vary_on_fragment_headers(reply.redirect(303, NOTES))
    signed.value().set_cookie(resp)
    return no_store(resp^)


def logout(req: HTTPRequest, params: List[String], app: App) raises -> HTTPResponse:
    """POST /logout — expires the cookie. A write, so it carries the token."""
    var session = app.login.session_of(req)
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
    app.login.sign_out(resp)
    return no_store(resp^)


def index(req: HTTPRequest, params: List[String], app: App) raises -> HTTPResponse:
    """GET /notes — the filtered list."""
    var session = app.login.session_of(req)
    if not session.ok:
        return refuse(req, session)
    return _listed(req, app, filter_of(req), session, String("notes"))


def detail(req: HTTPRequest, params: List[String], app: App) raises -> HTTPResponse:
    """GET /notes/:id — one note."""
    var session = app.login.session_of(req)
    if not session.ok:
        return refuse(req, session)
    var id = reply.param_int(params[0])
    var i = app.corpus.find(id) if id >= 0 else -1
    if i < 0:
        return no_store(page_or_fragment(
            req, render_missing(String("no note with this id"), session.subject, session.csrf),
            Site("not found"), 404,
        ))
    return no_store(page_or_fragment(
        req, render_note(app.corpus, i, session.subject, session.csrf),
        Site(String("note ", id)),
    ))


def keywords(req: HTTPRequest, params: List[String], app: App) raises -> HTTPResponse:
    """GET /keywords — every keyword with its count."""
    var session = app.login.session_of(req)
    if not session.ok:
        return refuse(req, session)
    return no_store(page_or_fragment(
        req, render_keywords(app.corpus, session.subject, session.csrf), Site("keywords")
    ))


def keyword(req: HTTPRequest, params: List[String], app: App) raises -> HTTPResponse:
    """GET /keywords/:k — the list, filtered by one keyword. An unknown
    keyword is an empty list, not a 404: it is a filter, not a resource."""
    var session = app.login.session_of(req)
    if not session.ok:
        return refuse(req, session)
    var want = filter_of(req)
    want.keyword = params[0]
    return _listed(req, app, want, session, params[0])


def themes(req: HTTPRequest, params: List[String], app: App) raises -> HTTPResponse:
    """GET /themes — the theme map's titles."""
    var session = app.login.session_of(req)
    if not session.ok:
        return refuse(req, session)
    return no_store(page_or_fragment(
        req, render_themes(app.corpus, session.subject, session.csrf), Site("themes")
    ))


def theme(req: HTTPRequest, params: List[String], app: App) raises -> HTTPResponse:
    """GET /themes/:n — one theme and the notes it cites."""
    var session = app.login.session_of(req)
    if not session.ok:
        return refuse(req, session)
    var n = reply.param_int(params[0])
    var t = app.corpus.find_theme(n) if n >= 0 else -1
    if t < 0:
        return no_store(page_or_fragment(
            req, render_missing(String("no theme with this number"), session.subject, session.csrf),
            Site("not found"), 404,
        ))
    return no_store(page_or_fragment(
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
    # Three collections, each a list and its rows: `resource` registers
    # the pair under one pattern, and the row's pattern in pages.mojo is
    # that pattern and `RESOURCE_ITEM`. Read-only, so the other slots are
    # empty and register nothing.
    v.resource(NOTES, list=index, show=detail)
    v.resource(KEYWORDS, list=keywords, show=keyword)
    v.resource(THEMES, list=themes, show=theme)
    return v^
