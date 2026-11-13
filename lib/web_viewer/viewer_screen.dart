import 'dart:convert';

import 'package:chord_diagrams/chord_diagrams.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../core/chords/chord_document.dart';
import '../../features/songs/presentation/widgets/chord_sheets.dart';
import '../../features/songs/presentation/widgets/song_sheet.dart';
import '../../features/sharing/cpl.dart';
import 'web_config.dart';

/// Fetches the shared snapshot and renders it read-only: chords above
/// lyrics, transpose, and chord diagrams — all through the same widgets the
/// in-app viewer uses.
class ViewerScreen extends StatefulWidget {
  const ViewerScreen({super.key, required this.token});

  final String? token;

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

sealed class _ViewerState {
  const _ViewerState();
}

class _Loading extends _ViewerState {
  const _Loading();
}

class _Failed extends _ViewerState {
  const _Failed(this.message);

  final String message;
}

enum _UnavailableReason { unknown, revoked, underReview, removed }

class _Unavailable extends _ViewerState {
  const _Unavailable(this.reason);

  final _UnavailableReason reason;
}

class _Ready extends _ViewerState {
  const _Ready(this.bundle);

  final CplBundle bundle;
}

class _ViewerScreenState extends State<ViewerScreen> {
  _ViewerState _state = const _Loading();

  Instrument _instrument = Instrument.guitar;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.token == null) {
      setState(() => _state = const _Unavailable(_UnavailableReason.unknown));
      return;
    }
    setState(() => _state = const _Loading());
    final uri = Uri.parse(
      '${WebViewerConfig.supabaseUrl}/rest/v1/shared_bundles',
    ).replace(
      queryParameters: {
        'token': 'eq.${widget.token}',
        'select': 'kind,title,snapshot,status,revoked',
      },
    );
    try {
      final response = await http.get(
        uri,
        headers: {
          'apikey': WebViewerConfig.supabasePublishableKey,
          'Authorization':
              'Bearer ${WebViewerConfig.supabasePublishableKey}',
        },
      );
      if (response.statusCode != 200) {
        setState(() => _state = _Failed('The server responded with '
            '${response.statusCode}.'));
        return;
      }
      final rows = (jsonDecode(response.body) as List).cast<Map>();
      if (rows.isEmpty) {
        setState(() => _state = const _Unavailable(_UnavailableReason.unknown));
        return;
      }
      final row = rows.first;
      final status = (row['status'] as String?) ?? 'active';
      final revoked = (row['revoked'] as bool?) ?? false;
      if (revoked) {
        setState(() => _state = const _Unavailable(_UnavailableReason.revoked));
        return;
      }
      if (status == 'under_review') {
        setState(
          () => _state = const _Unavailable(_UnavailableReason.underReview),
        );
        return;
      }
      if (status == 'removed') {
        setState(() => _state = const _Unavailable(_UnavailableReason.removed));
        return;
      }
      final bundle = CplBundle.decodeJson(jsonEncode(row['snapshot']));
      setState(() => _state = _Ready(bundle));
    } on CplException catch (error) {
      setState(() => _state = _Failed(error.message));
    } catch (_) {
      setState(() => _state = const _Failed(
        'Could not reach the server. Check your connection and try again.',
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ChordPlane'),
        actions: [
          if (_state is _Ready)
            IconButton(
              tooltip: 'Open in the app',
              icon: const Icon(Icons.phone_iphone_outlined),
              onPressed: _openInApp,
            ),
        ],
      ),
      body: switch (_state) {
        _Loading() => const Center(child: CircularProgressIndicator()),
        _Failed(:final message) => _Message(
            icon: Icons.cloud_off_outlined,
            title: 'Something went wrong',
            message: message,
            action: OutlinedButton(
              onPressed: _load,
              child: const Text('Try again'),
            ),
          ),
        _Unavailable(:final reason) => _Message(
            icon: Icons.link_off_outlined,
            title: switch (reason) {
              _UnavailableReason.unknown => 'Link not found',
              _UnavailableReason.revoked => 'Link no longer available',
              _UnavailableReason.underReview => 'Link temporarily hidden',
              _UnavailableReason.removed => 'Link no longer available',
            },
            message: switch (reason) {
              _UnavailableReason.unknown =>
                'This link is not valid or has been deleted. Ask the sender '
                    'for a new one.',
              _UnavailableReason.revoked =>
                'The person who shared this turned the link off.',
              _UnavailableReason.underReview =>
                'This share is being checked while we look into a report. '
                    'Check back later.',
              _UnavailableReason.removed =>
                'This share was taken down and cannot be viewed.',
            },
          ),
        _Ready(:final bundle) => _Content(
            bundle: bundle,
            instrument: _instrument,
            onInstrumentChanged: (value) => setState(() => _instrument = value),
          ),
      },
    );
  }

