import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/auth_gateway.dart';
import '../../../core/config/app_config.dart';
import '../../songs/data/song_repository.dart';
import '../cpl.dart';
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
  });

  final ShareCloudApi api;
  final ShareOutbox outbox;
  final AuthGateway auth;

  /// Creates a new share for [bundle]. Existing shares are left untouched —
  /// call [update] to re-push a snapshot to a token you already made.
  Future<ServerShareResult> share(CplBundle bundle) {
    return _upload(generateShareToken(), bundle);
  }

  /// Re-pushes [bundle] to an existing share, replacing its snapshot.
  Future<ServerShareResult> update(String token, CplBundle bundle) {
    return _upload(token, bundle);
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
