import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../community/data/community_api.dart';
import '../community/data/published_feed.dart';
import '../../shared/widgets/song_tile.dart';
import '../songs/data/song_repository.dart';
import 'widgets/published_song_card.dart';

/// Every published song, newest first. Pages are requested as the reader
/// approaches the bottom, and each page is cached for offline reading.
class PublishedLibraryScreen extends ConsumerStatefulWidget {
  const PublishedLibraryScreen({super.key});

  @override
  ConsumerState<PublishedLibraryScreen> createState() =>
      _PublishedLibraryScreenState();
}

class _PublishedLibraryScreenState extends ConsumerState<PublishedLibraryScreen> {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_loadNearBottom);
  }

  @override
  void dispose() {
    _scroll.removeListener(_loadNearBottom);
    _scroll.dispose();
    super.dispose();
  }

  void _loadNearBottom() {
    if (!_scroll.hasClients || _scroll.position.extentAfter > 600) return;
    final feed = ref.read(publishedFeedProvider).value;
    if (feed == null || !feed.hasMore || feed.loadingMore) return;
    ref.read(publishedFeedProvider.notifier).loadMore();
  }

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(publishedFeedProvider);
    // If the first page already fits on screen there is no scroll event to
    // trigger paging, so check once the list has been laid out.
    final loaded = feed.value;
    if (loaded != null &&
        loaded.hasMore &&
        !loaded.loadingMore &&
        loaded.loadMoreError == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadNearBottom());
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Published')),
      body: feed.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => SongListEmpty(
          title: 'Could not load published songs',
          message: '$error',
          action: OutlinedButton(
            onPressed: () => ref.read(publishedFeedProvider.notifier).refresh(),
            child: const Text('Retry'),
          ),
        ),
        data: (state) => RefreshIndicator(
          onRefresh: () => ref.read(publishedFeedProvider.notifier).refresh(),
          child: state.songs.isEmpty
              ? _scrollable(
                  SongListEmpty(
                    title: 'Nothing published yet',
                    message: 'Songs shared by the community will appear here.',
                    action: FilledButton.icon(
                      onPressed: () => context.go('/'),
                      icon: const Icon(Icons.library_music_outlined),
                      label: const Text('Browse library'),
                    ),
                  ),
                )
              : Column(
                  children: [
                    if (state.offline)
                      Container(
                        width: double.infinity,
                        color: Theme.of(context).colorScheme.surfaceContainerLow,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Text(
                          'Showing saved copies — reconnect to load the full list',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    Expanded(
                      child: ListView.builder(
                        controller: _scroll,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.only(bottom: 24),
                        itemCount: state.songs.length +
                            (state.hasMore ||
                                    state.loadingMore ||
                                    state.loadMoreError != null
                                ? 1
                                : 0),
                        itemBuilder: (context, index) {
                          if (index == state.songs.length) {
                            return _bottomRow(state);
                          }
                          final song = state.songs[index];
                          return PublishedSongCard(
                            song: song,
                            onTap: () => _open(song),
                          );
                        },
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _bottomRow(PublishedFeedState state) {
    if (state.loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (state.loadMoreError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: OutlinedButton(
            onPressed: () =>
                ref.read(publishedFeedProvider.notifier).loadMore(),
            child: const Text('Retry loading more'),
          ),
        ),
      );
    }
    // Keep a small tail so the scroll listener has room to fire.
    return const SizedBox(height: 16);
  }

  Future<void> _open(CommunitySong song) async {
    final id = await ref.read(songRepositoryProvider).cacheCommunitySong(song);
    if (id == null || !mounted) return;
    context.push('/song/$id');
  }

  /// Empty lists still need to be scrollable for pull-to-refresh.
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
}
