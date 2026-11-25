import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';
import 'google_auth.dart';

/// Local-first authentication seam.
///
/// Without Supabase credentials the app runs on [GuestAuthGateway], keeping
/// every write under a local user id. With credentials the [SupabaseAuthGateway]
/// takes over; repositories and screens never know the difference.
abstract interface class AuthGateway {
  String? get currentUserId;

  String? get currentUserEmail;

  bool get isSignedIn;

  Stream<String?> get userIdChanges;

  /// Emits on every sign-in / sign-out so auth-gated UI rebuilds.
  Stream<bool> get signedInChanges;

  /// Raw Supabase auth events, used to detect password-recovery links.
  Stream<AuthChangeEvent> get authEvents;
}

class GuestAuthGateway implements AuthGateway {
  const GuestAuthGateway();

  static const String localUserId = 'local-user';

  @override
  String? get currentUserId => localUserId;

  @override
  String? get currentUserEmail => null;

  @override
  bool get isSignedIn => false;

  @override
  Stream<String?> get userIdChanges => Stream<String?>.value(localUserId);

  @override
  Stream<bool> get signedInChanges => Stream<bool>.value(false);

  @override
  Stream<AuthChangeEvent> get authEvents =>
      const Stream<AuthChangeEvent>.empty();
}

class SupabaseAuthGateway implements AuthGateway {
  SupabaseAuthGateway(this._auth);

  final GoTrueClient _auth;

  @override
  String? get currentUserId => _auth.currentUser?.id;

  @override
  String? get currentUserEmail => _auth.currentUser?.email;

  @override
  bool get isSignedIn => _auth.currentUser != null;

  @override
  Stream<String?> get userIdChanges =>
      _auth.onAuthStateChange.map((event) => event.session?.user.id);

  @override
  Stream<bool> get signedInChanges =>
      _auth.onAuthStateChange.map((event) => event.session?.user != null);

  @override
  Stream<AuthChangeEvent> get authEvents =>
      _auth.onAuthStateChange.map((event) => event.event);
}

final authGatewayProvider = Provider<AuthGateway>((ref) {
  if (!AppConfig.hasSupabase || AppConfig.supabaseInitError != null) {
    return const GuestAuthGateway();
  }
  return SupabaseAuthGateway(Supabase.instance.client.auth);
});

/// The active user id as a stream so repositories rebuild when the account
/// changes. A one-time Provider kept favorites and local ownership bound to
/// whichever account happened to be signed in on the first frame.
final currentUserIdProvider = StreamProvider<String>((ref) async* {
  final gateway = ref.watch(authGatewayProvider);
  yield gateway.currentUserId ?? GuestAuthGateway.localUserId;
  yield* gateway.userIdChanges.map(
    (id) => id ?? GuestAuthGateway.localUserId,
  );
});

/// True when Supabase accepted the JWT but the user row no longer exists.
/// continuing with that session produces a 403 on every request.
bool isStaleUserError(Object error) {
  final message = error.toString().toLowerCase();
  return message.contains('user from sub claim in jwt does not exist') ||
      message.contains('jwt does not exist');
}

/// Clears both the Supabase session and the cached Google account after a
/// stale JWT. Without the Google sign-out the next tap silently reuses the
/// deleted identity and the error repeats.
Future<void> clearStaleAuthSession() async {
  try {
    await Supabase.instance.client.auth.signOut();
  } catch (error) {
    debugPrint('Stale Supabase sign-out failed: $error');
  }
  await const GoogleAuth().signOut();
}

/// Rebuilds consumers whenever the sign-in state flips.
final signedInProvider = StreamProvider<bool>(
  (ref) => ref.watch(authGatewayProvider).signedInChanges,
);

/// Raw auth events. The app root watches this for password-recovery links.
final authEventProvider = StreamProvider<AuthChangeEvent>(
  (ref) => ref.watch(authGatewayProvider).authEvents,
);
