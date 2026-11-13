import 'dart:async';
import 'dart:convert';

import 'package:chord_diagrams/chord_diagrams.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../core/chords/chord_document.dart';
import '../../features/songs/presentation/widgets/chord_sheets.dart';
import '../../features/songs/presentation/widgets/song_sheet.dart';
import '../../features/sharing/cpl.dart';
import 'web_config.dart';

/// The chosen instrument, shared across pages so the toggle on the setlist
/// page carries into the song pages.
final ValueNotifier<Instrument> viewerInstrument =
    ValueNotifier<Instrument>(Instrument.guitar);

/// One fetch per app run, shared by the setlist and song pages.
Future<ViewerData> loadSharedBundle(String token) =>
    _fetches.putIfAbsent(token, () => _fetch(token));

final Map<String, Future<ViewerData>> _fetches = {};

Future<ViewerData> _fetch(String token) async {
  final uri = Uri.parse(
    '${WebViewerConfig.supabaseUrl}/rest/v1/shared_bundles',
  ).replace(
    queryParameters: {
      'token': 'eq.$token',
      'select': 'kind,title,snapshot,status,revoked',
    },
  );
  final response = await http.get(
    uri,
    headers: {
      'apikey': WebViewerConfig.supabasePublishableKey,
      'Authorization': 'Bearer ${WebViewerConfig.supabasePublishableKey}',
    },
  );
  if (response.statusCode != 200) {
    throw _ViewerException('The server responded with ${response.statusCode}.');
  }
  final rows = (jsonDecode(response.body) as List).cast<Map>();
  if (rows.isEmpty) {
    return const ViewerData.unavailable(_UnavailableReason.unknown);
  }
  final row = rows.first;
  final status = (row['status'] as String?) ?? 'active';
  final revoked = (row['revoked'] as bool?) ?? false;
  if (revoked) return const ViewerData.unavailable(_UnavailableReason.revoked);
  if (status == 'under_review') {
    return const ViewerData.unavailable(_UnavailableReason.underReview);
  }
  if (status == 'removed') {
    return const ViewerData.unavailable(_UnavailableReason.removed);
  }
  return ViewerData.ready(CplBundle.decodeJson(jsonEncode(row['snapshot'])));
}

sealed class ViewerData {
  const ViewerData();

  const factory ViewerData.unavailable(_UnavailableReason reason) =
      _UnavailableData;
  const factory ViewerData.ready(CplBundle bundle) = _ReadyData;
}

class _UnavailableData implements ViewerData {
  const _UnavailableData(this.reason);

  final _UnavailableReason reason;
}

class _ReadyData implements ViewerData {
  const _ReadyData(this.bundle);

  final CplBundle bundle;
}

class _ViewerException implements Exception {
  const _ViewerException(this.message);

  final String message;

  @override
  String toString() => message;
}

enum _UnavailableReason { unknown, revoked, underReview, removed }

/// Landing page for `/s/<token>`: the set-list overview only — no lyrics.
/// Setlists show the running order; single songs go straight to the sheet.
class SetlistListScreen extends StatelessWidget {
  const SetlistListScreen({super.key, required this.token});

  final String token;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ViewerData>(
      future: loadSharedBundle(token),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _PageScaffold(
            token: token,
            child: const Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return _PageScaffold(
            token: token,
            child: _Message(
              icon: Icons.cloud_off_outlined,
              title: 'Something went wrong',
              message: snapshot.error is _ViewerException
                  ? (snapshot.error as _ViewerException).message
                  : 'Could not reach the server. Check your connection and '
                      'try again.',
            ),
          );
        }
        final data = snapshot.data!;
        return switch (data) {
          _UnavailableData(:final reason) => _PageScaffold(
            token: token,
            child: _unavailableMessage(reason),
          ),
          _ReadyData(:final bundle) => _PageScaffold(
            token: token,
            scrollable: true,
            child: bundle.kind == CplKind.setlist
                ? _SetlistOverview(bundle: bundle)
                : _SongSection(song: bundle.song!, offset: 0),
          ),
        };
      },
    );
  }
}

/// Song page for `/s/<token>/<n>`: exactly one song's sheet.
class SongScreen extends StatelessWidget {
  const SongScreen({super.key, required this.token, required this.songIndex});

  final String token;

