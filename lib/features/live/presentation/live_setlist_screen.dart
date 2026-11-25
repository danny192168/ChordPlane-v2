import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/theme/app_theme.dart';
import '../../sharing/cpl.dart';
import '../../songs/data/song_providers.dart';
import '../data/live_providers.dart';
import '../data/live_setlist_api.dart';

/// Live, collaborative view of a shared setlist. The token in the URL is the
/// link secret; the server decides what the current viewer may change.
class LiveSetlistScreen extends ConsumerWidget {
  const LiveSetlistScreen({super.key, required this.token});

  final String token;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final setlistAsync = ref.watch(liveSetlistProvider(token));
    final itemsAsync = ref.watch(liveItemsProvider(token));

    return setlistAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, stack) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('Could not open setlist: $error')),
      ),
      data: (setlist) {
        if (setlist == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Live setlist')),
            body: const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'This live link is not available. Check that the host has '
                  'not revoked it.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }
        return _build(context, ref, setlist, itemsAsync);
      },
    );
  }

  Widget _build(
    BuildContext context,
    WidgetRef ref,
    LiveSetlist setlist,
    AsyncValue<List<LiveSetlistItem>> itemsAsync,
  ) {
    final theme = Theme.of(context);
    final colors = ChordPlaneColors.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _LiveBadge(),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                setlist.title.isEmpty ? 'Live setlist' : setlist.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Share live link',
            onPressed: () => _showShareSheet(context, setlist),
            icon: const Icon(Icons.ios_share),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            color: theme.colorScheme.surfaceContainerLow,
            child: Row(
              children: [
                Icon(Icons.lock_outline, size: 15, color: colors.sectionLabel),
                const SizedBox(width: 6),
                Text(
                  setlist.permissionLabel,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: colors.sectionLabel,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '· ${setlist.audience == 'anyone' ? 'Anyone with link' : 'Signed in only'}',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                if (setlist.isOwner)
                  TextButton(
                    onPressed: () => _showHostControls(context, ref, setlist),
                    child: const Text('Link settings'),
                  ),
              ],
            ),
          ),
          Expanded(
            child: itemsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Could not load songs: $error',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.queue_music_outlined,
                            size: 42,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            setlist.canEdit
                                ? 'No songs in this set yet'
                                : 'Waiting for the host to add songs',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: 100),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => Divider(
                    height: 1,
                    indent: 70,
                    endIndent: 16,
                    color: theme.colorScheme.outlineVariant,
                  ),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: theme.colorScheme.secondaryContainer,
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: theme.colorScheme.onSecondaryContainer,
                          ),
                        ),
                      ),
                      title: Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        [
                          if (item.artist.isNotEmpty) item.artist,
                          if (item.originalKey.isNotEmpty)
                            'Key ${item.originalKey}',
                          if (item.capo > 0) 'Capo ${item.capo}',
                          if (item.note.isNotEmpty) item.note,
                        ].join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: setlist.canComment
                          ? PopupMenuButton<String>(
                              tooltip: 'Song options',
                              onSelected: (value) {
                                if (value == 'edit') {
                                  _showItemSheet(context, ref, setlist, item);
                                } else if (value == 'delete' &&
                                    setlist.canEdit) {
                                  _deleteItem(context, ref, item);
                                }
                              },
                              itemBuilder: (context) => [
                                PopupMenuItem(
                                  value: 'edit',
                                  child: ListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    leading: const Icon(Icons.edit_outlined),
                                    title: Text(
                                      setlist.canEdit
                                          ? 'Edit song'
                                          : 'Add comment',
                                    ),
                                  ),
                                ),
                                if (setlist.canEdit)
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: ListTile(
                                      dense: true,
                                      contentPadding: EdgeInsets.zero,
                                      leading: Icon(Icons.delete_outline),
                                      title: Text('Remove from set'),
                                    ),
                                  ),
                              ],
                            )
                          : null,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: setlist.canEdit
          ? FloatingActionButton.extended(
              heroTag: 'live-fab',
              onPressed: () => _showAddSongSheet(context, ref, token),
              icon: const Icon(Icons.add),
              label: const Text('Add song'),
            )
          : null,
    );
  }

  void _showShareSheet(BuildContext context, LiveSetlist setlist) {
    final theme = Theme.of(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const _LiveBadge(),
                const SizedBox(width: 8),
                Text(
                  'Share live link',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Anyone you send this to can follow edits in real time. Their '
              'permissions come from the host settings.',
              style: TextStyle(
                fontSize: 12.5,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: QrImageView(
                  data: setlist.link,
                  version: QrVersions.auto,
                  size: 200,
                  gapless: true,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Color(0xFF14121A),
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Color(0xFF14121A),
                  ),
                  semanticsLabel: 'QR code for the live setlist',
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: setlist.link),
                      );
                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Live link copied')),
                        );
                      }
                    },
                    icon: const Icon(Icons.link, size: 18),
                    label: const Text('Copy link'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      SharePlus.instance.share(
                        ShareParams(
                          text: setlist.link,
                          subject: setlist.title.isEmpty
                              ? 'Live ChordPlane setlist'
                              : setlist.title,
                        ),
                      );
                    },
                    icon: const Icon(Icons.send_outlined, size: 18),
                    label: const Text('Send link'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showHostControls(
    BuildContext context,
    WidgetRef ref,
    LiveSetlist setlist,
  ) {
    var permission = setlist.permission == 'owner' ? 'edit' : setlist.permission;
    var audience = setlist.audience;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) => Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              0,
              20,
              20 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Link permissions',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Applies to everyone who opens this link.',
                  style: TextStyle(fontSize: 12.5),
                ),
                const SizedBox(height: 16),
                const Text('What guests can do', style: TextStyle(fontSize: 12)),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'view',
                      icon: Icon(Icons.visibility_outlined),
                      label: Text('View'),
                    ),
                    ButtonSegment(
                      value: 'comment',
                      icon: Icon(Icons.comment_outlined),
                      label: Text('Comment'),
                    ),
                    ButtonSegment(
                      value: 'edit',
                      icon: Icon(Icons.edit_outlined),
                      label: Text('Edit'),
                    ),
                  ],
                  selected: {permission},
                  onSelectionChanged: (value) =>
                      setState(() => permission = value.first),
                ),
                const SizedBox(height: 16),
                const Text('Who can open it', style: TextStyle(fontSize: 12)),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'anyone',
                      icon: Icon(Icons.link),
                      label: Text('Anyone with link'),
                    ),
                    ButtonSegment(
                      value: 'signed_in',
                      icon: Icon(Icons.person_outline),
                      label: Text('Signed in only'),
                    ),
                  ],
                  selected: {audience},
                  onSelectionChanged: (value) =>
                      setState(() => audience = value.first),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () async {
                      try {
                        await ref.read(liveApiProvider).setAccess(
                          token,
                          permission: permission,
                          audience: audience,
                        );
                        if (context.mounted) Navigator.pop(context);
                        ref.invalidate(liveSetlistProvider(token));
                      } on LiveException catch (error) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(error.message)),
                          );
                        }
                      }
                    },
                    child: const Text('Save permissions'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showAddSongSheet(
    BuildContext context,
    WidgetRef ref,
    String token,
  ) {
    var query = '';
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) {
        final library = ref.watch(libraryProvider);
        return StatefulBuilder(
          builder: (context, setState) => SizedBox(
            height: MediaQuery.of(context).size.height * 0.75,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                  child: TextField(
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Search your library',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (value) => setState(() => query = value),
                  ),
                ),
                Expanded(
                  child: library.when(
                  loading: () => const Center(
                    child: CircularProgressIndicator(),
                  ),
                  error: (error, stack) =>
                      Center(child: Text('Could not load library: $error')),
                  data: (songs) {
                    final term = query.trim().toLowerCase();
                    final matches = songs.where((item) {
                      if (term.isEmpty) return true;
                      return item.song.title.toLowerCase().contains(term) ||
                          item.song.artist.toLowerCase().contains(term);
                    }).toList();
                    if (matches.isEmpty) {
                      return const Center(
                        child: Text('No songs match that search.'),
                      );
                    }
                    return ListView.builder(
                      itemCount: matches.length,
                      itemBuilder: (context, index) {
                        final song = matches[index].song;
                        return ListTile(
                          title: Text(song.title),
                          subtitle: Text(
                            song.artist.isEmpty ? 'Unknown artist' : song.artist,
                          ),
                          onTap: () async {
                            try {
                              await ref
                                  .read(liveApiProvider)
                                  .addItem(token, CplSong.fromLocal(song));
                              if (context.mounted) Navigator.pop(context);
                            } on LiveException catch (error) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(error.message)),
                                );
                              }
                            }
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
  }

  void _showItemSheet(
    BuildContext context,
    WidgetRef ref,
    LiveSetlist setlist,
    LiveSetlistItem item,
  ) {
    final title = TextEditingController(text: item.title);
    final artist = TextEditingController(text: item.artist);
    final key = TextEditingController(text: item.originalKey);
    final capo = TextEditingController(text: '${item.capo}');
    final body = TextEditingController(text: item.body);
    final note = TextEditingController(text: item.note);
    final editable = setlist.canEdit;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              editable ? 'Edit song' : 'Add a comment',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: title,
              enabled: editable,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: artist,
              enabled: editable,
              decoration: const InputDecoration(labelText: 'Artist'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: key,
                    enabled: editable,
                    decoration: const InputDecoration(labelText: 'Key'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: capo,
                    enabled: editable,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Capo'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: body,
              enabled: editable,
              minLines: 5,
              maxLines: 10,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              decoration: const InputDecoration(
                labelText: 'Chords & lyrics',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: note,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Note',
                hintText: 'Comment for the rest of the band',
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () async {
                  final parsedCapo = int.tryParse(capo.text.trim()) ?? 0;
                  try {
                    await ref.read(liveApiProvider).updateItem(
                      item,
                      note: note.text,
                      body: editable ? body.text : null,
                      originalKey: editable ? key.text : null,
                      title: editable ? title.text : null,
                      artist: editable ? artist.text : null,
                      capo: editable ? parsedCapo.clamp(0, 12) : null,
                    );
                    if (context.mounted) Navigator.pop(context);
                  } on LiveException catch (error) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(error.message)),
                      );
                    }
                  }
                },
                child: Text(editable ? 'Save changes' : 'Add comment'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteItem(
    BuildContext context,
    WidgetRef ref,
    LiveSetlistItem item,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove song?'),
        content: Text('"${item.title}" will be removed from this live set.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(liveApiProvider).deleteItem(item.id);
    } on LiveException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
      }
    }
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) {
    final colors = ChordPlaneColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: colors.chord.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: colors.chord,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            'LIVE',
            style: TextStyle(
              fontSize: 9.5,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w900,
              color: colors.chord,
            ),
          ),
        ],
      ),
    );
  }
}
