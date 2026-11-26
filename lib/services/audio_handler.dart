import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpClient;

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart' as yt show PlayerState;
import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/song.dart';
import 'deezer_service.dart';
import 'embed_bridge.dart';
import 'eq_service.dart';
import 'library_service.dart';
import 'music_api_service.dart';
import 'stream_resolver.dart';
import 'data_saver.dart';
import 'block_service.dart';
import 'music_mode.dart';
import 'radio_now.dart';
import 'song_fix.dart';


/// Estado observable compartido entre el handler y PlaybackService.
/// Lo crea PlaybackService (así los streams existen antes de init()).
class PlaybackSubjects {
  final BehaviorSubject<Song?> currentSong = BehaviorSubject<Song?>.seeded(null);
  final BehaviorSubject<bool> playing = BehaviorSubject<bool>.seeded(false);
  final BehaviorSubject<bool> loading = BehaviorSubject<bool>.seeded(false);
  final BehaviorSubject<String?> error = BehaviorSubject<String?>.seeded(null);
  final BehaviorSubject<Duration> position =
      BehaviorSubject<Duration>.seeded(Duration.zero);
  final BehaviorSubject<Duration?> duration =
      BehaviorSubject<Duration?>.seeded(null);
  final BehaviorSubject<List<Song>> queue =
      BehaviorSubject<List<Song>>.seeded(const <Song>[]);
  final BehaviorSubject<int?> currentIndex = BehaviorSubject<int?>.seeded(null);

  /// 0 = sin repetir, 1 = repetir lista, 2 = repetir canción.
  final BehaviorSubject<int> repeat = BehaviorSubject<int>.seeded(0);

  /// Temporizador para dormir: null = apagado; texto con el tiempo restante.
  final BehaviorSubject<String?> sleepLabel = BehaviorSubject<String?>.seeded(null);
}

