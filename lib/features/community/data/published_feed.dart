import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../songs/data/song_providers.dart';
import '../../songs/data/song_repository.dart';
import 'community_api.dart';

/// One page of the public catalog. Loaded pages are cached on the device, so
/// the same list can be paged through offline.
@immutable
class PublishedFeedState {
  const PublishedFeedState({
    this.songs = const <CommunitySong>[],
    this.hasMore = false,
    this.loadingMore = false,
    this.offline = false,
    this.loadMoreError,
  });

  final List<CommunitySong> songs;
  final bool hasMore;
  final bool loadingMore;
  final bool offline;
  final Object? loadMoreError;

  PublishedFeedState copyWith({
    List<CommunitySong>? songs,
    bool? hasMore,
    bool? loadingMore,
    bool? offline,
    Object? loadMoreError,
    bool clearLoadMoreError = false,
  }) {
    return PublishedFeedState(
      songs: songs ?? this.songs,
      hasMore: hasMore ?? this.hasMore,
      loadingMore: loadingMore ?? this.loadingMore,
      offline: offline ?? this.offline,
      loadMoreError: clearLoadMoreError ? null : loadMoreError ?? this.loadMoreError,
    );
  }
}

/// Adds a freshly fetched page without duplicating songs that shifted into an
/// earlier page while the user was scrolling.
List<CommunitySong> mergePublishedPages(
  List<CommunitySong> loaded,
  List<CommunitySong> incoming,
) {
  final seen = {for (final song in loaded) song.id};
  final merged = List<CommunitySong>.from(loaded, growable: true);
  for (final song in incoming) {
    if (seen.add(song.id)) merged.add(song);
  }
  return merged;
}

class _FeedPage {
  const _FeedPage(this.songs, this.hasMore, this.offline);

  final List<CommunitySong> songs;
  final bool hasMore;
  final bool offline;
}

/// Infinite-scroll state for the Library's "See all: published" screen.
final publishedFeedProvider =
    AsyncNotifierProvider<PublishedFeedController, PublishedFeedState>(
  PublishedFeedController.new,
);

class PublishedFeedController extends AsyncNotifier<PublishedFeedState> {
  static const pageSize = 25;
  static const maxPages = 40;

  int _pagesLoaded = 0;
  bool _loadingMore = false;

  @override
  Future<PublishedFeedState> build() async {
    _pagesLoaded = 0;
    _loadingMore = false;
    return _loadInitial();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_loadInitial);
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || _loadingMore) return;
    _loadingMore = true;
    state = AsyncValue.data(
      current.copyWith(loadingMore: true, clearLoadMoreError: true),
    );
    try {
      final page = await _fetch(current.songs.length, pageSize, cache: true);
      _pagesLoaded++;
      state = AsyncValue.data(
        PublishedFeedState(
          songs: mergePublishedPages(current.songs, page.songs),
          hasMore: page.hasMore && _pagesLoaded < maxPages,
          offline: current.offline || page.offline,
        ),
      );
    } catch (error) {
      state = AsyncValue.data(
        current.copyWith(loadingMore: false, loadMoreError: error),
      );
    } finally {
      _loadingMore = false;
    }
  }

  Future<PublishedFeedState> _loadInitial() async {
    final page = await _fetch(0, pageSize, cache: true);
    _pagesLoaded = 1;
    return PublishedFeedState(
      songs: page.songs,
      hasMore: page.hasMore && _pagesLoaded < maxPages,
      offline: page.offline,
    );
  }

  Future<_FeedPage> _fetch(
    int offset,
    int limit, {
    required bool cache,
  }) async {
    final repository = ref.read(songRepositoryProvider);
    final cloudReady =
        AppConfig.hasSupabase && AppConfig.supabaseInitError == null;
    final online = ref.read(isOnlineProvider);
    if (!cloudReady || !online) {
      final cached = await repository.cachedCommunitySongs(
        '',
        offset: offset,
        limit: limit,
      );
      return _FeedPage(cached, cached.length == limit, true);
    }

    try {
      final songs = await ref
          .read(communityApiProvider)
          .publishedPage(offset: offset, limit: limit)
          .timeout(const Duration(seconds: 8));
      if (cache) {
        await repository.cacheCommunitySongs(
          songs,
          downloadState: 'cached',
        );
      }
      return _FeedPage(songs, songs.length == limit, false);
    } catch (_) {
      final cached = await repository.cachedCommunitySongs(
        '',
        offset: offset,
        limit: limit,
      );
      if (cached.isEmpty && offset == 0) rethrow;
      return _FeedPage(cached, cached.length == limit, true);
    }
  }
}
