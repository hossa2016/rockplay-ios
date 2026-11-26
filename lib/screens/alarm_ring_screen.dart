import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:just_audio/just_audio.dart';

import '../models/song.dart';
import '../services/alarm_service.dart';
import '../services/library_service.dart';
import '../services/mix_service.dart';
import '../services/playback_service.dart';
import '../services/playlist_service.dart';
import '../services/radio_service.dart';
import '../services/music_mode.dart';
import '../theme/app_theme.dart';
import '../widgets/cover_art.dart';
import '../widgets/playback_ui.dart';

/// Arranca lo que suena en la alarma. Devuelve false si no hubo qué poner.
Future<bool> playAlarmSource(Alarm a) async {
  List<Song> songs = const [];
  try {
    switch (a.source) {
      case AlarmSource.radio:
        final st = RadioStation.fromJson(
            jsonDecode(a.payload) as Map<String, dynamic>);
        songs = [st.toSong()];
        break;
      case AlarmSource.song:
        songs = [Song.fromJson(jsonDecode(a.payload) as Map<String, dynamic>)];
        break;
      case AlarmSource.list:
        if (a.payload == 'fav') {
          songs = await LibraryService.instance.favorites();
        } else {
          for (final p in await PlaylistService.instance.all()) {
            if (p.id == a.payload) songs = List<Song>.of(p.songs);
          }
        }
        songs = List<Song>.of(songs)..shuffle();
        break;
      case AlarmSource.mix:
        final artists = await MixService.personalArtists();
        if (artists.isNotEmpty) {
          songs = await MixService.buildMix(artists, pick: 40, perArtist: 6)
              .firstWhere((l) => l.length >= 5, orElse: () => const <Song>[])
              .timeout(const Duration(seconds: 12),
                  onTimeout: () => const <Song>[]);
        }
        if (songs.isEmpty) {
          songs = List<Song>.of(await LibraryService.instance.favorites())
            ..shuffle();
        }
        break;
    }
  } catch (_) {}
  if (songs.isEmpty) return false;
  if (a.ramp) await PlaybackService.instance.rampUp(const Duration(seconds: 30));
  await PlaybackService.instance.playQueue(songs, 0);
  return true;
}

/// Pantalla cuando suena la alarma: hora grande, lo que suena y
/// Posponer / Apagar / Apagar y seguir escuchando.
class AlarmRingScreen extends StatefulWidget {
  final Alarm alarm;
  const AlarmRingScreen({super.key, required this.alarm});

  @override
  State<AlarmRingScreen> createState() => _AlarmRingScreenState();
}

