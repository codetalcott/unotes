"""Rendering: the routes as values, the one fragment, the document around it.

Every page is the SAME fragment — `Frag(ROOT_ID)` — so every swap lands in
the same place and any URL can be opened whole or swapped in. Escaping is
named at every hole: `text(...)` for data in an element, `attr(name, v)` for
data in an attribute, a bare string only for markup this file wrote.

Every swap here is a `get` to a view that can be reloaded, so every swap is
pushed (`push=True`): a filtered list that cannot be linked to is not worth
filtering (SOAK_LOG.md, finding 3).
"""

from m0_http import (
    Fragment, Html, Htmx, PageShell, Query, RESOURCE_ITEM, attr, csrf_input, el, flag, text,
    url_for, void,
)

from corpus import Corpus, Facet, Filter, PAGE_SIZE, page_count

comptime HTMX_CDN = "https://cdn.jsdelivr.net/npm/htmx.org@4.0.0/dist/htmx.min.js"

comptime ROOT = "/"
comptime HEALTH = "/health"
comptime FAVICON = "/favicon.ico"
comptime LOGIN = "/login"
comptime LOGOUT = "/logout"
comptime NOTES = "/notes"
comptime NOTE = NOTES + RESOURCE_ITEM
comptime KEYWORDS = "/keywords"
comptime KEYWORD = KEYWORDS + RESOURCE_ITEM
comptime THEMES = "/themes"
comptime THEME = THEMES + RESOURCE_ITEM

comptime ROOT_ID = "unotes"
comptime EXCERPT_BYTES = 280

comptime Frag = Fragment[Htmx]

comptime _STYLE = """<style>
body{font-family:Georgia,serif;max-width:46rem;margin:1.5rem auto;padding:0 1rem;line-height:1.5;color:#1b1b1b}
nav{display:flex;gap:1rem;align-items:baseline;border-bottom:1px solid #ccc;padding-bottom:.5rem;margin-bottom:1rem;font-family:system-ui,sans-serif}
nav form{margin-left:auto}
form.filter{display:grid;grid-template-columns:repeat(auto-fit,minmax(10rem,1fr));gap:.5rem;font-family:system-ui,sans-serif;margin-bottom:1rem}
form.filter input[type=search]{grid-column:1/-1}
input,select,button{font:inherit;padding:.3rem}
ul.notes{list-style:none;padding:0}
ul.notes li{padding:.6rem 0;border-bottom:1px solid #eee}
.meta,.count,.pager{font-family:system-ui,sans-serif;font-size:.85rem;color:#555}
.pager{display:flex;gap:1rem;margin-top:1rem}
.note{white-space:pre-wrap}
aside.comment{border-left:3px solid #b08d57;padding:.2rem .8rem;margin:1rem 0;font-style:italic}
ul.tags{list-style:none;padding:0;display:flex;flex-wrap:wrap;gap:.4rem .8rem;font-family:system-ui,sans-serif;font-size:.9rem}
ul.facet{columns:3;list-style:none;padding:0;font-family:system-ui,sans-serif}
[role=alert]{color:#b00020;font-family:system-ui,sans-serif}
form.login{display:grid;gap:.5rem;max-width:18rem;font-family:system-ui,sans-serif}
</style>"""


struct Site(PageShell):
    """What the document knows that a fragment does not: the title."""

    var title: String

    def __init__(out self, var title: String):
        self.title = title^

    def wrap(self, fragment: String) raises -> String:
        var h = Html(2048)
        h.raw('<!doctype html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n')
        h.raw('<meta name="viewport" content="width=device-width,initial-scale=1">\n')
        h.raw('<meta name="robots" content="noindex">\n')
        h.open("title")
        h.text(String(self.title, " · U Notes"))
        h.close("title")
        h.raw("\n")
        h.open("script")
        h.attr("src", HTMX_CDN)
        h.close("script")
        h.raw("\n")
        h.raw(_STYLE)
        h.raw("\n</head>\n<body>\n<main>\n")
        h.raw(fragment)
        h.raw("\n</main>\n</body>\n</html>\n")
        return h^.finish()


# --- URLs ----------------------------------------------------------------------


def list_url(want: Filter, page: Int) raises -> String:
    """The list's URL for `want` at `page`: only what is set (`Query.add`
    skips an empty value), in one order, so one view has one address."""
    var q = Query()
    q.add("q", want.q)
    q.add("era", want.era)
    q.add("type", want.kind)
    q.add("institution", want.institution)
    q.add("keyword", want.keyword)
    if want.commented:
        q.add("commented", "1")
    if page > 1:
        q.add("page", String(page))
    return q.on(url_for(NOTES))


def excerpt(s: String, limit: Int) -> String:
    """The first `limit` bytes of `s`, cut back to a codepoint boundary, with
    an ellipsis if anything was cut. Never a `[byte=a:b]` slice."""
    var bytes = s.as_bytes()
    if len(bytes) <= limit:
        return s
    var k = limit
    while k > 0 and (bytes[k] & 0xC0) == 0x80:
        k -= 1
    return String(String(unsafe_from_utf8=bytes[:k]), "…")


