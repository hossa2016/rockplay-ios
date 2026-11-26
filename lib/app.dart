import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens/home_screen.dart';
import 'screens/mode_pick_screen.dart';
import 'services/music_mode.dart';
import 'theme/app_theme.dart';
import 'widgets/embed_overlay.dart';
import 'widgets/rock_decor.dart';

class RockPlayApp extends StatelessWidget {
  const RockPlayApp({super.key});

  static final Map<MusicMode, GlobalKey<NavigatorState>> _navKeys = {
    for (final m in MusicMode.values) m: GlobalKey<NavigatorState>(),
  };

  @override
  Widget build(BuildContext context) {
    // Al cambiar de modo se recrea la navegación (colores, fuentes, textos
    // y géneros) y se vuelve a Inicio. El reproductor oculto de YouTube
    // (EmbedOverlay) queda fuera de esa parte, así la música no se corta.
    return ValueListenableBuilder<MusicMode>(
      valueListenable: MusicModeService.mode,
      builder: (context, mode, _) => MaterialApp(
        // Un navegador nuevo por modo: todas las pantallas se rearman.
        navigatorKey: _navKeys[mode],
        title: MusicModeService.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.dark,
        // Textos del sistema (Atrás, Copiar, Pegar…) en español de Colombia.
        locale: const Locale('es', 'CO'),
        supportedLocales: const [Locale('es', 'CO'), Locale('es')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) => MediaQuery.withClampedTextScaling(
          minScaleFactor: 1.0,
          maxScaleFactor: 1.3,
          child: EmbedOverlay(child: child ?? const SizedBox.shrink()),
        ),
        home: const _IntroGate(),
      ),
    );
  }
}

/// Arranque con marca: el logo aparece con un golpe de escala y un destello,
/// y se desvanece sobre Inicio (que ya carga por debajo).
class _IntroGate extends StatefulWidget {
  const _IntroGate();

  @override
  State<_IntroGate> createState() => _IntroGateState();
}

class _IntroGateState extends State<_IntroGate>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100));
  bool _done = _shown;
  // La animación de entrada solo al abrir la app, no al cambiar de modo.
  static bool _shown = false;

  @override
  void initState() {
    super.initState();
    _shown = true;
    if (_done) {
      _c.value = 1;
      return;
    }
    _c.forward().whenComplete(() {
      if (mounted) setState(() => _done = true);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reduced(context) && !_done) {
      _c.value = 1;
      _done = true;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      // Primera vez: «¿Qué vas a escuchar?» antes de Inicio.
      ValueListenableBuilder<bool>(
        valueListenable: MusicModeService.chosenN,
        builder: (context, chosen, _) =>
            chosen ? const HomeScreen() : const ModePickScreen(),
      ),
      if (!_done)
        AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final t = _c.value;
            // 0–0,45: entra con rebote; 0,45–0,7: destello; 0,7–1: se va.
            final inT = Curves.easeOutBack.transform((t / 0.45).clamp(0.0, 1.0));
            final out = ((t - 0.7) / 0.3).clamp(0.0, 1.0);
            final flash = t > 0.45 && t < 0.7
                ? 1 - ((t - 0.575).abs() / 0.125)
                : 0.0;
            return IgnorePointer(
              child: Opacity(
                opacity: 1 - out,
                child: ColoredBox(
                  color: AppColors.bg,
                  child: Center(
                    child: Transform.scale(
                      scale: (0.6 + 0.4 * inT) * (1 + 0.25 * out),
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.amber
                                  .withValues(alpha: 0.45 * flash.clamp(0.0, 1.0)),
                              blurRadius: 60,
                              spreadRadius: 10,
                            ),
                          ],
                        ),
                        child: const PickLogo(size: 120),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
    ]);
  }
}
