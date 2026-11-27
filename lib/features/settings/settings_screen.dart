import 'package:chord_diagrams/chord_diagrams.dart' show Instrument;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/auth_gateway.dart';
import '../../core/auth/google_auth.dart';
import '../../core/chords/chord_detection.dart';
import '../../core/config/app_config.dart';
import '../../core/settings/settings.dart';
import '../community/data/community_providers.dart';
import '../sharing/cloud/auth_gate_sheet.dart';
import '../songs/data/song_providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final controller = ref.read(settingsProvider.notifier);
    final theme = Theme.of(context);
    final signedIn =
        ref.watch(signedInProvider).value ??
        ref.read(authGatewayProvider).isSignedIn;
    final profile = ref.watch(profileInfoProvider).value;
    final localName = ref.watch(profileNameProvider).trim();
    final accountName =
        profile?.displayName.trim().isNotEmpty == true
        ? profile!.displayName.trim()
        : localName.isNotEmpty
        ? localName
        : 'ChordPlane account';
    final accountHandle = profile?.username.trim() ?? '';

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
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Default detection',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<ChordDetectionMode>(
                    initialValue: settings.defaultChordDetectionMode,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    items: [
                      for (final mode in ChordDetectionMode.values)
                        DropdownMenuItem(value: mode, child: Text(mode.label)),
                    ],
                    onChanged: (mode) {
                      if (mode == null) return;
                      controller.setDefaultChordDetectionMode(mode);
                    },
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${settings.defaultChordDetectionMode.description} '
                    'New songs start with this mode; each song can override '
                    'it while editing.',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
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
          const _SectionLabel('Sharing'),
          _Card(
            child: Column(
              children: [
                if (AppConfig.hasSupabase &&
                    AppConfig.supabaseInitError == null)
                  ListTile(
                    leading: const Icon(Icons.link),
                    title: const Text('My shared links'),
                    subtitle: const Text(
                      'View counts, update shared copies, revoke',
                    ),
                    onTap: () => context.push('/my-shares'),
                  )
                else
                  const ListTile(
                    leading: Icon(Icons.link),
                    title: Text('My shared links'),
                    subtitle: Text('Needs cloud sharing to be configured'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const _SectionLabel('Account'),
          _Card(
            child: Column(
              children: [
                if (signedIn) ...[
                  ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: Text(accountName),
                    subtitle: accountHandle.isEmpty
                        ? const Text('Signed in')
                        : Text('@$accountHandle'),
                  ),
                  ListTile(
                    leading: Icon(Icons.logout, color: theme.colorScheme.error),
                    title: Text(
                      'Sign out',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                    onTap: () => _signOut(context, ref),
                  ),
                ] else
                  ListTile(
                    leading: const Icon(Icons.login),
                    title: const Text('Sign in'),
                    subtitle: const Text('Publish songs and sync favorites'),
                    onTap: () => showSignInGate(context),
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
                  subtitle: Text('Version 1.3.0 · local-first songbook'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final cloudReady =
        AppConfig.hasSupabase && AppConfig.supabaseInitError == null;
    if (cloudReady) {
      await Supabase.instance.client.auth.signOut();
      await const GoogleAuth().signOut();
    }
    if (!context.mounted) return;
    ref.invalidate(profileInfoProvider);
    ref.invalidate(myUploadsProvider);
    context.go('/');
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
        border: Border.all(color: scheme.outlineVariant),
      ),
      // Tiles need their own ink surface: the decorated container would
      // otherwise paint over their splash and fail the ListTile assertion.
      child: Material(type: MaterialType.transparency, child: child),
    );
  }
}
