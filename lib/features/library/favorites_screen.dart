import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/widgets/artist_list.dart';
import '../../shared/widgets/profile_avatar_button.dart';
import '../../shared/widgets/song_tile.dart';
import '../songs/data/song_providers.dart';

/// Hearted songs grouped by artist. Favorites sync with the signed-in account.
class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artists = ref.watch(favoriteArtistsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Favorites'),
        actions: const [ProfileAvatarButton()],
      ),
      body: artists.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => SongListEmpty(
          title: 'Could not load favorites',
          message: '$error',
        ),
        data: (items) => ArtistTileList(
          artists: items,
          onTap: (artist) => context.push(
            '/artist/${Uri.encodeComponent(artist.slug)}?favorites=1',
          ),
          emptyTitle: 'No favorites yet',
          emptyMessage:
              'Tap the heart on any song to group it here by artist.',
        ),
      ),
    );
  }
}
