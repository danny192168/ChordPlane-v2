import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
    final filter = ref.watch(libraryFilterProvider);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            title: const Text('ChordPlane'),
            actions: [
              IconButton(
                tooltip: 'Artists',
                onPressed: () => context.push('/artists'),
                icon: const Icon(Icons.people_alt_outlined),
              ),
              const SizedBox(width: 4),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Row(
                children: [
                  ChoiceChip(
                    label: const Text('All songs'),
                    selected: filter == LibraryFilter.all,
                    onSelected: (_) => ref
                        .read(libraryFilterProvider.notifier)
                        .set(LibraryFilter.all),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Favorites'),
                    avatar: const Icon(Icons.favorite, size: 15),
                    selected: filter == LibraryFilter.favorites,
                    onSelected: (_) => ref
                        .read(libraryFilterProvider.notifier)
                        .set(LibraryFilter.favorites),
                  ),
                  const Spacer(),
                  if (songs.hasValue)
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
            songs.when(
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
                        title: filter == LibraryFilter.favorites
                            ? 'No favorites yet'
                            : 'Your songbook is empty',
                        message: filter == LibraryFilter.favorites
                            ? 'Tap the heart on any song to keep it close at hand.'
                            : 'Write your first song with chords and lyrics, or load a few public-domain classics to try the app.',
                        action: filter == LibraryFilter.favorites
                            ? FilledButton.tonal(
                                onPressed: () => ref
                                    .read(libraryFilterProvider.notifier)
                                    .set(LibraryFilter.all),
                                child: const Text('Browse all songs'),
                              )
                            : Wrap(
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
                                      final added = await ref
                                          .read(songRepositoryProvider)
                                          .addDemoSongs();
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
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
                          color: Theme.of(context)
                              .colorScheme
                              .outlineVariant
                              .withValues(alpha: 0.3),
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
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/editor'),
        icon: const Icon(Icons.add),
        label: const Text('New song'),
      ),
    );
  }
}
