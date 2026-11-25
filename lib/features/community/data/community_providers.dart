import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_gateway.dart';
import '../../../core/config/app_config.dart';
import '../../songs/data/song_repository.dart';
import 'community_api.dart';

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
