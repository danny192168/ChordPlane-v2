import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/song_tile.dart';
import '../data/song_providers.dart';

class ArtistScreen extends ConsumerWidget {
  const ArtistScreen({
    super.key,
    required this.slug,
    this.favoritesOnly = false,
    this.savedOnly = false,
  });

  final String slug;
  final bool favoritesOnly;
  final bool savedOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songs = favoritesOnly
        ? ref.watch(favoriteArtistSongsProvider(slug))
        : savedOnly
        ? ref.watch(savedArtistSongsProvider(slug))
        : ref.watch(artistSongsProvider(slug));
    final theme = Theme.of(context);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            title: Text(
              songs.value?.isNotEmpty == true
                  ? (songs.value!.first.song.artist.trim().isEmpty
                        ? 'Unknown artist'
                        : songs.value!.first.song.artist)
                  : (favoritesOnly
                        ? 'Favorites'
                        : savedOnly
                        ? 'Saved'
                        : 'Artist'),
            ),
          ),
          songs.when(
            loading: () => const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, stack) => SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: Text('$error')),
            ),
            data: (items) {
              if (items.isEmpty) {
                return SliverFillRemaining(
                  hasScrollBody: false,
                  child: SongListEmpty(
                    title: 'No songs found',
                    message: favoritesOnly
                        ? 'No hearted songs by this artist yet.'
                        : savedOnly
                        ? 'No saved songs by this artist yet.'
                        : 'This artist has no songs in your library.',
                  ),
                );
              }
              return SliverMainAxisGroup(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
                      child: Text(
                        '${items.length} ${items.length == 1 ? 'song' : 'songs'}',
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  SliverList.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) => Divider(
                      height: 1,
                      indent: 16,
                      endIndent: 16,
                      color: theme.colorScheme.outlineVariant,
                    ),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return SongTile(
                        item: item,
                        onTap: () => context.push('/song/${item.song.id}'),
                      );
                    },
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 40)),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
