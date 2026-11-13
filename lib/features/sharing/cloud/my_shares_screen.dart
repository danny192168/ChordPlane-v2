import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_gateway.dart';
import '../../../core/config/app_config.dart';
import '../../../core/db/app_database.dart';
import '../../songs/data/song_repository.dart';
import '../cpl.dart';
import '../share_service.dart';
import 'auth_gate_sheet.dart';
import 'server_share_service.dart';
import 'share_cloud.dart';

/// Compile-time gate (Supabase configured and initialized) exposed as a
/// provider so tests can override it without dart-defines.
final cloudSharingEnabledProvider = Provider<bool>((ref) {
  return AppConfig.hasSupabase && AppConfig.supabaseInitError == null;
});

/// The signed-in user's server shares, newest first.
final mySharesProvider = FutureProvider.autoDispose<List<ShareRecord>>((ref) {
  return ref.watch(serverShareServiceProvider).myShares();
});

/// Share uploads still queued in the outbox, waiting for connectivity.
final pendingShareUploadsProvider = FutureProvider.autoDispose<int>((ref) {
  return ref.watch(shareOutboxProvider).pendingCount();
});

/// Token → local song/setlist row, so "Update shared copy" knows what to
/// rebuild. Shares created before this mapping existed have no row. Read
/// once per screen visit; invalidated after update/revoke actions.
final sharedLinkRowsProvider =
    FutureProvider.autoDispose<Map<String, SharedLinkRow>>((ref) async {
      final db = ref.watch(databaseProvider);
      final rows = await db.select(db.sharedLinks).get();
      return {for (final row in rows) row.token: row};
    });

/// Manage everything this account has ever pushed to the server: view
/// counts, "Update shared copy", and revoke/restore. Creating a share still
/// happens from the share sheet.
class MySharesScreen extends ConsumerWidget {
  const MySharesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(cloudSharingEnabledProvider)) {
      return const _Scaffold(
        child: _CenterMessage(
          icon: Icons.cloud_off_outlined,
          title: 'Cloud sharing is not enabled',
          message: 'This build has no Supabase configuration, so there are '
              'no server links to manage.',
        ),
      );
    }

    final signedIn = ref.watch(signedInProvider).value ?? false;
    if (!signedIn) {
      return _Scaffold(
        child: _CenterMessage(
          icon: Icons.lock_outline,
          title: 'Sign in to see your links',
          message: 'Your cloud links belong to your account. Sign in to view '
              'and manage them.',
          action: FilledButton.icon(
            onPressed: () => showSignInGate(context),
            icon: const Icon(Icons.person_outline),
            label: const Text('Sign in'),
          ),
        ),
      );
    }

    final shares = ref.watch(mySharesProvider);
    return _Scaffold(
      child: shares.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _CenterMessage(
          icon: Icons.cloud_off_outlined,
          title: 'Could not load your links',
          message:
              error is ShareCloudException ? error.message : error.toString(),
          action: OutlinedButton.icon(
            onPressed: () => ref.invalidate(mySharesProvider),
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ),
        data: (records) {
          if (records.isEmpty) {
            return const _CenterMessage(
              icon: Icons.link_off_outlined,
              title: 'No shared links yet',
              message: 'Open a song or setlist, tap Share, and create a '
                  'cloud link. Everything you make shows up here.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.refresh(mySharesProvider.future),
            child: ListView.separated(
              itemCount: records.length + 1,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                if (index == records.length) {
                  return const _PendingUploadsBanner();
                }
                return _ShareTile(record: records[index]);
              },
            ),
          );
        },
      ),
    );
  }
}

class _Scaffold extends StatelessWidget {
  const _Scaffold({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My shared links')),
      body: child,
    );
  }
}

class _ShareTile extends ConsumerWidget {
  const _ShareTile({required this.record});

  final ShareRecord record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isSetlist = record.kind == CplKind.setlist.name;
    final mappings = ref.watch(sharedLinkRowsProvider).value;    final hasLocalMapping = mappings?.containsKey(record.token) ?? false;

    return ListTile(
      leading: Icon(
        isSetlist ? Icons.queue_music : Icons.music_note,
        color: theme.colorScheme.primary,
      ),
      title: Text(
        record.title.isEmpty ? record.token : record.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: _Subtitle(record: record),
      trailing: PopupMenuButton<String>(
        tooltip: 'Link actions',
        onSelected: (value) => _onAction(context, ref, value),
        itemBuilder: (context) => [
          const PopupMenuItem(
            value: 'copy',
            child: Text('Copy link'),
          ),
          PopupMenuItem(
            value: 'update',
            enabled: hasLocalMapping,
            child: const Text('Update shared copy'),
          ),
          PopupMenuItem(
            value: record.revoked ? 'restore' : 'revoke',
            child: Text(record.revoked ? 'Restore link' : 'Revoke link'),
          ),
        ],
      ),
      onTap: () => _copyLink(context),
    );
  }

