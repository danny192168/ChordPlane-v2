import 'package:chord_plane/core/auth/auth_gateway.dart';
import 'package:chord_plane/core/chords/chord_detection.dart';
import 'package:chord_plane/core/db/app_database.dart';
import 'package:chord_plane/core/settings/settings.dart';
import 'package:chord_plane/features/community/data/community_api.dart';
import 'package:chord_plane/features/community/data/community_providers.dart';
import 'package:chord_plane/features/profile/profile_screen.dart';
import 'package:chord_plane/features/songs/data/song_providers.dart';
import 'package:chord_plane/features/songs/data/song_repository.dart';
import 'package:chord_plane/shared/widgets/profile_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

CommunitySong _upload() => CommunitySong(
  id: 'remote-1',
  title: 'Community Anthem',
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
  anonymous: false,
  username: 'janedoe',
  createdAt: DateTime.now().toUtc().subtract(const Duration(days: 3)),
  ratingSum: 0,
  ratingCount: 0,
);

FavoriteItem _favorite() {
  final now = DateTime.now().toUtc();
  return FavoriteItem(
    song: SongRow(
      id: 'local-1',
      ownerId: 'local-user',
      title: 'Hearted Tune',
      artist: 'Jane',
      artistSlug: 'jane',
      body: '',
      originalKey: 'Am',
      chordDetectionMode: 'auto',
      capo: 0,
      instrument: 'guitar',
      tuning: 'standard',
      youtubeUrl: '',
      tags: '',
      visibility: 'private',
      anonymousUpload: false,
      createdAt: now,
      updatedAt: now,
      version: 1,
      syncState: 'local',
      origin: 'local',
      editedLocally: false,
      downloadState: 'complete',
      ratingSum: 0,
      ratingCount: 0,
    ),
    favoritedAt: now.subtract(const Duration(days: 7)),
  );
}

void main() {
  late SharedPreferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'profile.displayName': 'Jane Doe'});
    preferences = await SharedPreferences.getInstance();
  });

  Widget wrap() {
    return ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        signedInProvider.overrideWith((ref) => Stream.value(true)),
        profileInfoProvider.overrideWith(
          (ref) => Future.value(
            const ProfileInfo(
              displayName: 'Jane Doe',
              username: 'janedoe',
              email: 'jane@example.com',
            ),
          ),
        ),
        myUploadsProvider.overrideWith((ref) => Future.value([_upload()])),
        myPublishedCountProvider.overrideWith((ref) => Future.value(1)),
        favoriteItemsProvider.overrideWith(
          (ref) => Stream.value([_favorite()]),
        ),
      ],
      child: const MaterialApp(home: ProfileScreen()),
    );
  }

  Future<void> pumpUntil(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 40));
      if (finder.evaluate().isNotEmpty) return;
    }
    fail('Timed out waiting for $finder');
  }

  testWidgets('header shows name and handle, tabs load lazily', (tester) async {
    await tester.pumpWidget(wrap());
    await pumpUntil(tester, find.text('Community Anthem'));

    // The header column stretches its children; the avatar must still be a
    // fixed square circle rather than the full width of the screen.
    final avatar = tester.getSize(find.byType(ProfileAvatar));
    expect(avatar.width, 112);
    expect(avatar.height, 112);

    expect(find.text('Jane Doe'), findsOneWidget);
    expect(find.text('@janedoe'), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    expect(find.text('Published'), findsOneWidget);
    expect(find.text('Favorites'), findsOneWidget);

    // The Favorites panel is not built until its tab is opened.
    expect(find.text('Hearted Tune'), findsNothing);

    await tester.tap(find.text('Favorites'));
    await pumpUntil(tester, find.text('Hearted Tune'));
    expect(find.text('Community Anthem'), findsNothing);

    // Switching back keeps the already loaded panel.
    await tester.tap(find.text('Published'));
    await pumpUntil(tester, find.text('Community Anthem'));
    expect(find.text('Hearted Tune'), findsNothing);
  });
}
