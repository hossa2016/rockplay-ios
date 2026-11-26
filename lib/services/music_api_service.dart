import 'dart:async';
import 'dart:io' show HttpClient;

import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/song.dart';
import 'block_service.dart';

class MusicApiService {
  final YoutubeExplode _yt = YoutubeExplode();

  /// Caché de sesión: consulta normalizada -> videoId.
  static final Map<String, String> _idCache = <String, String>{};
  static final Map<String, Future<String?>> _idInflight =
      <String, Future<String?>>{};

  /// Descarta mixes, recopilaciones, documentales, directos largos, etc.
  static final RegExp _notSong = RegExp(
      r'\bmix\b|split screen|multi-?angle|\d angle|enganchad|megamix|compilation|recopilaci|full album|album completo|'
      r'álbum completo|best of|greatest hits|grandes éxitos|top ?\d+|\d+ (hits|songs|canciones)|'
      r'playlist|documental|documentary|docu\b|biograf|biography|historia de|history of|the story of|story of|'
      r'entrevista|interview|conversación|conversation|podcast|episod|capítulo|capitulo|temporada|season|'
      r'behind the scenes|making of|detrás de|trailer|tráiler|noticias|\bnews\b|análisis|analysis|'
      r'explicad|explained|review|reseña|ranking|mejores canciones|peores|'
      r'por qué|why does|why did|how to|how i |cómo se|como se hizo|qué pasó|que paso|murió|death of|'
      r'full show|full concert|concierto completo|show completo|'
      r'reaction|reacci|tutorial|lesson|clase|cover lesson|karaoke|\banthems\b|\bhours?\b|\bhoras?\b|'
      r'\bvol\.? ?\d|\bdj\b|nightcore|slowed|8d audio|lofi|lo-fi|tribute|tributo|parody|parodia|'
      r'\bamv\b|gameplay|game play|walkthrough|playthrough|let.?s play|speedrun|boss fight|gaming|'
      r'videojuego|video ?game|juego|\bgame\b|\bps[345]\b|xbox|nintendo|minecraft|fortnite|roblox|\bgta\b|'
      r'type ?beat|\[free\]|\bprod\.? by\b|instrumental beat|'
      r'\bpc\b|\bpart ?\d+|\bparte ?\d+|\bep\.? ?\d+|película|\bshorts?\b|fan ?made|soundtrack|\bost\b');

  static final RegExp _badChannel = RegExp(
      r'news|noticias|\btv\b|podcast|documental|documentary|entrevistas|interviews|radio show|cine|films?|gaming|gameplay|games?\b|gamer|juegos|\bplay\b|playstation|xbox|nintendo|esports|speedrun');

  static bool _looksLikeSong(String title, Duration? d, bool live,
      [String author = '']) {
    if (author.isNotEmpty && _badChannel.hasMatch(author.toLowerCase())) {
      return false;
    }
    if (live) return false;
    if (d != null && (d.inSeconds >= 540 || d.inSeconds < 60)) return false;
    return !_notSong.hasMatch(title.toLowerCase());
  }

  Future<List<Song>> search(String query) async {
    var last = <Song>[];
    await for (final l in searchStream(query, max: 60, maxPages: 5)) {
      last = l;
    }
    return last;
  }

  /// Emite la lista acumulada tras cada página de resultados (hasta [max]
  /// canciones o [maxPages] páginas), para poder mostrar la primera enseguida.
  Stream<List<Song>> searchStream(String query,
      {int max = 300, int maxPages = 25, String? mustMention}) async* {
    await BlockService.instance.ensureLoaded();
    await BadVideos.load();
    final wantsCoverQ = query.toLowerCase().contains('cover');
    final needle = mustMention == null ? '' : BlockService.normName(mustMention);
    final q = query.trim();
    if (q.isEmpty) {
      yield <Song>[];
      return;
    }
    final songs = <Song>[];
    final seen = <String>{};
    VideoSearchList? page = await _yt.search.search(q);
    var pages = 0;
    while (page != null && pages < maxPages && songs.length < max) {
      for (final v in page) {
        if (!_looksLikeSong(v.title, v.duration, v.isLive, v.author)) continue;
        if (!seen.add(v.id.value)) continue;
        if (BadVideos.ids.contains(v.id.value)) continue;
        if (!wantsCoverQ &&
            RegExp(r'\bcover\b|covered by', caseSensitive: false)
                .hasMatch(v.title)) {
          continue;
        }
        if (BlockService.instance.isBlockedAuthor(v.author)) continue;
        if (needle.isNotEmpty &&
            !BlockService.norm('${v.title} ${v.author}').contains(needle)) {
          continue;
        }
        final song = Song.fromYoutube(
            title: v.title,
            channel: v.author,
            image: v.thumbnails.mediumResUrl,
            videoId: v.id.value,
          );
        if (BlockService.instance.isBlockedSong(song)) continue;
        songs.add(song);
      }
      pages++;
      yield List<Song>.of(songs);
      if (songs.length >= max) break;
      try {
        page = await page.nextPage().timeout(const Duration(seconds: 8));
      } catch (_) {
        break;
      }
    }
    if (pages == 0) yield songs;
  }

  /// Busca el vídeo de una canción (query = "artista título") y elige el mejor
  /// candidato para audio: prefiere canales "Topic", audio oficial y lyric;
  /// evita directos, vídeos de más de 12 minutos, covers y similares.
  /// Resultado cacheado durante la sesión. Devuelve null si no hay candidato.
  Future<String?> findVideoId(String query) {
    final key = query.trim().toLowerCase();
    if (key.isEmpty) return Future.value(null);
    final hit = _idCache[key];
    if (hit != null) return Future.value(hit);
    final running = _idInflight[key];
    if (running != null) return running;
    final f = _find(query.trim(), key)
        .timeout(const Duration(seconds: 18))
        .whenComplete(() => _idInflight.remove(key));
    _idInflight[key] = f;
    return f;
  }

