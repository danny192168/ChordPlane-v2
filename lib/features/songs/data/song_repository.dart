import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/auth/auth_gateway.dart';
import '../../../core/db/app_database.dart';
import '../../../core/demo/demo_songs.dart';
import '../../../core/utils/slug.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final songRepositoryProvider = Provider<SongRepository>((ref) {
  return SongRepository(
    db: ref.watch(databaseProvider),
    userId: ref.watch(currentUserIdProvider),
  );
});

class SongListItem {
  const SongListItem({required this.song, required this.isFavorite});

  final SongRow song;
  final bool isFavorite;
}

class ArtistSummary {
  const ArtistSummary({
    required this.name,
    required this.slug,
    required this.songCount,
  });

  final String name;
  final String slug;
  final int songCount;
}

class SongDraft {
  const SongDraft({
    required this.title,
    this.artist = '',
    this.body = '',
    this.originalKey = '',
    this.capo = 0,
    this.tempo,
    this.instrument = 'guitar',
    this.tuning = 'standard',
    this.youtubeUrl = '',
    this.tags = '',
    this.visibility = 'private',
  });

  final String title;
  final String artist;
  final String body;
  final String originalKey;
  final int capo;
  final int? tempo;
  final String instrument;
  final String tuning;
  final String youtubeUrl;
  final String tags;
  final String visibility;
}

class SongRepository {
  SongRepository({required this.db, required this.userId});

  final AppDatabase db;
  final String userId;

  Stream<List<SongListItem>> watchLibrary({bool favoritesOnly = false}) {
    final query = db.select(db.songs).join([
      leftOuterJoin(
        db.favorites,
        db.favorites.songId.equalsExp(db.songs.id) &
            db.favorites.userId.equals(userId),
      ),
    ]);
    query.where(db.songs.deletedAt.isNull());
    if (favoritesOnly) {
      query.where(db.favorites.songId.isNotNull());
    }
    query.orderBy([OrderingTerm.asc(db.songs.title)]);

    return query.watch().map(_mapRows);
  }

  Stream<List<SongListItem>> watchRecentlyUpdated({int limit = 20}) {
    final query = db.select(db.songs).join([
      leftOuterJoin(
        db.favorites,
        db.favorites.songId.equalsExp(db.songs.id) &
            db.favorites.userId.equals(userId),
      ),
    ]);
    query.where(db.songs.deletedAt.isNull());
    query.orderBy([OrderingTerm.desc(db.songs.updatedAt)]);
    query.limit(limit);
    return query.watch().map(_mapRows);
  }

  Stream<List<SongListItem>> watchSearch(String rawQuery) {
    final term = rawQuery.trim().toLowerCase();
    if (term.isEmpty) return watchRecentlyUpdated();

    final pattern = '%$term%';
    final query = db.select(db.songs).join([
      leftOuterJoin(
        db.favorites,
        db.favorites.songId.equalsExp(db.songs.id) &
            db.favorites.userId.equals(userId),
      ),
    ]);
    query.where(
      db.songs.deletedAt.isNull() &
          (db.songs.title.lower().like(pattern) |
              db.songs.artist.lower().like(pattern) |
              db.songs.body.lower().like(pattern) |
              db.songs.tags.lower().like(pattern)),
    );
    query.orderBy([OrderingTerm.asc(db.songs.title)]);
    return query.watch().map(_mapRows);
  }

  Stream<List<SongListItem>> watchArtist(String slug) {
    final query = db.select(db.songs).join([
      leftOuterJoin(
        db.favorites,
        db.favorites.songId.equalsExp(db.songs.id) &
            db.favorites.userId.equals(userId),
      ),
    ]);
    query.where(
      db.songs.deletedAt.isNull() & db.songs.artistSlug.equals(slug),
    );
    query.orderBy([OrderingTerm.asc(db.songs.title)]);
    return query.watch().map(_mapRows);
  }

  Stream<List<ArtistSummary>> watchArtists() {
    return watchLibrary().map((items) {
      final grouped = <String, _ArtistAccumulator>{};
      for (final item in items) {
        final raw = item.song.artist.trim();
        final name = raw.isEmpty ? 'Unknown artist' : raw;
        final slug = raw.isEmpty
            ? 'unknown'
            : (item.song.artistSlug.isEmpty
                  ? slugify(name)
                  : item.song.artistSlug);
        final accumulator = grouped.putIfAbsent(
          slug,
          () => _ArtistAccumulator(name: name, slug: slug),
        );
        accumulator.count++;
      }
      final result = grouped.values
          .map(
            (a) => ArtistSummary(
              name: a.name,
              slug: a.slug,
              songCount: a.count,
            ),
          )
          .toList();
      result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return result;
    });
  }

