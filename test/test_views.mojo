"""The table, through the table the server serves: the guard on every route,
the login round trip, the list's filters, escaping, and the URLs.

No link, no socket, no server — and no real notes: the corpus is the
invented sample.
"""

from std.os import setenv
from std.testing import TestSuite, assert_equal, assert_false, assert_raises, assert_true

from lightbug_http.cookie.request_cookie_jar import RequestCookieJar
from lightbug_http.header import Header, Headers, HeaderKey
from lightbug_http.http import HTTPRequest, HTTPResponse
from lightbug_http.http.date import unix_now
from lightbug_http.io.bytes import Bytes
from lightbug_http.uri import URI

from m0_http import Login, SessionKeys, Views, issue_session, verify_session

from corpus import Filter
from pages import excerpt, list_url
from sources import load_corpus
from views import App, SESSION_COOKIE, app_urls, login_from_env

comptime KEY = "0123456789abcdef0123456789abcdef"


def _app() raises -> App:
    var keys = SessionKeys()
    keys.add(Span(String(KEY).as_bytes()))
    var login = Login(
        String("reader"), String("s3cret"), keys^, Int64(600), False, String(SESSION_COOKIE)
    )
    return App(load_corpus("data/sample.sql", "data/sample-theme-map.md"), login^)


def _cookie(app: App) raises -> String:
    return String(
        SESSION_COOKIE, "=",
        issue_session(app.login.keys, app.login.user, unix_now() + 600),
    )


def _jar(cookie: String) -> RequestCookieJar:
    """A hand-built request parses no `Cookie` header: only the server's
    parser fills `req.cookies`, so a test fills the jar itself."""
    var jar = RequestCookieJar()
    if cookie.byte_length() > 0:
        jar.add_pairs(cookie)
    return jar^


def _get(path: String, cookie: String = "", partial: Bool = False) raises -> HTTPRequest:
    var headers = Headers()
    if partial:
        headers["HX-Request-Type"] = "partial"
    return HTTPRequest(
        URI.parse(String("http://127.0.0.1", path)), headers=headers^, cookies=_jar(cookie)
    )


def _head(path: String, cookie: String = "") raises -> HTTPRequest:
    return HTTPRequest(
        URI.parse(String("http://127.0.0.1", path)), cookies=_jar(cookie), method="HEAD"
    )


def _post(path: String, body: String, cookie: String = "", partial: Bool = False) raises -> HTTPRequest:
    var headers = Headers(
        Header(HeaderKey.CONTENT_TYPE, "application/x-www-form-urlencoded")
    )
    if partial:
        headers["HX-Request-Type"] = "partial"
    return HTTPRequest(
        URI.parse(String("http://127.0.0.1", path)),
        headers=headers^, cookies=_jar(cookie), method="POST", body=Bytes(body.as_bytes()),
    )


def _body(resp: HTTPResponse) -> String:
    return String(StringSpan(unsafe_from_utf8=Span(resp.body_raw)))


def test_every_page_under_the_session_refuses_a_request_without_one() raises:
    var app = _app()
    var table = app_urls()
    var paths: List[String] = [
        "/notes", "/notes/1", "/keywords", "/keywords/chapel", "/themes", "/themes/1",
    ]
    for i in range(len(paths)):
        var nav = table.dispatch(_get(paths[i]), app)
        assert_equal(nav.status_code, 303, paths[i])
        assert_equal(nav.headers.get("location").value(), "/login")
        var swap = table.dispatch(_get(paths[i], partial=True), app)
        assert_equal(swap.status_code, 401, paths[i])
        var body = _body(swap)
        assert_true(body.startswith('<section id="unotes"'), paths[i])
        # Nothing of the corpus in a refusal.
        assert_false("Harrow" in body, paths[i])
        assert_equal(swap.headers.get("cache-control").value(), "no-store")


def test_a_forged_or_expired_cookie_is_no_session() raises:
    var app = _app()
    var table = app_urls()
    var other = SessionKeys()
    other.add(Span(String("ffffffffffffffffffffffffffffffff").as_bytes()))
    var forged = String(SESSION_COOKIE, "=", issue_session(other, "reader", unix_now() + 600))
    assert_equal(table.dispatch(_get("/notes", forged), app).status_code, 303)
    var stale = String(SESSION_COOKIE, "=", issue_session(app.login.keys, "reader", unix_now() - 1))
    assert_equal(table.dispatch(_get("/notes", stale), app).status_code, 303)


