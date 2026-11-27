import 'package:chord_plane/core/chords/chord_detection.dart';
import 'package:chord_plane/features/community/data/community_api.dart';
import 'package:chord_plane/features/library/widgets/published_song_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

CommunitySong _song({
  String username = 'jane',
  bool anonymous = false,
}) {
  return CommunitySong(
    id: 'song-1',
    title: 'Amazing Grace',
    artist: 'Traditional',
    body: '',
    originalKey: 'G',
    chordDetectionMode: ChordDetectionMode.auto,
    capo: 0,
    tempo: null,
    instrument: 'guitar',
    tuning: 'standard',
    youtubeUrl: '',
    tags: '',
    anonymous: anonymous,
    username: username,
    createdAt: DateTime.now().toUtc().subtract(const Duration(hours: 2)),
    ratingSum: 0,
    ratingCount: 0,
  );
}

void main() {
  testWidgets('shows uploader credit and relative time, and stays tappable', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PublishedSongCard(song: _song(), onTap: () => taps++),
        ),
      ),
    );

    expect(find.text('Amazing Grace'), findsOneWidget);
    expect(find.text('Traditional'), findsOneWidget);
    expect(find.text('jane'), findsOneWidget);
    expect(find.text('2h ago'), findsOneWidget);

    await tester.tap(find.text('Amazing Grace'));
    expect(taps, 1);
  });

  testWidgets('credits anonymous uploads without a username', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PublishedSongCard(
            song: _song(username: 'jane', anonymous: true),
            onTap: () {},
          ),
        ),
      ),
    );

    expect(find.text('Anonymous'), findsOneWidget);
    expect(find.text('jane'), findsNothing);
  });
}
