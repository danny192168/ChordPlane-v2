import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/auth/auth_gateway.dart';
import '../../../core/chords/chord_detection.dart';
import '../../../core/db/app_database.dart';
import '../../../core/config/app_config.dart';
import '../../../core/utils/slug.dart';
import '../../community/data/community_api.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final songRepositoryProvider = Provider<SongRepository>((ref) {
  final configured =
      AppConfig.hasSupabase && AppConfig.supabaseInitError == null;
  return SongRepository(
    db: ref.watch(databaseProvider),
    userId: ref.watch(currentUserIdProvider).value ?? 'local-user',
    communityApi: configured ? ref.read(communityApiProvider) : null,
  );
});

class SongListItem {
  const SongListItem({required this.song, required this.isFavorite});

  final SongRow song;
  final bool isFavorite;
}

/// A favorited song together with the moment it was hearted, so profile lists
/// can show a meaningful age rather than the song's last edit time.
class FavoriteItem {
  const FavoriteItem({required this.song, required this.favoritedAt});

  final SongRow song;
  final DateTime favoritedAt;
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
    this.chordDetectionMode = ChordDetectionMode.auto,
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
  final ChordDetectionMode chordDetectionMode;
  final int capo;
  final int? tempo;
  final String instrument;
  final String tuning;
  final String youtubeUrl;
  final String tags;
  final String visibility;
}

class SongRepository {
  SongRepository({required this.db, required this.userId, this.communityApi});

  final AppDatabase db;
  final String userId;
  final CommunityApi? communityApi;

  /// Favorites newest-first, with the date each one was added. This is the
  /// profile's Favorites panel; the tab's favourites use alphabetical order.
  Stream<List<FavoriteItem>> watchFavoriteItems() {
    final query = db.select(db.favorites).join([
      innerJoin(db.songs, db.songs.id.equalsExp(db.favorites.songId)),
    ]);
    query.where(
      db.favorites.userId.equals(userId) & db.songs.deletedAt.isNull(),
    );
    query.orderBy([OrderingTerm.desc(db.favorites.createdAt)]);
    return query.watch().map(
      (rows) => [
        for (final row in rows)
          FavoriteItem(
            song: row.readTable(db.songs),
            favoritedAt: row.readTable(db.favorites).createdAt,
          ),
      ],
    );
  }

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

  /// Songs kept on this device: everything created or edited here, plus
  /// community songs the user explicitly opened or downloaded. Search results
  /// cached in the background stay out until they are kept deliberately.
  Stream<List<SongListItem>> watchSaved() {
    final query = db.select(db.songs).join([
      leftOuterJoin(
        db.favorites,
        db.favorites.songId.equalsExp(db.songs.id) &
            db.favorites.userId.equals(userId),
      ),
    ]);
    query.where(
      db.songs.deletedAt.isNull() &
          db.songs.downloadState.isNotValue('cached'),
    );
    query.orderBy([OrderingTerm.desc(db.songs.updatedAt)]);
    return query.watch().map(_mapRows);
  }

