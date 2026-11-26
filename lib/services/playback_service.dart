import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/song.dart';
import 'audio_handler.dart';

/// Fachada de reproducción para la UI. Audio puro (just_audio) dentro de un
/// servicio en primer plano (audio_service): sigue sonando con la pantalla
/// apagada y muestra notificación y controles de bloqueo.
class PlaybackService {
  PlaybackService._();
  static final PlaybackService instance = PlaybackService._();

  final PlaybackSubjects _s = PlaybackSubjects();
  RockPlayAudioHandler? _handler;
  Future<void>? _initFuture;

  /// Idempotente. Llamar antes de runApp.
  Future<void> init() => _initFuture ??= _doInit();

  Future<void> _doInit() async {
    try {
      // Android 13+: sin este permiso la notificación no se muestra.
      await Permission.notification.request();
    } catch (_) {}
    try {
      // Una sola vez: pide que Android no limite la batería de la app
      // (evita que HyperOS corte la música con la pantalla apagada).
      final sp = await SharedPreferences.getInstance();
      if (sp.getBool('battery_asked') != true) {
        await sp.setBool('battery_asked', true);
        await Permission.ignoreBatteryOptimizations.request();
      }
    } catch (_) {}
    _handler = await AudioService.init<RockPlayAudioHandler>(
      builder: () => RockPlayAudioHandler(_s),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.rockplay.audio',
        androidNotificationChannelName: 'RockPlay IA',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
      ),
    );
    unawaited(_handler!.restore());
  }

  Future<RockPlayAudioHandler> _h() async {
    await init();
    return _handler!;
  }

  Future<void> playQueue(List<Song> songs, int index) async =>
      (await _h()).playQueue(songs, index);
  Future<void> play() async => (await _h()).play();
  Future<void> pause() async => (await _h()).pause();
  Future<void> next() async => (await _h()).skipToNext();
  Future<void> previous() async => (await _h()).skipToPrevious();
  Future<void> seek(Duration position) async => (await _h()).seek(position);
  /// Despertador: sube el volumen poco a poco durante [d].
  Future<void> rampUp(Duration d) async => (await _h()).rampUp(d);
  Future<void> duck(bool on) async => (await _h()).duck(on);

  // Cola editable, repetir, temporizador.
  Future<void> queueRemove(int i) async => (await _h()).qRemove(i);
  Future<void> queueMove(int from, int to) async => (await _h()).qMove(from, to);
  Future<void> queuePlayNext(Song s) async => (await _h()).qPlayNext(s);
  Future<void> queueAdd(Song s) async => (await _h()).qAdd(s);
  Future<void> queueShuffle() async => (await _h()).qShuffle();
  Future<void> setRepeat(int mode) async => (await _h()).setRepeat(mode);
  Future<void> setSleep(Duration? d, {bool endOfSong = false}) async =>
      (await _h()).setSleep(d, endOfSong: endOfSong);
  Stream<int> get repeat => _s.repeat.stream;
  Stream<String?> get sleepLabel => _s.sleepLabel.stream;

  Stream<Song?> get currentSong => _s.currentSong.stream;
  Stream<bool> get playing => _s.playing.stream;
  Stream<bool> get loading => _s.loading.stream;

  /// Mensaje en español cuando una canción falla; después emite null (~4 s).
  Stream<String?> get error => _s.error.stream;
  Stream<Duration> get position => _s.position.stream;
  Stream<Duration?> get duration => _s.duration.stream;
  Stream<List<Song>> get queue => _s.queue.stream;
  Stream<int?> get currentIndex => _s.currentIndex.stream;

  bool get hasNext {
    final i = _s.currentIndex.valueOrNull;
    if (i == null) return false;
    final n = _s.queue.value.length;
    return i + 1 < n || (_s.repeat.value == 1 && n > 0);
  }

  bool get hasPrevious {
    final i = _s.currentIndex.valueOrNull;
    return i != null && i > 0;
  }
}
