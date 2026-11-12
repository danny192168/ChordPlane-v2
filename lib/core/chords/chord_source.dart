import 'package:flutter/foundation.dart';

/// Rewrites plain chord formats into ChordPro bracket syntax so the parser
/// only ever sees one input dialect.
///
/// Supported input:
///  - ChordPro `[Am]` — already correct, left untouched.
///  - Angle-wrapped chords `<Am>` and progressions `<G D Em C>`.
///  - Ultimate-Guitar-style section headers: `[Verse]`, `[Chorus 2]`, …
///  - With [detectBare]: chords without any brackets — chord-only lines
///    placed above lyric lines (the classic Ultimate Guitar / crd format)
///    and bare chord words inside lyric lines.
@immutable
class ChordSource {
  const ChordSource._();

  /// A chord after the root: quality words, extensions, alterations, parens
  /// and slash-chord roots. Letters that never appear in chord suffixes
  /// (e, f, g, h, k…) are deliberately excluded so lyric words like
  /// "Eggs", "Bass" or "Major" do not match.
  static const String _suffix =
      r'(?:(?:maj|min|dim|aug|sus|add|Maj|m|M|ø|°|\d|#|b|♯|♭|\(|\)|/(?:[A-G][#b♯♭]?))*)';

  /// Strict enough to be used on unwrapped text.
  static final RegExp _fullChord = RegExp('^[A-G][#b♯♭]?$_suffix\$');

  /// `<…>` groups — either a single chord or a space-separated progression.
  static final RegExp _angleGroup = RegExp(r'<([^<>]*)>');

  /// Ultimate-Guitar-style standalone section headers.
  static final RegExp _sectionHeader = RegExp(
    r'^\s*\[\s*('
    r'intro|verse|pre-?chorus|chorus|post-?chorus|bridge|interlude|'
    r'refrain|hook|outro|coda|solo|guitar solo|instrumental|breakdown|'
    r'turnaround|drop|break|tag|ending|vamp|fade'
    r')\s*(\d+)?\s*(?:x\s*\d+)?\s*\]\s*$',
    caseSensitive: false,
  );

  /// Bare-chord scanner used inside lyric text. Requires the chord to be a
  /// standalone word so it never fires inside other words.
  static final RegExp _bareChord = RegExp(
    '(?<![A-Za-z0-9])([A-G][#b♯♭]?$_suffix)(?![A-Za-z0-9])',
  );

  /// Common English words that are also valid chord names and appear in
  /// lyrics far more often as words than as chords.
  static const Set<String> _bareStoplist = {'A'};

