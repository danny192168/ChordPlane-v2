import 'package:chord_plane/shared/widgets/profile_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('guests get the default icon inside a circular clip', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ProfileAvatar(seed: '', size: 124, signedIn: false),
        ),
      ),
    );

    expect(find.byType(ClipOval), findsOneWidget);
    expect(find.byIcon(Icons.person_outline), findsOneWidget);
  });

  testWidgets('signed-in avatars are also clipped to an oval', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ProfileAvatar(seed: 'Jane', size: 124),
        ),
      ),
    );

    expect(find.byType(ClipOval), findsOneWidget);
  });
}
