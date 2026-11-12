import 'package:chord_diagrams/chord_diagrams.dart' show Instrument;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/chords/chord_document.dart';
import '../../../core/db/app_database.dart';
import '../../../core/settings/settings.dart';
import '../../sharing/share_service.dart';
import '../../sharing/share_sheet.dart';
import '../data/song_providers.dart';
import '../data/song_repository.dart';
import 'widgets/chord_sheets.dart';
import 'widgets/song_sheet.dart';

class SongViewerScreen extends ConsumerStatefulWidget {
  const SongViewerScreen({super.key, required this.songId});

  final String songId;

  @override
  ConsumerState<SongViewerScreen> createState() => _SongViewerScreenState();
}

class _SongViewerScreenState extends ConsumerState<SongViewerScreen>
    with SingleTickerProviderStateMixin {
  final ScrollController _scroll = ScrollController();
  final Map<int, Offset> _pointers = <int, Offset>{};

  late final Ticker _ticker;
  late double _fontScale;
  late double _speed;

  int _transpose = 0;
  bool _auto = false;
  Duration _lastTick = Duration.zero;
  double _pinchStartDistance = 0;
  double _pinchStartScale = 1;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _fontScale = settings.textScale;
    _speed = ref
        .read(settingsProvider.notifier)
        .autoscrollSpeed(widget.songId);
    _ticker = createTicker(_onTick);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _scroll.dispose();
    if (_auto) WakelockPlus.disable().ignore();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    if (!_scroll.hasClients) return;
    final now = elapsed.inMicroseconds / 1e6;
    var dt = now - (_lastTick.inMicroseconds / 1e6);
    _lastTick = elapsed;
    if (dt <= 0 || dt > 0.25) dt = 1 / 60;

    final position = _scroll.position;
    final max = position.maxScrollExtent;
    if (max <= 0) {
      _stopAuto();
      return;
    }
    final next = (position.pixels + _speed * dt).clamp(0.0, max);
    _scroll.jumpTo(next);
    if (next >= max) _stopAuto();
  }

  void _toggleAuto() {
    if (_auto) {
      _stopAuto();
      return;
    }
    if (_scroll.hasClients &&
        _scroll.position.hasContentDimensions &&
        _scroll.position.pixels >= _scroll.position.maxScrollExtent) {
      _scroll.jumpTo(0);
    }
    _lastTick = Duration.zero;
    _ticker.start();
    WakelockPlus.enable().ignore();
    setState(() => _auto = true);
  }

  void _stopAuto() {
    if (!_auto) return;
    _ticker.stop();
    WakelockPlus.disable().ignore();
    if (mounted) setState(() => _auto = false);
  }

  @override
  Widget build(BuildContext context) {
    final songAsync = ref.watch(songProvider(widget.songId));

    return songAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, stack) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('Could not open song: $error')),
      ),
      data: (song) {
        if (song == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('This song is no longer available.')),
          );
        }
        return _buildSong(song);
      },
    );
  }

  Widget _buildSong(SongRow song) {
    final settings = ref.watch(settingsProvider);
    final isFavorite =
        ref.watch(favoriteProvider(widget.songId)).value ?? false;
    final document = ref.watch(
      chordDocumentProvider((
        body: song.body,
        originalKey: song.originalKey,
        transpose: _transpose,
        detectBare: settings.detectBareChords,
      )),
    );
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              song.title.trim().isEmpty ? 'Untitled' : song.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            if (song.artist.trim().isNotEmpty)
              GestureDetector(
                onTap: () => context.push(
                  '/artist/${song.artistSlug.isEmpty ? 'unknown' : song.artistSlug}',
                ),
                child: Text(
                  song.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: isFavorite ? 'Remove favorite' : 'Favorite',
            onPressed: () =>
                ref.read(songRepositoryProvider).toggleFavorite(song.id),
            icon: Icon(
              isFavorite ? Icons.favorite : Icons.favorite_border,
              color: isFavorite ? theme.colorScheme.error : null,
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (value) => _onMenu(value, song),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'edit',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.edit_outlined),
                  title: Text('Edit song'),
                ),
              ),
              PopupMenuItem(
                value: 'youtube',
                enabled: song.youtubeUrl.trim().isNotEmpty,
                child: const ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.play_circle_outline),
                  title: Text('Open YouTube'),
                ),
              ),
              const PopupMenuItem(
                value: 'copy',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.copy_all_outlined),
                  title: Text('Copy as ChordPro'),
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'share',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.ios_share),
                  title: Text('Share song'),
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.delete_outline),
                  title: Text('Delete song'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Listener(
              onPointerDown: _onPointerDown,
              onPointerMove: _onPointerMove,
              onPointerUp: _onPointerEnd,
              onPointerCancel: _onPointerEnd,
              child: ListView(
                controller: _scroll,
                physics: _pointers.length >= 2
                    ? const NeverScrollableScrollPhysics()
                    : null,
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 36),
                children: [
                  _SongHeader(
                    song: song,
                    document: document,
                    transpose: _transpose,
                    onChordTap: (chord) => showChordVoicingsSheet(
                      context,
                      chord: chord,
                      instrument: settings.instrument,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SongSheet(
                    document: document,
                    fontScale: _fontScale,
                    onChordTap: (chord) => showChordVoicingsSheet(
                      context,
                      chord: chord,
                      instrument: settings.instrument,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Center(
                    child: Text(
                      _transpose == 0
                          ? 'Original key'
                          : 'Transposed ${_signed(_transpose)} semitones',
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.65,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_auto) _buildSpeedPanel(theme),
            _buildToolbar(theme, document, settings.instrument),
          ],
        ),
      ),
    );
  }

  Widget _buildSpeedPanel(ThemeData theme) {
    return Container(
      color: theme.colorScheme.surfaceContainer,
      padding: const EdgeInsets.fromLTRB(12, 2, 14, 0),
      child: Row(
        children: [
          const Icon(Icons.speed, size: 17),
          Expanded(
            child: Slider(
              value: _speed,
              min: 8,
              max: 120,
              onChanged: (value) {
                setState(() => _speed = value);
                ref
                    .read(settingsProvider.notifier)
                    .setAutoscrollSpeed(widget.songId, value);
              },
            ),
          ),
          SizedBox(
            width: 46,
            child: Text(
              '${_speed.round()}',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(
    ThemeData theme,
    ChordDocument document,
    Instrument instrument,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(4, 5, 4, 5),
      child: Row(
        children: [
          Expanded(
            child: _ToolButton(
              icon: Icons.swap_vert,
              label: _transpose == 0 ? 'Key' : _signed(_transpose),
              active: _transpose != 0,
              onTap: () => _openTransposeSheet(document),
            ),
          ),
          Expanded(
            child: _ToolButton(
              icon: Icons.format_size,
              label: '${(_fontScale * 100).round()}%',
              onTap: _openTextSheet,
            ),
          ),
          Expanded(
            child: _ToolButton(
              icon: _auto ? Icons.pause : Icons.play_arrow,
              label: _auto ? 'Pause' : 'Auto',
              active: _auto,
              onTap: _toggleAuto,
            ),
          ),
          Expanded(
            child: _ToolButton(
              icon: Icons.piano_outlined,
              label: 'Chords',
              onTap: () => showSongChordsSheet(
                context,
                chords: document.chords,
                instrument: instrument,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openTransposeSheet(ChordDocument current) async {
    _ticker.muted = true;
    var offset = _transpose;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final songKey = offset == 0
                ? current.displayKey
                : _transposeKeyLabel(
                    ref.read(songProvider(widget.songId)).value,
                    offset,
                  );

            void change(int next) {
              final clamped = next.clamp(-11, 11);
              setSheetState(() => offset = clamped);
              setState(() => _transpose = clamped);
            }

            return Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Transpose',
                    style: Theme.of(sheetContext).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (songKey.isNotEmpty) 'Play in $songKey',
                      offset == 0
                          ? 'Original key'
                          : '${_signed(offset)} semitones',
                    ].join(' · '),
                    style: TextStyle(
                      color: Theme.of(
                        sheetContext,
                      ).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: offset <= -11
                              ? null
                              : () => change(offset - 1),
                          child: const Icon(Icons.remove),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 86,
                        child: Column(
                          children: [
                            Text(
                              _signed(offset),
                              style: const TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.w800,
                                height: 1,
                                fontFeatures: [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'semitones',
                              style: TextStyle(
                                fontSize: 10,
                                color: Theme.of(
                                  sheetContext,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: offset >= 11
                              ? null
                              : () => change(offset + 1),
                          child: const Icon(Icons.add),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Slider(
                    value: offset.toDouble(),
                    min: -11,
                    max: 11,
                    divisions: 22,
                    label: _signed(offset),
                    onChanged: (value) => change(value.round()),
                  ),
                  Center(
                    child: TextButton.icon(
                      onPressed: () => change(0),
                      icon: const Icon(Icons.restart_alt, size: 18),
                      label: const Text('Reset to original'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    _ticker.muted = false;
  }

  String _transposeKeyLabel(SongRow? song, int offset) {
    if (song == null) return '';
    // A direct root transpose — no document parsing per slider frame.
    return ChordDocument.transposeKeyLabel(song.originalKey, offset);
  }

  Future<void> _openTextSheet() async {
    _ticker.muted = true;
    var scale = _fontScale;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            void change(double next) {
              final clamped = next.clamp(0.7, 2.0);
              setSheetState(() => scale = clamped);
              setState(() => _fontScale = clamped);
            }

            return Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Text size',
                        style: Theme.of(sheetContext).textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const Spacer(),
                      Text(
                        '${(scale * 100).round()}%',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Theme.of(sheetContext).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      IconButton.filledTonal(
                        onPressed: () => change(scale - 0.1),
                        icon: const Text(
                          'A',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                      Expanded(
                        child: Slider(
                          value: scale,
                          min: 0.7,
                          max: 2,
                          divisions: 13,
                          onChanged: change,
                        ),
                      ),
                      IconButton.filledTonal(
                        onPressed: () => change(scale + 0.1),
                        icon: const Text(
                          'A',
                          style: TextStyle(fontSize: 20),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Center(
                    child: TextButton.icon(
                      onPressed: () => change(1),
                      icon: const Icon(Icons.restart_alt, size: 18),
                      label: const Text('Reset to 100%'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    ref.read(settingsProvider.notifier).setTextScale(scale);
    _ticker.muted = false;
  }

  Future<void> _onMenu(String value, SongRow song) async {
    switch (value) {
      case 'edit':
        await context.push('/editor/${song.id}');
        return;
      case 'youtube':
        final uri = Uri.tryParse(song.youtubeUrl.trim());
        if (uri == null ||
            (uri.scheme != 'http' && uri.scheme != 'https')) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('That YouTube link looks invalid.')),
          );
          return;
        }
        final opened = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (!opened && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open YouTube.')),
          );
        }
        return;
      case 'copy':
        final text = [
          '${song.title} — ${song.artist}'.trim(),
          if (song.originalKey.isNotEmpty) 'Key: ${song.originalKey}',
          if (song.capo > 0) 'Capo: ${song.capo}',
          '',
          song.body,
        ].join('\n');
        await Clipboard.setData(ClipboardData(text: text));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ChordPro copied to clipboard')),
        );
        return;
      case 'share':
        final bundle = await ref
            .read(shareServiceProvider)
            .bundleForSong(song.id);
        if (!mounted) return;
        await showShareSheet(context, bundle: bundle);
        return;
      case 'delete':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete song?'),
            content: Text(
              '"${song.title}" will be removed from this device.',
            ),
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
        await ref.read(songRepositoryProvider).deleteSong(song.id);
        if (!mounted) return;
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/');
        }
    }
  }

  void _onPointerDown(PointerDownEvent event) {
    _pointers[event.pointer] = event.position;
    if (_pointers.length == 2) {
      _pinchStartDistance = _pinchDistance();
      _pinchStartScale = _fontScale;
      setState(() {});
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_pointers.containsKey(event.pointer)) return;
    _pointers[event.pointer] = event.position;
    if (_pointers.length != 2 || _pinchStartDistance <= 0) return;
    final ratio = _pinchDistance() / _pinchStartDistance;
    if ((ratio - 1).abs() < 0.004) return;
    // Quantize to 5% steps: rebuilding the whole sheet every pointer frame
    // is what made pinch-to-zoom feel laggy.
    final raw = (_pinchStartScale * ratio).clamp(0.7, 2.0);
    final next = (raw / 0.05).roundToDouble() * 0.05;
    if ((next - _fontScale).abs() < 0.01) return;
    setState(() => _fontScale = next);
  }

  void _onPointerEnd(PointerEvent event) {
    _pointers.remove(event.pointer);
    if (_pointers.isEmpty) {
      _pinchStartDistance = 0;
      ref.read(settingsProvider.notifier).setTextScale(_fontScale);
      if (mounted) setState(() {});
    }
  }

  double _pinchDistance() {
    final points = _pointers.values.toList(growable: false);
    if (points.length < 2) return 0;
    return (points[0] - points[1]).distance;
  }

  static String _signed(int value) {
    if (value == 0) return '0';
    return value > 0 ? '+$value' : '$value';
  }
}

class _SongHeader extends StatelessWidget {
  const _SongHeader({
    required this.song,
    required this.document,
    required this.transpose,
    required this.onChordTap,
  });

  final SongRow song;
  final ChordDocument document;
  final int transpose;
  final ValueChanged<String> onChordTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = ChordPlaneColors.of(context);
    final chips = <Widget>[
      if (document.displayKey.isNotEmpty)
        _MetaChip(label: 'Key', value: document.displayKey),
      if (song.capo > 0) _MetaChip(label: 'Capo', value: '${song.capo}'),
      if (song.tempo != null)
        _MetaChip(label: 'Tempo', value: '${song.tempo} BPM'),
      if (transpose != 0)
        _MetaChip(
          label: 'Transpose',
          value: transpose > 0 ? '+$transpose' : '$transpose',
          accent: true,
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (chips.isNotEmpty)
          Wrap(spacing: 8, runSpacing: 8, children: chips),
        if (song.youtubeUrl.trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          TextButton.icon(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              visualDensity: VisualDensity.compact,
            ),
            onPressed: () async {
              final uri = Uri.tryParse(song.youtubeUrl.trim());
              if (uri != null) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            icon: const Icon(Icons.play_circle_outline, size: 19),
            label: const Text('Play reference video'),
          ),
        ],
        if (document.chords.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'CHORDS',
            style: TextStyle(
              fontSize: 10.5,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w800,
              color: colors.sectionLabel,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final chord in document.chords)
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  backgroundColor: colors.chordSurface,
                  side: BorderSide.none,
                  label: Text(
                    chord,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w700,
                      color: colors.chord,
                    ),
                  ),
                  onPressed: () => onChordTap(chord),
                ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        Divider(
          height: 1,
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ],
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.label,
    required this.value,
    this.accent = false,
  });

  final String label;
  final String value;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: accent ? scheme.primaryContainer : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 9.5,
              letterSpacing: 0.7,
              fontWeight: FontWeight.w800,
              color: accent
                  ? scheme.onPrimaryContainer.withValues(alpha: 0.75)
                  : scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: accent ? scheme.onPrimaryContainer : scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = active ? scheme.primary : scheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 21, color: color),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
