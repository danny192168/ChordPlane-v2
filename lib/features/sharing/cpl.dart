import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../core/config/app_config.dart';

/// ChordPlane's portable, plain-JSON song/setlist format (`.cpl`).
///
/// The same envelope is used for files, share links and QR codes:
///
/// ```json
/// {
///   "format": "chordplane.cpl/1",
///   "type": "setlist",
///   "setlist": {
///     "title": "Friday gig",
///     "description": "",
///     "items": [
///       {
///         "position": 0,
///         "transpose": -2,
///         "capo": null,
///         "note": "",
///         "song": { "title": "…", "artist": "…", "body": "…", … }
///       }
///     ]
///   }
/// }
/// ```
class CplFormat {
  const CplFormat._();

  static const String version = 'chordplane.cpl/1';
  static const String linkHost = 'https://chordplane.app';
  static const String customScheme = 'chordplane';

  /// Server-backed share links are shorter than inline codes because the
  /// bundle lives on the backend and the link only carries the token.
  static String serverLink(String token) =>
      '${AppConfig.shareHost}/s/$token';

  /// Pulls the token out of `https://…/s/<token>`, `chordplane://s/<token>`,
  /// or a bare token. Returns null for inline `/c/` links and other text.
  static String? extractServerToken(String raw) {
    final input = raw.trim();
    if (input.isEmpty) return null;
    final uri = Uri.tryParse(input);
    if (uri != null && uri.hasScheme) {
      final segments = uri.pathSegments;
      final index = segments.indexOf('s');
      if (index >= 0 && index + 1 < segments.length) {
        final token = segments[index + 1];
        return _isTokenShaped(token) ? token : null;
      }
      if (uri.host == 's' && segments.isNotEmpty) {
        return _isTokenShaped(segments.first) ? segments.first : null;
      }
      return null;
    }
    if (input.contains('://')) return null;
    final pathIndex = input.lastIndexOf('/s/');
    if (pathIndex >= 0) {
      final tail = input.substring(pathIndex + 3);
      return _isTokenShaped(tail) ? tail : null;
    }
    return _isTokenShaped(input) ? input : null;
  }

  /// A bare token is a short, unambiguous string; inline share codes are
  /// much longer base64. The length cut keeps the two distinguishable.
  static bool _isTokenShaped(String value) =>
      value.length >= 8 &&
      value.length <= 24 &&
      RegExp(r'^[A-Za-z0-9]+$').hasMatch(value);
}

class CplException implements Exception {
  const CplException(this.message);

  final String message;

  @override
  String toString() => message;
}

enum CplKind { setlist, song }

class CplSong {
  const CplSong({
    required this.title,
    this.artist = '',
    this.body = '',
    this.originalKey = '',
    this.capo = 0,
    this.tempo,
    this.instrument = 'guitar',
    this.tuning = 'standard',
    this.youtubeUrl = '',
    this.tags = '',
  });

  final String title;
  final String artist;
  final String body;
  final String originalKey;
  final int capo;
  final int? tempo;
  final String instrument;
  final String tuning;
  final String youtubeUrl;
  final String tags;

  Map<String, Object?> toJson() => {
    'title': title,
    'artist': artist,
    'body': body,
    'originalKey': originalKey,
    'capo': capo,
    if (tempo != null) 'tempo': tempo,
    'instrument': instrument,
    'tuning': tuning,
    if (youtubeUrl.isNotEmpty) 'youtubeUrl': youtubeUrl,
    if (tags.isNotEmpty) 'tags': tags,
  };

  static CplSong fromJson(Object? json, {int index = 0}) {
    if (json is! Map) {
      throw CplException('Song ${index + 1} is not a JSON object.');
    }
    final title = _string(json['title']).trim();
    if (title.isEmpty) {
      throw CplException('Song ${index + 1} has no title.');
    }
    return CplSong(
      title: title,
      artist: _string(json['artist']),
      body: _string(json['body']),
      originalKey: _string(json['originalKey']),
      capo: _int(json['capo']) ?? 0,
      tempo: _int(json['tempo']),
      instrument: _string(json['instrument'], fallback: 'guitar'),
      tuning: _string(json['tuning'], fallback: 'standard'),
      youtubeUrl: _string(json['youtubeUrl']),
      tags: _string(json['tags']),
    );
  }
}

class CplItem {
  const CplItem({
    required this.song,
    this.transpose = 0,
    this.capo,
    this.note = '',
    this.position = 0,
  });

  final CplSong song;
  final int transpose;
  final int? capo;
  final String note;
  final int position;

  Map<String, Object?> toJson() => {
    'position': position,
    'transpose': transpose,
    if (capo != null) 'capo': capo,
    if (note.isNotEmpty) 'note': note,
    'song': song.toJson(),
  };

  static CplItem fromJson(Object? json, {required int index}) {
    if (json is! Map) {
      throw CplException('Setlist item ${index + 1} is not a JSON object.');
    }
    return CplItem(
      song: CplSong.fromJson(json['song'], index: index),
      transpose: _int(json['transpose']) ?? 0,
      capo: _int(json['capo']),
      note: _string(json['note']),
      position: _int(json['position']) ?? index,
    );
  }
}

