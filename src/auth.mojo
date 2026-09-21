"""The one user, and the session they hold.

`m0_http.session` supplies the format and the verifier; what is here is the
POLICY an application owns: who the user is, what the cookie is called, how
long a session lasts, what a request with no session is answered with.

This file is, deliberately and almost line for line, `apps/fragment_notes`'s
login from the framework's repository — SOAK_LOG.md records that, because
whether the second hand-rolled login is a copy of the first is a question
this application exists to answer.

The app is read-only, so the one write is logout, and it carries the token.
"""

from std.os import getenv

from lightbug_http import HTTPRequest, HTTPResponse
from lightbug_http.header import HeaderKey
from lightbug_http.http.date import unix_now

from m0_core import constant_time_equal, sha256

from m0_http import (
    Form,
    SessionKeys,
    SessionVerdict,
    reply,
    session_refused,
    verify_session,
)

comptime SESSION_COOKIE = "unotes_session"
comptime SESSION_TTL_DEFAULT = 43200  # twelve hours: a working day, not a week
comptime CSRF_FIELD = "csrf"
comptime CSRF_HEADER = "x-csrf-token"

comptime KEY_ENV = "UNOTES_KEY"
comptime PREV_KEY_ENV = "UNOTES_KEY_PREV"
comptime PASSWORD_ENV = "UNOTES_PASSWORD"
comptime USER_ENV = "UNOTES_USER"
comptime TTL_ENV = "UNOTES_TTL"
comptime SECURE_ENV = "UNOTES_SECURE"


struct Auth(Movable):
    """The one user, and what a session of theirs is signed with.

    The password is compared as a SHA-256 digest so the compare is over two
    fixed-length byte strings. It is NOT a password hash — no salt, no work
    factor — because the password is never stored: it is an environment
    variable, and a process that can read that needs no hash to attack.
    """

    var user: String
    var password_digest: List[UInt8]
    var keys: SessionKeys
    var ttl: Int64
    var secure: Bool

    def __init__(
        out self,
        var user: String,
        password: String,
        var keys: SessionKeys,
        ttl: Int64,
        secure: Bool,
    ):
        self.user = user^
        self.password_digest = sha256(Span(password.as_bytes()))
        self.keys = keys^
        self.ttl = ttl
        self.secure = secure

    def accepts(self, user: String, password: String) -> Bool:
        """Both compares always run, over digests, so neither the user name
        nor the password leaks its length or its first wrong byte."""
        var want_user = sha256(Span(self.user.as_bytes()))
        var have_user = sha256(Span(user.as_bytes()))
        var have_pass = sha256(Span(password.as_bytes()))
        var user_ok = constant_time_equal(Span(want_user), Span(have_user))
        var pass_ok = constant_time_equal(Span(self.password_digest), Span(have_pass))
        return user_ok and pass_ok

    @staticmethod
    def from_env() raises -> Self:
        """The configuration, or an error naming the variable that is
        missing. Fail closed: these notes quote unpublished archival work,
        and a server that quietly served everyone because a deployment
        forgot a variable is worse than one that did not start."""
        var key = getenv(KEY_ENV, "")
        if key.byte_length() < 32:
            raise Error(String(KEY_ENV, " must be at least 32 bytes: it signs the session cookie"))
        var password = getenv(PASSWORD_ENV, "")
        if password.byte_length() == 0:
            raise Error(String(PASSWORD_ENV, " is not set: it is the one user's password"))
        var keys = SessionKeys()
        keys.add(Span(key.as_bytes()))
        var previous = getenv(PREV_KEY_ENV, "")
        if previous.byte_length() > 0:
            keys.add(Span(previous.as_bytes()))
        var ttl = Int64(SESSION_TTL_DEFAULT)
        var ttl_env = getenv(TTL_ENV, "")
        if ttl_env.byte_length() > 0:
            var parsed = reply.param_int(ttl_env)
            if parsed <= 0:
                raise Error(String(TTL_ENV, " must be a positive number of seconds"))
            ttl = Int64(parsed)
        return Self(
            getenv(USER_ENV, "reader"), password, keys^, ttl,
            getenv(SECURE_ENV, "") == "1",
        )


def session_of(req: HTTPRequest, auth: Auth) -> SessionVerdict:
    """The request's session, or the reason it has none."""
    var raw = req.cookies.get(SESSION_COOKIE)
    if not raw:
        return session_refused(String("no cookie"))
    return verify_session(Span(raw.value().as_bytes()), auth.keys, unix_now())


def private(var resp: HTTPResponse) -> HTTPResponse:
    """`Cache-Control: no-store` on every answer the session decided: `Vary`
    names only the fragment headers, so a shared cache would otherwise hand
    one reader's page, or the anonymous redirect, to another."""
    resp.headers[HeaderKey.CACHE_CONTROL] = "no-store"
    return resp^


def token_matches(verdict: SessionVerdict, got: String) -> Bool:
    return constant_time_equal(Span(verdict.csrf.as_bytes()), Span(got.as_bytes()))


def csrf_refusal(
    req: HTTPRequest, body: Optional[Form], verdict: SessionVerdict, instance: String
) -> Optional[HTTPResponse]:
    """403 unless the request carries THIS session's token, in the
    `X-CSRF-Token` header or the form body — never the query string. Fails
    closed on a verdict that is not ok: a refused session's token is empty,
    and two empty strings compare equal."""
    if not verdict.ok:
        return reply.problem(
            403, String("Forbidden"), String("no session to hold a token"), instance
        )
    var sent = req.headers.get(CSRF_HEADER)
    if sent:
        if token_matches(verdict, sent.value()):
            return None
    elif body:
        var got = body.value().get(CSRF_FIELD)
        if got:
            if token_matches(verdict, got.value()):
                return None
    return reply.problem(
        403, String("Forbidden"), String("the CSRF token is missing or wrong"), instance
    )
