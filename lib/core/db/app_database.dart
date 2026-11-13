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
  IntColumn get capo => integer().withDefault(const Constant(0))();
  IntColumn get tempo => integer().nullable()();
  TextColumn get instrument => text().withDefault(const Constant('guitar'))();
  TextColumn get tuning => text().withDefault(const Constant('standard'))();
  TextColumn get youtubeUrl => text().withDefault(const Constant(''))();
  TextColumn get tags => text().withDefault(const Constant(''))();
  TextColumn get visibility => text().withDefault(const Constant('private'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  TextColumn get syncState => text().withDefault(const Constant('local'))();
  DateTimeColumn get deletedAt => dateTime().nullable()();

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
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(sharedLinks);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
