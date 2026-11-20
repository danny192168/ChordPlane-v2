import 'package:chord_plane/core/auth/google_auth.dart';
import 'package:chord_plane/features/sharing/cloud/auth_gate_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotrue/gotrue.dart';

/// Exercises the sign-in gate's behaviour with faked [SignInApi] and
/// [GoogleAuthApi] implementations: success closes the sheet, credential
/// errors show a readable message, cancellation stays quiet, and a hanging
/// request times out instead of spinning forever.
void main() {
  /// The fake's behaviour, flipped per test.
  var failWith = <Object?>[null]; // first call throws this, if non-null
  var delay = Duration.zero;
  var returnsSessionlessResponse = false;

  late _FakeSignInApi api;
  late _FakeGoogleAuth google;
  var resentEmails = <String>[];

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

  setUp(() {
    failWith = <Object?>[null];
    delay = Duration.zero;
    returnsSessionlessResponse = false;
    resentEmails = <String>[];
    google = _FakeGoogleAuth();
    api = _FakeSignInApi(
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
      onResend: (email) async => resentEmails.add(email),
      onReset: (email) async {},
      onUpdatePassword: (password) async {},
      onSignOut: () async {},
    );
  });

  Future<void> pumpGate(
    WidgetTester tester, {
    bool googleEnabled = false,
    GoogleAuthApi? googleAuth,
  }) async {
    // The default 800x600 window is shorter than the sheet.
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          signInApiProvider.overrideWithValue(api),
          googleSignInEnabledProvider.overrideWithValue(googleEnabled),
          googleAuthProvider.overrideWithValue(googleAuth ?? google),
        ],
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

  testWidgets('wrong credentials show a friendly message, never a hang', (
    tester,
  ) async {
    failWith = ['Invalid login credentials'];

    await pumpGate(tester);
    await submit(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Wrong email or password.'), findsOneWidget);
    // The sheet stays open so the user can retry.
    expect(find.byType(TextField), findsNWidgets(2));
  });

  testWidgets('unconfirmed email is explained and can be resent', (
    tester,
  ) async {
    failWith = ['Email not confirmed'];

    await pumpGate(tester);
    await submit(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('Confirm your email'), findsOneWidget);
    expect(find.text('Resend confirmation email'), findsOneWidget);

    await tester.tap(find.text('Resend confirmation email'));
    await tester.pumpAndSettle();

    expect(resentEmails, ['t@example.com']);
    expect(find.textContaining('Confirmation email sent'), findsOneWidget);
  });

  testWidgets('a hanging request times out with a visible message', (
    tester,
  ) async {
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

    expect(find.textContaining('confirm your email'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.text('Resend confirmation email'), findsOneWidget);
  });

  testWidgets('Google button is hidden until a client ID is configured', (
    tester,
  ) async {
    await pumpGate(tester);

    expect(find.text('Continue with Google'), findsNothing);
    expect(find.text('or use email'), findsNothing);
  });

  testWidgets('Google sign-in sends the ID token and closes the sheet', (
    tester,
  ) async {
    await pumpGate(tester, googleEnabled: true);

    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('or use email'), findsOneWidget);

    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();

    expect(api.googleIdToken, 'google-id-token');
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('cancelling the Google picker stays quiet', (tester) async {
    google.failWith = const GoogleAuthException(
      'Google sign-in was cancelled.',
      canceled: true,
    );

    await pumpGate(tester, googleEnabled: true);
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();

    expect(find.textContaining('cancelled'), findsNothing);
    expect(find.byType(TextField), findsNWidgets(2));
  });

  testWidgets('a Google configuration error is explained', (tester) async {
    google.failWith = const GoogleAuthException(
      'Google sign-in is not configured correctly for this build.',
    );

    await pumpGate(tester, googleEnabled: true);
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();

    expect(find.textContaining('not configured correctly'), findsOneWidget);
  });

  testWidgets('forgot password opens the reset screen', (tester) async {
    await pumpGate(tester);

    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();

    expect(find.text('Reset password'), findsOneWidget);
    expect(find.text('Send reset link'), findsOneWidget);
  });
}

class _FakeSignInApi implements SignInApi {
  _FakeSignInApi({
    required this.call,
    required this.onResend,
    required this.onReset,
    required this.onUpdatePassword,
    required this.onSignOut,
  });

  final Future<AuthResponse> Function() call;
  final Future<void> Function(String email) onResend;
  final Future<void> Function(String email) onReset;
  final Future<void> Function(String password) onUpdatePassword;
  final Future<void> Function() onSignOut;

  String? googleIdToken;

  @override
  Future<AuthResponse> signIn(String email, String password) => call();

  @override
  Future<AuthResponse> signUp(String email, String password) => call();

  @override
  Future<AuthResponse> signInWithGoogle(String idToken) {
    googleIdToken = idToken;
    return call();
  }

  @override
  Future<void> resendConfirmation(String email) => onResend(email);

  @override
  Future<void> resetPassword(String email) => onReset(email);

  @override
  Future<void> updatePassword(String password) => onUpdatePassword(password);

  @override
  Future<void> signOut() => onSignOut();
}

class _FakeGoogleAuth implements GoogleAuthApi {
  Object? failWith;
  bool didSignOut = false;

  @override
  Future<GoogleAuthResult> signIn() async {
    final failure = failWith;
    if (failure != null) throw failure;
    return const GoogleAuthResult(idToken: 'google-id-token');
  }

  @override
  Future<void> signOut() async {
    didSignOut = true;
  }
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