  Stream<SongRow?> watchSong(String id) {
    return (db.select(
      db.songs,
    )..where((t) => t.id.equals(id))).watchSingleOrNull();
  }

  Future<SongRow?> getSong(String id) {
    return (db.select(
      db.songs,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  /// Case-insensitive title + artist lookup used to avoid duplicating songs
  /// when a setlist is imported more than once.
  Future<SongRow?> findMatching({
    required String title,
    required String artist,
  }) {
    final name = title.trim().toLowerCase();
    final artistName = artist.trim().toLowerCase();
    return (db.select(db.songs)..where(
          (t) =>
              t.deletedAt.isNull() &
              t.title.lower().equals(name) &
              t.artist.lower().equals(artistName),
        ))
        .getSingleOrNull();
  }

  Future<String> saveDraft({String? id, required SongDraft draft}) async {
    final now = DateTime.now().toUtc();
    final songId = id ?? Uuid().v7();
    final artist = draft.artist.trim();
    final base = SongsCompanion(
      title: Value(draft.title.trim()),
      artist: Value(artist),
      artistSlug: Value(artist.isEmpty ? 'unknown' : slugify(artist)),
      body: Value(draft.body),
      originalKey: Value(draft.originalKey.trim()),
      capo: Value(draft.capo.clamp(0, 12)),
      tempo: Value(draft.tempo),
      instrument: Value(draft.instrument),
      tuning: Value(draft.tuning),
      youtubeUrl: Value(draft.youtubeUrl.trim()),
      tags: Value(draft.tags),
      visibility: Value(draft.visibility),
      updatedAt: Value(now),
      syncState: Value('pending'),
    );

    if (id == null) {
      await db
          .into(db.songs)
          .insert(
            base.copyWith(
              id: Value(songId),
              ownerId: Value(userId),
              createdAt: Value(now),
              version: const Value(1),
            ),
          );
    } else {
      await (db.update(db.songs)..where((t) => t.id.equals(id))).write(base);
    }
    return songId;
  }

  Future<void> deleteSong(String id) async {
    final now = DateTime.now().toUtc();
    await (db.update(db.songs)..where((t) => t.id.equals(id))).write(
      SongsCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        syncState: const Value('pending'),
      ),
    );
  }

  Stream<bool> watchFavorite(String songId) => (db.select(db.favorites)..where(
        (t) => t.songId.equals(songId) & t.userId.equals(userId),
      ))
      .watch()
      .map((rows) => rows.isNotEmpty);

  Future<bool> toggleFavorite(String songId) async {
    final now = DateTime.now().toUtc();
    final existing = await (db.select(db.favorites)..where(
          (t) => t.songId.equals(songId) & t.userId.equals(userId),
        ))
        .getSingleOrNull();

    if (existing == null) {
      await db
          .into(db.favorites)
          .insert(
            FavoritesCompanion.insert(
              songId: songId,
              userId: Value(userId),
              createdAt: now,
            ),
          );
      return true;
    }

    await (db.delete(db.favorites)..where(
          (t) => t.songId.equals(songId) & t.userId.equals(userId),
        ))
        .go();
    return false;
  }

  Future<void> seedDemoSongs() async {
    final existing = await (db.select(db.songs)..limit(1)).get();
    if (existing.isNotEmpty) return;
    await addDemoSongs();
  }

  /// Adds any demo songs whose titles aren't already present. Returns the
  /// number of songs inserted.
  Future<int> addDemoSongs() async {
    final current = await (db.select(db.songs)).get();
    final titles = current
        .map((song) => song.title.trim().toLowerCase())
        .toSet();
    var added = 0;
    for (final demo in demoDrafts) {
      if (titles.contains(demo.title.toLowerCase())) continue;
      await saveDraft(
        draft: SongDraft(
          title: demo.title,
          artist: demo.artist,
          body: demo.body,
          originalKey: demo.key,
          capo: demo.capo,
          tempo: demo.tempo,
          tags: demo.tags,
        ),
      );
      added++;
    }
    return added;
  }

  List<SongListItem> _mapRows(List<TypedResult> rows) {
    return rows.map((row) {
      return SongListItem(
        song: row.readTable(db.songs),
        isFavorite: row.readTableOrNull(db.favorites) != null,
      );
    }).toList(growable: false);
  }
}

class _ArtistAccumulator {
  _ArtistAccumulator({required this.name, required this.slug});

  final String name;
  final String slug;
  int count = 0;
}
