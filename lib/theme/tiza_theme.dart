/// El tema de Tiza en dos superficies opuestas: **papel** en claro y **pizarrón**
/// en oscuro.
///
/// No es decoración gratis. La app va y viene entre dos materiales —lo que
/// fotografiás es un pizarrón, lo que obtenés es una hoja— y el modo oscuro es el
/// único lugar donde eso se puede decir sin escribirlo.
///
/// Las familias tipográficas son las genéricas de la plataforma (`serif`,
/// `monospace`), que Android resuelve a Noto Serif y Roboto Mono. Da contraste
/// tipográfico real sin bajar una sola fuente ni sumar una dependencia.
library;

import 'package:flutter/material.dart';

const String kSerif = 'serif';
const String kMono = 'monospace';

/// Colores con nombre semántico, no con nombre de color.
///
/// Existe como [ThemeExtension] y no como constantes globales para que los
/// widgets no sepan si están sobre papel o sobre pizarra: piden `ink` y reciben
/// tinta marrón o tiza blanca según el modo.
@immutable
class TizaPalette extends ThemeExtension<TizaPalette> {
  const TizaPalette({
    required this.paper,
    required this.panel,
    required this.ink,
    required this.inkMuted,
    required this.inkFaint,
    required this.rule,
    required this.accent,
    required this.accentSoft,
    required this.isChalkboard,
  });

  /// El fondo: la hoja o el pizarrón.
  final Color paper;

  /// Superficies apoyadas sobre el fondo (el panel de métricas, el visor).
  final Color panel;

  /// El trazo principal. Tinta sobre papel, tiza sobre pizarra.
  final Color ink;

  /// Texto secundario: descripciones, etiquetas.
  final Color inkMuted;

  /// Casi al borde de lo legible. Para la leyenda del formato, que tiene que
  /// distinguirse de los datos sin competir con ellos.
  final Color inkFaint;

  /// Hairlines y separadores.
  final Color rule;

  /// Terracota. Se usa con cuentagotas: sólo lo que está activo o medido.
  final Color accent;

  /// Fondo del acento, para píldoras y estados seleccionados.
  final Color accentSoft;

  /// Si la superficie es pizarrón. Los dibujos a mano cambian de trazo según
  /// esto: la tiza raspa, la tinta no.
  final bool isChalkboard;

  static const light = TizaPalette(
    paper: Color(0xFFF6F1E6),
    panel: Color(0xFFFFFCF4),
    ink: Color(0xFF221E18),
    inkMuted: Color(0xFF6E6455),
    inkFaint: Color(0xFFA79C88),
    rule: Color(0xFFDED3BE),
    accent: Color(0xFFB0542F),
    accentSoft: Color(0xFFF0DDD1),
    isChalkboard: false,
  );

  static const dark = TizaPalette(
    paper: Color(0xFF1A201C),
    panel: Color(0xFF212823),
    ink: Color(0xFFEAE5D8),
    inkMuted: Color(0xFF97A197),
    inkFaint: Color(0xFF6B756C),
    rule: Color(0xFF353E37),
    accent: Color(0xFFE08A5C),
    accentSoft: Color(0xFF33291F),
    isChalkboard: true,
  );

  @override
  TizaPalette copyWith({
    Color? paper,
    Color? panel,
    Color? ink,
    Color? inkMuted,
    Color? inkFaint,
    Color? rule,
    Color? accent,
    Color? accentSoft,
    bool? isChalkboard,
  }) {
    return TizaPalette(
      paper: paper ?? this.paper,
      panel: panel ?? this.panel,
      ink: ink ?? this.ink,
      inkMuted: inkMuted ?? this.inkMuted,
      inkFaint: inkFaint ?? this.inkFaint,
      rule: rule ?? this.rule,
      accent: accent ?? this.accent,
      accentSoft: accentSoft ?? this.accentSoft,
      isChalkboard: isChalkboard ?? this.isChalkboard,
    );
  }

  @override
  TizaPalette lerp(TizaPalette? other, double t) {
    if (other == null) return this;
    return TizaPalette(
      paper: Color.lerp(paper, other.paper, t)!,
      panel: Color.lerp(panel, other.panel, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      inkMuted: Color.lerp(inkMuted, other.inkMuted, t)!,
      inkFaint: Color.lerp(inkFaint, other.inkFaint, t)!,
      rule: Color.lerp(rule, other.rule, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      isChalkboard: t < 0.5 ? isChalkboard : other.isChalkboard,
    );
  }
}

extension TizaPaletteAccess on BuildContext {
  /// `context.tiza.ink` en vez de `Theme.of(context).extension<...>()!.ink`.
  TizaPalette get tiza => Theme.of(this).extension<TizaPalette>()!;
}

/// Construye el tema para una de las dos superficies.
ThemeData tizaTheme(Brightness brightness) {
  final palette = brightness == Brightness.dark
      ? TizaPalette.dark
      : TizaPalette.light;

  final scheme = ColorScheme.fromSeed(
    seedColor: palette.accent,
    brightness: brightness,
  ).copyWith(
    surface: palette.paper,
    onSurface: palette.ink,
    primary: palette.accent,
    onPrimary: palette.isChalkboard ? const Color(0xFF20170F) : Colors.white,
    outlineVariant: palette.rule,
  );

  final text = _textTheme(palette);

  return ThemeData(
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: palette.paper,
    textTheme: text,
    extensions: [palette],
    // El splash circular de Material desentona con una superficie de papel.
    splashFactory: InkSparkle.splashFactory,
    dividerTheme: DividerThemeData(
      color: palette.rule,
      thickness: 1,
      space: 1,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: palette.ink,
      contentTextStyle: TextStyle(color: palette.paper, fontSize: 13),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: palette.panel,
      hintStyle: TextStyle(color: palette.inkFaint, fontSize: 14),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: palette.rule),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: palette.rule),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: palette.accent, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: palette.ink,
        foregroundColor: palette.paper,
        minimumSize: const Size(0, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: palette.ink,
        minimumSize: const Size(0, 50),
        side: BorderSide(color: palette.rule),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
        ),
      ),
    ),
  );
}

TextTheme _textTheme(TizaPalette palette) {
  // El serif se reserva para el nombre y los títulos. Si se usa en todo pierde
  // el efecto y encima se lee peor en pantalla chica.
  final display = TextStyle(
    fontFamily: kSerif,
    color: palette.ink,
    fontWeight: FontWeight.w600,
    height: 1.1,
  );

  return TextTheme(
    displaySmall: display.copyWith(fontSize: 34, letterSpacing: -0.5),
    headlineMedium: display.copyWith(fontSize: 26),
    titleMedium: TextStyle(
      color: palette.ink,
      fontSize: 16,
      fontWeight: FontWeight.w600,
      height: 1.3,
    ),
    bodyMedium: TextStyle(color: palette.ink, fontSize: 14, height: 1.45),
    bodySmall: TextStyle(color: palette.inkMuted, fontSize: 13, height: 1.5),
    // Versalitas para las etiquetas del panel de métricas: el `letterSpacing`
    // generoso es lo que las hace leer como rótulo de instrumento y no como
    // texto chico.
    labelSmall: TextStyle(
      color: palette.inkMuted,
      fontSize: 10,
      fontWeight: FontWeight.w600,
      letterSpacing: 1.2,
      height: 1.2,
    ),
  );
}
