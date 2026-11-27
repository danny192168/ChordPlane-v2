import 'package:chord_plane/core/chords/chord_detection.dart';
import 'package:chord_plane/features/community/data/community_api.dart';
import 'package:chord_plane/features/community/data/published_feed.dart';
import 'package:flutter_test/flutter_test.dart';

CommunitySong _song(String id) => CommunitySong(
  id: id,
  title: 'Song $id',
  artist: 'Artist',
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
  username: 'jane',
  createdAt: DateTime.utc(2026, 11, 27),
  ratingSum: 0,
  ratingCount: 0,
);

void main() {
  group('mergePublishedPages', () {
    test('appends new songs in order', () {
      final result = mergePublishedPages([_song('1')], [_song('2')]);
      expect(result.map((song) => song.id), ['1', '2']);
    });

    test('drops songs that shifted into an earlier page', () {
      final result = mergePublishedPages(
        [_song('1'), _song('2')],
        [_song('2'), _song('3')],
      );
      expect(result.map((song) => song.id), ['1', '2', '3']);
    });

    test('does not mutate the loaded page', () {
      final loaded = [_song('1')];
      mergePublishedPages(loaded, [_song('2')]);
      expect(loaded.length, 1);
    });
  });

  test('state copyWith can clear the load-more error', () {
    final state = PublishedFeedState(
      songs: [_song('1')],
      hasMore: true,
      loadMoreError: 'offline',
    );
    final next = state.copyWith(loadingMore: true, clearLoadMoreError: true);
    expect(next.songs, state.songs);
    expect(next.loadingMore, isTrue);
    expect(next.loadMoreError, isNull);
  });
}
