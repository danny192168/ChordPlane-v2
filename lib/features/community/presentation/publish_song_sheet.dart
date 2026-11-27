import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/auth/auth_gateway.dart';
import '../../../core/db/app_database.dart';
import '../../sharing/cpl.dart';
import '../../sharing/cloud/auth_gate_sheet.dart';
import '../../songs/data/song_providers.dart';
import '../../songs/data/song_repository.dart';
import '../data/community_api.dart';
import '../data/community_providers.dart';
import '../data/published_feed.dart';
import 'username_sheet.dart';

/// Explicit publish step. Creating or editing a song never publishes it by
/// accident: this sheet shows exactly what becomes public first.
Future<bool> showPublishSongSheet(
  BuildContext context, {
  required WidgetRef ref,
  required SongRow song,
  String? remoteId,
}) async {
  // Read the gateway directly: the signed-in stream can still be loading on
  // the first frame even when Supabase already has a session.
  if (!ref.read(authGatewayProvider).isSignedIn) {
    await showSignInGate(context);
    return false;
  }
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => _PublishSheet(song: song, remoteId: remoteId),
  );
  return result ?? false;
}

class _PublishSheet extends ConsumerStatefulWidget {
  const _PublishSheet({required this.song, this.remoteId});

  final SongRow song;
  final String? remoteId;

  @override
  ConsumerState<_PublishSheet> createState() => _PublishSheetState();
}

class _PublishSheetState extends ConsumerState<_PublishSheet> {
  bool _anonymous = false;
  bool _busy = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = ChordPlaneColors.of(context);
    final updating = widget.remoteId != null;

    return Padding(
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
            updating ? 'Update online version' : 'Publish to Public Library',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            updating
                ? 'Push your local edits to the public copy.'
                : 'Anyone will be able to find and open this song. It stays '
                    'editable on this device.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.song.title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                if (widget.song.artist.trim().isNotEmpty)
                  Text(
                    widget.song.artist,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  widget.song.body.isEmpty
                      ? 'No chords or lyrics yet.'
                      : widget.song.body.length > 220
                      ? '${widget.song.body.substring(0, 220)}…'
                      : widget.song.body,
                  maxLines: 5,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _anonymous,
            onChanged: _busy ? null : (value) => setState(() => _anonymous = value),
            title: const Text('Upload anonymously'),
            subtitle: const Text(
              'Your account still owns the song, but the credit says Anonymous.',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 4),
            Text(
              _error!,
              style: TextStyle(fontSize: 12.5, color: theme.colorScheme.error),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _busy ? null : _publish,
              icon: Icon(
                updating ? Icons.cloud_upload_outlined : Icons.public,
                size: 18,
              ),
              label: _busy
                  ? const Text('Publishing…')
                  : Text(
                      updating ? 'Update online version' : 'Publish now',
                    ),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              'You can remove the public copy later from this menu.',
              style: TextStyle(
                fontSize: 11,
                color: colors.sectionLabel,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _publish() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = ref.read(communityApiProvider);
      final username = await api.currentUsername();
      if (username == null || username.trim().isEmpty) {
        if (!mounted) return;
        final picked = await showUsernameSheet(context);
        if (!picked || !mounted) return;
      }
      final cpl = CplSong.fromLocal(widget.song);
      if (widget.remoteId == null) {
        final published = await api.publish(cpl, anonymous: _anonymous);
        await ref.read(songRepositoryProvider).markPublished(
          widget.song.id,
          remoteId: published.id,
          anonymous: _anonymous,
        );
      } else {
        await api.updatePublished(
          widget.remoteId!,
          cpl,
          anonymous: _anonymous,
        );
        await ref.read(songRepositoryProvider).markPublished(
          widget.song.id,
          remoteId: widget.remoteId!,
          anonymous: _anonymous,
        );
      }
      ref.invalidate(myUploadsProvider);
      ref.invalidate(myPublishedCountProvider);
      ref.invalidate(publishedFeedProvider);
      ref.invalidate(recentPublishedProvider);
      if (!mounted) return;
      Navigator.pop(context, true);
    } on CommunityException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not publish: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
