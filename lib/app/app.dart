import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/auth/auth_gateway.dart';
import '../core/config/app_config.dart';
import '../core/settings/settings.dart';
import '../features/community/data/community_api.dart';
import '../features/community/presentation/username_sheet.dart';
import '../features/sharing/cloud/server_share_service.dart';
import '../features/songs/data/song_providers.dart';
import 'incoming_files.dart';
import 'router.dart';
import 'theme/app_theme.dart';

class ChordPlaneApp extends ConsumerStatefulWidget {
  const ChordPlaneApp({super.key});

  @override
  ConsumerState<ChordPlaneApp> createState() => _ChordPlaneAppState();
}

class _ChordPlaneAppState extends ConsumerState<ChordPlaneApp> {
  bool _communityPreparationStarted = false;

  @override
  void initState() {
    super.initState();
    // Drain any shares queued offline once, at start, if already signed in.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(authGatewayProvider).isSignedIn) {
        ref.read(shareOutboxProvider).flush();
        _prepareCommunityAccount();
      }
    });
  }

  /// Records the day of use for the rating gate and asks older accounts to
  /// choose a username once. Both are safe to repeat on every launch.
  Future<void> _prepareCommunityAccount() async {
    if (_communityPreparationStarted) return;
    _communityPreparationStarted = true;
    if (!AppConfig.hasSupabase || AppConfig.supabaseInitError != null) return;
    final api = ref.read(communityApiProvider);
    try {
      await api.recordActiveDay();
      // Union device favorites with the account's cloud favorites. Local rows
      // stay on the device; both sides are idempotent on later sign-ins.
      ref.read(favoritesSyncProvider);
      final username = await api.currentUsername();
      if (username != null && username.trim().isNotEmpty) return;
      final context = rootNavigatorKey.currentContext;
      if (context == null || !context.mounted) return;
      await showUsernameSheet(context);
    } catch (error) {
      debugPrint('Could not prepare community account: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final router = ref.watch(routerProvider);

    // A share created offline is queued in the outbox; drain it as soon as
    // the user is signed in again.
    ref.listen(signedInProvider, (previous, next) {
      if (next.value != true) {
        if (next.value == false) _communityPreparationStarted = false;
        return;
      }
      if (previous?.value == true) return;
      ref.read(shareOutboxProvider).flush();
      ref.read(favoritesSyncProvider);
      _prepareCommunityAccount();
    });

    // A password-reset link signs the member in without asking for a
    // password; send them straight to the screen that sets one.
    ref.listen(authEventProvider, (previous, next) {
      if (next.value != AuthChangeEvent.passwordRecovery) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(routerProvider).go('/set-new-password');
      });
    });

    // A .cpl file opened from another app lands in Import at the same decoder
    // used by the in-app file picker.
    ref.listen(incomingFilePathProvider, (previous, next) {
      final path = next.value;
      if (path == null || path == previous?.value) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref
            .read(routerProvider)
            .go('/import?file=${Uri.encodeComponent(path)}');
      });
    });

    return MaterialApp.router(
      title: 'ChordPlane',
      debugShowCheckedModeBanner: false,
      theme: ChordPlaneTheme.light(),
      darkTheme: ChordPlaneTheme.dark(),
      themeMode: settings.themeMode,
      routerConfig: router,
      builder: (context, child) => child ?? const SizedBox.shrink(),
    );
  }
}
