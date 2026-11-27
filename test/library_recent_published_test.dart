import 'package:chord_plane/core/auth/auth_gateway.dart';
import 'package:chord_plane/core/chords/chord_detection.dart';
import 'package:chord_plane/features/community/data/community_api.dart';
import 'package:chord_plane/features/community/data/published_feed.dart';
import 'package:chord_plane/features/library/library_screen.dart';
import 'package:chord_plane/features/library/published_library_screen.dart';
import 'package:chord_plane/features/songs/data/song_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

CommunitySong _song() => CommunitySong(
  id: 'remote-1',
  title: 'Community Anthem',
  artist: 'The Artists',
  body: '',
  originalKey: 'G',
  chordDetectionMode: ChordDetectionMode.auto,
  capo: 0,
  tempo: null,
  instrument: 'guitar',
  tuning: 'standard',
  youtubeUrl: '',
  tags: '',
  anonymous: false,
  username: 'janedoe',
  createdAt: DateTime.now().toUtc().subtract(const Duration(days: 3)),
  ratingSum: 0,
  ratingCount: 0,
);

class StubFeed extends PublishedFeedController {
  @override
  Future<PublishedFeedState> build() async => PublishedFeedState(
    songs: [_song()],
    hasMore: false,
  );
}

void main() {
  testWidgets('Library shows recent uploads and a See all action', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (context, state) => const LibraryScreen()),
        GoRoute(
          path: '/published',
          builder: (context, state) => const PublishedLibraryScreen(),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appBootstrapProvider.overrideWith((ref) => Future.value()),
          savedSongsProvider.overrideWith((ref) => Stream.value([])),
          recentPublishedProvider.overrideWith((ref) => Future.value([_song()])),
          signedInProvider.overrideWith((ref) => Stream.value(false)),
          publishedFeedProvider.overrideWith(StubFeed.new),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          theme: ThemeData(useMaterial3: true),
        ),
      ),
    );

    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 40));
      if (find.text('See all').evaluate().isNotEmpty) break;
    }

    expect(find.text('RECENTLY PUBLISHED'), findsOneWidget);
    expect(find.text('Community Anthem'), findsOneWidget);
    expect(find.text('janedoe'), findsOneWidget);
    expect(find.text('3d ago'), findsOneWidget);

    await tester.tap(find.text('See all'));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 40));
      if (find.text('Published').evaluate().isNotEmpty) break;
    }
    expect(find.text('Published'), findsWidgets);
  });
}
