import 'package:flutter/foundation.dart';

/// One suspicious character found in pasted text.
@immutable
class HiddenCharFinding {
  const HiddenCharFinding({required this.line, required this.code});

  /// 1-based line number in the text.
  final int line;

  /// Unicode code unit of the character.
  final int code;

  /// Display tag, e.g. `<U+00A0>`.
  String get tag =>
      '<U+${code.toRadixString(16).toUpperCase().padLeft(4, '0')}>';
}

/// Scans pasted text for invisible and look-alike characters that break
/// chord detection, and sanitizes them away.
///
/// Chord sheets copied from other apps (Guitar Songs, WhatsApp, PDFs,
/// web pages) routinely carry characters that *look* like normal text but
/// are not: non-breaking spaces instead of spaces, zero-width spaces
/// glued to chord names, fullwidth `＞` instead of `>`, line separators
/// instead of newlines. A chord line carrying any of these fails to
/// parse, while the same line retyped by hand — always clean ASCII —
/// works. This class both finds them ([scan]) and removes them
/// ([sanitize]).
abstract final class TextDiagnostics {
  /// True for characters that are invisible, or that merely *look* like
  /// spaces or angle brackets but are different code points.
  static bool isSuspicious(int code) {
    return code == 0x00AD || // soft hyphen
        code == 0x00A0 || // non-breaking space
        code == 0x1680 || // Ogham space mark
        code == 0x180E || // Mongolian vowel separator
        (code >= 0x2000 && code <= 0x200F) || // thin spaces, ZWSP/ZWNJ/ZWJ,
        //                                       left-to-right marks
        code == 0x2028 || // line separator
        code == 0x2029 || // paragraph separator
        code == 0x202F || // narrow no-break space
        code == 0x205F || // medium mathematical space
        (code >= 0x2060 && code <= 0x2064) || // word joiner, invisible ops
        code == 0xFEFF || // BOM / zero-width no-break space
        code == 0xFF1C || // fullwidth ＜
        code == 0xFF1E || // fullwidth ＞
        code == 0x3000; // ideographic space
  }

  /// Characters that occupy no space at all — removed outright.
  static bool _isInvisible(int code) {
    return code == 0x00AD ||
        code == 0x180E ||
        (code >= 0x200B && code <= 0x200F) ||
        (code >= 0x2060 && code <= 0x2064) ||
        code == 0xFEFF;
  }

  /// Returns [body] with every suspicious character replaced by its plain
  /// equivalent: Unicode spaces become regular spaces, fullwidth angle
  /// brackets become ASCII ones, line/paragraph separators become
  /// newlines, and zero-width characters are dropped. Safe to run on any
  /// text — it never alters visible characters.
  static String sanitize(String body) {
    final buffer = StringBuffer();
    for (final ch in body.runes) {
      if (ch == 0x2028 || ch == 0x2029) {
        buffer.write('\n');
      } else if (ch == 0xFF1C) {
        buffer.write('<');
      } else if (ch == 0xFF1E) {
        buffer.write('>');
      } else if (_isInvisible(ch)) {
        continue;
      } else if (isSuspicious(ch)) {
        buffer.write(' ');
      } else {
        buffer.writeCharCode(ch);
      }
    }
    return buffer.toString();
  }

  /// All suspicious characters in [body], in order.
  static List<HiddenCharFinding> scan(String body) {
    final findings = <HiddenCharFinding>[];
    var line = 1;
    for (final ch in body.runes) {
      if (ch == 0x0A) {
        line++;
        continue;
      }
      if (ch == 0x0D) continue;
      if (isSuspicious(ch)) {
        findings.add(HiddenCharFinding(line: line, code: ch));
      }
    }
    return findings;
  }

  /// Renders [lineText] with every suspicious character replaced by a
  /// visible `<U+XXXX>` tag (and tabs by `<TAB>`), so they can be read.
  static String reveal(String lineText) {
    final buffer = StringBuffer();
    for (final ch in lineText.runes) {
      if (isSuspicious(ch)) {
        final hex = ch.toRadixString(16).toUpperCase().padLeft(4, '0');
        buffer.write('<U+$hex>');
      } else if (ch == 0x09) {
        buffer.write('<TAB>');
      } else {
        buffer.writeCharCode(ch);
      }
    }
    return buffer.toString();
  }
}