  Future<void> _openInApp() async {
    if (widget.token == null) return;
    try {
      await launchUrl(
        Uri.parse('chordplane://s/${widget.token}'),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      // No handler on this device — silently ignore; visitors without the
      // app just keep reading here.
    }
  }
}

class _Content extends StatefulWidget {
  const _Content({
    required this.bundle,
    required this.instrument,
    required this.onInstrumentChanged,
  });

  final CplBundle bundle;
  final Instrument instrument;
  final ValueChanged<Instrument> onInstrumentChanged;

  @override
  State<_Content> createState() => _ContentState();
}

class _ContentState extends State<_Content> {
  /// Per-song transpose. Single songs get one entry; setlist entries start
  /// at the transpose baked into the shared setlist item.
  late List<int> _offsets;
  final List<GlobalKey> _sectionKeys = [];

  @override
  void initState() {
    super.initState();
    _resetOffsets(widget.bundle);
  }

  @override
  void didUpdateWidget(covariant _Content oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bundle != widget.bundle) {
      setState(() => _resetOffsets(widget.bundle));
    }
  }

  void _resetOffsets(CplBundle bundle) {
    _sectionKeys.clear();
    if (bundle.kind == CplKind.setlist) {
      _offsets = [
        for (final item in bundle.items) item.transpose,
      ];
      for (final _ in bundle.items) {
        _sectionKeys.add(GlobalKey());
      }
    } else {
      _offsets = [0];
    }
  }

