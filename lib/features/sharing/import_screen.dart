import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/config/app_config.dart';
import 'cpl.dart';
import 'cloud/server_share_service.dart';
import 'cloud/share_cloud.dart';
import 'share_service.dart';

class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key, this.initialCode, this.initialToken});

  final String? initialCode;

  /// Token of a server-backed share (`/s/<token>` links arrive here).
  final String? initialToken;

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  final _controller = TextEditingController();

  CplBundle? _bundle;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final token = widget.initialToken?.trim();
    if (token != null && token.isNotEmpty) {
      _fetchServerShare(token);
      return;
    }
    final code = widget.initialCode?.trim();
    if (code != null && code.isNotEmpty) {
      _controller.text = code;
      _loadCode(code);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Import')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 32),
        children: [
          Text(
            'Bring in a shared set',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Paste a ChordPlane link or share code, or open a .cpl file someone '
            'sent you. Everything stays on this device.',
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _controller,
            minLines: 3,
            maxLines: 6,
            autocorrect: false,
            keyboardType: TextInputType.multiline,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              height: 1.4,
            ),
            decoration: const InputDecoration(
              hintText:
                  'chordplane://c/…  ·  https://chordplane.citcs.site/s/…',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : _loadFromField,
                  icon: const Icon(Icons.download_outlined, size: 19),
                  label: const Text('Load code'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _pickFile,
                  icon: const Icon(Icons.folder_open, size: 18),
                  label: const Text('.cpl file'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _busy ? null : _pasteFromClipboard,
              icon: const Icon(Icons.content_paste, size: 17),
              label: const Text('Paste from clipboard'),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            _ErrorCard(message: _error!),
          ],
          if (_bundle != null) ...[
            const SizedBox(height: 18),
            _PreviewCard(
              bundle: _bundle!,
              busy: _busy,
              onImport: _import,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) {
      setState(() => _error = 'Your clipboard is empty.');
      return;
    }
    _controller.text = text;
    await _loadFromField();
  }

  Future<void> _loadFromField() async {
    final raw = _controller.text.trim();
    if (raw.isEmpty) {
      setState(() => _error = 'Paste a link or share code first.');
      return;
    }
    if (raw.startsWith('{')) {
      _loadJson(raw);
      return;
    }
    // Server-backed links carry only a token — resolve over the network.
    final token = CplFormat.extractServerToken(raw);
    if (token != null) {
      await _fetchServerShare(token);
      return;
    }
    await _loadCode(raw);
  }

  Future<void> _fetchServerShare(String token) async {
    if (!AppConfig.hasSupabase) {
      setState(
        () => _error =
            'Cloud links are not available in this build. Use a .cpl '
            'file or an inline share code instead.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref.read(serverShareServiceProvider).fetch(token);
      if (!mounted) return;
      if (result == null) {
        setState(
          () => _error =
              'That link has expired, was removed, or never existed.',
        );
        return;
      }
      setState(() {
        _bundle = result.bundle;
      });
    } on ShareCloudException catch (error) {
      if (!mounted) return;
      setState(() {
        _bundle = null;
        _error = error.message;
      });
    } on CplException catch (error) {
      if (!mounted) return;
      setState(() {
        _bundle = null;
        _error = error.message;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadCode(String raw) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bundle = CplBundle.decodeShareCode(raw);
      if (!mounted) return;
      setState(() => _bundle = bundle);
    } on CplException catch (error) {
      if (!mounted) return;
      setState(() {
        _bundle = null;
        _error = error.message;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _loadJson(String raw) {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bundle = CplBundle.decodeJson(raw);
      setState(() => _bundle = bundle);
    } on CplException catch (error) {
      setState(() {
        _bundle = null;
        _error = error.message;
      });
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _pickFile() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final files = await FilePicker.pickFiles(type: FileType.any);
      if (files.isEmpty) return;
      final bytes = await files.first.readAsBytes();
      _loadJson(utf8.decode(bytes));
    } on CplException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on FormatException {
      if (mounted) {
        setState(() => _error = 'That file is not a ChordPlane document.');
      }
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not read that file: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final bundle = _bundle;
    if (bundle == null) return;
    setState(() => _busy = true);
    try {
      final result = await ref.read(shareServiceProvider).importBundle(bundle);
      if (!mounted) return;
      final label = result.kind == CplKind.setlist
          ? 'Imported "${bundle.title}" · ${result.total} '
                '${result.total == 1 ? 'song' : 'songs'}'
          : 'Added "${bundle.title}"';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(label)));
      if (result.kind == CplKind.setlist) {
        context.pushReplacement('/setlist/${result.id}');
      } else {
        context.pushReplacement('/song/${result.id}');
      }
    } on CplException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Import failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
    required this.bundle,
    required this.busy,
    required this.onImport,
  });

  final CplBundle bundle;
  final bool busy;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = ChordPlaneColors.of(context);
    final songs = bundle.songs;
    final shown = songs.take(6).toList();
    final remaining = songs.length - shown.length;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                bundle.kind == CplKind.setlist
                    ? Icons.queue_music
                    : Icons.music_note,
                color: colors.chord,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  bundle.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${bundle.songCount} '
            '${bundle.songCount == 1 ? 'song' : 'songs'} ready to import',
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          for (final item in shown)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(
                    Icons.circle,
                    size: 5,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  if (item.artist.trim().isNotEmpty)
                    Text(
                      item.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          if (remaining > 0)
            Text(
              'and $remaining more',
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: busy ? null : onImport,
              icon: const Icon(Icons.library_add_outlined, size: 19),
              label: Text(
                bundle.kind == CplKind.setlist
                    ? 'Import setlist'
                    : 'Add to library',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 19, color: scheme.onErrorContainer),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: scheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
