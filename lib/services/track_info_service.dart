import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpClient;

class TrackInfo {
  final String title;
  final String artist;
  final String album;
  final int? year;
  final String genre;
  final String artwork; // URL cuadrada grande ('' si no hay)
  const TrackInfo({
    required this.title,
    required this.artist,
    this.album = '',
    this.year,
    this.genre = '',
    this.artwork = '',
  });

  /// "1992 · Rock · Álbum" (solo lo que exista).
  String get meta => [
        if (year != null) '$year',
        if (genre.isNotEmpty) genre,
        if (album.isNotEmpty) album,
      ].join(' · ');
}

/// Datos de la canción (nombre limpio, artista, álbum, año, género, carátula)
/// desde iTunes Search: gratis y sin clave.
class TrackInfoService {
  TrackInfoService._();
  static final TrackInfoService instance = TrackInfoService._();

  final Map<String, TrackInfo?> _cache = <String, TrackInfo?>{};

  static String _clean(String s) => s
      .replaceAll(RegExp(r'[\[\(][^\]\)]*[\]\)]'), ' ')
      .replaceAll(
          RegExp(
              r'\b(official|oficial|video|vídeo|audio|lyrics?|letra|hd|hq|4k|remaster(ed)?|music|topic|vevo|sub|español)\b',
              caseSensitive: false),
          ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9áéíóúñü ]'), '').trim();

  Future<TrackInfo?> fetch(String artist, String title,
      {bool throwOnError = false}) async {
    var a = _clean(artist);
    var t = title;
    final i = t.indexOf(' - ');
    if (i > 0) {
      final fromTitle = _clean(t.substring(0, i));
      if (fromTitle.isNotEmpty && fromTitle.length <= 40) a = fromTitle;
      t = t.substring(i + 3);
    }
    t = _clean(t);
    if (t.isEmpty) return null;
    final key = '${_norm(a)}|${_norm(t)}';
    if (_cache.containsKey(key)) return _cache[key];
    TrackInfo? res;
    try {
      res = await _search(a, t);
    } catch (e) {
      if (throwOnError) rethrow; // quien llama distingue error de «no hay»
      return null; // error de red: se reintenta la próxima vez
    }
    _cache[key] = res;
    return res;
  }

  Future<TrackInfo?> _search(String artist, String track) async {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final url =
          'https://itunes.apple.com/search?media=music&entity=song&limit=15&term=${Uri.encodeQueryComponent('$artist $track')}';
      final req =
          await c.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 8));
      final resp = await req.close().timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) {
        await resp.drain<void>();
        return null;
      }
      final body = await resp.transform(utf8.decoder).join();
      final data = jsonDecode(body);
      final list = data is Map ? data['results'] : null;
      if (list is! List) return null;
      final na = _norm(artist), nt = _norm(track);
      Map<String, dynamic>? best;
      DateTime? bestDate;
      for (final e in list) {
        if (e is! Map<String, dynamic>) continue;
        final ra = _norm((e['artistName'] as String?) ?? '');
        final rt = _norm((e['trackName'] as String?) ?? '');
        if (ra.isEmpty || rt.isEmpty) continue;
        final artistOk = ra.contains(na) || na.contains(ra);
        final trackOk = rt == nt || rt.startsWith(nt) || nt.startsWith(rt);
        if (!artistOk || !trackOk) continue;
        final d = DateTime.tryParse((e['releaseDate'] as String?) ?? '');
        // Entre las coincidencias, la más antigua suele ser el disco original.
        if (best == null ||
            (d != null && (bestDate == null || d.isBefore(bestDate)))) {
          best = e;
          bestDate = d ?? bestDate;
        }
      }
      if (best == null) return null;
      var art = (best['artworkUrl100'] as String?) ?? '';
      if (art.isNotEmpty) art = art.replaceAll('100x100bb', '600x600bb');
      return TrackInfo(
        title: (best['trackName'] as String?) ?? track,
        artist: (best['artistName'] as String?) ?? artist,
        album: ((best['collectionName'] as String?) ?? '')
            .replaceAll(RegExp(r'[\[\(][^\]\)]*[\]\)]'), ' ')
            .replaceAll(RegExp(r'\s*[-–]\s*(Single|EP)$'), '')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim(),
        year: bestDate?.year,
        genre: (best['primaryGenreName'] as String?) ?? '',
        artwork: art,
      );
    } finally {
      c.close(force: true);
    }
  }
}
