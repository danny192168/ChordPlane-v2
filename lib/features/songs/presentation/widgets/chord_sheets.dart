import 'dart:math' as math;

import 'package:chord_diagrams/chord_diagrams.dart';
import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';

int? _diagramThemeKey;

/// The native diagram renderer has a single global palette. Only push a new
/// palette when the theme actually changes so the SVG cache stays warm.
void _ensureDiagramTheme(BuildContext context) {
  final colors = ChordPlaneColors.of(context);
  final key = Object.hash(
    colors.diagramGrid,
    colors.diagramDot,
    colors.diagramFingerText,
    colors.chordSurface,
    Theme.of(context).colorScheme.surfaceContainerLow,
  );
  if (_diagramThemeKey == key) return;
  _diagramThemeKey = key;
  applyChordDiagramTheme(context);
}

int _positionCount(String chord, Instrument instrument) {
  try {
    return ChordDiagrams.getPositionCount(chord, instrument: instrument);
  } catch (_) {
    return 0;
  }
}

Future<void> showChordVoicingsSheet(
  BuildContext context, {
  required String chord,
  required Instrument instrument,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) =>
        _ChordVoicingsSheet(chord: chord, instrument: instrument),
  );
}

Future<void> showSongChordsSheet(
  BuildContext context, {
  required List<String> chords,
  required Instrument instrument,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.82,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      builder: (context, controller) =>
          _AllChordsSheet(
            chords: chords,
            instrument: instrument,
            controller: controller,
          ),
    ),
  );
}

class _ChordVoicingsSheet extends StatelessWidget {
  const _ChordVoicingsSheet({required this.chord, required this.instrument});

  final String chord;
  final Instrument instrument;

  @override
  Widget build(BuildContext context) {
    _ensureDiagramTheme(context);
    final count = _positionCount(chord, instrument);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                chord,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                instrument == Instrument.guitar ? 'Guitar' : 'Ukulele',
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (count == 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 34),
              child: Text(
                'No diagram is available for this chord.',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
            )
          else
            SizedBox(
              height: 270,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(top: 10, bottom: 8),
                itemCount: count,
                separatorBuilder: (_, _) => const SizedBox(width: 14),
                itemBuilder: (context, index) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ChordDiagram(
                      chord: chord,
                      instrument: instrument,
                      position: index,
                      width: 158,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Voicing ${index + 1}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AllChordsSheet extends StatelessWidget {
  const _AllChordsSheet({
    required this.chords,
    required this.instrument,
    required this.controller,
  });

  final List<String> chords;
  final Instrument instrument;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    _ensureDiagramTheme(context);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Row(
            children: [
              Text(
                'Chords in this song',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Text(
                '${chords.length}',
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
            itemCount: chords.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final chord = chords[index];
              return _AllChordsCard(
                chord: chord,
                instrument: instrument,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _AllChordsCard extends StatelessWidget {
  const _AllChordsCard({required this.chord, required this.instrument});

  final String chord;
  final Instrument instrument;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = _positionCount(chord, instrument);
    final shown = math.min(count, 4);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                chord,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              if (count > 4)
                Text(
                  '+${count - 4} more',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (count == 0)
            Text(
              'No diagram available',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 8,
              children: [
                for (var i = 0; i < shown; i++)
                  ChordDiagram(
                    chord: chord,
                    instrument: instrument,
                    position: i,
                    width: 100,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
