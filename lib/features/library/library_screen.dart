import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../shared/widgets/profile_avatar_button.dart';
import '../../shared/widgets/song_tile.dart';
import '../community/data/community_api.dart';
import 'widgets/published_song_card.dart';
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
        body: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 110),
            children: [
              if (bootstrap.isLoading)
                const Padding(
                  padding: EdgeInsets.only(top: 100),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (query.isEmpty)
                _buildPublished(context, published)
              else
                _buildSearch(context, view),
            ],
          ),
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

  /// Pull-to-refresh reloads the small slice of the shared catalog shown on
  /// the Library home. The saved shelf lives in its own tab.
  Future<void> _refresh() async {
    ref.invalidate(recentPublishedProvider);
    await ref.read(recentPublishedProvider.future);
  }

  Future<void> _openPublished(
    BuildContext context,
    CommunitySong song,
  ) async {
    final id = await ref
        .read(songRepositoryProvider)
        .cacheCommunitySong(song);
    if (id == null || !context.mounted) return;
    context.push('/song/$id');
  }

  Widget _buildPublished(
    BuildContext context,
    AsyncValue<List<CommunitySong>> published,
  ) {
    final songs = published.value?.take(5).toList();
    if (songs == null || songs.isEmpty) {
      return SongListEmpty(
        title: 'Nothing published yet',
        message: 'Songs shared by the community will appear here.',
        action: FilledButton.icon(
          onPressed: () => context.push('/editor'),
          icon: const Icon(Icons.add),
          label: const Text('New song'),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: _sectionTitle('Recently published')),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: TextButton(
                onPressed: () => context.push('/published'),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('See all'),
                    SizedBox(width: 2),
                    Icon(Icons.chevron_right, size: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
        for (final song in songs)
          PublishedSongCard(
            song: song,
            onTap: () => _openPublished(context, song),
          ),
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

