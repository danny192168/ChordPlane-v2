import 'package:flutter/material.dart';

import '../../../core/utils/relative_time.dart';
import '../../../shared/widgets/profile_avatar.dart';
import '../../community/data/community_api.dart';

/// One recently published song in the Library list. The uploader footer is
/// deliberately quiet: the song remains the primary information, and the
/// whole card still opens the sheet.
class PublishedSongCard extends StatelessWidget {
  const PublishedSongCard({
    super.key,
    required this.song,
    required this.onTap,
  });

  final CommunitySong song;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final artist = song.artist.trim();
    final credited = !song.anonymous && song.username != null;
    final credit = song.anonymous
        ? 'Anonymous'
        : (song.username ?? 'Community member');

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 14, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15.5,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          artist.isEmpty ? 'Unknown artist' : artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      if (song.originalKey.isNotEmpty) ...[
                        const _Dot(),
                        Text(
                          song.originalKey,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: scheme.primary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Row(
                children: [
                  ProfileAvatar(
                    seed: credit,
                    size: 22,
                    signedIn: credited,
                    showBorder: false,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      credit,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    relativeTime(song.createdAt),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
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
        style: TextStyle(color: Theme.of(context).colorScheme.outline, height: 1),
      ),
    );
  }
}
