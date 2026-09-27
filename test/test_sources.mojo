"""Reading the sources: Python's whitespace, FileMaker's repeating values,
the entered date in every shape the notes hold, the theme map's
citations, and every refusal. Each rule is `tools/export.py`'s, and the
equivalence with it is recorded in SOAK_LOG.md.

No real notes: the invented sample, and data written here.
"""

from std.os.path import exists
from std.testing import TestSuite, assert_equal, assert_false, assert_raises, assert_true

from m0_sqlite import open_memory

from corpus import Corpus
from sources import (
    comment_of,
    entered_date,
    load_corpus,
    open_notes,
    read_notes,
    read_theme_map,
    repeating,
    strip_space,
)

comptime NOTES = "data/sample.sql"
comptime THEMES = "data/sample-theme-map.md"

comptime SCHEMA = """
CREATE TABLE notes (row_id INTEGER PRIMARY KEY, note TEXT, source TEXT,
    date TEXT, type TEXT, institution TEXT, era TEXT,
    field_6 TEXT, field_7 TEXT, field_13 TEXT);
CREATE TABLE keyword (id INTEGER PRIMARY KEY, term TEXT UNIQUE);
CREATE TABLE note_keyword (note_id INTEGER, keyword_id INTEGER);
"""


def _bytes(var values: List[UInt8]) -> String:
    """Characters a literal would hide: named by their UTF-8 bytes."""
    return String(unsafe_from_utf8=Span(values))


def _same(got: List[String], want: List[String]) raises:
    assert_equal(len(got), len(want))
    for i in range(len(want)):
        assert_equal(got[i], want[i])


def test_strip_is_pythons() raises:
    var nbsp = _bytes([UInt8(0xC2), UInt8(0xA0)])
    var ideographic = _bytes([UInt8(0xE3), UInt8(0x80), UInt8(0x80)])
    var line_sep = _bytes([UInt8(0xE2), UInt8(0x80), UInt8(0xA8)])
    var zero_width = _bytes([UInt8(0xE2), UInt8(0x80), UInt8(0x8B)])
    var unit_sep = _bytes([UInt8(0x1F)])
    assert_equal(strip_space(" \t a b \r\n"), "a b")
    assert_equal(strip_space(String(nbsp, "a b", ideographic, line_sep)), "a b")
    assert_equal(strip_space(String(unit_sep, "a", unit_sep)), "a")
    # U+200B is not whitespace to Python, so it stays, and so does
    # everything behind it.
    assert_equal(strip_space(String("a", zero_width, nbsp)), String("a", zero_width))
    assert_equal(strip_space(String(nbsp, " ")), "")
    assert_equal(strip_space(""), "")


def test_repeating_values_split_as_filemaker_joined_them() raises:
    var vt = _bytes([UInt8(11)])
    var ff = _bytes([UInt8(12)])
    _same(repeating("Students\nPress"), ["Students", "Press"])
    _same(repeating(String(" 1990s \r\n", vt, vt, " 1960s")), ["1990s", "1960s"])
    _same(repeating("one value"), ["one value"])
    # A form feed is whitespace, not a separator.
    _same(repeating(String("a", ff, "b")), [String("a", ff, "b")])
    assert_equal(len(repeating("")), 0)
    assert_equal(len(repeating(String("\n", vt, " \r"))), 0)


def test_entered_dates_in_every_shape_the_notes_hold() raises:
    var w = List[String]()
    assert_equal(entered_date(1, "7/25/95", "", w), "1995-07-25")
    assert_equal(entered_date(1, " 8/2/1995 ", "", w), "1995-08-02")
    assert_equal(entered_date(1, "04/27/1999", "", w), "1999-04-27")
    assert_equal(entered_date(1, "3/7/01", "", w), "2001-03-07")
    assert_equal(entered_date(1, "", "3701", w), "2001-03-07")
    assert_equal(entered_date(1, "", "72595", w), "1995-07-25")
    assert_equal(entered_date(1, "", "021197", w), "1997-02-11")
    # The slashed form wins, even over a squeezed one that reads two ways.
    assert_equal(entered_date(1, "11/6/95", "11695", w), "1995-11-06")
    assert_equal(entered_date(1, "", "", w), "")
    assert_equal(len(w), 0)


def test_a_typo_in_a_slashed_date_is_left_blank_and_reported() raises:
    var w = List[String]()
    assert_equal(entered_date(520, "8/1/999", "", w), "")
    assert_equal(len(w), 1)
    assert_true("row 520" in w[0])
    assert_true("8/1/999" in w[0])
    # With a squeezed twin, the twin is the date and nothing is reported.
    assert_equal(entered_date(520, "8/1/999", "80199", w), "1999-08-01")
    assert_equal(len(w), 1)


def test_a_date_that_reads_two_ways_or_none_is_refused_by_row() raises:
    var w = List[String]()
    with assert_raises(contains="row 9: squeezed date '12600' is ambiguous"):
        _ = entered_date(9, "", "12600", w)
    with assert_raises(contains="neither 199x nor 200x"):
        _ = entered_date(9, "", "5249", w)
    with assert_raises(contains="not 4-6 digits"):
        _ = entered_date(9, "", "7/25", w)
    with assert_raises(contains="not 4-6 digits"):
        _ = entered_date(9, "", "123", w)
    with assert_raises(contains="is not a date"):
        _ = entered_date(9, "13/1/95", "", w)
    with assert_raises(contains="is not a date"):
        _ = entered_date(9, "", "0095", w)


