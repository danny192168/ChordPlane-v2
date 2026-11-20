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

      await tester.tap(find.text('Send reset link'));
      await tester.pump();

      expect(find.text('Enter a valid email address.'), findsOneWidget);
      expect(api.resetEmails, isEmpty);
    });

    testWidgets('sends the reset email and shows the inbox state', (
      tester,
    ) async {
      await pump(tester, const ResetPasswordScreen());

      await tester.enterText(find.byType(TextField), 't@example.com');
      await tester.tap(find.text('Send reset link'));
      await tester.pumpAndSettle();

      expect(api.resetEmails, ['t@example.com']);
      expect(find.text('Check your inbox'), findsOneWidget);
      expect(find.textContaining('t@example.com'), findsOneWidget);
    });

    testWidgets('surfaces a failed request', (tester) async {
      api.resetFailure = const AuthApiException(
        'Email rate limit exceeded',
        statusCode: '429',
      );
      await pump(tester, const ResetPasswordScreen());

      await tester.enterText(find.byType(TextField), 't@example.com');
      await tester.tap(find.text('Send reset link'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Too many attempts'), findsOneWidget);
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
        find.text('Password needs at least 8 characters.'),
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
  Object? resetFailure;
  Object? updateFailure;

  @override
  Future<void> resetPassword(String email) async {
    final failure = resetFailure;
    if (failure != null) throw failure;
    resetEmails.add(email);
  }

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
