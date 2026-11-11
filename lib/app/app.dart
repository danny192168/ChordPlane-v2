import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/settings/settings.dart';
import 'router.dart';
import 'theme/app_theme.dart';

class ChordPlaneApp extends ConsumerWidget {
  const ChordPlaneApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final router = ref.watch(routerProvider);

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
