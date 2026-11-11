import 'package:chord_pro/chord_pro.dart';
import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/chords/chord_document.dart';

/// Renders a parsed ChordPro document as chords above lyrics.
///
/// Used by both the performance viewer and the editor preview.
class SongSheet extends StatelessWidget {
  const SongSheet({
    super.key,
    required this.document,
    required this.fontScale,
    required this.onChordTap,
  });

  final ChordDocument document;
  final double fontScale;
  final ValueChanged<String> onChordTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = ChordPlaneColors.of(context);
    final lyricSize = 16.0 * fontScale;
    final chordSize = 13.0 * fontScale;

    final children = <Widget>[];
    for (final section in document.song.activeSections) {
      final label = sectionLabel(section);
      final visibleLines = section.lines
          .where((line) => line.kind != LineKind.layoutBreak)
          .toList();
      if (visibleLines.isEmpty && label == null) continue;

      if (label != null) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 18, bottom: 7),
            child: Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: 11 * fontScale.clamp(1.0, 1.4),
                letterSpacing: 1.2,
                fontWeight: FontWeight.w800,
                color: colors.sectionLabel,
              ),
            ),
          ),
        );
      }

      final blocks = <Widget>[];
      final verbatim = <String>[];
      void flushVerbatim() {
        if (verbatim.isEmpty) return;
        blocks.add(
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.chordSurface.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Text(
                verbatim.join('\n'),
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12.5 * fontScale,
                  height: 1.25,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        );
        verbatim.clear();
      }

      for (final line in section.lines) {
        if (line.kind == LineKind.verbatim) {
          verbatim.add(line.verbatim ?? '');
          continue;
        }
        flushVerbatim();
        blocks.add(_buildLine(context, line, lyricSize, chordSize));
      }
      flushVerbatim();

      if (blocks.isEmpty) continue;

      if (section.kind == SectionKind.chorus) {
        children.add(
          Container(
            padding: const EdgeInsets.only(left: 12),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: theme.colorScheme.primary.withValues(alpha: 0.35),
                  width: 3,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: blocks,
            ),
          ),
        );
      } else {
        children.add(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: blocks,
          ),
        );
      }
    }

    if (children.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Text(
            'This song has no chords or lyrics yet.',
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  Widget _buildLine(
    BuildContext context,
    Line line,
    double lyricSize,
    double chordSize,
  ) {
    if (line.kind == LineKind.layoutBreak) {
      return const SizedBox(height: 14);
    }
    if (line.kind == LineKind.comment) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          line.comment ?? '',
          style: TextStyle(
            fontSize: lyricSize * 0.85,
            fontStyle: FontStyle.italic,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    if (line.kind == LineKind.image) {
      return const SizedBox.shrink();
    }

    final units = _unitsFor(line);
    if (units.isEmpty) {
      return SizedBox(height: lyricSize * 1.35);
    }

    final hasChords = units.any((unit) => unit.chord != null);
    final theme = Theme.of(context);
    final colors = ChordPlaneColors.of(context);

    if (!hasChords) {
      return Padding(
        padding: EdgeInsets.only(bottom: 2 * fontScale),
        child: Text(
          units.map((unit) => unit.text).join(),
          style: TextStyle(
            fontSize: lyricSize,
            height: 1.38,
            color: theme.colorScheme.onSurface,
          ),
        ),
      );
    }

    final chordStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: chordSize,
      height: 1.1,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.2,
      color: colors.chord,
    );
    final lyricStyle = TextStyle(
      fontSize: lyricSize,
      height: 1.38,
      color: theme.colorScheme.onSurface,
    );

    return Padding(
      padding: EdgeInsets.only(bottom: 3 * fontScale),
      child: Wrap(
        spacing: 0,
        runSpacing: 0,
        children: [
          for (final unit in units)
            _ChordUnit(
              unit: unit,
              chordStyle: chordStyle,
              lyricStyle: lyricStyle,
              chordRowHeight: chordSize * 1.55,
              onChordTap: onChordTap,
            ),
        ],
      ),
    );
  }

  List<_Unit> _unitsFor(Line line) {
    final units = <_Unit>[];
    String? pendingChord;

    for (final token in line.tokens) {
      switch (token) {
        case ChordToken():
          if (pendingChord != null) {
            units.add(_Unit(chord: pendingChord, text: ''));
          }
          pendingChord = token.chord?.raw ?? token.raw;
        case TextToken():
          final chunks = _splitIntoWordChunks(token.text);
          if (chunks.isEmpty) continue;
          for (var i = 0; i < chunks.length; i++) {
            final isFirst = i == 0;
            if (chunks.length == 1 && chunks[i].trim().isEmpty) {
              if (pendingChord != null) {
                units.add(_Unit(chord: pendingChord, text: chunks[i]));
                pendingChord = null;
              } else if (units.isNotEmpty) {
                units.last.text += chunks[i];
              }
              continue;
            }
            units.add(
              _Unit(chord: isFirst ? pendingChord : null, text: chunks[i]),
            );
            if (isFirst) pendingChord = null;
          }
        case AnnotationToken():
          units.add(_Unit(chord: pendingChord, text: '*${token.text}'));
          pendingChord = null;
        case ChordRecallToken():
          break;
        case InlineDirectiveToken():
          break;
      }
    }

    if (pendingChord != null) {
      units.add(_Unit(chord: pendingChord, text: ''));
    }
    return units;
  }

  /// Splits a lyric token into word chunks while keeping the spaces that
  /// surround them, so wrapping never inserts stray gaps.
  static List<String> _splitIntoWordChunks(String text) {
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

  static bool _isSpace(int codeUnit) =>
      codeUnit == 0x20 || codeUnit == 0x09 || codeUnit == 0x0A;
}

class _Unit {
  _Unit({this.chord, required this.text});

  final String? chord;
  String text;
}

class _ChordUnit extends StatelessWidget {
  const _ChordUnit({
    required this.unit,
    required this.chordStyle,
    required this.lyricStyle,
    required this.chordRowHeight,
    required this.onChordTap,
  });

  final _Unit unit;
  final TextStyle chordStyle;
  final TextStyle lyricStyle;
  final double chordRowHeight;
  final ValueChanged<String> onChordTap;

  @override
  Widget build(BuildContext context) {
    final chord = unit.chord;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: chordRowHeight,
          child: chord == null
              ? null
              : InkWell(
                  onTap: () => onChordTap(chord),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 3),
                    child: Text(chord, style: chordStyle),
                  ),
                ),
        ),
        Text(unit.text, style: lyricStyle),
      ],
    );
  }
}