  Future<void> _onAction(
    BuildContext context,
    WidgetRef ref,
    String action,
  ) async {
    switch (action) {
      case 'copy':
        await _copyLink(context);
      case 'update':
        await _updateCopy(context, ref);
      case 'revoke':
        await _setRevoked(context, ref, revoked: true);
      case 'restore':
        await _setRevoked(context, ref, revoked: false);
    }
  }

  Future<void> _copyLink(BuildContext context) async {
    await Clipboard.setData(
      ClipboardData(text: CplFormat.serverLink(record.token)),
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Link copied')),
      );
    }
  }

  Future<void> _updateCopy(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Update shared copy?'),
        content: Text(
          'The link will show your current version of '
          '"${record.title.isEmpty ? 'this share' : record.title}". '
          'Copies already imported by others stay as they are.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Update'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final service = ref.read(serverShareServiceProvider);
    final bundle = await service.bundleForUpdate(
      record.token,
      ref.read(shareServiceProvider),
    );
    if (bundle == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
            'This link is not connected to a song or setlist anymore. '
            'Share it again to update it.',
          ),
        ));
      }
      return;
    }
    try {
      final result = await service.update(record.token, bundle);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          result.upload == ShareUpload.queued
              ? 'Saved offline — the copy updates when you are back online.'
              : 'Shared copy updated',
        ),
      ));
    } on ShareCloudException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } finally {
      ref.invalidate(mySharesProvider);
      ref.invalidate(pendingShareUploadsProvider);
    }
  }

  Future<void> _setRevoked(
    BuildContext context,
    WidgetRef ref, {
    required bool revoked,
  }) async {
    try {
      await ref
          .read(serverShareServiceProvider)
          .setRevoked(record.token, revoked: revoked);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(revoked ? 'Link revoked' : 'Link restored'),
      ));
    } on ShareCloudException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } finally {
      ref.invalidate(mySharesProvider);
    }
  }
}

class _Subtitle extends StatelessWidget {
  const _Subtitle({required this.record});

  final ShareRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = TextStyle(
      fontSize: 12.5,
      color: theme.colorScheme.onSurfaceVariant,
    );
    final chips = <String>[
      record.kind == CplKind.setlist.name ? 'Setlist' : 'Song',
      '${record.viewCount} ${record.viewCount == 1 ? 'view' : 'views'}',
      if (record.updatedAt != null) _relativeDate(record.updatedAt!),
    ];

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(chips.join(' · '), style: style),
        if (record.revoked) const _StatusChip(label: 'Revoked', error: true),
        if (record.status == 'under_review')
          const _StatusChip(label: 'Under review', error: true)
        else if (record.status == 'removed')
          const _StatusChip(label: 'Removed', error: true),
      ],
    );
  }
}

String _relativeDate(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inDays >= 365) {
    final years = (diff.inDays / 365).floor();
    return 'updated ${years == 1 ? 'a year' : '$years years'} ago';
  }
  if (diff.inDays >= 30) {
    final months = (diff.inDays / 30).floor();
    return 'updated ${months == 1 ? 'a month' : '$months months'} ago';
  }
  if (diff.inDays >= 1) {
    return 'updated ${diff.inDays == 1 ? 'yesterday' : '${diff.inDays} days ago'}';
  }
  if (diff.inHours >= 1) {
    return 'updated ${diff.inHours == 1 ? 'an hour' : '${diff.inHours} hours'} ago';
  }
  return 'updated just now';
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, this.error = false});

  final String label;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: error ? scheme.errorContainer : scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: error ? scheme.onErrorContainer : scheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

class _PendingUploadsBanner extends ConsumerWidget {
  const _PendingUploadsBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingShareUploadsProvider).value ?? 0;
    if (pending == 0) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: [
          Icon(
            Icons.schedule,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$pending share ${pending == 1 ? 'upload' : 'uploads'} waiting '
              'to go online',
              style: TextStyle(
                fontSize: 12.5,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              final uploaded = await ref.read(shareOutboxProvider).flush();
              if (context.mounted && uploaded > 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Uploaded $uploaded share(s)')),
                );
              }
              ref.invalidate(mySharesProvider);
              ref.invalidate(pendingShareUploadsProvider);
            },
            child: const Text('Retry now'),
          ),
        ],
      ),
    );
  }
}

class _CenterMessage extends StatelessWidget {
  const _CenterMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 14),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              message,
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[const SizedBox(height: 18), action!],
          ],
        ),
      ),
    );
  }
}
