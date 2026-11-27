import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_gateway.dart';
import '../../features/songs/data/song_providers.dart';
import 'profile_avatar.dart';

/// One avatar for every tab. Guests get a plain default icon — no generated
/// DiceBear image until they actually sign in.
class ProfileAvatarButton extends ConsumerWidget {
  const ProfileAvatarButton({super.key, this.size = 30});

  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn =
        ref.watch(signedInProvider).value ??
        ref.read(authGatewayProvider).isSignedIn;
    final profile = signedIn ? ref.watch(profileInfoProvider).value : null;
    final seed = profileAvatarSeed(
      localName: signedIn ? ref.watch(profileNameProvider) : '',
      username: profile?.username,
      email: profile?.email,
    );

    return IconButton(
      tooltip: 'Your profile',
      onPressed: () => context.push('/profile'),
      icon: ProfileAvatar(seed: seed, size: size, signedIn: signedIn),
    );
  }
}
