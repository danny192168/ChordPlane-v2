import 'package:flutter/material.dart';

import '../../features/songs/data/song_repository.dart';
import 'song_tile.dart';

/// Artist tiles shared by Saved and Favorites. Both tabs drill into an artist
/// page filtered to the current collection.
class ArtistTileList extends StatelessWidget {
  const ArtistTileList({
    super.key,
    required this.artists,
    required this.onTap,
    required this.emptyTitle,
    required this.emptyMessage,
    this.emptyAction,
  });

  final List<ArtistSummary> artists;
  final ValueChanged<ArtistSummary> onTap;
  final String emptyTitle;
  final String emptyMessage;
  final Widget? emptyAction;

  @override
  Widget build(BuildContext context) {
    if (artists.isEmpty) {
      return SongListEmpty(
        title: emptyTitle,
        message: emptyMessage,
        action: emptyAction,
      );
    }
    return Column(
      children: [
        for (final artist in artists)
          ListTile(
            onTap: () => onTap(artist),
            leading: CircleAvatar(
              backgroundColor: Theme.of(
                context,
              ).colorScheme.secondaryContainer,
              child: Text(
                artist.name.isEmpty ? '?' : artist.name[0].toUpperCase(),
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSecondaryContainer,
                ),
              ),
            ),
            title: Text(
              artist.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              '${artist.songCount} ${artist.songCount == 1 ? 'song' : 'songs'}',
            ),
            trailing: const Icon(Icons.chevron_right),
          ),
      ],
    );
  }
}
