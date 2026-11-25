import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/auth_gateway.dart';
import '../../../core/chords/chord_detection.dart';
import '../../../core/config/app_config.dart';
import '../../sharing/cpl.dart';

/// Maps the portable song into the snake-case columns of `community_songs`.
extension _CplSongRow on CplSong {
  Map<String, dynamic> toRow() => {
    'title': title.trim(),
    'artist': artist.trim(),
    'body': body,
    'original_key': originalKey.trim(),
    'chord_detection_mode': chordDetectionMode.storageKey,
    'capo': capo.clamp(0, 12),
    'tempo': tempo,
    'instrument': instrument,
    'tuning': tuning,
    'youtube_url': youtubeUrl.trim(),
    'tags': tags.trim(),
  };
}

/// A song published to the community catalog. The uploader is credited from
/// their profile unless they chose to publish anonymously.
class CommunitySong {
  const CommunitySong({
    required this.id,
    required this.title,
    required this.artist,
    required this.body,
    required this.originalKey,
    required this.chordDetectionMode,
    required this.capo,
    required this.tempo,
    required this.instrument,
    required this.tuning,
    required this.youtubeUrl,
    required this.tags,
    required this.anonymous,
    required this.username,
    required this.createdAt,
    required this.ratingSum,
    required this.ratingCount,
  });

