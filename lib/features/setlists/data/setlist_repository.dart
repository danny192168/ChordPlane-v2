import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/auth/auth_gateway.dart';
import '../../../core/db/app_database.dart';
import '../../songs/data/song_repository.dart';

final setlistRepositoryProvider = Provider<SetlistRepository>((ref) {
  return SetlistRepository(
    db: ref.watch(databaseProvider),
    userId: ref.watch(currentUserIdProvider),
  );
});

class SetlistSummary {
  const SetlistSummary({required this.setlist, required this.songCount});

  final SetlistRow setlist;
  final int songCount;
}

class SetlistEntry {
  const SetlistEntry({required this.item, required this.song});

  final SetlistItemRow item;
  final SongRow song;
}

/// One song's slot in an imported setlist.
class SetlistImportEntry {
  const SetlistImportEntry({
    required this.songId,
    this.transpose = 0,
    this.capo,
    this.note = '',
  });

  final String songId;
  final int transpose;
  final int? capo;
  final String note;
}

class SetlistRepository {
  SetlistRepository({required this.db, required this.userId});

  final AppDatabase db;
  final String userId;

  Stream<List<SetlistSummary>> watchSummaries() {
    final songCount = db.setlistItems.id.count();
    final query = db.select(db.setlists).join([
      leftOuterJoin(
        db.setlistItems,
        db.setlistItems.setlistId.equalsExp(db.setlists.id),
      ),
    ]);
    query.addColumns([songCount]);
    query.where(db.setlists.deletedAt.isNull());
    query.groupBy([db.setlists.id]);
    query.orderBy([OrderingTerm.desc(db.setlists.updatedAt)]);

    return query.watch().map((rows) {
      return rows.map((row) {
        return SetlistSummary(
          setlist: row.readTable(db.setlists),
          songCount: row.read(songCount) ?? 0,
        );
      }).toList(growable: false);
    });
  }

  Stream<SetlistRow?> watchSetlist(String id) {
    return (db.select(
      db.setlists,
    )..where((t) => t.id.equals(id))).watchSingleOrNull();
  }

