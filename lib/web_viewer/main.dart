import 'package:chord_diagrams/chord_diagrams.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import 'viewer_screen.dart';

/// Entry point for the public web viewer served at
/// `https://chordplane.citcs.site/s/<token>`.
///
/// This is deliberately NOT the full app: no database, no auth — just the
/// chord parser, the app theme, and a read-only view of a shared snapshot
/// fetched anonymously from Supabase.
///
/// Routes mirror the app-link surface so the same URL works everywhere:
/// `/s/<token>` — the set-list overview (or a single shared song),
/// `/s/<token>/<n>` — directly into song n. The app's universal-link
/// handler accepts both shapes too.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await ChordDiagrams.ensureInitialized();
  } catch (error) {
    // Diagrams are an enhancement; the sheet still renders without them.
    debugPrint('Chord diagram renderer failed to initialise: $error');
  }

  final router = GoRouter(
    // Friendly pages instead of a raw GoException dump for the bare domain
    // and any unknown path.
    errorBuilder: (context, state) => const NotFoundScreen(),
    routes: [
      GoRoute(path: '/', builder: (context, state) => const HomeLandingScreen()),
      GoRoute(
        path: '/s/:token',
        builder: (context, state) => SetlistListScreen(
          token: state.pathParameters['token']!,
        ),
      ),
      GoRoute(
        path: '/s/:token/:song',
        builder: (context, state) {
          final index = int.tryParse(state.pathParameters['song'] ?? '') ?? 0;
          return SongScreen(
            token: state.pathParameters['token']!,
            songIndex: index,
          );
        },
      ),
    ],
  );

  runApp(ChordPlaneViewerApp(router: router));
}

class ChordPlaneViewerApp extends StatelessWidget {
  const ChordPlaneViewerApp({super.key, required this.router});

  final GoRouter router;

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'ChordPlane',
      debugShowCheckedModeBanner: false,
      theme: ChordPlaneTheme.light(),
      darkTheme: ChordPlaneTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: router,
    );
  }
}
