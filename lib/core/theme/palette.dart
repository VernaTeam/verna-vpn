import 'package:flutter/material.dart';

/// The colours the app is painted in, taken from the design handoff.
///
/// A [ThemeExtension] rather than a bag of constants. It began as constants and
/// the app could only be dark: every screen named `Palette.background`
/// directly, so a light theme meant an `if` at each of a hundred call sites.
/// Hanging the palette off ThemeData means a widget asks for
/// `context.verna.background` and gets whichever half is in force.
///
/// The names say what a colour is *for*, not what it looks like: [background]
/// is the darkest surface in dark mode and the lightest in light mode. A field
/// called `navy` would have to lie in one of them.
///
/// Values are the design's own tokens, transcribed rather than approximated --
/// the accent is its blue, and green is reserved for "this is working", which
/// is a different statement from "this is the brand".
@immutable
class VernaColors extends ThemeExtension<VernaColors> {
  const VernaColors({
    required this.background,
    required this.surface,
    required this.surfaceSunken,
    required this.chip,
    required this.border,
    required this.borderFaint,
    required this.track,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.textFaint,
    required this.mono,
    required this.accent,
    required this.onAccent,
    required this.ok,
    required this.warn,
    required this.danger,
    required this.okSurface,
    required this.okBorder,
    required this.dangerSurface,
    required this.dangerBorder,
    required this.selectedSurface,
    required this.selectedBorder,
    required this.dotOff,
    required this.navInactive,
    required this.glow,
  });

  /// The page itself.
  final Color background;

  /// Cards and rows sitting on [background].
  final Color surface;

  /// A surface *below* [surface] -- the design uses it for the smaller inset
  /// tiles, which read as recessed rather than raised.
  final Color surfaceSunken;

  /// Flag plates and other filled placeholders.
  final Color chip;

  final Color border;

  /// A quieter border, for dividers inside a card that already has one.
  final Color borderFaint;

  /// The unfilled part of a progress ring or bar.
  final Color track;

  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color textFaint;

  /// Monospaced values -- addresses, codes, throughput.
  final Color mono;

  /// The brand colour, and the colour of anything interactive.
  final Color accent;

  /// Text drawn on top of [accent].
  final Color onAccent;

  /// Connected, working, go. Deliberately not [accent]: "this is our app" and
  /// "your tunnel is carrying traffic" are different claims and the design
  /// keeps them apart.
  final Color ok;

  final Color warn;
  final Color danger;

  final Color okSurface;
  final Color okBorder;
  final Color dangerSurface;
  final Color dangerBorder;

  /// A chosen row.
  final Color selectedSurface;
  final Color selectedBorder;

  /// An unselected radio dot.
  final Color dotOff;

  /// A bottom-bar item that is not the current screen.
  final Color navInactive;

  /// The wash behind the connect ring and on the splash.
  final Color glow;

  static const VernaColors dark = VernaColors(
    background: Color(0xFF0B0D13),
    surface: Color(0xFF11141D),
    surfaceSunken: Color(0xFF0F121A),
    chip: Color(0xFF1A1F2C),
    border: Color(0xFF1F2432),
    borderFaint: Color(0xFF171B26),
    track: Color(0xFF1A1F2C),
    textPrimary: Color(0xFFE8ECF4),
    textSecondary: Color(0xFF8A95AB),
    textMuted: Color(0xFF6B768C),
    textFaint: Color(0xFF5D6779),
    mono: Color(0xFFC3CDDD),
    accent: Color(0xFF5B8CFF),
    onAccent: Color(0xFF08090D),
    ok: Color(0xFF3DDC97),
    warn: Color(0xFFFFB84A),
    danger: Color(0xFFFF6B7D),
    okSurface: Color(0xFF0F2419),
    okBorder: Color(0xFF1F4A38),
    dangerSurface: Color(0xFF170F14),
    dangerBorder: Color(0xFF3A2230),
    selectedSurface: Color(0xFF141A2B),
    selectedBorder: Color(0xFF2F4A86),
    dotOff: Color(0xFF2B3142),
    navInactive: Color(0xFF4B5466),
    glow: Color(0xFF16203A),
  );

