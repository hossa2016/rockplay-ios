import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter/scheduler.dart';

import 'package:url_launcher/url_launcher.dart';

import '../models/song.dart';
import '../services/cover_color.dart';
import 'settings_hub_screen.dart';
import '../services/embed_bridge.dart';
import '../services/share_service.dart';
import '../services/track_info_service.dart';
import '../services/block_service.dart';
import '../widgets/add_to_playlist.dart';
import '../widgets/cover_art.dart';
import '../services/playback_service.dart';
import '../services/music_mode.dart';
import '../theme/app_theme.dart';
import '../widgets/favorite_button.dart';
import '../widgets/music_card.dart';
import '../widgets/lyrics_view.dart';
import '../widgets/mini_player.dart';
import '../widgets/pressable.dart';
import '../widgets/sleep_wake_sheet.dart';
import 'artist_screen.dart';
import 'eq_screen.dart';
import 'radio_screen.dart';
import '../widgets/playback_ui.dart';
import '../services/radio_now.dart';
import '../widgets/nav_signals.dart';
import 'search_hub.dart';
import 'search_screen.dart';

/// Pantalla de reproducción inmersiva. Lee todo de [PlaybackUi].
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with TickerProviderStateMixin {
  final PlaybackUi pb = PlaybackUi.instance;
  double? _drag;
  final GlobalKey _slotKey = GlobalKey();
  late final Ticker _ticker;
  late final AnimationController _spin;
  late final AnimationController _eq;
  /// Fondo que «respira» muy despacio (1,0 → 1,08 cada 20 s).
  late final AnimationController _breath;
  /// «Ver video»: muestra el reproductor de YouTube (visible, ≥ 200 dp)
  /// en lugar de la portada.
  static bool _showVideo = false;
  bool _disc = false;
  bool _lyrics = false;
  TrackInfo? _info;
  String _infoKey = '';

  /// Color de la carátula, aclarado para que se lea sobre fondo oscuro.
  /// Tiñe el botón de play, la barra de progreso y las ondas.
  Color _accent = AppColors.red;
  String _accentUrl = '';

  void _ensureAccent(Song song) {
    // El color sale de la carátula que se ve (la de Deezer si ya llegó).
    final art = _art;
    final url = !song.isRadio && art.isNotEmpty ? art : song.image;
    if (url == _accentUrl) return;
    _accentUrl = url;
    final peek = CoverColor.peek(url);
    if (peek != null) _accent = _readable(peek);
    CoverColor.of(url).then((c) {
      if (!mounted || _accentUrl != url) return;
      setState(() => _accent = c == null ? AppColors.red : _readable(c));
    });
  }

  static Color _readable(Color c) {
    final h = HSLColor.fromColor(c);
    // Croma real (no la saturación HSL, que se dispara en los casi negros).
    final r = (c.r * 255), g = (c.g * 255), b = (c.b * 255);
    final chroma = ([r, g, b].reduce(math.max) - [r, g, b].reduce(math.min)) / 255;
    if (chroma < 0.10 || h.saturation < 0.18) return AppColors.red; // gris
    // En rock solo tonos cálidos (rojos, naranjas, ámbar); si no, el rojo.
    if (!MusicModeService.general && h.hue > 50 && h.hue < 330) {
      return AppColors.red;
    }
    final c2 = h
        .withSaturation(h.saturation.clamp(0.55, 0.9))
        .withLightness(h.lightness.clamp(0.52, 0.62))
        .toColor();
    // En Pulso se mezcla con el violeta de la marca para no salirse de la
    // paleta (nada de naranjas ni ámbar).
    return MusicModeService.general
        ? Color.lerp(c2, const Color(0xFF6A4CF0), 0.5)!
        : c2;
  }

  /// Carátula validada (vacía = se muestra el recorte del video).
  String _art = '';

  void _ensureInfo(Song song) {
    if (song.isRadio) {
      _infoKey = '';
      _info = null;
      _art = '';
      return;
    }
    final key = '${song.artist}|${song.title}';
    if (_infoKey == key) return;
    _infoKey = key;
    _info = null;
    // Una sola fuente de carátula, la misma del mini reproductor y las listas.
    final p0 = SongArtwork.peek(song);
    _art = SongArtwork.isReal(p0) ? p0 : '';
    SongArtwork.of(song).then((u) {
      if (mounted && _infoKey == key) {
        setState(() => _art = SongArtwork.isReal(u) ? u : '');
      }
    });
    TrackInfoService.instance.fetch(song.artist, song.title).then((i) {
      if (mounted && _infoKey == key) setState(() => _info = i);
    });
  }


  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) => _measure())..start();
    // El ticker se detiene cuando otra pantalla tapa el reproductor; este
    // temporizador no, y así el video se esconde también en ese caso.
    _measureTimer = Timer.periodic(
        const Duration(milliseconds: 150), (_) { if (mounted) _measure(); });
    _spin = AnimationController(
        vsync: this, duration: const Duration(seconds: 14));
    _eq = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1600));
    _breath = AnimationController(
        vsync: this, duration: const Duration(seconds: 20));
    pb.playing.addListener(_syncAnim);
    _syncAnim();
  }

  void _sleepSheet() => showSleepWakeSheet(context);

  Future<void> _confirmBlock() async {
    final s = pb.song.value;
    if (s == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceHigh,
        title: const Text('¿Bloquear este artista?'),
        content: Text(
            'No volverá a salir «${s.artist}» en búsquedas ni mixes. Lo desbloqueas en Ajustes → Filtros.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Bloquear',
                  style: TextStyle(color: AppColors.redText))),
        ],
      ),
    );
    if (ok == true) await _block();
  }

  Future<void> _block() async {
    final s = pb.song.value;
    if (s == null) return;
    final name = s.artist
        .replaceAll(
            RegExp(r'\s*(-\s*topic|vevo|oficial|official)\s*$',
                caseSensitive: false),
            '')
        .trim();
    if (name.isEmpty) return;
    await BlockService.instance.add(name);
    pb.bumpLibrary();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('Listo: no volverá a salir «$name».'),
        action: SnackBarAction(
          label: 'Deshacer',
          onPressed: () async {
            await BlockService.instance.remove(name);
            pb.bumpLibrary();
          },
        ),
      ));
    if (PlaybackService.instance.hasNext) PlaybackService.instance.next();
  }

  /// Sistema pidió menos animaciones: disco, ondas y fondo quedan quietos.
  bool _reduced = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final r = AppMotion.reduced(context);
    if (r != _reduced) {
      _reduced = r;
      _syncAnim();
    }
  }

  void _syncAnim() {
    if (pb.playing.value && !_reduced) {
      if (!_spin.isAnimating) _spin.repeat();
      if (!_eq.isAnimating) _eq.repeat();
      if (!_breath.isAnimating) _breath.repeat(reverse: true);
    } else {
      _spin.stop();
      _eq.stop();
      _breath.stop();
    }
  }

  Timer? _measureTimer;

  void _measure() {
    // El video solo se ve con el reproductor arriba (sin Letra, hojas ni
    // menús encima); si no, vuelve fuera de pantalla.
    final top = ModalRoute.of(context)?.isCurrent ?? true;
    if (!_showVideo || _lyrics || !top || (pb.song.value?.isRadio ?? false)) {
      if (EmbedBridge.instance.slot.value != null) {
        EmbedBridge.instance.slot.value = null;
      }
      return;
    }
    final ro = _slotKey.currentContext?.findRenderObject();
    if (ro is RenderBox && ro.attached && ro.hasSize) {
      final r = ro.localToGlobal(Offset.zero) & ro.size;
      if (EmbedBridge.instance.slot.value != r) {
        EmbedBridge.instance.slot.value = r;
      }
    } else if (EmbedBridge.instance.slot.value != null) {
      EmbedBridge.instance.slot.value = null; // sin hueco: fuera de pantalla
    }
  }

  @override
  void dispose() {
    _measureTimer?.cancel();
    pb.playing.removeListener(_syncAnim);
    _spin.dispose();
    _eq.dispose();
    _breath.dispose();
    _ticker.dispose();
    EmbedBridge.instance.slot.value = null;
    if (EmbedBridge.instance.fullscreen.value) {
      EmbedBridge.instance.fullscreen.value = false;
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  static String _fmt(Duration d) {
    final totalSeconds = d.inSeconds < 0 ? 0 : d.inSeconds;
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    final ss = s.toString().padLeft(2, '0');
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$ss';
    return '$m:$ss';
  }

  Widget _background(Song? song) {
    final url = song?.image ?? '';
    return Stack(
      fit: StackFit.expand,
      children: [
        FutureBuilder<Color?>(
          future: CoverColor.of(url),
          initialData: CoverColor.peek(url),
          builder: (context, snap) {
            return TweenAnimationBuilder<Color?>(
              tween: ColorTween(
                  end: snap.data ?? const Color(0xFF4A1512)),
              duration: const Duration(milliseconds: 600),
              builder: (context, c, _) => DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [c ?? const Color(0xFF4A1512), AppColors.bg],
                  ),
                ),
              ),
            );
          },
        ),
        if (url.isNotEmpty)
          AnimatedBuilder(
            animation: _breath,
            builder: (context, child) => Transform.scale(
                scale: 1.0 + 0.08 * Curves.easeInOut.transform(_breath.value),
                child: child),
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 48, sigmaY: 48),
              child: Opacity(
                opacity: 0.55,
                child: Image.network(
                  url,
                  cacheWidth: 96,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stack) =>
                      const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color.fromRGBO(10, 10, 13, 0.25),
                Color.fromRGBO(10, 10, 13, 0.75),
                AppColors.bg,
              ],
              stops: [0.0, 0.55, 1.0],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          Positioned.fill(
            child: ValueListenableBuilder<Song?>(
              valueListenable: pb.song,
              builder: (context, s, _) {
                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 500),
                  child: KeyedSubtree(
                    key: ValueKey<String>(s?.image ?? ''),
                    child: _background(s),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: ValueListenableBuilder<Song?>(
              valueListenable: pb.song,
              builder: (context, s, _) {
                if (s == null) return _empty(context);
                return _content(context, s);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context) {
    return Column(
      children: [
        _topBar(context),
        Expanded(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'No hay nada en reproducción.\nElige una canción para empezar.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textDim, height: 1.4),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _topBar(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) > 500) Navigator.of(context).maybePop();
      },
      child: _topBarInner(context),
    );
  }

  Widget _topBarInner(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: Row(
        children: [
          IconButton(
            iconSize: 32,
            tooltip: 'Cerrar',
            icon: const Icon(Icons.keyboard_arrow_down_rounded),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: ValueListenableBuilder<List<Song>>(
              valueListenable: pb.queue,
              builder: (context, q, _) {
                final radio = pb.song.value?.isRadio ?? false;
                return Column(
                  children: [
                    Text(
                      'SONANDO DESDE',
                      style: TextStyle(
                        fontSize: AppType.caption,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDim,
                      ),
                    ),
                    Text(
                      radio
                          ? 'Radio en vivo'
                          : q.length > 1
                              ? 'Tu cola · ${q.length} canciones'
                              : 'Una canción',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: AppType.bodySm, fontWeight: FontWeight.w800),
                    ),
                  ],
                );
              },
            ),
          ),
          IconButton(
            tooltip: 'Ecualizador',
            icon: const Icon(Icons.equalizer_rounded),
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const EqScreen())),
          ),
          if (!(pb.song.value?.isRadio ?? false))
          PopupMenuButton<String>(
            tooltip: 'Más opciones',
            icon: const Icon(Icons.more_vert_rounded),
            color: AppColors.surfaceHigh,
            onSelected: (v) {
              if (v == 'artist') {
                final s = pb.song.value;
                if (s != null) {
                  Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => ArtistScreen(
                          name: _info?.artist ?? s.artist)));
                }
              } else if (v == 'share') {
                final s = pb.song.value;
                if (s != null) ShareService.song(s);
              } else if (v == 'view') {
                setState(() => _disc = !_disc);
              } else if (v == 'video') {
                setState(() => _showVideo = !_showVideo);
                WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
              } else if (v == 'block') {
                _confirmBlock();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'view',
                child: ListTile(
                  dense: true,
                  leading: Icon(_disc ? Icons.image_rounded : Icons.album_rounded),
                  title: Text(_disc ? 'Ver portada' : 'Ver disco'),
                ),
              ),
              PopupMenuItem(
                value: 'video',
                child: ListTile(
                  dense: true,
                  leading: Icon(_showVideo
                      ? Icons.image_rounded
                      : Icons.smart_display_rounded),
                  title: Text(_showVideo ? 'Ver portada' : 'Ver video'),
                ),
              ),
              const PopupMenuItem(
                value: 'artist',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.person_outline_rounded),
                  title: Text('Ver artista y discos'),
                ),
              ),
              const PopupMenuItem(
                value: 'share',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.share_rounded),
                  title: Text('Compartir'),
                ),
              ),
              PopupMenuItem(
                value: 'block',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.block_rounded, color: AppColors.redText),
                  title: Text('Bloquear artista',
                      style: TextStyle(color: AppColors.redText)),
                ),
              ),
            ],
          )
          else
            const SizedBox(width: 48),
        ],
      ),
    );
  }

  Future<void> _showHeard(String station) async {
    final l = await RadioNow.history(station);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: l.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                    'Esta emisora todavía no ha dicho qué canciones suenan (no todas lo envían).',
                    style: TextStyle(color: AppColors.textDim)),
              )
            : ListView(shrinkWrap: true, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text('Sonó en $station',
                      style: const TextStyle(
                          fontSize: AppType.title, fontWeight: FontWeight.w800)),
                ),
                for (final e in l)
                  ListTile(
                    title: Text(e.$1, maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                        '${e.$2.hour.toString().padLeft(2, '0')}:${e.$2.minute.toString().padLeft(2, '0')}',
                        style: TextStyle(color: AppColors.textDim)),
                    trailing: IconButton(
                      tooltip: 'Guardar en favoritas',
                      icon: const Icon(Icons.favorite_border_rounded),
                      onPressed: () async {
                        final m = ScaffoldMessenger.of(context);
                        final sv = await RadioNow.save(e.$1);
                        m.showSnackBar(SnackBar(
                            content: Text(sv == null
                                ? 'No la encontré para guardarla.'
                                : 'Guardada: ${sv.title}')));
                      },
                    ),
                  ),
              ]),
      ),
    );
  }

  Widget _liveBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.circle, size: 10, color: AppColors.red),
              SizedBox(width: 8),
              Text('EN VIVO',
                  style: TextStyle(
                      fontSize: AppType.label,
                      letterSpacing: 2,
                      fontWeight: FontWeight.w800)),
            ],
          ),
          // «¿Qué está sonando?»: lo que envía la emisora.
          ValueListenableBuilder<(String, String)?>(
            valueListenable: RadioNow.song,
            builder: (context, p, _) {
              final station = pb.song.value?.title ?? '';
              final now = p == null ? '' : '${p.$1} - ${p.$2}';
              return Column(children: [
                if (p != null) ...[
                  const SizedBox(height: 10),
                  Text('AHORA SUENA',
                      style: AppType.overline.copyWith(color: AppColors.amber)),
                  const SizedBox(height: 4),
                  Text('${p.$1} — ${p.$2}',
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: AppType.body, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Wrap(spacing: 8, alignment: WrapAlignment.center, children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                      icon: const Icon(Icons.favorite_border_rounded, size: 18),
                      label: const Text('Guardar'),
                      onPressed: () async {
                        final m = ScaffoldMessenger.of(context);
                        final sv = await RadioNow.save(now);
                        m.showSnackBar(SnackBar(
                            content: Text(sv == null
                                ? 'No la encontré para guardarla.'
                                : 'Guardada en favoritas: ${sv.title}')));
                      },
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                      icon: const Icon(Icons.play_circle_outline_rounded, size: 18),
                      label: const Text('Escuchar completa'),
                      onPressed: () {
                        Navigator.of(context).popUntil((r) => r.isFirst);
                        mainTabWant.value = 1;
                        searchHubWantMode.value = 0;
                        searchWantQuery.value = '${p.$1} ${p.$2}';
                      },
                    ),
                  ]),
                ],
                TextButton.icon(
                  style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
                  icon: const Icon(Icons.history_rounded, size: 18),
                  label: const Text('Lo que sonó'),
                  onPressed: () => _showHeard(station),
                ),
              ]);
            },
          ),
          ValueListenableBuilder<List<Song>?>(
            valueListenable: SongQueueMemory.queue,
            builder: (context, q, _) => q == null || q.isEmpty
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                          minimumSize: const Size(0, 48),
                          foregroundColor: AppColors.amber),
                      onPressed: SongQueueMemory.resume,
                      icon: const Icon(Icons.queue_music_rounded),
                      label: Text('Volver a tu cola · ${q.length} canciones'),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _content(BuildContext context, Song song) {
    _ensureInfo(song);
    _ensureAccent(song);
    final info = _info;
    return Column(
      children: [
        _topBar(context),
        Expanded(
          child: (_lyrics && !song.isRadio)
              ? LyricsView(song: song)
              : _visual(song),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 16, 28, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        // Rock: título en mayúsculas, como el resto de títulos.
                        MusicModeService.general
                            ? (info?.title ?? song.title)
                            : (info?.title ?? song.title).toUpperCase(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: AppType.headline,
                            fontFamily: AppType.head, fontVariations: [FontVariation('wght', 700)], fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                            height: 1.15),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        // Radio: lo que suena va en «AHORA SUENA», no aquí.
                        song.isRadio ? 'Radio en vivo' : (info?.artist ?? song.artist),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          color: AppColors.textDim,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!song.isRadio) Pressable(child: FavoriteButton(song: song)),
              ]),
              if (info != null && info.meta.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  info.meta,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppType.label,
                    color: AppColors.textFaint,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
        _errorBanner(),
        const SizedBox(height: 4),
        song.isRadio ? _liveBar() : _progress(),
        const SizedBox(height: 4),
        _controls(context, song),
        _extraControls(context, song),
        const SizedBox(height: 12),
      ],
    );
  }

  /// Acciones de abajo: guardar, letra, cola y dormir.
  Widget _extraControls(BuildContext context, Song song) {
    Widget btn(IconData icon, String label, VoidCallback onTap,
        {bool on = false}) {
      final c = on ? AppColors.amber : AppColors.textDim;
      // Flexible: con letra grande o «Dormir 25 min» la etiqueta se encoge
      // en vez de cortarse («A una li…»).
      return Expanded(
        child: Semantics(
          button: true,
          label: label,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.md),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                child: ExcludeSemantics(child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 24, color: c),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(label,
                          maxLines: 1,
                          style: TextStyle(
                              fontSize: AppType.caption,
                              fontWeight: FontWeight.w600,
                              color: c)),
                    ),
                  ],
                )),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: ListenableBuilder(
        listenable: pb.sleepLabel,
        builder: (context, _) => Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            if (!song.isRadio) ...[
              btn(Icons.playlist_add_rounded, 'Guardar',
                  () => showAddToPlaylist(context, song)),
              btn(_lyrics ? Icons.lyrics_rounded : Icons.lyrics_outlined,
                  'Letra', () => setState(() => _lyrics = !_lyrics),
                  on: _lyrics),
              btn(Icons.queue_music_rounded, 'Cola', () => _showQueue(context)),
            ],
            btn(Icons.bedtime_outlined,
                pb.sleepLabel.value == null ? 'Dormir' : pb.sleepLabel.value!,
                _sleepSheet,
                on: pb.sleepLabel.value != null),
          ],
        ),
      ),
    );
  }

  Widget _noCover(Song song) {
    return Container(
      padding: const EdgeInsets.all(22),
      alignment: Alignment.bottomLeft,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.redDeep, AppColors.surfaceWarm, AppColors.surface],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('SIN PORTADA',
              style: TextStyle(
                  fontSize: AppType.caption,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w700,
                  color: AppColors.amber)),
          const SizedBox(height: 6),
          Text(song.artist.toUpperCase(),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: AppType.display, fontFamily: AppType.head, fontVariations: [FontVariation('wght', 700)], fontWeight: FontWeight.w700, height: 1.0)),
        ],
      ),
    );
  }

  Widget _cover(Song song) {
    return LayoutBuilder(builder: (context, box) {
      final art = song.isRadio ? song.image : (_art);
      // Siempre cuadrada: sin portada real, se recorta el centro del video
      // (sin las bandas negras de las miniaturas de YouTube).
      final square = art.isNotEmpty;
      final w = math.min(box.maxWidth - 56, box.maxHeight - 90);
      final h = w;
      final fallback = song.image;
      // Sin portada real: la misma imagen que el mini reproductor (la del
      // resultado), y solo si no hay, la miniatura grande del video.
      final thumb = square
          ? art
          : (fallback.isNotEmpty || song.videoId.isEmpty
              ? fallback
              : 'https://i.ytimg.com/vi/${song.videoId}/hqdefault.jpg');
      if (_showVideo && !song.isRadio) {
        final vh = math.max(200.0, w * 9 / 16);
        return Center(
          child: SizedBox(
            key: _slotKey,
            width: math.max(w, 200),
            height: vh,
            child: const ColoredBox(color: Colors.black),
          ),
        );
      }
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Hero(
            tag: kNowPlayingHero,
            child: Container(
            width: w,
            height: h,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              boxShadow: [
                BoxShadow(color: _accent.withValues(alpha: 0.35), blurRadius: 40),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: AnimatedBuilder(
                animation: _spin,
                builder: (context, child) {
                  final t = math.sin(_spin.value * 2 * math.pi);
                  return Transform.scale(
                      scale: (square ? 1.0 : 1.34) + 0.04 * t,
                      child: child);
                },
                child: thumb.isEmpty
                    ? _noCover(song)
                    : Image.network(
                        thumb,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => fallback.isEmpty
                            ? _noCover(song)
                            : Image.network(fallback, fit: BoxFit.cover),
                      ),
              ),
            ),
          )),
          const SizedBox(height: 22),
          SizedBox(
            height: 56,
            width: math.min(box.maxWidth - 64, 320),
            child: AnimatedBuilder(
              animation: _eq,
              builder: (context, _) => CustomPaint(
                painter: _EqPainter(_eq.value, _accent),
              ),
            ),
          ),
        ],
      );
    });
  }

  Widget _visual(Song song) {
    if (!_disc) return _cover(song);
    return LayoutBuilder(builder: (context, box) {
      final disc = math.max(
          120.0, math.min(box.maxWidth - 64, box.maxHeight - 90));
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          RotationTransition(
            turns: _spin,
            child: SizedBox(
              width: disc,
              height: disc,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF0B0B0E),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.red.withValues(alpha: 0.35),
                          blurRadius: 40,
                        ),
                      ],
                    ),
                  ),
                  CustomPaint(
                    size: Size.square(disc),
                    painter: _GroovesPainter(),
                  ),
                  CoverArt(
                    url: _art.isNotEmpty
                        ? _art
                        : song.image,
                    size: disc * 0.46,
                    radius: disc * 0.23,
                    shadow: false,
                  ),
                  Container(
                    width: disc * 0.05,
                    height: disc * 0.05,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.bg,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          SizedBox(
            height: 56,
            width: math.min(box.maxWidth - 64, 320),
            child: AnimatedBuilder(
              animation: _eq,
              builder: (context, _) => CustomPaint(
                painter: _EqPainter(_eq.value, _accent),
              ),
            ),
          ),
        ],
      );
    });
  }

  Widget _errorBanner() {
    return ValueListenableBuilder<String?>(
      valueListenable: pb.error,
      builder: (context, err, _) {
        if (err == null || err.isEmpty) return const SizedBox.shrink();
        if (err.startsWith('Se detuvo: varias')) return _stoppedCard();
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.amberTint,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: AppColors.amberLine,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Row(
              children: [
                Icon(Icons.error_outline_rounded,
                    color: AppColors.amber, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    err,
                    style: TextStyle(
                      color: AppColors.amber,
                      fontSize: AppType.label,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
            Wrap(spacing: 8, children: [
              TextButton(
                  onPressed: _showSkipped, child: const Text('Ver cuáles')),
              if (pb.song.value != null &&
                  pb.song.value!.videoId.isNotEmpty &&
                  !pb.song.value!.isRadio)
                TextButton(
                  onPressed: () => launchUrl(
                      Uri.parse(
                          'https://www.youtube.com/watch?v=${pb.song.value!.videoId}'),
                      mode: LaunchMode.externalApplication),
                  child: const Text('Abrir en YouTube'),
                ),
            ]),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _stoppedCard() {
    final last = SkipLog.entries.take(4).toList();
    String name(String e) {
      final a = e.indexOf('«');
      final b = e.indexOf('»');
      return (a >= 0 && b > a) ? e.substring(a + 1, b) : e;
    }

    final song = pb.song.value;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.amberTint,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border:
              Border.all(color: AppColors.amberLine),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text('LA MÚSICA SE DETUVO',
                    style: TextStyle(
                        color: AppColors.amber,
                        fontSize: AppType.caption,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.w800)),
              ),
              SizedBox(
                width: 48,
                height: 48,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  tooltip: 'Cerrar aviso',
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () => pb.error.value = null,
                ),
              ),
            ]),
            const SizedBox(height: 6),
            const Text(
                'Las últimas canciones no se pueden reproducir en apps porque '
                'YouTube las bloquea. No es un problema de tu teléfono ni de '
                'tu internet.',
                style: TextStyle(fontSize: AppType.label, height: 1.35)),
            const SizedBox(height: 8),
            for (final e in last)
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 36),
                child: Row(children: [
                  Expanded(
                    child: Text(name(e),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: AppType.bodySm, fontWeight: FontWeight.w700)),
                  ),
                  Text('Bloqueada',
                      style: TextStyle(
                          color: AppColors.amber,
                          fontSize: AppType.caption,
                          fontWeight: FontWeight.w700)),
                ]),
              ),
            const SizedBox(height: 4),
            Wrap(spacing: 8, children: [
              FilledButton(
                style:
                    FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                onPressed: () {
                  pb.error.value = null;
                  Navigator.of(context).maybePop();
                },
                child: const Text('Seguir con otro artista'),
              ),
              TextButton(
                  onPressed: _showSkipped, child: const Text('Ver cuáles')),
              if (song != null && song.videoId.isNotEmpty && !song.isRadio)
                TextButton(
                  onPressed: () => launchUrl(
                      Uri.parse(
                          'https://www.youtube.com/watch?v=${song.videoId}'),
                      mode: LaunchMode.externalApplication),
                  child: const Text('Abrir en YouTube'),
                ),
            ]),
          ],
        ),
      ),
    );
  }

  void _showSkipped() => showSkippedDialog(context);

  Widget _progress() {
    return ListenableBuilder(
      listenable: Listenable.merge([pb.position, pb.duration]),
      builder: (context, _) {
        final total = (pb.duration.value ?? Duration.zero).inMilliseconds;
        final totalD = total > 0 ? total.toDouble() : 1.0;
        final posMs = pb.position.value.inMilliseconds.toDouble();
        final value = (_drag ?? posMs).clamp(0.0, totalD).toDouble();
        final shown = Duration(milliseconds: value.round());
        final remaining =
            Duration(milliseconds: total > 0 ? total - value.round() : 0);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              Slider(
                activeColor: _accent,
                thumbColor: Colors.white,
                value: total > 0 ? value : 0.0,
                min: 0.0,
                max: totalD,
                onChanged: total > 0
                    ? (v) => setState(() => _drag = v)
                    : null,
                onChangeEnd: (v) {
                  PlaybackService.instance
                      .seek(Duration(milliseconds: v.round()));
                  setState(() => _drag = null);
                },
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_fmt(shown), style: _timeStyle),
                    Text(total > 0 ? '-${_fmt(remaining)}' : '--:--',
                        style: _timeStyle),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static TextStyle get _timeStyle => TextStyle(
    fontSize: AppType.caption,
    color: AppColors.textDim,
    fontWeight: FontWeight.w500,
    fontFeatures: [ui.FontFeature.tabularFigures()],
  );

  Widget _controls(BuildContext context, Song song) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ListenableBuilder(
        listenable: Listenable.merge([pb.playing, pb.loading, pb.index, pb.queue]),
        builder: (context, _) {
          final svc = PlaybackService.instance;
          final loading = pb.loading.value;
          final playing = pb.playing.value;
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                iconSize: 26,
                tooltip: 'Aleatorio',
                color: AppColors.textDim,
                icon: const Icon(Icons.shuffle_rounded),
                onPressed: song.isRadio ? null : () => svc.queueShuffle(),
              ),
              IconButton(
                iconSize: 44,
                color: Colors.white,
                disabledColor: AppColors.textFaint,
                tooltip: 'Anterior',
                icon: const Icon(Icons.skip_previous_rounded),
                onPressed: svc.hasPrevious ? () => svc.previous() : null,
              ),
              Pressable(child: _playButton(svc, loading, playing)),
              IconButton(
                iconSize: 44,
                color: Colors.white,
                disabledColor: AppColors.textFaint,
                tooltip: 'Siguiente',
                icon: const Icon(Icons.skip_next_rounded),
                onPressed: svc.hasNext ? () => svc.next() : null,
              ),
              ValueListenableBuilder<int>(
                valueListenable: pb.repeat,
                builder: (context, rep, _) => IconButton(
                  iconSize: 26,
                  tooltip: rep == 0
                      ? 'Repetir: no'
                      : rep == 1
                          ? 'Repetir lista'
                          : 'Repetir una',
                  color: rep == 0 ? AppColors.textDim : AppColors.amber,
                  icon: Icon(rep == 2
                      ? Icons.repeat_one_rounded
                      : Icons.repeat_rounded),
                  onPressed:
                      song.isRadio ? null : () => svc.setRepeat((rep + 1) % 3),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _playButton(PlaybackService svc, bool loading, bool playing) {
    final dark = HSLColor.fromColor(_accent).withLightness(0.36).toColor();
    return AnimatedContainer(
      duration: AppMotion.of(context, AppMotion.slow),
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_accent, dark],
        ),
        boxShadow: [
          BoxShadow(
            color: _accent.withValues(alpha: 0.45),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: Semantics(
          button: true,
          label: playing ? 'Pausar' : 'Reproducir',
          child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () {
            HapticFeedback.mediumImpact();
            playing ? svc.pause() : svc.play();
          },
          child: Center(
            child: AnimatedSwitcher(
              duration: AppMotion.of(context, AppMotion.fast),
              transitionBuilder: (c, a) => ScaleTransition(
                  scale: a,
                  child: RotationTransition(
                      turns: Tween<double>(begin: -0.12, end: 0).animate(a),
                      child: c)),
              child: loading
                  ? const SizedBox(
                      key: ValueKey<String>('load'),
                      width: 30,
                      height: 30,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: Colors.white,
                      ),
                    )
                  : Icon(
                      playing
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      key: ValueKey<bool>(playing),
                      size: 44,
                      color: Colors.white,
                    ),
            ),
          ),
        ),
        ),
      ),
    );
  }

  void _showQueue(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          builder: (context, scroll) {
            return ListenableBuilder(
              listenable: Listenable.merge([pb.queue, pb.index, pb.repeat]),
              builder: (context, _) {
                final q = pb.queue.value;
                return Column(
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.outline,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'A continuación',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Aleatorio en lo que sigue',
                            icon: const Icon(Icons.shuffle_rounded),
                            onPressed: () =>
                                PlaybackService.instance.queueShuffle(),
                          ),
                          IconButton(
                            tooltip: pb.repeat.value == 0
                                ? 'Repetir: no'
                                : pb.repeat.value == 1
                                    ? 'Repetir la lista'
                                    : 'Repetir esta canción',
                            color: pb.repeat.value == 0
                                ? AppColors.textDim
                                : AppColors.amber,
                            icon: Icon(pb.repeat.value == 2
                                ? Icons.repeat_one_rounded
                                : Icons.repeat_rounded),
                            onPressed: () => PlaybackService.instance
                                .setRepeat((pb.repeat.value + 1) % 3),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(20, 0, 20, 6),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Mantén pulsada una fila para moverla · desliza para quitarla',
                          style: TextStyle(
                              fontSize: AppType.caption, color: AppColors.textFaint),
                        ),
                      ),
                    ),
                    Expanded(
                      child: q.isEmpty
                          ? Center(
                              child: Text(
                                'La cola está vacía',
                                style: TextStyle(color: AppColors.textDim),
                              ),
                            )
                          : ReorderableListView.builder(
                              scrollController: scroll,
                              itemCount: q.length,
                              onReorder: (a, b) =>
                                  PlaybackService.instance.queueMove(a, b),
                              itemBuilder: (context, i) {
                                final card = MusicCard(
                                  song: q[i],
                                  actions: false,
                                  onTap: () {
                                    PlaybackService.instance
                                        .playQueue(List<Song>.of(q), i);
                                    Navigator.of(sheetContext).pop();
                                  },
                                );
                                final k = ValueKey<String>(
                                    '$i|${q[i].videoId}|${q[i].title}');
                                if (i == (pb.index.value ?? -1)) {
                                  return KeyedSubtree(key: k, child: card);
                                }
                                return Dismissible(
                                  key: k,
                                  direction: DismissDirection.endToStart,
                                  onDismissed: (_) =>
                                      PlaybackService.instance.queueRemove(i),
                                  background: Container(
                                    color: AppColors.red.withValues(alpha: 0.33),
                                    alignment: Alignment.centerRight,
                                    padding:
                                        const EdgeInsets.only(right: 24),
                                    child: const Icon(
                                        Icons.delete_outline_rounded),
                                  ),
                                  child: card,
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}


class _GroovesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color.fromRGBO(255, 255, 255, 0.07);
    for (var f = 0.52; f < 0.98; f += 0.045) {
      canvas.drawCircle(c, r * f, p);
    }
    final shine = Paint()
      ..shader = SweepGradient(colors: const [
        Color.fromRGBO(255, 255, 255, 0.0),
        Color.fromRGBO(255, 255, 255, 0.10),
        Color.fromRGBO(255, 255, 255, 0.0),
        Color.fromRGBO(255, 255, 255, 0.10),
        Color.fromRGBO(255, 255, 255, 0.0),
      ]).createShader(Rect.fromCircle(center: c, radius: r));
    canvas.drawCircle(c, r * 0.98, shine);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _EqPainter extends CustomPainter {
  _EqPainter(this.t, this.color);
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const n = 24;
    final gap = 4.0;
    final bw = (size.width - gap * (n - 1)) / n;
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [
          color,
          MusicModeService.general
              ? HSLColor.fromColor(color).withLightness(0.75).toColor()
              : AppColors.amber,
        ],
      ).createShader(Offset.zero & size);
    for (var i = 0; i < n; i++) {
      final a = math.sin(2 * math.pi * (t * (1 + (i % 3)) + i * 0.17));
      final b = math.sin(2 * math.pi * (t * 2 + i * 0.41));
      final h = size.height * (0.18 + 0.82 * ((a + b + 2) / 4));
      final x = i * (bw + gap);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, size.height - h, bw, h),
          Radius.circular(bw / 2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _EqPainter old) =>
      old.t != t || old.color != color;
}
