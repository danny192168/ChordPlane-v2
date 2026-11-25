import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/auth/auth_gateway.dart';
import '../../../core/config/app_config.dart';
import '../live/data/live_setlist_api.dart';
import 'cpl.dart';
import 'cloud/auth_gate_sheet.dart';
import 'share_service.dart';

/// Sharing has two distinct modes:
///
/// * offline, where the `.cpl` file carries every chord and needs no account;
/// * live, where a link-backed setlist stays editable by everyone who opens it.
///
/// Links and QR codes belong to the live section only — an offline code is not
/// a usable substitute for a live setlist link.
Future<void> showShareSheet(
  BuildContext context, {
  required CplBundle bundle,

  /// Local song/setlist id the bundle came from, when known. Kept for callers
  /// that also manage frozen snapshot links in "My shared links".
  String? localId,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => _ShareSheet(bundle: bundle, localId: localId),
  );
}

class _ShareSheet extends ConsumerStatefulWidget {
  const _ShareSheet({required this.bundle, this.localId});

  final CplBundle bundle;
  final String? localId;

  @override
  ConsumerState<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends ConsumerState<_ShareSheet> {
  bool _busy = false;
  String? _liveToken;
  String _permission = 'edit';
  String _audience = 'anyone';

  CplBundle get bundle => widget.bundle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = ChordPlaneColors.of(context);
    final signedIn =
        ref.watch(signedInProvider).value ??
        ref.read(authGatewayProvider).isSignedIn;

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bundle.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${bundle.songCount} '
                        '${bundle.songCount == 1 ? 'song' : 'songs'} · '
                        '${bundle.kind == CplKind.setlist ? 'Setlist' : 'Song'}',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Icon(
                  bundle.kind == CplKind.setlist
                      ? Icons.queue_music
                      : Icons.music_note,
                  color: colors.chord,
                  size: 28,
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (AppConfig.hasSupabase) ...[
              _buildLiveSection(theme, colors, signedIn),
              const SizedBox(height: 20),
            ],
            Text(
              'OFFLINE',
              style: TextStyle(
                fontSize: 10.5,
                letterSpacing: 1.1,
                fontWeight: FontWeight.w800,
                color: colors.sectionLabel,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'A .cpl file keeps every chord and lyric on the other device. '
              'No account, link or internet connection is needed.',
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : _shareFile,
                icon: const Icon(Icons.ios_share),
                label: const Text('Share .cpl file'),
              ),
            ),
            const SizedBox(height: 14),
            Center(
              child: TextButton.icon(
                onPressed: _openMyLinks,
                icon: const Icon(Icons.link, size: 17),
                label: const Text('My shared links'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveSection(
    ThemeData theme,
    ChordPlaneColors colors,
    bool signedIn,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.chord.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.broadcast_on_personal, size: 19, color: colors.chord),
              const SizedBox(width: 8),
              Text(
                'LIVE SETLIST',
                style: TextStyle(
                  fontSize: 10.5,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w800,
                  color: colors.sectionLabel,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Give people a link instead of a file. Everyone who opens it sees '
            'changes immediately — including lyric, key and song edits.',
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          if (AppConfig.supabaseInitError != null)
            Text(
              AppConfig.supabaseInitError!,
              style: TextStyle(fontSize: 12.5, color: theme.colorScheme.error),
            )
          else if (_liveToken == null) ...[
            const Text('Guests can', style: TextStyle(fontSize: 12)),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'view', label: Text('View')),
                ButtonSegment(value: 'comment', label: Text('Comment')),
                ButtonSegment(value: 'edit', label: Text('Edit')),
              ],
              selected: {_permission},
              onSelectionChanged: (value) =>
                  setState(() => _permission = value.first),
            ),
            const SizedBox(height: 12),
            const Text('Who can open it', style: TextStyle(fontSize: 12)),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'anyone', label: Text('Anyone')),
                ButtonSegment(value: 'signed_in', label: Text('Signed in')),
              ],
              selected: {_audience},
              onSelectionChanged: (value) =>
                  setState(() => _audience = value.first),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: _busy ? null : _createLiveLink,
                icon: const Icon(Icons.link, size: 19),
                label: Text(
                  signedIn
                      ? 'Create live link'
                      : 'Sign in to create a live link',
                ),
              ),
            ),
          ] else ...[
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: colors.chord.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'LIVE',
                    style: TextStyle(
                      fontSize: 9.5,
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w900,
                      color: colors.chord,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Guests: $_permission · '
                    '${_audience == 'anyone' ? 'anyone with link' : 'signed in only'}',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Center(
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: QrImageView(
                  data: _liveLink,
                  version: QrVersions.auto,
                  size: 170,
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
            const SizedBox(height: 8),
            Center(
              child: Text(
                'Scan to join the live set',
                style: TextStyle(
                  fontSize: 11.5,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Text(
                _liveLink,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11.5,
                  height: 1.35,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _copyLiveLink,
                    icon: const Icon(Icons.copy, size: 17),
                    label: const Text('Copy link'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _sendLiveLink,
                    icon: const Icon(Icons.send_outlined, size: 18),
                    label: const Text('Send link'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Center(
              child: TextButton.icon(
                onPressed: () {
                  final token = _liveToken;
                  if (token == null) return;
                  Navigator.of(context).pop();
                  GoRouter.of(context).push('/live/$token');
                },
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Open live setlist'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String get _liveLink => _liveToken == null
      ? ''
      : '${AppConfig.shareHost}/l/$_liveToken';

  Future<void> _createLiveLink() async {
    if (!ref.read(authGatewayProvider).isSignedIn) {
      await showSignInGate(context);
      return;
    }
    setState(() => _busy = true);
    try {
      final created = await ref.read(liveApiProvider).create(
        title: bundle.title,
        songs: bundle.songs,
        permission: _permission,
        audience: _audience,
      );
      if (!mounted) return;
      setState(() => _liveToken = created.token);
    } on LiveException catch (error) {
      _snack(error.message);
    } catch (error) {
      _snack('Could not create the live link: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyLiveLink() async {
    await Clipboard.setData(ClipboardData(text: _liveLink));
    _snack('Live link copied');
  }

  Future<void> _sendLiveLink() async {
    await SharePlus.instance.share(
      ShareParams(
        text: 'Join my live ChordPlane setlist:\n$_liveLink',
        subject: 'Live ChordPlane setlist',
        sharePositionOrigin: _origin(context),
      ),
    );
  }

  Future<void> _shareFile() async {
    setState(() => _busy = true);
    final service = ref.read(shareServiceProvider);
    try {
      await service.shareFile(bundle, origin: _origin(context));
    } on CplException catch (error) {
      _snack(error.message);
    } catch (error) {
      _snack('Could not share the file: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Rect _origin(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return Rect.zero;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  /// Closes the sheet and opens the older, frozen snapshot links screen.
  void _openMyLinks() {
    Navigator.of(context).pop();
    GoRouter.of(context).push('/my-shares');
  }
}
