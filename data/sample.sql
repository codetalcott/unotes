-- The invented sample: twelve notes and fifteen keywords in the shape of
-- the owner's notes.sqlite (build_notes_db.py's tables, less the FTS index
-- the app never reads). No row here is a real note. The server runs this
-- script into a private in-memory database when it has no real one, and
-- so do the tests and smoke.sh.
--
-- It is stored the way FileMaker left the real data, so the sample
-- exercises what src/sources.mojo cleans up: repeating values split at a
-- line feed, CR LF or vertical tab (3, 4, 10, 11); a comment opening with
-- `::` (2, 6); an entered date as M/D/YY or M/D/YYYY (field_13) or
-- squeezed (field_6) in four, five and six digits, and an ambiguous
-- squeezed one that its slashed twin overrides (10); a trailing line feed
-- (1) and non-breaking space (8). Keyword ids are not in term order, and
-- the owner's are not either, so a note's keywords come out in term order
-- only because the query sorts them.

CREATE TABLE notes (
    row_id INTEGER PRIMARY KEY,   -- synthetic, stable
    fm_id INTEGER,                -- FileMaker id; has gaps/dupes, not a key
    note TEXT, keywords TEXT, source TEXT, date TEXT, type TEXT,
    institution TEXT, era TEXT,
    field_4 TEXT, field_6 TEXT, field_7 TEXT, field_9 TEXT,
    field_10 TEXT, field_11 TEXT, field_13 TEXT
);
CREATE TABLE keyword (id INTEGER PRIMARY KEY, term TEXT UNIQUE);
CREATE TABLE note_keyword (
    note_id INTEGER REFERENCES notes(row_id),
    keyword_id INTEGER REFERENCES keyword(id),
    PRIMARY KEY (note_id, keyword_id)
);

-- field_6: the entered date, squeezed. field_7: the comment.
-- field_13: the entered date, slashed.
INSERT INTO notes
    (row_id, note, source, date, type, institution, era, field_6, field_7, field_13)
VALUES
(1,
    '"The college belongs to the town that built it," the founder told the first class, "and the town will ask what you did with it."' || char(10),
    'Harrow College Bulletin, vol. 1',
    '9/12/1891',
    'President',
    'Harrow',
    '1890s',
    NULL,
    NULL,
    '7/25/95'),
(2,
    'Students marched to the depot to meet the returning debate team; classes were cancelled by acclamation.',
    'The Harrow Lantern',
    '3/4/1893',
    'Students',
    'Harrow',
    '1890s',
    '72595',
    ':: Note how the faculty simply go along with it.',
    NULL),
(3,
    'The trustees declined the gift, the donor having asked to name the chemistry professor.',
    'Minutes of the Trustees',
    NULL,
    'Regents' || char(11) || 'Institution',
    'Harrow',
    '1890s',
    NULL,
    NULL,
    '8/2/1995'),
(4,
    'An editorial asks whether a degree is "a key or merely a receipt."',
    'The Lakeshore Daily',
    '11/2/1931',
    'Students' || char(13) || char(10) || 'Press',
    'Lakeshore',
    '1930s',
    '21197',
    NULL,
    NULL),
(5,
    'The committee met again (1) and resolved nothing, which the student paper reported with evident relish. The committee met again (2) and resolved nothing, which the student paper reported with evident relish. The committee met again (3) and resolved nothing, which the student paper reported with evident relish. The committee met again (4) and resolved nothing, which the student paper reported with evident relish. The committee met again (5) and resolved nothing, which the student paper reported with evident relish. The committee met again (6) and resolved nothing, which the student paper reported with evident relish. The committee met again (7) and resolved nothing, which the student paper reported with evident relish. The committee met again (8) and resolved nothing, which the student paper reported with evident relish. The committee met again (9) and resolved nothing, which the student paper reported with evident relish. The committee met again (10) and resolved nothing, which the student paper reported with evident relish. The committee met again (11) and resolved nothing, which the student paper reported with evident relish. The committee met again (12) and resolved nothing, which the student paper reported with evident relish. The committee met again (13) and resolved nothing, which the student paper reported with evident relish. The committee met again (14) and resolved nothing, which the student paper reported with evident relish. The committee met again (15) and resolved nothing, which the student paper reported with evident relish. The committee met again (16) and resolved nothing, which the student paper reported with evident relish. The committee met again (17) and resolved nothing, which the student paper reported with evident relish. The committee met again (18) and resolved nothing, which the student paper reported with evident relish. The committee met again (19) and resolved nothing, which the student paper reported with evident relish. The committee met again (20) and resolved nothing, which the student paper reported with evident relish. The committee met again (21) and resolved nothing, which the student paper reported with evident relish. The committee met again (22) and resolved nothing, which the student paper reported with evident relish. The committee met again (23) and resolved nothing, which the student paper reported with evident relish. The committee met again (24) and resolved nothing, which the student paper reported with evident relish. The committee met again (25) and resolved nothing, which the student paper reported with evident relish. The committee met again (26) and resolved nothing, which the student paper reported with evident relish. The committee met again (27) and resolved nothing, which the student paper reported with evident relish. The committee met again (28) and resolved nothing, which the student paper reported with evident relish. The committee met again (29) and resolved nothing, which the student paper reported with evident relish. The committee met again (30) and resolved nothing, which the student paper reported with evident relish. The committee met again (31) and resolved nothing, which the student paper reported with evident relish. The committee met again (32) and resolved nothing, which the student paper reported with evident relish. The committee met again (33) and resolved nothing, which the student paper reported with evident relish. The committee met again (34) and resolved nothing, which the student paper reported with evident relish. The committee met again (35) and resolved nothing, which the student paper reported with evident relish. The committee met again (36) and resolved nothing, which the student paper reported with evident relish. The committee met again (37) and resolved nothing, which the student paper reported with evident relish. The committee met again (38) and resolved nothing, which the student paper reported with evident relish. The committee met again (39) and resolved nothing, which the student paper reported with evident relish. The committee met again (40) and resolved nothing, which the student paper reported with evident relish. The committee met again (41) and resolved nothing, which the student paper reported with evident relish. The committee met again (42) and resolved nothing, which the student paper reported with evident relish. The committee met again (43) and resolved nothing, which the student paper reported with evident relish. The committee met again (44) and resolved nothing, which the student paper reported with evident relish. The committee met again (45) and resolved nothing, which the student paper reported with evident relish. The committee met again (46) and resolved nothing, which the student paper reported with evident relish. The committee met again (47) and resolved nothing, which the student paper reported with evident relish. The committee met again (48) and resolved nothing, which the student paper reported with evident relish. The committee met again (49) and resolved nothing, which the student paper reported with evident relish. The committee met again (50) and resolved nothing, which the student paper reported with evident relish. The committee met again (51) and resolved nothing, which the student paper reported with evident relish. The committee met again (52) and resolved nothing, which the student paper reported with evident relish. The committee met again (53) and resolved nothing, which the student paper reported with evident relish. The committee met again (54) and resolved nothing, which the student paper reported with evident relish. The committee met again (55) and resolved nothing, which the student paper reported with evident relish. The committee met again (56) and resolved nothing, which the student paper reported with evident relish. The committee met again (57) and resolved nothing, which the student paper reported with evident relish. The committee met again (58) and resolved nothing, which the student paper reported with evident relish. The committee met again (59) and resolved nothing, which the student paper reported with evident relish.',
    'The Lakeshore Daily',
    '1/15/1932',
    'Faculty',
    'Lakeshore',
    '1930s',
    '021197',
    NULL,
    NULL),
