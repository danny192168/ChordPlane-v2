import 'package:chord_diagrams/chord_diagrams.dart' show Instrument;
import 'package:chord_pro/chord_pro.dart' show AccidentalPreference;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Overridden in `main()` after loading the preferences instance.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('SharedPreferences were not provided'),
);

@immutable
class AppSettingsState {
  const AppSettingsState({
    this.themeMode = ThemeMode.system,
    this.instrument = Instrument.guitar,
    this.accidentals = AccidentalPreference.sharps,
    this.textScale = 1,
  });

  final ThemeMode themeMode;
  final Instrument instrument;
  final AccidentalPreference accidentals;
  final double textScale;

  AppSettingsState copyWith({
    ThemeMode? themeMode,
    Instrument? instrument,
    AccidentalPreference? accidentals,
    double? textScale,
  }) {
    return AppSettingsState(
      themeMode: themeMode ?? this.themeMode,
      instrument: instrument ?? this.instrument,
      accidentals: accidentals ?? this.accidentals,
      textScale: textScale ?? this.textScale,
    );
  }
}

class SettingsController extends Notifier<AppSettingsState> {
  static const _themeKey = 'settings.themeMode';
  static const _instrumentKey = 'settings.instrument';
  static const _accidentalsKey = 'settings.accidentals';
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
      accidentals: prefs.getString(_accidentalsKey) == 'flats'
          ? AccidentalPreference.flats
          : AccidentalPreference.sharps,
      textScale: (prefs.getDouble(_textScaleKey) ?? 1).clamp(0.7, 2.0),
    );
  }

  void setThemeMode(ThemeMode mode) {
    state = state.copyWith(themeMode: mode);
    _prefs.setString(_themeKey, mode.name);
  }

  void setInstrument(Instrument instrument) {
    state = state.copyWith(instrument: instrument);
    _prefs.setString(_instrumentKey, instrument.name);
  }

  void setAccidentals(AccidentalPreference accidentals) {
    state = state.copyWith(accidentals: accidentals);
    _prefs.setString(_accidentalsKey, accidentals.name);
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
