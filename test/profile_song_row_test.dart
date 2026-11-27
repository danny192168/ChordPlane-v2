import 'package:chord_plane/features/profile/widgets/profile_empty_state.dart';
import 'package:chord_plane/features/profile/widgets/profile_song_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('profile row shows title, artist, key badge and age', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfileSongRow(
            title: 'Amazing Grace',
            artist: 'Traditional',
            musicalKey: 'G',
            age: '3d ago',
            onTap: () => taps++,
          ),
        ),
      ),
    );

    expect(find.text('Amazing Grace'), findsOneWidget);
    expect(find.text('Traditional'), findsOneWidget);
    expect(find.text('G'), findsOneWidget);
    expect(find.text('3d ago'), findsOneWidget);

    await tester.tap(find.text('Amazing Grace'));
    expect(taps, 1);
  });

  testWidgets('profile row falls back to Unknown artist without a key badge', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfileSongRow(
            title: 'Untitled',
            artist: '',
            musicalKey: '',
            age: 'just now',
            onTap: () {},
          ),
        ),
      ),
    );

    expect(find.text('Unknown artist'), findsOneWidget);
    expect(find.text('Untitled'), findsOneWidget);
  });

  testWidgets('empty state renders its action and stays tappable', (tester) async {
    var actions = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfileEmptyState(
            icon: Icons.upload_outlined,
            title: 'No uploads yet',
            message: 'Publish a song from its menu to see it here.',
            actionLabel: 'Browse library',
            onAction: () => actions++,
          ),
        ),
      ),
    );

    expect(find.text('No uploads yet'), findsOneWidget);
    expect(
      find.text('Publish a song from its menu to see it here.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Browse library'));
    expect(actions, 1);
  });
}
