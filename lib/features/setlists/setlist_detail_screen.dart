import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/db/app_database.dart';
import '../../shared/widgets/song_tile.dart';
import '../sharing/share_service.dart';
import '../sharing/share_sheet.dart';
import '../songs/data/song_providers.dart';
import 'data/setlist_repository.dart';

class SetlistDetailScreen extends ConsumerWidget {
  const SetlistDetailScreen({super.key, required this.setlistId});

  final String setlistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final setlistAsync = ref.watch(setlistProvider(setlistId));
    final entriesAsync = ref.watch(setlistEntriesProvider(setlistId));
    final theme = Theme.of(context);

    return setlistAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, stack) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('$error')),
      ),
      data: (setlist) {
        if (setlist == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('This setlist no longer exists.')),
          );
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(setlist.title),
            actions: [
              IconButton(
                tooltip: 'Add songs',
                onPressed: () => _openAddSongs(context),
                icon: const Icon(Icons.playlist_add),
              ),
              PopupMenuButton<String>(
                onSelected: (value) => _onMenu(context, ref, value, setlist),
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'share',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.ios_share),
                      title: Text('Share setlist'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'rename',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.edit_outlined),
                      title: Text('Rename'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'copy',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.copy_all_outlined),
                      title: Text('Copy song list'),
                    ),
                  ),
                  PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.delete_outline),
                      title: Text('Delete setlist'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                child: Row(
                  children: [
                    Icon(
                      Icons.offline_bolt_outlined,
                      size: 15,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Stored on this device',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    if (entriesAsync.hasValue)
                      Text(
                        '${entriesAsync.requireValue.length} '
                        '${entriesAsync.requireValue.length == 1 ? 'song' : 'songs'}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: entriesAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, stack) => Center(child: Text('$error')),
                  data: (entries) {
                    if (entries.isEmpty) {
                      return SongListEmpty(
                        title: 'This setlist is empty',
                        message:
                            'Add songs from your library, then drag to put them in show order.',
                        action: FilledButton.icon(
                          onPressed: () => _openAddSongs(context),
                          icon: const Icon(Icons.playlist_add),
                          label: const Text('Add songs'),
                        ),
                      );
                    }
                    return ReorderableListView.builder(
                      buildDefaultDragHandles: false,
                      padding: const EdgeInsets.only(bottom: 90),
                      itemCount: entries.length,
                      onReorderItem: (oldIndex, newIndex) => ref
                          .read(setlistRepositoryProvider)
                          .reorder(setlistId, oldIndex, newIndex),
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        return ListTile(
                          key: ValueKey(entry.item.id),
                          onTap: () =>
                              context.push('/song/${entry.song.id}'),
                          contentPadding: const EdgeInsets.fromLTRB(
                            16,
                            2,
                            6,
                            2,
                          ),
                          leading: Container(
                            width: 32,
                            height: 32,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Text(
                              '${index + 1}',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 12.5,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          title: Text(
                            entry.song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            [
                              if (entry.song.artist.trim().isNotEmpty)
                                entry.song.artist,
                              if (entry.song.originalKey.isNotEmpty)
                                'Key ${entry.song.originalKey}',
                              if (entry.song.capo > 0)
                                'Capo ${entry.song.capo}',
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Remove',
                                onPressed: () => ref
                                    .read(setlistRepositoryProvider)
                                    .removeEntry(entry.item.id, setlistId),
                                icon: const Icon(
                                  Icons.remove_circle_outline,
                                  size: 20,
                                ),
                              ),
                              ReorderableDragStartListener(
                                index: index,
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 10,
                                  ),
                                  child: Icon(Icons.drag_handle, size: 20),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openAddSongs(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => _AddSongsSheet(setlistId: setlistId),
    );
  }

  Future<void> _onMenu(
    BuildContext context,
    WidgetRef ref,
    String value,
    SetlistRow setlist,
  ) async {
    switch (value) {
      case 'share':
        final bundle = await ref
            .read(shareServiceProvider)
            .bundleForSetlist(setlist.id);
        if (!context.mounted) return;
        await showShareSheet(context, bundle: bundle);
        return;
      case 'rename':
        final controller = TextEditingController(text: setlist.title);
        final title = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Rename setlist'),
            content: TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              onSubmitted: (value) => Navigator.pop(context, value),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, controller.text),
                child: const Text('Save'),
              ),
            ],
          ),
        );
        if (title != null) {
          await ref
              .read(setlistRepositoryProvider)
              .rename(setlist.id, title);
        }
        return;
      case 'copy':
        final entries =
            ref.read(setlistEntriesProvider(setlist.id)).value ?? [];
        final text = [
          setlist.title,
          '',
          for (var i = 0; i < entries.length; i++)
            '${i + 1}. ${entries[i].song.title}'
                '${entries[i].song.artist.trim().isEmpty ? '' : ' — ${entries[i].song.artist}'}',
        ].join('\n');
        await Clipboard.setData(ClipboardData(text: text));
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Song list copied')),
        );
        return;
      case 'delete':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete setlist?'),
            content: Text('"${setlist.title}" will be removed.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
        await ref.read(setlistRepositoryProvider).delete(setlist.id);
        if (context.mounted) context.go('/setlists');
        return;
    }
  }
}

class _AddSongsSheet extends ConsumerStatefulWidget {
  const _AddSongsSheet({required this.setlistId});

  final String setlistId;

  @override
  ConsumerState<_AddSongsSheet> createState() => _AddSongsSheetState();
}

class _AddSongsSheetState extends ConsumerState<_AddSongsSheet> {
  final Set<String> _selected = <String>{};

  @override
  Widget build(BuildContext context) {
    final songs = ref.watch(libraryProvider);
    final theme = Theme.of(context);

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.78,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
            child: Row(
              children: [
                Text(
                  'Add songs',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                if (_selected.isNotEmpty)
                  Text(
                    '${_selected.length} selected',
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: songs.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => Center(child: Text('$error')),
              data: (items) {
                if (items.isEmpty) {
                  return const SongListEmpty(
                    title: 'No songs to add',
                    message: 'Create a song first, then come back to this setlist.',
                  );
                }
                return ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final selected = _selected.contains(item.song.id);
                    return CheckboxListTile(
                      value: selected,
                      onChanged: (value) {
                        setState(() {
                          if (value == true) {
                            _selected.add(item.song.id);
                          } else {
                            _selected.remove(item.song.id);
                          }
                        });
                      },
                      title: Text(
                        item.song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        item.song.artist.trim().isEmpty
                            ? 'Unknown artist'
                            : item.song.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      secondary: item.isFavorite
                          ? Icon(
                              Icons.favorite,
                              size: 18,
                              color: theme.colorScheme.error,
                            )
                          : null,
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _selected.isEmpty ? null : _addSelected,
                  icon: const Icon(Icons.playlist_add_check),
                  label: Text(
                    _selected.isEmpty
                        ? 'Select songs to add'
                        : 'Add ${_selected.length} ${_selected.length == 1 ? 'song' : 'songs'}',
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addSelected() async {
    final repository = ref.read(setlistRepositoryProvider);
    for (final songId in _selected) {
      await repository.addSong(widget.setlistId, songId);
    }
    if (!mounted) return;
    Navigator.pop(context);
  }
}
