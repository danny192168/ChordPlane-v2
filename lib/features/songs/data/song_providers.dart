import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/chords/chord_document.dart';
import '../../../core/settings/settings.dart';
import '../../../core/db/app_database.dart';
import 'song_repository.dart';

enum LibraryFilter { artists, favorites }

class LibraryFilterController extends Notifier<LibraryFilter> {
  @override
  LibraryFilter build() => LibraryFilter.artists;

  void set(LibraryFilter filter) => state = filter;
}

final libraryFilterProvider =
    NotifierProvider<LibraryFilterController, LibraryFilter>(
      LibraryFilterController.new,
    );

final libraryProvider = StreamProvider<List<SongListItem>>((ref) {
  final filter = ref.watch(libraryFilterProvider);
  return ref
      .watch(songRepositoryProvider)
      .watchLibrary(favoritesOnly: filter == LibraryFilter.favorites);
});

final artistsProvider = StreamProvider<List<ArtistSummary>>((ref) {
  return ref.watch(songRepositoryProvider).watchArtists();
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

final searchResultsProvider = StreamProvider<List<SongListItem>>((ref) {
  final query = ref.watch(searchQueryProvider);
  return ref.watch(songRepositoryProvider).watchSearch(query);
});

/// One launch-time seed so a fresh install has material to explore.
final demoSeedProvider = FutureProvider<void>((ref) async {
  final prefs = ref.watch(sharedPreferencesProvider);
  if (prefs.getBool('demo.seeded') == true) return;
  await ref.read(songRepositoryProvider).seedDemoSongs();
  await prefs.setBool('demo.seeded', true);
});

typedef ChordViewKey = ({
  String body,
  String originalKey,
  int transpose,
  bool detectBare,
});

final chordDocumentProvider = Provider.family<ChordDocument, ChordViewKey>((
  ref,
  key,
) {
  return ChordDocument.build(
    body: key.body,
    originalKey: key.originalKey,
    transpose: key.transpose,
    detectBare: key.detectBare,
  );
});
