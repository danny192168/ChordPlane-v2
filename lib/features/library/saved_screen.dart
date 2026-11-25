import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/widgets/artist_list.dart';
import '../../shared/widgets/profile_avatar_button.dart';
import '../../shared/widgets/song_tile.dart';
import '../songs/data/song_providers.dart';

/// The offline shelf: created, edited, opened, and downloaded songs.
/// Background search cache is deliberately excluded.
class SavedScreen extends ConsumerWidget {
  const SavedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artists = ref.watch(savedArtistsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved'),
        actions: const [ProfileAvatarButton()],
      ),
      body: artists.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => SongListEmpty(
          title: 'Could not load saved songs',
          message: '$error',
        ),
        data: (items) => ArtistTileList(
          artists: items,
          onTap: (artist) => context.push(
            '/artist/${Uri.encodeComponent(artist.slug)}?saved=1',
          ),
          emptyTitle: 'Nothing saved yet',
          emptyMessage:
              'Songs you create, edit, open, or download appear here and work '
              'offline.',
          emptyAction: FilledButton.icon(
            onPressed: () => context.push('/editor'),
            icon: const Icon(Icons.add),
            label: const Text('New song'),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'saved-fab',
        onPressed: () => context.push('/editor'),
        icon: const Icon(Icons.add),
        label: const Text('New song'),
      ),
    );
  }
}