class _AlarmRingScreenState extends State<AlarmRingScreen>
    with SingleTickerProviderStateMixin {
  final PlaybackUi pb = PlaybackUi.instance;
  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1600));
  Timer? _backupTimer;
  AudioPlayer? _backup;
  bool _musicOn = false;
  double? _prevVolume;

  Future<void> _restoreVolume() async {
    final v = _prevVolume;
    _prevVolume = null;
    if (v == null) return;
    try {
      await FlutterVolumeController.setVolume(v);
    } catch (_) {}
  }
  late DateTime _now = DateTime.now();
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _pulse.repeat();
    _clock = Timer.periodic(const Duration(seconds: 10),
        (_) => setState(() => _now = DateTime.now()));
    pb.playing.addListener(_onPlaying);
    _start();
  }

  Future<void> _start() async {
    final a = widget.alarm;
    await AlarmService.instance.startRinging(a.id);
    HapticFeedback.heavyImpact();
    // Volumen del celular al nivel de la alarma (se restaura al apagar).
    try {
      _prevVolume = await FlutterVolumeController.getVolume();
      await FlutterVolumeController.setVolume(a.volume);
    } catch (_) {}
    final ok = await playAlarmSource(a);
    // Si en 15 s no suena nada, el respaldo suena dentro de la app.
    _backupTimer = Timer(ok ? AlarmService.backupDelay : Duration.zero, () {
      if (!_musicOn && mounted && a.backup) _playBackup();
    });
  }

  void _onPlaying() {
    if (pb.playing.value && !_musicOn) {
      _musicOn = true;
      AlarmService.instance.musicStarted(widget.alarm.id);
      _stopBackup();
      if (mounted) setState(() {});
    }
  }

  Future<void> _playBackup() async {
    try {
      final p = AudioPlayer();
      _backup = p;
      final custom = widget.alarm.backupPath;
      if (custom.isNotEmpty) {
        await p.setFilePath(custom);
      } else {
        await p.setAsset(MusicModeService.general
            ? 'assets/sounds/soft_chime.wav'
            : 'assets/sounds/rock_riff.wav');
      }
      await p.setLoopMode(LoopMode.all);
      await p.setVolume(1.0);
      await p.play();
      await AlarmService.instance.musicStarted(widget.alarm.id);
      if (mounted) setState(() {});
    } catch (_) {}
  }

  void _stopBackup() {
    final p = _backup;
    _backup = null;
    if (p != null) {
      p.stop().whenComplete(p.dispose);
    }
  }

  @override
  void dispose() {
    pb.playing.removeListener(_onPlaying);
    _backupTimer?.cancel();
    _clock?.cancel();
    _stopBackup();
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _snooze() async {
    HapticFeedback.mediumImpact();
    _stopBackup();
    await PlaybackService.instance.pause();
    await _restoreVolume();
    await AlarmService.instance.snooze(widget.alarm.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Pospuesta 10 minutos')));
    Navigator.of(context).pop();
  }

  Future<void> _dismiss({bool keepPlaying = false}) async {
    HapticFeedback.mediumImpact();
    _stopBackup();
    if (!keepPlaying) {
      await PlaybackService.instance.pause();
      await _restoreVolume();
    }
    await AlarmService.instance.dismiss(widget.alarm.id);
    if (mounted) Navigator.of(context).pop();
  }

  static const _wd = ['', 'Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'];
  static const _mo = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];

  @override
  Widget build(BuildContext context) {
    final h = _now.hour % 12 == 0 ? 12 : _now.hour % 12;
    final time = '$h:${_now.minute.toString().padLeft(2, '0')}';
    final greet = _now.hour < 12
        ? 'BUENOS DÍAS'
        : (_now.hour < 19 ? 'BUENAS TARDES' : 'BUENAS NOCHES');
    final reduced = AppMotion.reduced(context);
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.4),
              radius: 1.1,
              colors: [Color(0xFF5A0F0D), Color(0xFF1A0C0B), AppColors.bg],
              stops: [0, 0.5, 0.85],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
              child: Column(
                children: [
                  Text(greet, style: AppType.overline),
                  const SizedBox(height: 8),
                  Text(time,
                      style: AppType.oswald(108, height: 1.0)
                          .copyWith(letterSpacing: 1)),
                  const SizedBox(height: 6),
                  Text(
                      '${_wd[_now.weekday]} ${_now.day} de ${_mo[_now.month - 1]}',
                      style: TextStyle(
                          fontSize: AppType.body, color: AppColors.textDim)),
                  const Spacer(),
                  ValueListenableBuilder<Song?>(
                    valueListenable: pb.song,
                    builder: (context, s, _) => Column(children: [
                      AnimatedBuilder(
                        animation: _pulse,
                        builder: (context, child) => Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.red.withValues(
                                    alpha: reduced ? 0.3 : 0.55 * (1 - _pulse.value)),
                                blurRadius: 0,
                                spreadRadius: reduced ? 6 : 26 * _pulse.value,
                              ),
                            ],
                          ),
                          child: child,
                        ),
                        child: ClipOval(
                          child: CoverArt(
                              url: s?.image ?? '',
                              size: 170,
                              radius: 85,
                              seed: s?.artist ?? 'RockPlay'),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        s?.title ??
                            (_backup != null
                                ? 'Tono de respaldo'
                                : 'Preparando ${widget.alarm.sourceLabel}…'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: AppType.oswald(AppType.headline),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        s == null
                            ? (_backup != null
                                ? 'No hubo internet: suena lo guardado'
                                : widget.alarm.sourceLabel)
                            : '${s.isRadio ? 'Radio en vivo' : s.artist} · ${widget.alarm.sourceLabel}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: AppType.body, color: AppColors.textDim),
                      ),
                    ]),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    height: 64,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.text,
                        backgroundColor: AppColors.surfaceHigh,
                        side: BorderSide(color: AppColors.outline),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.lg)),
                        textStyle: const TextStyle(
                            fontSize: AppType.body, fontWeight: FontWeight.w800),
                      ),
                      onPressed: _snooze,
                      icon: const Icon(Icons.snooze_rounded),
                      label: const Text('Posponer 10 min'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 64,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.redBtn,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.lg)),
                        textStyle: const TextStyle(
                            fontSize: AppType.body, fontWeight: FontWeight.w800),
                      ),
                      onPressed: () => _dismiss(),
                      icon: const Icon(Icons.alarm_off_rounded),
                      label: const Text('Apagar alarma'),
                    ),
                  ),
                  const SizedBox(height: 4),
                  TextButton(
                    style: TextButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        foregroundColor: AppColors.amber),
                    onPressed: _musicOn ? () => _dismiss(keepPlaying: true) : null,
                    child: const Text('Apagar y seguir escuchando'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
