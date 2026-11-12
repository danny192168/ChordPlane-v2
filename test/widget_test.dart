import 'package:chord_plane/core/chords/chord_document.dart';
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

    ChordDocument build({int transpose = 0, AccidentalPreference accidentals = AccidentalPreference.sharps}) {
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
    ChordDocument build(String body, {bool detectBare = false}) {
      return ChordDocument.build(
        body: body,
        originalKey: 'G',
        transpose: 0,
        detectBare: detectBare,
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
      const body = 'G          C\n'
          'Amazing grace, how sweet\n'
          'Em      D\n'
          'that saved a wretch like me';
      final document = build(body, detectBare: true);
      expect(document.chords, ['G', 'C', 'Em', 'D']);
    });

    test('bare chord detection is off by default', () {
      const body = 'G          C\nAmazing grace, how sweet';
      final document = build(body);
      expect(document.chords, isEmpty);
    });

    test('detects bare chord words inside lyric lines', () {
      final document = build(
        'I played the G chord and then the Am7',
        detectBare: true,
      );
      expect(document.chords, ['G', 'Am7']);
    });

    test('does not treat the word A as a bare chord', () {
      final document = build('I am A man of constant sorrow', detectBare: true);
      expect(document.chords, isEmpty);
    });

    test('rejects lyric words that merely resemble chords', () {
      final document = build(
        'The Eggs, Bass, Major and Aman passed by',
        detectBare: true,
      );
      expect(document.chords, isEmpty);
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
      const body = 'G      D\n'
          '[C]Amazing [Em]grace';
      final document = build(body, detectBare: true);
      expect(document.chords, ['G', 'C', 'D', 'Em']);
    });
  });
}
