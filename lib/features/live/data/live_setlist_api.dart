import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/auth_gateway.dart';
import '../../../core/config/app_config.dart';
import '../../sharing/cpl.dart';
import '../../sharing/cloud/share_cloud.dart' show generateShareToken;

/// A live setlist is a link-backed document. Unlike a shared `.cpl` snapshot,
/// everyone with an eligible link can change it in place and see each other's
/// edits through Supabase Realtime.
class LiveSetlist {
  const LiveSetlist({
    required this.token,
    required this.title,
    required this.permission,
    required this.audience,
    required this.revoked,
    required this.createdAt,
    required this.updatedAt,
  });

  factory LiveSetlist.fromJson(Map<String, dynamic> json) => LiveSetlist(
    token: (json['token'] as String?) ?? '',
    title: (json['title'] as String?) ?? '',
    permission: (json['permission'] as String?) ?? 'view',
    audience: (json['audience'] as String?) ?? 'anyone',
    revoked: (json['revoked'] as bool?) ?? false,
    createdAt: DateTime.tryParse((json['created_at'] as String?) ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
    updatedAt: DateTime.tryParse((json['updated_at'] as String?) ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
  );

  final String token;
  final String title;

  /// Effective permission for the current viewer: owner, edit, comment, view
  /// or none. Computed by the server from the link settings and auth state.
  final String permission;
  final String audience;
  final bool revoked;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isOwner => permission == 'owner';
  bool get canEdit => isOwner || permission == 'edit';
  bool get canComment => canEdit || permission == 'comment';

  String get link => '${AppConfig.shareHost}/l/$token';

  String get permissionLabel => switch (permission) {
    'owner' => 'Host',
    'edit' => 'Can edit',
    'comment' => 'Can comment',
    _ => 'View only',
  };
}

class LiveSetlistItem {
  const LiveSetlistItem({
    required this.id,
    required this.songId,
    required this.title,
    required this.artist,
    required this.body,
    required this.originalKey,
    required this.capo,
    required this.position,
    required this.note,
    required this.updatedAt,
  });

  factory LiveSetlistItem.fromJson(Map<String, dynamic> json) =>
      LiveSetlistItem(
        id: (json['id'] as String?) ?? '',
        songId: (json['song_id'] as String?) ?? '',
        title: (json['title'] as String?) ?? '',
        artist: (json['artist'] as String?) ?? '',
        body: (json['body'] as String?) ?? '',
        originalKey: (json['original_key'] as String?) ?? '',
        capo: (json['capo'] as int?) ?? 0,
        position: (json['position'] as num?)?.toDouble() ?? 0,
        note: (json['note'] as String?) ?? '',
        updatedAt: DateTime.tryParse((json['updated_at'] as String?) ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );

  final String id;
  final String songId;
  final String title;
  final String artist;
  final String body;
  final String originalKey;
  final int capo;
  final double position;
  final String note;
  final DateTime updatedAt;

  LiveSetlistItem copyWith({
    String? note,
    String? body,
    String? originalKey,
    String? title,
    String? artist,
    int? capo,
  }) => LiveSetlistItem(
    id: id,
    songId: songId,
    title: title ?? this.title,
    artist: artist ?? this.artist,
    body: body ?? this.body,
    originalKey: originalKey ?? this.originalKey,
    capo: capo ?? this.capo,
    position: position,
    note: note ?? this.note,
    updatedAt: updatedAt,
  );
}

class LiveException implements Exception {
  const LiveException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class LiveSetlistApi {
  Future<LiveSetlist> create({
    required String title,
    required List<CplSong> songs,
    required String permission,
    required String audience,
  });

  Future<LiveSetlist?> byToken(String token);

  Future<List<LiveSetlistItem>> items(String token);

  Stream<List<LiveSetlistItem>> watchItems(String token);

  Future<void> setAccess(
    String token, {
    required String permission,
    required String audience,
  });

  Future<void> setRevoked(String token, {required bool revoked});

  Future<void> addItem(String token, CplSong song);

  Future<void> updateItem(
    LiveSetlistItem item, {
    String? note,
    String? body,
    String? originalKey,
    String? title,
    String? artist,
    int? capo,
  });

  Future<void> deleteItem(String id);

  Future<void> reorder(String token, List<LiveSetlistItem> items);
}

class SupabaseLiveSetlistApi implements LiveSetlistApi {
  const SupabaseLiveSetlistApi(this._client);

  final SupabaseClient _client;

  static const _itemColumns = '*';

  Future<Map<String, dynamic>> _access(String token) async {
    final result = await _client.rpc(
      'shared_setlist_access',
      params: {'target_token': token},
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<LiveSetlist> _withPermission(
    String token,
    Map<String, dynamic> row,
  ) async {
    final access = await _access(token);
    final json = Map<String, dynamic>.from(row)
      ..['permission'] = (access['permission'] as String?) ?? 'none';
    return LiveSetlist.fromJson(json);
  }

  Future<LiveException> _friendly(Object error) async {
    if (isStaleUserError(error)) {
      await clearStaleAuthSession();
      return const LiveException(
        'That sign-in is no longer valid. You have been signed out — '
        'please sign in again.',
      );
    }
    if (error is PostgrestException) {
      final message = error.message;
      if (message.contains('row-level security') ||
          message.contains('permission denied') ||
          message.contains('JWT')) {
        return const LiveException(
          'This link does not allow that change. Ask the host for access.',
        );
      }
      if (message.contains('only allows comments')) {
        return const LiveException('This link only allows comments.');
      }
      if (message.toLowerCase().contains('failed to fetch') ||
          message.toLowerCase().contains('connection')) {
        return const LiveException('No connection. Try again.');
      }
      if (message.contains('schema cache') || message.contains('42703')) {
        return const LiveException(
          'The live setlist database is not set up yet. Apply the latest '
          'Supabase migrations and try again.',
        );
      }
      return LiveException(message);
    }
    return LiveException('$error');
  }

  @override
  Future<LiveSetlist> create({
    required String title,
    required List<CplSong> songs,
    required String permission,
    required String audience,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw const LiveException('Sign in to start a live setlist.');
    }
    final token = generateShareToken();
    try {
      await _client.from('shared_setlists').insert({
        'token': token,
        'owner': userId,
        'title': title.trim().isEmpty ? 'Live setlist' : title.trim(),
        'permission': permission,
        'audience': audience,
      });
      for (var index = 0; index < songs.length; index++) {
        await _client.from('shared_setlist_items').insert({
          'setlist_token': token,
          'song_id': 'local-${DateTime.now().microsecondsSinceEpoch}-$index',
          'title': songs[index].title,
          'artist': songs[index].artist,
          'body': songs[index].body,
          'original_key': songs[index].originalKey,
          'capo': songs[index].capo,
          'position': index.toDouble(),
        });
      }
      final row = await _client
          .from('shared_setlists')
          .select()
          .eq('token', token)
          .single();
      return await _withPermission(token, row);
    } catch (error) {
      throw await _friendly(error);
    }
  }

  @override
  Future<LiveSetlist?> byToken(String token) async {
    try {
      final row = await _client
          .from('shared_setlists')
          .select()
          .eq('token', token)
          .maybeSingle();
      if (row == null) return null;
      return await _withPermission(token, row);
    } catch (error) {
      throw await _friendly(error);
    }
  }

  @override
  Future<List<LiveSetlistItem>> items(String token) async {
    try {
      final rows = await _client
          .from('shared_setlist_items')
          .select(_itemColumns)
          .eq('setlist_token', token)
          .order('position');
      return [for (final row in rows) LiveSetlistItem.fromJson(row)];
    } catch (error) {
      throw await _friendly(error);
    }
  }

  @override
  Stream<List<LiveSetlistItem>> watchItems(String token) {
    return _client
        .from('shared_setlist_items')
        .stream(primaryKey: ['id'])
        .eq('setlist_token', token)
        .order('position')
        .map((rows) => [
          for (final row in rows) LiveSetlistItem.fromJson(row),
        ]);
  }

  @override
  Future<void> setAccess(
    String token, {
    required String permission,
    required String audience,
  }) async {
    try {
      await _client
          .from('shared_setlists')
          .update({'permission': permission, 'audience': audience})
          .eq('token', token);
    } catch (error) {
      throw await _friendly(error);
    }
  }

  @override
  Future<void> setRevoked(String token, {required bool revoked}) async {
    try {
      await _client
          .from('shared_setlists')
          .update({'revoked': revoked})
          .eq('token', token);
    } catch (error) {
      throw await _friendly(error);
    }
  }

  @override
  Future<void> addItem(String token, CplSong song) async {
    try {
      final current = await items(token);
      final position = current.isEmpty
          ? 0.0
          : current.last.position + 1;
      await _client.from('shared_setlist_items').insert({
        'setlist_token': token,
        'song_id': 'local-${DateTime.now().microsecondsSinceEpoch}',
        'title': song.title,
        'artist': song.artist,
        'body': song.body,
        'original_key': song.originalKey,
        'capo': song.capo,
        'position': position,
      });
    } catch (error) {
      throw await _friendly(error);
    }
  }

  @override
  Future<void> updateItem(
    LiveSetlistItem item, {
    String? note,
    String? body,
    String? originalKey,
    String? title,
    String? artist,
    int? capo,
  }) async {
    final row = <String, dynamic>{};
    if (note != null) row['note'] = note;
    if (body != null) row['body'] = body;
    if (originalKey != null) row['original_key'] = originalKey;
    if (title != null) row['title'] = title;
    if (artist != null) row['artist'] = artist;
    if (capo != null) row['capo'] = capo;
    if (row.isEmpty) return;
    try {
      await _client
          .from('shared_setlist_items')
          .update(row)
          .eq('id', item.id);
    } catch (error) {
      throw await _friendly(error);
    }
  }

  @override
  Future<void> deleteItem(String id) async {
    try {
      await _client.from('shared_setlist_items').delete().eq('id', id);
    } catch (error) {
      throw await _friendly(error);
    }
  }

  @override
  Future<void> reorder(String token, List<LiveSetlistItem> items) async {
    // Positions are fractional so a move only writes the affected rows.
    try {
      for (var index = 0; index < items.length; index++) {
        final item = items[index];
        if (item.position == index.toDouble()) continue;
        await _client
            .from('shared_setlist_items')
            .update({'position': index.toDouble()})
            .eq('id', item.id);
      }
    } catch (error) {
      throw await _friendly(error);
    }
  }
}

final liveApiProvider = Provider<LiveSetlistApi>((ref) {
  if (AppConfig.supabaseInitError != null || !AppConfig.hasSupabase) {
    throw StateError(AppConfig.supabaseInitError ?? 'Cloud is not configured.');
  }
  return SupabaseLiveSetlistApi(Supabase.instance.client);
});