  void _jumpTo(int index) {
    final key = _sectionKeys[index];
    final context = key.currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      alignment: 0.0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bundle = widget.bundle;
    final isSetlist = bundle.kind == CplKind.setlist;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Header(
                bundle: bundle,
                instrument: widget.instrument,
                onInstrumentChanged: widget.onInstrumentChanged,
              ),
              const SizedBox(height: 12),
              if (isSetlist)
                _SongListOverview(
                  bundle: bundle,
                  onJump: _jumpTo,
                ),
              for (var i = 0; i < (isSetlist ? bundle.items.length : 1); i++)
                _SongSection(
                  key: isSetlist ? _sectionKeys[i] : null,
                  position: isSetlist ? i + 1 : null,
                  song: isSetlist ? bundle.items[i].song : bundle.song!,
                  offset: _offsets[i],
                  instrument: widget.instrument,
                  onOffsetChanged: (value) =>
                      setState(() => _offsets[i] = value),
                ),
              const SizedBox(height: 28),
              Center(
                child: Text(
                  'Shared with ChordPlane · chordplane.citcs.site',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The numbered running order at the top of a shared setlist. Tapping a row
/// scrolls to that song's sheet below.
class _SongListOverview extends StatelessWidget {
  const _SongListOverview({required this.bundle, required this.onJump});

  final CplBundle bundle;
  final ValueChanged<int> onJump;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'SET LIST',
              style: TextStyle(
                fontSize: 10.5,
                letterSpacing: 1.1,
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          for (var i = 0; i < bundle.items.length; i++)
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              leading: Text(
                '${i + 1}.',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.primary,
                ),
              ),
              title: Text(
                bundle.items[i].song.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: bundle.items[i].song.artist.isEmpty
                  ? null
                  : Text(
                      bundle.items[i].song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
              trailing: bundle.items[i].transpose != 0
                  ? Text(
                      '${bundle.items[i].transpose > 0 ? '+' : ''}'
                      '${bundle.items[i].transpose}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.primary,
                      ),
                    )
                  : const Icon(Icons.chevron_right, size: 20),
              onTap: () => onJump(i),
            ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

/// One song: heading, its own transpose bar, the sheet, and the all-chords
/// button. Used for both single songs and setlist items.
class _SongSection extends StatelessWidget {
  const _SongSection({
    super.key,
    this.position,
    required this.song,
    required this.offset,
    required this.instrument,
    required this.onOffsetChanged,
  });

  final int? position;
  final CplSong song;
  final int offset;
  final Instrument instrument;
  final ValueChanged<int> onOffsetChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final transposedKey = ChordDocument.transposeKeyLabel(
      song.originalKey,
      offset,
    );

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              if (position != null) ...[
                Text(
                  '$position.',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  song.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (song.artist.isNotEmpty)
                Text(
                  song.artist,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          _TransposeBar(
            keyLabel: transposedKey.isEmpty ? 'Key' : 'Key $transposedKey',
            offset: offset,
            onChanged: onOffsetChanged,
          ),
          const SizedBox(height: 12),
          _SongSheetBlock(
            body: song.body,
            instrument: instrument,
            offset: offset,
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.bundle,
    required this.instrument,
    required this.onInstrumentChanged,
  });

  final CplBundle bundle;
  final Instrument instrument;
  final ValueChanged<Instrument> onInstrumentChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSetlist = bundle.kind == CplKind.setlist;
    final first = isSetlist
        ? bundle.items.firstOrNull?.song
        : bundle.song;

    final facts = <String>[
      if (isSetlist) '${bundle.items.length} songs',
      if (!isSetlist && (first?.artist.isNotEmpty ?? false)) first!.artist,
      if (first != null && first.capo > 0) 'Capo ${first.capo}',
      if (first?.tempo != null) '${first!.tempo} BPM',
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isSetlist ? Icons.queue_music : Icons.music_note,
            color: theme.colorScheme.primary,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  bundle.title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (facts.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    facts.join(' · '),
                    style: TextStyle(
                      fontSize: 12.5,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          SegmentedButton<Instrument>(
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            segments: const [
              ButtonSegment(value: Instrument.guitar, label: Text('Guitar')),
              ButtonSegment(value: Instrument.ukulele, label: Text('Ukulele')),
            ],
            selected: {instrument},
            onSelectionChanged: (value) => onInstrumentChanged(value.first),
          ),
        ],
      ),
    );
  }
}

class _TransposeBar extends StatelessWidget {
  const _TransposeBar({
    required this.keyLabel,
    required this.offset,
    required this.onChanged,
  });

  final String keyLabel;
  final int offset;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Transpose down',
            onPressed: offset > -11 ? () => onChanged(offset - 1) : null,
            icon: const Icon(Icons.remove),
          ),
          Expanded(
            child: Text(
              [
                keyLabel,
                if (offset != 0)
                  'Transposed ${offset > 0 ? '+' : ''}$offset',
              ].join(' · '),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Transpose up',
            onPressed: offset < 11 ? () => onChanged(offset + 1) : null,
            icon: const Icon(Icons.add),
          ),
          TextButton(
            onPressed: offset == 0 ? null : () => onChanged(0),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }
}

class _SongSheetBlock extends StatelessWidget {
  const _SongSheetBlock({
    required this.body,
    required this.offset,
    required this.instrument,
  });

  final String body;
  final int offset;
  final Instrument instrument;

  @override
  Widget build(BuildContext context) {
    final document = ChordDocument.build(
      body: body,
      originalKey: '',
      transpose: offset.clamp(-11, 11),
      detectBare: true,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SongSheet(
          document: document,
          fontScale: 1.0,
          onChordTap: (chord) => showChordVoicingsSheet(
            context,
            chord: chord,
            instrument: instrument,
          ),
        ),
        if (document.chords.isNotEmpty) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => showSongChordsSheet(
              context,
              chords: document.chords,
              instrument: instrument,
            ),
            icon: const Icon(Icons.piano_outlined, size: 18),
            label: Text('All chords (${document.chords.length})'),
          ),
        ],
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
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
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(
                message,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            if (action != null) ...[const SizedBox(height: 18), action!],
          ],
        ),
      ),
    );
  }
}
