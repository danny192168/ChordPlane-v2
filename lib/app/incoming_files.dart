import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

/// Android hands `.cpl` files to the app through ACTION_VIEW (open with) and
/// ACTION_SEND (share sheet). The native side copies the content URI into our
/// own cache, then sends a plain file path over this channel.
const MethodChannel incomingFileChannel = MethodChannel(
  'app.chordplane.chord_plane/incoming_files',
);

final StreamController<String?> _incomingFiles =
    StreamController<String?>.broadcast();

/// Keeps the last path so the app can read it even when the intent arrived
/// before Flutter's first frame.
String? _lastIncomingPath;

final incomingFilePathProvider = StreamProvider<String?>((ref) async* {
  yield _lastIncomingPath;
  yield* _incomingFiles.stream;
});

/// Registers the Dart side before `runApp` so the cold-start intent is not
/// lost. Safe to call on platforms without the native channel.
Future<void> initialiseIncomingFiles() async {
  incomingFileChannel.setMethodCallHandler((call) async {
    if (call.method == 'incomingFile' && call.arguments is String) {
      _publish(call.arguments as String);
    }
  });
  try {
    final pending = await incomingFileChannel.invokeMethod<String>(
      'takePendingFile',
    );
    if (pending != null && pending.isNotEmpty) _publish(pending);
  } on MissingPluginException {
    // Desktop, web and widget tests simply have no incoming files.
  } catch (error) {
    debugPrint('Could not read the incoming file: $error');
  }
}

void _publish(String path) {
  _lastIncomingPath = path;
  if (!_incomingFiles.isClosed) _incomingFiles.add(path);
}