  /// Songs the user created or edited here. Cached community copies only
  /// appear once they have been edited, so browsing the catalog does not
  /// pollute My Songs.
  Stream<List<SongListItem>> watchMySongs() {
    final query = db.select(db.songs).join([
      leftOuterJoin(
        db.favorites,
        db.favorites.songId.equalsExp(db.songs.id) &
            db.favorites.userId.equals(userId),
      ),
    ]);
    query.where(
      db.songs.deletedAt.isNull() &
          (db.songs.origin.equals('local') |
              db.songs.editedLocally.equals(true)),
    );
    query.orderBy([OrderingTerm.desc(db.songs.updatedAt)]);
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

  Stream<List<SongListItem>> watchSavedArtist(String slug) {
    final query = db.select(db.songs).join([
      leftOuterJoin(
        db.favorites,
        db.favorites.songId.equalsExp(db.songs.id) &
            db.favorites.userId.equals(userId),
      ),
    ]);
    query.where(
      db.songs.deletedAt.isNull() &
          db.songs.downloadState.isNotValue('cached') &
          db.songs.artistSlug.equals(slug),
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
    final existing = id == null ? null : await getSong(id);
    var base = SongsCompanion(
      title: Value(draft.title.trim()),
      artist: Value(artist),
      artistSlug: Value(artist.isEmpty ? 'unknown' : slugify(artist)),
      body: Value(draft.body),
      originalKey: Value(draft.originalKey.trim()),
      chordDetectionMode: Value(draft.chordDetectionMode.storageKey),
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

    // Editing an offline community copy makes it the user's own song. It
    // moves into My Songs while keeping its source id for credit/ratings.
    if (existing?.origin == 'community') {
      base = base.copyWith(
        editedLocally: const Value(true),
        origin: const Value('community'),
      );
    }

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

  /// Remembers that this local song has a public counterpart, so the viewer
  /// can offer "Update online version" instead of publishing a duplicate.
  Future<void> markPublished(
    String id, {
    required String remoteId,
    required bool anonymous,
  }) async {
    await (db.update(db.songs)..where((t) => t.id.equals(id))).write(
      SongsCompanion(
        remoteId: Value(remoteId),
        anonymousUpload: Value(anonymous),
        visibility: const Value('community'),
        syncState: const Value('synced'),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  Future<void> clearPublished(String id) async {
    await (db.update(db.songs)..where((t) => t.id.equals(id))).write(
      SongsCompanion(
        remoteId: const Value(null),
        anonymousUpload: const Value(false),
        visibility: const Value('private'),
        syncState: const Value('local'),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  /// Stores one community song in the unified Songs table. Existing user
  /// edits always win, so "download all" is safe to repeat.
  Future<String?> cacheCommunitySong(
    CommunitySong song, {
    String downloadState = 'complete',
  }) async {
    final artist = song.artist.trim();
    final existing = await (db.select(db.songs)..where(
          (t) =>
              t.remoteId.equals(song.id) & t.origin.equals('community'),
        ))
        .getSingleOrNull();
    if (existing != null && existing.editedLocally) return existing.id;

    // A song the user kept once stays kept when a later search re-caches it.
    final effectiveState =
        existing != null && existing.downloadState == 'complete'
        ? 'complete'
        : downloadState;

    final localMatch = await findMatching(
      title: song.title,
      artist: song.artist,
    );
    if (localMatch != null && localMatch.origin == 'local') {
      // A song the user made with the same name is never overwritten by a
      // download, even if it was published and has the same remote id.
      return localMatch.id;
    }

    final now = DateTime.now().toUtc();
    final companion = SongsCompanion(
      title: Value(song.title.trim()),
      artist: Value(artist),
      artistSlug: Value(artist.isEmpty ? 'unknown' : slugify(artist)),
      body: Value(song.body),
      originalKey: Value(song.originalKey.trim()),
      chordDetectionMode: Value(song.chordDetectionMode.storageKey),
      capo: Value(song.capo.clamp(0, 12)),
      tempo: Value(song.tempo),
      instrument: Value(song.instrument),
      tuning: Value(song.tuning),
      youtubeUrl: Value(song.youtubeUrl.trim()),
      tags: Value(song.tags),
      visibility: const Value('private'),
      remoteId: Value(song.id),
      anonymousUpload: Value(song.anonymous),
      updatedAt: Value(now),
      syncState: const Value('synced'),
      lastSyncedAt: Value(now),
      downloadState: Value(effectiveState),
      username: Value(song.username),
      ratingSum: Value(song.ratingSum),
      ratingCount: Value(song.ratingCount),
    );

    if (existing == null) {
      await db
          .into(db.songs)
          .insert(
            companion.copyWith(
              id: Value(song.id),
              ownerId: const Value('local-user'),
              createdAt: Value(song.createdAt),
              version: const Value(1),
              origin: const Value('community'),
              editedLocally: const Value(false),
            ),
            mode: InsertMode.insertOrIgnore,
          );
    } else {
      await (db.update(db.songs)..where((t) => t.id.equals(existing.id)))
          .write(
            companion.copyWith(
              createdAt: Value(existing.createdAt),
              editedLocally: const Value(false),
            ),
          );
    }
    return song.id;
  }

  /// Downloads a batch of community songs into the same Songs table used by
  /// the library. Returns the number actually stored (edits are preserved).
  Future<int> cacheCommunitySongs(
    List<CommunitySong> songs, {
    String downloadState = 'complete',
  }) async {
    var saved = 0;
    for (final song in songs) {
      if (await cacheCommunitySong(
            song,
            downloadState: downloadState,
          ) !=
          null) {
        saved++;
      }
    }
    return saved;
  }

  Future<List<CommunitySong>> cachedCommunitySongs(
    String query, {
    int limit = 50,
    int offset = 0,
  }) async {
    final term = query.trim().toLowerCase();
    final select = db.select(db.songs);
    select.where(
      (t) =>
          t.deletedAt.isNull() &
          t.origin.equals('community') &
          t.remoteId.isNotNull(),
    );
    if (term.isNotEmpty) {
      select.where(
        (t) =>
            t.title.lower().contains(term) |
            t.artist.lower().contains(term) |
            t.tags.lower().contains(term),
      );
    }
    final rows = await (select
          ..orderBy([
            (t) => OrderingTerm.desc(t.createdAt),
          ])
          ..limit(limit, offset: offset))
        .get();
    return [for (final row in rows) _communitySong(row)];
  }

  /// Published copies kept on this device, used as the offline fallback for
  /// the profile's Published panel. Background search cache never qualifies.
  Future<List<CommunitySong>> cachedUploads() async {
    final rows = await (db.select(db.songs)..where(
          (t) =>
              t.deletedAt.isNull() &
              t.remoteId.isNotNull() &
              t.visibility.equals('community'),
        )
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
    return [for (final row in rows) _communitySong(row)];
  }

  Future<CommunitySong?> cachedCommunitySong(String id) async {
    final row = await (db.select(db.songs)..where(
          (t) =>
              (t.id.equals(id) | t.remoteId.equals(id)) &
              t.origin.equals('community'),
        ))
        .getSingleOrNull();
    return row == null ? null : _communitySong(row);
  }

  Future<SongRow?> byRemoteId(String remoteId) async {
    return (db.select(db.songs)..where(
          (t) => t.remoteId.equals(remoteId) & t.deletedAt.isNull(),
        ))
        .getSingleOrNull();
  }

  CommunitySong _communitySong(SongRow row) => CommunitySong(
    id: row.remoteId ?? row.id,
    title: row.title,
    artist: row.artist,
    body: row.body,
    originalKey: row.originalKey,
    chordDetectionMode: ChordDetectionMode.fromStorage(
      row.chordDetectionMode,
    ),
    capo: row.capo,
    tempo: row.tempo,
    instrument: row.instrument,
    tuning: row.tuning,
    youtubeUrl: row.youtubeUrl,
    tags: row.tags,
    anonymous: row.anonymousUpload,
    username: row.username,
    createdAt: row.createdAt,
    ratingSum: row.ratingSum,
    ratingCount: row.ratingCount,
  );

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

    late final bool favored;
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
      favored = true;
    } else {
      await (db.delete(db.favorites)..where(
            (t) => t.songId.equals(songId) & t.userId.equals(userId),
          ))
          .go();
      favored = false;
    }

    // The local change is already durable. Cloud sync is best-effort so an
    // offline favorite never blocks the heart animation.
    final api = communityApi;
    final remoteId = (await getSong(songId))?.remoteId;
    if (api != null && remoteId != null) {
      try {
        await api.setFavorite(remoteId, favorite: favored);
      } catch (error) {
        debugPrint('Could not sync favorite: $error');
      }
    }
    return favored;
  }

  /// Unions device favorites with the account's cloud favorites. Runs on each
  /// sign-in; both sides are idempotent, so a later sign-in keeps them equal.
  Future<void> syncFavorites() async {
    final api = communityApi;
    if (api == null) return;

    final remoteIds = await api.myFavorites();
    for (final remoteId in remoteIds) {
      final song = await byRemoteId(remoteId);
      if (song == null) continue;
      await _ensureFavorite(song.id);
    }

    final localFavorites = await (db.select(db.favorites)
          ..where((t) => t.userId.equals(userId)))
        .get();
    for (final favorite in localFavorites) {
      final song = await getSong(favorite.songId);
      final remoteId = song?.remoteId;
      if (remoteId == null) continue;
      await api.setFavorite(remoteId, favorite: true);
    }
  }

  Future<void> _ensureFavorite(String songId) async {
    final existing = await (db.select(db.favorites)..where(
          (t) => t.songId.equals(songId) & t.userId.equals(userId),
        ))
        .getSingleOrNull();
    if (existing != null) return;
    await db
        .into(db.favorites)
        .insert(
          FavoritesCompanion.insert(
            songId: songId,
            userId: Value(userId),
            createdAt: DateTime.now().toUtc(),
          ),
        );
  }

  Future<int> countMySongs() async {
    final rows = await (db.select(db.songs)..where(
          (t) =>
              t.deletedAt.isNull() &
              (t.origin.equals('local') | t.editedLocally.equals(true)),
        ))
        .get();
    return rows.length;
  }

  Future<int> countFavorites() async {
    final rows = await (db.select(db.favorites)
          ..where((t) => t.userId.equals(userId)))
        .get();
    return rows.length;
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
