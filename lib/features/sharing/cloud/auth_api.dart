import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config.dart';

/// How long an auth request may run before the UI gives up with a visible
/// message. The SDK itself has no timeout. Mutable so tests can shrink it;
/// always assign back after changing.
Duration authCallTimeout = const Duration(seconds: 15);

/// How long the UI waits before offering "resend" again. Supabase Auth
/// already enforces a 60 second window per address on sign-up and recovery,
/// so matching it here turns a 429 into a countdown instead of an error.
const Duration authResendCooldown = Duration(seconds: 60);

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

  /// [username] is stored in auth metadata so the profile trigger can credit
  /// community uploads with a unique name from the first sign-in.
  Future<AuthResponse> signUp(
    String email,
    String password, {
    String? username,
  });

  /// Exchanges a native Google ID token for a Supabase session.
  Future<AuthResponse> signInWithGoogle(String idToken);

  /// Re-sends the sign-up confirmation email.
  Future<void> resendConfirmation(String email);

  /// Sends a password-reset email pointing at [AppConfig.passwordResetUrl].
  Future<void> resetPassword(String email);

  /// Redeems the six-digit code from a confirmation or recovery email.
  ///
  /// Unlike a link, a code does not depend on the PKCE verifier stored on the
  /// device that made the request, so it works when the email is opened
  /// somewhere else.
  Future<AuthResponse> verifyEmailCode({
    required String email,
    required String code,
    required OtpType type,
  });

  /// Redeems the `token_hash` carried by a confirmation or recovery link.
  Future<AuthResponse> verifyEmailLink({
    required String tokenHash,
    required OtpType type,
  });

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
  Future<AuthResponse> signUp(
    String email,
    String password, {
    String? username,
  }) => _auth.signUp(
    email: email,
    password: password,
    emailRedirectTo: AppConfig.emailConfirmUrl,
    data: username == null || username.trim().isEmpty
        ? null
        : <String, dynamic>{'username': username.trim().toLowerCase()},
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
  Future<AuthResponse> verifyEmailCode({
    required String email,
    required String code,
    required OtpType type,
  }) => _auth.verifyOTP(email: email, token: code, type: type);

  @override
  Future<AuthResponse> verifyEmailLink({
    required String tokenHash,
    required OtpType type,
  }) => _auth.verifyOTP(type: type, tokenHash: tokenHash);

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

/// What went wrong, in terms the UI can switch on instead of matching text.
enum AuthFailureKind {
  invalidCredentials,
  emailNotConfirmed,
  emailAlreadyRegistered,
  weakPassword,
  emailRateLimited,
  tooManyRequests,
  expiredToken,
  badToken,
  captchaFailed,
  providerDisabled,
  badGoogleToken,
  badApiKey,
  offline,
  mailerFailed,
  unknown,
}

class AuthFailure {
  const AuthFailure(this.kind, this.message);

  final AuthFailureKind kind;
  final String message;
}

/// Classifies a Supabase auth error using its stable `code` and HTTP
/// `statusCode` first, and its message only as a fallback. Older projects
/// report the same conditions as plain text, so both are covered.
AuthFailure describeAuthFailure(AuthException error) {
  final message = error.message.toLowerCase();
  final code = (error.code ?? '').toLowerCase();
  final status = error.statusCode;

  bool has(List<String> needles) =>
      needles.any((needle) => message.contains(needle));

  if (code == 'invalid_credentials' ||
      has(['invalid login credentials'])) {
    return const AuthFailure(
      AuthFailureKind.invalidCredentials,
      'Wrong email or password.',
    );
  }
  if (code == 'email_not_confirmed' || has(['email not confirmed'])) {
    return const AuthFailure(
      AuthFailureKind.emailNotConfirmed,
      'Confirm your email first — check your inbox (and spam).',
    );
  }
  if (code == 'user_already_exists' ||
      has(['already registered', 'already exists', 'user_already_exists'])) {
    return const AuthFailure(
      AuthFailureKind.emailAlreadyRegistered,
      'That email already has an account. Sign in instead, or use '
      '"Forgot password?" if you cannot remember it.',
    );
  }
  if (code == 'weak_password' ||
      has([
        'password should be at least',
        'password is too short',
        'weak password',
        'password does not meet',
      ])) {
    return const AuthFailure(
      AuthFailureKind.weakPassword,
      'That password is too weak — use at least 10 characters.',
    );
  }
  if (code == 'over_email_send_rate_limit' || has(['email rate limit'])) {
    return const AuthFailure(
      AuthFailureKind.emailRateLimited,
      'We have already sent a few emails. Wait about an hour, or use the '
      'last email we sent.',
    );
  }
  if (code == 'over_request_rate_limit' ||
      status == '429' ||
      has(['rate limit', 'too many requests', 'too many attempts'])) {
    return const AuthFailure(
      AuthFailureKind.tooManyRequests,
      'Too many attempts. Wait a minute and try again.',
    );
  }
  if (code == 'otp_expired' ||
      has([
        'token has expired',
        'has expired or is invalid',
        'expired or is invalid',
        'invalid or has expired',
      ])) {
    return const AuthFailure(
      AuthFailureKind.expiredToken,
      'That link or code has expired. Request a new one.',
    );
  }
  if (code == 'otp_disabled') {
    return const AuthFailure(
      AuthFailureKind.expiredToken,
      'That link or code is no longer valid. Request a new one.',
    );
  }
  if (code == 'captcha_failed' || has(['captcha'])) {
    return const AuthFailure(
      AuthFailureKind.captchaFailed,
      'The bot check did not pass. Try again.',
    );
  }
  if (code == 'same_password' || has(['should be different'])) {
    return const AuthFailure(
      AuthFailureKind.weakPassword,
      'That is already your password — choose a new one.',
    );
  }
  if (has(['provider is not enabled', 'unsupported provider'])) {
    return const AuthFailure(
      AuthFailureKind.providerDisabled,
      'Google sign-in is not enabled for this app yet.',
    );
  }
  if (has(['invalid id token', 'invalid jwt', 'audience'])) {
    return const AuthFailure(
      AuthFailureKind.badGoogleToken,
      'Google sign-in could not be verified. Check the OAuth client IDs '
      'in Supabase.',
    );
  }
  if (has(['invalid api key', 'apikey'])) {
    return const AuthFailure(
      AuthFailureKind.badApiKey,
      'The app is configured with a bad API key.',
    );
  }
  if (has([
    'failed host lookup',
    'socket',
    'connection refused',
    'connection closed',
    'network is unreachable',
    'clientexception',
  ])) {
    return const AuthFailure(
      AuthFailureKind.offline,
      'No connection. Check your network and try again.',
    );
  }
  if (status == '500' ||
      has(['gomail', 'sending email', 'unexpected_failure', 'database error'])) {
    return const AuthFailure(
      AuthFailureKind.mailerFailed,
      'The server could not send that email just now. Try again in a few '
      'minutes.',
    );
  }
  return AuthFailure(AuthFailureKind.unknown, error.message);
}

/// Turns Supabase's error text into something a musician can act on.
String friendlyAuthMessage(AuthException error) =>
    describeAuthFailure(error).message;

/// Shown when a request fails before it reaches Supabase at all (no network,
/// DNS failure, a closed connection). Screens previously interpolated the raw
/// exception, which read like an internal error rather than "you are offline".
const String offlineAuthMessage =
    'No connection. Check your network and try again.';
