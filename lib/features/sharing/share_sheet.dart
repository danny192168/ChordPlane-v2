import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/config/app_config.dart';
import '../../../core/auth/auth_gateway.dart';
import 'cpl.dart';
import 'cloud/auth_gate_sheet.dart';
import 'cloud/server_share_service.dart';
import 'cloud/share_cloud.dart';
import 'share_service.dart';

/// Largest share code that still produces a comfortably scannable QR code.
const int qrCodeLimit = 1600;

Future<void> showShareSheet(
  BuildContext context, {
  required CplBundle bundle,

  /// Local song/setlist id the bundle came from, when known. Lets the share
  /// be remembered so "My shared links" can offer "Update shared copy".
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

  /// Set once a cloud share exists; its link is then shown like an inline one.
  String? _serverToken;

  CplBundle get bundle => widget.bundle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = ChordPlaneColors.of(context);
    final signedIn = ref.watch(signedInProvider).value ?? false;
    final inlineLink = bundle.toLink();
    final showQr = inlineLink.length <= qrCodeLimit;

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
              _CloudLinkSection(
                bundle: bundle,
                signedIn: signedIn,
                busy: _busy,
                serverToken: _serverToken,
                onCreate: _createServerLink,
                onOpenMyLinks: _openMyLinks,
              ),
              const SizedBox(height: 20),
              Text(
                'OFFLINE OPTIONS',
                style: TextStyle(
                  fontSize: 10.5,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w800,
                  color: colors.sectionLabel,
                ),
              ),
              const SizedBox(height: 6),
            ],
            if (showQr)
              Center(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant.withValues(
                        alpha: 0.4,
                      ),
                    ),
                  ),
                  child: QrImageView(
                    data: inlineLink,
                    version: QrVersions.auto,
                    size: 216,
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
                    semanticsLabel: 'QR code for ${bundle.title}',
                  ),
                ),
              )
            else
              _NoticeCard(
                icon: Icons.qr_code_2,
                text:
                    'This set is too long to fit in a QR code. Share the .cpl '
                    'file or the link instead — both carry the whole set.',
              ),
            if (showQr) ...[
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'Scan from another device to import',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _busy ? null : _shareFile,
              icon: const Icon(Icons.ios_share),
              label: const Text('Share .cpl file'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _copyLink,
                    icon: const Icon(Icons.link, size: 19),
                    label: const Text('Copy link'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _shareLink,
                    icon: const Icon(Icons.send_outlined, size: 18),
                    label: const Text('Send link'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'LINKS AND CODES',
              style: TextStyle(
                fontSize: 10.5,
                letterSpacing: 1.1,
                fontWeight: FontWeight.w800,
                color: colors.sectionLabel,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.35,
                  ),
                ),
              ),
              child: Text(
                inlineLink,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10.5,
                  height: 1.35,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'A .cpl file works offline and keeps every chord. Links are '
              'convenient for small sets and paste straight into Import.',
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
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

  Future<void> _createServerLink() async {
    setState(() => _busy = true);
    try {
      final result = await ref
          .read(serverShareServiceProvider)
          .share(bundle, localId: widget.localId);
      if (!mounted) return;
      setState(() => _serverToken = result.token);
      if (result.upload == ShareUpload.queued) {
        _snack('Saved offline — the link goes live once you are back online.');
      }
    } on SignInRequiredException {
      if (!mounted) return;
      await showSignInGate(context);
    } on ShareCloudException catch (error) {
      _snack(error.message);
    } catch (error) {
      _snack('Could not create the link: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareLink() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(shareServiceProvider)
          .shareLink(bundle, origin: _origin(context));
    } catch (error) {
      _snack('Could not share the link: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyLink() async {
    await ref.read(shareServiceProvider).copyLink(bundle);
    _snack('Link copied');
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

  /// Closes the sheet and opens the "My shared links" screen.
  void _openMyLinks() {
    Navigator.of(context).pop();
    GoRouter.of(context).push('/my-shares');
  }
}

/// The cloud section of the share sheet: sign-in prompt, create button, and
/// the short server link once one exists.
class _CloudLinkSection extends StatelessWidget {
  const _CloudLinkSection({
    required this.bundle,
    required this.signedIn,
    required this.busy,
    required this.serverToken,
    required this.onCreate,
    required this.onOpenMyLinks,
  });

  final CplBundle bundle;
  final bool signedIn;
  final bool busy;
  final String? serverToken;
  final VoidCallback onCreate;
  final VoidCallback onOpenMyLinks;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = ChordPlaneColors.of(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colors.chord.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.cloud_outlined, size: 19, color: colors.chord),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'CLOUD LINK',
                  style: TextStyle(
                    fontSize: 10.5,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w800,
                    color: colors.sectionLabel,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'A short link anyone can open — no app needed to view, and no '
            'size limit. Your snapshot stays frozen after you send it.',
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          if (AppConfig.supabaseInitError != null)
            Text(
              AppConfig.supabaseInitError!,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: theme.colorScheme.error,
              ),
            )
          else if (serverToken != null) ...[
            _ServerLinkCard(token: serverToken!),
          ] else ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: busy ? null : onCreate,
                icon: const Icon(Icons.link, size: 19),
                label: Text(
                  signedIn ? 'Create cloud link' : 'Sign in to create a link',
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Center(
            child: TextButton.icon(
              onPressed: onOpenMyLinks,
              icon: const Icon(Icons.link, size: 17),
              label: const Text('My shared links'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The created server link with copy / send / QR actions.
class _ServerLinkCard extends StatelessWidget {
  const _ServerLinkCard({required this.token});

  final String token;

  @override
  Widget build(BuildContext context) {
    final link = CplFormat.serverLink(token);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
          child: Text(
            link,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: link));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Link copied')),
                    );
                  }
                },
                icon: const Icon(Icons.copy, size: 17),
                label: const Text('Copy'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: () async {
                  await SharePlus.instance.share(
                    ShareParams(
                      text: 'Open in ChordPlane:\n$link',
                      subject: 'ChordPlane link',
                      sharePositionOrigin: _boxOrigin(context),
                    ),
                  );
                },
                icon: const Icon(Icons.send_outlined, size: 18),
                label: const Text('Send'),
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
            ),
            child: QrImageView(
              data: link,
              version: QrVersions.auto,
              size: 150,
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
              semanticsLabel: 'QR code for the cloud link',
            ),
          ),
        ),
      ],
    );
  }

  Rect _boxOrigin(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return Rect.zero;
    return box.localToGlobal(Offset.zero) & box.size;
  }
}

class _NoticeCard extends StatelessWidget {  const _NoticeCard({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
