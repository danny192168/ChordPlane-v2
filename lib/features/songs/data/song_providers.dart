import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_gateway.dart';
import '../../../core/chords/chord_detection.dart';
import '../../../core/chords/chord_document.dart';
import '../../../core/config/app_config.dart';
import '../../../core/demo/demo_songs.dart';
import '../../../core/settings/settings.dart';
import '../../../core/db/app_database.dart';
import '../../community/data/community_api.dart';
import '../../community/data/community_providers.dart';
import '../../setlists/data/setlist_repository.dart';
import 'song_repository.dart';

final libraryProvider = StreamProvider<List<SongListItem>>((ref) {
  return ref.watch(songRepositoryProvider).watchLibrary();
});

/// Everything kept on this device: created, edited, opened, or downloaded.
/// Background search cache is excluded, so Saved stays intentional.
final savedSongsProvider = StreamProvider<List<SongListItem>>((ref) {
  return ref.watch(songRepositoryProvider).watchSaved();
});

/// Artists derived from saved songs, for the Saved tab.
final savedArtistsProvider = StreamProvider<List<ArtistSummary>>((ref) async* {
  final repository = ref.watch(songRepositoryProvider);
  await for (final items in repository.watchSaved()) {
    yield artistSummariesFromSongs(items);
  }
});

final savedArtistSongsProvider =
    StreamProvider.family<List<SongListItem>, String>((ref, slug) {
      return ref.watch(songRepositoryProvider).watchSavedArtist(slug);
    });

/// Songs the user created or edited, including published copies. Used by the
/// profile stats and kept for callers that still need the strict subset.
final mySongsProvider = StreamProvider<List<SongListItem>>((ref) {
  return ref.watch(songRepositoryProvider).watchMySongs();
});

final favoriteSongsProvider = StreamProvider<List<SongListItem>>((ref) {
  return ref.watch(songRepositoryProvider).watchLibrary(favoritesOnly: true);
});

/// Favorites for the profile panel, newest heart first, with the date they
/// were added so the list can show a relative age.
final favoriteItemsProvider = StreamProvider<List<FavoriteItem>>((ref) {
  return ref.watch(songRepositoryProvider).watchFavoriteItems();
});

/// Artists derived from favorited songs only. Used by the Favorites tab.
final favoriteArtistsProvider = StreamProvider<List<ArtistSummary>>((ref) async* {
  final repository = ref.watch(songRepositoryProvider);
  await for (final items in repository.watchLibrary(favoritesOnly: true)) {
    yield artistSummariesFromSongs(items);
  }
});

/// Hearted songs for one artist, for the Favorites → artist drill-down.
final favoriteArtistSongsProvider =
    StreamProvider.family<List<SongListItem>, String>((ref, slug) async* {
      final repository = ref.watch(songRepositoryProvider);
      await for (final items in repository.watchLibrary(favoritesOnly: true)) {
        yield items.where((item) {
          final raw = item.song.artist.trim();
          final itemSlug = item.song.artistSlug.isEmpty
              ? (raw.isEmpty ? 'unknown' : _slug(raw))
              : item.song.artistSlug;
          return itemSlug == slug;
        }).toList();
      }
    });

final artistSongsProvider =
    StreamProvider.family<List<SongListItem>, String>((ref, slug) {
      return ref.watch(songRepositoryProvider).watchArtist(slug);
    });

final songProvider = StreamProvider.family<SongRow?, String>((ref, id) {
  return ref.watch(songRepositoryProvider).watchSong(id);
});

final favoriteProvider = StreamProvider.family<bool, String>((ref, id) {
  return ref.watch(songRepositoryProvider).watchFavorite(id);
});

class SearchQueryController extends Notifier<String> {
  @override
  String build() => '';

  void set(String value) => state = value;

  void clear() => state = '';
}

final searchQueryProvider = NotifierProvider<SearchQueryController, String>(
  SearchQueryController.new,
);

