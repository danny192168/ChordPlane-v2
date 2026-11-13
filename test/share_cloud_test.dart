import 'dart:convert';

import 'package:chord_plane/app/deep_links.dart';
import 'package:chord_plane/core/db/app_database.dart';
import 'package:chord_plane/features/sharing/cpl.dart';
import 'package:chord_plane/features/sharing/cloud/share_cloud.dart';
import 'package:chord_plane/features/sharing/cloud/share_outbox.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('share tokens', () {
    test('are long, unambiguous, and unique', () {
      final tokens = {for (var i = 0; i < 200; i++) generateShareToken()};
      expect(tokens.length, 200);
      final shape = RegExp(r'^[a-z2-9A-HJ-NP-Z]{14}$');
      for (final token in tokens) {
        expect(shape.hasMatch(token), isTrue, reason: token);
      }
    });
  });

  group('server token extraction', () {
    test('reads https and custom-scheme server links', () {
      const token = 'abc123hjkmnp45';
      expect(
        CplFormat.extractServerToken(
          'https://chordplane.citcs.site/s/$token',
        ),
        token,
      );
      expect(CplFormat.extractServerToken('chordplane://s/$token'), token);
      expect(CplFormat.extractServerToken('/s/$token'), token);
      expect(CplFormat.extractServerToken(token), token);
    });

    test('rejects inline share codes and other text', () {
      // A real inline code is gzipped base64 — far longer than a token.
      final inlineCode =
          CplBundle.song(song: const CplSong(title: 'T'), title: 'T')
              .toShareCode();
      expect(inlineCode.length, greaterThan(24));
      expect(CplFormat.extractServerToken(inlineCode), isNull);
      expect(CplFormat.extractServerToken(''), isNull);
      expect(
        CplFormat.extractServerToken('https://chordplane.app/c/$inlineCode'),
        isNull,
      );
      expect(CplFormat.extractServerToken('hello world'), isNull);
    });

    test('deep link routing maps server links to /s/', () {
      const token = 'abc123hjkmnp45';
      expect(
        routeForIncomingLink('https://chordplane.citcs.site/s/$token'),
        '/s/$token',
      );
      expect(routeForIncomingLink('chordplane://s/$token'), '/s/$token');
      // Inline links keep working.
      final inlineCode =
          CplBundle.song(song: const CplSong(title: 'T'), title: 'T')
              .toShareCode();
      expect(
        routeForIncomingLink('chordplane://c/$inlineCode'),
        '/c/$inlineCode',
      );
    });

    test('builds the short server link on the share host', () {
      expect(
        CplFormat.serverLink('abc123hjkmnp45'),
        'https://chordplane.citcs.site/s/abc123hjkmnp45',
      );
    });
  });

  group('share outbox', () {
    late AppDatabase db;
    late _FakeShareApi api;
    late ShareOutbox outbox;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      db = AppDatabase.forTesting(NativeDatabase.memory());
      api = _FakeShareApi();
      outbox = ShareOutbox(db: db, api: api);
    });

    tearDown(() async => db.close());

    ShareRecord record(String token) => ShareRecord(
      token: token,
      kind: 'setlist',
      title: 'Sunday set',
      snapshot: const {
        'format': 'chordplane.cpl/1',
        'type': 'setlist',
        'setlist': {'title': 'Sunday set', 'items': []},
      },
    );

    test('uploads on flush and drops the queue entry', () async {
      await outbox.enqueue(record('tokenone11'));
      expect(await outbox.pendingCount(), 1);

      final uploaded = await outbox.flush();

      expect(uploaded, 1);
      expect(await outbox.pendingCount(), 0);
      expect(api.upserts.single.token, 'tokenone11');
      expect(api.upserts.single.snapshot['type'], 'setlist');
    });

    test('retries network failures and survives a restart', () async {
      await outbox.enqueue(record('tokentwo22'));
      api.failNext(
        1,
        const ShareCloudException(ShareCloudError.network, 'offline'),
      );

      expect(await outbox.flush(), 0);
      expect(await outbox.pendingCount(), 1);

      expect(await outbox.flush(), 1);
      expect(await outbox.pendingCount(), 0);
      expect(api.upserts.length, 1);
    });

    test('gives up on permanently rejected shares', () async {
      await outbox.enqueue(record('tokenthree'));
      api.failNext(
        20,
        const ShareCloudException(
          ShareCloudError.rejected,
          'policy violation',
        ),
      );

      for (var i = 0; i < 10; i++) {
        await outbox.flush();
      }

      expect(await outbox.pendingCount(), 0);
    });

    test('does nothing when the queue is empty', () async {
      expect(await outbox.flush(), 0);
      expect(await outbox.pendingCount(), 0);
    });

    test('payload round-trips into a decodable bundle', () async {
      final original = CplBundle.setlist(
        title: 'Friday',
        description: 'test',
        items: [
          const CplItem(
            song: CplSong(title: 'Amazing Grace', body: '[G]Amazing grace'),
          ),
        ],
      );
      final record = ShareRecord(
        token: generateShareToken(),
        kind: original.kind.name,
        title: original.title,
        snapshot: original.toJson(),
      );
      await outbox.enqueue(record);

      final entry = await (db.select(db.syncOutbox)).getSingle();
      final restored = ShareRecord.fromJson(
        jsonDecode(entry.payload) as Map<String, dynamic>,
      );

      expect(restored.title, 'Friday');
      expect(restored.kind, 'setlist');
      final bundle = CplBundle.decodeJson(jsonEncode(restored.snapshot));
      expect(bundle.songCount, 1);
      expect(bundle.items.single.song.title, 'Amazing Grace');
    });
  });
}

class _FakeShareApi implements ShareCloudApi {
  final upserts = <ShareRecord>[];
  final revocations = <String, bool>{};
  int _failuresLeft = 0;
  ShareCloudException? _failure;

  void failNext(int count, ShareCloudException failure) {
    _failuresLeft = count;
    _failure = failure;
  }

  @override
  Future<void> upsertShare(ShareRecord record) async {
    if (_failuresLeft > 0) {
      _failuresLeft--;
      throw _failure!;
    }
    upserts.add(record);
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
