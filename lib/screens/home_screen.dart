import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;

import 'package:quick_actions/quick_actions.dart';

import '../services/concert_service.dart';
import '../services/stats_service.dart';
import 'concerts_screen.dart';

import '../models/song.dart';
import '../services/artist_info_service.dart';
import '../services/block_service.dart';
import '../services/library_service.dart';
import '../services/mix_service.dart';
import 'song_list_screen.dart';
import '../services/day_part.dart';
import '../services/music_mode.dart';
import '../theme/app_theme.dart';
import '../widgets/cover_art.dart';
import '../widgets/mini_player.dart';
import '../widgets/playback_ui.dart';
import '../widgets/player_route.dart';
import '../widgets/rock_decor.dart';
import '../widgets/section_header.dart';
import '../widgets/state_views.dart';
import 'artist_screen.dart';
import 'assistant_screen.dart';
import 'search_screen.dart';
import 'alarm_ring_screen.dart';
import '../services/alarm_service.dart';
import '../widgets/concerts_card.dart';
import '../widgets/pressable.dart';
import 'library_screen.dart';
import 'search_hub.dart';
import '../services/help_settings.dart';
import 'onboarding_screen.dart';
import 'settings_hub_screen.dart';
import '../services/track_info_service.dart';
import '../services/data_saver.dart';
import '../widgets/app_button.dart';
import '../services/radio_service.dart';
import 'radio_screen.dart';
import '../widgets/nav_signals.dart';
import '../services/backup_service.dart';
import '../services/local_scene.dart';
import '../services/release_watch.dart';
import 'month_card_screen.dart';

/// Contenedor principal: pestañas + mini-reproductor sobre la navegación.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _tab = 0;
  bool _ringOpen = false;

  /// Si hay una alarma sonando, abre su pantalla (al abrir o volver a la app).
  Future<void> _checkAlarm() async {
    if (_ringOpen) return;
    _ringOpen = true;
    final id = await AlarmService.instance.dueAlarm();
    final a = id == null ? null : await AlarmService.instance.byId(id);
    if (a == null || !mounted || AlarmService.instance.ringingId == id) {
      _ringOpen = false;
      return;
    }
    await Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) => AlarmRingScreen(alarm: a)));
    _ringOpen = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkAlarm();
    // Guarda las escuchas pendientes al salir de la app.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      StatsService.instance.flush();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AlarmService.instance.ringRequest.removeListener(_checkAlarm);
    mainTabWant.removeListener(_onTabWant);
    super.dispose();
  }

  /// Atajos al mantener pulsado el ícono de la app.
  void _setupShortcuts() {
    try {
      const qa = QuickActions();
      qa.initialize((type) {
        if (!mounted) return;
        if (type == 'mix') {
          _go(0);
          homeWantAction.value = 'mix';
        } else if (type == 'radio') {
          _go(1);
          searchHubWantMode.value = 2;
        } else if (type == 'asistente') {
          _go(3);
        }
      });
      qa.setShortcutItems(const [
        ShortcutItem(type: 'mix', localizedTitle: 'Tu mix'),
        ShortcutItem(type: 'radio', localizedTitle: 'Radio en vivo'),
        ShortcutItem(type: 'asistente', localizedTitle: 'Asistente'),
      ]);
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _setupShortcuts();
    WidgetsBinding.instance.addObserver(this);
    AlarmService.instance.ringRequest.addListener(_checkAlarm);
    mainTabWant.addListener(_onTabWant);
    HelpSettings.load();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _checkAlarm();
      if (_ringOpen || !mounted) return;
      final seen = await HelpSettings.onboardingSeen();
      if (!seen && mounted) {
        await Navigator.of(context).push(MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) => const OnboardingScreen()));
      }
    });
  }

  void _onTabWant() {
    final t = mainTabWant.value;
    if (t < 0 || !mounted) return;
    mainTabWant.value = -1;
    _go(t);
  }

  void _go(int i) {
    HapticFeedback.selectionClick();
    ScaffoldMessenger.of(context).clearSnackBars();
    setState(() => _tab = i);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _tab == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _go(0);
      },
      child: Scaffold(
        body: IndexedStack(
          index: _tab,
          children: [
            _HomeTab(onNavigate: _go),
            const SearchHub(),
            const LibraryScreen(),
            const AssistantScreen(),
          ],
        ),
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const MiniPlayer(),
            Container(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: AppColors.navLine, width: 1),
                ),
              ),
              child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Dense(child: NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: _go,
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home_rounded),
                  label: 'Inicio',
                ),
                NavigationDestination(
                  icon: Icon(Icons.search_rounded),
                  selectedIcon: Icon(Icons.search_rounded),
                  label: 'Buscar',
                ),
                NavigationDestination(
                  icon: Icon(Icons.library_music_outlined),
                  selectedIcon: Icon(Icons.library_music_rounded),
                  label: 'Mi música',
                ),
                NavigationDestination(
                  icon: Icon(Icons.auto_awesome_outlined),
                  selectedIcon: Icon(Icons.auto_awesome_rounded),
                  label: 'Asistente',
                ),
              ],
            ))),
            ),
          ],
        ),
      ),
    );
  }
}

/// Acción pedida desde un atajo del ícono (ej. 'mix').
final ValueNotifier<String?> homeWantAction = ValueNotifier<String?>(null);

class _HomeTab extends StatefulWidget {
  final ValueChanged<int> onNavigate;
  const _HomeTab({required this.onNavigate});

  @override
  State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab> {
  List<Song> _recent = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    PlaybackUi.instance.libraryRevision.addListener(_load);
    homeWantAction.addListener(_wantAction);
    StopLog.load();
    _load();
  }