def test_login_sets_the_cookie_and_a_wrong_password_does_not() raises:
    var app = _app()
    var table = app_urls()
    var bad = table.dispatch(_post("/login", "user=reader&password=nope", partial=True), app)
    assert_equal(bad.status_code, 401)
    assert_true("wrong user or password" in _body(bad))
    var good = table.dispatch(_post("/login", "user=reader&password=s3cret"), app)
    assert_equal(good.status_code, 303)
    assert_equal(good.headers.get("location").value(), "/notes")
    var swapped = table.dispatch(_post("/login", "user=reader&password=s3cret", partial=True), app)
    assert_equal(swapped.status_code, 200)
    assert_true("12 of 12 notes" in _body(swapped))


def test_logout_needs_this_sessions_token() raises:
    var app = _app()
    var table = app_urls()
    var value = issue_session(app.login.keys, app.login.user, unix_now() + 600)
    var cookie = String(SESSION_COOKIE, "=", value)
    var session = verify_session(Span(value.as_bytes()), app.login.keys, unix_now())
    assert_equal(table.dispatch(_post("/logout", "", cookie), app).status_code, 403)
    assert_equal(table.dispatch(_post("/logout", "csrf=wrong", cookie), app).status_code, 403)
    var out = table.dispatch(_post("/logout", String("csrf=", session.csrf), cookie), app)
    assert_equal(out.status_code, 303)


def test_the_list_filters_from_the_query_and_reports_its_scan() raises:
    var app = _app()
    var table = app_urls()
    var cookie = _cookie(app)
    var all = table.dispatch(_get("/notes", cookie, partial=True), app)
    assert_true("12 of 12 notes" in _body(all))
    assert_true(Bool(all.headers.get("x-scan-us")))
    var some = _body(table.dispatch(
        _get("/notes?era=1890s&institution=Harrow&q=COACH", cookie, partial=True), app
    ))
    assert_true("1 of 12 notes" in some)
    assert_true('href="/notes/10"' in some)
    # The form comes back holding what was asked, so the view is its own state.
    assert_true('value="COACH"' in some)
    assert_true('<option value="1890s" selected>' in some)
    var none = _body(table.dispatch(_get("/notes?q=zzzz", cookie, partial=True), app))
    assert_true("nothing matches" in none)


def test_a_page_is_a_document_or_the_bare_fragment() raises:
    var app = _app()
    var table = app_urls()
    var cookie = _cookie(app)
    assert_true(_body(table.dispatch(_get("/notes/2", cookie), app)).startswith("<!doctype html>"))
    var bare = _body(table.dispatch(_get("/notes/2", cookie, partial=True), app))
    assert_true(bare.startswith('<section id="unotes"'))
    assert_true("faculty simply go along" in bare)  # the comment, set apart
    assert_true("<aside" in bare)


def test_note_text_is_escaped_wherever_it_is_rendered() raises:
    var app = _app()
    var table = app_urls()
    var cookie = _cookie(app)
    var paths: List[String] = ["/notes/12", "/notes?q=alert", "/keywords/escaping"]
    for i in range(len(paths)):
        var body = _body(table.dispatch(_get(paths[i], cookie, partial=True), app))
        assert_false("<script>alert" in body, paths[i])
        assert_true("&lt;script&gt;" in body, paths[i])
    var one = _body(table.dispatch(_get("/notes/12", cookie, partial=True), app))
    assert_false("<b>markup</b>" in one)


def test_a_missing_note_or_theme_is_a_404_fragment() raises:
    var app = _app()
    var table = app_urls()
    var cookie = _cookie(app)
    var paths: List[String] = ["/notes/999", "/notes/abc", "/themes/9"]
    for i in range(len(paths)):
        var resp = table.dispatch(_get(paths[i], cookie, partial=True), app)
        assert_equal(resp.status_code, 404, paths[i])
        assert_true('role="alert"' in _body(resp), paths[i])


def test_themes_and_keywords_link_both_ways() raises:
    var app = _app()
    var table = app_urls()
    var cookie = _cookie(app)
    var theme = _body(table.dispatch(_get("/themes/1", cookie, partial=True), app))
    assert_true("4 notes cited" in theme)
    assert_true('href="/notes/10"' in theme)
    var note = _body(table.dispatch(_get("/notes/10", cookie, partial=True), app))
    assert_true('href="/themes/1"' in note)
    assert_true('href="/keywords/private%20advancement"' in note)
    var by_keyword = _body(table.dispatch(
        _get("/keywords/private%20advancement", cookie, partial=True), app
    ))
    assert_true("2 of 12 notes" in by_keyword)


