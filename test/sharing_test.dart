import 'package:chord_plane/app/deep_links.dart';
import 'package:chord_plane/core/db/app_database.dart';
import 'package:chord_plane/features/setlists/data/setlist_repository.dart';
import 'package:chord_plane/features/sharing/cpl.dart';
import 'package:chord_plane/features/sharing/share_service.dart';
import 'package:chord_plane/features/songs/data/song_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

const _song = CplSong(
  title: 'Amazing Grace',
  artist: 'Traditional',
  body: '{start_of_verse: Verse 1}\n[G]Amazing grace [C]how sweet\n{end_of_verse}',
  originalKey: 'G',
  capo: 2,
  tempo: 84,
  youtubeUrl: 'https://youtube.com/watch?v=123',
  tags: 'hymn,slow',
);

const _bundle = CplBundle.setlist(
  title: 'Friday gig',
  description: 'Warm-up then the good stuff',
  items: [
    CplItem(song: _song, transpose: 2, capo: 1, note: 'Start quiet'),
    CplItem(
      song: CplSong(
        title: 'Scarborough Fair',
        artist: 'Traditional',
        body: '[Am]Are you going to [C]Scarborough Fair',
      ),
      transpose: -3,
    ),
  ],
);

void main() {
  group('CPL bundle', () {
    test('round-trips through pretty JSON', () {
      final decoded = CplBundle.decodeJson(_bundle.toPrettyJson());

      expect(decoded.kind, CplKind.setlist);
      expect(decoded.title, 'Friday gig');
      expect(decoded.description, 'Warm-up then the good stuff');
      expect(decoded.songCount, 2);
      expect(decoded.items.first.song.title, 'Amazing Grace');
      expect(decoded.items.first.song.capo, 2);
      expect(decoded.items.first.song.tempo, 84);
      expect(decoded.items.first.transpose, 2);
      expect(decoded.items.first.capo, 1);
      expect(decoded.items.first.note, 'Start quiet');
      expect(decoded.items.last.song.title, 'Scarborough Fair');
    });

    test('round-trips through a share code', () {
      final decoded = CplBundle.decodeShareCode(_bundle.toShareCode());

      expect(decoded.title, 'Friday gig');
      expect(decoded.songCount, 2);
    });

    test('round-trips through a full share link', () {
      final decoded = CplBundle.decodeShareCode(_bundle.toLink());

      expect(decoded.title, 'Friday gig');
      expect(decoded.items.last.song.title, 'Scarborough Fair');
    });

    test('exports a single song without setlist wrappers', () {
      const bundle = CplBundle.song(song: _song, title: 'Amazing Grace');
      final json = bundle.toCompactJson();

      expect(json, contains('"type":"song"'));
      expect(CplBundle.decodeJson(json).song!.title, 'Amazing Grace');
      expect(CplBundle.decodeShareCode(bundle.toShareCode()).songCount, 1);
    });

    test('rejects unknown formats and empty setlists', () {
      expect(
        () => CplBundle.decodeJson('{"format":"chordplane.cpl/9"}'),
        throwsA(isA<CplException>()),
      );
      expect(
        () => CplBundle.decodeJson('{"type":"setlist","setlist":{"items":[]}}'),
        throwsA(isA<CplException>()),
      );
      expect(
        () => CplBundle.decodeJson('not json'),
        throwsA(isA<CplException>()),
      );
    });
  });

  group('share code extraction', () {
    final code = _bundle.toShareCode();

    test('reads https links', () {
      expect(
        CplBundle.extractShareCode('https://chordplane.app/c/$code'),
        code,
      );
    });

    test('reads custom-scheme URIs', () {
      expect(CplBundle.extractShareCode('chordplane://c/$code'), code);
    });

    test('reads a bare code', () {
      expect(CplBundle.extractShareCode(code), code);
    });

    test('ignores unrelated text and links', () {
      expect(CplBundle.extractShareCode(''), isNull);
      expect(CplBundle.extractShareCode('hello there'), isNull);
      expect(
        CplBundle.extractShareCode('https://example.com/song/123'),
        isNull,
      );
    });
  });

  group('routeForIncomingLink', () {
    test('normalises custom-scheme and https links', () {
      expect(
        routeForIncomingLink('chordplane://c/abc123'),
        '/c/abc123',
      );
      expect(
        routeForIncomingLink('https://chordplane.app/c/abc123'),
        '/c/abc123',
      );
    });

    test('keeps platform paths', () {
      expect(routeForIncomingLink('/song/42'), '/song/42');
      expect(routeForIncomingLink('/'), '/');
      expect(routeForIncomingLink('song/42'), '/song/42');
    });

    test('falls back to the library for empty input', () {
      expect(routeForIncomingLink('  '), '/');
    });
  });

  group('ShareService import', () {
    late AppDatabase database;
    late ShareService service;
    late SongRepository songs;

    setUp(() {
      database = AppDatabase.forTesting(NativeDatabase.memory());
      songs = SongRepository(db: database, userId: 'local-user');
      service = ShareService(
        songs: songs,
        setlists: SetlistRepository(db: database, userId: 'local-user'),
      );
    });

    tearDown(() async {
      await database.close();
    });

    test('imports a setlist once and reuses matching songs', () async {
      final first = await service.importBundle(_bundle);

      expect(first.kind, CplKind.setlist);
      expect(first.songsCreated, 2);
      expect(first.songsReused, 0);
      expect((await database.select(database.songs).get()), hasLength(2));

      final second = await service.importBundle(_bundle);

      expect(second.songsCreated, 0);
      expect(second.songsReused, 2);
      expect((await database.select(database.songs).get()), hasLength(2));
      expect(
        (await database.select(database.setlistItems).get()),
        hasLength(4),
      );
    });

    test('imports a single song without duplicating it', () async {
      const bundle = CplBundle.song(song: _song, title: 'Amazing Grace');
      final first = await service.importBundle(bundle);
      final second = await service.importBundle(bundle);

      expect(first.songsCreated, 1);
      expect(second.songsReused, 1);
      expect(first.id, second.id);
      expect((await database.select(database.songs).get()), hasLength(1));
    });

    test('builds a bundle that round-trips through the codec', () async {
      final result = await service.importBundle(_bundle);
      final exported = await service.bundleForSetlist(result.id);
      final decoded = CplBundle.decodeShareCode(exported.toShareCode());

      expect(decoded.title, 'Friday gig');
      expect(decoded.songCount, 2);
      expect(decoded.items.first.transpose, 2);
      expect(decoded.items.last.song.title, 'Scarborough Fair');
    });
  });
}
