import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_gateway.dart';
import '../../../core/config/app_config.dart';
import 'live_setlist_api.dart';

final liveSetlistProvider = FutureProvider.family<LiveSetlist?, String>((
  ref,
  token,
) async {
  if (AppConfig.supabaseInitError != null || !AppConfig.hasSupabase) {
    return null;
  }
  // Recompute the effective permission whenever auth changes: a link that
  // requires sign-in opens up as soon as the viewer signs in.
  ref.watch(signedInProvider);
  return ref.read(liveApiProvider).byToken(token);
});

final liveItemsProvider = StreamProvider.family<List<LiveSetlistItem>, String>((
  ref,
  token,
) {
  if (AppConfig.supabaseInitError != null || !AppConfig.hasSupabase) {
    return Stream.value(const <LiveSetlistItem>[]);
  }
  return ref.read(liveApiProvider).watchItems(token);
});
