import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';

/// Debug-only diagnostic: runs the app's own network stack step by step
/// (DNS → TCP → HTTP) with timings, so a hang can be pinned to one layer.
/// Shell-side curl does not run with the app's UID, so it can succeed while
/// the app is blocked by per-app network controls.
class NetworkDiagnosticsSheet extends StatefulWidget {
  const NetworkDiagnosticsSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => const NetworkDiagnosticsSheet(),
    );
  }

  @override
  State<NetworkDiagnosticsSheet> createState() =>
      _NetworkDiagnosticsSheetState();
}

class _Step {
  _Step(this.title);
  final String title;
  String result = '…';
  bool done = false;
  bool failed = false;
}

class _NetworkDiagnosticsSheetState extends State<NetworkDiagnosticsSheet> {
  late final List<_Step> _steps;
  Timer? _ticker;
  int _elapsedMs = 0;

  @override
  void initState() {
    super.initState();
    _steps = [
      _Step('DNS lookup'),
      _Step('TCP connect'),
      _Step('HTTPS request'),
      _Step('HTTPS request (example.com)'),
    ];
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (mounted) setState(() => _elapsedMs += 200);
    });
    unawaited(_run());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<T> _timed<T>(
    _Step step,
    Future<T> Function() run,
    String Function(T) describe,
  ) async {
    final watch = Stopwatch()..start();
    try {
      final value = await run();
      watch.stop();
      step.result = '${describe(value)} (${watch.elapsedMilliseconds}ms)';
      step.failed = false;
      return value;
    } catch (error) {
      watch.stop();
      step.result =
          '$error (after ${watch.elapsedMilliseconds}ms)';
      step.failed = true;
      rethrow;
    } finally {
      if (mounted) setState(() => step.done = true);
    }
  }

  Future<void> _run() async {
    final host = AppConfig.supabaseUrl.isNotEmpty
        ? Uri.parse(AppConfig.supabaseUrl).host
        : 'eweppodjncodtsiljvak.supabase.co';
    final key = AppConfig.supabaseAnonKey;

    List<InternetAddress> addresses = const <InternetAddress>[];
    try {
      addresses = await _timed(
        _steps[0],
        () => InternetAddress.lookup(host).timeout(const Duration(seconds: 12)),
        (addrs) => addrs.map((a) => a.address).join(', '),
      );
    } catch (_) {}

    try {
      await _timed(
        _steps[1],
        () => Socket.connect(
          addresses.isNotEmpty ? addresses.first : host,
          443,
          timeout: const Duration(seconds: 12),
        ).then<void>((socket) => socket.destroy()),
        (_) => 'connected to $host:443',
      );
    } catch (_) {}

    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
      await _timed(
        _steps[2],
        () async {
          final request = await client
              .getUrl(Uri.parse('https://$host/auth/v1/health'))
            ..headers.set('apikey', key);
          final response = await request.close().timeout(
            const Duration(seconds: 12),
          );
          await response.drain<void>();
          client.close(force: true);
          return response.statusCode;
        },
        (status) => 'auth/v1/health → HTTP $status',
      );
    } catch (_) {}

    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
      await _timed(
        _steps[3],
        () async {
          final request = await client
              .getUrl(Uri.parse('https://example.com/'));
          final response = await request.close().timeout(
            const Duration(seconds: 12),
          );
          await response.drain<void>();
          client.close(force: true);
          return response.statusCode;
        },
        (status) => 'example.com → HTTP $status',
      );
    } catch (_) {}

    _ticker?.cancel();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.7,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Network diagnostics', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Elapsed ${_elapsedMs / 1000}s',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            for (final step in _steps)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: step.done
                          ? Icon(
                              step.failed ? Icons.close : Icons.check,
                              size: 20,
                              color: step.failed
                                  ? theme.colorScheme.error
                                  : Colors.green,
                            )
                          : const Padding(
                              padding: EdgeInsets.all(4),
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                              ),
                            ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(step.title,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold)),
                          Text(
                            step.result,
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.3,
                              color: step.failed
                                  ? theme.colorScheme.error
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const Spacer(),
            Text(
              'Shell curl works on this device, so any hang here means the '
              'app itself is blocked (per-app data controls) or the Dart '
              'network stack differs from curl.',
              style: theme.textTheme.bodySmall?.copyWith(height: 1.35),
            ),
          ],
        ),
      ),
    );
  }
}
