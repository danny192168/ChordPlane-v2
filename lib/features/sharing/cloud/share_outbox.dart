import 'dart:convert';

import 'package:drift/drift.dart';import 'package:uuid/uuid.dart';

import '../../../core/db/app_database.dart';
import 'share_cloud.dart';

/// Queues share uploads in the database so a share created offline survives
/// an app restart. [flush] retries everything pending; it is safe to call at
/// any time and simply does nothing when the queue is empty.
class ShareOutbox {
  ShareOutbox({required this.db, required this.api});

  final AppDatabase db;
  final ShareCloudApi api;

  static const String _entity = 'server_share';

  Future<void> enqueue(ShareRecord record) {
    return db
        .into(db.syncOutbox)
        .insert(
          SyncOutboxCompanion.insert(
            id: const Uuid().v7(),
            entity: _entity,
            entityId: record.token,
            operation: 'upsert',
            payload: Value(jsonEncode(record.toJson())),
            createdAt: DateTime.now(),
          ),
        );
  }

  /// Returns how many queued shares were successfully uploaded.
  Future<int> flush() async {
    final pending = await (
      db.select(db.syncOutbox)..where((t) => t.entity.equals(_entity))
    ).get();
    if (pending.isEmpty) return 0;

    var uploaded = 0;
    for (final entry in pending) {
      try {
        final record = ShareRecord.fromJson(
          (jsonDecode(entry.payload) as Map).cast<String, dynamic>(),
        );
        await api.upsertShare(record);
        await (db.delete(
          db.syncOutbox,
        )..where((t) => t.id.equals(entry.id))).go();
        uploaded++;
      } on ShareCloudException {
        // Network and auth failures may resolve later (connectivity, sign-in).
        // Rejected rows (policy violations, bad data) never succeed, so give
        // up on them after a handful of attempts instead of looping forever.
        final attempts = entry.attempts + 1;
        if (attempts >= 8) {
          await (db.delete(
            db.syncOutbox,
          )..where((t) => t.id.equals(entry.id))).go();
        } else {
          await (db.update(db.syncOutbox)
                ..where((t) => t.id.equals(entry.id)))
              .write(SyncOutboxCompanion(attempts: Value(attempts)));
        }
      }
    }
    return uploaded;
  }

  /// Number of queued server shares still waiting to upload.
  Future<int> pendingCount() async {
    final count = db.syncOutbox.id.count();
    final query = db.selectOnly(db.syncOutbox)
      ..addColumns([count])
      ..where(db.syncOutbox.entity.equals(_entity));
    final row = await query.getSingle();
    return row.read(count) ?? 0;
  }
}