def test_a_query_that_is_not_utf8_is_answered() raises:
    var app = _app()
    var table = app_urls()
    var resp = table.dispatch(_get("/notes?q=%80%C3%28", _cookie(app), partial=True), app)
    assert_equal(resp.status_code, 200)
    assert_true("nothing matches" in _body(resp))


def test_list_url_names_only_what_is_set_and_encodes_it() raises:
    var want = Filter()
    assert_equal(list_url(want, 1), "/notes")
    want.q = String("a b&c")
    want.kind = String("Ref's")
    assert_equal(list_url(want, 3), "/notes?q=a%20b%26c&type=Ref%27s&page=3")
    var accented = Filter()
    accented.era = String("é")
    assert_equal(list_url(accented, 1), "/notes?era=%C3%A9")


def test_every_swap_moves_the_address_bar() raises:
    """Every swap here is a `get` to a view that can be reloaded, so every
    one is pushed; the two writes (sign in, sign out) are plain forms."""
    var app = _app()
    var table = app_urls()
    var cookie = _cookie(app)
    var paths: List[String] = ["/notes", "/notes/10", "/keywords", "/themes/1"]
    for i in range(len(paths)):
        var body = _body(table.dispatch(_get(paths[i], cookie, partial=True), app))
        var gets = body.count("hx-get=")
        assert_true(gets > 0, paths[i])
        assert_equal(body.count('hx-push-url="true"'), gets, paths[i])
        assert_false("hx-post=" in body, paths[i])


def test_a_get_route_answers_head_as_its_get() raises:
    """Since m0 0.3.0 (SPEC N38) an uptime check that sends HEAD no longer
    reads the app as down. The guard runs as it does for the GET."""
    var app = _app()
    var table = app_urls()
    var cookie = _cookie(app)
    var paths: List[String] = ["/notes", "/notes/10", "/keywords", "/themes/1", "/login"]
    for i in range(len(paths)):
        assert_equal(table.dispatch(_head(paths[i], cookie), app).status_code, 200, paths[i])
    assert_equal(table.dispatch(_head("/notes"), app).status_code, 303)


def test_the_login_policy_is_read_from_unotes_variables() raises:
    """The names and defaults this app has always used, now read by
    `Login.from_env`: the prefix, the cookie, `reader`, twelve hours."""
    _ = setenv("UNOTES_KEY", "0123456789abcdef0123456789abcdef", True)
    _ = setenv("UNOTES_PASSWORD", "s3cret", True)
    _ = setenv("UNOTES_USER", "", True)
    _ = setenv("UNOTES_TTL", "", True)
    _ = setenv("UNOTES_SECURE", "1", True)
    var login = login_from_env()
    assert_equal(login.user, "reader")
    assert_equal(login.ttl, Int64(43200))
    assert_equal(login.cookie, "unotes_session")
    assert_true(login.secure)
    assert_true(Bool(login.sign_in("reader", "s3cret")))
    assert_false(Bool(login.sign_in("reader", "nope")))
    # Stricter than the hand-written policy: `true` was read as off, and
    # dropped `Secure` behind TLS without a word. Now it is refused.
    _ = setenv("UNOTES_SECURE", "true", True)
    with assert_raises(contains="UNOTES_SECURE"):
        _ = login_from_env()
    _ = setenv("UNOTES_SECURE", "1", True)
    _ = setenv("UNOTES_KEY", "short", True)
    with assert_raises(contains="UNOTES_KEY"):
        _ = login_from_env()


def test_unotes_secure_is_stated_or_the_server_does_not_start() raises:
    """Since m0 0.4.0 (SPEC N43) `UNOTES_SECURE` has no default. Unset used
    to read as off, which sends the session cookie in clear on a visitor's
    first http:// request, before any redirect to HTTPS. The deploy states
    `1` (`deploy/fly.toml`); a local run, `smoke.sh` and a test state `0`."""
    _ = setenv("UNOTES_KEY", "0123456789abcdef0123456789abcdef", True)
    _ = setenv("UNOTES_PASSWORD", "s3cret", True)
    _ = setenv("UNOTES_SECURE", "", True)
    with assert_raises(contains="UNOTES_SECURE"):
        _ = login_from_env()
    _ = setenv("UNOTES_SECURE", "0", True)
    assert_false(login_from_env().secure)
    _ = setenv("UNOTES_SECURE", "1", True)
    assert_true(login_from_env().secure)


def test_an_excerpt_never_cuts_a_codepoint() raises:
    assert_equal(excerpt("short", 10), "short")
    # "é" is two bytes; a limit landing inside it backs up to before it.
    assert_equal(excerpt("abé", 3), "ab…")
    assert_equal(excerpt("abé", 4), "abé")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
