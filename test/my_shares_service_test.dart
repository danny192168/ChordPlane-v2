import 'package:chord_plane/core/auth/auth_gateway.dart';
import 'package:chord_plane/core/db/app_database.dart';
import 'package:chord_plane/features/setlists/data/setlist_repository.dart';
import 'package:chord_plane/features/sharing/cloud/server_share_service.dart';
import 'package:chord_plane/features/sharing/cloud/share_cloud.dart';
import 'package:chord_plane/features/sharing/cloud/share_outbox.dart';
import 'package:chord_plane/features/sharing/cpl.dart';
import 'package:chord_plane/features/sharing/share_service.dart';
import 'package:chord_plane/features/songs/data/song_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Covers the server-share service behaviours that back the "My shared
/// links" screen: token ↔ local-content mapping, re-pushing updates, and
/// revoke/restore passthrough.
void main() {
  late AppDatabase db;
  late _FakeShareApi api;
  late ServerShareService service;
  late SongRepository songs;
  late SetlistRepository setlists;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    api = _FakeShareApi();
    service = ServerShareService(
      api: api,
      outbox: ShareOutbox(db: db, api: api),
      auth: const _SignedInAuthGateway(),
      db: db,
    );
    songs = SongRepository(db: db, userId: 'local-user');
    setlists = SetlistRepository(db: db, userId: 'local-user');
  });

  tearDown(() async => db.close());

  CplBundle songBundle() => CplBundle.song(
    song: const CplSong(title: 'Amazing Grace', body: '[G]Amazing grace'),
    title: 'Amazing Grace',
  );

  Future<String> createSong(String body) => songs.saveDraft(
    draft: const SongDraft(title: 'Amazing Grace', body: '[G]Amazing grace'),
  ).then((id) => id);

  test('share() remembers the token against the local song', () async {
    final songId = await createSong('[G]Amazing grace');

    final result = await service.share(songBundle(), localId: songId);

    expect(result.upload, ShareUpload.uploaded);
    final row = await (db.select(
      db.sharedLinks,
    )..where((t) => t.token.equals(result.token))).getSingle();
    expect(row.kind, 'song');
    expect(row.localId, songId);
    expect(row.title, 'Amazing Grace');
  });

  test('share() without a localId writes no mapping', () async {
    await service.share(songBundle());
    expect(await db.select(db.sharedLinks).get(), isEmpty);
  });

  test('bundleForUpdate rebuilds the bundle from the mapped song', () async {
    final songId = await createSong('[G]Amazing grace');
    final result = await service.share(songBundle(), localId: songId);

    final bundle = await service.bundleForUpdate(
      result.token,
      ShareService(songs: songs, setlists: setlists),
    );

    expect(bundle, isNotNull);
    expect(bundle!.kind, CplKind.song);
    expect(bundle.song!.title, 'Amazing Grace');
  });

  test('bundleForUpdate is null without a mapping or after song deletion', () async {
    // No mapping at all.
    expect(
      await service.bundleForUpdate(
        'notokenhere',
        ShareService(songs: songs, setlists: setlists),
      ),
      isNull,
    );

    // Mapping exists but the content is gone.
    final songId = await createSong('[G]Amazing grace');
    final result = await service.share(songBundle(), localId: songId);
    await songs.deleteSong(songId);
    expect(
      await service.bundleForUpdate(
        result.token,
        ShareService(songs: songs, setlists: setlists),
      ),
      isNull,
    );
  });

  test('update() replaces the snapshot and stamps lastPushedAt', () async {
    final songId = await createSong('[G]Amazing grace');
    final created = await service.share(songBundle(), localId: songId);

    await songs.saveDraft(
      id: songId,
      draft: const SongDraft(title: 'Amazing Grace', body: '[D]Amazing grace'),
    );
    await service.update(created.token, songBundle());

    expect(api.upsertCount, 2);
    expect(api.upserts.single.token, created.token);

    final row = await (db.select(
      db.sharedLinks,
    )..where((t) => t.token.equals(created.token))).getSingle();
    expect(
      row.lastPushedAt.isAtSameMomentAs(row.createdAt) ||
          row.lastPushedAt.isAfter(row.createdAt),
      isTrue,
    );
  });

  test('setRevoked() passes both directions through to the API', () async {
    await service.share(songBundle());
    final token = api.upserts.single.token;

    await service.setRevoked(token, revoked: true);
    expect(api.revocations[token], isTrue);

    await service.setRevoked(token, revoked: false);
    expect(api.revocations[token], isFalse);
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
  Stream<bool> get signedInChanges => const Stream<bool>.empty();
}

class _FakeShareApi implements ShareCloudApi {
  final upserts = <ShareRecord>[];
  final revocations = <String, bool>{};

  /// Total number of pushes, counting repeats of the same token.
  int upsertCount = 0;

  @override
  Future<void> upsertShare(ShareRecord record) async {
    upsertCount++;
    final index = upserts.indexWhere((r) => r.token == record.token);
    if (index >= 0) {
      upserts[index] = record;
    } else {
      upserts.add(record);
    }
  }

  @override
  Future<ShareRecord?> findShare(String token) async =>
      upserts.where((r) => r.token == token).firstOrNull;

  @override
  Future<List<ShareRecord>> listMyShares() async => List.of(upserts);

  @override
  Future<void> setRevoked(String token, {required bool revoked}) async {
    revocations[token] = revoked;
  }
}
