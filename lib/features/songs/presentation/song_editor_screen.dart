import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/chords/chord_detection.dart';
import '../../../core/chords/text_diagnostics.dart';
import '../../../core/settings/settings.dart';
import '../../../core/validation/youtube_link.dart';
import '../../community/presentation/publish_song_sheet.dart';
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
  String _tags = '';
  final _body = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _preview = false;
  double _editorScale = 1.0;
  bool _notFound = false;
  bool _publishWhenSaved = false;
  ChordDetectionMode _chordMode = ChordDetectionMode.auto;

  /// Programmatic edits (toolbar inserts, clean-up) and typed edits share one
  /// stack. Flutter's own TextField undo only covers typing, and toolbar
  /// replacements clear it, so the editor keeps its own history instead.
  final List<_BodySnapshot> _history = <_BodySnapshot>[];
  int _historyIndex = -1;
  bool _restoringSnapshot = false;

  bool get _isEditing => widget.songId != null;
  bool get _canUndo => _historyIndex > 0;
  bool get _canRedo => _historyIndex >= 0 && _historyIndex < _history.length - 1;

  void _zoomIn() => setState(
    () => _editorScale = (_editorScale + 0.1).clamp(0.7, 2.0),
  );

  void _zoomOut() => setState(
    () => _editorScale = (_editorScale - 0.1).clamp(0.7, 2.0),
  );

  @override
  void initState() {
    super.initState();
    _body.addListener(_onBodyChanged);
    if (_isEditing) {
      _load();
    } else {
      _chordMode = ref.read(settingsProvider).defaultChordDetectionMode;
      _resetHistory();
      _loading = false;
    }
  }

  @override
  void dispose() {
    _body.removeListener(_onBodyChanged);
    _title.dispose();
    _artist.dispose();
    _key.dispose();
    _capo.dispose();
    _tempo.dispose();
    _youtube.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final song = await ref.read(songRepositoryProvider).getSong(widget.songId!);
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
    _tags = song.tags;
    _body.text = song.body;
    _chordMode = ChordDetectionMode.fromStorage(song.chordDetectionMode);
    _resetHistory();
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

    return _withUndoShortcuts(
      Scaffold(
        appBar: AppBar(
          title: Text(_isEditing ? 'Edit song' : 'New song'),
          actions: [
            IconButton(
              tooltip: 'Undo',
              onPressed: _canUndo ? _undo : null,
              icon: const Icon(Icons.undo),
            ),
            IconButton(
              tooltip: 'Redo',
              onPressed: _canRedo ? _redo : null,
              icon: const Icon(Icons.redo),
            ),
            if (_isEditing)
            IconButton(
              tooltip: 'Delete song',
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline),
            ),
          IconButton(
            tooltip: 'Find hidden characters',
            onPressed: _showHiddenCharacters,
            icon: const Icon(Icons.search_outlined),
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
              validator: (value) => value == null || value.trim().isEmpty
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
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Give the song an artist'
                  : null,
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
                      labelText: 'Key (optional)',
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
              validator: validateYouTubeLink,
            ),
            const SizedBox(height: 26),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Chords & lyrics',
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                  segments: const [
                    ButtonSegment(value: false, label: Text('Write')),
                    ButtonSegment(value: true, label: Text('Preview')),
                  ],
                  selected: {_preview},
                  onSelectionChanged: (value) =>
                      setState(() => _preview = value.first),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: 'Zoom out',
                  visualDensity: VisualDensity.compact,
                  onPressed: _editorScale <= 0.7 ? null : _zoomOut,
                  icon: const Icon(Icons.zoom_out, size: 20),
                ),
                Text(
                  '${(_editorScale * 100).round()}%',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                IconButton(
                  tooltip: 'Zoom in',
                  visualDensity: VisualDensity.compact,
                  onPressed: _editorScale >= 2.0 ? null : _zoomIn,
                  icon: const Icon(Icons.zoom_in, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 4),
            _buildDetectionSelector(theme),
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
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13 * _editorScale,
                  height: 1.45,
                ),
                decoration: const InputDecoration(
                  alignLabelWithHint: true,
                  labelText: 'Lyrics & chords',
                  // Placeholder only — nothing to delete before typing.
                  hintText:
                      '{start_of_verse: Verse 1}\n'
                      '[G]Amazing grace, how [C]sweet the sound\n'
                      '{end_of_verse}',
                ),
              ),
            ],
            if (!_isEditing) ...[
              const SizedBox(height: 20),
              Card(
                margin: EdgeInsets.zero,
                child: SwitchListTile(
                  value: _publishWhenSaved,
                  onChanged: _saving
                      ? null
                      : (value) =>
                          setState(() => _publishWhenSaved = value),
                  secondary: Icon(
                    Icons.public,
                    color: theme.colorScheme.primary,
                  ),
                  title: const Text('Publish to Public Library'),
                  subtitle: const Text(
                    'Save here first, then make a public copy. You will '
                    'confirm the details in the next step.',
                  ),
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
      ),
    );
  }

  Widget _withUndoShortcuts(Widget child) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _undo,
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): _undo,
        const SingleActivator(
          LogicalKeyboardKey.keyZ,
          control: true,
          shift: true,
        ): _redo,
        const SingleActivator(
          LogicalKeyboardKey.keyZ,
          meta: true,
          shift: true,
        ): _redo,
        const SingleActivator(LogicalKeyboardKey.keyY, control: true): _redo,
      },
      child: child,
    );
  }

  void _resetHistory() {
    _history
      ..clear()
      ..add(_BodySnapshot(_body.text, 0, 0));
    _historyIndex = 0;
  }

  void _onBodyChanged() {
    if (_restoringSnapshot || _history.isEmpty || !mounted) return;
    _pushSnapshot();
  }

  void _pushSnapshot() {
    final selection = _body.selection;
    final snapshot = _BodySnapshot(
      _body.text,
      selection.isValid ? selection.start : _body.text.length,
      selection.isValid ? selection.end : _body.text.length,
    );
    if (_historyIndex >= 0 && _history[_historyIndex].text == snapshot.text) {
      return;
    }
    if (_historyIndex < _history.length - 1) {
      _history.removeRange(_historyIndex + 1, _history.length);
    }
    _history.add(snapshot);
    if (_history.length > 200) _history.removeAt(0);
    _historyIndex = _history.length - 1;
    if (mounted) setState(() {});
  }

  void _replaceBody(String text, {required int cursor}) {
    _restoringSnapshot = true;
    _body.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(
        offset: cursor.clamp(0, text.length),
      ),
    );
    _restoringSnapshot = false;
    _pushSnapshot();
  }

  void _applySnapshot(int index) {
    if (index < 0 || index >= _history.length) return;
    final snapshot = _history[index];
    final start = snapshot.selectionStart.clamp(0, snapshot.text.length);
    final end = snapshot.selectionEnd.clamp(start, snapshot.text.length);
    _restoringSnapshot = true;
    _body.value = TextEditingValue(
      text: snapshot.text,
      selection: TextSelection(baseOffset: start, extentOffset: end),
    );
    _restoringSnapshot = false;
    _historyIndex = index;
    setState(() {});
  }

  void _undo() => _applySnapshot(_historyIndex - 1);

  void _redo() => _applySnapshot(_historyIndex + 1);

  /// Lets the user choose how this song's chords are recognized. The
  /// choice is stored with the song, so it survives sharing and imports.
  Widget _buildDetectionSelector(ThemeData theme) {
    final defaultMode = ref.watch(settingsProvider).defaultChordDetectionMode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InputDecorator(
          decoration: const InputDecoration(
            labelText: 'Chord detection',
            isDense: true,
            contentPadding: EdgeInsets.fromLTRB(12, 10, 8, 10),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<ChordDetectionMode>(
              isExpanded: true,
              isDense: true,
              value: _chordMode,
              items: [
                for (final mode in ChordDetectionMode.values)
                  DropdownMenuItem(value: mode, child: Text(mode.label)),
              ],
              onChanged: (mode) {
                if (mode == null) return;
                setState(() => _chordMode = mode);
              },
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${_chordMode.description} '
          '${_chordMode == ChordDetectionMode.chordProOnly ? 'Write chords as [Am] and sections as {start_of_verse: Verse 1}.' : 'Wrap chords in < > (<G> or <G D Em C>) or use ChordPro [Am] brackets; a line of < > groups or starting with > positions chords above the next lyric line.'}'
          '${_chordMode == defaultMode ? '' : ' Default for new songs: ${defaultMode.label}.'}',
          style: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildPreview(ThemeData theme) {
    final settings = ref.watch(settingsProvider);
    final document = ref.watch(
      chordDocumentProvider((
        body: _body.text,
        originalKey: _key.text,
        transpose: 0,
        mode: _chordMode,
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
          color: theme.colorScheme.outlineVariant,
        ),
      ),
      child: SongSheet(
        document: document,
        fontScale: settings.textScale * _editorScale,
        onChordTap: (chord) => showChordVoicingsSheet(
          context,
          chord: chord,
          instrument: settings.instrument,
        ),
      ),
    );
  }

  Widget _buildChordToolbar(ThemeData theme) {
    const chords = [
      'C',
      'G',
      'D',
      'A',
      'E',
      'F',
      'Am',
      'Em',
      'Dm',
      'Bm',
      'F#m',
    ];
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
    _replaceBody(
      controller.text.replaceRange(start, end, text),
      cursor: start + text.length,
    );
  }

  void _insertSection() {
    const template = '{start_of_verse: Verse 1}\n\n{end_of_verse}\n';
    final controller = _body;
    final selection = controller.selection;
    final start = selection.isValid ? selection.start : controller.text.length;
    final end = selection.isValid ? selection.end : controller.text.length;
    _replaceBody(
      controller.text.replaceRange(start, end, template),
      cursor: start + template.indexOf('{end_of_verse}'),
    );
  }

  /// Scans the song body for invisible characters that break chord
  /// detection (non-breaking spaces, zero-width characters, fullwidth
  /// `＞`…), shows what was found, and offers to clean the text in place.
  Future<void> _showHiddenCharacters() async {
    final findings = TextDiagnostics.scan(_body.text);
    final affected = <int>{for (final f in findings) f.line};
    final lines = _body.text.split('\n');
    final report = StringBuffer()
      ..writeln(
        findings.isEmpty
            ? 'No hidden characters found.'
            : '${findings.length} hidden character(s) on '
                  '${affected.length} line(s):',
      );
    for (final lineNumber in affected) {
      report
        ..write('Line $lineNumber: ')
        ..writeln(TextDiagnostics.reveal(lines[lineNumber - 1]));
    }

    final cleaned = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hidden characters'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (findings.isEmpty)
                const Text(
                  'No hidden characters found — the text is clean. If '
                  'pasted chords still are not detected, the problem is '
                  'the format itself: tell me the exact line.',
                )
              else ...[
                Text(
                  '${findings.length} hidden character(s) on '
                  '${affected.length} line(s). These look like normal '
                  'spaces or brackets but are not, and they break chord '
                  'detection:',
                ),
                const SizedBox(height: 12),
                for (final lineNumber in affected)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SelectableText(
                      'Line $lineNumber\n'
                      '${TextDiagnostics.reveal(lines[lineNumber - 1])}',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Clipboard.setData(ClipboardData(text: '$report')),
            child: const Text('Copy report'),
          ),
          if (findings.isNotEmpty)
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Clean text'),
            )
          else
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
        ],
      ),
    );
    if (cleaned ?? false) {
      final cursor = _body.selection.isValid ? _body.selection.start : 0;
      _replaceBody(TextDiagnostics.sanitize(_body.text), cursor: cursor);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Hidden characters removed.')),
        );
      }
    }
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
      chordDetectionMode: _chordMode,
      capo: capo.clamp(0, 12),
      tempo: tempo?.clamp(20, 400),
      youtubeUrl: _youtube.text,
      tags: _tags,
    );

    final repository = ref.read(songRepositoryProvider);
    final id = await repository.saveDraft(id: widget.songId, draft: draft);
    if (!mounted) return;

    // Publishing is opt-in during creation. The local save above is already
    // durable, so a cancelled or failed publish never loses the song.
    if (_publishWhenSaved && !_isEditing) {
      final saved = await repository.getSong(id);
      if (!mounted) return;
      if (saved != null) {
        await showPublishSongSheet(context, ref: ref, song: saved);
      }
      if (!mounted) return;
    }

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
}

@immutable
class _BodySnapshot {
  const _BodySnapshot(this.text, this.selectionStart, this.selectionEnd);

  final String text;
  final int selectionStart;
  final int selectionEnd;
}
