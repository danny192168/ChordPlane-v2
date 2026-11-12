import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/auth_gateway.dart';
import '../core/settings/settings.dart';
import '../features/sharing/cloud/server_share_service.dart';
import 'router.dart';
import 'theme/app_theme.dart';

class ChordPlaneApp extends ConsumerStatefulWidget {
  const ChordPlaneApp({super.key});

  @override
  ConsumerState<ChordPlaneApp> createState() => _ChordPlaneAppState();
}

class _ChordPlaneAppState extends ConsumerState<ChordPlaneApp> {
  @override
  void initState() {
    super.initState();
    // Drain any shares queued offline once, at start, if already signed in.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(signedInProvider).value == true) {
        ref.read(shareOutboxProvider).flush();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final router = ref.watch(routerProvider);

    // A share created offline is queued in the outbox; drain it as soon as
    // the user is signed in again.
    ref.listen(signedInProvider, (previous, next) {
      if (previous?.value == false && next.value == true) {
        ref.read(shareOutboxProvider).flush();
      }
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
