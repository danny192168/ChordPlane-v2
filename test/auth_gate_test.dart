import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chord_plane/features/sharing/cloud/auth_gate_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotrue/gotrue.dart';

/// Exercises the sign-in gate against a real [GoTrueClient] pointed at a
/// local fake GoTrue server, so success, credential errors and timeouts all
/// produce *visible* outcomes instead of a stuck spinner.
void main() {
  final handled = StreamController<int>.broadcast();

  /// Behaviour switches the fake server reads per request.
  var failWithStatus = 0;
  var failWithBody = '';
  Completer<void>? holdRequests;

  setUpAll(() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final baseUrl = Uri.parse('http://127.0.0.1:${server.port}');
    FakeGoTrueServer.baseUrl = baseUrl;
    server.listen((request) async {
      handled.add(1);
      // Holding requests keeps the socket open without a pending timer, so
      // the test isolate can still exit cleanly afterwards.
      if (holdRequests != null) await holdRequests!.future;
      final status = failWithStatus != 0 ? failWithStatus : 200;
      final body = failWithBody.isNotEmpty
          ? failWithBody
          : jsonEncode({
              'access_token': 'fake-access-token',
              'refresh_token': 'fake-refresh-token',
              'token_type': 'bearer',
              'expires_in': 3600,
              'user': {'id': 'user-1', 'email': 't@example.com'},
            });
      request.response.statusCode = status;
      request.response.headers.contentType = ContentType.json;
      request.response.write(body);
      await request.response.close();
      failWithStatus = 0;
      failWithBody = '';
    });
    addTearDown(() {
      holdRequests?.complete();
      handled.close();
      server.close(force: true);
    });
  });

  /// Boots the gate with a GoTrueClient wired to the fake server.
  Future<void> pumpGate(WidgetTester tester) async {
    // The default 800x600 window is shorter than the sheet.
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final client = GoTrueClient(
      url: FakeGoTrueServer.baseUrl.toString(),
      headers: const {'apikey': 'fake-anon-key'},
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authClientProvider.overrideWithValue(client)],
        child: const MaterialApp(home: Scaffold(body: _GateHost())),
      ),
    );
    await tester.pump();
  }

  /// Real socket I/O needs [WidgetTester.runAsync]; wait until the fake
  /// server has handled [count] requests, then let the UI catch up. The
  /// timeout keeps a missing request a fast failure instead of a hang.
  Future<void> settle(WidgetTester tester, {int count = 1}) async {
    var seen = 0;
    await tester.runAsync(() async {
      await for (final n in handled.stream) {
        seen += n;
        if (seen >= count) break;
      }
    }).timeout(const Duration(seconds: 10), onTimeout: () {});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('successful sign-in closes the sheet', (tester) async {
    await pumpGate(tester);

    await tester.enterText(find.byType(TextField).at(0), 't@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'password123');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await settle(tester);

    // The sheet pops itself on success, leaving the empty host behind.
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('wrong credentials show a visible message, never a hang',
      (tester) async {
    failWithStatus = 400;
    failWithBody = jsonEncode({
      'code': 400,
      'error_code': 'invalid_credentials',
      'msg': 'Invalid login credentials',
    });

    await pumpGate(tester);
    await tester.enterText(find.byType(TextField).at(0), 't@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'wrong-pass-1');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await settle(tester);

    expect(find.text('Wrong email or password.'), findsOneWidget);
    // The sheet stays open so the user can retry.
    expect(find.byType(TextField), findsNWidgets(2));
  });

  testWidgets('a hanging connection times out with a visible message',
      (tester) async {
    final realTimeout = authCallTimeout;
    authCallTimeout = const Duration(milliseconds: 400);
    holdRequests = Completer<void>();
    addTearDown(() {
      authCallTimeout = realTimeout;
      holdRequests?.complete();
      holdRequests = null;
    });

    await pumpGate(tester);
    await tester.enterText(find.byType(TextField).at(0), 't@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'password123');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();

    // While the request is pending the button shows the busy state.
    expect(find.text('Please wait…'), findsOneWidget);

    // The app-level timeout fires and the sheet recovers with a readable
    // message instead of spinning forever.
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.textContaining('took too long to respond'), findsOneWidget);
    expect(find.text('Please wait…'), findsNothing);
    expect(find.byType(TextField), findsNWidgets(2));
  });

  testWidgets('client-side validation shows inline messages', (tester) async {
    await pumpGate(tester);
    await tester.enterText(find.byType(TextField).at(0), 'not-an-email');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();

    expect(find.text('Enter a valid email address.'), findsOneWidget);
  });
}

/// Shared handle for the fake GoTrue server started in [setUpAll].
class FakeGoTrueServer {
  static late Uri baseUrl;
}

/// Opens the sheet inside the test tree without needing a build context.
class _GateHost extends StatefulWidget {
  const _GateHost();

  @override
  State<_GateHost> createState() => _GateHostState();
}

class _GateHostState extends State<_GateHost> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showSignInGate(context);
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
