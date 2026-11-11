import 'package:chord_pro/chord_pro.dart';
import 'package:flutter/foundation.dart';

/// A parsed, transposed view of a song body. Parsing is cached by source text
/// so scrolling and control changes stay cheap.
@immutable
class ChordDocument {
  const ChordDocument._({
    required this.song,
    required this.transpose,
    required this.accidentals,
    required this.displayKey,
    required this.chords,
    required this.diagnostics,
  });

  final Song song;
  final int transpose;
  final AccidentalPreference accidentals;
  final String displayKey;
  final List<String> chords;
  final List<String> diagnostics;

  static final Map<String, Song> _parseCache = <String, Song>{};
  static const int _cacheLimit = 48;

  factory ChordDocument.build({
    required String body,
    required String originalKey,
    required int transpose,
    required AccidentalPreference accidentals,
  }) {
    final source = body.trim().isEmpty ? '' : body;
    var base = _parseCache[source];
    if (base == null) {
      final result = ChordPro.parse(source);
      base = result.songs.isEmpty ? ChordPro.parseSong('') : result.songs.first;
      if (_parseCache.length >= _cacheLimit) {
        _parseCache.remove(_parseCache.keys.first);
      }
      _parseCache[source] = base;
    }

    final transposed = transpose == 0
        ? base
        : base.transposed(transpose, accidentals: accidentals);

    final sourceKey = originalKey.trim().isNotEmpty
        ? originalKey.trim()
        : (transposed.metadata.key ?? '');

    return ChordDocument._(
      song: transposed,
      transpose: transpose,
      accidentals: accidentals,
      displayKey: _transposeKey(sourceKey, transpose, accidentals),
      chords: _collectChords(transposed),
      diagnostics: const [],
    );
  }

  bool get hasChords => chords.isNotEmpty;

  static List<String> _collectChords(Song song) {
    final seen = <String>{};
    for (final section in song.activeSections) {
      for (final line in section.lines) {
        for (final token in line.tokens) {
          if (token is! ChordToken) continue;
          final chord = token.chord;
          if (chord == null) continue;
          if (chord.system != ChordSystem.letter) continue;
          final raw = chord.raw.trim();
          if (raw.isEmpty || _isRest(raw)) continue;
          if (!_looksLikeChord(raw)) continue;
          seen.add(raw);
        }
      }
    }
    return seen.toList(growable: false);
  }

  static bool _isRest(String raw) {
    final value = raw.replaceAll('.', '').toUpperCase();
    return value == 'NC';
  }

  static bool _looksLikeChord(String raw) {
    return RegExp(
      r'^[A-G][#b]?(?:maj|min|m|dim|aug|sus|add|M|ø|°)?[0-9()+#bø°susmajaddalt/]*$',
    ).hasMatch(raw);
  }

  static String _transposeKey(
    String key,
    int semitones,
    AccidentalPreference accidentals,
  ) {
    if (key.isEmpty || semitones == 0) return key;
    final match = RegExp(r'^([A-G][#b]?)(.*)$').firstMatch(key);
    if (match == null) return key;
    final root = transposeRoot(
      match.group(1)!,
      semitones,
      accidentals: accidentals,
      forceCommonKeys: true,
    );
    return '${root ?? match.group(1)}${match.group(2)}';
  }
}

/// Section heading for the renderer. ChordPro `{start_of_verse: Verse 1}`
/// labels win; otherwise a readable default is used.
String? sectionLabel(Section section) {
  if (section.label != null && section.label!.trim().isNotEmpty) {
    return section.label!.trim();
  }
  return switch (section.kind) {
    SectionKind.verse => 'Verse',
    SectionKind.chorus => 'Chorus',
    SectionKind.bridge => 'Bridge',
    SectionKind.tab => 'Tab',
    SectionKind.grid => 'Grid',
    SectionKind.textblock => 'Notes',
    SectionKind.custom => section.customKind,
    _ => null,
  };
}
