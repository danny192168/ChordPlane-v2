/// How plain chord input is recognized when a song body is parsed.
///
/// The parser always understands ChordPro `[Am]` brackets and `{…}`
/// directives; the modes control which of the lenient plain-text formats
/// are rewritten into ChordPro before parsing.
enum ChordDetectionMode {
  /// Everything: chord-only lines above lyrics, bare chord words inside
  /// lyric lines, `<…>` groups, `>`-marked rows and plain section headers.
  auto,

  /// Ultimate-Guitar-style chord rows above lyrics, `<…>` groups and
  /// `>`-marked rows — but bare chord words inside lyric lines are left
  /// as text, so lyrics containing "A", "Am" or "G" stay intact.
  ultimateGuitar,

  /// Only explicitly marked chord input: `<G>`, `<G D Em>` groups,
  /// `>`-prefixed chord rows and ChordPro `[Am]` brackets. Bare chord
  /// rows and bare chord words are left as typed.
  bracketsOnly,

  /// ChordPro only: `[Am]` brackets and `{…}` directives. The body is
  /// sanitized but otherwise not rewritten — every other syntax is text.
  chordProOnly;

  /// Whether chord-only rows above lyrics are picked up as chords.
  bool get detectChordRows =>
      this == ChordDetectionMode.auto ||
      this == ChordDetectionMode.ultimateGuitar;

  /// Whether bare chord words inside lyric lines are wrapped as chords.
  bool get detectInlineBare => this == ChordDetectionMode.auto;

  /// Whether the plain-text formats are rewritten at all.
  bool get rewritesPlainText => this != ChordDetectionMode.chordProOnly;

  /// Stable identifier used in the database, in shared song bundles and
  /// in the persisted app setting. Never rename these.
  String get storageKey => switch (this) {
    ChordDetectionMode.auto => 'auto',
    ChordDetectionMode.ultimateGuitar => 'ug',
    ChordDetectionMode.bracketsOnly => 'brackets',
    ChordDetectionMode.chordProOnly => 'chordpro',
  };

  /// Short label for selectors.
  String get label => switch (this) {
    ChordDetectionMode.auto => 'Auto',
    ChordDetectionMode.ultimateGuitar => 'Ultimate Guitar',
    ChordDetectionMode.bracketsOnly => 'Brackets only',
    ChordDetectionMode.chordProOnly => 'ChordPro only',
  };

  /// One-line explanation for selectors and help text.
  String get description => switch (this) {
    ChordDetectionMode.auto =>
      'Chord rows above lyrics, bare chord words, <G> groups, > rows and '
          '[Am] brackets are all recognized.',
    ChordDetectionMode.ultimateGuitar =>
      'Chord rows above lyrics are recognized, but bare words inside lyrics '
          'are never turned into chords.',
    ChordDetectionMode.bracketsOnly =>
      'Only <G> groups, > rows and [Am] brackets count — nothing bare is '
          'guessed.',
    ChordDetectionMode.chordProOnly =>
      '[Am] brackets and {…} directives only. Every other format is shown as '
          'typed.',
  };

  /// Parses a stored identifier, accepting both [storageKey] values and the
  /// enum names. Anything unknown falls back to [ChordDetectionMode.auto].
  static ChordDetectionMode fromStorage(String? raw) {
    final value = raw?.trim().toLowerCase();
    return switch (value) {
      'ug' ||
      'ultimate-guitar' ||
      'ultimateguitar' => ChordDetectionMode.ultimateGuitar,
      'brackets' ||
      'bracketsonly' ||
      'brackets-only' => ChordDetectionMode.bracketsOnly,
      'chordpro' ||
      'chordproonly' ||
      'chordpro-only' => ChordDetectionMode.chordProOnly,
      _ => ChordDetectionMode.auto,
    };
  }
}