  /// 1-based position in the shared setlist.
  final int songIndex;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ViewerData>(
      future: loadSharedBundle(token),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _PageScaffold(
            token: token,
            child: const Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return _PageScaffold(
            token: token,
            child: _Message(
              icon: Icons.cloud_off_outlined,
              title: 'Something went wrong',
              message: snapshot.error is _ViewerException
                  ? (snapshot.error as _ViewerException).message
                  : 'Could not reach the server. Check your connection and '
                      'try again.',
            ),
          );
        }
        final data = snapshot.data!;
        return switch (data) {
          _UnavailableData(:final reason) => _PageScaffold(
            token: token,
            child: _unavailableMessage(reason),
          ),
          _ReadyData() => _songPage(context, data),
        };
      },
    );
  }

  Widget _songPage(BuildContext context, _ReadyData data) {
    final bundle = data.bundle;
    if (bundle.kind == CplKind.setlist) {
      final index = songIndex - 1;
      if (index < 0 || index >= bundle.items.length) {
        return _PageScaffold(
          token: token,
          child: _Message(
            icon: Icons.music_note_outlined,
            title: 'Song not found',
            message: 'That position does not exist in this set list.',
            action: FilledButton.icon(
              onPressed: () => context.go('/s/$token'),
              icon: const Icon(Icons.list),
              label: const Text('All songs'),
            ),
          ),
        );
      }
      return _PageScaffold(
        token: token,
        scrollable: true,
        child: _SongDetail(bundle: bundle, index: index),
      );
    }
    // A shared single song: index is irrelevant, show the song.
    return _PageScaffold(
      token: token,
      scrollable: true,
      child: _SongSection(song: bundle.song!, offset: 0),
    );
  }
}

/// Stateful wrapper for one setlist song: local transpose offset and the
/// back-to-list affordance.
class _SongDetail extends StatefulWidget {
  const _SongDetail({required this.bundle, required this.index});

  final CplBundle bundle;
  final int index;

  @override
  State<_SongDetail> createState() => _SongDetailState();
}

class _SongDetailState extends State<_SongDetail> {
  late int _offset = widget.bundle.items[widget.index].transpose;

  @override
  Widget build(BuildContext context) {
    final item = widget.bundle.items[widget.index];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton.icon(
          onPressed: () => context.go('/s/${_tokenOf(context)}'),
          icon: const Icon(Icons.arrow_back, size: 18),
          label: const Text('All songs'),
        ),
        _SongSection(
          song: item.song,
          offset: _offset,
          onOffsetChanged: (value) => setState(() => _offset = value),
        ),
      ],
    );
  }
}

/// The numbered running order — the landing view of a shared setlist.
class _SetlistOverview extends StatelessWidget {
  const _SetlistOverview({required this.bundle});

  final CplBundle bundle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final token = _tokenOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header(bundle: bundle),
        const SizedBox(height: 12),
        Container(
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
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16),
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
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (bundle.items[i].transpose != 0)
                        Text(
                          '${bundle.items[i].transpose > 0 ? '+' : ''}'
                          '${bundle.items[i].transpose}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      const SizedBox(width: 6),
                      const Icon(Icons.chevron_right, size: 20),
                    ],
                  ),
                  onTap: () => context.go('/s/$token/${i + 1}'),
                ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ],
    );
  }
}

/// Reads the share token out of the current go_router match.
String _tokenOf(BuildContext context) {
  return GoRouterState.of(context).pathParameters['token'] ?? '';
}

/// Shared header card used on the setlist landing page.
class _Header extends StatelessWidget {
  const _Header({required this.bundle});

  final CplBundle bundle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final facts = <String>['${bundle.items.length} songs'];

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
            Icons.queue_music,
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
                const SizedBox(height: 3),
                Text(
                  facts.join(' · '),
                  style: TextStyle(
                    fontSize: 12.5,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _InstrumentToggle(),
        ],
      ),
    );
  }
}

/// Guitar/ukulele switch, driven by the shared [viewerInstrument] notifier.
class _InstrumentToggle extends StatelessWidget {
  const _InstrumentToggle();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Instrument>(
      valueListenable: viewerInstrument,
      builder: (context, instrument, _) {
        return SegmentedButton<Instrument>(
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
          onSelectionChanged: (value) => viewerInstrument.value = value.first,
        );
      },
    );
  }
}

/// One song: heading, transpose bar, the sheet, and the all-chords button.
class _SongSection extends StatelessWidget {
  const _SongSection({
    required this.song,
    required this.offset,
    this.onOffsetChanged,
  });

