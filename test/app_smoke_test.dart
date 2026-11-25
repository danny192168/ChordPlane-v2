import 'package:chord_plane/app/app_shell.dart';
import 'package:chord_plane/app/theme/app_theme.dart';
import 'package:chord_plane/core/db/app_database.dart';
import 'package:chord_plane/core/settings/settings.dart';
import 'package:chord_plane/features/library/favorites_screen.dart';
import 'package:chord_plane/features/library/library_screen.dart';
import 'package:chord_plane/features/library/saved_screen.dart';
import 'package:chord_plane/features/profile/profile_screen.dart';
import 'package:chord_plane/features/settings/settings_screen.dart';
import 'package:chord_plane/features/songs/data/song_repository.dart';
import 'package:chord_plane/features/songs/presentation/song_editor_screen.dart';
import 'package:chord_plane/features/songs/presentation/song_viewer_screen.dart';
import 'package:chord_plane/features/songs/presentation/artist_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Boots the real database, repositories and providers against in-memory
/// SQLite so the screens can be exercised without a device.
void main() {
  late AppDatabase database;
  late SharedPreferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    database = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  Widget wrap(Widget child) {
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(database),
        sharedPreferencesProvider.overrideWithValue(preferences),
      ],
      child: MaterialApp(theme: ChordPlaneTheme.light(), home: child),
    );
  }

  /// Like [wrap], but with the real four-tab shell so navigation and the
  /// artist drill-downs are exercised together.
  Widget wrapRouted() {
    final rootKey = GlobalKey<NavigatorState>(debugLabel: 'test-root');
    final router = GoRouter(
      navigatorKey: rootKey,
      initialLocation: '/',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) =>
              AppShell(navigationShell: navigationShell),
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/',
                  builder: (context, state) => const LibraryScreen(),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/saved',
                  builder: (context, state) => const SavedScreen(),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/favorites',
                  builder: (context, state) => const FavoritesScreen(),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/setlists',
                  builder: (context, state) => const SizedBox.shrink(),
                ),
              ],
            ),
          ],
        ),
        GoRoute(
          path: '/artist/:slug',
          parentNavigatorKey: rootKey,
          builder: (context, state) => ArtistScreen(
            slug: state.pathParameters['slug']!,
            favoritesOnly: state.uri.queryParameters['favorites'] == '1',
            savedOnly: state.uri.queryParameters['saved'] == '1',
          ),
        ),
        GoRoute(
          path: '/song/:id',
          parentNavigatorKey: rootKey,
          builder: (context, state) =>
              SongViewerScreen(songId: state.pathParameters['id']!),
        ),
      ],
    );
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(database),
        sharedPreferencesProvider.overrideWithValue(preferences),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        theme: ChordPlaneTheme.light(),
      ),
    );
  }

  /// Pumps frames until [finder] matches. Never use `pumpAndSettle` while a
  /// [CircularProgressIndicator] can be on screen: it spins forever.
  Future<void> pumpUntil(
    WidgetTester tester,
    Finder finder, {
    int frames = 100,
    Duration settle = const Duration(milliseconds: 400),
  }) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 40));
      if (finder.evaluate().isNotEmpty) {
        // Let modal sheets finish sliding in before tapping inside them.
        await tester.pump(settle);
        return;
      }
    }
    fail('Timed out waiting for $finder');
  }

  /// The default 800x600 test window cuts off the bottom sheets, so give the
  /// tests a phone-sized viewport.
  void phoneViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  /// Artist tiles are the only rows with a chevron; song tiles use a heart.
  Finder artistTile(String name) => find.ancestor(
    of: find.text(name),
    matching: find.widgetWithIcon(ListTile, Icons.chevron_right),
  );

  /// Tear the tree down inside the test so drift can flush the zero-duration
  /// timer it schedules when a query stream closes.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump(const Duration(milliseconds: 20));
  }

  testWidgets('library search and tabs drill into songs by artist', (
    tester,
  ) async {
    // One small artist keeps the artist tile on screen without scrolling.
    final repository = SongRepository(db: database, userId: 'local-user');
    await repository.saveDraft(
      draft: const SongDraft(
        title: 'Solo Song',
        artist: 'Solo Artist',
        originalKey: 'G',
      ),
    );

    phoneViewport(tester);
    await tester.pumpWidget(wrapRouted());
    await pumpUntil(tester, find.text('RECENTLY SAVED'));

    // Search is song-first, with a separate artist section underneath.
    await tester.enterText(find.byType(TextField), 'Solo Artist');
    await tester.pump(const Duration(milliseconds: 120));
    await pumpUntil(tester, find.text('SONGS'));
    await pumpUntil(tester, find.text('ARTISTS'));
    expect(find.text('Solo Song'), findsWidgets);
    expect(artistTile('Solo Artist'), findsOneWidget);

    // Open that artist and heart the song.
    await tester.tap(artistTile('Solo Artist'));
    await pumpUntil(tester, find.text('Solo Song'));
    await tester.tap(find.byIcon(Icons.favorite_border).first);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pageBack();
    await tester.pump(const Duration(milliseconds: 300));

    // Favorites tab shows only hearted songs, grouped by artist.
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Favorites'),
      ),
    );
    await pumpUntil(tester, artistTile('Solo Artist'));
    await tester.tap(artistTile('Solo Artist'));
    await pumpUntil(tester, find.text('Solo Song'));
    expect(find.text('Solo Song'), findsOneWidget);
    expect(find.text('Amazing Grace'), findsNothing);
    await tester.pageBack();
    await tester.pump(const Duration(milliseconds: 300));

    // Saved tab keeps every song, including the un-heartened starters.
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Saved'),
      ),
    );
    await pumpUntil(tester, artistTile('Solo Artist'));
    await tester.tap(artistTile('Solo Artist'));
    await pumpUntil(tester, find.text('Solo Song'));

    await unmount(tester);
  });

  testWidgets('song viewer renders chords and transposes', (tester) async {
    final repository = SongRepository(db: database, userId: 'local-user');
    final songId = await repository.saveDraft(
      draft: const SongDraft(
        title: 'Transpose Test',
        artist: 'ChordPlane',
        originalKey: 'G',
        body: '{start_of_verse: Verse 1}\n'
            '[G]First line [C]with chords\n'
            '{end_of_verse}',
      ),
    );

    phoneViewport(tester);
    await tester.pumpWidget(wrap(SongViewerScreen(songId: songId)));
    await pumpUntil(tester, find.text('Transpose Test'));

    // The lyric words are split into chord-anchored units, so check the
    // chord chips rendered in the header instead.
    expect(find.widgetWithText(ActionChip, 'G'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, 'C'), findsOneWidget);
    expect(find.text('VERSE 1'), findsOneWidget);

    // Open the transpose sheet and move up a semitone.
    await tester.tap(find.text('Key'));
    await pumpUntil(tester, find.text('Transpose'));

    await tester.tap(find.byIcon(Icons.add));
    await pumpUntil(tester, find.text('+1'));
    expect(find.text('+1'), findsWidgets);

    // Dismiss the sheet and confirm the chords were transposed.
    await tester.tapAt(const Offset(12, 12));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.widgetWithText(ActionChip, 'G#'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, 'G'), findsNothing);

    // And reset back to the original key.
    await tester.tap(find.byIcon(Icons.swap_vert));
    await pumpUntil(tester, find.text('Reset to original'));
    await tester.tap(find.text('Reset to original'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tapAt(const Offset(12, 12));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.widgetWithText(ActionChip, 'G'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('song viewer renders an empty song without crashing', (
    tester,
  ) async {
    final repository = SongRepository(db: database, userId: 'local-user');
    final songId = await repository.saveDraft(
      draft: const SongDraft(title: 'Blank', artist: 'ChordPlane'),
    );

    phoneViewport(tester);
    await tester.pumpWidget(wrap(SongViewerScreen(songId: songId)));
    await pumpUntil(tester, find.text('Blank'));

    expect(
      find.text('This song has no chords or lyrics yet.'),
      findsOneWidget,
    );

    await unmount(tester);
  });

  testWidgets('settings opened from profile has a back button', (
    tester,
  ) async {
    phoneViewport(tester);
    final router = GoRouter(
      initialLocation: '/profile',
      routes: [
        GoRoute(
          path: '/profile',
          builder: (context, state) => const ProfileScreen(),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsScreen(),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          sharedPreferencesProvider.overrideWithValue(preferences),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          theme: ChordPlaneTheme.light(),
        ),
      ),
    );
    await pumpUntil(tester, find.text('Profile'));
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await pumpUntil(tester, find.text('Settings'));
    expect(find.byType(BackButton), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('editor drops tags and offers zoom controls', (tester) async {
    phoneViewport(tester);
    await tester.pumpWidget(wrap(const SongEditorScreen()));
    await pumpUntil(tester, find.text('New song'));
    expect(find.text('Tags (optional)'), findsNothing);
    expect(find.text('100%'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.zoom_in));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('110%'), findsOneWidget);
    await unmount(tester);
  });
}
