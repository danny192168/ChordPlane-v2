import 'package:chord_diagrams/chord_diagrams.dart';
import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import 'viewer_screen.dart';

/// Entry point for the public web viewer served at
/// `https://chordplane.citcs.site/s/<token>`.
///
/// This is deliberately NOT the full app: no database, no auth, no router —
/// just the chord parser, the app theme, and a read-only view of a shared
/// snapshot fetched anonymously from Supabase.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await ChordDiagrams.ensureInitialized();
  } catch (error) {
    // Diagrams are an enhancement; the sheet still renders without them.
    debugPrint('Chord diagram renderer failed to initialise: $error');
  }

  final token = viewerTokenFromUri(Uri.base);
  runApp(ChordPlaneViewerApp(token: token));
}

/// Pulls the share token out of the page URL: `…/s/<token>`.
String? viewerTokenFromUri(Uri uri) {
  final segments = uri.pathSegments;
  final index = segments.indexOf('s');
  if (index < 0 || index + 1 >= segments.length) return null;
  final token = segments[index + 1];
  // Same shape rule as the app's server-token extraction.
  if (token.length < 8 || token.length > 24) return null;
  if (!RegExp(r'^[A-Za-z0-9]+$').hasMatch(token)) return null;
  return token;
}

class ChordPlaneViewerApp extends StatelessWidget {
  const ChordPlaneViewerApp({super.key, required this.token});

  final String? token;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ChordPlane',
      debugShowCheckedModeBanner: false,
      theme: ChordPlaneTheme.light(),
      darkTheme: ChordPlaneTheme.dark(),
      themeMode: ThemeMode.system,
      home: ViewerScreen(token: token),
    );
  }
}
