"""The notes and the themes, held in memory, and the scan that filters them.

No HTTP in this file, so every function here is reachable by `uv run m0
test`. The input is what `tools/export.py` writes: one JSON object per
line, every value a string, multi-valued fields joined with `|`.

Search is a byte scan over a lowered copy of each note. A query comes from
a request and may not be UTF-8, so nothing here slices a `String`: the scan
reads `as_bytes()` spans and compares bytes.
"""

from m0_core import parse_json_string

comptime SEP = "|"
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


def split_values(joined: String) -> List[String]:
    """The values of a `|`-joined field; an empty field has none."""
    var out = List[String]()
    if joined.byte_length() == 0:
        return out^
    for part in joined.split(SEP):
        out.append(String(part))
    return out^


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

    def __len__(self) -> Int:
        return len(self.ids)

    def add_note_line(mut self, line: String, line_number: Int) raises:
        """One exported line. A line that is not the format is refused by
        number: a note silently missing is worse than a server not starting."""
        var id = _field(line, "id", line_number)
        var id_number: Int
        try:
            id_number = Int(id)
        except:
            raise Error(String("notes line ", line_number, ": id ", id, " is not a number"))
        var note = _field(line, "note", line_number)
        var source = _field(line, "source", line_number)
        var comment = _field(line, "comment", line_number)
        var keywords = split_values(_field(line, "keywords", line_number))
        var kinds = split_values(_field(line, "type", line_number))
        var institutions = split_values(_field(line, "institution", line_number))
        var eras = split_values(_field(line, "era", line_number))

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

        self.ids.append(id_number)
        self.haystacks.append(_lower(hay))
        self.notes.append(note^)
        self.sources.append(source^)
        self.comments.append(comment^)
        self.dates.append(_field(line, "date", line_number))
        self.entered.append(_field(line, "entered", line_number))
        self.keywords.append(keywords^)
        self.kinds.append(kinds^)
        self.institutions.append(institutions^)
        self.eras.append(eras^)

    def add_theme_line(mut self, line: String, line_number: Int) raises:
        var n = _field(line, "n", line_number)
        var cited = List[Int]()
        for part in split_values(_field(line, "notes", line_number)):
            var id: Int
            try:
                id = Int(part)
            except:
                raise Error(String("themes line ", line_number, ": note id ", part, " is not a number"))
            if self.find(id) < 0:
                raise Error(String("themes line ", line_number, ": cites note ", id, ", which is not loaded"))
            cited.append(id)
        try:
            self.theme_numbers.append(Int(n))
        except:
            raise Error(String("themes line ", line_number, ": n ", n, " is not a number"))
        self.theme_titles.append(_field(line, "title", line_number))
        self.theme_tensions.append(_field(line, "tension", line_number))
        self.theme_notes.append(cited^)

    def finish(mut self):
        """Sort the facets once every line is in."""
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


def _field(line: String, name: String, line_number: Int) raises -> String:
    var got = parse_json_string(line, name)
    if not got:
        raise Error(String("line ", line_number, ": no string field `", name, "`"))
    return got.take()


def page_count(matches: Int) -> Int:
    if matches == 0:
        return 1
    return (matches + PAGE_SIZE - 1) // PAGE_SIZE


def load_corpus(notes_path: String, themes_path: String) raises -> Corpus:
    """Both files, or an error naming the path and the line. An empty
    `themes_path` is a corpus with no themes."""
    var corpus = Corpus()
    var number = 0
    with open(notes_path, "r") as f:
        for raw in f.read().split("\n"):
            number += 1
            var line = String(raw)
            if line.byte_length() == 0:
                continue
            try:
                corpus.add_note_line(line, number)
            except e:
                raise Error(String(notes_path, ": ", e))
    if len(corpus) == 0:
        raise Error(String(notes_path, ": no notes in it"))
    if themes_path.byte_length() > 0:
        number = 0
        with open(themes_path, "r") as f:
            for raw in f.read().split("\n"):
                number += 1
                var line = String(raw)
                if line.byte_length() == 0:
                    continue
                try:
                    corpus.add_theme_line(line, number)
                except e:
                    raise Error(String(themes_path, ": ", e))
    corpus.finish()
    return corpus^