  final CplSong song;
  final int offset;
  final ValueChanged<int>? onOffsetChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final transposedKey = ChordDocument.transposeKeyLabel(
      song.originalKey,
      offset,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(
                song.title,
                style: theme.textTheme.titleLarge?.copyWith(
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
        if (onOffsetChanged != null) ...[
          _TransposeBar(
            keyLabel: transposedKey.isEmpty ? 'Key' : 'Key $transposedKey',
            offset: offset,
            onChanged: onOffsetChanged!,
          ),
          const SizedBox(height: 12),
        ],
        _SongSheetBlock(body: song.body, offset: offset),
      ],
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
  const _SongSheetBlock({required this.body, required this.offset});

  final String body;
  final int offset;

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
            instrument: viewerInstrument.value,
          ),
        ),
        if (document.chords.isNotEmpty) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => showSongChordsSheet(
              context,
              chords: document.chords,
              instrument: viewerInstrument.value,
            ),
            icon: const Icon(Icons.piano_outlined, size: 18),
            label: Text('All chords (${document.chords.length})'),
          ),
        ],
      ],
    );
  }
}

/// Scaffold shared by all pages: app bar, "open in app" banner (only when a
/// share token is known), and the footer.
class _PageScaffold extends StatelessWidget {
  const _PageScaffold({
    this.token,
    required this.child,
    this.scrollable = false,
  });

  /// Present on share pages; null on the home / not-found pages, where there
  /// is nothing to open in the app.
  final String? token;
  final Widget child;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final body = Column(
      children: [
        Expanded(
          child: scrollable
              ? SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: child,
                    ),
                  ),
                )
              : Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(32),
                    child: child,
                  ),
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Column(
            children: [
              if (token != null) ...[
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _launchApp(context, token!),
                    icon: const Icon(Icons.phone_iphone_outlined, size: 19),
                    label: const Text('Open in the ChordPlane app'),
                  ),
                ),
                const SizedBox(height: 6),
              ],
              Text(
                'Shared with ChordPlane · chordplane.citcs.site',
                style: TextStyle(
                  fontSize: 11.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    return Scaffold(appBar: AppBar(title: const Text('ChordPlane')), body: body);
  }

  Future<void> _launchApp(BuildContext context, String token) async {
    try {
      await launchUrl(
        Uri.parse('chordplane://s/$token'),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      // No handler on this device — the page stays usable.
    }
  }
}

/// Landing page for the bare domain (`/`). Anyone who types the host or hits
/// a QR that encodes it lands here — explain what the site is and what a
/// real shared link looks like. No redirect: there is no sensible default
/// share to send people to.
class HomeLandingScreen extends StatelessWidget {
  const HomeLandingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _PageScaffold(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.music_note, size: 52, color: theme.colorScheme.primary),
          const SizedBox(height: 14),
          Text(
            'ChordPlane',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Text(
              'Chord and lyric sheets with diagrams. Build set lists, share '
              'them with a link, and transpose any song into the key you '
              'need.',
              style: TextStyle(
                fontSize: 13.5,
                height: 1.45,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
              ),
            ),
            child: Column(
              children: [
                Text(
                  'Shared links look like',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'chordplane.citcs.site/s/<token>',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Fallback for every unknown URL — typos in tokens, stale paths, anything
/// the routes above don't match.
class NotFoundScreen extends StatelessWidget {
  const NotFoundScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _PageScaffold(
      child: _Message(
        icon: Icons.explore_off_outlined,
        title: 'Page not found',
        message:
            'The page you are looking for does not exist. Shared links look '
            'like chordplane.citcs.site/s/<token> — double-check the link '
            'you were sent.',
      ),
    );
  }
}

Widget _unavailableMessage(_UnavailableReason reason) {
  return _Message(
    icon: Icons.link_off_outlined,
    title: switch (reason) {
      _UnavailableReason.unknown => 'Link not found',
      _UnavailableReason.revoked => 'Link no longer available',
      _UnavailableReason.underReview => 'Link temporarily hidden',
      _UnavailableReason.removed => 'Link no longer available',
    },
    message: switch (reason) {
      _UnavailableReason.unknown =>
        'This link is not valid or has been deleted. Ask the sender for a '
            'new one.',
      _UnavailableReason.revoked =>
        'The person who shared this turned the link off.',
      _UnavailableReason.underReview =>
        'This share is being checked while we look into a report. Check '
            'back later.',
      _UnavailableReason.removed =>
        'This share was taken down and cannot be viewed.',
    },
  );
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
    return Column(
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
    );
  }
}
