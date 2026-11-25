import 'package:chord_diagrams/chord_diagrams.dart';
import 'package:flutter/material.dart';

/// Music-specific colours that don't belong in the Material colour scheme.
@immutable
class ChordPlaneColors extends ThemeExtension<ChordPlaneColors> {
  const ChordPlaneColors({
    required this.chord,
    required this.chordSurface,
    required this.sectionLabel,
    required this.stage,
    required this.diagramGrid,
    required this.diagramDot,
    required this.diagramFingerText,
  });

  final Color chord;
  final Color chordSurface;
  final Color sectionLabel;
  final Color stage;
  final Color diagramGrid;
  final Color diagramDot;
  final Color diagramFingerText;

  @override
  ChordPlaneColors copyWith({
    Color? chord,
    Color? chordSurface,
    Color? sectionLabel,
    Color? stage,
    Color? diagramGrid,
    Color? diagramDot,
    Color? diagramFingerText,
  }) {
    return ChordPlaneColors(
      chord: chord ?? this.chord,
      chordSurface: chordSurface ?? this.chordSurface,
      sectionLabel: sectionLabel ?? this.sectionLabel,
      stage: stage ?? this.stage,
      diagramGrid: diagramGrid ?? this.diagramGrid,
      diagramDot: diagramDot ?? this.diagramDot,
      diagramFingerText: diagramFingerText ?? this.diagramFingerText,
    );
  }

  @override
  ChordPlaneColors lerp(ThemeExtension<ChordPlaneColors>? other, double t) {
    if (other is! ChordPlaneColors) return this;
    return ChordPlaneColors(
      chord: Color.lerp(chord, other.chord, t)!,
      chordSurface: Color.lerp(chordSurface, other.chordSurface, t)!,
      sectionLabel: Color.lerp(sectionLabel, other.sectionLabel, t)!,
      stage: Color.lerp(stage, other.stage, t)!,
      diagramGrid: Color.lerp(diagramGrid, other.diagramGrid, t)!,
      diagramDot: Color.lerp(diagramDot, other.diagramDot, t)!,
      diagramFingerText: Color.lerp(
        diagramFingerText,
        other.diagramFingerText,
        t,
      )!,
    );
  }

  static ChordPlaneColors of(BuildContext context) {
    return Theme.of(context).extension<ChordPlaneColors>()!;
  }
}

/// Palette mirrored from the marketing site's token block
/// (`site/src/styles/site.css`): alice-blue paper, near-black ink and the teal
/// family from the logo. Ink buttons carry the primary action, exactly like the
/// site's CTA; teal is reserved for links, focus, selection and the chord layer.
class ChordPlaneTheme {
  // Light surfaces.
  static const _paper = Color(0xFFF2F7FD);
  static const _paperDeep = Color(0xFFE7EFF8);
  static const _header = Color(0xFFFCFDFF);
  static const _raised = Color(0xFFFFFFFF);
  static const _band = Color(0xFFE8F1FA);

  // Light ink.
  static const _ink = Color(0xFF171B1F);
  static const _inkSoft = Color(0xFF555D64);
  static const _inkFaint = Color(0xFF6B737A);
  static const _outline = Color(0xFFB0B5BA);
  static const _outlineVariant = Color(0xFFD8DDE2);

  // Dark surfaces.
  static const _paperDark = Color(0xFF0B0F12);
  static const _deepDark = Color(0xFF080B0E);
  static const _sheetDark = Color(0xFF101418);
  static const _raisedDark = Color(0xFF14191D);
  static const _containerDark = Color(0xFF1A2027);
  static const _containerHighestDark = Color(0xFF1F262D);

  // Dark ink.
  static const _inkDark = Color(0xFFEDF1F3);
  static const _inkSoftDark = Color(0xFFA3ADB4);
  static const _inkFaintDark = Color(0xFF78838A);
  static const _outlineDark = Color(0xFF4F5356);
  static const _outlineVariantDark = Color(0xFF282C2F);

  // Accent family.
  static const _accent = Color(0xFF2BAFAB);
  static const _accentDeep = Color(0xFF177A76);
  static const _accentLight = Color(0xFF5DD3CF);
  static const _accentWashLight = Color(0x1A2BAFAB);
  static const _accentWashDark = Color(0x1F5DD3CF);