  /// Diagnóstico de la última búsqueda de video (se muestra si falla).
  static String lastDebug = '';

  // Las búsquedas de apoyo van de una en una y con una pausa corta, para que
  // YouTube no devuelva resultados vacíos por exceso de peticiones.
  static Future<void> _gate = Future<void>.value();
  static Future<T> _serial<T>(Future<T> Function() f) async {
    final prev = _gate;
    final done = Completer<void>();
    _gate = done.future;
    try {
      await prev;
    } catch (_) {}
    try {
      return await f();
    } finally {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      done.complete();
    }
  }

  /// Busca otro video distinto a los de [exclude] (p. ej. uno que sí se pueda
  /// incrustar). Sin caché.
  Future<String?> findVideoIdExcluding(String query, Set<String> exclude) =>
      _find(query.trim(), '', exclude: exclude).timeout(const Duration(seconds: 18));

  /// oEmbed responde 401/404 cuando el dueño no permite incrustar.
  static Future<bool> embeddable(String id, int seconds) async {
    final c = HttpClient()..connectionTimeout = Duration(seconds: seconds);
    try {
      final req = await c
          .getUrl(Uri.parse(
              'https://www.youtube.com/oembed?format=json&url=https://www.youtube.com/watch?v=$id'))
          .timeout(Duration(seconds: seconds));
      final res = await req.close().timeout(Duration(seconds: seconds));
      await res.drain<void>();
      return !(res.statusCode == 401 || res.statusCode == 404);
    } catch (_) {
      return true; // sin respuesta: que lo intente el reproductor
    } finally {
      c.close(force: true);
    }
  }

  /// Mejor video de la búsqueda que SÍ se pueda incrustar: revisa los
  /// primeros candidatos a la vez y devuelve el mejor puesto que pase.
  Future<String?> findEmbeddable(String query, Set<String> exclude) async {
    final ranked = <String>[];
    await _find(query.trim(), '', exclude: exclude, ranked: ranked)
        .timeout(const Duration(seconds: 18));
    final cands = ranked.take(6).toList();
    if (cands.isEmpty) return null;
    final ok = await Future.wait(cands.map((id) => embeddable(id, 5)));
    for (var i = 0; i < cands.length; i++) {
      if (ok[i]) return cands[i];
    }
    return null;
  }

  Future<String?> _find(String query, String key,
      {Set<String> exclude = const <String>{}, List<String>? ranked}) async {
    final sw = Stopwatch()..start();
    lastDebug = 'buscando…';
    var results = await _serial(() => _yt.search.search(query));
    if (results.isEmpty) {
      // YouTube a veces responde vacío si se le pide muy rápido: reintenta.
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      results = await _serial(() => _yt.search.search(query));
    }
    lastDebug = '${results.length} resultados en ${sw.elapsedMilliseconds}ms';
    var kept = 0;
    final lq = query.toLowerCase();
    final wantsLive = lq.contains('live') || lq.contains('en vivo');
    final wantsCover = lq.contains('cover');
    final words = lq
        .split(RegExp(r'[^a-z0-9áéíóúñü]+'))
        .where((w) => w.length > 2)
        .toSet();

    String? bestId;
    var bestScore = -1000;
    final scored = <MapEntry<String, int>>[];
    var rank = 0;
    for (final v in results.take(10)) {
      rank++;
      final title = v.title.toLowerCase();
      final author = v.author.toLowerCase();
      final d = v.duration;

      if (v.isLive) continue;
      if (d != null && (d.inSeconds >= 540 || d.inSeconds < 45)) continue;
      if (!wantsLive && _notSong.hasMatch(title)) continue;
      if (_badChannel.hasMatch(author)) continue;

      if (exclude.contains(v.id.value) || BadVideos.ids.contains(v.id.value)) {
        continue;
      }
      if (!wantsCover && RegExp(r'\bcover\b|covered by').hasMatch(title)) {
        continue;
      }
      kept++;
      var score = 10 - rank; // respeta el orden de relevancia de YouTube
      if (author.endsWith('- topic')) score += 8;
      if (RegExp(r'official audio|audio oficial|\(audio\)|\[audio\]|lyric|letra')
          .hasMatch(title)) {
        score += 4;
      }
      if (title.contains('official')) score += 1;
      if (author.contains('vevo')) score += 2;
      if (!wantsLive &&
          RegExp(r'\blive\b|en vivo|concert|concierto|festival|session|unplugged')
              .hasMatch(title)) {
        score -= 8;
      }
      if (!wantsCover &&
          RegExp(r'cover|karaoke|reaction|tutorial|lesson|instrumental|slowed|reverb|8d|nightcore|remix')
              .hasMatch(title)) {
        score -= 8;
      }
      if (title.contains('full album') || title.contains('compilation')) {
        score -= 10;
      }
      // Coincidencia con las palabras de la consulta (artista y título).
      final hay = '$title $author';
      var matched = 0;
      for (final w in words) {
        if (hay.contains(w)) matched++;
      }
      if (words.isNotEmpty) score += (6 * matched / words.length).round();

      scored.add(MapEntry(v.id.value, score));
      if (score > bestScore) {
        bestScore = score;
        bestId = v.id.value;
      }
    }
    if (ranked != null) {
      scored.sort((a, b) => b.value.compareTo(a.value));
      ranked.addAll(scored.map((e) => e.key));
    }
    lastDebug += ', $kept válidos';
    if (bestId != null && key.isNotEmpty) _idCache[key] = bestId;
    return bestId;
  }

  void dispose() {
    _yt.close();
  }
}
