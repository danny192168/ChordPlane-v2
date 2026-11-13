import 'package:chord_plane/web_viewer/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('viewer token extraction', () {
    test('reads the token from /s/<token> page URLs', () {
      expect(
        viewerTokenFromUri(
          Uri.parse('https://chordplane.citcs.site/s/abc123hjkmnp45'),
        ),
        'abc123hjkmnp45',
      );
      expect(
        viewerTokenFromUri(
          Uri.parse('https://chordplane.citcs.site/s/abc123hjkmnp45?x=1'),
        ),
        'abc123hjkmnp45',
      );
      expect(
        viewerTokenFromUri(Uri.parse('https://chordplane.citcs.site/')),
        isNull,
      );
    });

    test('rejects non-token-shaped values', () {
      expect(
        viewerTokenFromUri(Uri.parse('https://chordplane.citcs.site/s/short')),
        isNull,
      );
      expect(
        viewerTokenFromUri(
          Uri.parse('https://chordplane.citcs.site/s/has%20space123'),
        ),
        isNull,
      );
    });
  });
}
