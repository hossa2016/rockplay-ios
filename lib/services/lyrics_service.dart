import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpClient;

import 'ai_json.dart';
import 'deezer_service.dart';

class LyricLine {
  final Duration at;
  final String text;
  const LyricLine(this.at, this.text);
}

class Lyrics {
  final List<LyricLine> synced; // vacío si solo hay texto plano
  final String plain;
  const Lyrics({this.synced = const [], this.plain = ''});
  bool get isEmpty => synced.isEmpty && plain.trim().isEmpty;
}

/// Busca la letra en LRCLIB (https://lrclib.net), gratis y sin clave.
class LyricsService {
  LyricsService._();
  static final LyricsService instance = LyricsService._();

  final Map<String, Lyrics?> _cache = <String, Lyrics?>{};

  static String _clean(String s) {
    var t = s
        .replaceAll(RegExp(r'[\[\(][^\]\)]*[\]\)]'), ' ')
        .replaceAll(
            RegExp(
                r'\b(official|oficial|video|vídeo|audio|lyrics?|letra|hd|hq|4k|remaster(ed)?|music|topic|vevo)\b',
                caseSensitive: false),
            ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return t;
  }

  Future<Lyrics?> fetch(String artist, String title, {int? seconds}) async {
    var a = _clean(artist);
    var t = title;
    // "Artista - Canción (Official Video)" → "Canción"
    final i = t.indexOf(' - ');
    if (i > 0) {
      final fromTitle = _clean(t.substring(0, i));
      if (fromTitle.isNotEmpty && fromTitle.length <= 40) a = fromTitle;
      t = t.substring(i + 3);
    }
    t = _clean(t);
    if (t.isEmpty) return null;
    final key = '${a.toLowerCase()}|${t.toLowerCase()}';
    if (_cache.containsKey(key)) return _cache[key];

    Lyrics? res;
    try {
      res = await _search(
          'https://lrclib.net/api/search?track_name=${Uri.encodeQueryComponent(t)}&artist_name=${Uri.encodeQueryComponent(a)}',
          seconds);
      res ??= await _search(
          'https://lrclib.net/api/search?q=${Uri.encodeQueryComponent('$a $t')}',
          seconds);
    } catch (_) {
      return null; // error de red: no se guarda en caché para reintentar
    }
    _cache[key] = res;
    return res;
  }

  Future<Lyrics?> _search(String url, int? seconds) async {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req =
          await c.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 8));
      req.headers.set('User-Agent', 'RockPlay personal app');
      final resp = await req.close().timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) {
        await resp.drain<void>();
        return null;
      }
      final body = await resp.transform(utf8.decoder).join();
      final list = jsonDecode(body);
      if (list is! List || list.isEmpty) return null;
      Map<String, dynamic>? best;
      var bestScore = -1e9;
      for (final e in list.take(10)) {
        if (e is! Map<String, dynamic>) continue;
        final hasSync = (e['syncedLyrics'] as String?)?.isNotEmpty ?? false;
        final hasPlain = (e['plainLyrics'] as String?)?.isNotEmpty ?? false;
        if (!hasSync && !hasPlain) continue;
        var score = hasSync ? 100.0 : 0.0;
        final d = (e['duration'] as num?)?.toDouble();
        if (seconds != null && d != null) score -= (d - seconds).abs();
        if (score > bestScore) {
          bestScore = score;
          best = e;
        }
      }
      if (best == null) return null;
      final synced = _parse((best['syncedLyrics'] as String?) ?? '');
      final plain = (best['plainLyrics'] as String?) ?? '';
      return Lyrics(synced: synced, plain: plain);
    } finally {
      c.close(force: true);
    }
  }

  /// Buscar una canción por un pedazo de su letra (LRCLIB busca en todos
  /// los campos). Devuelve (artista, canción, línea que coincide).
  Future<List<(String, String, String)>> byLyric(String text) async {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    final out = <(String, String, String)>[];
    try {
      final req = await c
          .getUrl(Uri.parse(
              'https://lrclib.net/api/search?q=${Uri.encodeQueryComponent(text)}'))
          .timeout(const Duration(seconds: 8));
      req.headers.set('User-Agent', 'RockPlay personal app');
      final resp = await req.close().timeout(const Duration(seconds: 12));
      if (resp.statusCode != 200) {
        await resp.drain<void>();
        throw Exception('lrclib ${resp.statusCode}'); // → respaldo con IA
      }
      final list = jsonDecode(await resp.transform(utf8.decoder).join());
      if (list is! List) throw Exception('lrclib');
      final words = text
          .toLowerCase()
          .split(RegExp(r'\s+'))
          .where((w) => w.length > 2)
          .toList();
      final seen = <String>{};
      for (final e in list) {
        if (e is! Map) continue;
        final a = '${e['artistName'] ?? ''}', t = '${e['trackName'] ?? ''}';
        if (a.isEmpty || t.isEmpty || !seen.add('${a.toLowerCase()}|${t.toLowerCase()}')) {
          continue;
        }
        // La línea que más palabras comparte con lo que escribiste.
        var best = '', bs = 0;
        for (final l in '${e['plainLyrics'] ?? ''}'.split('\n')) {
          final ll = l.toLowerCase();
          final sc = words.where(ll.contains).length;
          if (sc > bs) {
            bs = sc;
            best = l.trim();
          }
        }
        out.add((a, t, best));
        if (out.length >= 5) break;
      }
    } catch (_) {
    } finally {
      c.close(force: true);
    }
    if (out.isNotEmpty) return out;
    // Respaldo con IA: candidatas confirmadas con Deezer (nada inventado).
    try {
      final j = await AiJson.ask(
          'Identificas canciones por fragmentos de su letra. Respondes SOLO JSON.',
          'Fragmento (puede estar mal recordado): "$text".\n'
              'Dame hasta 5 canciones reales que lo contengan, la más probable primero.\n'
              'Formato: {"c":[{"artista":"","cancion":"","linea":"la línea parecida"}]}');
      if (j is Map) {
        final d = DeezerService();
        for (final e in (j['c'] as List?) ?? const []) {
          if (e is! Map) continue;
          final a = '${e['artista'] ?? ''}'.trim(), t = '${e['cancion'] ?? ''}'.trim();
          if (a.isEmpty || t.isEmpty) continue;
          if (!await d.trackExists(a, t)) continue;
          // La línea que da la IA no se puede comprobar: no se muestra.
          out.add((a, t, ''));
          if (out.length >= 5) break;
        }
      }
    } catch (_) {}
    return out;
  }

  static List<LyricLine> _parse(String lrc) {
    final out = <LyricLine>[];
    final re = RegExp(r'\[(\d+):(\d+(?:\.\d+)?)\]');
    for (final raw in lrc.split('\n')) {
      final ms = re.allMatches(raw).toList();
      if (ms.isEmpty) continue;
      final text = raw.substring(ms.last.end).trim();
      for (final m in ms) {
        final min = int.parse(m.group(1)!);
        final sec = double.parse(m.group(2)!);
        out.add(LyricLine(
            Duration(milliseconds: ((min * 60 + sec) * 1000).round()), text));
      }
    }
    out.sort((a, b) => a.at.compareTo(b.at));
    return out;
  }
}