(6,
    'Chapel attendance made voluntary; the dean calls it "an experiment in conscience."',
    'Dean''s Report',
    NULL,
    'Administration',
    'Lakeshore',
    '1920s',
    '53096',
    '::Compare with note 2: the institution steps back, the students step forward.',
    '5/30/96'),
(7,
    'Café Münsterberg advertises "a quiet table for the thinking man" — naïveté sold as distinction.',
    'Anzeiger für Universitätsfreunde (Zürich)',
    NULL,
    'Ads',
    'Other',
    '1930s',
    '42799',
    NULL,
    NULL),
(8,
    'A note with no era, no type and no keywords: a secondary source read for background.',
    'R. Ellery, The Uses of a College (1964)' || char(160),
    NULL,
    NULL,
    'Other',
    NULL,
    '3701',
    NULL,
    NULL),
(9,
    'Women admitted to the literary society "as guests of the chair"; the minute is struck the following week.',
    'Philomathean Society Minutes',
    '10/9/1894',
    'Students',
    'Harrow',
    '1890s',
    NULL,
    NULL,
    '7/26/95'),
(10,
    'The coach is paid more than the professor of Greek, and the paper says so.' || char(9) || 'Tabbed aside: nobody replied.',
    'The Harrow Lantern',
    '11/20/1896',
    'Students' || char(10) || 'Press',
    'Harrow',
    '1890s',
    '11695',
    NULL,
    '11/6/95'),
(11,
    'A historian looks back: the founders'' public language outlived the public it addressed.',
    'M. Oyelaran, lecture notes',
    NULL,
    'Faculty',
    'Harrow' || char(11) || 'Other',
    ' 1990s ' || char(11) || char(11) || '1960s',
    NULL,
    NULL,
    '04/27/1999'),
(12,
    '<script>alert(''x'')</script> & "quotes" — a note that must arrive escaped, never executed.',
    'Test & <Fixture>',
    NULL,
    'Ref''s',
    'Other',
    '1990s',
    NULL,
    'A comment with <b>markup</b> in it.',
    NULL);

INSERT INTO keyword (id, term) VALUES
(1, 'public trust'),
(2, 'founding'),
(3, 'college spirit'),
(4, 'debate'),
(5, 'autonomy'),
(6, 'donors'),
(7, 'private advancement'),
(8, 'committees'),
(9, 'religion'),
(10, 'chapel'),
(11, 'advertising'),
(12, 'gender'),
(13, 'membership'),
(14, 'athletics'),
(15, 'escaping');

INSERT INTO note_keyword SELECT 1, id FROM keyword WHERE term IN ('public trust', 'founding');
INSERT INTO note_keyword SELECT 2, id FROM keyword WHERE term IN ('college spirit', 'debate');
INSERT INTO note_keyword SELECT 3, id FROM keyword WHERE term IN ('autonomy', 'donors');
INSERT INTO note_keyword SELECT 4, id FROM keyword WHERE term IN ('private advancement');
INSERT INTO note_keyword SELECT 5, id FROM keyword WHERE term IN ('committees');
INSERT INTO note_keyword SELECT 6, id FROM keyword WHERE term IN ('religion', 'chapel');
INSERT INTO note_keyword SELECT 7, id FROM keyword WHERE term IN ('advertising');
INSERT INTO note_keyword SELECT 9, id FROM keyword WHERE term IN ('gender', 'membership');
INSERT INTO note_keyword SELECT 10, id FROM keyword WHERE term IN ('athletics', 'private advancement');
INSERT INTO note_keyword SELECT 11, id FROM keyword WHERE term IN ('public trust');
INSERT INTO note_keyword SELECT 12, id FROM keyword WHERE term IN ('escaping');
