import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_gateway.dart';
import '../../core/utils/relative_time.dart';
import '../../shared/widgets/profile_avatar.dart';
import '../community/data/community_api.dart';
import '../community/data/community_providers.dart';
import '../community/presentation/edit_profile_sheet.dart';
import '../sharing/cloud/auth_gate_sheet.dart';
import '../songs/data/song_providers.dart';
import '../songs/data/song_repository.dart';
import 'widgets/profile_empty_state.dart';
import 'widgets/profile_song_row.dart';

/// Compact account surface: identity at the top, then two lazily built panels
/// (Published and Favorites). Settings and sign-out live in Settings, not here.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final Set<int> _visited = {0};
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final signedIn =
        ref.watch(signedInProvider).value ??
        ref.read(authGatewayProvider).isSignedIn;
    final localName = ref.watch(profileNameProvider).trim();
    final profile = ref.watch(profileInfoProvider).value;
    final seed = profileAvatarSeed(
      localName: localName,
      username: profile?.username,
      email: profile?.email,
    );
    final username = profile?.username.trim() ?? '';
    final displayName =
        profile?.displayName.trim().isNotEmpty == true
        ? profile!.displayName.trim()
        : localName;
    final heading = !signedIn
        ? 'Guest profile'
        : displayName.isNotEmpty
        ? displayName
        : username.isNotEmpty
        ? '@$username'
        : 'Your profile';
    final handle = signedIn && username.isNotEmpty ? '@$username' : '';

    final publishedCount = ref.watch(myPublishedCountProvider).value;
    final favoriteCount = ref.watch(favoriteItemsProvider).value?.length;

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: 'Settings',
            onPressed: () => context.push('/settings'),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          // The header column stretches its children to full width; Center
          // gives the avatar loose constraints so it stays a fixed 112px
          // circle instead of being clamped to the screen width.
          Center(
            child: ProfileAvatar(seed: seed, size: 112, signedIn: signedIn),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  heading,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 2),
              IconButton(
                tooltip: 'Edit display name',
                onPressed: () => showEditProfileSheet(context),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                icon: const Icon(Icons.edit_outlined, size: 17),
              ),
            ],
          ),
          if (handle.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                handle,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
            ),
          const SizedBox(height: 16),
          if (signedIn)
            TabBar(
              controller: _tabs,
              dividerHeight: 0,
              labelColor: scheme.primary,
              unselectedLabelColor: scheme.onSurfaceVariant,
              labelStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              indicator: UnderlineTabIndicator(
                borderSide: BorderSide(width: 2, color: scheme.primary),
                insets: const EdgeInsets.symmetric(horizontal: 20),
              ),
              onTap: (index) {
                setState(() {
                  _visited.add(index);
                  _tab = index;
                });
              },
              tabs: [
                _tabLabel('Published', publishedCount),
                _tabLabel('Favorites', favoriteCount),
              ],
            ),
          Expanded(
            child: !signedIn
                ? _guestPanel(context)
                : IndexedStack(
                    index: _tab,
                    children: [
                      if (_visited.contains(0))
                        const _PublishedPanel()
                      else
                        const SizedBox.shrink(),
                      if (_visited.contains(1))
                        const _FavoritesPanel()
                      else
                        const SizedBox.shrink(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _tabLabel(String label, int? count) {
    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          if (count != null) ...[
            const SizedBox(width: 6),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _guestPanel(BuildContext context) {
    return Center(
      child: FilledButton.icon(
        onPressed: () => showSignInGate(context),
        icon: const Icon(Icons.login),
        label: const Text('Sign in to publish and sync favorites'),
      ),
    );
  }
}

class _PublishedPanel extends ConsumerWidget {
  const _PublishedPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uploads = ref.watch(myUploadsProvider);
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(myUploadsProvider);
        await ref.read(myUploadsProvider.future);
      },
      child: uploads.when(
        loading: () => _scrollable(const Center(
          child: CircularProgressIndicator(),
        )),
        error: (error, _) => _scrollable(
          _PanelError(
            message: '$error',
            onRetry: () => ref.invalidate(myUploadsProvider),
          ),
        ),
        data: (songs) {
          if (songs.isEmpty) {
            return _scrollable(
              ProfileEmptyState(
                icon: Icons.publish_outlined,
                title: 'No uploads yet',
                message: 'Publish a song from its menu to see it here.',
                actionLabel: 'Browse library',
                onAction: () => context.go('/'),
              ),
            );
          }
          return ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 24),
            itemCount: songs.length,
            itemBuilder: (context, index) {
              final song = songs[index];
              return ProfileSongRow(
                title: song.title,
                artist: song.artist,
                musicalKey: song.originalKey,
                age: relativeTime(song.createdAt),
                onTap: () => _openUpload(context, ref, song),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _openUpload(
    BuildContext context,
    WidgetRef ref,
    CommunitySong song,
  ) async {
    final local = await ref.read(songRepositoryProvider).byRemoteId(song.id);
    if (!context.mounted) return;
    if (local != null) {
      context.push('/song/${local.id}');
    } else {
      context.push('/community/${Uri.encodeComponent(song.id)}');
    }
  }
}

class _FavoritesPanel extends ConsumerWidget {
  const _FavoritesPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(favoriteItemsProvider);
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(favoriteItemsProvider);
        await ref.read(favoriteItemsProvider.future);
      },
      child: items.when(
        loading: () => _scrollable(const Center(
          child: CircularProgressIndicator(),
        )),
        error: (error, _) => _scrollable(
          _PanelError(
            message: '$error',
            onRetry: () => ref.invalidate(favoriteItemsProvider),
          ),
        ),
        data: (favorites) {
          if (favorites.isEmpty) {
            return _scrollable(
              ProfileEmptyState(
                icon: Icons.favorite_border,
                title: 'No favorites yet',
                message: 'Tap the heart on any song to keep it here.',
                actionLabel: 'Browse library',
                onAction: () => context.go('/'),
              ),
            );
          }
          return ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 24),
            itemCount: favorites.length,
            itemBuilder: (context, index) {
              final item = favorites[index];
              return ProfileSongRow(
                title: item.song.title,
                artist: item.song.artist,
                musicalKey: item.song.originalKey,
                age: relativeTime(item.favoritedAt),
                onTap: () => context.push('/song/${item.song.id}'),
              );
            },
          );
        },
      ),
    );
  }
}

/// Keeps loading/empty/error states scrollable so pull-to-refresh still works.
Widget _scrollable(Widget child) {
  return LayoutBuilder(
    builder: (context, constraints) => ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: constraints.maxHeight - 1, child: child),
      ],
    ),
  );
}

class _PanelError extends StatelessWidget {
  const _PanelError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 40),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 14),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