def test_a_comment_loses_the_colons_it_opens_with() raises:
    assert_equal(comment_of(":: Compare note 2. "), "Compare note 2.")
    assert_equal(comment_of("::Compare"), "Compare")
    assert_equal(comment_of("a :: b"), "a :: b")
    assert_equal(comment_of(""), "")


def test_the_sample_is_read_as_filemaker_left_it() raises:
    var c = load_corpus(NOTES, THEMES)
    assert_equal(c.comments[c.find(2)], "Note how the faculty simply go along with it.")
    assert_equal(c.comments[c.find(6)].startswith("Compare with note 2"), True)
    assert_equal(c.entered[c.find(2)], "1995-07-25")
    assert_equal(c.entered[c.find(8)], "2001-03-07")
    assert_equal(c.entered[c.find(10)], "1995-11-06")
    assert_equal(c.entered[c.find(12)], "")
    assert_equal(c.sources[c.find(8)], "R. Ellery, The Uses of a College (1964)")
    assert_false(c.notes[c.find(1)].endswith("\n"))
    _same(c.kinds[c.find(3)], ["Regents", "Institution"])
    _same(c.kinds[c.find(4)], ["Students", "Press"])
    _same(c.eras[c.find(11)], ["1990s", "1960s"])
    # A note's keywords come in term order.
    _same(c.keywords[c.find(1)], ["founding", "public trust"])
    assert_equal(len(c.warnings), 0)


def test_a_value_that_is_not_utf8_is_refused_by_row() raises:
    var db = open_memory()
    db.execute(SCHEMA)
    db.execute("INSERT INTO notes (row_id, note) VALUES (7, CAST(x'80' AS TEXT))")
    var c = Corpus()
    with assert_raises(contains="row 7: note is not UTF-8"):
        read_notes(db, c)
    var db2 = open_memory()
    db2.execute(SCHEMA)
    db2.execute("INSERT INTO notes (row_id, note) VALUES (3, 'fine')")
    db2.execute("INSERT INTO keyword VALUES (1, CAST(x'C328' AS TEXT))")
    db2.execute("INSERT INTO note_keyword VALUES (3, 1)")
    var c2 = Corpus()
    with assert_raises(contains="row 3: a keyword is not UTF-8"):
        read_notes(db2, c2)


def test_the_database_is_never_created_and_the_old_export_is_refused() raises:
    var missing = "data/no-such-notes.sqlite"
    with assert_raises(contains=missing):
        _ = load_corpus(missing, "")
    assert_false(exists(missing))
    with assert_raises(contains="tools/export.py"):
        _ = open_notes("data/notes.jsonl")


def _sample_notes() raises -> Corpus:
    return load_corpus(NOTES, "")


def test_citations_are_ids_and_ranges_once_each() raises:
    var c = _sample_notes()
    read_theme_map(
        "# Map\n\n## 5. Five\n\n**Tension.** *Plain* and _plain_.\n\n"
        + "**Research notes.** Some 30 notes, 1890s: [2]-[4], [4] – [6] and [12].\n",
        c,
    )
    assert_equal(c.theme_numbers[0], 5)
    assert_equal(c.theme_titles[0], "Five")
    assert_equal(c.theme_tensions[0], "Plain and plain.")
    var want: List[Int] = [2, 3, 4, 5, 6, 12]
    assert_equal(len(c.theme_notes[0]), len(want))
    for i in range(len(want)):
        assert_equal(c.theme_notes[0][i], want[i])


def test_a_theme_runs_to_the_next_numbered_heading_and_the_map_to_the_next_h1() raises:
    var c = _sample_notes()
    read_theme_map(
        "# Map\n\n## 1. One\n\n## An aside, still theme 1\n\n**Tension.**\nOn the next line.\n\n"
        + "**Research notes.** [1]\n\n## 2. Two\n\n**Tension.** t\n\n**Research notes.** [2]\n\n"
        + "# Anomalies\n\n## 3. Not a theme\n\n**Tension.** t\n\n**Research notes.** [99]\n",
        c,
    )
    assert_equal(len(c.theme_numbers), 2)
    assert_equal(c.theme_tensions[0], "On the next line.")
    assert_equal(c.theme_notes[1][0], 2)


def test_a_theme_the_map_cannot_read_is_refused_by_number() raises:
    var c = _sample_notes()
    with assert_raises(contains="theme 4 cites [99], which is not a note"):
        read_theme_map("## 4. X\n**Tension.** t\n**Research notes.** [1], [99]\n", c)
    with assert_raises(contains="theme 4 cites [6]–[4], which runs backwards"):
        read_theme_map("## 4. X\n**Tension.** t\n**Research notes.** [6]–[4]\n", c)
    with assert_raises(contains="theme 4 lacks a **Tension.**"):
        read_theme_map("## 4. X\n**Research notes.** [1]\n", c)
    with assert_raises(contains="theme 4 has no title"):
        read_theme_map("## 4.  \n**Tension.** t\n**Research notes.** [1]\n", c)
    with assert_raises(contains="no `## N. Title` sections"):
        read_theme_map("# A map\n\n## Not numbered\n", c)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
