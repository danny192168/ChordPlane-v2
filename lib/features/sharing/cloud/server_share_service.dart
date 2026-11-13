import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/auth_gateway.dart';
import '../../../core/config/app_config.dart';
import '../../../core/db/app_database.dart';
import '../../songs/data/song_repository.dart';
import '../cpl.dart';
import '../share_service.dart';
import 'share_cloud.dart';
import 'share_outbox.dart';

/// Thrown when a server share is attempted while signed out — the UI should
/// open the sign-in gate instead of queueing.
class SignInRequiredException implements Exception {
  const SignInRequiredException();

  @override
  String toString() => 'Sign in to share with a cloud link.';
}

/// Where a share ended up after [ServerShareService.share].
enum ShareUpload { uploaded, queued }

class ServerShareResult {
  const ServerShareResult({required this.token, required this.upload});

  final String token;
  final ShareUpload upload;
}

final shareCloudApiProvider = Provider<ShareCloudApi>((ref) {
  if (!AppConfig.hasSupabase) {
    throw StateError('Cloud sharing is not configured in this build.');
  }
  return SupabaseShareApi(Supabase.instance.client);
});

final shareOutboxProvider = Provider<ShareOutbox>((ref) {
  return ShareOutbox(
    db: ref.watch(databaseProvider),
    api: ref.watch(shareCloudApiProvider),
  );
});

final serverShareServiceProvider = Provider<ServerShareService>((ref) {
  return ServerShareService(
    api: ref.watch(shareCloudApiProvider),
    outbox: ref.watch(shareOutboxProvider),
    auth: ref.watch(authGatewayProvider),
    db: ref.watch(databaseProvider),
  );
});

/// Turns bundles into server-backed share links.
///
/// Uploads happen immediately when online; network failures fall back to the
/// [ShareOutbox] so the share survives until connectivity returns. Auth or
/// policy rejections are surfaced, never queued.
class ServerShareService {
  ServerShareService({
    required this.api,
    required this.outbox,
    required this.auth,
    required this.db,
  });

  final ShareCloudApi api;
  final ShareOutbox outbox;
  final AuthGateway auth;
  final AppDatabase db;

  /// Creates a new share for [bundle]. Existing shares are left untouched —
  /// call [update] to re-push a snapshot to a token you already made.
  ///
  /// When [localId] is given, the token is remembered against the local song
  /// or setlist it was made from so [bundleForUpdate] can rebuild it later.
  Future<ServerShareResult> share(CplBundle bundle, {String? localId}) async {
    final result = await _upload(generateShareToken(), bundle);
    if (localId != null) {
      await _rememberLink(result.token, bundle, localId);
    }
    return result;
  }

  /// Re-pushes [bundle] to an existing share, replacing its snapshot.
  Future<ServerShareResult> update(String token, CplBundle bundle) async {
    final result = await _upload(token, bundle);
    await (db.update(db.sharedLinks)..where((t) => t.token.equals(token)))
        .write(SharedLinksCompanion(
      title: Value(bundle.title),
      lastPushedAt: Value(DateTime.now()),
    ));
    return result;
  }

  Future<ServerShareResult> _upload(String token, CplBundle bundle) async {
    if (!auth.isSignedIn) {
      throw const SignInRequiredException();
    }
    final record = ShareRecord(
      token: token,
      kind: bundle.kind.name,
      title: bundle.title,
      snapshot: bundle.toJson(),
    );
    try {
      await api.upsertShare(record);
      return ServerShareResult(token: token, upload: ShareUpload.uploaded);
    } on ShareCloudException catch (error) {
      if (error.kind != ShareCloudError.network) rethrow;
      await outbox.enqueue(record);
      return ServerShareResult(token: token, upload: ShareUpload.queued);
    }
  }

  Future<void> _rememberLink(
    String token,
    CplBundle bundle,
    String localId,
  ) async {
    final row = await (db.select(
      db.sharedLinks,
    )..where((t) => t.token.equals(token))).getSingleOrNull();
    if (row != null) {
      await (db.update(db.sharedLinks)..where((t) => t.token.equals(token)))
          .write(SharedLinksCompanion(
        kind: Value(bundle.kind.name),
        localId: Value(localId),
        title: Value(bundle.title),
        lastPushedAt: Value(DateTime.now()),
      ));
      return;
    }
    await db.into(db.sharedLinks).insert(
      SharedLinksCompanion.insert(
        token: token,
        kind: bundle.kind.name,
        localId: localId,
        title: Value(bundle.title),
        createdAt: DateTime.now(),
        lastPushedAt: DateTime.now(),
      ),
    );
  }

  /// The signed-in user's shares, newest first.
  Future<List<ShareRecord>> myShares() => api.listMyShares();

  /// Revokes (or restores) one of the user's shares.
  Future<void> setRevoked(String token, {required bool revoked}) =>
      api.setRevoked(token, revoked: revoked);

  /// Rebuilds the bundle for a share from the local content it was created
  /// from. Returns null when the token has no local mapping, or when that
  /// song/setlist no longer exists (including soft-deleted) — re-share
  /// instead.
  Future<CplBundle?> bundleForUpdate(String token, ShareService shares) async {
    final row = await (db.select(
      db.sharedLinks,
    )..where((t) => t.token.equals(token))).getSingleOrNull();
    if (row == null) return null;
    final exists = row.kind == CplKind.setlist.name
        ? await _setlistExists(row.localId)
        : await _songExists(row.localId);
    if (!exists) return null;
    try {
      return row.kind == CplKind.setlist.name
          ? await shares.bundleForSetlist(row.localId)
          : await shares.bundleForSong(row.localId);
    } on CplException {
      return null;
    }
  }

  /// True when the mapped song still exists and is not soft-deleted.
  Future<bool> _songExists(String id) async {
    final found = await (db.select(db.songs)
          ..where((t) => t.id.equals(id) & t.deletedAt.isNull()))
        .get();
    return found.isNotEmpty;
  }

  /// True when the mapped setlist still exists and is not soft-deleted.
  Future<bool> _setlistExists(String id) async {
    final found = await (db.select(db.setlists)
          ..where((t) => t.id.equals(id) & t.deletedAt.isNull()))
        .get();
    return found.isNotEmpty;
  }

  /// Anonymous fetch for the import flow.
  Future<({CplBundle bundle, ShareRecord record})?> fetch(String token) async {
    final record = await api.findShare(token);
    if (record == null) return null;
    return (
      bundle: CplBundle.decodeJson(jsonEncode(record.snapshot)),
      record: record,
    );
  }

  /// Drains the outbox; used at app start and after sign-in.
  Future<int> flushOutbox() => outbox.flush();
}
