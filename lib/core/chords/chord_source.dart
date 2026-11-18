import 'package:flutter/foundation.dart';

import 'chord_detection.dart';
import 'text_diagnostics.dart';

/// One chord of a chord line: where it starts, where its raw token ends
/// (so the spacing around it can be preserved), the chord name, and an
/// optional repeat count (`G(2X)` → 2).
typedef _ChordToken = ({int column, int end, String chord, int? repeat});

/// Rewrites plain chord formats into ChordPro bracket syntax so the parser
/// only ever sees one input dialect.
///
/// Supported input:
///  - ChordPro `[Am]` — already correct, left untouched.
///  - Angle-wrapped chords `<Am>` and progressions `<G D Em C>`.
///  - Angle-wrapped chord lines `<G      D     Em>` — a line made up only
///    of groups: the spacing positions each chord above the lyric line
///    that follows.
///  - `>`-prefixed chord lines `>   G   D   Em` — everything on the line
///    is chords; the `>` counts as the first column of the lyric line
///    below, so chords line up exactly as typed (a lyric line starting
///    with a space lines up with the `>`).
///  - Section headers: bracketed (`[Verse]`, `[Chorus 2]`), plain
///    (`Chorus:`, `Verse 1:`), colon-less (`Intro`, `Verse1`,
///    `Prechorus`), optionally with a note after the colon
///    (`Instrumental:(Do Chorus chords)`) or a progression
///    (`Intro:< C G D Em  C G D 3X >2X`, `Intro: <Am Dm E> } 3x`).
///  - Repeat annotations on chord lines — `G(2X)`, `G(2)`, `G(x2)` or a
///    standalone `2X` / `x2` repeating the previous chord — rendered as a
///    badge next to the chord. Hold dashes (`---`, `---x`) are tolerated
///    as decoration, lone `>` markers between chords (`>Bm  >  A`) are
///    accepted, and all Unicode spaces (non-breaking spaces included)
///    count as whitespace, so pastes from other apps work.
///  - Guitar tab lines (`e|-----6----5----`) are left verbatim and never
///    absorb the chord line above them.
///  - Depending on [ChordDetectionMode]: chords without any brackets —
///    chord-only lines placed above lyric lines (the classic Ultimate
///    Guitar / crd format) and bare chord words inside lyric lines.
///    [ChordDetectionMode.chordProOnly] disables all rewriting, so only
///    ChordPro brackets and directives are recognized.
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

  /// A line made up solely of `<…>` groups (plus whitespace), e.g.
  /// `<G      D     Em>` — treated as a positional chord line.
  static final RegExp _lineOfGroupsOnly = RegExp(r'^\s*(?:<[^<>]*>\s*)+$');

  /// A `>` marker introducing a chord line: `>   G   D   Em`.
  static final RegExp _gtMarker = RegExp(r'^\s*>');

  /// Repeat annotation attached to a chord: `G(2X)`, `G(2)`, `G(x2)`…
  /// The parentheses are pure decoration and are dropped.
  static final RegExp _attachedRepeat = RegExp(
    r'^([A-G][#b♯♭]?' + _suffix + r')\(\s*[xX]?\s*(\d+)\s*[xX]?\s*\)$',
  );

  /// A standalone repeat marker repeating the previous chord:
  /// `2X`, `3x`, `x2`, `×5`.
  static final RegExp _standaloneRepeat = RegExp(
    r'^(?:[xX×]\s*(\d+)|(\d+)\s*[xX×])$',
  );

  /// A chord-line token of only dashes (`---`, `--`, `-`), optionally
  /// ending in an `x` (`---x`) — a hold mark that is pure decoration.
  static bool _isHoldDashes(String token) =>
      RegExp(r'^-+[xX]?$').hasMatch(token);

  /// Space, tab, carriage return, pipe (bar separator) and the Unicode
  /// spaces that copies from web pages and documents sneak in
  /// (non-breaking space et al.).
  static bool _isChordSpace(int ch) {
    return ch == 0x20 ||
        ch == 0x09 ||
        ch == 0x0D ||
        ch == 0x7C ||
        ch == 0xA0 ||
        ch == 0x1680 ||
        ch == 0xFEFF ||
        (ch >= 0x2000 && ch <= 0x200A) ||
        ch == 0x202F ||
        ch == 0x205F ||
        ch == 0x3000;
  }

  /// Section-header words shared by the bracketed and plain forms.
  static const String _sectionWords =
      'intro|verse|pre-?chorus|chorus|post-?chorus|bridge|interlude|'
      'refrain|hook|outro|coda|solo|guitar solo|instrumental|breakdown|'
      'turnaround|drop|break|tag|ending|vamp|fade';

  /// Ultimate-Guitar-style standalone section headers.
  static final RegExp _sectionHeader = RegExp(
    r'^\s*\[\s*('
    '$_sectionWords'
    r')\s*(\d+)?\s*(?:x\s*\d+)?\s*\]\s*$',
    caseSensitive: false,
  );

  /// Plain section headers: `Chorus:`, `Verse 1:`, `Instrumental:(note)`…
  /// Group 3 is anything after the colon (a note or chord progression).
  static final RegExp _plainSectionHeader = RegExp(
    r'^\s*('
    '$_sectionWords'
    r')\s*(\d+)?\s*:\s*(.*)$',
    caseSensitive: false,
  );

  /// Standalone header words without a colon — the Guitar Songs app writes
  /// `Intro`, `Verse1`, `Prechorus`, `Chorus`, `Bridge` on their own line.
  /// A conservative subset only: common lyric words (`Break`, `Drop`,
  /// `Solo`…) are deliberately absent so lyrics are never swallowed.
  static final RegExp _bareHeader = RegExp(
    r'^\s*(intro|verse|pre-?chorus|chorus|post-?chorus|bridge|interlude|'
    r'instrumental|outro)\s*(\d+)?\s*$',
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
  ///
  /// The body is sanitized first: non-breaking and other Unicode spaces
  /// become plain spaces, fullwidth `＞`/`＜` become ASCII angle brackets,
  /// line separators become newlines, and zero-width characters are
  /// dropped — the invisible characters that pastes from other apps
  /// carry and that would otherwise break chord detection.
  static String normalize(
    String body, {
    ChordDetectionMode mode = ChordDetectionMode.auto,
  }) {
    if (body.trim().isEmpty) return body;
    body = TextDiagnostics.sanitize(body);
    // ChordPro-only mode leaves the document untouched: no angle-group
    // conversion, no positional chord rows, no plain headers.
    if (!mode.rewritesPlainText) return body;

    // Pass 1: `<G>` and `<G D Em C>` angle groups become `[G]` / `[G][D][Em][C]`.
    // Explicit positional chord lines are left untouched — their spacing
    // matters and is resolved in the main pass below. Plain headers whose
    // rest is a chord progression (`Intro:< C G D >`) are kept intact too.
    final lines = [
      for (final line in body.split('\n'))
        line.trim().startsWith('{') ||
                _explicitChordLine(line) != null ||
                _isPlainHeaderWithChords(line) ||
                (line.contains('<') && _chordTokens(line) != null)
            ? line
            : _convertAngleGroups(line),
    ];
    final classified = List<_LineKind>.filled(lines.length, _LineKind.text);
    for (var i = 0; i < lines.length; i++) {
      classified[i] = _classify(lines[i], mode);
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
          final bracketed = _sectionHeader.firstMatch(line);
          String? chordRow;
          final String inner;
          final String kind;
          if (bracketed != null) {
            inner = line
                .substring(line.indexOf('[') + 1, line.lastIndexOf(']'))
                .trim();
            kind = _headerKind(bracketed.group(1)!);
          } else {
            final plain = _plainSectionHeader.firstMatch(line);
            if (plain != null) {
              // Plain header (`Chorus:`, `Verse 1:`). A note after the
              // colon joins the label; chord content after the colon
              // becomes a standalone chord row instead.
              kind = _headerKind(plain.group(1)!);
              final number = plain.group(2);
              final rest = (plain.group(3) ?? '').trim();
              final base = number == null
                  ? plain.group(1)!
                  : '${plain.group(1)} $number';
              final row = _headerChordRow(rest);
              if (row != null) {
                chordRow = _bracketTokens(row.source, row.tokens);
                inner = base;
              } else {
                inner = rest.isEmpty ? base : '$base $rest';
              }
            } else {
              // Colon-less header word (`Intro`, `Verse1`, `Prechorus`).
              final bare = _bareHeader.firstMatch(line)!;
              kind = _headerKind(bare.group(1)!);
              final number = bare.group(2);
              inner = number == null
                  ? bare.group(1)!
                  : '${bare.group(1)} $number';
            }
          }
          // Close the previous header section so sections never nest.
          if (openHeaderKind != null) out.add('{end_of_$openHeaderKind}');
          openHeaderKind = kind;
          out.add('{start_of_$kind: $inner}');
          if (chordRow != null) out.add(chordRow);
          continue;
        case _LineKind.chordLine:
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
        case _LineKind.explicitChordLine:
          // Explicitly marked chord line (`<G      D>`, `>   G   D`, or a
          // mixed `<G> Asus4 ---x` row). Always recognized — the marker
          // makes it unambiguous, so this does not depend on the chord
          // detection mode beyond ChordPro-only, which returns early.
          final explicit =
              _explicitChordLine(line) ??
              (source: line, tokens: _chordTokens(line)!);
          final lyricIndex = _lyricAfter(lines, classified, i + 1);
          if (lyricIndex != null) {
            // Anchor each chord at its column inside the lyric line below,
            // then drop the chord line.
            out.add(_mapChordsOntoLyric(explicit.tokens, lines[lyricIndex]));
            classified[lyricIndex] = _LineKind.consumed;
          } else {
            // Standalone chord line — keep the spacing between chords.
            out.add(_bracketTokens(explicit.source, explicit.tokens));
          }
          continue;
        case _LineKind.text:
          out.add(_inlineChords(line, detectBare: mode.detectInlineBare));
          continue;
        case _LineKind.consumed:
          // Already merged into the chord line above it — drop it.
          continue;
      }
    }
    if (openHeaderKind != null) out.add('{end_of_$openHeaderKind}');
    return out.join('\n');
  }

  /// A plain `Word: rest` header whose rest carries chord content — the
  /// rest must reach the main pass unconverted so it can become a
  /// standalone chord row inside the section.
  static bool _isPlainHeaderWithChords(String line) {
    final match = _plainSectionHeader.firstMatch(line);
    if (match == null) return false;
    return _headerChordRow((match.group(3) ?? '').trim()) != null;
  }

  /// The chord row carried by a plain header's rest, or `null` when the
  /// rest is a note (`Instrumental:(Do Chorus chords)`).
  ///
  /// Handles the Guitar Songs app shapes:
  ///  - `Intro: <Am Dm E> } 3x` — one `<…>` group with a trailing repeat
  ///    and decoration after it;
  ///  - `Intro:< C G D Em  C G D 3X >2X` — a group whose inner is a full
  ///    progression (repeats allowed inside), with a trailing repeat;
  ///  - `Intro: Am Dm E` — a bare progression;
  ///  - `Intro: <G> <D>` — several single-chord groups.
  static ({String source, List<_ChordToken> tokens})? _headerChordRow(
    String rest,
  ) {
    if (rest.isEmpty) return null;
    if (rest.startsWith('<')) {
      final close = rest.indexOf('>');
      if (close > 0) {
        final inner = rest.substring(1, close);
        final innerTokens = _chordTokens(inner);
        final tail = _headerTail(rest.substring(close + 1));
        if (innerTokens != null && tail.valid) {
          return (source: inner, tokens: _withRepeat(innerTokens, tail.repeat));
        }
      }
    }
    final explicit = _explicitChordLine(rest);
    if (explicit != null) return explicit;
    final bare = _chordTokens(rest);
    return bare == null ? null : (source: rest, tokens: bare);
  }

  /// Decoration allowed after the `<…>` group of a header progression:
  /// spaces, `}`, another `>` and repeat counts (`3x`, `x2`). Anything
  /// else makes the header a note rather than a chord row.
  static ({bool valid, int? repeat}) _headerTail(String tail) {
    int? repeat;
    var i = 0;
    while (i < tail.length) {
      if (_isChordSpace(tail.codeUnitAt(i))) {
        i++;
        continue;
      }
      final start = i;
      while (i < tail.length && !_isChordSpace(tail.codeUnitAt(i))) {
        i++;
      }
      final token = tail.substring(start, i);
      if (token == '}' || token == '>') continue;
      final match = _standaloneRepeat.firstMatch(token);
      if (match == null) return (valid: false, repeat: null);
      repeat = int.parse(match.group(1) ?? match.group(2)!);
    }
    return (valid: true, repeat: repeat);
  }

  /// Gives the last chord a trailing repeat count when it has none yet;
  /// a chord that already carries one keeps its first annotation.
  static List<_ChordToken> _withRepeat(List<_ChordToken> tokens, int? repeat) {
    if (repeat == null || tokens.isEmpty || tokens.last.repeat != null) {
      return tokens;
    }
    final last = tokens.last;
    return [
      ...tokens.take(tokens.length - 1),
      (column: last.column, end: last.end, chord: last.chord, repeat: repeat),
    ];
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

  /// An explicitly marked chord line: either built solely from `<…>` groups
  /// (`<G      D     Em>` — the brackets are stripped and the spacing kept)
  /// or introduced by a `>` marker (`>   G   D` — everything after the
  /// marker is chords). Chord columns are measured on the returned chord
  /// text so they line up with the visible columns of the lyric line below.
  /// For `>` lines the marker counts as the lyric line's first column: it
  /// is replaced by an equal-width run of spaces, so chords land exactly
  /// where they were typed. Returns null when the line is not an explicit
  /// chord line, e.g. when a group contains a non-chord token (`<spoken>`)
  /// or the text after `>` is not a row of chords.
  static ({String source, List<_ChordToken> tokens})? _explicitChordLine(
    String line,
  ) {
    final marker = _gtMarker.firstMatch(line);
    if (marker != null) {
      final source = line.replaceRange(
        marker.start,
        marker.end,
        ' ' * (marker.end - marker.start),
      );
      final tokens = _chordTokens(source);
      return tokens == null ? null : (source: source, tokens: tokens);
    }
    if (!_lineOfGroupsOnly.hasMatch(line)) return null;
    final source = line.replaceAll('<', '').replaceAll('>', '');
    final tokens = _chordTokens(source);
    return tokens == null ? null : (source: source, tokens: tokens);
  }

  static _LineKind _classify(String line, ChordDetectionMode mode) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return _LineKind.text;
    if (trimmed.startsWith('{')) return _LineKind.directive;
    // Guitar tab lines are always literal text.
    if (_isTabLine(line)) return _LineKind.text;
    if (_sectionHeader.hasMatch(line) ||
        _plainSectionHeader.hasMatch(line) ||
        _bareHeader.hasMatch(line)) {
      return _LineKind.sectionHeader;
    }
    if (_explicitChordLine(line) != null) {
      return _LineKind.explicitChordLine;
    }
    // A chord-only line mixing `<…>`-wrapped and bare chords
    // (`<G> Asus4 ---x`) is explicit too — the wrapper marks it.
    if (line.contains('<') && _chordTokens(line) != null) {
      return _LineKind.explicitChordLine;
    }
    if (!mode.detectChordRows) return _LineKind.text;
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
  /// between them means the chord line stands on its own. Another chord
  /// line is never treated as lyrics either, so consecutive chord lines
  /// all render as standalone rows.
  static int? _lyricAfter(
    List<String> lines,
    List<_LineKind> classified,
    int start,
  ) {
    if (start >= lines.length) return null;
    final kind = classified[start];
    if (kind == _LineKind.consumed ||
        kind == _LineKind.directive ||
        kind == _LineKind.sectionHeader ||
        kind == _LineKind.chordLine ||
        kind == _LineKind.explicitChordLine) {
      return null;
    }
    if (lines[start].trim().isEmpty) return null;
    // Guitar tab lines are never lyric carriers — a chord line above a
    // tab block stays a standalone chord row.
    if (_isTabLine(lines[start])) return null;
    return start;
  }

  /// A guitar-tab line: `e|-----6----5----`, `D|0-----0---…`, `|----4----|`,
  /// or the leading bar omitted (`E------6---------1---`).
  static bool _isTabLine(String line) {
    final trimmed = line.trimLeft();
    if (trimmed.isEmpty) return false;
    if (RegExp(r'^[eEBGDA][#b]?\s*\|').hasMatch(trimmed)) return true;
    if (trimmed.startsWith('|') && trimmed.contains('-')) return true;
    // A string letter glued to dashes: only tab lines do this, and they
    // carry fret numbers.
    return RegExp(r'^[eEBGDA][#b]?\s*-').hasMatch(trimmed) &&
        RegExp(r'\d').hasMatch(trimmed);
  }

  /// Chord tokens of a chord-only line with their 0-based columns, or
  /// `null` when the line contains anything that is not a chord. `|`
  /// bar separators, tabs and all Unicode spaces (non-breaking spaces
  /// included, which pastes from web pages and documents love to carry)
  /// are treated as whitespace.
  ///
  /// Three extras are tolerated on chord lines:
  ///  - `<…>`-wrapped chords mixed with bare ones — `<G> Asus4 ---x` or
  ///    `<D> <Bm> A7sus4` are chord lines too; every chord stays on the
  ///    same line with the typed spacing preserved (a single chord per
  ///    group; progression groups belong to full-line group rows).
  ///  - Repeat annotations — `G(2X)`, `G(2)`, `G(x2)` attached to a chord,
  ///    or a standalone `2X` / `x2` / `×5` repeating the previous chord.
  ///  - Hold dashes — a token of dashes, optionally ending in an `x`
  ///    (`---`, `---x`), is decoration and produces no token, but its
  ///    spacing is kept in standalone chord rows.
  static List<_ChordToken>? _chordTokens(String line) {
    final tokens = <_ChordToken>[];
    var i = 0;
    while (i < line.length) {
      if (_isChordSpace(line.codeUnitAt(i))) {
        i++;
        continue;
      }
      final start = i;
      if (line.codeUnitAt(i) == 0x3C) {
        // '<' — a wrapped single chord: `<G>`, `<G(2X)>`. Columns are kept
        // as typed, so spacing to the next chord is preserved exactly.
        final close = line.indexOf('>', i + 1);
        if (close < 0) return null;
        final inner = line.substring(i + 1, close).trim();
        final attached = _attachedRepeat.firstMatch(inner);
        if (attached != null) {
          final chord = attached.group(1)!;
          if (!_fullChord.hasMatch(chord)) return null;
          tokens.add((
            column: start,
            end: close + 1,
            chord: chord,
            repeat: int.parse(attached.group(2)!),
          ));
        } else {
          // A progression group (`<G D>`) mixed with bare chords is not
          // a single chord — leave the line to the group-row logic.
          final hasInnerSpace = inner.runes.any(_isChordSpace);
          if (inner.isEmpty || hasInnerSpace || !_fullChord.hasMatch(inner)) {
            return null;
          }
          tokens.add((
            column: start,
            end: close + 1,
            chord: inner,
            repeat: null,
          ));
        }
        i = close + 1;
        continue;
      }
      while (i < line.length &&
          !_isChordSpace(line.codeUnitAt(i)) &&
          line.codeUnitAt(i) != 0x3C) {
        i++;
      }
      final token = line.substring(start, i);
      // A lone `>` is a marker, not a chord — `>Bm        >     A` marks
      // each chord group on one chord line.
      if (token == '>') continue;
      if (_isHoldDashes(token)) continue;
      final standalone = _standaloneRepeat.firstMatch(token);
      if (standalone != null) {
        // Repeats the chord before it — attach to that token so the badge
        // stays anchored to its chord however the line is rendered.
        if (tokens.isEmpty || tokens.last.repeat != null) return null;
        final previous = tokens.last;
        tokens[tokens.length - 1] = (
          column: previous.column,
          end: i,
          chord: previous.chord,
          repeat: int.parse(standalone.group(1) ?? standalone.group(2)!),
        );
        continue;
      }
      final attached = _attachedRepeat.firstMatch(token);
      if (attached != null) {
        final chord = attached.group(1)!;
        if (!_fullChord.hasMatch(chord)) return null;
        tokens.add((
          column: start,
          end: i,
          chord: chord,
          repeat: int.parse(attached.group(2)!),
        ));
        continue;
      }
      if (!_fullChord.hasMatch(token)) return null;
      tokens.add((column: start, end: i, chord: token, repeat: null));
    }
    return tokens.isEmpty ? null : tokens;
  }

  /// Inserts each chord of a chord-only line into the lyric line at the
  /// column it appeared above. Bracketed spans (`[…]`, `{…}`) in the lyric
  /// line are skipped over — columns refer to the visible lyric text only.
  static String _mapChordsOntoLyric(List<_ChordToken> tokens, String lyric) {
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
        final repeat = tokens[t].repeat;
        if (repeat != null) buffer.write('[×$repeat]');
        t++;
      }
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
  /// Repeat annotations are emitted as a marker bracket after the chord
  /// (`[G][×2]`), which the sheet renders as a badge.
  static String _bracketTokens(String line, List<_ChordToken> tokens) {
    final buffer = StringBuffer();
    var pos = 0;
    for (final token in tokens) {
      final at = token.column.clamp(0, line.length);
      if (at > pos) {
        buffer.write(line.substring(pos, at).replaceAll('|', ''));
        pos = at;
      }
      buffer.write('[${token.chord}]');
      pos = token.end;
      final repeat = token.repeat;
      if (repeat != null) buffer.write('[×$repeat]');
    }
    // Trailing decoration — hold marks (`---x`) and the spacing around
    // them — stays on the row after the last chord.
    if (pos < line.length) {
      buffer.write(line.substring(pos).replaceAll('|', ''));
    }
    return buffer.toString();
  }

  /// Detects bare chord words inside a lyric line (outside `[...]` and
  /// `{...}` spans). Tab lines are left untouched — their string letters
  /// (`B|`, `G|`…) are not chords.
  static String _inlineChords(String line, {required bool detectBare}) {
    if (!detectBare || _isTabLine(line) || !_bareChord.hasMatch(line)) {
      return line;
    }

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

enum _LineKind {
  text,
  directive,
  sectionHeader,
  chordLine,
  explicitChordLine,
  consumed,
}
