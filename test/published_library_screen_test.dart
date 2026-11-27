import 'package:chord_plane/core/chords/chord_detection.dart';
import 'package:chord_plane/features/community/data/community_api.dart';
import 'package:chord_plane/features/community/data/published_feed.dart';
import 'package:chord_plane/features/library/published_library_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

CommunitySong _song(String id) => CommunitySong(
  id: id,
  title: 'Song $id',
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
  createdAt: DateTime.now().toUtc().subtract(const Duration(hours: 2)),
  ratingSum: 0,
  ratingCount: 0,
);

class FakeFeed extends PublishedFeedController {
  static int loadCalls = 0;

  @override
  Future<PublishedFeedState> build() async {
    return PublishedFeedState(songs: [_song('one'), _song('two')], hasMore: true);
  }

  @override
  Future<void> loadMore() async {
    loadCalls++;
    final current = state.value ?? const PublishedFeedState();
    state = AsyncValue.data(
      PublishedFeedState(
        songs: [...current.songs, _song('three')],
        hasMore: false,
      ),
    );
  }
}

void main() {
  setUp(() => FakeFeed.loadCalls = 0);

  testWidgets('cards show uploader and age, and load more near the bottom', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [publishedFeedProvider.overrideWith(FakeFeed.new)],
        child: const MaterialApp(home: PublishedLibraryScreen()),
      ),
    );

    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 40));
      if (find.text('Song three').evaluate().isNotEmpty) break;
    }

    expect(find.text('Song one'), findsOneWidget);
    expect(find.text('The Artists'), findsWidgets);
    expect(find.text('janedoe'), findsWidgets);
    expect(find.text('2h ago'), findsWidgets);
    expect(FakeFeed.loadCalls, greaterThanOrEqualTo(1));
    expect(find.text('Song three'), findsOneWidget);
  });
}
