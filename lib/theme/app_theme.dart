import 'package:flutter/material.dart';

import '../services/music_mode.dart';

/// Colores de un modo. Rock = negro, rojo y ámbar. Pulso (todos los
/// géneros) = negro azulado, violeta y cian.
class _Tone {
  final Color bg, surface, surfaceHigh, outline, red, redBtn, redDeep, amber,
      textDim, textFaint, redText, redSoft, surfaceWarm;
  final List<Color> accent, hero;
  final List<List<Color>> cards;
  final String head;
  const _Tone({
    required this.bg,
    required this.surface,
    required this.surfaceHigh,
    required this.outline,
    required this.red,
    required this.redBtn,
    required this.redDeep,
    required this.amber,
    required this.textDim,
    required this.textFaint,
    required this.redText,
    required this.redSoft,
    required this.surfaceWarm,
    required this.accent,
    required this.hero,
    required this.cards,
    required this.head,
  });
}

const _rock = _Tone(
  bg: Color(0xFF0A0A0D),
  surface: Color(0xFF14141A),
  surfaceHigh: Color(0xFF1E1E26),
  outline: Color(0xFF2B2B35),
  red: Color(0xFFE5332E),
  redBtn: Color(0xFFC92B26),
  redDeep: Color(0xFF7A1411),
  amber: Color(0xFFFFB02E),
  textDim: Color(0xFFA6A6B2),
  textFaint: Color(0xFF8A8A98),
  redText: Color(0xFFFF5A52),
  redSoft: Color(0xFFF08A7E),
  surfaceWarm: Color(0xFF1A1014),
  accent: [Color(0xFFE5332E), Color(0xFFB3201B)],
  hero: [Color(0xFFB3201B), Color(0xFF5A0F0D), Color(0xFF1A1014)],
  cards: [
    [Color(0xFFC2331A), Color(0xFF2C0A05)],
    [Color(0xFF4A4A56), Color(0xFF16161C)],
    [Color(0xFF7A1411), Color(0xFF1A1014)],
    [Color(0xFF8A5A2A), Color(0xFF241608)],
    [Color(0xFF8A2A24), Color(0xFF2A0D0B)],
    [Color(0xFF5A5A66), Color(0xFF1C1C22)],
    [Color(0xFF6B2A3A), Color(0xFF220A12)],
    [Color(0xFF7A6A2A), Color(0xFF241E08)],
  ],
  head: 'Oswald',
);

const _pulso = _Tone(
  bg: Color(0xFF0B0B12),
  surface: Color(0xFF15151F),
  surfaceHigh: Color(0xFF1F1F2C),
  outline: Color(0xFF2E2E40),
  red: Color(0xFF6A4CF0),
  redBtn: Color(0xFF5B3FE0),
  redDeep: Color(0xFF2A1F6B),
  amber: Color(0xFF2EC5D3),
  textDim: Color(0xFFA9A9BC),
  textFaint: Color(0xFF8D8DA3),
  redText: Color(0xFFB8A8FF),
  redSoft: Color(0xFFCFC4FF),
  surfaceWarm: Color(0xFF141429),
  accent: [Color(0xFF6A4CF0), Color(0xFF4B33C4)],
  hero: [Color(0xFF5B3FE0), Color(0xFF2A1F6B), Color(0xFF141429)],
  cards: [
    [Color(0xFF5B3FE0), Color(0xFF15103A)],
    [Color(0xFF17707A), Color(0xFF07262A)],
    [Color(0xFF9B3FB5), Color(0xFF2A0F33)],
    [Color(0xFF3A5BD9), Color(0xFF0E1640)],
    [Color(0xFFC0407A), Color(0xFF330F22)],
    [Color(0xFF4A4A60), Color(0xFF16161E)],
    [Color(0xFF1F7A5E), Color(0xFF0A2A20)],
    [Color(0xFF7A5AE0), Color(0xFF1C1440)],
  ],
  head: 'SpaceGrotesk',
);

_Tone get _t => MusicModeService.general ? _pulso : _rock;

/// Paleta de la app. Cambia con el modo de música (ver [MusicModeService]).
class AppColors {
  AppColors._();

