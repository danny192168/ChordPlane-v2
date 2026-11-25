import 'package:chord_plane/core/validation/youtube_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('YouTube link validation', () {
    test('accepts empty links and supported YouTube hosts', () {
      const allowed = <String>[
        '',
        'https://youtube.com/watch?v=dQw4w9WgXcQ',
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        'https://m.youtube.com/watch?v=dQw4w9WgXcQ',
        'https://music.youtube.com/watch?v=dQw4w9WgXcQ',
        'https://youtu.be/dQw4w9WgXcQ',
        'http://www.youtu.be/dQw4w9WgXcQ',
      ];
      for (final link in allowed) {
        expect(isValidYouTubeLink(link), isTrue, reason: link);
        expect(validateYouTubeLink(link), isNull, reason: link);
      }
    });

    test('rejects other hosts, schemes and malformed links', () {
      const rejected = <String>[
        'example.com/watch?v=dQw4w9WgXcQ',
        'https://notyoutube.com/watch?v=dQw4w9WgXcQ',
        'https://youtube.com.evil.test/watch',
        'ftp://youtube.com/watch',
        'youtube.com',
        'not a url',
      ];
      for (final link in rejected) {
        expect(isValidYouTubeLink(link), isFalse, reason: link);
        expect(
          validateYouTubeLink(link),
          'Use a youtube.com or youtu.be link.',
          reason: link,
        );
      }
    });
  });
}