/// A decoded `.cpl` payload. Setlists carry [items]; single songs carry
/// [song].
class CplBundle {
  const CplBundle.setlist({
    required this.title,
    required this.items,
    this.description = '',
  }) : kind = CplKind.setlist,
       song = null;

  const CplBundle.song({required this.song, required this.title})
    : kind = CplKind.song,
      items = const [],
      description = '';

  final CplKind kind;
  final String title;
  final String description;
  final List<CplItem> items;
  final CplSong? song;

  int get songCount => kind == CplKind.setlist ? items.length : 1;

  List<CplSong> get songs =>
      kind == CplKind.setlist ? items.map((item) => item.song).toList() : [song!];

  Map<String, Object?> toJson() => {
    'format': CplFormat.version,
    'type': kind.name,
    if (kind == CplKind.setlist) ...{
      'setlist': {
        'title': title,
        if (description.isNotEmpty) 'description': description,
        'items': [
          for (var i = 0; i < items.length; i++)
            CplItem(
              song: items[i].song,
              transpose: items[i].transpose,
              capo: items[i].capo,
              note: items[i].note,
              position: i,
            ).toJson(),
        ],
      },
    } else
      'song': song!.toJson(),
  };

  String toPrettyJson() =>
      const JsonEncoder.withIndent('  ').convert(toJson());

  String toCompactJson() => jsonEncode(toJson());

  /// Compressed, URL-safe payload for links and QR codes.
  String toShareCode() {
    final bytes = utf8.encode(toCompactJson());
    final gzipped = GZipEncoder().encodeBytes(bytes, level: 9);
    return base64Url.encode(gzipped).replaceAll('=', '');
  }

  /// A link a human can send to someone else.
  String toLink() => '${CplFormat.linkHost}/c/${toShareCode()}';

  static CplBundle decodeJson(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      throw const CplException(
        'That does not look like a ChordPlane file. Expected JSON.',
      );
    }
    return _fromDecoded(decoded);
  }

  /// Reads any of: a list of songs, a setlist export, or a single song.
  static CplBundle _fromDecoded(Object? decoded) {
    if (decoded is! Map) {
      throw const CplException('ChordPlane files must contain an object.');
    }
    final format = decoded['format'];
    if (format != null && format != CplFormat.version) {
      throw CplException(
        'Unsupported ChordPlane format "$format". This app reads '
        '${CplFormat.version}.',
      );
    }
    final type = decoded['type'] ?? (decoded['setlist'] != null ? 'setlist' : 'song');
    if (type == 'setlist') {
      final setlist = decoded['setlist'];
      if (setlist is! Map) {
        throw const CplException('This setlist file has no setlist data.');
      }
      final items = setlist['items'];
      if (items is! List || items.isEmpty) {
        throw const CplException('This setlist has no songs.');
      }
      return CplBundle.setlist(
        title: _string(setlist['title'], fallback: 'Imported setlist'),
        description: _string(setlist['description']),
        items: [
          for (var i = 0; i < items.length; i++)
            CplItem.fromJson(items[i], index: i),
        ],
      );
    }
    final songs = decoded['songs'];
    final source =
        decoded['song'] ??
        (songs is List && songs.isNotEmpty ? songs.first : null);
    final song = CplSong.fromJson(source);
    return CplBundle.song(song: song, title: song.title);
  }

  /// Decodes a share link, custom-scheme URI, or bare share code.
  static CplBundle decodeShareCode(String input) {
    final code = extractShareCode(input);
    if (code == null) {
      throw const CplException('No ChordPlane share code found in that text.');
    }
    final Uint8List compressed;
    try {
      compressed = base64Url.decode(base64Url.normalize(code));
    } on FormatException {
      throw const CplException('That share code is not valid base64.');
    }
    final List<int> bytes;
    try {
      bytes = GZipDecoder().decodeBytes(compressed);
    } catch (_) {
      throw const CplException('That share code is corrupted.');
    }
    try {
      return decodeJson(utf8.decode(bytes));
    } on FormatException {
      throw const CplException('That share code is corrupted.');
    }
  }

  /// Pulls the code out of `https://chordplane.app/c/<code>`,
  /// `chordplane://c/<code>`, or a bare code.
  static String? extractShareCode(String raw) {
    final input = raw.trim();
    if (input.isEmpty) return null;
    final uri = Uri.tryParse(input);
    if (uri != null && uri.hasScheme) {
      final segments = uri.pathSegments;
      final index = segments.indexOf('c');
      if (index >= 0 && index + 1 < segments.length) {
        return segments[index + 1];
      }
      if (uri.host == 'c' && segments.isNotEmpty) return segments.first;
      return null;
    }
    if (input.contains('://')) return null;
    final pathIndex = input.lastIndexOf('/c/');
    if (pathIndex >= 0) {
      final tail = input.substring(pathIndex + 3);
      return tail.isEmpty ? null : tail;
    }
    // Bare codes are long, URL-safe base64 strings.
    if (RegExp(r'^[A-Za-z0-9_-]{24,}$').hasMatch(input)) return input;
    return null;
  }
}

String _string(Object? value, {String fallback = ''}) {
  if (value is String) return value;
  if (value == null) return fallback;
  return value.toString();
}

int? _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value.trim());
  return null;
}