  static Color get bg => _t.bg;
  static Color get surface => _t.surface;
  static Color get surfaceHigh => _t.surfaceHigh;
  static Color get outline => _t.outline;
  /// Acento principal (rojo en rock, violeta en Pulso).
  static Color get red => _t.red;
  /// Acento para botones con texto blanco (contraste ≥ 4,5:1).
  static Color get redBtn => _t.redBtn;
  static Color get redDeep => _t.redDeep;
  /// Acento secundario (ámbar en rock, cian en Pulso).
  static Color get amber => _t.amber;
  static const Color text = Color(0xFFF4F4F6);
  /// Texto de cuerpo un poco más suave que [text].
  static const Color textBody = Color(0xFFD0D0D8);
  static Color get textDim => _t.textDim;
  /// Texto terciario. Sigue pasando AA (≈4,6:1 sobre [bg]).
  static Color get textFaint => _t.textFaint;
  /// Acento para texto e iconos sobre superficies oscuras (AA).
  static Color get redText => _t.redText;
  static Color get redSoft => _t.redSoft;
  static Color get surfaceWarm => _t.surfaceWarm;
  static Color get borderAccent => _t.amber.withValues(alpha: 0.20);
  static const Color borderSubtle = Color(0x1FFFFFFF);
  static const Color scrim = Color(0x66000000);
  static Color get amberTint => _t.amber.withValues(alpha: 0.10);
  static Color get amberLine => _t.amber.withValues(alpha: 0.35);
  /// Línea de acento sobre la barra de navegación.
  static Color get navLine => _t.red.withValues(alpha: 0.40);

  static LinearGradient get accent => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: _t.accent,
      );

  static LinearGradient get heroGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: _t.hero,
        stops: const [0, 0.55, 1],
      );

  /// Velo inferior para que el texto se lea sobre degradados de color.
  static const LinearGradient bottomScrim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x00000000), Color(0x40000000)],
  );
}

/// Única paleta de tarjetas (mixes, géneros, ánimos).
class AppPalettes {
  AppPalettes._();
  static List<Color> get fire => _t.cards[0];
  static List<Color> get graphite => _t.cards[1];
  static List<Color> get wine => _t.cards[2];
  static List<Color> get amber => _t.cards[3];
  static List<Color> get rust => _t.cards[4];
  static List<Color> get steel => _t.cards[5];
  static List<Color> get burgundy => _t.cards[6];
  static List<Color> get brass => _t.cards[7];

  static List<List<Color>> get cards => _t.cards;
}

/// Escala tipográfica: Oswald (rock) o Space Grotesk (Pulso) en títulos,
/// Roboto en cuerpo.
class AppType {
  AppType._();
  static const double display = 32;
  static const double headline = 26;
  static const double title = 22;
  static const double titleSm = 18;
  static const double body = 15;
  static const double bodySm = 14;
  static const double label = 13;
  static const double caption = 12;
  static const double micro = 11;

  /// Familia de los títulos según el modo.
  static String get head => _t.head;

  /// Título grande de marca.
  static TextStyle oswald(double size,
          {Color color = AppColors.text, double height = 1.05}) =>
      TextStyle(
        fontFamily: head,
        fontSize: size,
        height: height,
        color: color,
        fontWeight: FontWeight.w700,
        fontVariations: const [FontVariation('wght', 700)],
        letterSpacing: MusicModeService.general ? -0.3 : 0.5,
      );

  /// Etiqueta sobre tarjetas de color (rojo o violeta): ámbar claro en
  /// rock y cian claro en Pulso, para pasar 4,5:1 en todo el degradado.
  static TextStyle get overlineOnAccent => overline.copyWith(
      color: MusicModeService.general
          ? const Color(0xFFB5F1F6)
          : const Color(0xFFFFD27A));

  /// Etiqueta en mayúsculas espaciadas (ej. TU MIX).
  static TextStyle get overline => TextStyle(
        fontSize: caption,
        letterSpacing: 1.6,
        fontWeight: FontWeight.w800,
        color: AppColors.amber,
      );
}

class AppSpace {
  AppSpace._();
  static const double xs = 4, sm = 8, md = 12, lg = 16, xl = 20, xxl = 24, xxxl = 32;
}

class AppRadius {
  AppRadius._();
  /// Carátula en lista = sm, tarjetas = lg, hero y banners = xl.
  static const double xs = 4, sm = 8, md = 12, lg = 16, xl = 24, pill = 999;
}

class AppShadow {
  AppShadow._();
  static const List<BoxShadow> card = [
    BoxShadow(color: Color(0x73000000), blurRadius: 18, offset: Offset(0, 6)),
  ];
  static List<BoxShadow> get glow => [
        BoxShadow(
            color: AppColors.red.withValues(alpha: 0.45),
            blurRadius: 28,
            offset: const Offset(0, 10)),
      ];
}