  /// Normalizes [body] into ChordPro bracket syntax.
  static String normalize(String body, {bool detectBare = false}) {
    if (body.trim().isEmpty) return body;

    // Pass 1: `<G>` and `<G D Em C>` angle groups become `[G]` / `[G][D][Em][C]`.
    final lines = [
      for (final line in body.split('\n'))
        line.trim().startsWith('{') ? line : _convertAngleGroups(line),
    ];
    final classified = List<_LineKind>.filled(lines.length, _LineKind.text);
    for (var i = 0; i < lines.length; i++) {
      classified[i] = _classify(lines[i]);
    }

    final out = <String>[];
    String? openHeaderKind;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      switch (classified[i]) {
        case _LineKind.directive:
          out.add(line);
          continue;
        case _LineKind.sectionHeader:
          final header = _sectionHeader.firstMatch(line)!;
          final inner = line
              .substring(line.indexOf('[') + 1, line.lastIndexOf(']'))
              .trim();
          final kind = _headerKind(header.group(1)!);
          // Close the previous header section so sections never nest.
          if (openHeaderKind != null) out.add('{end_of_$openHeaderKind}');
          openHeaderKind = kind;
          out.add('{start_of_$kind: $inner}');
          continue;
        case _LineKind.chordLine:
          if (!detectBare) {
            out.add(line);
            continue;
          }
          final tokens = _chordTokens(line)!;
          final lyricIndex = _lyricAfter(lines, classified, i + 1);
          if (lyricIndex != null) {
            // Chords-above-lyrics pair: anchor each chord at its original
            // column inside the lyric line, then drop the chord line.
            out.add(_mapChordsOntoLyric(tokens, lines[lyricIndex]));
            classified[lyricIndex] = _LineKind.consumed;
          } else {
            // Standalone chord line (strum row, progression on its own…).
            out.add(_bracketTokens(line, tokens));
          }
          continue;
        case _LineKind.text:
        case _LineKind.consumed:
          out.add(_inlineChords(line, detectBare: detectBare));
          continue;
      }
    }
    if (openHeaderKind != null) out.add('{end_of_$openHeaderKind}');
    return out.join('\n');
  }

  static String _headerKind(String raw) {
    final name = raw.toLowerCase().trim();
    return switch (name) {
      'verse' => 'verse',
      'chorus' || 'refrain' || 'hook' => 'chorus',
      'bridge' => 'bridge',
      _ => name.replaceAll(RegExp(r'[^a-z0-9]'), ''),
    };
  }

  /// `<Am>` → `[Am]`; `<G D Em C>` → `[G][D][Em][C]`. Groups whose content
  /// is not a chord (notes, HTML, ellipses) are kept as literal text.
  static String _convertAngleGroups(String line) {
    if (!line.contains('<')) return line;
    return line.replaceAllMapped(_angleGroup, (match) {
      final inner = match.group(1)!.trim();
      if (inner.isEmpty) return match.group(0)!;
      final tokens = inner.split(RegExp(r'\s+'));
      for (final token in tokens) {
        if (!_fullChord.hasMatch(token)) return match.group(0)!;
      }
      return tokens.map((token) => '[$token]').join();
    });
  }

  static _LineKind _classify(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return _LineKind.text;
    if (trimmed.startsWith('{')) return _LineKind.directive;
    if (_sectionHeader.hasMatch(line)) return _LineKind.sectionHeader;
    if (!detectableLine(line)) return _LineKind.text;
    if (_chordTokens(line) != null) return _LineKind.chordLine;
    return _LineKind.text;
  }

  /// Lines that contain existing ChordPro markup or tab notation are never
  /// rewritten by the bare-chord heuristics.
  static bool detectableLine(String line) {
    if (line.contains('[') || line.contains(']')) return false;
    if (line.contains('{') || line.contains('}')) return false;
    if (line.contains('<') || line.contains('>')) return false;
    return true;
  }

  /// The next lyric line at or after [start], or `null`. Only the line
  /// directly after the chord line can carry the chords — a blank line
  /// between them means the chord line stands on its own.
  static int? _lyricAfter(List<String> lines, List<_LineKind> classified, int start) {
    if (start >= lines.length) return null;
    final kind = classified[start];
    if (kind == _LineKind.consumed ||
        kind == _LineKind.directive ||
        kind == _LineKind.sectionHeader) {
      return null;
    }
    if (lines[start].trim().isEmpty) return null;
    return start;
  }

  /// Chord tokens of a chord-only line with their 0-based columns, or
  /// `null` when the line contains anything that is not a chord. `|`
  /// bar separators are treated as whitespace.
  static List<({int column, String chord})>? _chordTokens(String line) {
    final tokens = <({int column, String chord})>[];
    var i = 0;
    while (i < line.length) {
      final ch = line.codeUnitAt(i);
      if (ch == 0x20 || ch == 0x09 || ch == 0x7C) {
        i++;
        continue;
      }
      final start = i;
      while (i < line.length) {
        final c = line.codeUnitAt(i);
        if (c == 0x20 || c == 0x09 || c == 0x7C) break;
        i++;
      }
      final token = line.substring(start, i);
      if (!_fullChord.hasMatch(token)) return null;
      tokens.add((column: start, chord: token));
    }
    return tokens.isEmpty ? null : tokens;
  }

  /// Inserts each chord of a chord-only line into the lyric line at the
  /// column it appeared above. Bracketed spans (`[…]`, `{…}`) in the lyric
  /// line are skipped over — columns refer to the visible lyric text only.
  static String _mapChordsOntoLyric(
    List<({int column, String chord})> tokens,
    String lyric,
  ) {
    final spans = _protectedRanges(lyric);
    final buffer = StringBuffer();
    var rawPos = 0;
    var visible = 0;
    var t = 0;

    while (t < tokens.length) {
      final target = tokens[t].column;
      // Copy lyric text until the visible column of the next chord.
      while (rawPos < lyric.length && visible < target) {
        final spanEnd = _spanEndAt(spans, rawPos);
        if (spanEnd != null) {
          buffer.write(lyric.substring(rawPos, spanEnd));
          rawPos = spanEnd;
          continue;
        }
        buffer.write(lyric[rawPos]);
        rawPos++;
        visible++;
      }
      // Emit every chord anchored at this visible column, in order.
      while (t < tokens.length && tokens[t].column <= target) {
        buffer.write('[${tokens[t].chord}]');
        t++;
      }
      if (rawPos >= lyric.length) break;
    }
    if (rawPos < lyric.length) buffer.write(lyric.substring(rawPos));
    return buffer.toString();
  }

  /// If [pos] sits inside a protected span, returns its end; otherwise null.
  static int? _spanEndAt(List<(int, int)> spans, int pos) {
    for (final (start, end) in spans) {
      if (pos >= start && pos < end) return end;
    }
    return null;
  }

  /// `[…]` and `{…}` spans (start, end-exlusive) of a line.
  static List<(int, int)> _protectedRanges(String line) {
    final ranges = <(int, int)>[];
    var inBracket = false;
    var inBrace = false;
    var start = -1;
    for (var i = 0; i < line.length; i++) {
      final ch = line.codeUnitAt(i);
      if (ch == 0x5C) {
        i++;
        continue;
      }
      if (inBracket || inBrace) {
        if (ch == 0x5D && !inBrace) {
          inBracket = false;
          ranges.add((start, i + 1));
        } else if (ch == 0x7D && !inBracket) {
          inBrace = false;
          ranges.add((start, i + 1));
        }
      } else {
        if (ch == 0x5B) {
          inBracket = true;
          start = i;
        } else if (ch == 0x7B) {
          inBrace = true;
          start = i;
        }
      }
    }
    if (inBracket || inBrace) ranges.add((start, line.length));
    return ranges;
  }

  /// Standalone chord line: wrap every token, keep spacing between them.
  static String _bracketTokens(
    String line,
    List<({int column, String chord})> tokens,
  ) {
    final buffer = StringBuffer();
    var pos = 0;
    for (final token in tokens) {
      final at = token.column.clamp(0, line.length);
      if (at > pos) {
        buffer.write(line.substring(pos, at).replaceAll('|', ''));
        pos = at;
      }
      buffer.write('[${token.chord}]');
      pos = token.column + token.chord.length;
    }
    return buffer.toString();
  }

  /// Detects bare chord words inside a lyric line (outside `[...]` and
  /// `{...}` spans).
  static String _inlineChords(String line, {required bool detectBare}) {
    if (!detectBare || !_bareChord.hasMatch(line)) return line;

    final buffer = StringBuffer();
    for (final segment in _splitProtected(line)) {
      if (segment.protected) {
        buffer.write(segment.text);
        continue;
      }
      buffer.write(
        segment.text.replaceAllMapped(_bareChord, (match) {
          final chord = match.group(1)!;
          if (_bareStoplist.contains(chord)) return match.group(0)!;
          return '[$chord]';
        }),
      );
    }
    return buffer.toString();
  }

  /// Splits [line] into segments that are inside `[…]`/`{…}` spans and
  /// segments that are plain lyric text.
  static List<({bool protected, String text})> _splitProtected(String line) {
    final out = <({bool protected, String text})>[];
    final buffer = StringBuffer();
    var isProtected = false;

    void flush(bool wasProtected) {
      if (buffer.isEmpty) return;
      out.add((protected: wasProtected, text: buffer.toString()));
      buffer.clear();
    }

    var inBracket = false;
    var inBrace = false;
    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      final nowProtected = inBracket || inBrace;
      if (nowProtected != isProtected) {
        flush(isProtected);
        isProtected = nowProtected;
      }
      buffer.write(ch);
      if (ch == '\\' && i + 1 < line.length) {
        i++;
        buffer.write(line[i]);
        continue;
      }
      if (ch == '[' && !inBrace) {
        inBracket = true;
      } else if (ch == ']' && !inBrace) {
        inBracket = false;
      } else if (ch == '{' && !inBracket) {
        inBrace = true;
      } else if (ch == '}' && !inBracket) {
        inBrace = false;
      }
    }
    flush(isProtected);
    return out;
  }
}

enum _LineKind { text, directive, sectionHeader, chordLine, consumed }