# --- pieces --------------------------------------------------------------------


def _link(f: Frag, url: String, label: String) raises -> String:
    """A link that swaps the fragment AND moves the address bar, and is a
    plain link without JavaScript."""
    return f.el("a", "get", url, attr("href", url), text(label), push=True)


def _chrome(f: Frag, user: String, csrf: String) raises -> String:
    """The navigation every signed-in page carries, and the one write."""
    return el("nav", "",
        _link(f, url_for(NOTES), "Notes"),
        _link(f, url_for(KEYWORDS), "Keywords"),
        _link(f, url_for(THEMES), "Themes"),
        # A PLAIN form, not a swap: signing out changes who the reader is, and
        # the address bar has to move with it (303 to /login). A swap left
        # the login form under the list's URL (SOAK_LOG.md, finding 4).
        el("form", attr("method", "post") + attr("action", url_for(LOGOUT)),
            csrf_input(csrf),
            el("button", "", text(String("Sign out ", user))),
        ),
    )


def _select(name: String, label: String, facet: Facet, current: String) raises -> String:
    var options = el("option", attr("value", ""), text(String("any ", label)))
    for i in range(len(facet.values)):
        var attrs = attr("value", facet.values[i])
        if facet.values[i] == current:
            attrs += flag("selected")
        options += el(
            "option", attrs,
            text(String(excerpt(facet.values[i], 40), " (", facet.counts[i], ")")),
        )
    return el("select", attr("name", name) + attr("aria-label", label), options)


def _tags(f: Frag, corpus: Corpus, i: Int) raises -> String:
    """A note's facets as links to the list filtered by each."""
    var items = String()
    for j in range(len(corpus.eras[i])):
        var want = Filter()
        want.era = corpus.eras[i][j]
        items += el("li", "", _link(f, list_url(want, 1), corpus.eras[i][j]))
    for j in range(len(corpus.institutions[i])):
        var want = Filter()
        want.institution = corpus.institutions[i][j]
        items += el("li", "", _link(f, list_url(want, 1), corpus.institutions[i][j]))
    for j in range(len(corpus.kinds[i])):
        var want = Filter()
        want.kind = corpus.kinds[i][j]
        items += el("li", "", _link(f, list_url(want, 1), excerpt(corpus.kinds[i][j], 40)))
    return items^


def _row(f: Frag, corpus: Corpus, i: Int) raises -> String:
    var url = url_for(NOTE, String(corpus.ids[i]))
    var meta = String("#", corpus.ids[i])
    if corpus.sources[i].byte_length() > 0:
        meta += String(" · ", excerpt(corpus.sources[i], 90))
    if corpus.dates[i].byte_length() > 0:
        meta += String(" · ", corpus.dates[i])
    if corpus.comments[i].byte_length() > 0:
        meta += " · commented"
    return el("li", "",
        el("div", attr("class", "meta"), text(meta)),
        el("div", "", _link(f, url, excerpt(corpus.notes[i], EXCERPT_BYTES))),
    )


def _rows(f: Frag, corpus: Corpus, indexes: List[Int], first: Int, last: Int) raises -> String:
    var rows = String()
    for k in range(first, last):
        rows += _row(f, corpus, indexes[k])
    return el("ul", attr("class", "notes"), rows)


# --- pages ---------------------------------------------------------------------


def render_login(message: String) raises -> String:
    var f = Frag(ROOT_ID)
    f.raw(el("h1", "", text("U Notes")))
    if message.byte_length() > 0:
        f.raw(el("p", attr("role", "alert"), text(message)))
    # Plain, for the reason logout is: the answer is a 303 to the list.
    f.raw(el("form", attr("method", "post") + attr("action", url_for(LOGIN)) + attr("class", "login"),
        void("input", attr("name", "user") + attr("placeholder", "user") + attr("autocomplete", "username")),
        void("input", attr("name", "password") + attr("type", "password")
            + attr("placeholder", "password") + attr("autocomplete", "current-password")),
        el("button", "", "Sign in"),
    ))
    return f^.finish()


def render_list(
    corpus: Corpus, want: Filter, matches: List[Int], scan_us: Int,
    user: String, csrf: String,
) raises -> String:
    """The list: the filter form, the count and what the scan cost, one page
    of rows, the pager."""
    var f = Frag(ROOT_ID)
    f.raw(_chrome(f, user, csrf))
    var commented = attr("type", "checkbox") + attr("name", "commented") + attr("value", "1")
    if want.commented:
        commented += flag("checked")
    f.raw(f.el("form", "get", url_for(NOTES), attr("class", "filter"),
        void("input", attr("type", "search") + attr("name", "q") + attr("value", want.q)
            + attr("placeholder", "search notes, sources, keywords, comments")),
        _select("era", "era", corpus.era_facet, want.era),
        _select("institution", "institution", corpus.institution_facet, want.institution),
        _select("type", "type", corpus.kind_facet, want.kind),
        _select("keyword", "keyword", corpus.keyword_facet, want.keyword),
        el("label", "", void("input", commented), " has a comment"),
        el("button", "", "Filter"),
        push=True,
    ))
    var pages = page_count(len(matches))
    var page = want.page
    if page < 1:
        page = 1
    if page > pages:
        page = pages
    f.raw(el("p", attr("class", "count"), text(String(
        len(matches), " of ", len(corpus), " notes · page ", page, " of ", pages,
        " · scanned in ", scan_us, " µs",
    ))))
    var first = (page - 1) * PAGE_SIZE
    var last = first + PAGE_SIZE
    if last > len(matches):
        last = len(matches)
    if len(matches) == 0:
        f.raw(el("p", "", text("nothing matches")))
    else:
        f.raw(_rows(f, corpus, matches, first, last))
    var pager = String()
    if page > 1:
        pager += _link(f, list_url(want, page - 1), "← previous")
    if page < pages:
        pager += _link(f, list_url(want, page + 1), "next →")
    if pager.byte_length() > 0:
        f.raw(el("div", attr("class", "pager"), pager))
    return f^.finish()


