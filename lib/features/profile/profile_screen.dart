import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/auth_gateway.dart';
import '../../core/auth/google_auth.dart';
import '../../core/config/app_config.dart';
import '../sharing/cloud/auth_gate_sheet.dart';
import '../songs/data/song_providers.dart';

/// Account surface. Guests stay fully local and get the default avatar — no
/// generated image until they actually sign in.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final signedIn =
        ref.watch(signedInProvider).value ??
        ref.read(authGatewayProvider).isSignedIn;
    final localName = ref.watch(profileNameProvider).trim();
    final profile = ref.watch(profileInfoProvider).value;
    final seed = localName.isNotEmpty
        ? localName
        : (profile?.username.trim().isNotEmpty == true
              ? profile!.username.trim()
              : (profile?.email.trim().isNotEmpty == true
                    ? profile!.email.trim()
                    : 'ChordPlane'));
    final avatarUrl =
        'https://api.dicebear.com/10.x/initial-face/svg?seed=${Uri.encodeComponent(seed)}';
    final mySongs = ref.watch(mySongsProvider).value?.length;
    final favorites = ref.watch(favoriteSongsProvider).value?.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            onPressed: () => context.push('/settings'),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          Center(
            child: Container(
              width: 124,
              height: 124,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                shape: BoxShape.circle,
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              clipBehavior: Clip.antiAlias,
              child: signedIn
                  ? SvgPicture.network(
                      avatarUrl,
                      fit: BoxFit.cover,
                      placeholderBuilder: (_) => Icon(
                        Icons.person_outline,
                        size: 58,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    )
                  : Icon(
                      Icons.person_outline,
                      size: 58,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            signedIn ? 'Your profile' : 'Guest profile',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            signedIn
                ? 'Signed in · favorites and publishing are available'
                : 'Sign in to unlock more features',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          if (signedIn) ...[
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    icon: Icons.library_music_outlined,
                    label: 'My Songs',
                    value: mySongs?.toString() ?? '—',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatCard(
                    icon: Icons.favorite_outline,
                    label: 'Favorites',
                    value: favorites?.toString() ?? '—',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Center(
              child: OutlinedButton.icon(
                onPressed: () => _signOut(context, ref),
                icon: const Icon(Icons.logout),
                label: const Text('Sign out'),
              ),
            ),
          ] else
            Center(
              child: FilledButton.icon(
                onPressed: () => showSignInGate(context),
                icon: const Icon(Icons.login),
                label: const Text('Sign in to unlock more features'),
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
    context.go('/');
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        child: Column(
          children: [
            Icon(icon, color: theme.colorScheme.primary),
            const SizedBox(height: 6),
            Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