  Future<SetlistRow?> getSetlist(String id) {
    return (db.select(
      db.setlists,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  /// One-off read used by the share/export path.
  Future<List<SetlistEntry>> getEntries(String setlistId) =>
      _getEntries(setlistId);

  Stream<List<SetlistEntry>> watchEntries(String setlistId) {
    final query = db.select(db.setlistItems).join([
      innerJoin(db.songs, db.songs.id.equalsExp(db.setlistItems.songId)),
    ]);
    query.where(
      db.setlistItems.setlistId.equals(setlistId) &
          db.songs.deletedAt.isNull(),
    );
    query.orderBy([OrderingTerm.asc(db.setlistItems.position)]);

    return query.watch().map((rows) {
      return rows.map((row) {
        return SetlistEntry(
          item: row.readTable(db.setlistItems),
          song: row.readTable(db.songs),
        );
      }).toList(growable: false);
    });
  }

  Future<String> create({
    String title = 'New setlist',
    String description = '',
  }) async {
    final now = DateTime.now().toUtc();
    final id = Uuid().v7();
    await db
        .into(db.setlists)
        .insert(
          SetlistsCompanion.insert(
            id: id,
            ownerId: Value(userId),
            title: title.trim().isEmpty ? 'New setlist' : title.trim(),
            description: Value(description.trim()),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return id;
  }

  /// Creates a setlist with its songs already in place. Used by imports so a
  /// shared set arrives in one write.
  Future<String> createFromEntries({
    required String title,
    String description = '',
    required List<SetlistImportEntry> entries,
  }) async {
    final now = DateTime.now().toUtc();
    final setlistId = Uuid().v7();
    await db.transaction(() async {
      await db
          .into(db.setlists)
          .insert(
            SetlistsCompanion.insert(
              id: setlistId,
              ownerId: Value(userId),
              title: title.trim().isEmpty ? 'Imported setlist' : title.trim(),
              description: Value(description.trim()),
              createdAt: now,
              updatedAt: now,
            ),
          );
      for (var i = 0; i < entries.length; i++) {
        final entry = entries[i];
        await db
            .into(db.setlistItems)
            .insert(
              SetlistItemsCompanion.insert(
                id: Uuid().v7(),
                setlistId: setlistId,
                songId: entry.songId,
                position: (i + 1) * 1024.0,
                transpose: Value(entry.transpose),
                capoOverride: Value(entry.capo),
                note: Value(entry.note),
                createdAt: now,
                updatedAt: now,
              ),
            );
      }
    });
    return setlistId;
  }

  Future<void> rename(String id, String title) async {
    final name = title.trim();
    if (name.isEmpty) return;
    await (db.update(db.setlists)..where((t) => t.id.equals(id))).write(
      SetlistsCompanion(
        title: Value(name),
        updatedAt: Value(DateTime.now().toUtc()),
        syncState: const Value('pending'),
      ),
    );
  }

  Future<void> setDescription(String id, String description) async {
    await (db.update(db.setlists)..where((t) => t.id.equals(id))).write(
      SetlistsCompanion(
        description: Value(description.trim()),
        updatedAt: Value(DateTime.now().toUtc()),
        syncState: const Value('pending'),
      ),
    );
  }

  Future<void> delete(String id) async {
    final now = DateTime.now().toUtc();
    await (db.update(db.setlists)..where((t) => t.id.equals(id))).write(
      SetlistsCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        syncState: const Value('pending'),
      ),
    );
  }

  Future<void> addSong(String setlistId, String songId) async {
    final now = DateTime.now().toUtc();
    final maxPosition = db.setlistItems.position.max();
    final row = await (db.selectOnly(db.setlistItems)
          ..addColumns([maxPosition])
          ..where(db.setlistItems.setlistId.equals(setlistId)))
        .getSingle();
    final nextPosition = (row.read(maxPosition) ?? 0) + 1024;

    await db
        .into(db.setlistItems)
        .insert(
          SetlistItemsCompanion.insert(
            id: Uuid().v7(),
            setlistId: setlistId,
            songId: songId,
            position: nextPosition,
            createdAt: now,
            updatedAt: now,
          ),
        );
    await _touch(setlistId);
  }

  Future<void> removeEntry(String entryId, String setlistId) async {
    await (db.delete(
      db.setlistItems,
    )..where((t) => t.id.equals(entryId))).go();
    await _touch(setlistId);
  }

  /// Moves the entry at [oldIndex] so it ends up at [newIndex], where
  /// [newIndex] is already the final position in the shortened list (the
  /// convention used by `ReorderableListView.onReorderItem`).
  Future<void> reorder(
    String setlistId,
    int oldIndex,
    int newIndex,
  ) async {
    final entries = await _getEntries(setlistId);
    if (oldIndex < 0 || oldIndex >= entries.length) return;
    final target = newIndex.clamp(0, entries.length - 1);
    if (target == oldIndex) return;

    final moved = entries.removeAt(oldIndex);
    entries.insert(target, moved);
    final now = DateTime.now().toUtc();
    await db.transaction(() async {
      for (var i = 0; i < entries.length; i++) {
        await (db.update(db.setlistItems)
              ..where((t) => t.id.equals(entries[i].item.id)))
            .write(
              SetlistItemsCompanion(
                position: Value((i + 1) * 1024.0),
                updatedAt: Value(now),
                syncState: const Value('pending'),
              ),
            );
      }
    });
    await _touch(setlistId);
  }

  Future<void> updateEntrySettings(
    String entryId, {
    int? transpose,
    int? capoOverride,
    String? note,
  }) async {
    await (db.update(db.setlistItems)..where((t) => t.id.equals(entryId)))
        .write(
          SetlistItemsCompanion(
            transpose: transpose == null ? const Value.absent() : Value(transpose),
            capoOverride: capoOverride == null
                ? const Value.absent()
                : Value(capoOverride),
            note: note == null ? const Value.absent() : Value(note),
            updatedAt: Value(DateTime.now().toUtc()),
            syncState: const Value('pending'),
          ),
        );
  }

  Future<List<SetlistEntry>> _getEntries(String setlistId) async {
    final query = db.select(db.setlistItems).join([
      innerJoin(db.songs, db.songs.id.equalsExp(db.setlistItems.songId)),
    ]);
    query.where(db.setlistItems.setlistId.equals(setlistId));
    query.orderBy([OrderingTerm.asc(db.setlistItems.position)]);
    final rows = await query.get();
    return rows
        .map(
          (row) => SetlistEntry(
            item: row.readTable(db.setlistItems),
            song: row.readTable(db.songs),
          ),
        )
        .toList();
  }

  Future<void> _touch(String setlistId) async {
    await (db.update(db.setlists)..where((t) => t.id.equals(setlistId))).write(
      SetlistsCompanion(
        updatedAt: Value(DateTime.now().toUtc()),
        syncState: const Value('pending'),
      ),
    );
  }
}

final setlistsProvider = StreamProvider<List<SetlistSummary>>((ref) {
  return ref.watch(setlistRepositoryProvider).watchSummaries();
});

final setlistProvider = StreamProvider.family<SetlistRow?, String>((ref, id) {
  return ref.watch(setlistRepositoryProvider).watchSetlist(id);
});

final setlistEntriesProvider =
    StreamProvider.family<List<SetlistEntry>, String>((ref, id) {
      return ref.watch(setlistRepositoryProvider).watchEntries(id);
    });