/// Local search is synchronous; only the cloud query is debounced. This keeps
/// results responsive on a slow connection without spamming Supabase.
class OnlineQueryController extends Notifier<String> {
  Timer? _timer;

  @override
  String build() {
    ref.onDispose(() => _timer?.cancel());
    ref.listen(searchQueryProvider, (_, next) {
      _timer?.cancel();
      final trimmed = next.trim();
      if (trimmed.isEmpty) {
        state = '';
        return;
      }
      _timer = Timer(const Duration(milliseconds: 300), () => state = trimmed);
    });
    return '';
  }

}

final onlineQueryProvider =
    NotifierProvider<OnlineQueryController, String>(OnlineQueryController.new);

/// Connectivity is a hint, not a gate: the search provider still fails
/// silently and shows local results when a "connected" network has no route.
final connectivityProvider = StreamProvider<List<ConnectivityResult>>((ref) async* {
  final connectivity = Connectivity();
  try {
    yield await connectivity.checkConnectivity();
  } catch (_) {
    yield const <ConnectivityResult>[ConnectivityResult.none];
  }
  try {
    await for (final results in connectivity.onConnectivityChanged) {
      yield results;
    }
  } catch (_) {
    // Plugin unavailable in tests or unsupported platform: stay offline.
  }
});

final isOnlineProvider = Provider<bool>((ref) {
  final results = ref.watch(connectivityProvider).value;
  if (results == null) return false;
  return results.any((result) => result != ConnectivityResult.none);
});

/// Device-only search: only songs already saved on this device are searched.
final searchResultsProvider = StreamProvider<List<SongListItem>>((ref) {
  final query = ref.watch(searchQueryProvider);
  return ref.watch(songRepositoryProvider).watchSearch(query);
});

/// One song row in the merged search results. Local rows are already stored;
/// online rows are cached quietly but not counted as Saved until opened.
class SearchSongResult {
  const SearchSongResult._({this.local, this.online});

  factory SearchSongResult.local(SongListItem item) =>
      SearchSongResult._(local: item);

  factory SearchSongResult.online(CommunitySong song) =>
      SearchSongResult._(online: song);

  final SongListItem? local;
  final CommunitySong? online;

  bool get isOnline => online != null;

  String get id => local?.song.id ?? online!.id;

  String get title => local?.song.title ?? online!.title;

  String get artist => local?.song.artist ?? online!.artist;

  String get key => local?.song.originalKey ?? online!.originalKey;
}

/// An artist section result. Local artists drill into the normal artist page;
/// online artists drill into the catalog artist page.
class SearchArtistResult {
  const SearchArtistResult({
    required this.name,
    required this.slug,
    required this.songCount,
    required this.online,
  });

  final String name;
  final String slug;
  final int songCount;
  final bool online;
}

class SearchView {
  const SearchView({
    this.songs = const <SearchSongResult>[],
    this.artists = const <SearchArtistResult>[],
    this.onlineLoading = false,
  });

  final List<SearchSongResult> songs;
  final List<SearchArtistResult> artists;
  final bool onlineLoading;

  bool get isEmpty => songs.isEmpty && artists.isEmpty && !onlineLoading;
}

/// Searches the shared catalog only when the device is online. Results are
/// cached as passive copies so opening them works offline, but they do not
/// appear in Saved until the user deliberately opens or downloads one.
final onlineSearchProvider = FutureProvider<List<CommunitySong>>((ref) async {
  final query = ref.watch(onlineQueryProvider);
  if (query.isEmpty) return const <CommunitySong>[];
  if (!AppConfig.hasSupabase || AppConfig.supabaseInitError != null) {
    return const <CommunitySong>[];
  }
  if (!ref.watch(isOnlineProvider)) return const <CommunitySong>[];
  ref.watch(signedInProvider);

  try {
    final songs = await ref
        .read(communityApiProvider)
        .search(query)
        .timeout(const Duration(seconds: 8));
    await ref
        .read(songRepositoryProvider)
        .cacheCommunitySongs(songs, downloadState: 'cached');
    return songs;
  } catch (_) {
    return const <CommunitySong>[];
  }
});

