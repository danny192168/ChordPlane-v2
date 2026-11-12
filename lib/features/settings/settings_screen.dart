import 'package:chord_diagrams/chord_diagrams.dart' show Instrument;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/auth_gateway.dart';
import '../../core/config/app_config.dart';
import '../../core/settings/settings.dart';
import '../sharing/cloud/auth_gate_sheet.dart';
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
          const _SectionLabel('Chord input'),
          _Card(
            child: SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              value: settings.detectBareChords,
              onChanged: controller.setDetectBareChords,
              title: const Text('Detect chords without < >'),
              subtitle: const Text(
                'Ultimate-Guitar-style chord lines above lyrics and bare '
                'chord words are picked up as chords. Turn this off if '
                'lyrics are misread, and wrap chords in < > instead — '
                'e.g. <G> or <G D Em C>.',
              ),
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
                _AccountTile(),
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

class _AccountTile extends ConsumerWidget {
  const _AccountTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!AppConfig.hasSupabase) {
      return const ListTile(
        leading: Icon(Icons.cloud_off_outlined),
        title: Text('Local mode'),
        subtitle: Text('Cloud sharing is not enabled in this build.'),
      );
    }
    if (AppConfig.supabaseInitError != null) {
      return ListTile(
        leading: const Icon(Icons.cloud_alert_outlined),
        title: const Text('Cloud setup failed'),
        subtitle: Text(AppConfig.supabaseInitError!),
      );
    }
    final signedIn = ref.watch(signedInProvider).value ?? false;
    if (!signedIn) {
      return ListTile(
        leading: const Icon(Icons.person_add_alt_1_outlined),
        title: const Text('Sign in'),
        subtitle: const Text('Needed for cloud share links'),
        onTap: () => showSignInGate(context),
      );
    }
    final gateway = ref.read(authGatewayProvider);
    final email = gateway.currentUserEmail ?? 'your account';
    return ListTile(
      leading: const Icon(Icons.person_outline),
      title: Text('Signed in as $email'),
      subtitle: const Text('Cloud share links enabled'),
      trailing: TextButton(
        onPressed: () async {
          await Supabase.instance.client.auth.signOut();
        },
        child: const Text('Sign out'),
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
