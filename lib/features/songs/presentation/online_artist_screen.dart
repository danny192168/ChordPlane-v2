import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/song_tile.dart';
import '../data/song_providers.dart';
import '../data/song_repository.dart';

/// Songs by one artist from the shared catalog. Results are cached on the
/// device as soon as this screen loads, so opening any row works offline.
class OnlineArtistScreen extends ConsumerWidget {
  const OnlineArtistScreen({super.key, required this.artist});

  final String artist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songsAsync = ref.watch(onlineArtistSongsProvider(artist));
    final download = ref.watch(artistDownloadControllerProvider(artist));
    final progress = download.value;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              artist.isEmpty ? 'Unknown artist' : artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              _subtitle(progress, songsAsync.value?.length ?? 0, download.hasError),
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Download all songs by $artist',
            onPressed: () => ref
                .read(artistDownloadControllerProvider(artist).notifier)
                .download(),
            icon: const Icon(Icons.download_for_offline_outlined),
          ),
        ],
      ),
      body: songsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => SongListEmpty(
          title: 'Could not load this artist',
          message: '$error',
        ),
        data: (songs) {
          if (songs.isEmpty) {
            return const SongListEmpty(
              title: 'No songs found',
              message: 'This artist has no songs in the shared catalog.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 40),
            itemCount: songs.length,
            separatorBuilder: (_, _) => Divider(
              height: 1,
              indent: 72,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            itemBuilder: (context, index) {
              final song = songs[index];
              return ListTile(
                leading: _SongGlyph(title: song.title),
                title: Text(
                  song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  [
                    song.originalKey,
                    if (song.capo > 0) 'Capo ${song.capo}',
                  ].join(' · '),
                ),
                trailing: progress != null &&
                        progress.total > 0 &&
                        !progress.isComplete
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.chevron_right),
                onTap: () async {
                  final localId = await ref
                      .read(songRepositoryProvider)
                      .cacheCommunitySong(song);
                  if (localId == null || !context.mounted) return;
                  context.push('/song/$localId');
                },
              );
            },
          );
        },
      ),
    );
  }

  String _subtitle(DownloadProgress? progress, int count, bool failed) {
    if (failed) return 'Download failed — tap to retry';
    if (progress != null && progress.total > 0 && !progress.isComplete) {
      return 'Downloading ${progress.done} / ${progress.total}';
    }
    if (progress?.isComplete ?? false) return 'Saved on this device';
    return '$count ${count == 1 ? 'song' : 'songs'} · saved as opened';
  }
}

class _SongGlyph extends StatelessWidget {
  const _SongGlyph({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        title.trim().isEmpty ? '?' : title.trim()[0].toUpperCase(),
        style: TextStyle(
          color: scheme.onPrimaryContainer,
          fontWeight: FontWeight.w800,
          fontSize: 17,
        ),
      ),
    );
  }
}
