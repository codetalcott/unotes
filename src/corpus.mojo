"""The notes and the themes, held in memory, and the scan that filters them.

No HTTP and no I/O in this file, so every function here is reachable by
`uv run m0 test`. `sources.mojo` fills a `Corpus` from the notes database
and the theme map, once, at startup.

Search is a byte scan over a lowered copy of each note. A query comes from
a request and may not be UTF-8, so nothing here slices a `String`: the scan
reads `as_bytes()` spans and compares bytes.
"""

comptime PAGE_SIZE = 25


def _lower(s: String) -> String:
    """ASCII-lowered copy. Bytes above 0x7F pass through, so `É` does not
    match `é`; the corpus is English and the rule stays one line."""
    var src = s.as_bytes()
    var out = List[UInt8](capacity=len(src))
    for i in range(len(src)):
        var b = src[i]
        if b >= 65 and b <= 90:
            b += 32
        out.append(b)
    return String(unsafe_from_utf8=Span(out))


def contains_bytes(hay: Span[UInt8, _], needle: Span[UInt8, _]) -> Bool:
    """Whether `needle` occurs in `hay`. An empty needle matches."""
    var n = len(needle)
    var h = len(hay)
    if n == 0:
        return True
    if n > h:
        return False
    var first = needle[0]
    var last_start = h - n
    var i = 0
    while i <= last_start:
        if hay[i] == first:
            var j = 1
            while j < n and hay[i + j] == needle[j]:
                j += 1
            if j == n:
                return True
        i += 1
    return False


def _has(values: List[String], wanted: String) -> Bool:
    for i in range(len(values)):
        if values[i] == wanted:
            return True
    return False


struct Facet(Copyable, Movable):
    """One field's distinct values with how many notes carry each, sorted
    by count, then by name."""

    var values: List[String]
    var counts: List[Int]

    def __init__(out self):
        self.values = List[String]()
        self.counts = List[Int]()

    def count(mut self, value: String):
        for i in range(len(self.values)):
            if self.values[i] == value:
                self.counts[i] += 1
                return
        self.values.append(value)
        self.counts.append(1)

    def sort(mut self, by_name: Bool = False):
        # Insertion sort: the largest facet has 164 values.
        for i in range(1, len(self.values)):
            var j = i
            while j > 0 and self._before(j, j - 1, by_name):
                self.values.swap_elements(j, j - 1)
                self.counts.swap_elements(j, j - 1)
                j -= 1

    def _before(self, a: Int, b: Int, by_name: Bool) -> Bool:
        if not by_name and self.counts[a] != self.counts[b]:
            return self.counts[a] > self.counts[b]
        return self.values[a] < self.values[b]


struct Filter(Copyable, Movable):
    """What a request asked for. Empty strings mean "any"."""

    var q: String
    var era: String
    var kind: String
    var institution: String
    var keyword: String
    var commented: Bool
    var page: Int

    def __init__(out self):
        self.q = String("")
        self.era = String("")
        self.kind = String("")
        self.institution = String("")
        self.keyword = String("")
        self.commented = False
        self.page = 1

    def is_empty(self) -> Bool:
        return (
            self.q.byte_length() == 0
            and self.era.byte_length() == 0
            and self.kind.byte_length() == 0
            and self.institution.byte_length() == 0
            and self.keyword.byte_length() == 0
            and not self.commented
        )


