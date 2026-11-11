import 'package:chord_diagrams/chord_diagrams.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'app/deep_links.dart';
import 'app/router.dart';
import 'core/settings/settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final preferences = await SharedPreferences.getInstance();
  final initialRoute = routeForIncomingLink(
    WidgetsBinding.instance.platformDispatcher.defaultRouteName,
  );
  try {
    await ChordDiagrams.ensureInitialized();
  } catch (error, stack) {
    debugPrint('Chord diagram renderer failed to initialise: $error');
    debugPrintStack(stackTrace: stack);
  }

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        initialLocationProvider.overrideWithValue(initialRoute),
      ],
      child: const ChordPlaneApp(),
    ),
  );
}
