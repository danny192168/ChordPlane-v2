import 'package:chord_plane/core/chords/chord_detection.dart';
import 'package:chord_plane/core/chords/chord_document.dart';
import 'package:chord_plane/core/chords/chord_source.dart';
import 'package:chord_plane/core/chords/text_diagnostics.dart';
import 'package:chord_plane/core/utils/slug.dart';
import 'package:chord_pro/chord_pro.dart' show AccidentalPreference;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('slugify', () {
    test('lowercases and hyphenates', () {
      expect(slugify('Fleetwood Mac'), 'fleetwood-mac');
      expect(slugify('  The  Beatles  '), 'the-beatles');
    });

    test('strips accents', () {
      expect(slugify('Sigur Rós'), 'sigur-ros');
      expect(slugify('Beyoncé'), 'beyonce');
    });

    test('falls back for empty or punctuation-only input', () {
      expect(slugify(''), 'unknown');
      expect(slugify('!!!'), 'unknown');
    });
  });

  group('ChordDocument', () {
    const body = '''
{start_of_verse: Verse 1}
[G]Amazing grace, how [C]sweet the sound
[Em]That saved a [D]wretch like me
{end_of_verse}
''';

    ChordDocument build({
      int transpose = 0,
      AccidentalPreference accidentals = AccidentalPreference.sharps,
    }) {
      return ChordDocument.build(
        body: body,
        originalKey: 'G',
        transpose: transpose,
        accidentals: accidentals,
      );
    }

    test('collects unique chords from the source', () {
      expect(build().chords, ['G', 'C', 'Em', 'D']);
    });

    test('transposes chords up a whole step and spell with sharps', () {
      final document = build(transpose: 2);
      expect(document.chords, ['A', 'D', 'F#m', 'E']);
      expect(document.displayKey, 'A');
    });

    test('transposes down and spells with flats on request', () {
      final document = build(
        transpose: -1,
        accidentals: AccidentalPreference.flats,
      );
      expect(document.chords, ['Gb', 'B', 'Ebm', 'Db']);
      expect(document.displayKey, 'Gb');
    });

    test('reports the original key when nothing changes', () {
      expect(build().displayKey, 'G');
    });

    test('handles an empty body without throwing', () {
      final document = ChordDocument.build(
        body: '',
        originalKey: '',
        transpose: 0,
        accidentals: AccidentalPreference.sharps,
      );
      expect(document.chords, isEmpty);
      expect(document.displayKey, '');
    });

    test('wraps around the chromatic circle', () {
      final document = build(transpose: 11);
      expect(document.displayKey, 'F#');
    });
  });

  group('chord source formats', () {
    ChordDocument build(
      String body, {
      ChordDetectionMode mode = ChordDetectionMode.bracketsOnly,
    }) {
      return ChordDocument.build(
        body: body,
        originalKey: 'G',
        transpose: 0,
        mode: mode,
      );
    }

    test('detects angle-wrapped single chords', () {
      final document = build('<G>Amazing grace, how <C>sweet the sound');
      expect(document.chords, ['G', 'C']);
    });

    test('splits angle-wrapped progressions into single chords', () {
      final document = build('Play <G D Em C> over and over');
      expect(document.chords, ['G', 'D', 'Em', 'C']);
    });

    test('keeps non-chord angle groups as literal text', () {
      final document = build('<N.C.> and <spoken>');
      expect(document.chords, isEmpty);
    });

    test('maps chord-only lines onto the lyric line below them', () {
      const body =
          'G          C\n'
          'Amazing grace, how sweet\n'
          'Em      D\n'
          'that saved a wretch like me';
      final document = build(body, mode: ChordDetectionMode.auto);
      expect(document.chords, ['G', 'C', 'Em', 'D']);
    });

    test('brackets-only mode leaves bare chord rows as text', () {
      const body = 'G          C\nAmazing grace, how sweet';
      final document = build(body);
      expect(document.chords, isEmpty);
    });

    test('detects bare chord words inside lyric lines', () {
      final document = build(
        'I played the G chord and then the Am7',
        mode: ChordDetectionMode.auto,
      );
      expect(document.chords, ['G', 'Am7']);
    });

    test('does not treat the word A as a bare chord', () {
      final document = build(
        'I am A man of constant sorrow',
        mode: ChordDetectionMode.auto,
      );
      expect(document.chords, isEmpty);
    });

    test('rejects lyric words that merely resemble chords', () {
      final document = build(
        'The Eggs, Bass, Major and Aman passed by',
        mode: ChordDetectionMode.auto,
      );
      expect(document.chords, isEmpty);
    });

    test('ultimate guitar mode keeps bare lyric words as text', () {
      const body =
          'G               C\n'
          'I played the G chord and then the Am7';
      final document = build(body, mode: ChordDetectionMode.ultimateGuitar);
      expect(document.chords, ['G', 'C']);
    });

    test('brackets-only mode ignores bare chord rows and words', () {
      const body = 'G          C\nI played the G chord';
      final document = build(body, mode: ChordDetectionMode.bracketsOnly);
      expect(document.chords, isEmpty);
    });

    test('chordpro-only mode leaves every other syntax literal', () {
      final document = build(
        '<G>Hello [Am]world\nChorus:\n>  C',
        mode: ChordDetectionMode.chordProOnly,
      );
      expect(document.chords, ['Am']);
    });

    test('converts Ultimate Guitar section headers', () {
      const body = '[Verse 1]\n[G]First line\n\n[Chorus]\n[C]Last line';
      final document = build(body);
      expect(document.chords, ['G', 'C']);
      final labels = document.song.activeSections
          .map(sectionLabel)
          .whereType<String>()
          .toList();
      expect(labels, containsAll(['Verse 1', 'Chorus']));
    });

    test('transposes angle-wrapped progressions', () {
      final document = ChordDocument.build(
        body: '<G D>',
        originalKey: 'G',
        transpose: 2,
      );
      expect(document.chords, ['A', 'E']);
    });

    test('accepts unicode accidentals', () {
      final document = build('Play <C♯m7> then <D♭maj9>');
      // The parser keeps the ♯/♭ glyphs in the raw chord spelling.
      expect(document.chords, ['C♯m7', 'D♭maj9']);
    });

    test('maps bare chords into lyric lines that already have chords', () {
      const body =
          'G      D\n'
          '[C]Amazing [Em]grace';
      final document = build(body, mode: ChordDetectionMode.auto);
      expect(document.chords, ['G', 'C', 'D', 'Em']);
    });

    test('positions full-line angle groups above the lyric line', () {
      expect(
        ChordSource.normalize('<G   D>\nLyrics here'),
        '[G]Lyri[D]cs here',
      );
    });

    test('preserves wide spacing inside angle-wrapped chord lines', () {
      expect(
        ChordSource.normalize('<G      D     Em>\nLyrics of the song is here'),
        '[G]Lyrics [D]of the[Em] song is here',
      );
      expect(
        ChordSource.normalize('<       C      G>\nSome more lyrics'),
        'Some mo[C]re lyri[G]cs',
      );
    });

    test('anchors a lone angle-wrapped chord above the next lyric line', () {
      expect(ChordSource.normalize('<G>\nLyrics here'), '[G]Lyrics here');
    });

    test('positions >-marked chord lines above the lyric line', () {
      expect(
        ChordSource.normalize('>  G   C\nHello world again'),
        'Hel[G]lo w[C]orld again',
      );
      expect(
        ChordSource.normalize(
          '>    G    D     Em     C\n'
          'Song lyrics here sample lyrics here',
        ),
        'Song [G]lyric[D]s here[Em] sample[C] lyrics here',
      );
    });

    test('renders explicit chord lines as rows when no lyric follows', () {
      expect(ChordSource.normalize('<G   D>\n\nLyrics'), '[G]   [D]\n\nLyrics');
      expect(
        ChordSource.normalize('>  G   C\n\nLyrics'),
        '   [G]   [C]\n\nLyrics',
      );
    });

    test('keeps non-chord > lines as literal text', () {
      const body = '> just a quote, not chords';
      expect(ChordSource.normalize(body), body);
    });

    test('keeps a chord line above another chord line standalone', () {
      expect(
        ChordSource.normalize('> G   C\n> Am  F\nLyrics here'),
        '  [G]   [C]\nLy[Am]rics[F] here',
      );
    });

    test('explicit chord lines work with bare detection off', () {
      final document = build('<G   D>\nLyrics here\n>  C\nMore lyrics');
      expect(document.chords, ['G', 'D', 'C']);
    });

    test('transposes explicitly positioned chord lines', () {
      final document = ChordDocument.build(
        body: '<G      D>\nLyrics here\n>  C\nMore lyrics',
        originalKey: 'G',
        transpose: 2,
      );
      expect(document.chords, ['A', 'E', 'D']);
    });

    test('aligns > chords with lyrics that start with a space', () {
      expect(
        ChordSource.normalize(
          '>C             G    Dsus4 D\n Worship His holy name.',
        ),
        ' [C]Worship His ho[G]ly na[Dsus4]me.[D]',
      );
    });

    test('keeps chords past the end of a shorter lyric line', () {
      expect(
        ChordSource.normalize(
          '>     C              D       C/G G C/G G \n'
          " I'll worship Your holy name.",
        ),
        " I'll [C]worship Your ho[D]ly name.[C/G][G][C/G][G]",
      );
    });

    test('converts plain section headers', () {
      const body =
          'Chorus:\n'
          '>C  G\n'
          ' lyrics one\n'
          '\n'
          'Verse 1:\n'
          '>Em\n'
          ' lyrics two';
      final document = build(body);
      expect(document.chords, ['C', 'G', 'Em']);
      final labels = document.song.activeSections
          .map(sectionLabel)
          .whereType<String>()
          .toList();
      expect(labels, containsAll(['Chorus', 'Verse 1']));
    });

    test('keeps ordinary colon lines as lyric text', () {
      const body = 'Love: a story\n>  C\n Words here';
      final document = build(body);
      expect(document.chords, ['C']);
      expect(ChordSource.normalize(body).startsWith('Love: a story'), isTrue);
    });

    test('parses the 10,000 Reasons chorus arrangement', () {
      const body =
          'Chorus:\n'
          '>          C          G     D/F# Em\n'
          ' Bless the Lord, O my soul, O my soul,\n'
          '>C             G    Dsus4 D\n'
          ' Worship His holy name.\n'
          '>          C        Em   C D  Em\n'
          ' Sing like never before, 0 my soul.\n'
          '>     C              D       C/G G C/G G \n'
          " I'll worship Your holy name.";
      final document = build(body);
      expect(document.chords, ['C', 'G', 'D/F#', 'Em', 'Dsus4', 'D', 'C/G']);
      expect(ChordSource.normalize(body).split('\n').take(3).toList(), [
        '{start_of_chorus: Chorus}',
        ' Bless the [C]Lord, O my [G]soul, [D/F#]O my [Em]soul,',
        ' [C]Worship His ho[G]ly na[Dsus4]me.[D]',
      ]);
    });

    test('parses attached repeat annotations like G(2X)', () {
      expect(
        ChordSource.normalize(
          '>     C            D    G(2X)\n'
          " I'll worship Your holy name.",
        ),
        " I'll [C]worship Your [D]holy [G][×2]name.",
      );
      final document = build('>  C   G(2X)\n lyrics here');
      expect(document.chords, ['C', 'G']);
      final transposed = ChordDocument.build(
        body: '>  C   G(2X)\n lyrics here',
        originalKey: 'C',
        transpose: 2,
      );
      expect(transposed.chords, ['D', 'A']);
    });

    test('attaches a standalone repeat token to the previous chord', () {
      expect(
        ChordSource.normalize('>  C   G   D  2X\n lyrics here'),
        ' ly[C]rics[G] her[D][×2]e',
      );
      // A standalone repeat with no chord before it keeps the line literal.
      const body = '>  2X\n lyrics here';
      expect(ChordSource.normalize(body), body);
    });

    test('tolerates hold dashes on chord lines', () {
      expect(
        ChordSource.normalize(
          '>     C            D    C  G ---\n'
          " I'll worship Your holy name",
        ),
        " I'll [C]worship Your [D]holy [C]nam[G]e",
      );
      // Dashes keep their spacing in a standalone chord row.
      expect(
        ChordSource.normalize('>  C  --  G\n\nlyrics'),
        '   [C]  --  [G]\n\nlyrics',
      );
    });

    test('tolerates non-breaking spaces in pasted chord lines', () {
      expect(
        ChordSource.normalize(
          '>C\u00A0\u00A0\u00A0\u00A0\u00A0G\u00A0\u00A0Dsus4\u00A0D\n'
          ' Worship His holy name.',
        ),
        ' [C]Worshi[G]p H[Dsus4]is hol[D]y name.',
      );
    });

    test('supports notes after plain section headers', () {
      const body = 'Instrumental:(Do Chorus chords)\n>  C  G\n lyrics here';
      final document = build(body);
      final labels = document.song.activeSections
          .map(sectionLabel)
          .whereType<String>()
          .toList();
      expect(labels, ['Instrumental (Do Chorus chords)']);
      expect(document.chords, ['C', 'G']);
    });

    test('turns an intro header with a progression into a chord row', () {
      const body = 'Intro:< C G D Em  C G D >\n\nChorus:\n>  C\n lyrics';
      final normalized = ChordSource.normalize(body);
      expect(normalized.split('\n').first, '{start_of_intro: Intro}');
      final document = ChordDocument.build(
        body: body,
        originalKey: 'C',
        transpose: 0,
      );
      expect(document.chords, containsAll(['C', 'G', 'D', 'Em']));
      final labels = document.song.activeSections
          .map(sectionLabel)
          .whereType<String>()
          .toList();
      expect(labels, containsAll(['Intro', 'Chorus']));
    });

    test('keeps mixed wrapped and bare chords on one line', () {
      // Standalone: all chords on one row, spacing and holds preserved.
      expect(
        ChordSource.normalize('<G> Asus4 ---x\n\nlyrics'),
        '[G] [Asus4] ---x\n\nlyrics',
      );
      expect(
        ChordSource.normalize('<D> <Bm> A7sus4\n\nlyrics'),
        '[D] [Bm] [A7sus4]\n\nlyrics',
      );
      // Above a lyric line: anchored at the typed columns.
      expect(
        ChordSource.normalize('<G> Asus4\nlyrics here'),
        '[G]lyri[Asus4]cs here',
      );
    });

    test('recognizes mixed chord rows even when bare detection is off', () {
      const body = '<G> Asus4 ---x\n\nlyrics';
      final document = ChordDocument.build(
        body: body,
        originalKey: 'G',
        transpose: 0,
      );
      expect(document.chords, ['G', 'Asus4']);
    });

    test('tolerates ---x holds on > chord lines', () {
      expect(
        ChordSource.normalize('>  C  ---x  G\n lyric line here'),
        ' ly[C]ric line [G]here',
      );
    });

    test('parses header progressions with repeats', () {
      const first = 'Intro:< C G D Em  C G D 3X >2X\n\nChorus:\n>  C\n lyrics';
      final normalized = ChordSource.normalize(first);
      expect(normalized.split('\n').first, '{start_of_intro: Intro}');
      expect(normalized.split('\n')[1], contains('[D][×3]'));
      final document = ChordDocument.build(
        body: first,
        originalKey: 'C',
        transpose: 0,
      );
      expect(document.chords, containsAll(['C', 'G', 'D', 'Em']));

      const second = 'Intro: <Am Dm E> } 3x\n\n>  C\n lyrics';
      final row = ChordSource.normalize(second).split('\n');
      expect(row.first, '{start_of_intro: Intro}');
      expect(row[1], contains('[Am] [Dm] [E][×3]'));
      final secondDoc = ChordDocument.build(
        body: second,
        originalKey: 'C',
        transpose: 0,
      );
      expect(secondDoc.chords, containsAll(['Am', 'Dm', 'E']));
    });

    test('accepts lone > markers between chords on a chord line', () {
      expect(
        ChordSource.normalize('>Bm        >     A\nAll my past is washed away'),
        'A[Bm]ll my past is wa[A]shed away',
      );
    });

    test('recognizes colon-less section headers', () {
      const body =
          'Verse1\n>G   Bm\n my first line\n\n'
          'Prechorus\n>Bm    >  A\n all my past\n\n'
          'Chorus\n>  G\n all my life';
      final document = ChordDocument.build(
        body: body,
        originalKey: 'G',
        transpose: 0,
      );
      final labels = document.song.activeSections
          .map(sectionLabel)
          .whereType<String>()
          .toList();
      expect(labels, containsAll(['Verse 1', 'Prechorus', 'Chorus']));
      expect(document.chords, containsAll(['G', 'Bm', 'A']));
    });

    test('keeps tab lines verbatim and off the chord mapping', () {
      const body =
          '<F>  <Bb> <Dm>\n'
          'e|-----6----5----1----|\n'
          'B|10---6----6----1----|\n'
          'E------6---------1----|';
      final normalized = ChordSource.normalize(body);
      final lines = normalized.split('\n');
      expect(lines.first, '[F]  [Bb] [Dm]');
      expect(lines[1], 'e|-----6----5----1----|');
      expect(lines[2], 'B|10---6----6----1----|');
      expect(lines[3], 'E------6---------1----|');
      expect(normalized.contains('[B]'), isFalse);
      expect(normalized.contains('[E]'), isFalse);
      const single =
          '<Bb>              <Dsus2>\n'
          'e|--------------------------------|';
      final singleNorm = ChordSource.normalize(single).split('\n');
      expect(singleNorm.first, contains('[Bb]'));
      expect(singleNorm.first, contains('[Dsus2]'));
      expect(singleNorm[1], 'e|--------------------------------|');
    });

    test('maps single-chord groups above their lyric lines', () {
      const body =
          '[Verse 3]\n'
          '      <Ebm>           <Ab7>\n'
          "To any outlaw tryin to draw, thinkin you're bad";
      final document = ChordDocument.build(
        body: body,
        originalKey: 'Eb',
        transpose: 0,
      );
      expect(document.chords, ['Ebm', 'Ab7']);
      final labels = document.song.activeSections
          .map(sectionLabel)
          .whereType<String>()
          .toList();
      expect(labels, ['Verse 3']);
      expect(ChordSource.normalize(body).split('\n')[1], contains('[Ebm]'));
    });
  });

  group('ChordDetectionMode', () {
    test('round-trips every storage key', () {
      for (final mode in ChordDetectionMode.values) {
        expect(ChordDetectionMode.fromStorage(mode.storageKey), mode);
      }
    });

    test('accepts enum names and falls back to auto', () {
      expect(
        ChordDetectionMode.fromStorage('ultimateGuitar'),
        ChordDetectionMode.ultimateGuitar,
      );
      expect(
        ChordDetectionMode.fromStorage('chordProOnly'),
        ChordDetectionMode.chordProOnly,
      );
      expect(ChordDetectionMode.fromStorage(null), ChordDetectionMode.auto);
      expect(ChordDetectionMode.fromStorage(''), ChordDetectionMode.auto);
      expect(
        ChordDetectionMode.fromStorage('nonsense'),
        ChordDetectionMode.auto,
      );
    });

    test('exposes the capability flags each mode needs', () {
      expect(ChordDetectionMode.auto.detectChordRows, isTrue);
      expect(ChordDetectionMode.auto.detectInlineBare, isTrue);
      expect(ChordDetectionMode.ultimateGuitar.detectChordRows, isTrue);
      expect(ChordDetectionMode.ultimateGuitar.detectInlineBare, isFalse);
      expect(ChordDetectionMode.bracketsOnly.detectChordRows, isFalse);
      expect(ChordDetectionMode.bracketsOnly.rewritesPlainText, isTrue);
      expect(ChordDetectionMode.chordProOnly.rewritesPlainText, isFalse);
    });
  });

  group('paste hardening', () {
    test('zero-width characters do not break > chord lines', () {
      final normalized = ChordSource.normalize(
        '>\u200B C \u200B\u200BG(2X)\n lyrics here',
      );
      expect(normalized.contains('\u200B'), isFalse);
      expect(normalized.contains('[C]'), isTrue);
      expect(normalized.contains('[G][×2]'), isTrue);
      final document = ChordDocument.build(
        body: '>\u200B C \u200B\u200BG(2X)\n lyrics here',
        originalKey: 'C',
        transpose: 0,
      );
      expect(document.chords, ['C', 'G']);
    });

    test('non-breaking spaces are normalized everywhere', () {
      final normalized = ChordSource.normalize(
        '>C\u00A0\u00A0G\n\u00A0lyr\u00A0ics',
      );
      expect(normalized.contains('\u00A0'), isFalse);
      expect(normalized.contains('[C]'), isTrue);
      expect(normalized.contains('[G]'), isTrue);
    });

    test('fullwidth angle brackets act as their ASCII equivalents', () {
      final normalized = ChordSource.normalize('＞C   G\n lyrics here');
      expect(normalized.contains('＞'), isFalse);
      expect(normalized.contains('[C]'), isTrue);
      expect(normalized.contains('[G]'), isTrue);
    });

    test('line separators are treated as newlines', () {
      final normalized = ChordSource.normalize(
        'Chorus:\u2028>  C   G\n lyrics here',
      );
      expect(normalized.contains('\u2028'), isFalse);
      expect(normalized, contains('{start_of_chorus: Chorus}'));
      expect(normalized.contains('[C]'), isTrue);
      expect(normalized.contains('[G]'), isTrue);
    });

    test('CRLF and lone CR line endings are normalized', () {
      expect(TextDiagnostics.sanitize('a\r\nb\rc'), 'a\nb\nc');
      expect(
        ChordSource.normalize('>  C  ---x  G\r\n lyric line here'),
        ' ly[C]ric line [G]here',
      );
    });

    test('CRLF pasted chord rows are detected', () {
      // In Ultimate Guitar mode inline bare-word detection is off, so a
      // trailing CR on the last chord would previously drop the whole row.
      const body = 'G          C\r\nAmazing grace, how sweet';
      final document = ChordDocument.build(
        body: body,
        originalKey: 'G',
        transpose: 0,
        mode: ChordDetectionMode.ultimateGuitar,
      );
      expect(document.chords, ['G', 'C']);

      const marked = '>  C  ---x  G\r\n lyric line here';
      final markedDocument = ChordDocument.build(
        body: marked,
        originalKey: 'C',
        transpose: 0,
      );
      expect(markedDocument.chords, ['C', 'G']);

      const classicMac = '>  C  ---x  G\r lyric line here';
      final crDocument = ChordDocument.build(
        body: classicMac,
        originalKey: 'C',
        transpose: 0,
      );
      expect(crDocument.chords, ['C', 'G']);
    });

    test('sanitize never alters visible text', () {
      expect(
        TextDiagnostics.sanitize('Am\u00A0G\u200B\u200D7---\uFEFF'),
        'Am G7---',
      );
    });

    test('scan reports the right lines and codes', () {
      final findings = TextDiagnostics.scan(
        'clean line\nbad\u00A0line\u200Bhere\n\talso fine',
      );
      expect(findings.map((f) => (f.line, f.code)).toList(), [
        (2, 0x00A0),
        (2, 0x200B),
      ]);
      expect(findings.first.tag, '<U+00A0>');
    });

    test('reveal makes hidden characters visible', () {
      expect(TextDiagnostics.reveal('>\u00A0C\u200B'), '><U+00A0>C<U+200B>');
      expect(TextDiagnostics.reveal('a\tb'), 'a<TAB>b');
    });
  });
}
