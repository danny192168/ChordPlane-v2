import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';

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
}

final authGatewayProvider = Provider<AuthGateway>((ref) {
  if (!AppConfig.hasSupabase || AppConfig.supabaseInitError != null) {
    return const GuestAuthGateway();
  }
  return SupabaseAuthGateway(Supabase.instance.client.auth);
});

final currentUserIdProvider = Provider<String>(
  (ref) => ref.watch(authGatewayProvider).currentUserId ?? 'local-user',
);

/// Rebuilds consumers whenever the sign-in state flips.
final signedInProvider = StreamProvider<bool>(
  (ref) => ref.watch(authGatewayProvider).signedInChanges,
);
