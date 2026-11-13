import 'dart:io';
import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

/// A server-backed share stored in the `shared_bundles` table.
///
/// The [token] is the secret: links carry it, and anonymous read access is
/// granted by knowing it. Snapshots are plain `.cpl` bundle JSON.
class ShareRecord {
  const ShareRecord({
    required this.token,
    required this.kind,
    required this.title,
    required this.snapshot,
    this.status = 'active',
    this.revoked = false,
    this.viewCount = 0,
    this.updatedAt,
  });

  factory ShareRecord.fromJson(Map<String, dynamic> json) => ShareRecord(
    token: json['token'] as String,
    kind: json['kind'] as String,
    title: (json['title'] as String?) ?? '',
    snapshot: (json['snapshot'] as Map).cast<String, dynamic>(),
    status: (json['status'] as String?) ?? 'active',
    revoked: (json['revoked'] as bool?) ?? false,
    viewCount: (json['view_count'] as int?) ?? 0,
    updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? ''),
  );

  final String token;
  final String kind; // 'song' | 'setlist'
  final String title;
  final Map<String, dynamic> snapshot;
  final String status; // 'active' | 'under_review' | 'removed'
  final bool revoked;
  final int viewCount;

  /// When the server last saw an update to this share. Kept only for display
  /// in "My shared links"; never written back.
  final DateTime? updatedAt;

  bool get isViewable => status == 'active' && !revoked;

  Map<String, dynamic> toJson() => {
    'token': token,
    'kind': kind,
    'title': title,
    'snapshot': snapshot,
    'status': status,
    'revoked': revoked,
    'view_count': viewCount,
  };

  /// The row written to Postgres. `view_count` is server-owned and never
  /// overwritten by an upsert, so it is deliberately left out here.
  Map<String, dynamic> toRow() => {
    'token': token,
    'kind': kind,
    'title': title,
    'snapshot': snapshot,
    'status': status,
    'revoked': revoked,
  };
}

/// Why an API call failed — the outbox only queues retryable failures.
enum ShareCloudError { network, auth, rejected }

class ShareCloudException implements Exception {
  const ShareCloudException(this.kind, this.message);

  final ShareCloudError kind;
  final String message;

  @override
  String toString() => message;
}

/// Transport-agnostic shares API so the outbox and UI can be tested against
/// fakes while [SupabaseShareApi] talks to the real backend.
abstract interface class ShareCloudApi {
  /// Creates a share, or replaces the snapshot of an existing token.
  Future<void> upsertShare(ShareRecord record);

  /// Anonymous lookup by token; null when the token is unknown or revoked.
  Future<ShareRecord?> findShare(String token);

  /// The signed-in user's shares, newest first.
  Future<List<ShareRecord>> listMyShares();

  /// Revokes (or restores) a share the user owns.
  Future<void> setRevoked(String token, {required bool revoked});
}

class SupabaseShareApi implements ShareCloudApi {
  SupabaseShareApi(this._client);

  final SupabaseClient _client;

  static const String _table = 'shared_bundles';

  @override
  Future<void> upsertShare(ShareRecord record) async {
    try {
      // RLS requires owner = auth.uid(); the record itself is user-agnostic,
      // so stamp the signed-in user here.
      final row = record.toRow()
        ..['owner'] = _client.auth.currentUser?.id;
      await _client.from(_table).upsert(row, onConflict: 'token');
    } on SocketException {
      throw const ShareCloudException(
        ShareCloudError.network,
        'No connection — the share was saved for later.',
      );
    } on AuthException catch (error) {
      throw ShareCloudException(ShareCloudError.auth, error.message);
    } on PostgrestException catch (error) {
      throw ShareCloudException(ShareCloudError.rejected, error.message);
    }
  }

  @override
  Future<ShareRecord?> findShare(String token) async {
    try {
      final row = await _client
          .from(_table)
          .select()
          .eq('token', token)
          .maybeSingle();
      if (row == null) return null;
      return ShareRecord.fromJson(row);
    } on SocketException {
      throw const ShareCloudException(
        ShareCloudError.network,
        'No connection — try again when you are back online.',
      );
    } on AuthException catch (error) {
      throw ShareCloudException(ShareCloudError.auth, error.message);
    } on PostgrestException catch (error) {
      throw ShareCloudException(ShareCloudError.rejected, error.message);
    }
  }

  @override
  Future<List<ShareRecord>> listMyShares() async {
    try {
      // RLS alone is not enough: the anon-read policy also matches this
      // query, which would return every active share on the server. Scope
      // explicitly to the signed-in user's rows.
      final rows = await _client
          .from(_table)
          .select()
          .eq('owner', _client.auth.currentUser?.id ?? '')
          .order('updated_at', ascending: false);
      return [for (final row in rows) ShareRecord.fromJson(row)];
    } on SocketException {
      throw const ShareCloudException(
        ShareCloudError.network,
        'No connection — try again when you are back online.',
      );
    } on AuthException catch (error) {
      throw ShareCloudException(ShareCloudError.auth, error.message);
    } on PostgrestException catch (error) {
      throw ShareCloudException(ShareCloudError.rejected, error.message);
    }
  }

  @override
  Future<void> setRevoked(String token, {required bool revoked}) async {
    try {
      await _client
          .from(_table)
          .update({'revoked': revoked})
          .eq('token', token);
    } on AuthException catch (error) {
      throw ShareCloudException(ShareCloudError.auth, error.message);
    } on PostgrestException catch (error) {
      throw ShareCloudException(ShareCloudError.rejected, error.message);
    }
  }
}

/// Unambiguous URL-safe alphabet (no 0/O/1/I/l).
const String _tokenAlphabet =
    'abcdefghjkmnpqrstuvwxyz23456789ABCDEFGHJKMNPQRSTUVWXYZ';

/// A share token doubles as the link secret, so it is random, unguessable,
/// and short enough to type. 14 characters of a 58-symbol alphabet ≈ 82 bits.
String generateShareToken([Random? random]) {
  final rng = random ?? Random.secure();
  return List.generate(
    14,
    (_) => _tokenAlphabet[rng.nextInt(_tokenAlphabet.length)],
  ).join();
}
