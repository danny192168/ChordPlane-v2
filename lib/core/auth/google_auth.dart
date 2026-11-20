import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../config/app_config.dart';

/// A Google account pick that produced an ID token Supabase can verify.
class GoogleAuthResult {
  const GoogleAuthResult({required this.idToken});

  final String idToken;
}

/// A Google sign-in failure with a message the auth sheet can show as-is.
class GoogleAuthException implements Exception {
  const GoogleAuthException(this.message, {this.canceled = false});

  final String message;

  /// True when the user dismissed the account picker. Callers should return
  /// quietly instead of showing an error.
  final bool canceled;

  @override
  String toString() => 'GoogleAuthException: $message';
}

/// The native account-picker operations the auth gate needs. Kept behind an
/// interface so widget tests can avoid the platform channel.
abstract interface class GoogleAuthApi {
  Future<GoogleAuthResult> signIn();

  Future<void> signOut();
}

/// Native Google Sign-In backed by the platform account picker.
///
/// No `google-services.json` is required: Android needs the *web* client ID as
/// `serverClientId` and verifies the package/signing key from the Android
/// OAuth client, while iOS uses its own client ID plus the reversed client ID
/// URL scheme declared in `Info.plist`.
class GoogleAuth implements GoogleAuthApi {
  const GoogleAuth();

  static Future<void>? _initialization;

  Future<void> _ensureInitialized() {
    final pending = _initialization;
    if (pending != null) return pending;
    final future = _initialize();
    _initialization = future;
    // A failed initialization (a transient platform error, say) should not be
    // cached forever; the next tap gets a fresh attempt.
    future.then<void>(
      (_) {},
      onError: (Object _) {
        _initialization = null;
      },
    );
    return future;
  }

  Future<void> _initialize() async {
    if (kIsWeb) {
      throw const GoogleAuthException(
        'Google sign-in is not available in this build.',
      );
    }
    if (AppConfig.googleWebClientId.isEmpty) {
      throw const GoogleAuthException(
        'Google sign-in is not configured for this build.',
      );
    }
    if (!GoogleSignIn.instance.supportsAuthenticate()) {
      throw const GoogleAuthException(
        'Google sign-in is not supported on this platform.',
      );
    }
    final isIOS = defaultTargetPlatform == TargetPlatform.iOS;
    await GoogleSignIn.instance.initialize(
      // On iOS the platform SDK identifies the app by its iOS OAuth client.
      // Android ignores this and uses the Android client registered for the
      // package + signing certificate.
      clientId: isIOS && AppConfig.googleIosClientId.isNotEmpty
          ? AppConfig.googleIosClientId
          : null,
      // The web client is the token audience Supabase verifies on Android.
      serverClientId: AppConfig.googleWebClientId,
    );
  }

  @override
  Future<GoogleAuthResult> signIn() async {
    try {
      await _ensureInitialized();
    } on GoogleAuthException {
      rethrow;
    } catch (error) {
      debugPrint('Google Sign-In initialization failed: $error');
      throw const GoogleAuthException(
        'Google sign-in is not configured correctly for this build.',
      );
    }

    final GoogleSignInAccount account;
    try {
      account = await GoogleSignIn.instance.authenticate();
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) {
        throw const GoogleAuthException(
          'Google sign-in was cancelled.',
          canceled: true,
        );
      }
      debugPrint(
        'Google Sign-In failed: ${error.code} ${error.description ?? ''}',
      );
      if (error.code == GoogleSignInExceptionCode.clientConfigurationError ||
          error.code == GoogleSignInExceptionCode.providerConfigurationError) {
        throw const GoogleAuthException(
          'Google sign-in is not configured correctly for this build. '
          'Check the OAuth client ID and signing certificate.',
        );
      }
      throw GoogleAuthException(
        error.description?.trim().isNotEmpty == true
            ? error.description!
            : 'Google sign-in failed. Try again.',
      );
    } catch (error) {
      debugPrint('Google Sign-In failed unexpectedly: $error');
      throw const GoogleAuthException('Google sign-in failed. Try again.');
    }

    final idToken = account.authentication.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw const GoogleAuthException(
        'Google did not return a sign-in token. Try again.',
      );
    }
    return GoogleAuthResult(idToken: idToken);
  }

  @override
  Future<void> signOut() async {
    try {
      await _ensureInitialized();
      await GoogleSignIn.instance.signOut();
    } catch (error) {
      // Signing out of Supabase must succeed even if the Google SDK was never
      // initialized (email-only build) or the platform channel is absent.
      debugPrint('Google sign-out skipped: $error');
    }
  }
}

final googleAuthProvider = Provider<GoogleAuthApi>((ref) => const GoogleAuth());

/// Whether the sign-in sheet should offer Google.
///
/// Hidden on web (native accounts only), on desktop, and whenever no client ID
/// was injected with `--dart-define=GOOGLE_WEB_CLIENT_ID=…`.
final googleSignInEnabledProvider = Provider<bool>((ref) {
  final isMobile =
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
  return !kIsWeb && isMobile && AppConfig.hasGoogleSignIn;
});
