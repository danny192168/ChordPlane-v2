import 'package:chord_plane/core/auth/auth_gateway.dart';
import 'package:chord_plane/core/db/app_database.dart';
import 'package:chord_plane/features/sharing/cloud/my_shares_screen.dart';
import 'package:chord_plane/features/sharing/cloud/server_share_service.dart';
import 'package:chord_plane/features/sharing/cloud/share_cloud.dart';
import 'package:chord_plane/features/songs/data/song_repository.dart';
import 'package:drift/native.dart';import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Exercises the "My shared links" screen against a faked API and an
/// in-memory database: states it renders and the actions it offers.
void main() {
  late AppDatabase db;
  late _FakeShareApi api;

  ShareRecord record({
    String token = 'testtoken11',
    String title = 'Sunday set',
    String kind = 'setlist',
    String status = 'active',
    bool revoked = false,
    int viewCount = 3,
  }) {
    return ShareRecord(
      token: token,
      kind: kind,
      title: title,
      snapshot: const {
        'format': 'chordplane.cpl/1',
        'type': 'setlist',
        'setlist': {'title': 'Sunday set', 'items': []},
      },
      status: status,
      revoked: revoked,
      viewCount: viewCount,
      updatedAt: DateTime(2026, 1, 15),
    );
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    api = _FakeShareApi();
  });

  tearDown(() async => db.close());

  Widget app({required List<ShareRecord> shares}) {
    return ProviderScope(
      overrides: [
        cloudSharingEnabledProvider.overrideWithValue(true),
        databaseProvider.overrideWithValue(db),
        shareCloudApiProvider.overrideWith((ref) => api),
        authGatewayProvider.overrideWithValue(const _SignedInAuthGateway()),
      ],
      child: const MaterialApp(home: MySharesScreen()),
    );
  }

  testWidgets('shows the empty state when there are no shares', (tester) async {
    await tester.pumpWidget(app(shares: []));
    await tester.pumpAndSettle();

    expect(find.text('No shared links yet'), findsOneWidget);
  });

  testWidgets('lists shares with kind, view count, and status', (tester) async {
    api.seeded = [
      record(),
      record(
        token: 'othertoken22',
        title: 'Wonderwall',
        kind: 'song',
        viewCount: 1,
        revoked: true,
      ),
    ];
    await tester.pumpWidget(app(shares: api.seeded));
    await tester.pumpAndSettle();

    expect(find.text('Sunday set'), findsOneWidget);
    expect(find.text('Wonderwall'), findsOneWidget);
    expect(find.textContaining('Setlist · 3 views'), findsOneWidget);
    expect(find.textContaining('Song · 1 view'), findsOneWidget);
    expect(find.text('Revoked'), findsOneWidget);
    // Row actions are reachable via the per-row menu.
    expect(find.byType(PopupMenuButton<String>), findsNWidgets(2));
  });

  testWidgets('revoking a link calls the API and shows a confirmation',
      (tester) async {
    api.seeded = [record()];
    await tester.pumpWidget(app(shares: api.seeded));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Revoke link'));
    await tester.pumpAndSettle();

    expect(api.revocations['testtoken11'], isTrue);
    expect(find.text('Link revoked'), findsOneWidget);
    // The refreshed list reflects the revoked state.
    expect(find.text('Revoked'), findsOneWidget);
  });

  testWidgets('shows a sign-in prompt for signed-out users', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cloudSharingEnabledProvider.overrideWithValue(true),
          databaseProvider.overrideWithValue(db),
          shareCloudApiProvider.overrideWith((ref) => api),
          authGatewayProvider.overrideWithValue(const GuestAuthGateway()),
        ],
        child: const MaterialApp(home: MySharesScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sign in to see your links'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
  });
}

class _SignedInAuthGateway implements AuthGateway {
  const _SignedInAuthGateway();

  @override
  String get currentUserId => 'test-user';

  @override
  String get currentUserEmail => 'test@example.com';

  @override
  bool get isSignedIn => true;

  @override
  Stream<String?> get userIdChanges => const Stream<String?>.empty();

  @override
  Stream<bool> get signedInChanges => Stream<bool>.value(true);
}

class _FakeShareApi implements ShareCloudApi {
  List<ShareRecord> seeded = [];
  final revocations = <String, bool>{};

  @override
  Future<void> upsertShare(ShareRecord record) async {}

  @override
  Future<ShareRecord?> findShare(String token) async =>
      seeded.where((r) => r.token == token).firstOrNull;

  @override
  Future<List<ShareRecord>> listMyShares() async => List.of(seeded);

  @override
  Future<void> setRevoked(String token, {required bool revoked}) async {
    revocations[token] = revoked;
    seeded = [
      for (final share in seeded)
        if (share.token == token)
          ShareRecord(
            token: share.token,
            kind: share.kind,
            title: share.title,
            snapshot: share.snapshot,
            status: share.status,
            revoked: revoked,
            viewCount: share.viewCount,
            updatedAt: share.updatedAt,
          )
        else
          share,
    ];
  }
}