  // Button pair, same as the site's `--btn-bg` / `--btn-ink`.
  static const _btnLight = Color(0xFF171B1F);
  static const _btnInkLight = Color(0xFFFAFAFA);
  static const _btnDark = Color(0xFFEDF1F3);
  static const _btnInkDark = Color(0xFF101418);

  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ColorScheme _scheme(Brightness brightness) {
    if (brightness == Brightness.dark) {
      return const ColorScheme(
        brightness: Brightness.dark,
        primary: _accentLight,
        onPrimary: _paperDark,
        primaryContainer: Color(0xFF123634),
        onPrimaryContainer: Color(0xFFA9EDE9),
        secondary: _accent,
        onSecondary: _paperDark,
        secondaryContainer: Color(0xFF14302F),
        onSecondaryContainer: Color(0xFF8FE6E1),
        tertiary: _accentLight,
        onTertiary: _paperDark,
        tertiaryContainer: Color(0xFF14302F),
        onTertiaryContainer: Color(0xFF8FE6E1),
        error: Color(0xFFF2B8B5),
        onError: Color(0xFF601410),
        errorContainer: Color(0xFF8C1D18),
        onErrorContainer: Color(0xFFF9DEDC),
        surface: _paperDark,
        onSurface: _inkDark,
        surfaceDim: _deepDark,
        surfaceBright: _containerHighestDark,
        surfaceContainerLowest: _deepDark,
        surfaceContainerLow: _sheetDark,
        surfaceContainer: _raisedDark,
        surfaceContainerHigh: _containerDark,
        surfaceContainerHighest: _containerHighestDark,
        onSurfaceVariant: _inkSoftDark,
        outline: _outlineDark,
        outlineVariant: _outlineVariantDark,
        shadow: Colors.black,
        scrim: Colors.black,
        inverseSurface: _inkDark,
        onInverseSurface: _sheetDark,
        inversePrimary: _accentDeep,
        surfaceTint: Colors.transparent,
      );
    }

    return const ColorScheme(
      brightness: Brightness.light,
      primary: _accentDeep,
      onPrimary: _btnInkLight,
      primaryContainer: Color(0xFFDCF0EE),
      onPrimaryContainer: Color(0xFF0E5C59),
      secondary: _accent,
      onSecondary: _btnInkLight,
      secondaryContainer: Color(0xFFE6F4F3),
      onSecondaryContainer: _accentDeep,
      tertiary: _accent,
      onTertiary: _btnInkLight,
      tertiaryContainer: Color(0xFFE6F4F3),
      onTertiaryContainer: _accentDeep,
      error: Color(0xFFB3261E),
      onError: _btnInkLight,
      errorContainer: Color(0xFFF9DEDC),
      onErrorContainer: Color(0xFF410E0B),
      surface: _paper,
      onSurface: _ink,
      surfaceDim: Color(0xFFE3EAF2),
      surfaceBright: _raised,
      surfaceContainerLowest: _header,
      surfaceContainerLow: _raised,
      surfaceContainer: Color(0xFFF7FAFE),
      surfaceContainerHigh: _paperDeep,
      surfaceContainerHighest: _band,
      onSurfaceVariant: _inkSoft,
      outline: _outline,
      outlineVariant: _outlineVariant,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: _ink,
      onInverseSurface: _paper,
      inversePrimary: _accentLight,
      surfaceTint: Colors.transparent,
    );
  }

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = _scheme(brightness);
    final buttonBg = isDark ? _btnDark : _btnLight;
    final buttonInk = isDark ? _btnInkDark : _btnInkLight;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      // InkSparkle compiles shaders on every tap and is a well-known source
      // of jank on mid-range Android devices; InkRipple is much cheaper.
      splashFactory: InkRipple.splashFactory,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        // The header stays a touch whiter than the page in light mode, the
        // same relationship the site's nav has with its paper.
        backgroundColor: isDark ? scheme.surface : scheme.surfaceContainerLowest,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11.5,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? scheme.surfaceContainerHigh
            : scheme.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 50),
          backgroundColor: buttonBg,
          foregroundColor: buttonInk,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      // The FAB is a primary action too, so it takes the same ink/white CTA
      // pair as FilledButton instead of the default teal container tint.
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: buttonBg,
        foregroundColor: buttonInk,
        extendedTextStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide.none,
        ),
        backgroundColor: scheme.surfaceContainerHigh,
        selectedColor: scheme.secondaryContainer,
        checkmarkColor: scheme.onSecondaryContainer,
        side: BorderSide.none,
        labelStyle: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 12.5,
          color: WidgetStateColor.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? scheme.onSecondaryContainer
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        space: 1,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        modalBackgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.inverseSurface,
        actionTextColor: scheme.inversePrimary,
        contentTextStyle: TextStyle(color: scheme.onInverseSurface),
      ),
      extensions: [
        isDark
            ? const ChordPlaneColors(
                chord: _accentLight,
                chordSurface: _accentWashDark,
                sectionLabel: _inkFaintDark,
                stage: _deepDark,
                diagramGrid: _inkDark,
                diagramDot: _inkDark,
                diagramFingerText: _btnInkDark,
              )
            : const ChordPlaneColors(
                chord: _accentDeep,
                chordSurface: _accentWashLight,
                sectionLabel: _inkFaint,
                stage: _paperDeep,
                diagramGrid: _ink,
                diagramDot: _ink,
                diagramFingerText: _raised,
              ),
      ],
    );
  }
}

/// Applies the diagram palette for the current brightness. The diagrams are
/// rendered natively and share a global colour configuration.
void applyChordDiagramTheme(BuildContext context) {
  final colors = ChordPlaneColors.of(context);
  final scheme = Theme.of(context).colorScheme;
  // The native renderer embeds these strings in SVG fills, so use plain
  // `#RRGGBB`. The sheet surface keeps the diagrams from sitting in black
  // boxes in light mode.
  ChordDiagramsSettings.setBackgroundColor(_hex(scheme.surfaceContainerLow));
  ChordDiagramsSettings.setGridColor(_hex(colors.diagramGrid));
  ChordDiagramsSettings.setDotColor(_hex(colors.diagramDot));
  ChordDiagramsSettings.setDotStrokeColor(_hex(colors.diagramDot));
  ChordDiagramsSettings.setFingerTextColor(_hex(colors.diagramFingerText));
  ChordDiagramsSettings.setMutedColor(_hex(colors.diagramGrid));
  ChordDiagramsSettings.setFretNumberColor(_hex(colors.diagramGrid));
  ChordDiagramsSettings.setTuningColor(_hex(colors.diagramGrid));
  ChordDiagramsSettings.setTitleColor(_hex(colors.diagramGrid));
  ChordDiagramsSettings.setHideTitle(false);
  ChordDiagramsSettings.setHideTuning(true);
}

String _hex(Color color) {
  final argb = color.toARGB32();
  final rgb = argb & 0xFFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}
