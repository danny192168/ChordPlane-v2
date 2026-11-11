import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/settings/settings.dart';
import '../data/song_providers.dart';
import '../data/song_repository.dart';
import 'widgets/chord_sheets.dart';
import 'widgets/song_sheet.dart';

class SongEditorScreen extends ConsumerStatefulWidget {
  const SongEditorScreen({super.key, this.songId});

  final String? songId;

  @override
  ConsumerState<SongEditorScreen> createState() => _SongEditorScreenState();
}

class _SongEditorScreenState extends ConsumerState<SongEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _artist = TextEditingController();
  final _key = TextEditingController();
  final _capo = TextEditingController();
  final _tempo = TextEditingController();
  final _youtube = TextEditingController();
  final _tags = TextEditingController();
  final _body = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _preview = false;
  bool _notFound = false;

  bool get _isEditing => widget.songId != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _load();
    } else {
      _loading = false;
      _body.text = _starterBody.trim();
      _key.text = 'G';
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _artist.dispose();
    _key.dispose();
    _capo.dispose();
    _tempo.dispose();
    _youtube.dispose();
    _tags.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final song = await ref
        .read(songRepositoryProvider)
        .getSong(widget.songId!);
    if (!mounted) return;
    if (song == null) {
      setState(() {
        _loading = false;
        _notFound = true;
      });
      return;
    }
    _title.text = song.title;
    _artist.text = song.artist;
    _key.text = song.originalKey;
    _capo.text = song.capo == 0 ? '' : '${song.capo}';
    _tempo.text = song.tempo?.toString() ?? '';
    _youtube.text = song.youtubeUrl;
    _tags.text = song.tags;
    _body.text = song.body;
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(_isEditing ? 'Edit song' : 'New song')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_notFound) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('This song no longer exists.')),
      );
    }

    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit song' : 'New song'),
        actions: [
          if (_isEditing)
            IconButton(
              tooltip: 'Delete song',
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline),
            ),
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text('Save'),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
          children: [
            TextFormField(
              controller: _title,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Title',
                hintText: 'e.g. Wonderwall',
              ),
              validator: (value) =>
                  value == null || value.trim().isEmpty
                  ? 'Give the song a title'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _artist,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Artist',
                hintText: 'e.g. Oasis',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _key,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Key',
                      hintText: 'G, Am, F#m',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _capo,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Capo',
                      hintText: '0',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _tempo,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'BPM',
                      hintText: '—',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _youtube,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'YouTube link (optional)',
                hintText: 'https://youtube.com/watch?v=…',
                prefixIcon: Icon(Icons.play_circle_outline),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _tags,
              decoration: const InputDecoration(
                labelText: 'Tags (optional)',
                hintText: 'rock, acoustic, campfire',
                prefixIcon: Icon(Icons.tag),
              ),
            ),
            const SizedBox(height: 26),
            Row(
              children: [
                Text(
                  'Chords & lyrics',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                  segments: const [
                    ButtonSegment(
                      value: false,
                      icon: Icon(Icons.edit_outlined, size: 16),
                      label: Text('Write'),
                    ),
                    ButtonSegment(
                      value: true,
                      icon: Icon(Icons.visibility_outlined, size: 16),
                      label: Text('Preview'),
                    ),
                  ],
                  selected: {_preview},
                  onSelectionChanged: (value) =>
                      setState(() => _preview = value.first),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Put chords in brackets right before the syllable: [Am]Hello world. '
              'Use {start_of_verse: Verse 1} … {end_of_verse} to add sections.',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            if (_preview)
              _buildPreview(theme)
            else ...[
              _buildChordToolbar(theme),
              const SizedBox(height: 8),
              TextFormField(
                controller: _body,
                minLines: 16,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  height: 1.45,
                ),
                decoration: const InputDecoration(
                  alignLabelWithHint: true,
                  hintText:
                      '{start_of_verse: Verse 1}\n'
                      '[G]Amazing grace, how [C]sweet the sound\n'
                      '{end_of_verse}',
                ),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: Text(_isEditing ? 'Save changes' : 'Add to library'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview(ThemeData theme) {
    final settings = ref.watch(settingsProvider);
    final document = ref.watch(
      chordDocumentProvider((
        body: _body.text,
        originalKey: _key.text,
        transpose: 0,
        accidentals: settings.accidentals,
      )),
    );

    return Container(
      constraints: const BoxConstraints(minHeight: 240),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: SongSheet(
        document: document,
        fontScale: settings.textScale,
        onChordTap: (chord) => showChordVoicingsSheet(
          context,
          chord: chord,
          instrument: settings.instrument,
        ),
      ),
    );
  }

  Widget _buildChordToolbar(ThemeData theme) {
    const chords = ['C', 'G', 'D', 'A', 'E', 'F', 'Am', 'Em', 'Dm', 'Bm', 'F#m'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final chord in chords)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ActionChip(
                visualDensity: VisualDensity.compact,
                label: Text(
                  chord,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700,
                  ),
                ),
                onPressed: () => _insert('[$chord]'),
              ),
            ),
          ActionChip(
            visualDensity: VisualDensity.compact,
            avatar: const Icon(Icons.playlist_add, size: 16),
            label: const Text('Section'),
            onPressed: _insertSection,
          ),
        ],
      ),
    );
  }

  void _insert(String text) {
    final controller = _body;
    final selection = controller.selection;
    final start = selection.isValid ? selection.start : controller.text.length;
    final end = selection.isValid ? selection.end : controller.text.length;
    controller.value = TextEditingValue(
      text: controller.text.replaceRange(start, end, text),
      selection: TextSelection.collapsed(offset: start + text.length),
    );
    setState(() {});
  }

  void _insertSection() {
    const template =
        '{start_of_verse: Verse 1}\n\n{end_of_verse}\n';
    final controller = _body;
    final selection = controller.selection;
    final start = selection.isValid ? selection.start : controller.text.length;
    final end = selection.isValid ? selection.end : controller.text.length;
    final newText = controller.text.replaceRange(start, end, template);
    final cursor =
        start + template.indexOf('{end_of_verse}');
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: cursor),
    );
    setState(() {});
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);
    final capo = int.tryParse(_capo.text.trim()) ?? 0;
    final tempo = int.tryParse(_tempo.text.trim());
    final draft = SongDraft(
      title: _title.text,
      artist: _artist.text,
      body: _body.text,
      originalKey: _key.text.trim(),
      capo: capo.clamp(0, 12),
      tempo: tempo?.clamp(20, 400),
      youtubeUrl: _youtube.text,
      tags: _tags.text.trim(),
    );

    final id = await ref
        .read(songRepositoryProvider)
        .saveDraft(id: widget.songId, draft: draft);
    if (!mounted) return;

    if (_isEditing) {
      context.pop();
    } else {
      context.pushReplacement('/song/$id');
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete song?'),
        content: Text('"${_title.text}" will be removed from this device.'),
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
    await ref.read(songRepositoryProvider).deleteSong(widget.songId!);
    if (!mounted) return;
    context.go('/');
  }

  static const _starterBody = '''
{start_of_verse: Verse 1}
[G]Your first line goes here
[C]The second line follows
{end_of_verse}

{start_of_chorus: Chorus}
[G]Sing the part everyone remembers
[D]Then bring it back home
{end_of_chorus}
''';
}
