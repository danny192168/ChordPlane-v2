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

class ChordPlaneTheme {
  static const seed = Color(0xFF6C5CE7);

  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.vibrant,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: scheme.surface,
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
        backgroundColor: isDark
            ? scheme.surfaceContainerHighest.withValues(alpha: 0.55)
            : scheme.surfaceContainerLowest,
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
            ? scheme.surfaceContainerHighest.withValues(alpha: 0.45)
            : scheme.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
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
        color: scheme.outlineVariant.withValues(alpha: 0.35),
        space: 1,
      ),
      extensions: [
        isDark
            ? const ChordPlaneColors(
                chord: Color(0xFFB7AEFF),
                chordSurface: Color(0xFF232138),
                sectionLabel: Color(0xFF9C93CF),
                stage: Color(0xFF08080C),
                diagramGrid: Color(0xFFE9E6FF),
                diagramDot: Color(0xFFE9E6FF),
                diagramFingerText: Color(0xFF121016),
              )
            : const ChordPlaneColors(
                chord: Color(0xFF5243C9),
                chordSurface: Color(0xFFEEEAFF),
                sectionLabel: Color(0xFF6C5CE7),
                stage: Color(0xFFF6F4FF),
                diagramGrid: Color(0xFF2B2838),
                diagramDot: Color(0xFF2B2838),
                diagramFingerText: Color(0xFFFFFFFF),
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
