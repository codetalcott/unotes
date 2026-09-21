"""The corpus: loading the invented sample, the facets, the scan.

Everything here reads `data/sample-*.jsonl`, which is committed and
invented, so this passes on a checkout that has never seen the real notes.
"""

from std.testing import TestSuite, assert_equal, assert_false, assert_true

from corpus import (
    Corpus,
    Filter,
    contains_bytes,
    load_corpus,
    page_count,
    split_values,
)

comptime NOTES = "data/sample-notes.jsonl"
comptime THEMES = "data/sample-themes.jsonl"


def _sample() raises -> Corpus:
    return load_corpus(NOTES, THEMES)


def test_the_sample_loads_whole() raises:
    var c = _sample()
    assert_equal(len(c), 12)
    assert_equal(len(c.theme_titles), 2)
    assert_equal(c.ids[0], 1)
    assert_equal(c.find(12), 11)
    assert_equal(c.find(99), -1)


def test_a_multi_valued_field_is_every_value() raises:
    var c = _sample()
    var i = c.find(11)
    assert_equal(len(c.eras[i]), 2)
    assert_equal(c.eras[i][0], "1990s")
    assert_equal(c.eras[i][1], "1960s")
    assert_equal(len(c.institutions[i]), 2)
    # A note with no era has no values, not one empty one.
    assert_equal(len(c.eras[c.find(8)]), 0)
    assert_equal(len(split_values("")), 0)


def test_a_facet_counts_a_two_valued_note_under_both() raises:
    var c = _sample()
    var want = Filter()
    want.kind = String("Press")
    assert_equal(len(c.select(want)), 2)
    want.kind = String("Students")
    assert_equal(len(c.select(want)), 4)
    # The era facet is by name, the others by count.
    assert_equal(c.era_facet.values[0], "1890s")
    assert_equal(c.kind_facet.values[0], "Students")
    assert_equal(c.kind_facet.counts[0], 4)


def test_filters_narrow_together() raises:
    var c = _sample()
    var want = Filter()
    want.era = String("1890s")
    want.institution = String("Harrow")
    assert_equal(len(c.select(want)), 5)
    want.keyword = String("athletics")
    var got = c.select(want)
    assert_equal(len(got), 1)
    assert_equal(c.ids[got[0]], 10)
    want.commented = True
    assert_equal(len(c.select(want)), 0)


def test_search_is_case_blind_and_reads_source_comment_and_keywords() raises:
    var c = _sample()
    var want = Filter()
    want.q = String("DEPOT")
    assert_equal(len(c.select(want)), 1)
    want.q = String("lantern")  # a source
    assert_equal(len(c.select(want)), 2)
    want.q = String("faculty simply")  # a comment
    assert_equal(len(c.select(want)), 1)
    want.q = String("chapel")  # a keyword, and the note's own text
    assert_equal(len(c.select(want)), 1)
    want.q = String("no such words anywhere")
    assert_equal(len(c.select(want)), 0)


def test_a_query_that_is_not_utf8_matches_nothing_and_traps_nothing() raises:
    var c = _sample()
    var bad: List[UInt8] = [UInt8(0x80), UInt8(0xC3), UInt8(0x28)]
    var want = Filter()
    want.q = String(unsafe_from_utf8=Span(bad))
    assert_equal(len(c.select(want)), 0)


def test_contains_bytes_at_both_ends() raises:
    var hay = String("abcdef")
    assert_true(contains_bytes(hay.as_bytes(), String("abc").as_bytes()))
    assert_true(contains_bytes(hay.as_bytes(), String("def").as_bytes()))
    assert_true(contains_bytes(hay.as_bytes(), String("").as_bytes()))
    assert_false(contains_bytes(hay.as_bytes(), String("efg").as_bytes()))
    assert_false(contains_bytes(hay.as_bytes(), String("abcdefg").as_bytes()))


def test_themes_cite_notes_both_ways() raises:
    var c = _sample()
    assert_equal(len(c.theme_notes[0]), 4)
    var citing = c.themes_citing(10)
    assert_equal(len(citing), 1)
    assert_equal(c.theme_numbers[citing[0]], 1)
    assert_equal(len(c.themes_citing(12)), 0)


def test_a_line_that_is_not_the_format_is_refused_by_number() raises:
    var c = Corpus()
    var raised = False
    try:
        c.add_note_line(String('{"id":"1","note":"x"}'), 7)
    except e:
        raised = True
        assert_true("line 7" in String(e))
    assert_true(raised)


def test_pages() raises:
    assert_equal(page_count(0), 1)
    assert_equal(page_count(25), 1)
    assert_equal(page_count(26), 2)
    assert_equal(page_count(535), 22)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
