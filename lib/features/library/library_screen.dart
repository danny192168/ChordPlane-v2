import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../shared/widgets/song_tile.dart';
import '../songs/data/song_providers.dart';
import '../songs/data/song_repository.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seed = ref.watch(demoSeedProvider);
    final songs = ref.watch(libraryProvider);
    final artists = ref.watch(artistsProvider);
    final filter = ref.watch(libraryFilterProvider);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SvgPicture.asset(
                    'assets/logo.svg',
                    width: 28,
                    height: 28,
                  ),
                ),
                const SizedBox(width: 10),
                const Text('ChordPlane'),
              ],
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: Row(
                children: [
                  ChoiceChip(
                    label: const Text('Artists'),
                    selected: filter == LibraryFilter.artists,
                    onSelected: (_) => ref
                        .read(libraryFilterProvider.notifier)
                        .set(LibraryFilter.artists),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Favorites'),
                    showCheckmark: false,
                    avatar: const Icon(Icons.favorite, size: 15),
                    selected: filter == LibraryFilter.favorites,
                    onSelected: (_) => ref
                        .read(libraryFilterProvider.notifier)
                        .set(LibraryFilter.favorites),
                  ),
                  const Spacer(),
                  if (filter == LibraryFilter.favorites && songs.hasValue)
                    Text(
                      '${songs.requireValue.length}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (seed.isLoading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            )
          else
            switch (filter) {
              LibraryFilter.artists => _buildArtists(
                context,
                ref,
                artists,
                songs,
              ),
              LibraryFilter.favorites => _buildSongList(
                context,
                ref,
                songs,
                emptyTitle: 'No favorites yet',
                emptyMessage:
                    'Tap the heart on any song to keep it close at hand.',
                emptyAction: FilledButton.tonal(
                  onPressed: () => ref
                      .read(libraryFilterProvider.notifier)
                      .set(LibraryFilter.artists),
                  child: const Text('Browse artists'),
                ),
              ),
            },
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/editor'),
        icon: const Icon(Icons.add),
        label: const Text('New song'),
      ),
    );
  }

  /// The default library view: songs surfaced through the artists that
  /// recorded them.
  Widget _buildArtists(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<ArtistSummary>> artists,
    AsyncValue<List<SongListItem>> songs,
  ) {
    if (artists.isLoading) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (artists.hasValue && artists.value!.isEmpty) {
      final libraryEmpty = !songs.hasValue || songs.value!.isEmpty;
      return SliverFillRemaining(
        hasScrollBody: false,
        child: SongListEmpty(
          title: libraryEmpty ? 'Your songbook is empty' : 'No artists yet',
          message: libraryEmpty
              ? 'Write your first song with chords and lyrics, or load a few '
                    'public-domain classics to try the app.'
              : 'Add an artist name to a song and they will appear here.',
          action: libraryEmpty ? _emptyLibraryActions(ref) : null,
          leading: SvgPicture.asset(
            'assets/logo.svg',
            width: 92,
            height: 92,
          ),
        ),
      );
    }
    return artists.when(
      error: (error, stack) => SliverFillRemaining(
        hasScrollBody: false,
        child: SongListEmpty(title: 'Could not load artists', message: '$error'),
      ),
      loading: () => const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: CircularProgressIndicator()),
      ),
      data: (items) => SliverPadding(
        padding: const EdgeInsets.only(bottom: 110),
        sliver: SliverList.separated(
          itemCount: items.length,
          separatorBuilder: (_, _) => Divider(
            height: 1,
            indent: 76,
            endIndent: 16,
            color: Theme.of(context).colorScheme.outlineVariant.withValues(
              alpha: 0.3,
            ),
          ),
          itemBuilder: (context, index) {
            final artist = items[index];
            return ListTile(
              onTap: () => context.push('/artist/${artist.slug}'),
              leading: CircleAvatar(
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.secondaryContainer,
                child: Text(
                  artist.name.isEmpty ? '?' : artist.name[0].toUpperCase(),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
              title: Text(
                artist.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                '${artist.songCount} ${artist.songCount == 1 ? 'song' : 'songs'}',
              ),
              trailing: const Icon(Icons.chevron_right),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSongList(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<SongListItem>> songs, {
    required String emptyTitle,
    required String emptyMessage,
    Widget? emptyAction,
  }) {
    return songs.when(
      loading: () => const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, stack) => SliverFillRemaining(
        hasScrollBody: false,
        child: SongListEmpty(
          title: 'Could not load your library',
          message: '$error',
        ),
      ),
      data: (items) => items.isEmpty
          ? SliverFillRemaining(
              hasScrollBody: false,
              child: SongListEmpty(
                title: emptyTitle,
                message: emptyMessage,
                action: emptyAction ?? _emptyLibraryActions(ref),
              ),
            )
          : SliverPadding(
              padding: const EdgeInsets.only(bottom: 110),
              sliver: SliverList.separated(
                itemCount: items.length,
                separatorBuilder: (_, _) => Divider(
                  height: 1,
                  indent: 72,
                  endIndent: 16,
                  color: Theme.of(context).colorScheme.outlineVariant.withValues(
                    alpha: 0.3,
                  ),
                ),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return SongTile(
                    item: item,
                    onTap: () => context.push('/song/${item.song.id}'),
                  );
                },
              ),
            ),
    );
  }

  Widget _emptyLibraryActions(WidgetRef ref) {
    return Builder(
      builder: (context) => Wrap(
        spacing: 12,
        runSpacing: 10,
        alignment: WrapAlignment.center,
        children: [
          FilledButton.icon(
            onPressed: () => context.push('/editor'),
            icon: const Icon(Icons.add),
            label: const Text('New song'),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              final added = await ref.read(songRepositoryProvider).addDemoSongs();
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
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Load demos'),
          ),
        ],
      ),
    );
  }
}