/// Combines instant local results with the quiet online pass. Songs come
/// first; artist rows only appear when the artist's own name matches.
final searchViewProvider = Provider<SearchView>((ref) {
  final query = ref.watch(searchQueryProvider).trim();
  if (query.isEmpty) return const SearchView();

  final localAsync = ref.watch(searchResultsProvider);
  final onlineAsync = ref.watch(onlineSearchProvider);
  final localItems = localAsync.value ?? const <SongListItem>[];
  final onlineSongs = onlineAsync.value ?? const <CommunitySong>[];

  final knownIds = <String>{
    for (final item in localItems) item.song.id,
    for (final item in localItems) if (item.song.remoteId != null)
      item.song.remoteId!,
  };
  final freshOnline =
      onlineSongs.where((song) => !knownIds.contains(song.id)).toList();

  final term = query.toLowerCase();
  int rank(SearchSongResult result) {
    final title = result.title.trim().toLowerCase();
    if (title == term) return 0;
    if (title.startsWith(term)) return 1;
    if (title.contains(term)) return 2;
    return 3;
  }

  final songs = <SearchSongResult>[
    ...localItems.map(SearchSongResult.local),
    ...freshOnline.map(SearchSongResult.online),
  ]..sort((a, b) {
      final byRank = rank(a).compareTo(rank(b));
      if (byRank != 0) return byRank;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });

  final localArtists = artistSummariesFromSongs(localItems)
      .where((artist) => artist.name.toLowerCase().contains(term))
      .map(
        (artist) => SearchArtistResult(
          name: artist.name,
          slug: artist.slug,
          songCount: artist.songCount,
          online: false,
        ),
      );
  final onlineArtists = _onlineArtistResults(freshOnline)
      .where((artist) => artist.name.toLowerCase().contains(term));

  return SearchView(
    songs: songs,
    artists: [...localArtists, ...onlineArtists],
    onlineLoading: onlineAsync.isLoading,
  );
});

List<SearchArtistResult> _onlineArtistResults(List<CommunitySong> songs) {
  final grouped = <String, _ArtistAccumulator>{};
  for (final song in songs) {
    final name = song.artist.trim().isEmpty
        ? 'Unknown artist'
        : song.artist.trim();
    final slug = _slug(name).isEmpty ? 'unknown' : _slug(name);
    final artist = grouped.putIfAbsent(
      slug,
      () => _ArtistAccumulator(name: name, slug: slug),
    );
    artist.count++;
  }
  final results = grouped.values
      .map(
        (artist) => SearchArtistResult(
          name: artist.name,
          slug: artist.slug,
          songCount: artist.count,
          online: true,
        ),
      )
      .toList();
  results.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return results;
}

/// Every catalog song by one artist, cached locally when the artist screen
/// opens. Downloading all uses the same provider so it never re-fetches.
final onlineArtistSongsProvider =
    FutureProvider.family<List<CommunitySong>, String>((ref, artist) async {
      if (!AppConfig.hasSupabase || AppConfig.supabaseInitError != null) {
        return const <CommunitySong>[];
      }
      if (!ref.watch(isOnlineProvider)) return const <CommunitySong>[];
      ref.watch(signedInProvider);
      try {
        final found = await ref
            .read(communityApiProvider)
            .search(artist)
            .timeout(const Duration(seconds: 8));
        final normalized = artist.trim().toLowerCase();
        final songs = found
            .where((song) => song.artist.trim().toLowerCase() == normalized)
            .toList();
        await ref.read(songRepositoryProvider).cacheCommunitySongs(songs);
        return songs;
      } catch (_) {
        return const <CommunitySong>[];
      }
    });

