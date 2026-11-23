import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/chords/chord_detection.dart';
import '../../../core/chords/chord_document.dart';
import '../../../core/demo/demo_songs.dart';
import '../../../core/settings/settings.dart';
import '../../../core/db/app_database.dart';
import '../../setlists/data/setlist_repository.dart';
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
///
/// Songs come first, then a set list built from them, so a new install opens
/// onto a library that looks like somebody already uses it. The
/// `demo.seeded` flag still guards existing libraries: nothing is added twice.
final demoSeedProvider = FutureProvider<void>((ref) async {
  final prefs = ref.watch(sharedPreferencesProvider);
  if (prefs.getBool('demo.seeded') == true) return;
  final songs = ref.read(songRepositoryProvider);
  await songs.seedDemoSongs();
  await _seedDemoSetlist(ref, songs);
  await prefs.setBool('demo.seeded', true);
});

/// Creates [demoSetlist] once, if its songs made it into the library and no
/// set list with that title exists yet. A failure here must not keep the app
/// from starting, so missing songs simply shorten the list.
Future<void> _seedDemoSetlist(Ref ref, SongRepository songs) async {
  final setlists = ref.read(setlistRepositoryProvider);
  if (await setlists.hasTitled(demoSetlist.title)) return;
  final songIds = <String>[];
  for (final title in demoSetlist.songTitles) {
    final song = await songs.findMatching(title: title, artist: 'Traditional');
    if (song != null) songIds.add(song.id);
  }
  if (songIds.isEmpty) return;
  final id = await setlists.create(
    title: demoSetlist.title,
    description: demoSetlist.description,
  );
  for (final songId in songIds) {
    await setlists.addSong(id, songId);
  }
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
