import 'package:chord_plane/features/sharing/cloud/auth_api.dart';
import 'package:chord_plane/features/sharing/cloud/password_reset.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotrue/gotrue.dart';

/// Covers the password-reset request and new-password screens with a fake
/// [SignInApi], so no network is touched.
void main() {
  late _FakeSignInApi api;

  setUp(() {
    api = _FakeSignInApi();
  });

  Future<void> pump(WidgetTester tester, Widget screen) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [signInApiProvider.overrideWithValue(api)],
        child: MaterialApp(home: screen),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('ResetPasswordScreen', () {
    testWidgets('validates the email address', (tester) async {
      await pump(tester, const ResetPasswordScreen());

      await tester.tap(find.text('Send reset email'));
      await tester.pump();

      expect(find.text('Enter a valid email address.'), findsOneWidget);
      expect(api.resetEmails, isEmpty);
    });

    testWidgets('sends the reset email and shows the inbox state', (
      tester,
    ) async {
      await pump(tester, const ResetPasswordScreen());

      await tester.enterText(find.byType(TextField), 't@example.com');
      await tester.tap(find.text('Send reset email'));
      await tester.pumpAndSettle();

      expect(api.resetEmails, ['t@example.com']);
      expect(find.text('Check your inbox'), findsOneWidget);
      // The address is masked: first characters plus dots, never the whole
      // inbox name on a shared screen.
      expect(find.textContaining('t•'), findsOneWidget);
    });

    testWidgets('a 6-digit code completes recovery', (tester) async {
      await pump(tester, const ResetPasswordScreen());

      await tester.enterText(find.byType(TextField), 't@example.com');
      await tester.tap(find.text('Send reset email'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '123456');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(api.verifiedCodes, ['t@example.com:123456:recovery']);
      expect(find.text('Save new password'), findsOneWidget);
    });

    testWidgets('rejects a code that is not six digits', (tester) async {
      await pump(tester, const ResetPasswordScreen());

      await tester.enterText(find.byType(TextField), 't@example.com');
      await tester.tap(find.text('Send reset email'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '123');
      await tester.tap(find.text('Continue'));
      await tester.pump();

      expect(
        find.text('Enter the 6-digit code from the email.'),
        findsOneWidget,
      );
      expect(api.verifiedCodes, isEmpty);
    });

    testWidgets('surfaces a failed request', (tester) async {
      api.resetFailure = const AuthException(
        'Email rate limit exceeded',
        statusCode: '429',
      );
      await pump(tester, const ResetPasswordScreen());

      await tester.enterText(find.byType(TextField), 't@example.com');
      await tester.tap(find.text('Send reset email'));
      await tester.pumpAndSettle();

      expect(find.textContaining('already sent a few emails'), findsOneWidget);
      expect(find.text('Check your inbox'), findsNothing);
    });
  });

  group('SetNewPasswordScreen', () {
    testWidgets('rejects a short password', (tester) async {
      await pump(tester, const SetNewPasswordScreen());

      await tester.enterText(find.byType(TextField).at(0), 'short');
      await tester.enterText(find.byType(TextField).at(1), 'short');
      await tester.tap(find.text('Save new password'));
      await tester.pump();

      expect(
        find.text('Password needs at least 10 characters.'),
        findsOneWidget,
      );
      expect(api.updatedPasswords, isEmpty);
    });

    testWidgets('rejects mismatched passwords', (tester) async {
      await pump(tester, const SetNewPasswordScreen());

      await tester.enterText(find.byType(TextField).at(0), 'password123');
      await tester.enterText(find.byType(TextField).at(1), 'password124');
      await tester.tap(find.text('Save new password'));
      await tester.pump();

      expect(find.text('The two passwords do not match.'), findsOneWidget);
      expect(api.updatedPasswords, isEmpty);
    });

    testWidgets('saves the password and confirms', (tester) async {
      await pump(tester, const SetNewPasswordScreen());

      await tester.enterText(find.byType(TextField).at(0), 'password123');
      await tester.enterText(find.byType(TextField).at(1), 'password123');
      await tester.tap(find.text('Save new password'));
      await tester.pumpAndSettle();

      expect(api.updatedPasswords, ['password123']);
      expect(find.text('Password updated'), findsOneWidget);
    });

    testWidgets('explains an expired recovery session', (tester) async {
      api.updateFailure = AuthSessionMissingException();
      await pump(tester, const SetNewPasswordScreen());

      await tester.enterText(find.byType(TextField).at(0), 'password123');
      await tester.enterText(find.byType(TextField).at(1), 'password123');
      await tester.tap(find.text('Save new password'));
      await tester.pumpAndSettle();

      expect(find.textContaining('reset link has expired'), findsOneWidget);
      expect(find.text('Password updated'), findsNothing);
    });
  });
}

class _FakeSignInApi implements SignInApi {
  final resetEmails = <String>[];
  final updatedPasswords = <String>[];
  final verifiedCodes = <String>[];
  Object? resetFailure;
  Object? updateFailure;
  Object? verifyFailure;

  @override
  Future<void> resetPassword(String email) async {
    final failure = resetFailure;
    if (failure != null) throw failure;
    resetEmails.add(email);
  }

  @override
  Future<AuthResponse> verifyEmailCode({
    required String email,
    required String code,
    required OtpType type,
  }) async {
    final failure = verifyFailure;
    if (failure != null) throw failure;
    verifiedCodes.add('$email:$code:${type.name}');
    return _emptyResponse();
  }

  @override
  Future<AuthResponse> verifyEmailLink({
    required String tokenHash,
    required OtpType type,
  }) async => _emptyResponse();

  AuthResponse _emptyResponse() => AuthResponse();

  @override
  Future<void> updatePassword(String password) async {
    final failure = updateFailure;
    if (failure != null) throw failure;
    updatedPasswords.add(password);
  }

  @override
  Future<AuthResponse> signIn(String email, String password) =>
      throw UnimplementedError();

  @override
  Future<AuthResponse> signUp(String email, String password) =>
      throw UnimplementedError();

  @override
  Future<AuthResponse> signInWithGoogle(String idToken) =>
      throw UnimplementedError();

  @override
  Future<void> resendConfirmation(String email) async {}

  @override
  Future<void> signOut() async {}
}
