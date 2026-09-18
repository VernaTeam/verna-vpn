import 'package:flutter/material.dart';

/// The colours the app is painted in, taken from the Aurora design handoff.
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
/// Values are the design's own tokens, transcribed rather than approximated.
/// Where the design writes `rgba(255,255,255,.07)` the alpha is kept rather
/// than flattened against the card underneath, because the same token sits on
/// three different surfaces and flattening it would need three constants.
@immutable
class VernaColors extends ThemeExtension<VernaColors> {
  const VernaColors({
    required this.background,
    required this.surface,
    required this.surfaceSunken,
    required this.chip,
    required this.border,
    required this.borderFaint,
    required this.borderStrong,
    required this.track,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.textFaint,
    required this.mono,
    required this.accent,
    required this.accentBlue,
    required this.accentSoft,
    required this.onAccent,
    required this.ok,
    required this.warn,
    required this.danger,
    required this.okSurface,
    required this.okBorder,
    required this.warnSurface,
    required this.dangerSurface,
    required this.dangerBorder,
    required this.selectedSurface,
    required this.selectedBorder,
    required this.dotOff,
    required this.navInactive,
    required this.glow,
    required this.mapSea,
    required this.mapLand,
    required this.mapHighlight,
    required this.mapStroke,
    required this.auraOffInner,
    required this.auraOffMid,
    required this.auraOffOuter,
    required this.auraOffInk,
    required this.shadow,
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

  /// The design's `lineHi`: a border meant to be seen, on a selected row or a
  /// control that is currently accepting input.
  final Color borderStrong;

  /// The unfilled part of a progress ring or bar.
  final Color track;

  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color textFaint;

  /// Monospaced values -- addresses, codes, throughput.
  final Color mono;

  /// The brand colour, and the colour of anything interactive. Cyan in Aurora.
  final Color accent;

  /// The far end of the accent gradient. Never used alone for text: it is the
  /// blue that cyan runs into across a filled surface.
  final Color accentBlue;

  /// A wash of [accent], for the bubble behind an active nav item and for
  /// chips that are accented rather than neutral.
  final Color accentSoft;

  /// Text drawn on top of [accent].
  final Color onAccent;

  /// Connected, working, go.
  ///
  /// In Aurora this *is* the accent cyan, unlike the previous palette which
  /// kept them apart. The design makes cyan mean protected everywhere -- the
  /// aura, the ring, the map highlight and the pin -- so a separate green
  /// would be a second word for the same thing.
  final Color ok;

  final Color warn;
  final Color danger;

  final Color okSurface;
  final Color okBorder;
  final Color warnSurface;
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

  /// The map's water, its countries, the country being connected through, and
  /// the hairline between them.
  final Color mapSea;
  final Color mapLand;
  final Color mapHighlight;
  final Color mapStroke;

  /// The three stacked half-ellipses behind the power button while the tunnel
  /// is down, and the ink that sits on them.
  ///
  /// Only the off state is in the palette: the design gives connecting,
  /// connected and failed the same colours in both themes, because those are
  /// state colours rather than surface colours. They live in the aura widget.
  final Color auraOffInner;
  final Color auraOffMid;
  final Color auraOffOuter;
  final Color auraOffInk;

  /// The card shadow, already carrying its own alpha.
  final Color shadow;

  static const VernaColors dark = VernaColors(
    background: Color(0xFF0A1020),
    surface: Color(0xFF131B2E),
    surfaceSunken: Color(0xFF0F1626),
    chip: Color(0xFF1A2338),
    border: Color(0x12FFFFFF),
    borderFaint: Color(0x0BFFFFFF),
    borderStrong: Color(0x29FFFFFF),
    track: Color(0x12FFFFFF),
    textPrimary: Color(0xFFEAF1FB),
    textSecondary: Color(0xFF9AA8C2),
    textMuted: Color(0xFF8B98B2),
    textFaint: Color(0xFF6B7791),
    mono: Color(0xFFC3CDDD),
    accent: Color(0xFF35E0E8),
    accentBlue: Color(0xFF2B7FFF),
    accentSoft: Color(0x2135E0E8),
    onAccent: Color(0xFFFFFFFF),
    ok: Color(0xFF35E0E8),
    warn: Color(0xFFFFC061),
    danger: Color(0xFFFF6B8A),
    okSurface: Color(0x2135E0E8),
    okBorder: Color(0x5935E0E8),
    warnSurface: Color(0x24FFC061),
    dangerSurface: Color(0x21FF6B8A),
    dangerBorder: Color(0x59FF6B8A),
    selectedSurface: Color(0x1A35E0E8),
    selectedBorder: Color(0x8C35E0E8),
    dotOff: Color(0xFF2B3654),
    navInactive: Color(0xFF7B87A3),
    glow: Color(0x802B7FFF),
    mapSea: Color(0xFF101828),
    mapLand: Color(0xFF2B3A55),
    mapHighlight: Color(0xFF46DAE2),
    mapStroke: Color(0x14FFFFFF),
    auraOffInner: Color(0xFF182034),
    auraOffMid: Color(0xFF202A43),
    auraOffOuter: Color(0xFF2A3654),
    auraOffInk: Color(0x6BFFFFFF),
    shadow: Color(0xF2000000),
  );

  static const VernaColors light = VernaColors(
    background: Color(0xFFF7F9FD),
    surface: Color(0xFFFFFFFF),
    surfaceSunken: Color(0xFFF2F5FB),
    chip: Color(0xFFE8EDF7),
    border: Color(0x17101A30),
    borderFaint: Color(0x0F101A30),
    borderStrong: Color(0x33101A30),
    track: Color(0xFFE6EAF3),
    textPrimary: Color(0xFF0D1526),
    textSecondary: Color(0xFF4F5A70),
    textMuted: Color(0xFF5E6A80),
    textFaint: Color(0xFF7C8699),
    mono: Color(0xFF3A4256),
    accent: Color(0xFF0E8F9C),
    accentBlue: Color(0xFF1F5FDB),
    accentSoft: Color(0x1A0E8F9C),
    onAccent: Color(0xFFFFFFFF),
    ok: Color(0xFF0E8F9C),
    warn: Color(0xFFA9700C),
    danger: Color(0xFFCF3F60),
    okSurface: Color(0x1A0E8F9C),
    okBorder: Color(0x4D0E8F9C),
    warnSurface: Color(0x1FA9700C),
    dangerSurface: Color(0x1ACF3F60),
    dangerBorder: Color(0x4DCF3F60),
    selectedSurface: Color(0x140E8F9C),
    selectedBorder: Color(0x800E8F9C),
    dotOff: Color(0xFFC9D0E0),
    navInactive: Color(0xFF7C8699),
    glow: Color(0x661F5FDB),
    mapSea: Color(0xFFE4EAF4),
    mapLand: Color(0xFFC2CCDD),
    mapHighlight: Color(0xFF17A9B4),
    mapStroke: Color(0x1F101A30),
    auraOffInner: Color(0xFFDDE5F2),
    auraOffMid: Color(0xFFE8EEF8),
    auraOffOuter: Color(0xFFF2F5FB),
    auraOffInk: Color(0x73101A30),
    shadow: Color(0x66142038),
  );

  /// Cyan into blue, at the design's 140°.
  ///
  /// A getter rather than a constant because the two ends differ by theme, and
  /// a gradient built from the wrong half is the kind of thing that only shows
  /// up in a screenshot someone sends six weeks later.
  LinearGradient get accentGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          accent,
          accentBlue,
        ],
      );