/// A small, read-only peek at the shared catalog for the Library home screen.
/// Results are passive cache rows, so they do not appear in Saved until the
/// user opens one. Offline launches fall back to already cached songs.
final recentPublishedProvider = FutureProvider<List<CommunitySong>>((ref) async {
  final repository = ref.read(songRepositoryProvider);
  Future<List<CommunitySong>> cached() async =>
      (await repository.cachedCommunitySongs('')).take(5).toList();

  if (!AppConfig.hasSupabase || AppConfig.supabaseInitError != null) {
    return cached();
  }
  if (!ref.watch(isOnlineProvider)) return cached();
  try {
    // Only five are needed here; the full chronological list lives on its
    // own paginated screen reached from the section's See all button.
    final songs = await ref
        .read(communityApiProvider)
        .publishedPage(offset: 0, limit: 5)
        .timeout(const Duration(seconds: 6));
    await repository.cacheCommunitySongs(
      songs,
      downloadState: 'cached',
    );
    return songs;
  } catch (_) {
    return cached();
  }
});

class DownloadProgress {
  const DownloadProgress(this.done, this.total);

  final int done;
  final int total;

  bool get isComplete => total > 0 && done >= total;
}

/// Per-artist download state so the UI can show `Downloading 3 / 12`.
class ArtistDownloadController extends Notifier<AsyncValue<DownloadProgress?>> {
  ArtistDownloadController(this.artist);

  final String artist;

  @override
  AsyncValue<DownloadProgress?> build() => const AsyncData(null);

  Future<void> download() async {
    if (!AppConfig.hasSupabase || AppConfig.supabaseInitError != null) return;
    state = const AsyncData(DownloadProgress(0, 0));
    try {
      final songs = await ref.read(onlineArtistSongsProvider(artist).future);
      if (songs.isEmpty) {
        state = const AsyncData(DownloadProgress(0, 0));
        return;
      }
      final repository = ref.read(songRepositoryProvider);
      for (var index = 0; index < songs.length; index++) {
        await repository.cacheCommunitySong(songs[index]);
        state = AsyncData(DownloadProgress(index + 1, songs.length));
      }
      ref.invalidate(savedArtistsProvider);
    } catch (error, stack) {
      state = AsyncError(error, stack);
    }
  }
}

final artistDownloadControllerProvider =
    NotifierProvider.family<
      ArtistDownloadController,
      AsyncValue<DownloadProgress?>,
      String
    >(ArtistDownloadController.new);

/// Unions local and cloud favorites once the account is available.
final favoritesSyncProvider = FutureProvider<void>((ref) async {
  if (!AppConfig.hasSupabase || AppConfig.supabaseInitError != null) return;
  // Re-run when the active account changes, not only when signed-in flips.
  ref.watch(currentUserIdProvider);
  final signedIn =
      ref.watch(signedInProvider).value ??
      ref.read(authGatewayProvider).isSignedIn;
  if (!signedIn) return;
  await ref.read(songRepositoryProvider).syncFavorites();
  ref.invalidate(favoriteSongsProvider);
  ref.invalidate(favoriteArtistsProvider);
  ref.invalidate(favoriteItemsProvider);
});

/// Profile name is kept locally too, so guest mode and offline launches still
/// have a stable avatar and display name.
class ProfileNameController extends Notifier<String> {
  static const key = 'profile.displayName';

  @override
  String build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return prefs.getString(key)?.trim() ?? '';
  }

  void set(String value) {
    final trimmed = value.trim();
    state = trimmed;
    ref.read(sharedPreferencesProvider).setString(key, trimmed);
  }
}

final profileNameProvider = NotifierProvider<ProfileNameController, String>(
  ProfileNameController.new,
);

/// Published count for the Profile tab label. Shares the exact list request
/// used by the panel, so the number and the list can never disagree.
final myPublishedCountProvider = FutureProvider<int>((ref) async {
  ref.watch(currentUserIdProvider);
  final signedIn =
      ref.watch(signedInProvider).value ??
      ref.read(authGatewayProvider).isSignedIn;
  if (!signedIn) return 0;
  try {
    return (await ref.watch(myUploadsProvider.future)).length;
  } catch (_) {
    return 0;
  }
});

