import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/auth/auth_gateway.dart';
import '../../../core/settings/settings.dart';
import '../../sharing/cloud/auth_gate_sheet.dart';
import '../../songs/data/song_providers.dart';
import '../../songs/data/song_repository.dart';
import '../../songs/presentation/widgets/chord_sheets.dart';
import '../../songs/presentation/widgets/song_sheet.dart';
import '../data/community_api.dart';
import '../data/community_providers.dart';

/// Read-only view of a community song, with a gated accuracy rating and a
/// one-tap "save a copy on this device" action.
class CommunitySongScreen extends ConsumerStatefulWidget {
  const CommunitySongScreen({super.key, required this.songId});

  final String songId;

  @override
  ConsumerState<CommunitySongScreen> createState() =>
      _CommunitySongScreenState();
}

class _CommunitySongScreenState extends ConsumerState<CommunitySongScreen> {
  int? _myScore;
  final _comment = TextEditingController();
  bool _savingRating = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMyRating());
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(signedInProvider, (previous, next) {
      if (next.value == true && previous?.value != true) _loadMyRating();
    });
    final songAsync = ref.watch(communitySongProvider(widget.songId));
    return songAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, stack) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('Could not load song: $error')),
      ),
      data: (song) {
        if (song == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('This song is no longer public.')),
          );
        }
        return _buildSong(song);
      },
    );
  }

  Widget _buildSong(CommunitySong song) {
    final theme = Theme.of(context);
    final settings = ref.watch(settingsProvider);
    final signedIn =
        ref.watch(signedInProvider).value ??
        ref.read(authGatewayProvider).isSignedIn;
    final eligibility = ref.watch(ratingEligibilityProvider);
    final document = ref.watch(
      chordDocumentProvider((
        body: song.body,
        originalKey: song.originalKey,
        transpose: 0,
        mode: song.chordDetectionMode,
      )),
    );
    final date = DateFormat.yMMMd().format(song.createdAt.toLocal());

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              song.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            Text(
              song.artist.isEmpty ? 'Unknown artist' : song.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Open saved copy',
            onPressed: () async {
              final id = await ref
                  .read(songRepositoryProvider)
                  .cacheCommunitySong(song);
              if (!mounted || id == null) return;
              context.push('/song/$id');
            },
            icon: const Icon(Icons.download_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 40),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (song.originalKey.isNotEmpty)
                _MetaChip(label: 'Key', value: song.originalKey),
              if (song.capo > 0)
                _MetaChip(label: 'Capo', value: '${song.capo}'),
              if (song.tempo != null)
                _MetaChip(label: 'Tempo', value: '${song.tempo} BPM'),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${song.credit} · uploaded $date',
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (song.youtubeUrl.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () {
                final uri = Uri.tryParse(song.youtubeUrl.trim());
                if (uri != null) {
                  launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              icon: const Icon(Icons.play_circle_outline, size: 18),
              label: const Text('Play reference video'),
            ),
          ],
          const SizedBox(height: 14),
          SongSheet(
            document: document,
            fontScale: settings.textScale,
            onChordTap: (chord) => showChordVoicingsSheet(
              context,
              chord: chord,
              instrument: settings.instrument,
            ),
          ),
          const SizedBox(height: 28),
          _RatingSection(
            song: song,
            signedIn: signedIn,
            eligibility: eligibility,
            score: _myScore,
            comment: _comment,
            busy: _savingRating,
            onSignIn: () => showSignInGate(context),
            onSave: () => _saveRating(song.id),
            onScore: (value) => setState(() => _myScore = value),
          ),
        ],
      ),
    );
  }

  Future<void> _loadMyRating() async {
    final signedIn =
        ref.read(signedInProvider).value ??
        ref.read(authGatewayProvider).isSignedIn;
    if (!signedIn) return;
    try {
      final rating = await ref
          .read(communityApiProvider)
          .myRating(widget.songId);
      if (!mounted || rating == null) return;
      setState(() {
        _myScore = rating.score;
        _comment.text = rating.comment;
      });
    } on CommunityException {
      // A missing migration must not block reading the song.
    }
  }

  Future<void> _saveRating(String songId) async {
    if (_myScore == null) return;
    setState(() => _savingRating = true);
    try {
      await ref
          .read(communityApiProvider)
          .rate(songId, _myScore!, _comment.text);
      if (!mounted) return;
      ref.invalidate(communitySongProvider(songId));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thanks — your rating was saved')),
      );
    } on CommunityException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
      }
    } finally {
      if (mounted) setState(() => _savingRating = false);
    }
  }
}

class _RatingSection extends StatelessWidget {
  const _RatingSection({
    required this.song,
    required this.signedIn,
    required this.eligibility,
    required this.score,
    required this.comment,
    required this.busy,
    required this.onSignIn,
    required this.onSave,
    required this.onScore,
  });

  final CommunitySong song;
  final bool signedIn;
  final AsyncValue<RatingEligibility> eligibility;
  final int? score;
  final TextEditingController comment;
  final bool busy;
  final VoidCallback onSignIn;
  final VoidCallback onSave;
  final ValueChanged<int> onScore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = ChordPlaneColors.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.star_outline, size: 19, color: colors.chord),
              const SizedBox(width: 8),
              Text(
                'CHORD ACCURACY',
                style: TextStyle(
                  fontSize: 10.5,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w800,
                  color: colors.sectionLabel,
                ),
              ),
              const Spacer(),
              if (song.ratingCount > 0)
                Text(
                  '${song.ratingAverage.toStringAsFixed(1)} '
                  '(${song.ratingCount})',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (!signedIn)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Sign in to rate how accurate these chords are.',
                  style: TextStyle(fontSize: 12.5),
                ),
                const SizedBox(height: 8),
                FilledButton.tonal(
                  onPressed: onSignIn,
                  child: const Text('Sign in'),
                ),
              ],
            )
          else
            eligibility.when(
              loading: () => const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              error: (error, stack) => Text(
                'Ratings are unavailable right now. $error',
                style: TextStyle(
                  fontSize: 12.5,
                  color: theme.colorScheme.error,
                ),
              ),
              data: (state) {
                if (!state.allowed) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ratings unlock after 3 days and one day of use.',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 6),
                      for (final reason in state.reasons)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Text(
                            '• $reason',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        for (var value = 1; value <= 5; value++)
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 38,
                              minHeight: 38,
                            ),
                            tooltip: '$value out of 5',
                            onPressed: busy ? null : () => onScore(value),
                            icon: Icon(
                              value <= (score ?? 0)
                                  ? Icons.star
                                  : Icons.star_border,
                              color: value <= (score ?? 0)
                                  ? colors.chord
                                  : theme.colorScheme.outline,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: comment,
                      enabled: !busy,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Comment (optional)',
                        hintText: 'What could be clearer?',
                      ),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: busy || score == null ? null : onSave,
                      icon: const Icon(Icons.rate_review_outlined, size: 18),
                      label: Text(
                        score == null ? 'Choose a rating' : 'Save rating',
                      ),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '${label.toUpperCase()}  $value',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
      ),
    );
  }
}