  factory CommunitySong.fromJson(Map<String, dynamic> json) {
    final profile = json['profiles'];
    final rawUsername = profile is Map ? profile['username'] as String? : null;
    final trimmedUsername = rawUsername?.trim();
    final username = (trimmedUsername == null || trimmedUsername.isEmpty)
        ? null
        : trimmedUsername;
    return CommunitySong(
      id: json['id'] as String,
      title: (json['title'] as String?) ?? '',
      artist: (json['artist'] as String?) ?? '',
      body: (json['body'] as String?) ?? '',
      originalKey: (json['original_key'] as String?) ?? '',
      chordDetectionMode: ChordDetectionMode.fromStorage(
        (json['chord_detection_mode'] as String?) ?? 'auto',
      ),
      capo: (json['capo'] as int?) ?? 0,
      tempo: json['tempo'] as int?,
      instrument: (json['instrument'] as String?) ?? 'guitar',
      tuning: (json['tuning'] as String?) ?? 'standard',
      youtubeUrl: (json['youtube_url'] as String?) ?? '',
      tags: (json['tags'] as String?) ?? '',
      anonymous: (json['anonymous'] as bool?) ?? false,
      username: username,
      createdAt: DateTime.tryParse((json['created_at'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      ratingSum: (json['rating_sum'] as int?) ?? 0,
      ratingCount: (json['rating_count'] as int?) ?? 0,
    );
  }

  final String id;
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
  final bool anonymous;
  final String? username;
  final DateTime createdAt;
  final int ratingSum;
  final int ratingCount;

  String get credit => anonymous
      ? 'Anonymous'
      : username == null
      ? 'Community member'
      : '@$username';

  double get ratingAverage =>
      ratingCount == 0 ? 0 : ratingSum / ratingCount;

  CplSong toCplSong() => CplSong(
    title: title,
    artist: artist,
    body: body,
    originalKey: originalKey,
    chordDetectionMode: chordDetectionMode,
    capo: capo,
    tempo: tempo,
    instrument: instrument,
    tuning: tuning,
    youtubeUrl: youtubeUrl,
    tags: tags,
  );

  Map<String, dynamic> toRow() => {
    'title': title.trim(),
    'artist': artist.trim(),
    'body': body,
    'original_key': originalKey.trim(),
    'chord_detection_mode': chordDetectionMode.storageKey,
    'capo': capo.clamp(0, 12),
    'tempo': tempo,
    'instrument': instrument,
    'tuning': tuning,
    'youtube_url': youtubeUrl.trim(),
    'tags': tags.trim(),
    'anonymous': anonymous,
  };
}

class RatingEligibility {
  const RatingEligibility({
    required this.allowed,
    required this.reasons,
    required this.accountAgeDays,
    required this.activeDays,
  });

  factory RatingEligibility.fromJson(Map<String, dynamic> json) {
    final raw = json['reasons'];
    return RatingEligibility(
      allowed: (json['allowed'] as bool?) ?? false,
      reasons: raw is List
          ? [for (final item in raw) item.toString()]
          : const [],
      accountAgeDays: (json['accountAgeDays'] as int?) ?? 0,
      activeDays: (json['activeDays'] as int?) ?? 0,
    );
  }

  final bool allowed;
  final List<String> reasons;
  final int accountAgeDays;
  final int activeDays;
}

class MyRating {
  const MyRating({required this.score, required this.comment});

  final int score;
  final String comment;
}

/// Account details shown on the Profile screen.
class ProfileInfo {
  const ProfileInfo({
    required this.displayName,
    required this.username,
    required this.email,
  });

  final String displayName;
  final String username;
  final String email;

  String get nameForAvatar {
    final trimmed = displayName.trim();
    if (trimmed.isNotEmpty) return trimmed;
    if (username.trim().isNotEmpty) return username.trim();
    if (email.trim().isNotEmpty) return email.trim().split('@').first;
    return 'ChordPlane';
  }
}

class CommunityException implements Exception {
  const CommunityException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Everything the community screens need from Supabase, behind an interface
/// so the UI can be exercised with a fake client in tests.
abstract interface class CommunityApi {
  Future<List<CommunitySong>> search(String query);

  /// Downloads the whole published catalog in pages for offline storage.
  Future<List<CommunitySong>> downloadAll();

  Future<List<CommunitySong>> myUploads();

  Future<CommunitySong?> byId(String id);

  Future<CommunitySong> publish(CplSong song, {required bool anonymous});

  Future<void> updatePublished(
    String remoteId,
    CplSong song, {
    required bool anonymous,
  });

  Future<void> unpublish(String remoteId);

  Future<RatingEligibility> ratingEligibility();

  Future<MyRating?> myRating(String songId);

  Future<void> rate(String songId, int score, String comment);

  Future<void> recordActiveDay();

  Future<String?> currentUsername();

  /// Remote ids of community songs the signed-in account has favorited.
  Future<Set<String>> myFavorites();

  Future<void> setFavorite(String songId, {required bool favorite});

  Future<ProfileInfo> currentProfile();

  Future<void> setDisplayName(String displayName);

  Future<Map<String, dynamic>> checkUsername(String candidate);

  Future<bool> setUsername(String candidate);
}

class SupabaseCommunityApi implements CommunityApi {
  const SupabaseCommunityApi(this._client);

  final SupabaseClient _client;

  static const _columns =
      '*, profiles!community_songs_owner_profile_fkey(username)';

  String _cleanQuery(String raw) {
    final trimmed = raw.trim();
    if (trimmed.length > 60) return trimmed.substring(0, 60);
    // PostgREST filters use commas and parentheses as syntax; keep the search
    // text plain so a query cannot change the shape of the request.
    return trimmed.replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), ' ').trim();
  }

  /// Stale sessions are signed out once, then surfaced as a friendly message.
  Future<Never> _fail(Object error) async {
    if (isStaleUserError(error)) {
      await clearStaleAuthSession();
      throw const CommunityException(
        'That sign-in is no longer valid. You have been signed out — '
        'please sign in again.',
      );
    }
    throw CommunityException(_friendly(error.toString()));
  }

  @override
  Future<List<CommunitySong>> search(String query) async {
    try {
      var request = _client.from('community_songs').select(_columns);
      final term = _cleanQuery(query);
      if (term.isNotEmpty) {
        final pattern = '%$term%';
        request = request.or(
          'title.ilike.$pattern,artist.ilike.$pattern,tags.ilike.$pattern',
        );
      }
      final rows = await request
          .eq('moderation_status', 'published')
          .order('created_at', ascending: false)
          .limit(50);
      return [for (final row in rows) CommunitySong.fromJson(row)];
    } on PostgrestException catch (error) {
      await _fail(error);
    }
  }

  @override
  Future<List<CommunitySong>> downloadAll() async {
    const pageSize = 200;
    final songs = <CommunitySong>[];
    var start = 0;
    try {
      while (true) {
        final rows = await _client
            .from('community_songs')
            .select(_columns)
            .eq('moderation_status', 'published')
            .order('created_at', ascending: false)
            .range(start, start + pageSize - 1);
        final page = [for (final row in rows) CommunitySong.fromJson(row)];
        songs.addAll(page);
        if (page.length < pageSize) break;
        start += pageSize;
      }
      return songs;
    } on PostgrestException catch (error) {
      await _fail(error);
    }
  }

  @override
  Future<List<CommunitySong>> myUploads() async {
    try {
      final rows = await _client
          .from('community_songs')
          .select(_columns)
          .eq('owner', _client.auth.currentUser?.id ?? '')
          .order('created_at', ascending: false)
          .limit(50);
      return [for (final row in rows) CommunitySong.fromJson(row)];
    } on PostgrestException catch (error) {
      await _fail(error);
    }
  }

  @override
  Future<CommunitySong?> byId(String id) async {
    try {
      final row = await _client
          .from('community_songs')
          .select(_columns)
          .eq('id', id)
          .maybeSingle();
      return row == null ? null : CommunitySong.fromJson(row);
    } on PostgrestException catch (error) {
      await _fail(error);
    }
  }

  @override
  Future<CommunitySong> publish(
    CplSong song, {
    required bool anonymous,
  }) async {
    try {
      final row = song.toRow()
        ..['owner'] = _client.auth.currentUser?.id
        ..['anonymous'] = anonymous;
      final created = await _client
          .from('community_songs')
          .insert(row)
          .select(_columns)
          .single();
      return CommunitySong.fromJson(created);
    } on PostgrestException catch (error) {
      await _fail(error);
    }
  }

  @override
  Future<void> updatePublished(
    String remoteId,
    CplSong song, {
    required bool anonymous,
  }) async {
    try {
      final row = song.toRow()..['anonymous'] = anonymous;
      await _client
          .from('community_songs')
          .update(row)
          .eq('id', remoteId)
          .eq('owner', _client.auth.currentUser?.id ?? '');
    } on PostgrestException catch (error) {
      await _fail(error);
    }
  }

  @override
  Future<void> unpublish(String remoteId) async {
    try {
      await _client
          .from('community_songs')
          .delete()
          .eq('id', remoteId)
          .eq('owner', _client.auth.currentUser?.id ?? '');
    } on PostgrestException catch (error) {
      await _fail(error);
    }
  }

  @override
  Future<RatingEligibility> ratingEligibility() async {
    try {
      final result = await _client.rpc('can_rate_songs');
      return RatingEligibility.fromJson(Map<String, dynamic>.from(result as Map));
    } on PostgrestException catch (error) {
      await _fail(error);
    }
  }

  @override
  Future<MyRating?> myRating(String songId) async {
    try {
      final row = await _client
          .from('song_ratings')
          .select('score,comment')
          .eq('song_id', songId)
          .eq('user_id', _client.auth.currentUser?.id ?? '')
          .maybeSingle();
      if (row == null) return null;
      return MyRating(
        score: (row['score'] as int?) ?? 0,
        comment: (row['comment'] as String?) ?? '',
      );
    } on PostgrestException catch (error) {
      await _fail(error);
    }
  }

  @override
  Future<void> rate(String songId, int score, String comment) async {
    try {
      await _client.from('song_ratings').upsert({
        'song_id': songId,
        'user_id': _client.auth.currentUser?.id,
        'score': score.clamp(1, 5),
        'comment': comment.trim(),
      }, onConflict: 'song_id,user_id');
    } on PostgrestException catch (error) {
      await _fail(error);
    }
  }

  @override
  Future<void> recordActiveDay() async {
    if (_client.auth.currentUser == null) return;
    try {
      await _client.rpc('record_active_day');
    } on PostgrestException {
      // An eligibility function that has not been installed yet must not
      // break the app. The UI reports the gate from `ratingEligibility`.
    }
  }

  @override
  Future<String?> currentUsername() async {
    if (_client.auth.currentUser == null) return null;
    try {
      final row = await _client
          .from('profiles')
          .select('username')
          .eq('id', _client.auth.currentUser!.id)
          .maybeSingle();
      return row?['username'] as String?;
    } on PostgrestException catch (error) {
      await _fail(error);
    }
  }

  @override
  Future<Set<String>> myFavorites() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return const <String>{};
    try {
      final rows = await _client
          .from('song_favorites')
          .select('song_id')
          .eq('user_id', userId);
      return {for (final row in rows) row['song_id'] as String};
    } on PostgrestException catch (error) {
      await _fail(error);
    }
  }

  @override
  Future<void> setFavorite(String songId, {required bool favorite}) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      if (favorite) {
        await _client.from('song_favorites').upsert(
          {'user_id': userId, 'song_id': songId},
          onConflict: 'user_id,song_id',
        );
      } else {
        await _client
            .from('song_favorites')
            .delete()
            .eq('user_id', userId)
            .eq('song_id', songId);
      }
    } on PostgrestException catch (error) {
      await _fail(error);
    }
  }

  @override
  Future<ProfileInfo> currentProfile() async {
    final user = _client.auth.currentUser;
    final fallback = ProfileInfo(
      displayName: (user?.userMetadata?['display_name'] as String?)?.trim() ?? '',
      username: (user?.userMetadata?['username'] as String?)?.trim() ?? '',
      email: user?.email ?? '',
    );
    if (user == null) return fallback;
    try {
      final row = await _client
          .from('profiles')
          .select('display_name,username')
          .eq('id', user.id)
          .maybeSingle();
      if (row == null) return fallback;
      return ProfileInfo(
        displayName: (row['display_name'] as String?)?.trim() ??
            fallback.displayName,
        username: (row['username'] as String?)?.trim() ?? fallback.username,
        email: fallback.email,
      );
    } on PostgrestException catch (error) {
      await _fail(error);
    }
  }

  @override
  Future<void> setDisplayName(String displayName) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await _client
          .from('profiles')
          .update({'display_name': displayName.trim()})
          .eq('id', userId);
    } on PostgrestException catch (error) {
      await _fail(error);
    }
  }

  @override
  Future<Map<String, dynamic>> checkUsername(String candidate) async {
    try {
      final result = await _client.rpc(
        'check_username_available',
        params: {'candidate': candidate},
      );
      return Map<String, dynamic>.from(result as Map);
    } on PostgrestException catch (error) {
      await _fail(error);
    }
  }

  @override
  Future<bool> setUsername(String candidate) async {
    try {
      final result = await _client.rpc(
        'set_username',
        params: {'candidate': candidate},
      );
      return (result as Map)['ok'] == true;
    } on PostgrestException catch (error) {
      await _fail(error);
    }
  }

  String _friendly(String message) {
    if (isStaleUserError(message)) {
      return 'That sign-in is no longer valid. You have been signed out — '
          'please sign in again.';
    }
    if (message.contains('JWT') ||
        message.contains('permission denied') ||
        message.contains('row-level security')) {
      return 'Cloud access was rejected. Check your account and try again.';
    }
    if (message.toLowerCase().contains('failed to fetch') ||
        message.toLowerCase().contains('connection')) {
      return 'No connection. Try again when you are back online.';
    }
    if (message.contains('schema cache') || message.contains('42703')) {
      return 'The Public Library database is not set up yet. Apply the latest '
          'Supabase migrations and try again.';
    }
    return message;
  }
}

final communityApiProvider = Provider<CommunityApi>((ref) {
  if (AppConfig.supabaseInitError != null || !AppConfig.hasSupabase) {
    throw StateError(AppConfig.supabaseInitError ?? 'Cloud is not configured.');
  }
  return SupabaseCommunityApi(Supabase.instance.client);
});