final profileInfoProvider = FutureProvider<ProfileInfo>((ref) async {
  final localName = ref.watch(profileNameProvider);
  ref.watch(currentUserIdProvider);
  if (!AppConfig.hasSupabase || AppConfig.supabaseInitError != null) {
    return ProfileInfo(
      displayName: localName,
      username: '',
      email: '',
    );
  }
  final signedIn =
      ref.watch(signedInProvider).value ??
      ref.read(authGatewayProvider).isSignedIn;
  if (!signedIn) {
    return ProfileInfo(displayName: localName, username: '', email: '');
  }
  final profile = await ref.read(communityApiProvider).currentProfile();
  return ProfileInfo(
    displayName: profile.displayName.isEmpty ? localName : profile.displayName,
    username: profile.username,
    email: profile.email,
  );
});

/// The starter pack is gone. On the first launch after this build, remove the
/// old sample songs and their sample set list. Anything the user edited or
/// hearted is left alone, so this never destroys real work.
final appBootstrapProvider = FutureProvider<void>((ref) async {
  final prefs = ref.watch(sharedPreferencesProvider);
  if (prefs.getBool('demo.removed') == true) return;

  final db = ref.read(databaseProvider);
  final songs = ref.read(songRepositoryProvider);
  final titles = demoDrafts.map((draft) => draft.title.toLowerCase()).toSet();
  final artists = demoDrafts.map((draft) => draft.artist.toLowerCase()).toSet();

  final candidates = await (db.select(db.songs)..where(
        (t) =>
            t.deletedAt.isNull() &
            t.origin.equals('local') &
            t.editedLocally.equals(false) &
            t.remoteId.isNull(),
      ))
      .get();

  for (final row in candidates) {
    if (!titles.contains(row.title.toLowerCase()) ||
        !artists.contains(row.artist.toLowerCase())) {
      continue;
    }
    final favorites = await (db.select(db.favorites)..where(
          (t) => t.songId.equals(row.id),
        ))
        .get();
    if (favorites.isNotEmpty) continue;
    await songs.deleteSong(row.id);
  }

  final setlists = ref.read(setlistRepositoryProvider);
  final sample = await (db.select(db.setlists)..where(
        (t) => t.deletedAt.isNull() & t.title.equals(demoSetlist.title),
      ))
      .get();
  for (final row in sample) {
    await setlists.delete(row.id);
  }

  await prefs.setBool('demo.removed', true);
});

String _slug(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-|-$'), '');

/// Groups songs into the artist tiles shown in Saved and Favorites.
List<ArtistSummary> artistSummariesFromSongs(Iterable<SongListItem> items) {
  final grouped = <String, _ArtistAccumulator>{};
  for (final item in items) {
    final raw = item.song.artist.trim();
    final name = raw.isEmpty ? 'Unknown artist' : raw;
    final slug = item.song.artistSlug.isEmpty
        ? (raw.isEmpty ? 'unknown' : _slug(raw))
        : item.song.artistSlug;
    final artist = grouped.putIfAbsent(
      slug,
      () => _ArtistAccumulator(name: name, slug: slug),
    );
    artist.count++;
  }
  final result = grouped.values
      .map(
        (a) => ArtistSummary(name: a.name, slug: a.slug, songCount: a.count),
      )
      .toList();
  result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return result;
}

class _ArtistAccumulator {
  _ArtistAccumulator({required this.name, required this.slug});

  final String name;
  final String slug;
  int count = 0;
}

typedef ChordViewKey = ({
  String body,
  String originalKey,
  int transpose,
  ChordDetectionMode mode,
});

final chordDocumentProvider = Provider.family<ChordDocument, ChordViewKey>((
  ref,
  key,
) {
  return ChordDocument.build(
    body: key.body,
    originalKey: key.originalKey,
    transpose: key.transpose,
    mode: key.mode,
  );
});
