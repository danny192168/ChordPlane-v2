import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Local-first authentication seam.
///
/// Phase 1 ships [GuestAuthGateway], which keeps every write under a local
/// user id. Phase 3 swaps in a Clerk-backed implementation without changing
/// repositories or screens.
abstract interface class AuthGateway {
  String? get currentUserId;

  bool get isSignedIn;

  Stream<String?> get userIdChanges;
}

class GuestAuthGateway implements AuthGateway {
  const GuestAuthGateway();

  static const String localUserId = 'local-user';

  @override
  String? get currentUserId => localUserId;

  @override
  bool get isSignedIn => false;

  @override
  Stream<String?> get userIdChanges => Stream<String?>.value(localUserId);
}

final authGatewayProvider = Provider<AuthGateway>(
  (ref) => const GuestAuthGateway(),
);

final currentUserIdProvider = Provider<String>(
  (ref) => ref.watch(authGatewayProvider).currentUserId ?? 'local-user',
);
