import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config.dart';

/// How long an auth request may run before the UI gives up with a visible
/// message. The SDK itself has no timeout. Mutable so tests can shrink it;
/// always assign back after changing.
Duration authCallTimeout = const Duration(seconds: 15);

/// Resolves the Supabase auth client. Overridable in tests with a client
/// pointed at a local fake server.
final authClientProvider = Provider<GoTrueClient>((ref) {
  if (AppConfig.supabaseInitError != null || !AppConfig.hasSupabase) {
    throw StateError(AppConfig.supabaseInitError ?? 'Cloud is not configured.');
  }
  return Supabase.instance.client.auth;
});

/// The account operations the auth UI needs, so widget tests can fake
/// behavior without touching the network (TestWidgetsFlutterBinding blocks
/// sockets).
abstract interface class SignInApi {
  Future<AuthResponse> signIn(String email, String password);

  Future<AuthResponse> signUp(String email, String password);

  /// Exchanges a native Google ID token for a Supabase session.
  Future<AuthResponse> signInWithGoogle(String idToken);

  /// Re-sends the sign-up confirmation email.
  Future<void> resendConfirmation(String email);

  /// Sends a password-reset email pointing at [AppConfig.passwordResetUrl].
  Future<void> resetPassword(String email);

  /// Sets a new password for the member recovered from a reset link.
  Future<void> updatePassword(String password);

  Future<void> signOut();
}

class SupabaseSignInApi implements SignInApi {
  const SupabaseSignInApi();

  GoTrueClient get _auth => Supabase.instance.client.auth;

  @override
  Future<AuthResponse> signIn(String email, String password) =>
      _auth.signInWithPassword(email: email, password: password);

  @override
  Future<AuthResponse> signUp(String email, String password) => _auth.signUp(
    email: email,
    password: password,
    emailRedirectTo: AppConfig.emailConfirmUrl,
  );

  @override
  Future<AuthResponse> signInWithGoogle(String idToken) =>
      _auth.signInWithIdToken(provider: OAuthProvider.google, idToken: idToken);

  @override
  Future<void> resendConfirmation(String email) async {
    await _auth.resend(
      email: email,
      type: OtpType.signup,
      emailRedirectTo: AppConfig.emailConfirmUrl,
    );
  }

  @override
  Future<void> resetPassword(String email) => _auth.resetPasswordForEmail(
    email,
    redirectTo: AppConfig.passwordResetUrl,
  );

  @override
  Future<void> updatePassword(String password) =>
      _auth.updateUser(UserAttributes(password: password));

  @override
  Future<void> signOut() => _auth.signOut();
}

final signInApiProvider = Provider<SignInApi>((ref) {
  if (AppConfig.supabaseInitError != null || !AppConfig.hasSupabase) {
    throw StateError(AppConfig.supabaseInitError ?? 'Cloud is not configured.');
  }
  return const SupabaseSignInApi();
});

/// Bounds a call that the Supabase SDK would otherwise let hang forever.
/// The timeout surfaces as an [AuthException] so the normal error path
/// handles it.
Future<T> authCall<T>(Future<T> Function() call) {
  return call().timeout(
    authCallTimeout,
    onTimeout: () => throw const AuthException(
      'The server took too long to respond. Check your connection and '
      'the project URL, then try again.',
    ),
  );
}

/// Turns Supabase's error text into something a musician can act on.
String friendlyAuthMessage(AuthException error) {
  final message = error.message.toLowerCase();
  if (message.contains('invalid login credentials')) {
    return 'Wrong email or password.';
  }
  if (message.contains('email not confirmed')) {
    return 'Confirm your email first — check your inbox (and spam).';
  }
  if (message.contains('already registered') ||
      message.contains('already exists') ||
      message.contains('user_already_exists')) {
    return 'That email already has an account. Sign in instead, or use '
        '"Forgot password?" if you cannot remember it.';
  }
  if (message.contains('password should be at least') ||
      message.contains('password is too short') ||
      message.contains('weak password')) {
    return 'That password is too weak — use at least 8 characters.';
  }
  if (message.contains('rate limit') || message.contains('too many')) {
    return 'Too many attempts — wait a minute and try again.';
  }
  if (message.contains('provider is not enabled') ||
      message.contains('unsupported provider')) {
    return 'Google sign-in is not enabled for this app yet.';
  }
  if (message.contains('invalid id token') ||
      message.contains('invalid jwt') ||
      message.contains('audience')) {
    return 'Google sign-in could not be verified. Check the OAuth client '
        'IDs in Supabase.';
  }
  if (message.contains('invalid api key') || message.contains('apikey')) {
    return 'The app is configured with a bad API key.';
  }
  return error.message;
}
