import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Picks the seed used to generate an avatar: the local display name first,
/// then the account username, then email, with a stable fallback.
String profileAvatarSeed({
  required String localName,
  required String? username,
  required String? email,
}) {
  final local = localName.trim();
  if (local.isNotEmpty) return local;
  final name = username?.trim() ?? '';
  if (name.isNotEmpty) return name;
  final mail = email?.trim() ?? '';
  if (mail.isNotEmpty) return mail;
  return 'ChordPlane';
}

/// The app's one circular avatar, shared by the profile page, the tab-bar
/// button and community song footers.
///
/// A dedicated ClipOval keeps the image perfectly round regardless of what
/// the SVG paints. The border is drawn as a separate decoration on top so it
/// cannot introduce square corners or inset the image with decoration
/// padding.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    required this.seed,
    required this.size,
    this.signedIn = true,
    this.showBorder = true,
  });

  /// Value used to generate the avatar. Display name first, then username,
  /// then email — the same order used everywhere avatars appear.
  final String seed;
  final double size;
  final bool signedIn;
  final bool showBorder;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fallback = Icon(
      Icons.person_outline,
      size: size * 0.52,
      color: scheme.onSecondaryContainer,
    );

    final Widget content;
    if (signedIn && seed.trim().isNotEmpty) {
      final url =
          'https://api.dicebear.com/10.x/initial-face/svg?seed='
          '${Uri.encodeComponent(seed.trim())}';
      content = SvgPicture.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholderBuilder: (_) => fallback,
        errorBuilder: (_, _, _) => fallback,
      );
    } else {
      content = fallback;
    }

    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: scheme.secondaryContainer,
              child: Center(child: content),
            ),
            if (showBorder)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