  @override
  void dispose() {
    PlaybackUi.instance.libraryRevision.removeListener(_load);
    homeWantAction.removeListener(_wantAction);
    if (_disc == 1) _leaveReleases(); // NUEVO visto al salir de Inicio
    super.dispose();
  }

  void _wantAction() {
    final a = homeWantAction.value;
    if (a == null) return;
    homeWantAction.value = null;
    if (a == 'mix') _playMix();
  }

  Future<void> _load() async {
    List<Song> h = [];
    try {
      h = await LibraryService.instance.history();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _recent = h.take(12).toList();
      _loading = false;
    });
  }

  // Portada nítida: la carátula de Deezer (500 px) en lugar de la miniatura
  // de YouTube ampliada; mientras llega, la miniatura.
  String? _coverFor;
  String _coverHd = '';

  String _sharpCover(Song s) {
    final key = '${s.artist}|${s.title}';
    if (_coverFor != key) {
      _coverFor = key;
      _coverHd = '';
      // La misma fuente que el reproductor (TrackInfoService), para que
      // Inicio y el reproductor muestren la misma carátula.
      TrackInfoService.instance.fetch(s.artist, s.title).then((i) {
        final u = i?.artwork ?? '';
        if (!mounted || _coverFor != key || u.isEmpty) return;
        setState(() => _coverHd = u);
      }).catchError((_) {});
    }
    return _coverHd.isNotEmpty ? _coverHd : s.image;
  }

  String _greeting() {
    final base = switch (dayPart()) {
      DayPart.madrugada => byMode('Todavía despierto', 'Todavía despierto'),
      DayPart.manana => 'Buenos días',
      DayPart.tarde => 'Buenas tardes',
      DayPart.noche => 'Buenas noches',
    };
    final n = PulsoPrefs.userName.value;
    return n.isEmpty ? base : '$base, $n';
  }

  /// Frase grande de portada según la hora (estilo revista).
  String _coverLine() {
    final weekend = DateTime.now().weekday >= DateTime.saturday;
    final g = MusicModeService.general;
    return switch (dayPart()) {
      DayPart.manana => g
          ? (weekend ? 'Mañana\nsin afán' : 'Empieza con\nlo tuyo')
          : (weekend ? 'MAÑANA DE\nCARRETERA' : 'ARRANCA\nCON RIFFS'),
      DayPart.tarde => g
          ? (weekend ? 'Tarde\npara salir' : 'Tu tarde\nsuena así')
          : (weekend ? 'TARDE DE\nCARRETERA' : 'TARDE\nDE GUITARRAS'),
      DayPart.noche => g ? 'Tu noche\nsuena así' : 'NOCHE\nDE RIFFS',
      DayPart.madrugada => g ? 'Madrugada\nen calma' : 'MADRUGADA\nEN CALMA',
    };
  }

  /// Mixes de ánimo ordenados para esta hora: tranquilo de noche, con
  /// energía de mañana, de carretera el fin de semana.
  List<MixDef> _hourMixes() {
    final now = DateTime.now();
    final weekend = now.weekday >= DateTime.saturday;
    final p = dayPart(now);
    final String first;
    if (p == DayPart.madrugada || now.hour >= 22) {
      first = 'Tranquilo';
    } else if (weekend && p != DayPart.noche && now.hour >= 8) {
      first = 'Para manejar';
    } else if (p == DayPart.manana) {
      first = 'Energía';
    } else if (p == DayPart.noche || now.hour >= 17) {
      first = 'Para entrenar';
    } else {
      first = 'Nostalgia';
    }
    final l = List<MixDef>.of(MixService.mood);
    l.sort((x, y) => (x.title == first ? 0 : 1) - (y.title == first ? 0 : 1));
    return l;
  }

  String _hourTitle() {
    return switch (dayPart()) {
      DayPart.madrugada => 'Para esta madrugada',
      DayPart.manana => 'Para esta mañana',
      DayPart.tarde => 'Para esta tarde',
      DayPart.noche => 'Para esta noche',
    };
  }

  Future<List<MixDef>>? _dailyFuture;

  /// 3 o 4 mixes diarios que se renuevan solos cada mañana (5 a. m.).
  MonthSummary? _monthData;

  Future<List<MixDef>> _loadDaily() async {
    // Días 1–10: «Tu mes» como tarjeta dentro de los mixes diarios.
    _monthData = DateTime.now().day <= 10 ? await MonthSummary.previous() : null;
    var arts = <String>[];
    try {
      arts = await MixService.personalArtists();
    } catch (_) {}
    final uniq = <String>[];
    final seen = <String>{};
    for (final a in arts) {
      if (seen.add(a.toLowerCase())) uniq.add(a);
    }
    // Pocos datos: se completa con artistas de arranque del modo hasta 6.
    final mine = uniq.length;
    if (uniq.length < 6) {
      for (final a in MixService.modeSeeds) {
        if (uniq.length >= 6) break;
        if (seen.add(a.toLowerCase())) uniq.add(a);
      }
    }
    // Si dominan los de arranque, se dice con honestidad.
    final starter = mine * 2 < uniq.length;
    final d = DateTime.now().subtract(const Duration(hours: 5));
    final seed = d.year * 400 + d.month * 32 + d.day;
    uniq.shuffle(math.Random(seed));
    final n = uniq.length >= 12 ? 4 : (uniq.length >= 8 ? 3 : 2);
    // Reparto parejo (sin mínimo de 3: con 6 artistas, 3 y 3).
    final per = (uniq.length / n).ceil().clamp(1, 10).toInt();
    return [
      for (var i = 0; i < n; i++)
        if (uniq.skip(i * per).isNotEmpty)
          MixDef(
            'Mix diario ${i + 1}',
            starter
                ? 'Para empezar · se ajusta a lo que escuches'
                : _names(uniq.skip(i * per).take(per).toList()),
            const [Icons.today_rounded, Icons.bolt_rounded, Icons.album_rounded, Icons.graphic_eq_rounded][i % 4],
            AppPalettes.cards[i % AppPalettes.cards.length],
            uniq.skip(i * per).take(per).toList(),
          ),
    ];
  }

  /// «System of a Down, Mudvayne y más».
  static String _names(List<String> a) => a.length <= 1
      ? (a.isEmpty ? '' : a.first)
      : '${a.take(2).join(', ')}${a.length > 2 ? ' y más' : ''}';

  int _dailyDay = -1;

  Widget _dailyRow() {
    // Se renuevan solos al cambiar el día (a las 5 a. m.).
    final day = DateTime.now().subtract(const Duration(hours: 5)).day;
    if (day != _dailyDay) {
      _dailyDay = day;
      _dailyFuture = null;
    }
    _dailyFuture ??= _loadDaily();
    return FutureBuilder<List<MixDef>>(
      future: _dailyFuture,
      builder: (context, snap) {
        final l = snap.data ?? const <MixDef>[];
        if (snap.connectionState != ConnectionState.done) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SectionTitle('Tus mixes diarios'),
            SizedBox(height: rowHeight(context, 176), child: const SkeletonRow(itemWidth: 150, coverHeight: 150)),
          ]);
        }
        // Sin tarjetas no se muestra ni el título.
        if (l.isEmpty) return const SizedBox.shrink();
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SectionTitle('Tus mixes diarios'),
          SizedBox(
          height: rowHeight(context, 176),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            // Primera tarjeta: el mix de la hora (antes una fila aparte).
            itemCount: l.length + 1 + (_monthData != null ? 1 : 0),
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              if (i == 1 && _monthData != null) {
                final m = _monthData!;
                return _MixCard(
                  def: MixDef(byMode('Tu ${m.month} en rock', 'Tu ${m.month}'),
                      '${m.plays} escuchas', Icons.insights_rounded,
                      AppPalettes.cards[3], const []),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => MonthCardScreen(summary: m))),
                );
              }
              if (i > 1 && _monthData != null) i--;
              if (i == 0) {
                final h = _hourMixes().first;
                final m = MixDef(h.title, _hourTitle(), h.icon, h.colors, h.artists);
                return _MixCard(
                  def: m,
                  onTap: () => _openMix(h.title, h.subtitle, h.colors,
                      MixService.buildMix(MixService.pool(h),
                          pick: 70, perArtist: 4, keepOrder: true)),
                );
              }
              final m = l[i - 1];
              return _MixCard(
                def: m,
                photos: true,
                onTap: () => _openMix(m.title, m.subtitle, m.colors,
                    MixService.buildMix(m.artists, pick: 40, perArtist: 6)),
              );
            },
          ),
        ),
        ]);
      },
    );
  }

  Future<_Nudge?>? _nudgeFuture;

  /// Tarjeta del asistente que toma la iniciativa: concierto de una banda
  /// que escuchas, o algo parecido a lo que más suena esta semana.
  Future<_Nudge?> _loadNudge() async {
    try {
      final plays = await StatsService.instance.plays(days: 7);
      final top = StatsService.topArtists(plays, n: 5);
      if (top.isEmpty) return null;
      await ConcertService.instance.ensureLoaded();
      final concerts = ConcertService.instance.state.value.items;
      for (final a in top) {
        final k = a.name.toLowerCase();
        for (final c in concerts) {
          if (!isTribute(c) && c.band.toLowerCase().contains(k)) {
            final city = concertCity(c);
            return _Nudge(
              '${a.name} en ${city.isEmpty ? 'Colombia' : city}',
              '${c.date != null ? '${c.date!.day} ${kMonthsShort[c.date!.month - 1].toLowerCase()}' : (c.when.isEmpty ? 'Fecha por confirmar' : c.when)}${c.venue.isEmpty ? ' · lugar por confirmar' : ' · ${c.venue}'}',
              Icons.confirmation_number_outlined,
              concert: true,
              band: a.name,
            );
          }
        }
      }
      final a = top.first;
      if (a.count < 5) return null;
      return _Nudge(
        '${a.name}, ${a.count}\u00A0veces esta semana',
        byMode('Toca y te armo algo con bandas nuevas',
            'Toca y te armo algo de otros géneros para variar'),
        Icons.auto_awesome_rounded,
        prompt: byMode(
            'Llevo una semana escuchando mucho ${a.name}. Arma una lista parecida pero con bandas que probablemente no conozco.',
            'Llevo una semana escuchando mucho ${a.name}. Arma una lista de otros géneros que combinen con mi gusto, con artistas que probablemente no conozco.'),
      );
    } catch (_) {
      return null;
    }
  }

  Widget _nudgeCard() {
    _nudgeFuture ??= _loadNudge();
    return FutureBuilder<_Nudge?>(
      future: _nudgeFuture,
      builder: (context, snap) {
        final n = snap.data;
        if (n == null || _nudgeClosed) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: Material(
            color: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              side: BorderSide(color: AppColors.outline),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                if (n.concert) {
                  Navigator.of(context).push(MaterialPageRoute<String>(
                      builder: (_) => ConcertsScreen(focusBand: n.band))).then((band) {
                    if (band != null && band.isNotEmpty) _listenBand(band);
                  });
                } else {
                  widget.onNavigate(3);
                  assistantWantPrompt.value = n.prompt;
                }
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 4, 14),
                child: Row(children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle, gradient: AppColors.accent),
                    child: Icon(n.icon, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(n.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: AppType.bodySm,
                                fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text(n.text,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: AppType.label,
                                height: 1.3,
                                color: AppColors.textDim)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Ocultar sugerencia',
                    icon: Icon(Icons.close_rounded,
                        color: AppColors.textDim, size: 20),
                    onPressed: () => setState(() => _nudgeClosed = true),
                  ),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }

  bool _nudgeClosed = false;

  /// Cabecera que se encoge al hacer scroll: frase grande + última portada.
  Widget _sliverHeader(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    const minH = 64.0, maxH = 190.0;
    final cover = _recent.isEmpty ? '' : _sharpCover(_recent.first);
    return SliverAppBar(
      pinned: true,
      automaticallyImplyLeading: false,
      backgroundColor: AppColors.bg,
      surfaceTintColor: Colors.transparent,
      toolbarHeight: minH,
      collapsedHeight: minH,
      expandedHeight: maxH,
      titleSpacing: 16,
      title: Row(children: [
        const PickLogo(size: 34),
        const SizedBox(width: 10),
        ValueListenableBuilder<String>(
            valueListenable: PulsoPrefs.brand,
            builder: (context, b, _) => Text(byMode('ROCKPLAY', b),
                style: AppType.oswald(AppType.title))),
      ]),
      actions: [
        IconButton(
          tooltip: 'Ajustes',
          icon: const Icon(Icons.settings_rounded),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const SettingsHubScreen())),
        ),
        const SizedBox(width: 4),
      ],
      flexibleSpace: LayoutBuilder(builder: (context, box) {
        final t = ((box.maxHeight - minH - top) / (maxH - minH))
            .clamp(0.0, 1.0);
        return Stack(fit: StackFit.expand, children: [
          if (cover.isNotEmpty)
            Positioned(
              right: 20,
              bottom: 16,
              child: Opacity(
                opacity: t,
                child: Transform.rotate(
                  // Pulso: sin girar.
                  angle: MusicModeService.general ? 0 : 0.06,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 350),
                    child: DecoratedBox(
                      key: ValueKey(cover),
                      // Pulso: esquinas de 20 y brillo violeta.
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(
                            MusicModeService.general ? 20 : AppRadius.md),
                        boxShadow: MusicModeService.general
                            ? [
                                BoxShadow(
                                    color: const Color(0xFF6A4CF0)
                                        .withValues(alpha: 0.45),
                                    blurRadius: 24,
                                    offset: const Offset(0, 8)),
                              ]
                            : null,
                      ),
                      child: CoverArt(
                          url: cover,
                          size: 92,
                          radius: MusicModeService.general ? 20 : AppRadius.md,
                          shadow: !MusicModeService.general,
                          seed: _recent.first.artist),
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            left: 20,
            right: cover.isEmpty ? 20 : 128,
            bottom: 16,
            child: Opacity(
              opacity: t,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ValueListenableBuilder<String>(
                      valueListenable: PulsoPrefs.userName,
                      builder: (context, _, __) => Text(
                          _greeting().toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.overline)),
                  const SizedBox(height: 4),
                  Text(_coverLine(),
                      maxLines: 2,
                      style: AppType.oswald(AppType.display, height: 1.0)),
                ],
              ),
            ),
          ),
        ]);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        color: AppColors.red,
        onRefresh: () async {
          setState(() {
            _dailyFuture = null;
            _nudgeFuture = null;
            _nudgeClosed = false;
            _releasesFuture = null;
            _emergingFuture = null;
          });
          await _load();
        },
        child: CustomScrollView(
          slivers: [
            _sliverHeader(context),
            SliverPadding(
              padding: const EdgeInsets.only(top: 8, bottom: 24),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _stopNotice(),
                  _backupNotice(),
                  _personalMix(),
                  const SizedBox(height: 12),
                  _nudgeCard(),
                  _dailyRow(),
                  _quickAccess(),
                  const SizedBox(height: 4),
                  SectionTitle(
                    'Seguir escuchando',
                    actionLabel: _recent.isEmpty ? null : 'Ver historial',
                    onAction: () {
                      widget.onNavigate(2);
                      libraryWantTab.value = 2;
                    },
                  ),
                  _recentSection(),
                  const SizedBox(height: 24),
                  ConcertsCard(onListen: _listenBand),
                  const SectionTitle('Descubrir'),
                  _discoverChips(),
                  const SizedBox(height: 14),
                  _discoverBody(),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  int _disc = 0;

  Widget _discoverChips() {
    final labels = [
      byMode('Bandas nuevas', 'Artistas nuevos'),
      'Lanzamientos',
      'Mixes',
      'Hecho en Colombia',
    ];
    return Dense(child: SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: labels.length,
        separatorBuilder: (context, i) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final on = _disc == i;
          return Semantics(
            button: true,
            selected: on,
            child: GestureDetector(
            onTap: () {
              if (!on) HapticFeedback.selectionClick();
              if (_disc == 1 && i != 1) _leaveReleases();
              setState(() => _disc = i);
            },
            child: AnimatedContainer(
              duration: AppMotion.of(context, AppMotion.fast),
              padding: const EdgeInsets.symmetric(horizontal: 18),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? AppColors.redBtn : AppColors.surfaceHigh,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: on ? null : Border.all(color: AppColors.outline),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(labels[i],
                    style: TextStyle(
                        fontSize: AppType.label,
                        fontWeight: FontWeight.w700,
                        color: on ? Colors.white : AppColors.textDim)),
                // Punto: hay lanzamientos nuevos de tus artistas.
                if (i == 1)
                  ValueListenableBuilder<int>(
                    valueListenable: ReleaseWatch.fresh,
                    builder: (_, n, __) => n == 0
                        ? const SizedBox.shrink()
                        : Semantics(
                            label: n == 1
                                ? 'Hay un lanzamiento nuevo'
                                : 'Hay $n lanzamientos nuevos',
                            child: Container(
                            margin: const EdgeInsets.only(left: 6),
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                                color: AppColors.amber, shape: BoxShape.circle),
                          )),
                  ),
              ]),
            ),
          ));
        },
      ),
    ));
  }

  String _sceneFilter = 'Todo';

  /// «Hecho en Colombia»: la escena local, con filtros de ciudad (rock) o
  /// de género (Pulso).
  Widget _localScene() {
    final mixes = LocalScene.mixes(_sceneFilter);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (final f in LocalScene.filters)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(f),
                    selected: _sceneFilter == f,
                    onSelected: (_) => setState(() => _sceneFilter = f),
                  ),
                ),
            ],
          ),
      ),
      const SizedBox(height: 10),
      SizedBox(
        height: rowHeight(context, 176),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: mixes.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (context, i) {
            final m = mixes[i];
            return _MixCard(
              def: m,
              onTap: () => _openMix(m.title, m.subtitle, m.colors,
                  MixService.buildMix(m.artists, pick: 50, perArtist: 5)),
            );
          },
        ),
      ),
      const SizedBox(height: 8),
    ]);
  }

  Widget _discoverBody() {
    switch (_disc) {
      case 0:
        return _emergingRow();
      case 1:
        return _releasesRow();
      case 3:
        return _localScene();
      default:
        // En Pulso, tus géneros favoritos van primero.
        final gs = List<MixDef>.of(MixService.genre);
        if (MusicModeService.general) {
          final fav = PulsoPrefs.favGenres.value;
          int rank(MixDef d) {
            final i = fav.indexOf(d.title);
            return i < 0 ? 99 : i;
          }
          gs.sort((a, b) => rank(a).compareTo(rank(b)));
        }
        return _mixRow(gs);
    }
  }

  Future<bool>? _backupDue;

  /// Recordatorio de la copia de seguridad (cada 30 días).
  Widget _backupNotice() {
    // Se recalcula al hacer una copia (BackupService.done).
    return ValueListenableBuilder<int>(
      valueListenable: BackupService.done,
      builder: (context, _, __) => _backupNoticeInner(),
    );
  }

  int _backupSeen = -1;

  Widget _backupNoticeInner() {
    if (_backupSeen != BackupService.done.value) {
      _backupSeen = BackupService.done.value;
      _backupDue = BackupService.shouldRemind();
    }
    return FutureBuilder<bool>(
      future: _backupDue,
      builder: (context, snap) {
        if (snap.data != true) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: AppColors.outline),
            ),
            child: Row(children: [
              Icon(Icons.backup_rounded, color: AppColors.amber),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                    'Haz una copia de seguridad para no perder tus favoritas y listas.',
                    style: TextStyle(fontSize: AppType.label, height: 1.3)),
              ),
              TextButton(
                onPressed: () async {
                  try {
                    await BackupService.export();
                  } catch (_) {}
                },
                child: const Text('Hacer copia'),
              ),
              IconButton(
                tooltip: 'Más tarde',
                icon: const Icon(Icons.close_rounded),
                onPressed: () {
                  BackupService.snooze();
                  setState(() => _backupDue = Future.value(false));
                },
              ),
            ]),
          ),
        );
      },
    );
  }

  Widget _stopNotice() {
    return ValueListenableBuilder<String?>(
      valueListenable: StopLog.last,
      builder: (context, v, _) {
        if (v == null || !v.contains('|')) return const SizedBox.shrink();
        final i = v.indexOf('|');
        final hora = v.substring(0, i);
        final motivo = v.substring(i + 1);
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
            decoration: BoxDecoration(
              color: AppColors.amberTint,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border:
                  Border.all(color: AppColors.amberLine),
            ),
            child: Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('La música se detuvo a las $hora',
                        style: TextStyle(
                            color: AppColors.amber,
                            fontWeight: FontWeight.w800,
                            fontSize: AppType.label)),
                    const SizedBox(height: 2),
                    Text(motivo,
                        style: const TextStyle(fontSize: AppType.label, height: 1.3)),
                  ],
                ),
              ),
              SizedBox(
                width: 48,
                height: 48,
                child: IconButton(
                  tooltip: 'Cerrar aviso',
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: StopLog.clear,
                ),
              ),
            ]),
          ),
        );
      },
    );
  }

  Future<RadioStation?>? _lastRadio;

  /// «Seguir con <última emisora>»; si nunca has oído radio, no se muestra
  /// (la radio sigue en Buscar › Radio).
  Widget _quickAccess() {
    // Se recalcula cuando cambia la última emisora.
    return ValueListenableBuilder<int>(
      valueListenable: RadioService.instance.lastChanged,
      builder: (context, v, _) {
        if (_lastRadioSeen != v) {
          _lastRadioSeen = v;
          _lastRadio = RadioService.instance.last();
        }
        return _quickInner();
      },
    );
  }

  int _lastRadioSeen = -1;

  Widget _quickInner() {
    return FutureBuilder<RadioStation?>(
      future: _lastRadio,
      builder: (context, snap) {
        final st = snap.data;
        if (st == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: _QuickTile(
            icon: Icons.sensors_rounded,
            label: 'Seguir con ${st.shortName}',
            subtitle: 'Radio en vivo',
            onTap: () => playStation(context, st),
          ),
        );
      },
    );
  }

  /// «Escuchar banda» desde Conciertos: la busca en la pestaña Buscar.
  void _listenBand(String band) {
    widget.onNavigate(1);
    searchHubWantMode.value = 0;
    searchWantQuery.value = band;
  }

  void _openMix(String title, String subtitle, List<Color> colors,
      Stream<List<Song>> stream) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => SongListScreen(
        title: title,
        subtitle: subtitle,
        colors: colors,
        stream: stream,
        emptyMessage:
            'No se pudo armar el mix. Revisa tu conexión e inténtalo de nuevo.',
      ),
    ));
  }

  Future<List<ReleaseItem>>? _releasesFuture;

  Future<List<ReleaseItem>> _loadReleases() async {
    var names = <String>[];
    try {
      names = await MixService.personalArtists();
    } catch (_) {}
    names = names.toSet().take(12).toList();
    await ReleaseWatch.ensureLoaded();
    final l = await ArtistInfoService.instance.recentReleases(names);
    // Lo nuevo primero; se marca como visto al salir de Lanzamientos.
    l.sort((a, b) => (ReleaseWatch.isNew(b.album.id) ? 1 : 0) -
        (ReleaseWatch.isNew(a.album.id) ? 1 : 0));
    _relIds = [for (final r in l) r.album.id];
    return l;
  }

  List<String> _relIds = const [];

  void _leaveReleases() {
    if (_relIds.isNotEmpty) ReleaseWatch.markSeen(_relIds);
  }

  Widget _releasesRow() {
    _releasesFuture ??= _loadReleases();
    return SizedBox(
      height: rowHeight(context, 214),
      child: FutureBuilder<List<ReleaseItem>>(
        future: _releasesFuture,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const SkeletonRow();
          }
          final list = snap.data ?? const <ReleaseItem>[];
          if (list.isEmpty) {
            return Align(
              alignment: Alignment.topCenter,
              child: StateMessage(
                compact: true,
                icon: Icons.album_outlined,
                title: 'Sin lanzamientos recientes',
                message: 'No encontré discos nuevos de tus artistas.',
                actionLabel: 'Reintentar',
                onAction: () => setState(() => _releasesFuture = null),
              ),
            );
          }
          return ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              final r = list[i];
              return GestureDetector(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SongListScreen(
                      title: r.album.title,
                      subtitle: r.artist,
                      stream: ArtistInfoService.instance
                          .albumTracks(r.album, r.artist)
                          .asStream(),
                      emptyMessage: 'No pude cargar este disco.',
                    ),
                  ),
                ),
                child: SizedBox(
                  width: 140,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Stack(children: [
                        CoverArt(
                            url: r.album.cover,
                            size: 140,
                            radius: 12,
                            seed: r.artist),
                        if (ReleaseWatch.isNew(r.album.id))
                          Positioned(
                            left: 8,
                            top: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.redBtn,
                                borderRadius: BorderRadius.circular(AppRadius.pill),
                              ),
                              child: const Text('NUEVO',
                                  style: TextStyle(
                                      fontSize: AppType.caption,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white)),
                            ),
                          ),
                      ]),
                      const SizedBox(height: 8),
                      Text(r.album.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: AppType.label)),
                      Text(r.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: AppColors.textDim, fontSize: AppType.caption)),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<List<ArtistInfo>>? _emergingFuture;

  /// Artistas de referencia por género favorito (Pulso).
  static const Map<String, List<String>> _genreSeeds = {
    'Pop': ['Dua Lipa', 'Taylor Swift'],
    'Pop latino': ['Morat', 'Sebastián Yatra'],
    'Baladas': ['Ricardo Arjona', 'Laura Pausini'],
    'Salsa': ['Grupo Niche', 'Marc Anthony'],
    'Reguetón': ['Feid', 'Karol G'],
    'Vallenato': ['Silvestre Dangond', 'Carlos Vives'],
    'Rock': ['Soda Stereo', 'Foo Fighters'],
    'Electrónica': ['Bomba Estéreo', 'Calvin Harris'],
    'Jazz': ['Norah Jones', 'Michael Bublé'],
    'Clásica': ['Ludovico Einaudi', 'Yo-Yo Ma'],
  };

  Future<List<ArtistInfo>> _loadEmerging() async {
    var seeds = <String>[];
    try {
      seeds = await MixService.personalArtists();
    } catch (_) {}
    if (MusicModeService.general) {
      // Cuota de variedad: como máximo la mitad de las semillas son tuyas;
      // el resto sale de tus géneros favoritos o de las semillas del modo.
      final own = (seeds.toSet().toList()..shuffle()).take(3).toList();
      final other = <String>[
        // El rock no cuenta como «otro género» en Pulso: ya lo tienes.
        for (final g in PulsoPrefs.favGenres.value)
          if (g != 'Rock') ...(_genreSeeds[g] ?? const <String>[]),
        ...MixService.modeSeeds,
      ]..shuffle();
      final keys = own.map(SongMeta.artistKey).toSet();
      seeds = [...own];
      for (final o in other) {
        if (seeds.length >= 6) break;
        if (keys.add(SongMeta.artistKey(o))) seeds.add(o);
      }
    } else {
      if (seeds.length < 3) {
        seeds = [
          ...seeds,
          'Nirvana', 'Foo Fighters', 'Soda Stereo', 'Pearl Jam', 'Green Day', 'Metallica',
        ];
      }
      seeds = (seeds.toSet().toList()..shuffle()).take(6).toList();
    }
    // Tope de 2 artistas nuevos por género: las semillas del mismo género
    // comparten cupo.
    final groupOf = <String, String>{
      for (final e in _genreSeeds.entries)
        for (final a in e.value) a: e.key,
    };
    return ArtistInfoService.instance.emerging(seeds, groupOf: groupOf);
  }

  Widget _emergingRow() {
    _emergingFuture ??= _loadEmerging();
    return SizedBox(
      height: rowHeight(context, 150),
      child: FutureBuilder<List<ArtistInfo>>(
        future: _emergingFuture,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const SkeletonRow(
                itemWidth: 96, coverHeight: 88, circle: true);
          }
          final list = snap.data ?? const <ArtistInfo>[];
          if (list.isEmpty) {
            return Align(
              alignment: Alignment.topCenter,
              child: StateMessage(
                compact: true,
                icon: Icons.cloud_off_rounded,
                title: byMode('No pude cargar bandas', 'No pude cargar artistas'),
                message: 'Revisa tu conexión.',
                actionLabel: 'Reintentar',
                isError: true,
                onAction: () => setState(() => _emergingFuture = null),
              ),
            );
          }
          return ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (context, i) {
              final a = list[i];
              return GestureDetector(
                onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => ArtistScreen(name: a.name))),
                child: SizedBox(
                  width: 96,
                  child: Column(
                    children: [
                      ClipOval(
                        child: SizedBox(
                          width: 88,
                          height: 88,
                          child: a.picture.isEmpty
                              ? ColoredBox(color: AppColors.surfaceWarm)
                              : Image.network(a.picture, fit: BoxFit.cover),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(a.name,
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: AppType.caption, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _playMix() async {
    final artists = await MixService.personalArtists();
    if (!mounted) return;
    if (artists.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Marca algunas canciones como favoritas o escucha música y armo tu mix.'),
      ));
      return;
    }
    _openMix(
      'Tu mix',
      'Con tus artistas favoritos',
      AppPalettes.wine,
      MixService.buildMix(artists, pick: 30, perArtist: 10),
    );
  }

  Widget _personalMix() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _playMix,
          child: Container(
            decoration: BoxDecoration(
              gradient: AppColors.heroGradient,
              borderRadius: BorderRadius.circular(AppRadius.xl),
              border: Border.all(color: AppColors.borderAccent),
            ),
            child: Stack(
              children: [
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Opacity(
                    opacity: 0.5,
                    child: SizedBox(
                      width: 260,
                      height: 90,
                      child: CustomPaint(
                          painter: WavesPainter(AppColors.borderAccent)),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('TU MIX', style: AppType.overlineOnAccent),
                      const SizedBox(height: 6),
                      Text(byMode('SUENA COMO\nTÚ ERES', 'Lo que más\nte suena'),
                          style: AppType.oswald(AppType.display)),
                      const SizedBox(height: 8),
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: 230),
                        child: const Text(
                            'Armado con tus favoritos y lo último que escuchaste.',
                            style: TextStyle(
                                fontSize: AppType.label,
                                height: 1.35,
                                color: Color(0xE6FFFFFF))),
                      ),
                      const SizedBox(height: 16),
                      // Botón con la regla común (blanco sobre tarjeta de color).
                      AppButton.primary(
                        label: 'Reproducir',
                        icon: Icons.play_arrow_rounded,
                        onColor: true,
                        onPressed: _playMix,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _mixRow(List<MixDef> mixes) {
    return SizedBox(
      height: rowHeight(context, 176),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: mixes.length,
        separatorBuilder: (context, i) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final m = mixes[i];
          return _MixCard(
            def: m,
            onTap: () => _openMix(m.title, m.subtitle, m.colors,
                MixService.buildMix(MixService.pool(m),
                    pick: 70, perArtist: 4, keepOrder: true)),
          );
        },
      ),
    );
  }

  Widget _recentSection() {
    if (_loading) {
      return SizedBox(height: rowHeight(context, 200), child: const SkeletonRow());
    }
    if (_recent.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.outline),
          ),
          child: Row(
            children: [
              Icon(Icons.headphones_rounded, color: AppColors.amber, size: 30),
              SizedBox(width: 14),
              Expanded(
                child: Text(
                  'Aún no has escuchado nada. Busca una canción y empieza el ruido.',
                  style: TextStyle(color: AppColors.textDim, height: 1.4),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return SizedBox(
      height: rowHeight(context, 200),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _recent.length,
        separatorBuilder: (context, i) => const SizedBox(width: 14),
        itemBuilder: (context, i) {
          final s = _recent[i];
          return FadeIn(
            order: i,
            child: _RecentCard(
              song: s,
              onTap: () => playSongs(context, _recent, i),
            ),
          );
        },
      ),
    );
  }
}

class _QuickTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _QuickTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceHigh,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.lg, vertical: AppSpace.md),
            child: Row(
              children: [
                Icon(icon, color: AppColors.redText, size: 26),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(label,
                          style: const TextStyle(
                              fontSize: AppType.body,
                              fontWeight: FontWeight.w700)),
                      Text(subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: AppType.label,
                              color: AppColors.textDim)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    color: AppColors.textDim),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecentCard extends StatelessWidget {
  final Song song;
  final VoidCallback onTap;

  const _RecentCard({required this.song, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Dense(child: Pressable(child: _card()));
  }

  Widget _card() {
    return SizedBox(
      width: 140,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SongCover(song,
                size: 140, radius: AppRadius.md, shadow: true),
            const SizedBox(height: 10),
            Text(
              song.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: AppType.bodySm),
            ),
            const SizedBox(height: 2),
            Text(
              song.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppColors.textDim, fontSize: AppType.caption),
            ),
          ],
        ),
      ),
    );
  }
}


class _MixCard extends StatelessWidget {
  final MixDef def;
  final VoidCallback onTap;

  /// Mix diario: collage con fotos de sus artistas en vez del ícono.
  final bool photos;

  const _MixCard({required this.def, required this.onTap, this.photos = false});

  @override
  Widget build(BuildContext context) {
    return Dense(child: Pressable(child: _card(context)));
  }

  Widget _card(BuildContext context) {
    return SizedBox(
      width: 150,
      child: Material(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        clipBehavior: Clip.antiAlias,
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: def.colors,
            ),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.borderSubtle),
          ),
          child: InkWell(
            onTap: onTap,
            child: Stack(
              children: [
                if (photos)
                  Positioned.fill(child: _ArtistCollage(def.artists, def.colors))
                else ...[
                Positioned.fill(
                  child: CustomPaint(
                      painter: MusicModeService.general
                          ? null
                          : const PickPatternPainter(Color(0x0FFFFFFF))),
                ),
                Positioned(
                  right: -14,
                  top: -10,
                  child: Transform.rotate(
                    angle: 0.3,
                    child: Icon(def.icon,
                        size: 92, color: const Color(0x2EFFFFFF)),
                  ),
                ),
                ],
                const Positioned.fill(
                  child: DecoratedBox(
                      decoration: BoxDecoration(gradient: AppColors.bottomScrim)),
                ),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Spacer(),
                      Text(
                        MusicModeService.general ? def.title : def.title.toUpperCase(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontSize: AppType.titleSm, height: 1.05, letterSpacing: 0.6),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        def.subtitle,
                        maxLines: photos ? 2 : 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: AppType.caption,
                            color: Color(0xE6FFFFFF)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Nudge {
  final String title;
  final String text;
  final IconData icon;
  final bool concert;
  final String prompt;
  final String band;
  const _Nudge(this.title, this.text, this.icon,
      {this.concert = false, this.prompt = '', this.band = ''});
}


/// Cuatro fotos de artistas (Deezer) en cuadrícula, con velo para leer el
/// texto. Mientras cargan se ve el degradado de la tarjeta.
class _ArtistCollage extends StatefulWidget {
  final List<String> artists;
  final List<Color> colors;
  const _ArtistCollage(this.artists, this.colors);

  @override
  State<_ArtistCollage> createState() => _ArtistCollageState();
}

class _ArtistCollageState extends State<_ArtistCollage> {
  /// Fotos ya usadas por otro mix: así dos tarjetas no repiten la misma.
  static final Set<String> _used = <String>{};
  static final Map<String, List<String>> _cache = {};
  List<String> _pics = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final key = widget.artists.take(8).join('|');
    final hit = _cache[key];
    if (hit != null) {
      _pics = hit;
      return;
    }
    // Sin imágenes en datos móviles si el usuario lo pidió.
    final ds = DataSaver.instance;
    if (ds.noMobileImages && !await ds.onWifi()) return;
    // En paralelo, no una tras otra.
    final infos = await Future.wait([
      for (final a in widget.artists.take(8))
        ArtistInfoService.instance
            .artist(a)
            .then<ArtistInfo?>((i) => i)
            .catchError((_) => null),
    ]);
    final out = <String>[];
    for (final i in infos) {
      if (i == null || i.picture.isEmpty) continue;
      // Versión mediana (250 px): basta para una celda.
      final u = i.picture.replaceAll(RegExp(r'\d{3,4}x\d{3,4}'), '250x250');
      if (_used.contains(u) || out.contains(u)) continue;
      out.add(u);
      if (out.length == 4) break;
    }
    _used.addAll(out);
    _cache[key] = out;
    if (mounted && out.isNotEmpty) setState(() => _pics = out);
  }

  @override
  Widget build(BuildContext context) {
    if (_pics.isEmpty) return const SizedBox.shrink();
    final dpr = MediaQuery.devicePixelRatioOf(context);
    Widget cell(String u) => Image.network(u,
        fit: BoxFit.cover,
        cacheWidth: (100 * dpr).round(),
        errorBuilder: (_, __, ___) => const SizedBox.shrink());
    final p = _pics;
    // Composición según cuántas fotos hay (sin repetir ninguna).
    final Widget grid = switch (p.length) {
      1 => cell(p[0]),
      2 => Row(children: [Expanded(child: cell(p[0])), Expanded(child: cell(p[1]))]),
      3 => Row(children: [
          Expanded(child: cell(p[0])),
          Expanded(
              child: Column(children: [
            Expanded(child: cell(p[1])),
            Expanded(child: cell(p[2])),
          ])),
        ]),
      _ => Column(children: [
          Expanded(child: Row(children: [Expanded(child: cell(p[0])), Expanded(child: cell(p[1]))])),
          Expanded(child: Row(children: [Expanded(child: cell(p[2])), Expanded(child: cell(p[3]))])),
        ]),
    };
    final tint = widget.colors.isEmpty ? Colors.black : widget.colors.first;
    final deep = widget.colors.length > 1 ? widget.colors.last : Colors.black;
    return Stack(fit: StackFit.expand, children: [
      grid,
      // Velo teñido con el color del mix: cada tarjeta conserva su color.
      DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [tint.withValues(alpha: 0.35), deep.withValues(alpha: 0.9)],
          ),
        ),
      ),
    ]);
  }
}
