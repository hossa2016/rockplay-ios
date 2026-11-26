import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

/// Puente con el reproductor oficial de YouTube (IFrame). El WebView vive
/// en un overlay global (ver app.dart) para que siga sonando al cerrar la
/// pantalla del reproductor. Solo funciona con la pantalla encendida.
class EmbedBridge {
  EmbedBridge._();
  static final EmbedBridge instance = EmbedBridge._();

  YoutubePlayerController? controller;
  StreamSubscription<YoutubePlayerValue>? _sub;
  String _videoId = '';
  PlayerState _last = PlayerState.unknown;
  PlayerState get state => _last;

  /// Rectángulo (coordenadas globales) donde se muestra el video; null = oculto.
  final ValueNotifier<Rect?> slot = ValueNotifier<Rect?>(null);
  final ValueNotifier<bool> fullscreen = ValueNotifier<bool>(false);

  void Function()? onEnded;
  void Function(String message)? onError;
  void Function(bool playing)? onPlaying;
  void Function(Duration position, Duration? duration)? onTick;
  Timer? _timer;
  Timer? _nudge;
  bool _endedFired = false;

  /// Carga [videoId] y reproduce.
  void rearm() => _endedFired = false;

  void load(String videoId, {double start = 0}) {
    if (videoId.isEmpty) return;
    _videoId = videoId;
    _endedFired = false;
    _startNudge();
    final c = controller;
    if (c == null) {
      final nc = YoutubePlayerController.fromVideoId(
        videoId: videoId,
        autoPlay: true,
        startSeconds: start > 0 ? start : null,
        params: const YoutubePlayerParams(
          showControls: true,
          showFullscreenButton: false,
          playsInline: true,
        ),
      );
      controller = nc;
      _sub = nc.listen(_onValue);
      _timer = Timer.periodic(const Duration(milliseconds: 500), (_) => _poll());
      _created.add(nc);
    } else {
      c.loadVideoById(videoId: videoId, startSeconds: start);
    }
  }

  final StreamController<YoutubePlayerController> _created =
      StreamController<YoutubePlayerController>.broadcast();
  Stream<YoutubePlayerController> get created => _created.stream;

  void _onValue(YoutubePlayerValue v) {
    if (v.error.name != 'none') {
      onError?.call('YouTube no permite reproducir este video aquí (${v.error.name}).');
    }
    if (v.playerState != _last) {
      _last = v.playerState;
      onPlaying?.call(v.playerState == PlayerState.playing ||
          v.playerState == PlayerState.buffering);
      if (v.playerState == PlayerState.ended) _fireEnded();
    }
  }

  void _fireEnded() {
    if (_endedFired) return;
    _endedFired = true;
    onEnded?.call();
  }

  /// Con la pantalla apagada Android puede bloquear el autoplay del video
  /// siguiente: se insiste con "play" unos segundos hasta que suene.
  void _startNudge() {
    _nudge?.cancel();
    var tries = 0;
    _nudge = Timer.periodic(const Duration(milliseconds: 1500), (t) {
      tries++;
      // Hasta ~30 s (con la pantalla apagada YouTube tarda en dejar sonar).
      if (_last == PlayerState.playing || tries > 20) {
        t.cancel();
        return;
      }
      controller?.playVideo();
    });
  }

  Future<void> _poll() async {
    final c = controller;
    if (c == null || _videoId.isEmpty) return;
    try {
      final t = await c.currentTime;
      final d = await c.duration;
      onTick?.call(Duration(milliseconds: (t * 1000).round()),
          d > 0 ? Duration(milliseconds: (d * 1000).round()) : null);
      // Respaldo: si el evento "terminó" no llega (pantalla apagada),
      // se detecta por la posición.
      if (d > 5 && t >= d - 0.6) _fireEnded();
    } catch (_) {}
  }

  Future<void> play() async => controller?.playVideo();
  Future<void> pause() async => controller?.pauseVideo();
  /// 0–100. Lo usa el fundido entre canciones y el temporizador.
  Future<void> setVolume(int v) async {
    try {
      await controller?.setVolume(v.clamp(0, 100));
    } catch (_) {}
  }
  Future<void> seek(Duration p) async =>
      controller?.seekTo(seconds: p.inMilliseconds / 1000.0, allowSeekAhead: true);

  void dispose() {
    _timer?.cancel();
    _nudge?.cancel();
    _sub?.cancel();
    controller?.close();
  }
}
