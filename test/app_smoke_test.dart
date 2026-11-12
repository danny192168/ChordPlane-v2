import 'package:chord_plane/app/theme/app_theme.dart';
import 'package:chord_plane/core/db/app_database.dart';
import 'package:chord_plane/core/settings/settings.dart';
import 'package:chord_plane/features/library/library_screen.dart';
import 'package:chord_plane/features/songs/data/song_repository.dart';
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

  /// Like [wrap], but with a real GoRouter so screens can push routes —
  /// the artists-first library opens artist pages via `context.push`.
  Widget wrapRouted() {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, _) => const LibraryScreen()),
        GoRoute(
          path: '/artist/:slug',
          builder: (context, state) =>
              ArtistScreen(slug: state.pathParameters['slug']!),
        ),
        GoRoute(
          path: '/song/:id',
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

  /// The favorited song keeps its filled heart across filters, so filter
  /// switches are verified by waiting for the un-hearted songs to vanish.
  Future<void> pumpUntilAbsent(
    WidgetTester tester,
    Finder finder, {
    int frames = 100,
  }) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 40));
      if (finder.evaluate().isEmpty) {
        await tester.pump(const Duration(milliseconds: 100));
        return;
      }
    }
    fail('Timed out waiting for $finder to disappear');
  }

  /// The default 800x600 test window cuts off the bottom sheets, so give the
  /// tests a phone-sized viewport.
  void phoneViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  /// Tear the tree down inside the test so drift can flush the zero-duration
  /// timer it schedules when a query stream closes.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump(const Duration(milliseconds: 20));
  }

  testWidgets('library lists artists and filters favorites', (tester) async {
    phoneViewport(tester);
    await tester.pumpWidget(wrapRouted());
    await pumpUntil(tester, find.text('Traditional'));

    // The default view surfaces songs through their artists. All three
    // demo songs share one artist.
    expect(find.text('Traditional'), findsOneWidget);
    expect(find.text('3 songs'), findsOneWidget);

    // Open the artist and heart the first song.
    await tester.tap(find.text('Traditional'));
    await pumpUntil(tester, find.text('Amazing Grace'));

    await tester.tap(find.byIcon(Icons.favorite_border).first);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    // Back to the library, then switch to the favorites filter.
    await tester.pageBack();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.widgetWithText(ChoiceChip, 'Favorites'));
    // The favorited song shows a filled heart in every filter, so wait for
    // the filter switch itself: the un-hearted songs must disappear.
    await pumpUntilAbsent(tester, find.text('Scarborough Fair'));

    expect(find.text('Amazing Grace'), findsOneWidget);
    expect(find.text('Scarborough Fair'), findsNothing);

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
}
