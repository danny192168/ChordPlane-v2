import 'package:chord_pro/chord_pro.dart';
import 'package:flutter/foundation.dart';

import 'chord_detection.dart';
import 'chord_source.dart';

/// A parsed, transposed view of a song body. Parsing is cached by normalized
/// source text so scrolling and control changes stay cheap.
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
    AccidentalPreference accidentals = AccidentalPreference.sharps,
    ChordDetectionMode mode = ChordDetectionMode.auto,
  }) {
    final source = body.trim().isEmpty ? '' : body;
    // Plain chord formats (angle brackets, chord-only lines, UG headers)
    // are rewritten once; the parser only ever sees ChordPro brackets.
    final normalized = ChordSource.normalize(source, mode: mode);
    var base = _parseCache[normalized];
    if (base == null) {
      final result = ChordPro.parse(normalized);
      base = result.songs.isEmpty ? ChordPro.parseSong('') : result.songs.first;
      if (_parseCache.length >= _cacheLimit) {
        _parseCache.remove(_parseCache.keys.first);
      }
      _parseCache[normalized] = base;
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
      displayKey: transposeKeyLabel(sourceKey, transpose, accidentals),
      chords: _collectChords(transposed),
      diagnostics: const [],
    );
  }

  bool get hasChords => chords.isNotEmpty;

  /// Transposes a key label for display without parsing any song body.
  static String transposeKeyLabel(
    String key,
    int semitones, [
    AccidentalPreference accidentals = AccidentalPreference.sharps,
  ]) {
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
      r'^[A-G][#b♯♭]?(?:maj|min|m|dim|aug|sus|add|M|ø|°)?[0-9()+#b♯♭ø°susmajaddalt]*(?:/[A-G][#b♯♭]?)?$',
    ).hasMatch(raw);
  }
}

/// One chord-anchored render unit of a sheet line: an optional chord label
/// (with an optional repeat badge, e.g. `2X`) above a run of lyric text.
@immutable
class SheetUnit {
  const SheetUnit({this.chord, this.badge, required this.text});

  final String? chord;

  /// Repeat annotation for [chord], e.g. `2X` — rendered beside the chord.
  final String? badge;

  final String text;
}

/// Per-`Line` unit cache. The parsed document is cached by source text, so
/// `Line` objects are stable across rebuilds — recomputing chord/lyric
/// splits on every widget rebuild was one of the biggest hot paths.
final Expando<List<SheetUnit>> _lineUnits = Expando<List<SheetUnit>>();

/// Chord/lyric units for a line, computed once per parsed line.
List<SheetUnit> unitsForLine(Line line) {
  final cached = _lineUnits[line];
  if (cached != null) return cached;
  final units = _computeUnits(line);
  _lineUnits[line] = units;
  return units;
}

List<SheetUnit> _computeUnits(Line line) {
  final units = <_UnitBuilder>[];
  String? pendingChord;
  String? pendingBadge;

  void addUnit(String? chord, String text, {String? badge}) {
    if (text.isEmpty && chord == null) return;
    units.add(_UnitBuilder(chord: chord, badge: badge, text: text));
  }

  for (final token in line.tokens) {
    switch (token) {
      case ChordToken():
        if (pendingChord != null) {
          addUnit(pendingChord, '', badge: pendingBadge);
          pendingBadge = null;
        }
        // A repeat marker (`[×2]`, `[2X]`) rides along on the pending
        // chord instead of replacing it.
        final repeat = token.chord == null ? _repeatBadge(token.raw) : null;
        if (repeat != null && pendingChord != null) {
          pendingBadge = repeat;
        } else if (repeat == null) {
          pendingChord = token.chord?.raw ?? token.raw;
        }
      case TextToken():
        final chunks = splitIntoWordChunks(token.text);
        if (chunks.isEmpty) continue;
        for (var i = 0; i < chunks.length; i++) {
          final isFirst = i == 0;
          if (chunks.length == 1 && chunks[i].trim().isEmpty) {
            if (pendingChord != null) {
              addUnit(pendingChord, chunks[i], badge: pendingBadge);
              pendingChord = null;
              pendingBadge = null;
            } else if (units.isNotEmpty) {
              units.last.text.write(chunks[i]);
            }
            continue;
          }
          addUnit(
            isFirst ? pendingChord : null,
            chunks[i],
            badge: isFirst ? pendingBadge : null,
          );
          if (isFirst) {
            pendingChord = null;
            pendingBadge = null;
          }
        }
      case AnnotationToken():
        addUnit(pendingChord, '*${token.text}');
        pendingChord = null;
      case ChordRecallToken():
        break;
      case InlineDirectiveToken():
        break;
    }
  }

  if (pendingChord != null) {
    addUnit(pendingChord, '', badge: pendingBadge);
  }
  return units
      .map(
        (builder) => SheetUnit(
          chord: builder.chord,
          badge: builder.badge,
          text: builder.text.toString(),
        ),
      )
      .toList(growable: false);
}

/// A repeat marker carried as a bare bracket (`[×2]`, `[2X]`, `[x3]`) —
/// normalized to a display label like `2X`, or null when the raw text is
/// not a repeat count.
String? _repeatBadge(String raw) {
  final match = RegExp(r'^[×xX]?\s*(\d+)\s*[xX×]?$').firstMatch(raw);
  if (match == null) return null;
  return '${match.group(1)}X';
}

class _UnitBuilder {
  _UnitBuilder({this.chord, this.badge, required String text})
    : text = StringBuffer(text);

  final String? chord;
  final String? badge;
  final StringBuffer text;
}

/// Splits a lyric token into word chunks while keeping the spaces that
/// surround them, so wrapping never inserts stray gaps.
List<String> splitIntoWordChunks(String text) {
  final chunks = <String>[];
  var index = 0;
  while (index < text.length) {
    final leadingStart = index;
    while (index < text.length && _isSpace(text.codeUnitAt(index))) {
      index++;
    }
    final leading = text.substring(leadingStart, index);
    if (index >= text.length) {
      if (chunks.isEmpty) {
        chunks.add(leading);
      } else {
        chunks[chunks.length - 1] += leading;
      }
      break;
    }
    final wordStart = index;
    while (index < text.length && !_isSpace(text.codeUnitAt(index))) {
      index++;
    }
    final word = text.substring(wordStart, index);
    final trailingStart = index;
    while (index < text.length && _isSpace(text.codeUnitAt(index))) {
      index++;
    }
    final trailing = text.substring(trailingStart, index);
    chunks.add('$leading$word$trailing');
  }
  return chunks;
}

bool _isSpace(int codeUnit) =>
    codeUnit == 0x20 || codeUnit == 0x09 || codeUnit == 0x0A;

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