class AppMotion {
  AppMotion._();
  static const Duration fast = Duration(milliseconds: 180);
  static const Duration base = Duration(milliseconds: 260);
  static const Duration slow = Duration(milliseconds: 500);

  /// true si el sistema pidió reducir animaciones.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  static Duration of(BuildContext context, Duration d) =>
      reduced(context) ? Duration.zero : d;
}

class AppTheme {
  AppTheme._();

  static ThemeData dark() {
    final scheme = ColorScheme.dark(
      primary: AppColors.red,
      onPrimary: Colors.white,
      secondary: AppColors.amber,
      onSecondary: Colors.black,
      surface: AppColors.surface,
      onSurface: AppColors.text,
      error: Color(0xFFFF6B5E),
      outline: AppColors.outline,
    );

    final base = ThemeData(brightness: Brightness.dark, useMaterial3: true)
        .textTheme
        .apply(bodyColor: AppColors.text, displayColor: AppColors.text);

    TextStyle? osw(TextStyle? t, double ls) => t?.copyWith(
          fontFamily: AppType.head,
          fontWeight: FontWeight.w700,
          fontVariations: const [FontVariation('wght', 700)],
          // Space Grotesk ya es ancha: sin espaciado extra en Pulso.
          letterSpacing: MusicModeService.general ? -0.2 : ls,
        );

    final textTheme = base.copyWith(
      displaySmall: osw(base.displaySmall, 0.5),
      headlineMedium: osw(base.headlineMedium, 0.5),
      headlineSmall: osw(base.headlineSmall, 0.3),
      titleLarge: osw(base.titleLarge, 1.2),
      titleMedium: base.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      labelLarge: base.labelLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      ),
    );

    return ThemeData(
      // Onda simple en vez del destello de Material 3 (se repetía mucho).
      splashFactory: InkRipple.splashFactory,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.bg,
      canvasColor: AppColors.bg,
      textTheme: textTheme,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
        },
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        indicatorColor: MusicModeService.general
            ? const Color(0xFF26214A)
            : AppColors.amber.withValues(alpha: 0.20),
        indicatorShape: const StadiumBorder(),
        height: 68,
        elevation: 0,
        labelTextStyle: const WidgetStatePropertyAll<TextStyle>(
          TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceHigh,
        hintStyle: TextStyle(color: AppColors.textFaint),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          borderSide: BorderSide(color: AppColors.red, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.redBtn,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 50),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      // Chip elegido: ámbar con texto oscuro (11:1). Blanco sobre ámbar
      // daba 1,8:1 y no se leía.
      tabBarTheme: TabBarThemeData(
        labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
        unselectedLabelStyle:
            const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
        labelColor: AppColors.text,
        unselectedLabelColor: AppColors.textDim,
        indicatorColor: AppColors.red,
      ),
            chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceHigh,
        selectedColor: AppColors.amber,
        checkmarkColor: const Color(0xFF14110A),
        side: BorderSide(color: AppColors.outline),
        shape: const StadiumBorder(),
        labelStyle: TextStyle(
          color: WidgetStateColor.resolveWith((st) =>
              st.contains(WidgetState.selected)
                  ? const Color(0xFF14110A)
                  : AppColors.text),
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
      sliderTheme: const SliderThemeData(
        trackHeight: 4,
        activeTrackColor: Colors.white,
        inactiveTrackColor: Color.fromRGBO(255, 255, 255, 0.18),
        thumbColor: Colors.white,
        overlayColor: Color.fromRGBO(255, 255, 255, 0.12),
        thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: RoundSliderOverlayShape(overlayRadius: 16),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: AppColors.red,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surfaceHigh,
        contentTextStyle: const TextStyle(color: AppColors.text),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      ),
      dividerColor: AppColors.outline,
    );
  }
}

/// Limita la letra grande del sistema en piezas densas (pestañas, chips,
/// tarjetas pequeñas, mini player) para que no se corten. El texto normal
/// sigue creciendo hasta 1,3×.
class Dense extends StatelessWidget {
  final Widget child;
  final double max;
  const Dense({super.key, required this.child, this.max = 1.1});

  @override
  Widget build(BuildContext context) =>
      MediaQuery.withClampedTextScaling(maxScaleFactor: max, child: child);
}

/// Alto de una fila horizontal (tarjetas con texto debajo) que crece con
/// la letra grande del sistema, para que el texto no se corte.
double rowHeight(BuildContext context, double base, {double text = 44}) {
  final k = MediaQuery.textScalerOf(context).scale(100) / 100;
  return base + (k - 1).clamp(0.0, 0.5) * text;
}
