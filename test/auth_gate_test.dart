import 'package:chord_plane/features/sharing/cloud/auth_gate_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotrue/gotrue.dart';

/// Exercises the sign-in gate's behaviour with a faked [SignInApi]:
/// success closes the sheet, credential errors show a readable message,
/// and a hanging request times out instead of spinning forever.
void main() {
  /// The fake's behaviour, flipped per test.
  var failWith = <Object?>[null]; // first call throws this, if non-null
  var delay = Duration.zero;
  var returnsSessionlessResponse = false;

  setUp(() {
    failWith = <Object?>[null];
    delay = Duration.zero;
    returnsSessionlessResponse = false;
  });

  Future<AuthResponse> fakeResponse() async {
    await Future<void>.delayed(delay);
    final user = User(
      id: 'user-1',
      appMetadata: const {},
      userMetadata: null,
      aud: 'authenticated',
      createdAt: '',
    );
    return AuthResponse(
      session: returnsSessionlessResponse
          ? null
          : Session(
              accessToken: 'fake-access-token',
              tokenType: 'bearer',
              expiresIn: 3600,
              user: user,
            ),
      user: user,
    );
  }

  SignInApi fakeApi() => _FakeSignInApi(
    call: () async {
      if (failWith.isNotEmpty) {
        final failure = failWith.removeAt(0);
        if (failure is Exception) throw failure;
        if (failure is String) {
          throw AuthApiException(failure, statusCode: '400');
        }
      }
      return fakeResponse();
    },
  );

  Future<void> pumpGate(WidgetTester tester) async {
    // The default 800x600 window is shorter than the sheet.
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [signInApiProvider.overrideWithValue(fakeApi())],
        child: const MaterialApp(home: Scaffold(body: _GateHost())),
      ),
    );
    // Let the bottom-sheet entrance animation finish, or taps land on a
    // mid-animation position off the bottom of the viewport.
    await tester.pumpAndSettle();
  }

  Future<void> submit(WidgetTester tester, {String label = 'Sign in'}) async {
    await tester.enterText(find.byType(TextField).at(0), 't@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'password123');
    await tester.tap(find.widgetWithText(FilledButton, label));
  }

  testWidgets('successful sign-in closes the sheet', (tester) async {
    await pumpGate(tester);
    await submit(tester);
    await tester.pump();

    expect(find.text('Please wait…'), findsOneWidget);

    await tester.pumpAndSettle();

    // The sheet pops itself on success, leaving the empty host behind.
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('wrong credentials show a friendly message, never a hang',
      (tester) async {
    failWith = ['Invalid login credentials'];

    await pumpGate(tester);
    await submit(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Wrong email or password.'), findsOneWidget);
    // The sheet stays open so the user can retry.
    expect(find.byType(TextField), findsNWidgets(2));
  });

  testWidgets('unconfirmed email is explained', (tester) async {
    failWith = ['Email not confirmed'];

    await pumpGate(tester);
    await submit(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('Confirm your email'), findsOneWidget);
  });

  testWidgets('a hanging request times out with a visible message',
      (tester) async {
    final realTimeout = authCallTimeout;
    authCallTimeout = const Duration(milliseconds: 300);
    addTearDown(() => authCallTimeout = realTimeout);
    delay = const Duration(seconds: 30);

    await pumpGate(tester);
    await submit(tester);
    await tester.pump();

    // While the request is pending the button shows the busy state.
    expect(find.text('Please wait…'), findsOneWidget);

    // The app-level timeout fires and the sheet recovers with a readable
    // message instead of spinning forever.
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('took too long to respond'), findsOneWidget);
    expect(find.text('Please wait…'), findsNothing);
    expect(find.byType(TextField), findsNWidgets(2));

    // Advance past the fake's pending delay so no timer dangles when the
    // test ends.
    await tester.pump(const Duration(seconds: 31));
  });

  testWidgets('client-side validation shows inline messages', (tester) async {
    await pumpGate(tester);
    await tester.enterText(find.byType(TextField).at(0), 'not-an-email');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();

    expect(find.text('Enter a valid email address.'), findsOneWidget);
  });

  testWidgets('create-account flow', (tester) async {
    returnsSessionlessResponse = true;

    await pumpGate(tester);
    // Switch the gate to "create account".
    await tester.tap(find.text('New here? Create an account'));
    await tester.pump();
    await submit(tester, label: 'Create account');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.textContaining('confirm your email'),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsNWidgets(2));
  });
}

class _FakeSignInApi implements SignInApi {
  const _FakeSignInApi({required this.call});

  final Future<AuthResponse> Function() call;

  @override
  Future<AuthResponse> signIn(String email, String password) => call();

  @override
  Future<AuthResponse> signUp(String email, String password) => call();

  @override
  Future<void> signOut() async {}
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
