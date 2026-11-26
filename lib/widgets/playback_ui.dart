
import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../models/song.dart';
import '../services/library_service.dart';
import '../services/playback_service.dart';
import '../services/stats_service.dart';

/// Espejo del estado de reproducción para la interfaz.
///
/// Escucha UNA sola vez los streams de [PlaybackService] y guarda el último
/// valor en [ValueNotifier]s, así cualquier pantalla (mini-reproductor,
/// pantalla completa, listas) muestra el estado correcto aunque se cree tarde.
class PlaybackUi {
  PlaybackUi._();
  static final PlaybackUi instance = PlaybackUi._();

  final ValueNotifier<Song?> song = ValueNotifier<Song?>(null);
  final ValueNotifier<bool> playing = ValueNotifier<bool>(false);
  final ValueNotifier<bool> loading = ValueNotifier<bool>(false);
  final ValueNotifier<String?> error = ValueNotifier<String?>(null);
  final ValueNotifier<Duration> position = ValueNotifier<Duration>(Duration.zero);
  final ValueNotifier<Duration?> duration = ValueNotifier<Duration?>(null);
  final ValueNotifier<List<Song>> queue = ValueNotifier<List<Song>>(const <Song>[]);
  final ValueNotifier<int?> index = ValueNotifier<int?>(null);
  final ValueNotifier<int> repeat = ValueNotifier<int>(0);
  final ValueNotifier<String?> sleepLabel = ValueNotifier<String?>(null);

  /// Sube cada vez que cambian favoritos o historial.
  final ValueNotifier<int> libraryRevision = ValueNotifier<int>(0);

  bool _started = false;
  String _lastLogged = '';

  void bumpLibrary() => libraryRevision.value = libraryRevision.value + 1;

  void start() {
    if (_started) return;
    _started = true;
    final p = PlaybackService.instance;

    p.currentSong.listen((s) {
      song.value = s;
      _logHistory(s);
      _updateWidget(s);
    }, onError: (Object _) {});
    p.playing.listen((v) => playing.value = v, onError: (Object _) {});
    p.loading.listen((v) => loading.value = v, onError: (Object _) {});
    p.error.listen((v) => error.value = v, onError: (Object _) {});
    p.position.listen((v) => position.value = v, onError: (Object _) {});
    p.duration.listen((v) => duration.value = v, onError: (Object _) {});
    p.queue.listen((v) => queue.value = v, onError: (Object _) {});
    p.currentIndex.listen((v) => index.value = v, onError: (Object _) {});
    p.repeat.listen((v) => repeat.value = v, onError: (Object _) {});
    p.sleepLabel.listen((v) => sleepLabel.value = v, onError: (Object _) {});
  }

  String _widgetKey = '';

  /// Widget de pantalla de inicio «Seguir escuchando».
  Future<void> _updateWidget(Song? s) async {
    if (s == null) return;
    final k = '${s.title}|${s.artist}';
    if (k == _widgetKey) return;
    _widgetKey = k;
    try {
      await HomeWidget.saveWidgetData<String>('np_title', s.title);
      await HomeWidget.saveWidgetData<String>(
          'np_artist', s.isRadio ? 'Radio en vivo' : s.artist);
      await HomeWidget.updateWidget(androidName: 'NowPlayingWidget');
    } catch (_) {}
  }

  Future<void> _logHistory(Song? s) async {
    if (s == null || s.videoId.isEmpty) return;
    if (s.videoId == _lastLogged) return;
    _lastLogged = s.videoId;
    try {
      await LibraryService.instance.addToHistory(s);
      await StatsService.instance.record(s);
      bumpLibrary();
    } catch (_) {}
  }
}
