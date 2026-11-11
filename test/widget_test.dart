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
}
