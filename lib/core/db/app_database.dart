import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

/// Songs are stored local-first. Chords and lyrics live in [body] as a
/// ChordPro document, while searchable metadata lives in dedicated columns.
@DataClassName('SongRow')
class Songs extends Table {
  TextColumn get id => text()();
  TextColumn get ownerId => text().withDefault(const Constant('local-user'))();
  TextColumn get title => text()();
  TextColumn get artist => text().withDefault(const Constant(''))();
  TextColumn get artistSlug => text().withDefault(const Constant(''))();
  TextColumn get body => text().withDefault(const Constant(''))();
  TextColumn get originalKey => text().withDefault(const Constant(''))();
  TextColumn get chordDetectionMode =>
      text().withDefault(const Constant('auto'))();
  IntColumn get capo => integer().withDefault(const Constant(0))();
  IntColumn get tempo => integer().nullable()();
  TextColumn get instrument => text().withDefault(const Constant('guitar'))();
  TextColumn get tuning => text().withDefault(const Constant('standard'))();
  TextColumn get youtubeUrl => text().withDefault(const Constant(''))();
  TextColumn get tags => text().withDefault(const Constant(''))();
  TextColumn get visibility => text().withDefault(const Constant('private'))();

  /// Id of the public row in `community_songs`, once this song is published.
  /// Null means the song exists only on this device (or was imported).
  TextColumn get remoteId => text().nullable()();

  /// Credits the upload as Anonymous even though the server keeps the owner.
  BoolColumn get anonymousUpload =>
      boolean().withDefault(const Constant(false))();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  TextColumn get syncState => text().withDefault(const Constant('local'))();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  /// `local` songs were created or edited here. `community` songs are offline
  /// copies from the shared catalog; they stay read-only until the user edits
  /// them, at which point [editedLocally] moves them into My Songs.
  TextColumn get origin => text().withDefault(const Constant('local'))();
  BoolColumn get editedLocally =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();
  TextColumn get downloadState =>
      text().withDefault(const Constant('complete'))();

  /// Community credit copied alongside the offline song.
  TextColumn get username => text().nullable()();
  IntColumn get ratingSum => integer().withDefault(const Constant(0))();
  IntColumn get ratingCount => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('FavoriteRow')
class Favorites extends Table {
  TextColumn get songId =>
      text().references(Songs, #id, onDelete: KeyAction.cascade)();
  TextColumn get userId => text().withDefault(const Constant('local-user'))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {songId, userId};
}

@DataClassName('SetlistRow')
class Setlists extends Table {
  TextColumn get id => text()();
  TextColumn get ownerId => text().withDefault(const Constant('local-user'))();
  TextColumn get title => text()();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get visibility => text().withDefault(const Constant('private'))();
  TextColumn get shareSlug => text().nullable()();
  BoolColumn get collaborationEnabled =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  TextColumn get syncState => text().withDefault(const Constant('local'))();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('SetlistItemRow')
class SetlistItems extends Table {
  TextColumn get id => text()();
  TextColumn get setlistId =>
      text().references(Setlists, #id, onDelete: KeyAction.cascade)();
  TextColumn get songId =>
      text().references(Songs, #id, onDelete: KeyAction.cascade)();
  RealColumn get position => real()();
  IntColumn get transpose => integer().withDefault(const Constant(0))();
  IntColumn get capoOverride => integer().nullable()();
  TextColumn get note => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  TextColumn get syncState => text().withDefault(const Constant('local'))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('SettingEntry')
class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// Writes are queued here so the cloud sync layer can be added without
/// changing the UI or repository code. Unused while the app is local-only.
@DataClassName('OutboxEntry')
class SyncOutbox extends Table {
  TextColumn get id => text()();
  TextColumn get entity => text()();
  TextColumn get entityId => text()();
  TextColumn get operation => text()();
  TextColumn get payload => text().withDefault(const Constant(''))();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Local record of every server share link this device created. Maps a share
/// token back to the local song or setlist it was made from, so the "My
/// shared links" screen can offer "Update shared copy" later. Shares created
/// before this table existed have no row and cannot be updated in place.
@DataClassName('SharedLinkRow')
class SharedLinks extends Table {
  TextColumn get token => text()();
  TextColumn get kind => text()(); // 'song' | 'setlist'
  TextColumn get localId => text()();
  TextColumn get title => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get lastPushedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {token};
}

@DriftDatabase(
  tables: [
    Songs,
    Favorites,
    Setlists,
    SetlistItems,
    AppSettings,
    SyncOutbox,
    SharedLinks,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'chord_plane'));

  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(sharedLinks);
      }
      if (from < 3) {
        await m.addColumn(songs, songs.chordDetectionMode);
      }
      if (from < 4) {
        await m.addColumn(songs, songs.remoteId);
        await m.addColumn(songs, songs.anonymousUpload);
      }
      if (from < 5) {
        await customStatement('''
          create table if not exists community_copies (
            id text primary key,
            title text not null,
            artist text not null default '',
            body text not null default '',
            original_key text not null default '',
            chord_detection_mode text not null default 'auto',
            capo integer not null default 0,
            tempo integer,
            instrument text not null default 'guitar',
            tuning text not null default 'standard',
            youtube_url text not null default '',
            tags text not null default '',
            anonymous integer not null default 0,
            username text,
            created_at datetime not null,
            synced_at datetime not null,
            rating_sum integer not null default 0,
            rating_count integer not null default 0
          )
        ''');
      }
      if (from < 6) {
        await m.addColumn(songs, songs.origin);
        await m.addColumn(songs, songs.editedLocally);
        await m.addColumn(songs, songs.lastSyncedAt);
        await m.addColumn(songs, songs.downloadState);
        await m.addColumn(songs, songs.username);
        await m.addColumn(songs, songs.ratingSum);
        await m.addColumn(songs, songs.ratingCount);

        // Move the old read-only cache into the one Songs table. Edited user
        // songs win: a cache row never replaces an existing local song.
        await customStatement('''
          insert or ignore into songs (
            id, owner_id, title, artist, artist_slug, body, original_key,
            chord_detection_mode, capo, tempo, instrument, tuning,
            youtube_url, tags, visibility, remote_id, anonymous_upload,
            created_at, updated_at, version, sync_state, origin,
            edited_locally, last_synced_at, download_state, username,
            rating_sum, rating_count
          )
          select
            c.id, 'local-user', c.title, c.artist,
            lower(replace(trim(c.artist), ' ', '-')), c.body, c.original_key,
            c.chord_detection_mode, c.capo, c.tempo, c.instrument, c.tuning,
            c.youtube_url, c.tags, 'private', c.id, c.anonymous,
            c.created_at, c.synced_at, 1, 'synced', 'community',
            0, c.synced_at, 'complete', c.username,
            c.rating_sum, c.rating_count
          from community_copies c
          where not exists (
            select 1 from songs s
            where s.id = c.id or (s.remote_id is not null and s.remote_id = c.id)
          )
        ''');
        await customStatement('drop table if exists community_copies');
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
