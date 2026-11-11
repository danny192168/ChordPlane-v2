import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/song_tile.dart';
import '../data/song_providers.dart';

class ArtistsScreen extends ConsumerWidget {
  const ArtistsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artists = ref.watch(artistsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Artists')),
      body: artists.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('$error')),
        data: (items) {
          if (items.isEmpty) {
            return const SongListEmpty(
              title: 'No artists yet',
              message:
                  'Add an artist name to a song and they will appear here.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.only(top: 4, bottom: 32),
            itemCount: items.length,
            separatorBuilder: (_, _) => Divider(
              height: 1,
              indent: 76,
              endIndent: 16,
              color: Theme.of(
                context,
              ).colorScheme.outlineVariant.withValues(alpha: 0.3),
            ),
            itemBuilder: (context, index) {
              final artist = items[index];
              return ListTile(
                onTap: () => context.push('/artist/${artist.slug}'),
                leading: CircleAvatar(
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.secondaryContainer,
                  child: Text(
                    artist.name.isEmpty
                        ? '?'
                        : artist.name[0].toUpperCase(),
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
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  '${artist.songCount} ${artist.songCount == 1 ? 'song' : 'songs'}',
                ),
                trailing: const Icon(Icons.chevron_right),
              );
            },
          );
        },
      ),
    );
  }
}