/// Handler de audio_service: gestiona cola, resolución de URL y just_audio.
/// La cola la llevamos nosotros (no ConcatenatingAudioSource) porque las URL
/// de YouTube se resuelven de forma perezosa y caducan.
class RockPlayAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  RockPlayAudioHandler(this._s) {
    _init();
  }

  final PlaybackSubjects _s;
  final AudioPlayer _player = AudioPlayer(
    audioPipeline: AudioPipeline(androidAudioEffects: [EqService.instance.androidEq]),
  );
  final MusicApiService _api = MusicApiService();
  final StreamResolver _resolver = StreamResolver.instance;

  List<Song> _songs = <Song>[];
  int _index = -1;
  int _gen = 0; // token de la carga vigente
  bool _resolving = false;
  int _recoveredIndex = -1;
  int _prefetchedFor = -2;

  String _stage = '';
  final DeezerService _deezer = DeezerService();
  DateTime? _ytDownUntil;
  String _notice = '';
  String _progress = '';
  Timer? _tick;
  static const int _maxConsecutiveFailures = 2;
  String _lastDetail = '';
  bool _embedPlaying = false;
  int _chainSkips = 0; // canciones saltadas seguidas por no poder reproducirse
  final Set<String> _badIds = <String>{};
  final Map<int, int> _altTries = <int, int>{};
  String _handledErrFor = '';
  int _embedFails = 0;
  Duration _embedPos = Duration.zero;
  Duration? _resumeAt; // posición pendiente al restaurar la cola
  Timer? _saveTimer;
  Timer? _sleepTimer;
  DateTime? _sleepAt;
  bool _sleepEndOfSong = false;

  // ---- Vigilante: la música debe sonar (fuera de la app / pantalla apagada).
  /// El usuario quiere que suene (se apaga al pausar, detener, dormir o
  /// terminar la cola).
  bool _wantPlay = false;
  /// Llamada u otra app con audio: no pelear por el sonido.
  bool _interrupted = false;
  Duration _wdLastPos = Duration.zero;
  int _wdStuck = 0;
  Timer? _watchdog;
  bool _radio = false; // sonando una emisora en vivo con just_audio

  // ---- Volumen suave: fundido entre canciones y al apagar con el temporizador.
  double _sleepVol = 1, _edgeVol = 1, _rampVol = 1, _appliedVol = 1;
  double _duckVol = 1; // el locutor habla: la música baja
  bool _fadeIn = false;
  Timer? _rampTimer;

  /// Locutor: baja la música mientras habla.
  void duck(bool on) {
    _duckVol = on ? 0.22 : 1;
    _applyVol();
  }

  /// Despertador: el volumen empieza bajo y sube hasta el máximo en [d].
  void rampUp(Duration d) {
    _rampTimer?.cancel();
    _rampVol = 0.4;
    _applyVol();
    final start = DateTime.now();
    _rampTimer = Timer.periodic(const Duration(milliseconds: 500), (t) {
      final f = DateTime.now().difference(start).inMilliseconds /
          d.inMilliseconds;
      _rampVol = f >= 1 ? 1 : 0.4 + 0.6 * f;
      _applyVol();
      if (f >= 1) t.cancel();
    });
  }

  void _applyVol() {
    var v = _sleepVol < _edgeVol ? _sleepVol : _edgeVol;
    if (_rampVol < v) v = _rampVol;
    if (_duckVol < v) v = _duckVol;
    if (v < 0) v = 0;
    if (v > 1) v = 1;
    if ((v - _appliedVol).abs() < 0.04 && v != 1 && v != 0) return;
    if (v == _appliedVol) return;
    _appliedVol = v;
    try {
      unawaited(_player.setVolume(v));
    } catch (_) {}
    unawaited(EmbedBridge.instance.setVolume((v * 100).round()));
  }

  /// Baja el volumen en los últimos segundos y lo sube al empezar la
  /// siguiente, para que el cambio no sea un corte seco.
  void _edgeFade(Duration pos, Duration? dur) {
    const outMs = 2500, inMs = 1500;
    var e = 1.0;
    final p = pos.inMilliseconds;
    if (_fadeIn) {
      e = p / inMs;
      if (e < 0.3) e = 0.3;
      if (e >= 1) {
        e = 1;
        _fadeIn = false;
      }
    }
    final d = dur?.inMilliseconds ?? 0;
    if (d > 20000 && hasNextTrack && _s.repeat.value != 2) {
      final left = d - p;
      if (left < outMs) {
        final o = left <= 0 ? 0.3 : 0.3 + 0.7 * left / outMs;
        if (o < e) e = o;
      }
    }
    _edgeVol = e;
    _applyVol();
  }
  StreamSubscription<IcyMetadata?>? _icySub;

  // ------------------------------------------------------------------ init

  Future<void> _init() async {
    await BadVideos.load();
    _badIds.addAll(BadVideos.ids);
    final eb = EmbedBridge.instance;
    eb.onPlaying = (p) {
      if (p) _chainSkips = 0;
      // Con «Ver video», una pausa en el propio video es tuya: el vigilante
      // no debe reanudarla.
      if (!p &&
          eb.slot.value != null &&
          eb.state == yt.PlayerState.paused &&
          !_interrupted) {
        _wantPlay = false;
      }
      _embedPlaying = p;
      _s.playing.add(p);
      _broadcast();
    };
    eb.onTick = (pos, dur) {
      _embedPos = pos;
      if (_embedPlaying) _edgeFade(pos, dur ?? _s.duration.valueOrNull);
      if (!_resolving) {
        _s.position.add(pos);
        if (dur != null && _s.duration.valueOrNull != dur) {
          _s.duration.add(dur);
          if (_index >= 0 &&
              _index < _songs.length &&
              dur.inSeconds > 0 &&
              (_songs[_index].durationMs - dur.inMilliseconds).abs() > 1500) {
            _songs[_index] = _songs[_index].withDuration(dur);
            _scheduleSave();
          }
          final item = mediaItem.value;
          if (item != null) mediaItem.add(item.copyWith(duration: dur));
        }
      }
    };
    Timer.periodic(const Duration(seconds: 20), (_) {
      if (_embedPlaying) _saveNow();
    });
    eb.onEnded = () {
      if (_sleepEndOfSong) {
        _clearSleep();
        _wantPlay = false;
        unawaited(StopLog.record(
            'El temporizador de dormir apagó la música (al terminar la canción).'));
        EmbedBridge.instance.pause();
        return;
      }
      final rep = _s.repeat.value;
      if (rep == 2 && _index >= 0) {
        EmbedBridge.instance.rearm();
        EmbedBridge.instance.seek(Duration.zero);
        EmbedBridge.instance.play();
      } else if (hasNextTrack) {
        _startAt(_index + 1);
      } else if (rep == 1 && _songs.isNotEmpty) {
        _startAt(0);
      } else {
        _wantPlay = false; // terminó la cola
        _embedPlaying = false;
        _s.playing.add(false);
        _broadcast();
      }
    };
    eb.onError = (m) => _onEmbedError(m);
    _watchdog = Timer.periodic(const Duration(seconds: 4), (_) => _checkStall());
    try {
      final session = await AudioSession.instance;
      await session.configure(AudioSessionConfiguration.music());
      // Llamadas y otras apps: el video de YouTube no pausa solo; se hace
      // aquí y se reanuda al terminar la interrupción.
      session.interruptionEventStream.listen((e) {
        if (!_useEmbed || _radio) return;
        if (e.begin) {
          if (e.type != AudioInterruptionType.duck && _wantPlay) {
            _interrupted = true;
            unawaited(EmbedBridge.instance.pause());
          }
        } else if (_interrupted) {
          _interrupted = false;
          if (_wantPlay && e.type != AudioInterruptionType.unknown) {
            unawaited(EmbedBridge.instance.play());
          }
        }
      });
      // Audífonos desconectados: pausar (no seguir por el parlante).
      session.becomingNoisyEventStream.listen((_) {
        if (_useEmbed && !_radio) unawaited(pause());
      });
      // just_audio (handleInterruptions: true) ya pausa/reanuda con las
      // interrupciones de audio_session (llamadas, otras apps, auriculares).
    } catch (_) {}

    _player.playbackEventStream.listen(
      (_) => _broadcast(),
      onError: (Object e, StackTrace st) => _recover(),
    );
    _player.playingStream.listen((p) {
      if (_useEmbed && !_radio) return;
      _s.playing.add(p);
      _broadcast();
    });
    _player.positionStream.listen((p) {
      if (!_resolving && !_radio) _s.position.add(p);
    });
    _player.durationStream.listen((d) {
      _s.duration.add(d);
      final item = mediaItem.value;
      if (d != null && item != null && item.duration != d) {
        mediaItem.add(item.copyWith(duration: d));
      }
    });
    _player.processingStateStream.listen((st) {
      if (st == ProcessingState.completed && !_resolving && !_radio) {
        if (hasNextTrack) {
          _startAt(_index + 1);
        } else {
          _player.pause();
          _player.seek(Duration.zero);
        }
      }
    });
  }

  bool get hasNextTrack => _index >= 0 && _index + 1 < _songs.length;
  bool get hasPreviousTrack => _index > 0;

  // ---------------------------------------------------------- API de cola

  Future<void> playQueue(List<Song> songs, int index) async {
    if (songs.isEmpty) return;
    MusicModeService.queueMode = MusicModeService.mode.value;
    // Quita artistas bloqueados, pero respeta la canción que tocaste.
    final chosen = songs[index.clamp(0, songs.length - 1)];
    final bl = BlockService.instance;
    _songs = [
      for (final s in songs)
        if (identical(s, chosen) || !bl.isBlockedSong(s)) s
    ];
    final i = _songs.indexOf(chosen).clamp(0, _songs.length - 1);
    _publishQueue();
    await _startAt(i);
  }

  void _publishQueue() {
    _scheduleSave();
    _s.queue.add(List<Song>.unmodifiable(_songs));
    queue.add([for (var i = 0; i < _songs.length; i++) _item(_songs[i], i)]);
  }

  /// Los títulos de YouTube traen códigos HTML (I&#39;m → I'm).
  static String _unescape(String t) => t
      .replaceAll('&#39;', "'")
      .replaceAll('&#039;', "'")
      .replaceAll('&quot;', '"')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&');

  MediaItem _item(Song s, int i, {Duration? duration}) {
    // Carátula: la de la canción o, si no hay, la miniatura del video
    // (así se ve también en la notificación, la pantalla de bloqueo y widgets).
    final art = s.image.isNotEmpty
        ? s.image
        : (s.videoId.isNotEmpty ? 'https://i.ytimg.com/vi/${s.videoId}/hqdefault.jpg' : '');
    return MediaItem(
      id: s.videoId.isNotEmpty ? s.videoId : 'q$i:${s.query}',
      title: _unescape(s.title),
      artist: _unescape(s.artist),
      album: s.album.isEmpty ? null : s.album,
      artUri: art.isEmpty ? null : Uri.tryParse(art),
      duration: duration,
    );
  }

  void _setIndex(int i) {
    _index = i;
    _scheduleSave();
    final song = _songs[i];
    _s.currentIndex.add(i);
    _s.currentSong.add(song);
    _s.position.add(Duration.zero);
    _s.duration.add(
        song.durationMs > 0 ? Duration(milliseconds: song.durationMs) : null);
    mediaItem.add(_item(song, i));
  }

  void _replaceSong(int i, Song song) {
    _songs[i] = song;
    _publishQueue();
    if (i == _index) {
      _s.currentSong.add(song);
      mediaItem.add(_item(song, i, duration: _player.duration));
    }
  }

  // ----------------------------------------------------------- Carga/avance

  /// Carga y reproduce la canción [index]; si falla, avisa y salta a la
  /// siguiente (hasta [_maxConsecutiveFailures] seguidas).
  bool _useEmbed = true;
  int _audioFails = 0; // fallos seguidos de solo audio en esta sesión

  Future<void> _startAt(int index,
      {Duration? resumeAt, bool fresh = false}) async {
    _wantPlay = true;
    _wdStuck = 0;
    final live = index >= 0 && index < _songs.length && _songs[index].isRadio;
    _fadeIn = !live && resumeAt == null;
    _edgeVol = _fadeIn ? 0.3 : 1;
    _applyVol();
    if (!DataSaver.instance.audioOnly ||
        _audioFails >= 2 ||
        (index >= 0 && index < _songs.length && _songs[index].isRadio)) {
      _useEmbed = true;
      return _startEmbed(index);
    }
    if (_useEmbed) {
      _useEmbed = false;
      _embedPlaying = false;
      try {
        unawaited(EmbedBridge.instance.pause());
      } catch (_) {}
    }
    final gen = ++_gen;
    var i = index;
    var fails = 0;
    var forceFresh = fresh;
    if (resumeAt == null) _recoveredIndex = -1;

    while (true) {
      if (gen != _gen) return;
      _setIndex(i);
      _resolving = true;
      unawaited(_player.pause());
      StreamResolver.onProgress = (m) => _progress = m;
      _progress = '';
      final t0 = DateTime.now();
      _tick?.cancel();
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!_resolving) {
          _tick?.cancel();
          return;
        }
        final secs = DateTime.now().difference(t0).inSeconds;
        _s.error.add(secs < 4 ? null : 'Cargando la canción…');
      });
      if (fails == 0) _s.error.add(null);
      _broadcast();

      final song = _songs[i];
      String? failure;
      try {
        final ok = await _loadSong(i, gen, forceFresh)
            .timeout(const Duration(seconds: 20));
        if (ok == null) return; // reemplazada por otra carga
        if (ok) {
          _resolving = false;
          _audioFails = 0;
          if (_notice.isNotEmpty) {
            _emitError(_notice);
            _notice = '';
          }
          if (resumeAt != null) await _player.seek(resumeAt);
          unawaited(_player.play());
          _broadcast();
          final current = _songs[i];
          unawaited(LibraryService.instance
              .addToHistory(current)
              .catchError((_) {}));
          _prefetchNext();
          return;
        }
        failure = 'No se pudo reproducir. $_lastDetail';
      } on StreamResolveException catch (e) {
        failure = e.message;
      } catch (e) {
        failure = 'Error: $e | etapa: $_stage | $_lastDetail';
      }

      if (gen != _gen) return;
      if (fails == 0 && !_radio) {
        // Solo audio falló: usar el reproductor de YouTube para esta canción.
        _audioFails++;
        _tick?.cancel();
        _s.error.add(null);
        _resolving = false;
        _useEmbed = true;
        try {
          await _player.stop();
        } catch (_) {}
        return _startEmbed(i);
      }
      fails++;
      forceFresh = false;
      resumeAt = null;
      _emitError(failure ?? 'Error de reproducción.');
      if (i + 1 < _songs.length && fails < _maxConsecutiveFailures) {
        i++;
        continue;
      }
      // Sin más canciones o demasiados fallos seguidos: detenerse.
      _resolving = false;
      try {
        await _player.stop();
      } catch (_) {}
      if (fails >= _maxConsecutiveFailures) {
        _emitError('Se detuvo. Último error: ${failure ?? "?"}');
        unawaited(StopLog.record(
            'Se detuvo por varios errores seguidos. Último: ${failure ?? "?"}'));
      }
      _broadcast();
      return;
    }
  }

  /// Limpia un título de YouTube para buscar otra versión: quita números de
  /// pista, años, paréntesis y palabras como HD / Official / Live.
  static String _cleanQuery(String q) {
    var t = q
        .replaceAll(RegExp(r'[\[\(][^\]\)]*[\]\)]'), ' ')
        .replaceAll(RegExp(r'^\s*\d{1,2}\s*[-.)]\s*'), '')
        .replaceAll(
            RegExp(
                r'\b(hd|hq|4k|official|oficial|video|audio|lyrics?|letra|live|en vivo|remaster(ed)?|studio version|version)\b',
                caseSensitive: false),
            ' ')
        .replaceAll(RegExp(r'\b(19|20)\d{2}\b'), ' ')
        .replaceAll(RegExp(r'\s+-\s+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return t.isEmpty ? q : t;
  }

  /// El video no se puede incrustar (o falló): prueba otra versión de la misma
  /// canción (letra / audio / Topic); si no hay, salta a la siguiente.
  Future<void> _onEmbedError(String message) async {
    if (_index < 0 || _index >= _songs.length) return;
    final idx = _index;
    final gen = _gen;
    final song = _songs[idx];
    if (song.videoId.isEmpty || _handledErrFor == song.videoId) return;
    _handledErrFor = song.videoId;
    _badIds.add(song.videoId);
    unawaited(BadVideos.add(song.videoId, title: song.title, artist: song.artist));
    final tries = (_altTries[idx] ?? 0) + 1;
    _altTries[idx] = tries;

    if (tries <= 4) {
      final base = _cleanQuery(song.query.isNotEmpty
          ? song.query
          : '${song.title} ${song.artist}');
      const suffixes = ['topic', 'official audio', 'lyrics', 'audio'];
      final api = MusicApiService();
      String? id;
      try {
        id = await api.findEmbeddable(
            '$base ${suffixes[(tries - 1) % suffixes.length]}', _badIds);
        if (id != null) _embedOk.add(id);
      } catch (_) {
      } finally {
        try {
          api.dispose();
        } catch (_) {}
      }
      if (gen != _gen || idx != _index) return;
      if (id != null) {
        final alt = song.withVideoId(id);
        _replaceSong(idx, alt);
        _s.error.add(null);
        EmbedBridge.instance.load(id);
        return;
      }
    }
    _chainSkips++;
    SkipLog.add('«${song.title}»: ${message.replaceFirst('YouTube no permite reproducir este video aquí', 'bloqueado por YouTube')} · ${MusicApiService.lastDebug}');
    if (_chainSkips >= 4) {
      // Varias seguidas sin sonar: no seguir saltando en silencio.
      _chainSkips = 0;
      _resolving = false;
      _wantPlay = false;
      _broadcast();
      unawaited(StopLog.record(
          'Se detuvo: varias canciones seguidas están bloqueadas por YouTube.'));
      _emitError('Se detuvo: varias canciones seguidas no están disponibles. '
          'Toca siguiente para probar otra.',
          seconds: 3600);
      return;
    }
    final shortTitle = song.title.length > 34
        ? '${song.title.substring(0, 34)}…'
        : song.title;
    _emitError('Omitimos «$shortTitle»: no está disponible.', seconds: 12);
    if (hasNextTrack) {
      Future<void>.delayed(const Duration(milliseconds: 900), () {
        if (idx == _index && gen == _gen && hasNextTrack) {
          _startAt(idx + 1);
        }
      });
    }
  }

  /// Modo YouTube IFrame: solo busca el videoId y se lo pasa al WebView.
  /// Emisora en vivo: just_audio reproduce la transmisión directamente.
  Future<void> _startRadio(int index) async {
    final gen = ++_gen;
    _setIndex(index);
    _s.error.add(null);
    _embedPlaying = false;
    unawaited(EmbedBridge.instance.pause());
    _radio = true;
    _resolving = true;
    _s.playing.add(false);
    _broadcast();
    final song = _songs[index];
    try {
      await _player.setUrl(song.url).timeout(const Duration(seconds: 25));
      unawaited(EqService.instance.applyAndroid());
      if (gen != _gen) return;
      _resolving = false;
      await _icySub?.cancel();
      RadioNow.reset();
      _icySub = _player.icyMetadataStream.listen((m) {
        final t = (m?.info?.title ?? '').trim();
        if (t.isEmpty || !_radio || _index != index || index >= _songs.length) {
          return;
        }
        final cur = _songs[index];
        unawaited(RadioNow.heard(cur.title, t));
        if (cur.artist == t) return;
        _songs[index] = Song(
            title: cur.title,
            artist: t,
            album: cur.album,
            image: cur.image,
            url: cur.url,
            query: cur.query);
        _s.currentSong.add(_songs[index]);
        mediaItem.add(_item(_songs[index], index));
      });
      unawaited(_player.play());
      _broadcast();
    } catch (_) {
      if (gen != _gen) return;
      _resolving = false;
      _emitError('No se pudo conectar con la emisora.');
      _broadcast();
    }
  }

  Future<void> _startEmbed(int index) async {
    if (index >= 0 && index < _songs.length && _songs[index].isRadio) {
      return _startRadio(index);
    }
    if (_radio) {
      _radio = false;
      RadioNow.reset();
      await _icySub?.cancel();
      _icySub = null;
      try {
        await _player.stop();
      } catch (_) {}
    }
    final gen = ++_gen;
    _setIndex(index);
    // Título o artista dudoso (canal de letras, «♫Lyrics»): se corrige al
    // empezar a sonar, no solo al guardar en el historial.
    final cur = _songs[index];
    if (SongFix.doubtful(cur)) {
      SongFix.verify(cur).then((f) {
        if (index >= _songs.length) return;
        final now = _songs[index];
        // Misma canción (aunque ya tenga su video): solo cambia el texto.
        if (now.title == cur.title &&
            now.artist == cur.artist &&
            (f.title != cur.title || f.artist != cur.artist)) {
          _replaceSong(index, now.withMeta(title: f.title, artist: f.artist));
        }
      });
    }
    _s.error.add(null);
    _altTries.remove(index);
    _handledErrFor = '';
    _embedPos = Duration.zero;
    _embedPlaying = false;
    _s.playing.add(false);
    _resolving = true;
    _broadcast();
    var song = _songs[index];
    try {
      if (song.videoId.isEmpty) {
        final q =
            song.query.isNotEmpty ? song.query : '${song.artist} ${song.title}';
        _s.error.add('Buscando «${song.title}»…');
        String? id;
        Object? lastErr;
        final dbg = <String>[];
        for (final qq in [
          q,
          '$q official audio',
          '${song.title} ${song.artist}',
        ]) {
          // Instancia nueva por intento: evita conexiones colgadas.
          final api = MusicApiService();
          try {
            id = await api
                .findEmbeddable(qq, _badIds)
                .timeout(const Duration(seconds: 25));
            if (id != null) _embedOk.add(id);
          } catch (e) {
            lastErr = e;
          } finally {
            try {
              api.dispose();
            } catch (_) {}
          }
          if (gen != _gen) return;
          if (id != null) break;
          dbg.add('${lastErr != null ? 'error ${lastErr.toString().split('\n').first}' : MusicApiService.lastDebug}');
          _s.error.add('Buscando «${song.title}»…');
        }
        _s.error.add(null);
        if (id == null) {
          _resolving = false;
          _embedFails++;
          _emitError('Pasando a la siguiente…');
          _broadcast();
          if (_embedFails < 3 && index + 1 < _songs.length) {
            Future<void>.delayed(const Duration(milliseconds: 600), () {
              if (gen == _gen) _startAt(index + 1);
            });
          }
          return;
        }
        _embedFails = 0;
        song = song.withVideoId(id);
        _replaceSong(index, song);
      }
    } catch (e) {
      if (gen != _gen) return;
      _resolving = false;
      _emitError('Error buscando en YouTube: $e');
      _broadcast();
      return;
    }
    // Comprueba antes de cargar que el video se puede incrustar: así el
    // cambio a otra versión ocurre sin mostrar el error gris.
    if (!_embedOk.contains(song.videoId)) {
      final ok = await _embeddable(song.videoId, 4);
      if (gen != _gen) return;
      if (ok) {
        _embedOk.add(song.videoId);
      } else {
        _resolving = false;
        _broadcast();
        _onEmbedError('no incrustable');
        return;
      }
    }
    _resolving = false;
    final rs = _resumeAt;
    _resumeAt = null;
    EmbedBridge.instance.load(song.videoId,
        start: rs == null ? 0 : rs.inMilliseconds / 1000.0);
    _broadcast();
    _prefetchAhead(gen);
  }

  final Set<String> _embedOk = <String>{};
  bool _prefBusy = false;
  int _removed = 0;

  Future<bool> _embeddable(String id, int seconds) =>
      MusicApiService.embeddable(id, seconds);

  Future<String?> _altFind(String q) async {
    final api = MusicApiService();
    try {
      return await api
          .findEmbeddable(q, _badIds)
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      return null;
    } finally {
      try {
        api.dispose();
      } catch (_) {}
    }
  }

  /// Deja lista la canción n: con videoId que se pueda incrustar (buscando
  /// otra versión si hace falta). true = lista, false = no hay forma,
  /// null = la cola cambió mientras tanto.
  Future<bool?> _prepare(int n, int gen) async {
    if (_songs[n].isRadio) return true;
    var s0 = _songs[n];
    final title = s0.title;
    final base = _cleanQuery(
        s0.query.isNotEmpty ? s0.query : '${s0.artist} ${s0.title}');
    var ok = s0.videoId.isNotEmpty && _embedOk.contains(s0.videoId);
    if (!ok && s0.videoId.isNotEmpty) {
      ok = await _embeddable(s0.videoId, 6);
      if (!ok) {
        _badIds.add(s0.videoId);
        unawaited(BadVideos.add(s0.videoId, title: s0.title, artist: s0.artist));
      }
    }
    if (gen != _gen) return null;
    if (!ok) {
      for (final q in [
        '$base topic',
        '$base official audio',
        '$base lyrics',
        base,
      ]) {
        final id = await _altFind(q);
        if (gen != _gen) return null;
        if (id != null) {
          s0 = s0.withVideoId(id);
          ok = true;
          break;
        }
      }
    }
    if (gen != _gen || n >= _songs.length || _songs[n].title != title) {
      return null;
    }
    if (!ok) return false;
    if (s0.videoId != _songs[n].videoId) _replaceSong(n, s0);
    _embedOk.add(s0.videoId);
    return true;
  }

  /// Mientras suena la actual, prepara las 3 siguientes. Las que no se pueden
  /// reproducir en la app se quitan de la cola sin que se note el salto.
  void _prefetchAhead(int gen) {
    if (_prefBusy) return;
    _prefBusy = true;
    () async {
      try {
        var n = _index + 1;
        var done = 0;
        while (done < 3 && n < _songs.length && gen == _gen) {
          final title = _songs[n].title;
          final r = await _prepare(n, gen);
          if (r == null) break;
          if (r == false) {
            if (n < _songs.length && _songs[n].title == title) {
              _songs.removeAt(n);
              _removed++;
              _publishQueue();
            }
            continue; // la siguiente ocupa ahora el lugar n
          }
          done++;
          n++;
        }
      } catch (_) {
      } finally {
        _prefBusy = false;
      }
    }();
  }

  /// true = cargada; false = falló; null = superada por otra carga.
  Future<bool?> _loadSong(int i, int gen, bool fresh) async {
    var song = _songs[i];
    if (song.videoId.isEmpty) {
      final q = song.query.isNotEmpty ? song.query : '${song.artist} ${song.title}';
      _stage = 'buscando';
      final id = await _api.findVideoId(q);
      if (gen != _gen) return null;
      if (id == null) return false;
      song = song.withVideoId(id);
      _replaceSong(i, song);
    }
    final exclude = <String>{};
    final down = _ytDownUntil;
    if (down != null && DateTime.now().isBefore(down)) {
      return _loadPreview(song, gen);
    }
    for (var attempt = 0; attempt < 2; attempt++) {
      _stage = 'resolviendo';
      ResolvedStream rs;
      try {
        rs = await _resolver.resolve(
          song.videoId,
          force: fresh || attempt > 0,
          exclude: exclude,
        );
      } on StreamResolveException {
        // YouTube bloquea esta conexión: usar vista previa de Deezer (30 s).
        _ytDownUntil = DateTime.now().add(const Duration(minutes: 3));
        return _loadPreview(song, gen);
      }
      if (gen != _gen) return null;
      try {
        _stage = 'cargando ${rs.source}';
        _lastDetail = 'probó ${rs.source}';
        await _player
            .setAudioSource(AudioSource.uri(
              rs.uri,
              headers: rs.headers.isEmpty ? null : rs.headers,
            ))
            .timeout(const Duration(seconds: 20));
        if (gen != _gen) return null;
        return true;
      } on PlayerInterruptedException {
        return null;
      } catch (e) {
        _lastDetail = '${rs.source}: $e';
        // Típicamente 403 / URL caducada: descarta y reintenta una vez
        // evitando la misma fuente.
        _resolver.invalidate(song.videoId);
        exclude.add(rs.source);
        if (attempt == 1) return false;
      }
    }
    return false;
  }

  /// Respaldo: vista previa de 30 s desde Deezer (sin clave, sin bloqueo).
  Future<bool?> _loadPreview(Song song, int gen) async {
    _stage = 'vista previa';
    final q = song.query.isNotEmpty ? song.query : '${song.artist} ${song.title}';
    String? url;
    try {
      url = await _deezer.previewUrl(q);
    } catch (e) {
      _lastDetail = 'deezer: $e';
      return false;
    }
    if (gen != _gen) return null;
    if (url == null) {
      _lastDetail = 'deezer: sin vista previa para "$q"';
      return false;
    }
    try {
      await _player
          .setAudioSource(AudioSource.uri(Uri.parse(url)))
          .timeout(const Duration(seconds: 20));
      if (gen != _gen) return null;
      _notice =
          'Vista previa de 30 s: YouTube bloquea el audio completo en esta conexión.';
      return true;
    } on PlayerInterruptedException {
      return null;
    } catch (e) {
      _lastDetail = 'preview: $e';
      return false;
    }
  }

  /// Error durante la reproducción (URL caducada, 403 a mitad de canción):
  /// reintenta una vez con URL nueva desde la misma posición; si vuelve a
  /// fallar, salta a la siguiente.
  Future<void> _recover() async {
    if (_radio) {
      if (!_resolving) {
        _emitError('Se cortó la transmisión. Toca play para reconectar.');
        _broadcast();
      }
      return;
    }
    if (_resolving || _index < 0) return;
    final song = _songs[_index];
    if (_recoveredIndex == _index) {
      _emitError('Se interrumpió «${song.title}».');
      if (hasNextTrack) {
        await _startAt(_index + 1);
      } else {
        await _player.pause();
      }
      return;
    }
    _recoveredIndex = _index;
    final pos = _player.position;
    _resolver.invalidate(song.videoId);
    await _startAt(_index, resumeAt: pos, fresh: true);
  }

  /// Resuelve en segundo plano la siguiente canción (videoId + URL).
  void _prefetchNext() {
    final n = _index + 1;
    if (n >= _songs.length || _prefetchedFor == n) return;
    _prefetchedFor = n;
    final gen = _gen;
    () async {
      try {
        var s = _songs[n];
        if (s.videoId.isEmpty) {
          final q = s.query.isNotEmpty ? s.query : '${s.artist} ${s.title}';
          final id = await _api.findVideoId(q);
          if (id == null || gen != _gen) return;
          s = s.withVideoId(id);
          _replaceSong(n, s);
        }
        await _resolver.resolve(s.videoId);
      } catch (_) {
        _prefetchedFor = -2; // permitir reintento en la carga real
      }
    }();
  }

  void _emitError(String msg, {int seconds = 40}) {
    _s.error.add(msg);
    Future<void>.delayed(Duration(seconds: seconds), () {
      if (_s.error.valueOrNull == msg) _s.error.add(null);
    });
  }

  // --------------------------------------------------------------- Estado

  /// Cada 4 s: si debería sonar y el video está quieto (YouTube no arrancó
  /// la siguiente con la pantalla apagada, se quedó cargando o el WebView
  /// se pausó), lo reanima: play → recargar en el mismo punto → siguiente.
  void _checkStall() {
    if (!_wantPlay || _interrupted || !_useEmbed || _radio || _resolving) {
      _wdStuck = 0;
      return;
    }
    if (_index < 0 || _index >= _songs.length) return;
    final pos = _embedPos;
    final moving = (pos - _wdLastPos).inMilliseconds.abs() > 500;
    _wdLastPos = pos;
    if (_embedPlaying && moving) {
      _wdStuck = 0;
      return;
    }
    _wdStuck++;
    final eb = EmbedBridge.instance;
    final vid = _songs[_index].videoId;
    if (_wdStuck == 2) {
      unawaited(eb.play()); // ~8 s quieta
    } else if (_wdStuck == 4 && vid.isNotEmpty) {
      // ~16 s: recargar el video donde iba.
      eb.load(vid, start: pos.inMilliseconds / 1000.0);
    } else if (_wdStuck == 6 && vid.isNotEmpty) {
      eb.load(vid, start: pos.inMilliseconds / 1000.0);
    } else if (_wdStuck >= 8) {
      // ~32 s sin sonar: pasar a la siguiente (y anotarlo).
      _wdStuck = 0;
      SkipLog.add('«${_songs[_index].title}»: se quedó sin sonar fuera de la app; pasé a la siguiente.');
      if (hasNextTrack) {
        _startAt(_index + 1);
      } else if (_s.repeat.value == 1 && _songs.isNotEmpty) {
        _startAt(0);
      }
    }
  }

  void _broadcast() {
    final playing =
        _useEmbed && !_radio ? _embedPlaying : _player.playing;
    // Para Android, mientras quieras música (cambio de canción, búsqueda o
    // carga), la app sigue «sonando»: así el servicio en primer plano no se
    // cae y HyperOS no congela la app entre canciones.
    final keep = playing ||
        (_useEmbed && !_radio && _wantPlay && !_interrupted);
    final ps = _useEmbed && !_radio
        ? ProcessingState.ready
        : _player.processingState;
    final busy = _resolving ||
        ps == ProcessingState.loading ||
        ps == ProcessingState.buffering;
    _s.loading.add(busy);

    final AudioProcessingState aps;
    if (_resolving) {
      aps = AudioProcessingState.loading;
    } else {
      aps = const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[ps]!;
    }

    playbackState.add(PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (keep) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: _radio
          ? const <MediaAction>{}
          : const {
              MediaAction.seek,
              MediaAction.seekForward,
              MediaAction.seekBackward,
            },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: aps,
      playing: keep,
      updatePosition: _radio
          ? Duration.zero
          : (_useEmbed ? _embedPos : _player.position),
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: _index < 0 ? null : _index,
    ));
  }

  // ------------------------------------------------- Controles (AudioHandler)

  @override
  Future<void> play() async {
    _wantPlay = true;
    _interrupted = false;
    _wdStuck = 0;
    if (_radio) {
      // En vivo: reconecta en vez de reanudar lo que quedó en el búfer.
      if (_index >= 0 && !_resolving) return _startRadio(_index);
      return;
    }
    if (_useEmbed) {
      if (_index >= 0 &&
          !_resolving &&
          (_songs[_index].videoId.isEmpty ||
              EmbedBridge.instance.controller == null)) {
        _embedFails = 0;
        return _startAt(_index);
      }
      return EmbedBridge.instance.play();
    }
    if (_index >= 0 &&
        !_resolving &&
        _player.processingState == ProcessingState.idle) {
      await _startAt(_index);
      return;
    }
    if (_player.processingState == ProcessingState.completed) {
      await _player.seek(Duration.zero);
    }
    unawaited(_player.play());
  }

  @override
  Future<void> pause() async {
    _wantPlay = false;
    if (_radio) return _player.pause();
    if (_useEmbed) return EmbedBridge.instance.pause();
    await _player.pause();
  }

  @override
  Future<void> stop() async {
    _wantPlay = false;
    _gen++;
    _resolving = false;
    if (_useEmbed) unawaited(EmbedBridge.instance.pause());
    await _player.stop();
    _radio = false;
    await _icySub?.cancel();
    _icySub = null;
    _broadcast();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    if (_resolving || _radio) return;
    if (_useEmbed) {
      await EmbedBridge.instance.seek(position);
      _s.position.add(position);
      return;
    }
    await _player.seek(position);
    _s.position.add(position);
  }

  @override
  Future<void> skipToNext() async {
    if (hasNextTrack) {
      await _startAt(_index + 1);
    } else if (_s.repeat.value == 1 && _songs.isNotEmpty) {
      await _startAt(0);
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_index < 0) return;
    if (_radio) {
      if (hasPreviousTrack) await _startAt(_index - 1);
      return;
    }
    if (_useEmbed) {
      if (_embedPos > const Duration(seconds: 3) || !hasPreviousTrack) {
        await EmbedBridge.instance.seek(Duration.zero);
        return;
      }
      await _startAt(_index - 1);
      return;
    }
    if (_player.position > const Duration(seconds: 3) || !hasPreviousTrack) {
      await _player.seek(Duration.zero);
      return;
    }
    await _startAt(_index - 1);
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= _songs.length) return;
    await _startAt(index);
  }

  // ------------------------------------------------------- Cola editable

  void qRemove(int i) {
    if (i < 0 || i >= _songs.length || i == _index) return;
    _songs.removeAt(i);
    if (i < _index) _index--;
    _s.currentIndex.add(_index);
    _publishQueue();
  }

  /// [to] como lo entrega ReorderableListView (antes de quitar el elemento).
  void qMove(int from, int to) {
    if (from < 0 || from >= _songs.length) return;
    if (to > from) to--;
    to = to.clamp(0, _songs.length - 1);
    if (from == to) return;
    final s = _songs.removeAt(from);
    _songs.insert(to, s);
    if (from == _index) {
      _index = to;
    } else if (from < _index && to >= _index) {
      _index--;
    } else if (from > _index && to <= _index) {
      _index++;
    }
    _s.currentIndex.add(_index);
    _publishQueue();
  }

  void qPlayNext(Song s) {
    if (_songs.isEmpty) {
      playQueue([s], 0);
      return;
    }
    _songs.insert(_index + 1, s);
    _publishQueue();
  }

  void qAdd(Song s) {
    if (_songs.isEmpty) {
      playQueue([s], 0);
      return;
    }
    _songs.add(s);
    _publishQueue();
  }

  /// Baraja solo lo que viene después de la canción actual.
  void qShuffle() {
    if (_index < 0 || _index + 1 >= _songs.length) return;
    final rest = _songs.sublist(_index + 1)..shuffle();
    _songs = [..._songs.sublist(0, _index + 1), ...rest];
    _publishQueue();
  }

  void setRepeat(int mode) => _s.repeat.add(mode.clamp(0, 2));

  // --------------------------------------------- Temporizador para dormir

  static String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  void _clearSleep() {
    _sleepTimer?.cancel();
    _sleepAt = null;
    _sleepEndOfSong = false;
    _s.sleepLabel.add(null);
    _sleepVol = 1;
    _applyVol();
  }

  /// [d] null y endOfSong false = apagar.
  void setSleep(Duration? d, {bool endOfSong = false}) {
    _clearSleep();
    if (endOfSong) {
      _sleepEndOfSong = true;
      _s.sleepLabel.add('Al terminar la canción');
      return;
    }
    if (d == null) return;
    _sleepAt = DateTime.now().add(d);
    _s.sleepLabel.add(_fmt(d));
    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      final at = _sleepAt;
      if (at == null) {
        t.cancel();
        return;
      }
      final left = at.difference(DateTime.now());
      if (left <= Duration.zero) {
        unawaited(StopLog.record('El temporizador de dormir apagó la música.'));
        // Pausa ya en silencio y luego deja el volumen normal para mañana.
        pause().whenComplete(() {
          Future<void>.delayed(const Duration(milliseconds: 600), _clearSleep);
        });
        t.cancel();
        _sleepAt = null;
      } else {
        // Últimos 30 s: baja el volumen poco a poco.
        if (left.inSeconds < 30) {
          _sleepVol = left.inMilliseconds / 30000;
          _applyVol();
        }
        _s.sleepLabel.add(_fmt(left));
      }
    });
  }

  // ------------------------------------------------ Cola guardada en disco

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), _saveNow);
  }

  Future<void> _saveNow() async {
    try {
      if (_songs.isEmpty || _index < 0) return;
      final sp = await SharedPreferences.getInstance();
      await sp.setString(
        'queue_v1',
        jsonEncode({
          'i': _index,
          'p': _embedPos.inSeconds,
          'd': _s.duration.valueOrNull?.inSeconds,
          's': [for (final s in _songs.take(700)) s.toJson()],
        }),
      );
    } catch (_) {}
  }

  /// Recupera la cola de la sesión anterior (en pausa, lista para ▶).
  Future<void> restore() async {
    try {
      if (_songs.isNotEmpty) return;
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString('queue_v1');
      if (raw == null) return;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final list = [
        for (final e in (j['s'] as List))
          Song.fromJson(Map<String, dynamic>.from(e as Map)),
      ];
      if (list.isEmpty) return;
      _songs = list;
      final i = ((j['i'] as num?)?.toInt() ?? 0).clamp(0, list.length - 1);
      final p = Duration(seconds: (j['p'] as num?)?.toInt() ?? 0);
      _publishQueue();
      _setIndex(i);
      _resumeAt = p > const Duration(seconds: 3) ? p : null;
      _s.position.add(p);
      // Duración conocida al reanudar (sin «--:--»).
      final d = (j['d'] as num?)?.toInt();
      if (d != null && d > 0) _s.duration.add(Duration(seconds: d));
      _broadcast();
      unawaited(_fixQueueTitles());
    } catch (_) {}
  }

  /// Corrige en segundo plano los títulos dudosos de la cola restaurada
  /// («Shakira · No», canales de productoras), sin esperar a que suenen.
  Future<void> _fixQueueTitles() async {
    var n = 0;
    for (var i = 0; i < _songs.length && n < 30; i++) {
      final cur = _songs[i];
      if (cur.isRadio || !SongFix.doubtful(cur)) continue;
      n++;
      final f = await SongFix.verify(cur);
      if (i < _songs.length &&
          identical(_songs[i], cur) &&
          (f.title != cur.title || f.artist != cur.artist)) {
        _replaceSong(i, cur.withMeta(title: f.title, artist: f.artist));
        _scheduleSave();
      }
    }
  }

  @override
  Future<void> onTaskRemoved() async {
    // Si no está sonando, cerrar el servicio al quitar la app de recientes.
    if (!(_useEmbed ? _embedPlaying : _player.playing)) await stop();
  }
}