def render_note(corpus: Corpus, i: Int, user: String, csrf: String) raises -> String:
    var f = Frag(ROOT_ID)
    f.raw(_chrome(f, user, csrf))
    f.raw(el("h1", "", text(String("Note ", corpus.ids[i]))))
    var meta = String()
    if corpus.sources[i].byte_length() > 0:
        meta += corpus.sources[i]
    if corpus.dates[i].byte_length() > 0:
        meta += String(" · ", corpus.dates[i])
    if meta.byte_length() > 0:
        f.raw(el("p", attr("class", "meta"), text(meta)))
    f.raw(el("div", attr("class", "note"), text(corpus.notes[i])))
    if corpus.comments[i].byte_length() > 0:
        f.raw(el("aside", attr("class", "comment"), text(corpus.comments[i])))
    var tags = _tags(f, corpus, i)
    for j in range(len(corpus.keywords[i])):
        var k = corpus.keywords[i][j]
        tags += el("li", "", _link(f, url_for(KEYWORD, k), k))
    if tags.byte_length() > 0:
        f.raw(el("ul", attr("class", "tags"), tags))
    var citing = corpus.themes_citing(corpus.ids[i])
    if len(citing) > 0:
        var themes = String()
        for j in range(len(citing)):
            var t = citing[j]
            themes += el("li", "", _link(
                f, url_for(THEME, String(corpus.theme_numbers[t])), corpus.theme_titles[t]
            ))
        f.raw(el("h2", "", text("In themes")))
        f.raw(el("ul", "", themes))
    if corpus.entered[i].byte_length() > 0:
        f.raw(el("p", attr("class", "meta"), text(String("entered ", corpus.entered[i]))))
    return f^.finish()


def render_keywords(corpus: Corpus, user: String, csrf: String) raises -> String:
    var f = Frag(ROOT_ID)
    f.raw(_chrome(f, user, csrf))
    f.raw(el("h1", "", text(String(len(corpus.keyword_facet.values), " keywords"))))
    var items = String()
    for i in range(len(corpus.keyword_facet.values)):
        var k = corpus.keyword_facet.values[i]
        items += el("li", "",
            _link(f, url_for(KEYWORD, k), k),
            text(String(" ", corpus.keyword_facet.counts[i])),
        )
    f.raw(el("ul", attr("class", "facet"), items))
    return f^.finish()


def render_themes(corpus: Corpus, user: String, csrf: String) raises -> String:
    var f = Frag(ROOT_ID)
    f.raw(_chrome(f, user, csrf))
    f.raw(el("h1", "", text("Themes")))
    if len(corpus.theme_titles) == 0:
        f.raw(el("p", "", text("no theme map is loaded")))
    var items = String()
    for t in range(len(corpus.theme_titles)):
        items += el("li", "",
            _link(f, url_for(THEME, String(corpus.theme_numbers[t])), corpus.theme_titles[t]),
            el("span", attr("class", "meta"),
                text(String(" · ", len(corpus.theme_notes[t]), " notes"))),
        )
    f.raw(el("ol", "", items))
    return f^.finish()


def render_theme(corpus: Corpus, t: Int, user: String, csrf: String) raises -> String:
    var f = Frag(ROOT_ID)
    f.raw(_chrome(f, user, csrf))
    f.raw(el("h1", "", text(String(corpus.theme_numbers[t], ". ", corpus.theme_titles[t]))))
    f.raw(el("p", "", text(corpus.theme_tensions[t])))
    var indexes = List[Int]()
    for j in range(len(corpus.theme_notes[t])):
        indexes.append(corpus.find(corpus.theme_notes[t][j]))
    f.raw(el("p", attr("class", "count"), text(String(len(indexes), " notes cited"))))
    f.raw(_rows(f, corpus, indexes, 0, len(indexes)))
    return f^.finish()


def render_missing(what: String, user: String, csrf: String) raises -> String:
    """A 404 a person may see is the fragment too."""
    var f = Frag(ROOT_ID)
    f.raw(_chrome(f, user, csrf))
    f.raw(el("p", attr("role", "alert"), text(what)))
    return f^.finish()
