import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../shared/widgets/profile_avatar_button.dart';
import '../../shared/widgets/song_tile.dart';
import '../community/data/community_api.dart';
import '../songs/data/song_providers.dart';
import '../songs/data/song_repository.dart';

/// Discovery lives here: local results appear immediately, online results
/// merge in quietly when the device is connected. Saved/Favorites/Setlists are
/// bottom tabs, so this screen only carries the search field.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  late final TextEditingController _search;

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(text: ref.read(searchQueryProvider));
    _search.addListener(() {
      ref.read(searchQueryProvider.notifier).set(_search.text);
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bootstrap = ref.watch(appBootstrapProvider);
    final query = ref.watch(searchQueryProvider).trim();
    final view = ref.watch(searchViewProvider);
    final recent = ref.watch(savedSongsProvider);
    final published = ref.watch(recentPublishedProvider);

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            pinned: true,
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SvgPicture.asset(
                    'assets/logo.svg',
                    width: 30,
                    height: 30,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'ChordPlane',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            actions: const [
              Padding(
                padding: EdgeInsets.only(right: 12),
                child: ProfileAvatarButton(size: 30),
              ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(72),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                child: TextField(
                  controller: _search,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search songs and artists',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              _search.clear();
                              ref.read(searchQueryProvider.notifier).clear();
                            },
                          ),
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
            ),
          ),
        ],
        body: ListView(
          padding: const EdgeInsets.only(bottom: 110),
          children: [
            if (bootstrap.isLoading)
              const Padding(
                padding: EdgeInsets.only(top: 100),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (query.isEmpty)
              _buildRecent(context, recent, published)
            else
              _buildSearch(context, view),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'library-fab',
        onPressed: () => context.push('/editor'),
        icon: const Icon(Icons.add),
        label: const Text('New song'),
      ),
    );
  }

  Widget _buildRecent(
    BuildContext context,
    AsyncValue<List<SongListItem>> recent,
    AsyncValue<List<CommunitySong>> published,
  ) {
    return recent.when(
      loading: () => const Padding(
        padding: EdgeInsets.only(top: 100),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, stack) => SongListEmpty(
        title: 'Could not load your library',
        message: '$error',
      ),
      data: (items) {
        final shown = items.take(12).toList();
        final known = <String>{
          for (final item in items) if (item.song.remoteId != null)
            item.song.remoteId!,
        };
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sectionTitle('Recently saved'),
            if (shown.isEmpty)
              SongListEmpty(
                title: 'Your songbook is empty',
                message:
                    'Write a song with chords and lyrics, or search above to '
                    'find something to save.',
                action: FilledButton.icon(
                  onPressed: () => context.push('/editor'),
                  icon: const Icon(Icons.add),
                  label: const Text('New song'),
                ),
              )
            else ...[
              for (final item in shown)
                SongTile(
                  item: item,
                  onTap: () => context.push('/song/${item.song.id}'),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: OutlinedButton.icon(
                  onPressed: () => context.go('/saved'),
                  icon: const Icon(Icons.bookmark_outline),
                  label: const Text('See all saved songs'),
                ),
              ),
            ],
            _buildPublished(context, published, known),
          ],
        );
      },
    );
  }

  Widget _buildPublished(
    BuildContext context,
    AsyncValue<List<CommunitySong>> published,
    Set<String> known,
  ) {
    final songs = published.value
        ?.where((song) => !known.contains(song.id))
        .take(5)
        .toList();
    if (songs == null || songs.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle('Recently published'),
        for (final song in songs)
          _SearchSongTile(result: SearchSongResult.online(song)),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildSearch(BuildContext context, SearchView view) {
    if (view.isEmpty) {
      if (view.onlineLoading) {
        return const Padding(
          padding: EdgeInsets.only(top: 100),
          child: Center(child: CircularProgressIndicator()),
        );
      }
      return const SongListEmpty(
        title: 'No matches',
        message: 'Try a different song or artist name.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (view.songs.isNotEmpty) ...[
          _sectionTitle('Songs'),
          for (final result in view.songs) _SearchSongTile(result: result),
        ],
        if (view.artists.isNotEmpty) ...[
          _sectionTitle('Artists'),
          for (final artist in view.artists)
            _SearchArtistTile(artist: artist),
        ],
        if (view.onlineLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
      ],
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _SearchSongTile extends ConsumerWidget {
  const _SearchSongTile({required this.result});

  final SearchSongResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final local = result.local;
    if (local != null) {
      return SongTile(
        item: local,
        onTap: () => context.push('/song/${local.song.id}'),
      );
    }

    final online = result.online!;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      leading: _SongGlyph(title: online.title),
      title: Text(
        online.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15.5),
      ),
      subtitle: Text(
        [
          online.artist.trim().isEmpty ? 'Unknown artist' : online.artist,
          online.originalKey,
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () async {
        final id = await ref
            .read(songRepositoryProvider)
            .cacheCommunitySong(online);
        if (id == null || !context.mounted) return;
        context.push('/song/$id');
      },
    );
  }
}

class _SearchArtistTile extends StatelessWidget {
  const _SearchArtistTile({required this.artist});

  final SearchArtistResult artist;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: () {
        final path = artist.online
            ? '/online-artist/${Uri.encodeComponent(artist.name)}'
            : '/artist/${Uri.encodeComponent(artist.slug)}';
        context.push(path);
      },
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
        child: Text(
          artist.name.isEmpty ? '?' : artist.name[0].toUpperCase(),
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: Theme.of(context).colorScheme.onSecondaryContainer,
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
    );
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
