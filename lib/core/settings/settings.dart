import 'package:chord_diagrams/chord_diagrams.dart' show Instrument;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../chords/chord_detection.dart';

/// Overridden in `main()` after loading the preferences instance.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('SharedPreferences were not provided'),
);

@immutable
class AppSettingsState {
  const AppSettingsState({
    this.themeMode = ThemeMode.system,
    this.instrument = Instrument.guitar,
    this.defaultChordDetectionMode = ChordDetectionMode.auto,
    this.textScale = 1,
  });

  final ThemeMode themeMode;
  final Instrument instrument;

  /// The chord detection mode new songs start with. Each song stores its
  /// own mode, so this only affects songs created from now on.
  final ChordDetectionMode defaultChordDetectionMode;

  final double textScale;

  AppSettingsState copyWith({
    ThemeMode? themeMode,
    Instrument? instrument,
    ChordDetectionMode? defaultChordDetectionMode,
    double? textScale,
  }) {
    return AppSettingsState(
      themeMode: themeMode ?? this.themeMode,
      instrument: instrument ?? this.instrument,
      defaultChordDetectionMode:
          defaultChordDetectionMode ?? this.defaultChordDetectionMode,
      textScale: textScale ?? this.textScale,
    );
  }
}

class SettingsController extends Notifier<AppSettingsState> {
  static const _themeKey = 'settings.themeMode';
  static const _instrumentKey = 'settings.instrument';
  static const _chordModeKey = 'settings.chordDetectionMode';
  static const _legacyDetectBareKey = 'settings.detectBareChords';
  static const _textScaleKey = 'settings.textScale';

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  AppSettingsState build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return AppSettingsState(
      themeMode: _parseThemeMode(prefs.getString(_themeKey)),
      instrument: prefs.getString(_instrumentKey) == 'ukulele'
          ? Instrument.ukulele
          : Instrument.guitar,
      defaultChordDetectionMode: _readChordMode(prefs),
      textScale: (prefs.getDouble(_textScaleKey) ?? 1).clamp(0.7, 2.0),
    );
  }

  /// Reads the chord detection default, migrating the old on/off switch
  /// (`true` → Auto, `false` → Brackets only) the first time.
  static ChordDetectionMode _readChordMode(SharedPreferences prefs) {
    final stored = prefs.getString(_chordModeKey);
    if (stored != null) return ChordDetectionMode.fromStorage(stored);

    final legacy = prefs.getBool(_legacyDetectBareKey);
    if (legacy != null) {
      final mode = legacy
          ? ChordDetectionMode.auto
          : ChordDetectionMode.bracketsOnly;
      prefs.setString(_chordModeKey, mode.storageKey);
      prefs.remove(_legacyDetectBareKey);
      return mode;
    }
    return ChordDetectionMode.auto;
  }

  void setThemeMode(ThemeMode mode) {
    state = state.copyWith(themeMode: mode);
    _prefs.setString(_themeKey, mode.name);
  }

  void setInstrument(Instrument instrument) {
    state = state.copyWith(instrument: instrument);
    _prefs.setString(_instrumentKey, instrument.name);
  }

  void setDefaultChordDetectionMode(ChordDetectionMode mode) {
    state = state.copyWith(defaultChordDetectionMode: mode);
    _prefs.setString(_chordModeKey, mode.storageKey);
  }

  void setTextScale(double scale) {
    final clamped = scale.clamp(0.7, 2.0);
    if ((clamped - state.textScale).abs() < 0.001) return;
    state = state.copyWith(textScale: clamped);
    _prefs.setDouble(_textScaleKey, clamped);
  }

  double autoscrollSpeed(String songId) {
    return (_prefs.getDouble('autoscroll.$songId') ?? 28).clamp(8, 120);
  }

  void setAutoscrollSpeed(String songId, double speed) {
    _prefs.setDouble('autoscroll.$songId', speed.clamp(8, 120));
  }

  static ThemeMode _parseThemeMode(String? raw) {
    return switch (raw) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }
}

final settingsProvider =
    NotifierProvider<SettingsController, AppSettingsState>(
      SettingsController.new,
    );
