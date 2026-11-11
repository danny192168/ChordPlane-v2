import 'package:chord_diagrams/chord_diagrams.dart' show Instrument;
import 'package:chord_pro/chord_pro.dart' show AccidentalPreference;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings/settings.dart';
import '../songs/data/song_repository.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final controller = ref.read(settingsProvider.notifier);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: [
          const _SectionLabel('Appearance'),
          _Card(
            child: Column(
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  title: const Text('Theme'),
                  subtitle: const Text('Follow the system or pick a side'),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                  child: SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<ThemeMode>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: ThemeMode.system,
                          icon: Icon(Icons.brightness_auto, size: 18),
                          label: Text('System'),
                        ),
                        ButtonSegment(
                          value: ThemeMode.light,
                          icon: Icon(Icons.light_mode, size: 18),
                          label: Text('Light'),
                        ),
                        ButtonSegment(
                          value: ThemeMode.dark,
                          icon: Icon(Icons.dark_mode, size: 18),
                          label: Text('Dark'),
                        ),
                      ],
                      selected: {settings.themeMode},
                      onSelectionChanged: (value) =>
                          controller.setThemeMode(value.first),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const _SectionLabel('Instrument'),
          _Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<Instrument>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: Instrument.guitar,
                      icon: Icon(Icons.music_note, size: 18),
                      label: Text('Guitar'),
                    ),
                    ButtonSegment(
                      value: Instrument.ukulele,
                      icon: Icon(Icons.music_note_outlined, size: 18),
                      label: Text('Ukulele'),
                    ),
                  ],
                  selected: {settings.instrument},
                  onSelectionChanged: (value) =>
                      controller.setInstrument(value.first),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const _SectionLabel('Chord spelling'),
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: Text(
                    'Use sharps or flats when transposing. ChordPlane follows the song key where it can.',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
                  child: SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<AccidentalPreference>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: AccidentalPreference.sharps,
                          label: Text('Sharps (C♯)'),
                        ),
                        ButtonSegment(
                          value: AccidentalPreference.flats,
                          label: Text('Flats (D♭)'),
                        ),
                      ],
                      selected: {settings.accidentals},
                      onSelectionChanged: (value) =>
                          controller.setAccidentals(value.first),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const _SectionLabel('Reading'),
          _Card(
            child: Column(
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                  title: const Text('Text size'),
                  trailing: Text(
                    '${(settings.textScale * 100).round()}%',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                  child: Row(
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Text('A', style: TextStyle(fontSize: 12)),
                      ),
                      Expanded(
                        child: Slider(
                          value: settings.textScale,
                          min: 0.7,
                          max: 2,
                          divisions: 13,
                          onChanged: controller.setTextScale,
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: Text('A', style: TextStyle(fontSize: 22)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const _SectionLabel('Library'),
          _Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.auto_awesome_outlined),
                  title: const Text('Add demo songs'),
                  subtitle: const Text('Public-domain classics to try the app'),
                  onTap: () async {
                    final added = await ref
                        .read(songRepositoryProvider)
                        .addDemoSongs();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          added == 0
                              ? 'Demo songs are already in your library'
                              : 'Added $added demo songs',
                        ),
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
                const ListTile(
                  leading: Icon(Icons.cloud_off_outlined),
                  title: Text('Local mode'),
                  subtitle: Text(
                    'Songs live on this device. Clerk accounts and cloud sync arrive in the next step.',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const _SectionLabel('About'),
          _Card(
            child: const Column(
              children: [
                ListTile(
                  leading: Icon(Icons.piano_outlined),
                  title: Text('ChordPlane'),
                  subtitle: Text('Version 1.0.0 · Phase 1 local build'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: child,
    );
  }
}