  static const VernaColors light = VernaColors(
    background: Color(0xFFFFFFFF),
    surface: Color(0xFFF7F8FC),
    surfaceSunken: Color(0xFFF1F3F9),
    chip: Color(0xFFE7EBF5),
    border: Color(0xFFE2E6F0),
    borderFaint: Color(0xFFEAEDF5),
    track: Color(0xFFE4E8F1),
    textPrimary: Color(0xFF0F1420),
    textSecondary: Color(0xFF5A6478),
    textMuted: Color(0xFF7C8598),
    textFaint: Color(0xFF98A1B3),
    mono: Color(0xFF3A4256),
    accent: Color(0xFF2F5FE0),
    onAccent: Color(0xFFFFFFFF),
    ok: Color(0xFF0F9D63),
    warn: Color(0xFFB5730C),
    danger: Color(0xFFD24558),
    okSurface: Color(0xFFE7F7EF),
    okBorder: Color(0xFFBDE6D2),
    dangerSurface: Color(0xFFFDEEF0),
    dangerBorder: Color(0xFFF3CCD3),
    selectedSurface: Color(0xFFEAF0FF),
    selectedBorder: Color(0xFFA9C0FF),
    dotOff: Color(0xFFC9D0E0),
    navInactive: Color(0xFFA3ABBD),
    glow: Color(0xFFE9EFFE),
  );

  @override
  VernaColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceSunken,
    Color? chip,
    Color? border,
    Color? borderFaint,
    Color? track,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? textFaint,
    Color? mono,
    Color? accent,
    Color? onAccent,
    Color? ok,
    Color? warn,
    Color? danger,
    Color? okSurface,
    Color? okBorder,
    Color? dangerSurface,
    Color? dangerBorder,
    Color? selectedSurface,
    Color? selectedBorder,
    Color? dotOff,
    Color? navInactive,
    Color? glow,
  }) =>
      VernaColors(
        background: background ?? this.background,
        surface: surface ?? this.surface,
        surfaceSunken: surfaceSunken ?? this.surfaceSunken,
        chip: chip ?? this.chip,
        border: border ?? this.border,
        borderFaint: borderFaint ?? this.borderFaint,
        track: track ?? this.track,
        textPrimary: textPrimary ?? this.textPrimary,
        textSecondary: textSecondary ?? this.textSecondary,
        textMuted: textMuted ?? this.textMuted,
        textFaint: textFaint ?? this.textFaint,
        mono: mono ?? this.mono,
        accent: accent ?? this.accent,
        onAccent: onAccent ?? this.onAccent,
        ok: ok ?? this.ok,
        warn: warn ?? this.warn,
        danger: danger ?? this.danger,
        okSurface: okSurface ?? this.okSurface,
        okBorder: okBorder ?? this.okBorder,
        dangerSurface: dangerSurface ?? this.dangerSurface,
        dangerBorder: dangerBorder ?? this.dangerBorder,
        selectedSurface: selectedSurface ?? this.selectedSurface,
        selectedBorder: selectedBorder ?? this.selectedBorder,
        dotOff: dotOff ?? this.dotOff,
        navInactive: navInactive ?? this.navInactive,
        glow: glow ?? this.glow,
      );

  @override
  VernaColors lerp(covariant VernaColors? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return VernaColors(
      background: mix(background, other.background),
      surface: mix(surface, other.surface),
      surfaceSunken: mix(surfaceSunken, other.surfaceSunken),
      chip: mix(chip, other.chip),
      border: mix(border, other.border),
      borderFaint: mix(borderFaint, other.borderFaint),
      track: mix(track, other.track),
      textPrimary: mix(textPrimary, other.textPrimary),
      textSecondary: mix(textSecondary, other.textSecondary),
      textMuted: mix(textMuted, other.textMuted),
      textFaint: mix(textFaint, other.textFaint),
      mono: mix(mono, other.mono),
      accent: mix(accent, other.accent),
      onAccent: mix(onAccent, other.onAccent),
      ok: mix(ok, other.ok),
      warn: mix(warn, other.warn),
      danger: mix(danger, other.danger),
      okSurface: mix(okSurface, other.okSurface),
      okBorder: mix(okBorder, other.okBorder),
      dangerSurface: mix(dangerSurface, other.dangerSurface),
      dangerBorder: mix(dangerBorder, other.dangerBorder),
      selectedSurface: mix(selectedSurface, other.selectedSurface),
      selectedBorder: mix(selectedBorder, other.selectedBorder),
      dotOff: mix(dotOff, other.dotOff),
      navInactive: mix(navInactive, other.navInactive),
      glow: mix(glow, other.glow),
    );
  }
}

extension VernaTheme on BuildContext {
  /// The palette in force. Short because it is read in nearly every build.
  ///
  /// Falls back to dark rather than throwing: a widget built outside a
  /// MaterialApp -- a test, a hot-reload glitch -- should render, not crash.
  VernaColors get verna =>
      Theme.of(this).extension<VernaColors>() ?? VernaColors.dark;
}

/// The two type families the design uses.
///
/// Vazirmatn carries Persian and Latin prose equally well, which matters for an
/// app that ships in both. JetBrains Mono is reserved for values that are read
/// as data rather than language -- timers, addresses, throughput, status codes
/// -- where a fixed advance stops digits from dancing as they change.
class VernaType {
  const VernaType._();

  static const String sans = 'Vazirmatn';
  static const String mono = 'JetBrainsMono';
}
