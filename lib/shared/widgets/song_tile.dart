import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/slug.dart';
import '../../features/songs/data/song_repository.dart';

class SongTile extends ConsumerWidget {
  const SongTile({
    super.key,
    required this.item,
    this.onTap,
    this.showFavorite = true,
  });

  final SongListItem item;
  final VoidCallback? onTap;
  final bool showFavorite;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final song = item.song;
    final artist = song.artist.trim();

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      leading: _SongGlyph(title: song.title),
      title: Text(
        song.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15.5),
      ),
      subtitle: Row(
        children: [
          if (artist.isNotEmpty) ...[
            Flexible(
              child: InkWell(
                borderRadius: BorderRadius.circular(4),
                onTap: () => context.push(
                  '/artist/${song.artistSlug.isEmpty ? slugify(artist) : song.artistSlug}',
                ),
                child: Text(
                  artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            if (song.originalKey.isNotEmpty) const _Dot(),
          ],
          if (song.originalKey.isNotEmpty)
            Text(
              song.originalKey,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.primary,
              ),
            ),
          if (song.capo > 0) ...[
            const _Dot(),
            Text(
              'Capo ${song.capo}',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
      trailing: showFavorite
          ? IconButton(
              tooltip: item.isFavorite ? 'Remove from favorites' : 'Favorite',
              onPressed: () async {
                await ref
                    .read(songRepositoryProvider)
                    .toggleFavorite(song.id);
              },
              icon: Icon(
                item.isFavorite ? Icons.favorite : Icons.favorite_border,
                color: item.isFavorite
                    ? theme.colorScheme.error
                    : theme.colorScheme.onSurfaceVariant,
                size: 21,
              ),
            )
          : null,
    );
  }
}

class _SongGlyph extends StatelessWidget {
  const _SongGlyph({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final letter = title.trim().isEmpty ? '?' : title.trim()[0].toUpperCase();
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        letter,
        style: TextStyle(
          color: scheme.onPrimaryContainer,
          fontWeight: FontWeight.w800,
          fontSize: 17,
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Text(
        '·',
        style: TextStyle(
          color: Theme.of(context).colorScheme.outline,
          height: 1,
        ),
      ),
    );
  }
}

class SongListEmpty extends StatelessWidget {
  const SongListEmpty({
    super.key,
    required this.title,
    required this.message,
    this.action,
    this.leading,
  });

  final String title;
  final String message;
  final Widget? action;

  /// Optional branding shown above the icon, e.g. the app logo.
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 56, 28, 28),
      child: Column(
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(height: 24),
          ],
          Icon(
            Icons.music_note_rounded,
            size: 44,
            color: theme.colorScheme.primary.withValues(alpha: 0.7),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
          if (action != null) ...[const SizedBox(height: 22), action!],
        ],
      ),
    );
  }
}
