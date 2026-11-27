import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_gateway.dart';
import '../../../core/config/app_config.dart';
import '../../songs/data/song_repository.dart';
import 'community_api.dart';

/// Every upload owned by the signed-in account. The Profile panel and its tab
/// count share this one request. Offline it falls back to published copies
/// already kept on the device; if there are none, the error reaches the UI.
final myUploadsProvider = FutureProvider<List<CommunitySong>>((ref) async {
  final repository = ref.read(songRepositoryProvider);
  final cloudReady =
      AppConfig.hasSupabase && AppConfig.supabaseInitError == null;
  if (!cloudReady) return repository.cachedUploads();

  final signedIn =
      ref.watch(signedInProvider).value ??
      ref.read(authGatewayProvider).isSignedIn;
  if (!signedIn) return const <CommunitySong>[];

  try {
    return await ref
        .read(communityApiProvider)
        .myUploads()
        .timeout(const Duration(seconds: 10));
  } catch (_) {
    final cached = await repository.cachedUploads();
    if (cached.isEmpty) rethrow;
    return cached;
  }
});

/// One published song, falling back to the offline copy when the request
/// fails. Opening a community song stores that copy on the device.
final communitySongProvider = FutureProvider.family<CommunitySong?, String>((
  ref,
  id,
) async {
  final repository = ref.read(songRepositoryProvider);
  if (AppConfig.supabaseInitError == null && AppConfig.hasSupabase) {
    try {
      final song = await ref.read(communityApiProvider).byId(id);
      if (song != null) await repository.cacheCommunitySongs([song]);
      return song;
    } catch (_) {
      // Fall through to the offline copy.
    }
  }
  return repository.cachedCommunitySong(id);
});

final ratingEligibilityProvider = FutureProvider<RatingEligibility>((ref) async {
  if (AppConfig.supabaseInitError != null || !AppConfig.hasSupabase) {
    return const RatingEligibility(
      allowed: false,
      reasons: ['Cloud features are not configured in this build.'],
      accountAgeDays: 0,
      activeDays: 0,
    );
  }
  ref.watch(signedInProvider);
  return ref.read(communityApiProvider).ratingEligibility();
});