  @override
  VernaColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceSunken,
    Color? chip,
    Color? border,
    Color? borderFaint,
    Color? borderStrong,
    Color? track,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? textFaint,
    Color? mono,
    Color? accent,
    Color? accentBlue,
    Color? accentSoft,
    Color? onAccent,
    Color? ok,
    Color? warn,
    Color? danger,
    Color? okSurface,
    Color? okBorder,
    Color? warnSurface,
    Color? dangerSurface,
    Color? dangerBorder,
    Color? selectedSurface,
    Color? selectedBorder,
    Color? dotOff,
    Color? navInactive,
    Color? glow,
    Color? mapSea,
    Color? mapLand,
    Color? mapHighlight,
    Color? mapStroke,
    Color? auraOffInner,
    Color? auraOffMid,
    Color? auraOffOuter,
    Color? auraOffInk,
    Color? shadow,
  }) =>
      VernaColors(
        background: background ?? this.background,
        surface: surface ?? this.surface,
        surfaceSunken: surfaceSunken ?? this.surfaceSunken,
        chip: chip ?? this.chip,
        border: border ?? this.border,
        borderFaint: borderFaint ?? this.borderFaint,
        borderStrong: borderStrong ?? this.borderStrong,
        track: track ?? this.track,
        textPrimary: textPrimary ?? this.textPrimary,
        textSecondary: textSecondary ?? this.textSecondary,
        textMuted: textMuted ?? this.textMuted,
        textFaint: textFaint ?? this.textFaint,
        mono: mono ?? this.mono,
        accent: accent ?? this.accent,
        accentBlue: accentBlue ?? this.accentBlue,
        accentSoft: accentSoft ?? this.accentSoft,
        onAccent: onAccent ?? this.onAccent,
        ok: ok ?? this.ok,
        warn: warn ?? this.warn,
        danger: danger ?? this.danger,
        okSurface: okSurface ?? this.okSurface,
        okBorder: okBorder ?? this.okBorder,
        warnSurface: warnSurface ?? this.warnSurface,
        dangerSurface: dangerSurface ?? this.dangerSurface,
        dangerBorder: dangerBorder ?? this.dangerBorder,
        selectedSurface: selectedSurface ?? this.selectedSurface,
        selectedBorder: selectedBorder ?? this.selectedBorder,
        dotOff: dotOff ?? this.dotOff,
        navInactive: navInactive ?? this.navInactive,
        glow: glow ?? this.glow,
        mapSea: mapSea ?? this.mapSea,
        mapLand: mapLand ?? this.mapLand,
        mapHighlight: mapHighlight ?? this.mapHighlight,
        mapStroke: mapStroke ?? this.mapStroke,
        auraOffInner: auraOffInner ?? this.auraOffInner,
        auraOffMid: auraOffMid ?? this.auraOffMid,
        auraOffOuter: auraOffOuter ?? this.auraOffOuter,
        auraOffInk: auraOffInk ?? this.auraOffInk,
        shadow: shadow ?? this.shadow,
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
      borderStrong: mix(borderStrong, other.borderStrong),
      track: mix(track, other.track),
      textPrimary: mix(textPrimary, other.textPrimary),
      textSecondary: mix(textSecondary, other.textSecondary),
      textMuted: mix(textMuted, other.textMuted),
      textFaint: mix(textFaint, other.textFaint),
      mono: mix(mono, other.mono),
      accent: mix(accent, other.accent),
      accentBlue: mix(accentBlue, other.accentBlue),
      accentSoft: mix(accentSoft, other.accentSoft),
      onAccent: mix(onAccent, other.onAccent),
      ok: mix(ok, other.ok),
      warn: mix(warn, other.warn),
      danger: mix(danger, other.danger),
      okSurface: mix(okSurface, other.okSurface),
      okBorder: mix(okBorder, other.okBorder),
      warnSurface: mix(warnSurface, other.warnSurface),
      dangerSurface: mix(dangerSurface, other.dangerSurface),
      dangerBorder: mix(dangerBorder, other.dangerBorder),
      selectedSurface: mix(selectedSurface, other.selectedSurface),
      selectedBorder: mix(selectedBorder, other.selectedBorder),
      dotOff: mix(dotOff, other.dotOff),
      navInactive: mix(navInactive, other.navInactive),
      glow: mix(glow, other.glow),
      mapSea: mix(mapSea, other.mapSea),
      mapLand: mix(mapLand, other.mapLand),
      mapHighlight: mix(mapHighlight, other.mapHighlight),
      mapStroke: mix(mapStroke, other.mapStroke),
      auraOffInner: mix(auraOffInner, other.auraOffInner),
      auraOffMid: mix(auraOffMid, other.auraOffMid),
      auraOffOuter: mix(auraOffOuter, other.auraOffOuter),
      auraOffInk: mix(auraOffInk, other.auraOffInk),
      shadow: mix(shadow, other.shadow),
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
/// The Aurora handoff asks for Manrope on Latin UI text. This app does not
/// ship it: Vazirmatn sets Latin and Persian equally well, a third family
/// would add roughly 300 KB to an APK that is sideloaded over bad connections,
/// and in a Persian sentence containing a Latin word the two faces would meet
/// inside one line. Weight and size carry the hierarchy instead, which is what
/// the design uses them for anyway.
///
/// JetBrains Mono is kept exactly as the design uses it: values read as data
/// rather than language -- timers, addresses, throughput, status codes --
/// where a fixed advance stops digits from dancing as they change.
class VernaType {
  const VernaType._();

  static const String sans = 'Vazirmatn';
  static const String mono = 'JetBrainsMono';
}