struct Corpus(Movable, Sized):
    """535 notes as parallel lists, built once and never changed — which is
    why every view over it is `add_read` and any worker count is honest."""

    var ids: List[Int]
    var notes: List[String]
    var sources: List[String]
    var dates: List[String]
    var comments: List[String]
    var entered: List[String]
    var keywords: List[List[String]]
    var kinds: List[List[String]]
    var institutions: List[List[String]]
    var eras: List[List[String]]
    var haystacks: List[String]

    var era_facet: Facet
    var kind_facet: Facet
    var institution_facet: Facet
    var keyword_facet: Facet

    var theme_numbers: List[Int]
    var theme_titles: List[String]
    var theme_tensions: List[String]
    var theme_notes: List[List[Int]]

    var warnings: List[String]
    """What loading noticed and did not refuse, for `make` to print."""

    def __init__(out self):
        self.ids = List[Int]()
        self.notes = List[String]()
        self.sources = List[String]()
        self.dates = List[String]()
        self.comments = List[String]()
        self.entered = List[String]()
        self.keywords = List[List[String]]()
        self.kinds = List[List[String]]()
        self.institutions = List[List[String]]()
        self.eras = List[List[String]]()
        self.haystacks = List[String]()
        self.era_facet = Facet()
        self.kind_facet = Facet()
        self.institution_facet = Facet()
        self.keyword_facet = Facet()
        self.theme_numbers = List[Int]()
        self.theme_titles = List[String]()
        self.theme_tensions = List[String]()
        self.theme_notes = List[List[Int]]()
        self.warnings = List[String]()

    def __len__(self) -> Int:
        return len(self.ids)

    def add_note(
        mut self,
        id: Int,
        *,
        var note: String,
        var source: String,
        var date: String,
        var comment: String,
        var entered: String,
        var keywords: List[String],
        var kinds: List[String],
        var institutions: List[String],
        var eras: List[String],
    ):
        """One note, counted into every facet it carries."""
        var hay = String(note, "\n", source, "\n", comment)
        for i in range(len(keywords)):
            hay += "\n"
            hay += keywords[i]
            self.keyword_facet.count(keywords[i])
        for i in range(len(kinds)):
            self.kind_facet.count(kinds[i])
        for i in range(len(institutions)):
            self.institution_facet.count(institutions[i])
        for i in range(len(eras)):
            self.era_facet.count(eras[i])

        self.ids.append(id)
        self.haystacks.append(_lower(hay))
        self.notes.append(note^)
        self.sources.append(source^)
        self.comments.append(comment^)
        self.dates.append(date^)
        self.entered.append(entered^)
        self.keywords.append(keywords^)
        self.kinds.append(kinds^)
        self.institutions.append(institutions^)
        self.eras.append(eras^)

    def add_theme(mut self, n: Int, var title: String, var tension: String, var notes: List[Int]):
        """One theme; `notes` are ids already in the corpus."""
        self.theme_numbers.append(n)
        self.theme_titles.append(title^)
        self.theme_tensions.append(tension^)
        self.theme_notes.append(notes^)

    def finish(mut self):
        """Sort the facets once every note is in."""
        self.era_facet.sort(by_name=True)
        self.kind_facet.sort()
        self.institution_facet.sort()
        self.keyword_facet.sort(by_name=True)

    def find(self, id: Int) -> Int:
        """The index of note `id`, or -1."""
        for i in range(len(self.ids)):
            if self.ids[i] == id:
                return i
        return -1

    def find_theme(self, n: Int) -> Int:
        for i in range(len(self.theme_numbers)):
            if self.theme_numbers[i] == n:
                return i
        return -1

    def themes_citing(self, id: Int) -> List[Int]:
        """Indexes of the themes that cite note `id`."""
        var out = List[Int]()
        for t in range(len(self.theme_notes)):
            for j in range(len(self.theme_notes[t])):
                if self.theme_notes[t][j] == id:
                    out.append(t)
                    break
        return out^

    def select(self, want: Filter) -> List[Int]:
        """Indexes of every note `want` matches, in corpus order."""
        var needle = _lower(want.q)
        var needle_bytes = needle.as_bytes()
        var out = List[Int]()
        for i in range(len(self.ids)):
            if want.commented and self.comments[i].byte_length() == 0:
                continue
            if want.era.byte_length() > 0 and not _has(self.eras[i], want.era):
                continue
            if want.kind.byte_length() > 0 and not _has(self.kinds[i], want.kind):
                continue
            if want.institution.byte_length() > 0 and not _has(
                self.institutions[i], want.institution
            ):
                continue
            if want.keyword.byte_length() > 0 and not _has(
                self.keywords[i], want.keyword
            ):
                continue
            if len(needle_bytes) > 0 and not contains_bytes(
                self.haystacks[i].as_bytes(), needle_bytes
            ):
                continue
            out.append(i)
        return out^


def page_count(matches: Int) -> Int:
    if matches == 0:
        return 1
    return (matches + PAGE_SIZE - 1) // PAGE_SIZE
