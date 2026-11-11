import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/db/app_database.dart';
import '../../core/utils/slug.dart';
import '../setlists/data/setlist_repository.dart';
import '../songs/data/song_repository.dart';
import 'cpl.dart';

final shareServiceProvider = Provider<ShareService>((ref) {
  return ShareService(
    songs: ref.watch(songRepositoryProvider),
    setlists: ref.watch(setlistRepositoryProvider),
  );
});

class ImportResult {
  const ImportResult({
    required this.kind,
    required this.id,
    required this.songsCreated,
    required this.songsReused,
  });

  final CplKind kind;

  /// Song id for a single song, setlist id otherwise.
  final String id;
  final int songsCreated;
  final int songsReused;

  int get total => songsCreated + songsReused;
}

/// Turns local rows into portable bundles and back again.
class ShareService {
  ShareService({required this.songs, required this.setlists});

  final SongRepository songs;
  final SetlistRepository setlists;

  Future<CplBundle> bundleForSetlist(String setlistId) async {
    final setlist = await setlists.getSetlist(setlistId);
    if (setlist == null) {
      throw const CplException('That setlist no longer exists.');
    }
    final entries = await setlists.getEntries(setlistId);
    return CplBundle.setlist(
      title: setlist.title,
      description: setlist.description,
      items: [
        for (final entry in entries)
          CplItem(
            song: _songToCpl(entry.song),
            transpose: entry.item.transpose,
            capo: entry.item.capoOverride,
            note: entry.item.note,
          ),
      ],
    );
  }

  Future<CplBundle> bundleForSong(String songId) async {
    final song = await songs.getSong(songId);
    if (song == null) {
      throw const CplException('That song no longer exists.');
    }
    return CplBundle.song(song: _songToCpl(song), title: song.title);
  }

  /// Adds everything in [bundle] to the local library. Songs already present
  /// with the same title and artist are reused rather than duplicated.
  Future<ImportResult> importBundle(CplBundle bundle) async {
    if (bundle.kind == CplKind.song) {
      final song = bundle.song!;
      final existing = await songs.findMatching(
        title: song.title,
        artist: song.artist,
      );
      if (existing != null) {
        return ImportResult(
          kind: CplKind.song,
          id: existing.id,
          songsCreated: 0,
          songsReused: 1,
        );
      }
      final id = await _createSong(song);
      return ImportResult(
        kind: CplKind.song,
        id: id,
        songsCreated: 1,
        songsReused: 0,
      );
    }

    var created = 0;
    var reused = 0;
    final entries = <SetlistImportEntry>[];
    for (final item in bundle.items) {
      var songId = await _existingSongId(item.song);
      if (songId == null) {
        songId = await _createSong(item.song);
        created++;
      } else {
        reused++;
      }
      entries.add(
        SetlistImportEntry(
          songId: songId,
          transpose: item.transpose.clamp(-11, 11),
          capo: item.capo,
          note: item.note,
        ),
      );
    }

    final setlistId = await setlists.createFromEntries(
      title: bundle.title,
      description: bundle.description,
      entries: entries,
    );
    return ImportResult(
      kind: CplKind.setlist,
      id: setlistId,
      songsCreated: created,
      songsReused: reused,
    );
  }

  /// Writes a `.cpl` file into the app's temporary directory so it can be
  /// handed to the system share sheet.
  Future<File> writeCplFile(CplBundle bundle) async {
    final directory = await getTemporaryDirectory();
    final name = slugify(bundle.title);
    final file = File('${directory.path}/$name.cpl');
    await file.writeAsString(bundle.toPrettyJson(), flush: true);
    return file;
  }

  Future<void> shareFile(CplBundle bundle, {Rect? origin}) async {
    final file = await writeCplFile(bundle);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/json')],
        fileNameOverrides: ['${slugify(bundle.title)}.cpl'],
        subject: '${bundle.title} — ChordPlane',
        text: '${bundle.title} · ${bundle.songCount} '
            '${bundle.songCount == 1 ? 'song' : 'songs'} — open with ChordPlane',
        sharePositionOrigin: origin,
      ),
    );
  }

  Future<void> shareLink(CplBundle bundle, {Rect? origin}) async {
    final link = bundle.toLink();
    await SharePlus.instance.share(
      ShareParams(
        text:
            '${bundle.title} · ${bundle.songCount} '
            '${bundle.songCount == 1 ? 'song' : 'songs'} — open in ChordPlane:\n'
            '$link',
        subject: '${bundle.title} — ChordPlane',
        sharePositionOrigin: origin,
      ),
    );
  }

  Future<void> copyLink(CplBundle bundle) {
    return Clipboard.setData(ClipboardData(text: bundle.toLink()));
  }

  Future<String?> _existingSongId(CplSong song) async {
    final row = await songs.findMatching(
      title: song.title,
      artist: song.artist,
    );
    return row?.id;
  }

  Future<String> _createSong(CplSong song) {
    return songs.saveDraft(
      draft: SongDraft(
        title: song.title,
        artist: song.artist,
        body: song.body,
        originalKey: song.originalKey,
        capo: song.capo,
        tempo: song.tempo,
        instrument: song.instrument,
        tuning: song.tuning,
        youtubeUrl: song.youtubeUrl,
        tags: song.tags,
      ),
    );
  }

  CplSong _songToCpl(SongRow row) {
    return CplSong(
      title: row.title,
      artist: row.artist,
      body: row.body,
      originalKey: row.originalKey,
      capo: row.capo,
      tempo: row.tempo,
      instrument: row.instrument,
      tuning: row.tuning,
      youtubeUrl: row.youtubeUrl,
      tags: row.tags,
    );
  }
}
