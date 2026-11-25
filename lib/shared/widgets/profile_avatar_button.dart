import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_gateway.dart';
import '../../features/songs/data/song_providers.dart';

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
    final scheme = Theme.of(context).colorScheme;

    Widget avatar;
    if (signedIn) {
      final localName = ref.watch(profileNameProvider).trim();
      final profile = ref.watch(profileInfoProvider).value;
      final seed = localName.isNotEmpty
          ? localName
          : (profile?.username.trim().isNotEmpty == true
                ? profile!.username.trim()
                : (profile?.email.trim().isNotEmpty == true
                      ? profile!.email.trim()
                      : 'ChordPlane'));
      final url =
          'https://api.dicebear.com/10.x/initial-face/svg?seed=${Uri.encodeComponent(seed)}';
      avatar = ClipOval(
        child: SizedBox(
          width: size,
          height: size,
          child: Container(
            color: scheme.secondaryContainer,
            child: SvgPicture.network(
              url,
              fit: BoxFit.cover,
              placeholderBuilder: (_) => Icon(
                Icons.person_outline,
                size: size * 0.62,
                color: scheme.onSecondaryContainer,
              ),
            ),
          ),
        ),
      );
    } else {
      avatar = CircleAvatar(
        radius: size / 2,
        backgroundColor: scheme.secondaryContainer,
        child: Icon(
          Icons.person_outline,
          size: size * 0.62,
          color: scheme.onSecondaryContainer,
        ),
      );
    }

    return IconButton(
      tooltip: 'Your profile',
      onPressed: () => context.push('/profile'),
      icon: avatar,
    );
  }
}
