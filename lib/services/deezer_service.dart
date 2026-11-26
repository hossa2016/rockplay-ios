import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/song.dart';
import 'data_saver.dart';
import 'block_service.dart';

class RadioResult {
  final String artistName;
  final List<String> similar;
  final List<Song> tracks;

  RadioResult({
    required this.artistName,
    required this.similar,
    required this.tracks,
  });
}

/// Usa la API pública de Deezer (sin clave) para armar una emisora:
/// canciones del artista y de artistas similares.
class DeezerService {
  static const String _base = 'https://api.deezer.com';

  Future<Map<String, dynamic>> _get(String path, Map<String, String> q,
      {Duration ttl = const Duration(hours: 12)}) async {
    final uri = Uri.parse('$_base$path').replace(queryParameters: q);
    final j = await DataSaver.instance.getJson(uri.toString(), ttl: ttl);
    return j as Map<String, dynamic>;
  }

  /// URL de la vista previa (30 s, mp3) de la mejor coincidencia en Deezer.
  Future<String?> previewUrl(String query) async {
    final q = query
        .replaceAll(RegExp(r'[\[\(][^\]\)]*[\]\)]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (q.isEmpty) return null;
    final j = await _get('/search', {'q': q, 'limit': '5'},
        ttl: const Duration(minutes: 20));
    final data = (j['data'] as List?) ?? <dynamic>[];
    for (final t in data) {
      if (t is Map) {
        final p = t['preview'];
        if (p is String && p.isNotEmpty) return p;
      }
    }
    return null;
  }

  /// Sugerencias mientras escribes: artistas y canciones (máx. 8).
  /// Cada entrada es el texto que se buscará.
  Future<List<String>> suggest(String query) async {
    final q = query.trim();
    if (q.length < 2) return const <String>[];
    final out = <String>[];
    final seen = <String>{};
    void add(String v) {
      final t = v.trim();
      if (t.isNotEmpty && seen.add(t.toLowerCase())) out.add(t);
    }

    try {
      final a = await _get('/search/artist', {'q': q, 'limit': '3'},
          ttl: const Duration(hours: 6));
      for (final x in (a['data'] as List?) ?? <dynamic>[]) {
        if (x is Map && x['name'] is String) add(x['name'] as String);
      }
    } catch (_) {}
    try {
      final t = await _get('/search', {'q': q, 'limit': '6'},
          ttl: const Duration(hours: 6));
      for (final x in (t['data'] as List?) ?? <dynamic>[]) {
        if (x is Map && x['title'] is String && x['artist'] is Map) {
          add('${x['artist']['name']} - ${x['title']}');
        }
      }
    } catch (_) {}
    return out.take(8).toList();
  }

  /// Portada de la mejor coincidencia (vacía si no hay).
  /// Artista real de una canción por su título (para videos subidos por
  /// canales que no son del artista). null si no hay coincidencia clara.
  Future<String?> artistForTitle(String title) async {
    String n(String s) => s
        .toLowerCase()
        .replaceAll(RegExp(r'[\[\(][^\]\)]*[\]\)]'), ' ')
        .replaceAll(RegExp(r'[^a-z0-9áéíóúñü ]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final t = n(title);
    if (t.length < 2) return null;
    try {
      final j = await _get('/search', {'q': 'track:"$t"', 'limit': '5'},
          ttl: const Duration(days: 30));
      for (final e in (j['data'] as List?) ?? <dynamic>[]) {
        if (e is! Map) continue;
        if (n((e['title'] ?? '').toString()) != t) continue;
        final a = e['artist'];
        final name = a is Map ? (a['name'] ?? '').toString() : '';
        if (name.isNotEmpty) return name;
      }
      // Respaldo: búsqueda libre; vale si el título de Deezer empieza igual
      // («Sonnet» ↔ «Sonnet (Remastered 2016)»).
      final j2 = await _get('/search', {'q': t, 'limit': '5'},
          ttl: const Duration(days: 30));
      // Solo si todos los resultados que coinciden son del mismo artista:
      // «Creep» (Radiohead, TLC, STP) es ambiguo y no se adivina.
      final names = <String, String>{};
      for (final e in (j2['data'] as List?) ?? <dynamic>[]) {
        if (e is! Map) continue;
        final dt = n((e['title'] ?? '').toString());
        if (!(dt == t || dt.startsWith('$t ') || t.startsWith('$dt '))) continue;
        final a = e['artist'];
        final name = a is Map ? (a['name'] ?? '').toString() : '';
        if (name.isNotEmpty) names[n(name)] = name;
      }
      if (names.length == 1) return names.values.first;
    } catch (_) {}
    return null;
  }

  /// Portada validada: la de la canción [title] de [artist] en Deezer, solo
  /// si el artista coincide (no el primer resultado a ciegas).
  Future<String> coverForTrack(String artist, String title) async {
    String n(String s) => s
        .toLowerCase()
        .replaceAll(RegExp(r'[\[\(][^\]\)]*[\]\)]'), ' ')
        .replaceAll(RegExp(r'^the\s+'), '')
        .replaceAll(RegExp(r'[^a-z0-9áéíóúñü]'), '');
    final na = n(artist), nt = n(title);
    if (na.isEmpty || nt.isEmpty) return '';
    final clean = title.replaceAll(RegExp(r'[\[\(][^\]\)]*[\]\)]'), ' ').trim();
    final j = await _get('/search',
        {'q': 'artist:"$artist" track:"$clean"', 'limit': '5'},
        ttl: const Duration(days: 30));
    for (final e in (j['data'] as List?) ?? <dynamic>[]) {
      if (e is! Map || e['album'] is! Map) continue;
      final ea = n('${(e['artist'] as Map?)?['name'] ?? ''}');
      final et = n('${e['title'] ?? ''}');
      if (ea != na && !ea.contains(na) && !na.contains(ea)) continue;
      if (!et.startsWith(nt) && !nt.startsWith(et)) continue;
      final c = '${e['album']['cover_big'] ?? e['album']['cover_medium'] ?? ''}';
      if (c.isNotEmpty) return c;
    }
    return '';
  }

  /// ¿Existe en Deezer la canción [title] de [artist]?
  Future<bool> trackExists(String artist, String title) async {
    try {
      final j = await _get('/search',
          {'q': 'artist:"$artist" track:"$title"', 'limit': '3'},
          ttl: const Duration(days: 30));
      return ((j['data'] as List?) ?? const []).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// BPM de una canción (0 si Deezer no lo sabe).
  Future<double> bpm(String artist, String title) async {
    try {
      final j = await _get('/search',
          {'q': 'artist:"$artist" track:"$title"', 'limit': '1'},
          ttl: const Duration(days: 60));
      final l = (j['data'] as List?) ?? const [];
      if (l.isEmpty) return 0;
      final t = await _get('/track/${(l.first as Map)['id']}', const {},
          ttl: const Duration(days: 60));
      return ((t['bpm'] as num?) ?? 0).toDouble();
    } catch (_) {
      return 0;
    }
  }

  Future<String> coverFor(String query) async {
    final q = query
        .replaceAll(RegExp(r'[\[\(][^\]\)]*[\]\)]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (q.isEmpty) return '';
    final j = await _get('/search', {'q': q, 'limit': '3'});
    for (final t in (j['data'] as List?) ?? <dynamic>[]) {
      if (t is Map && t['album'] is Map) {
        final c = (t['album']['cover_medium'] ?? '') as String;
        if (c.isNotEmpty) return c;
      }
    }
    return '';
  }

  List<Song> _tracks(Map<String, dynamic> json) {
    final out = <Song>[];
    final data = (json['data'] as List?) ?? <dynamic>[];
    for (final t in data) {
      if (t is! Map<String, dynamic>) continue;
      final title = (t['title'] ?? '') as String;
      final artistMap = t['artist'];
      final artist = artistMap is Map ? (artistMap['name'] ?? '') as String : '';
      final albumMap = t['album'];
      final image =
          albumMap is Map ? (albumMap['cover_medium'] ?? '') as String : '';
      if (title.isEmpty) continue;
      if (BlockService.instance.isBlockedAuthor(artist)) continue;
      out.add(Song(
        title: title,
        artist: artist,
        image: image,
        query: '$artist $title',
      ));
    }
    return out;
  }

  /// Solo nombre oficial + artistas parecidos (2 peticiones, rápido).
  Future<RadioResult?> similarOnly(String name) async {
    final found = await _get('/search/artist', {'q': name, 'limit': '1'});
    final list = (found['data'] as List?) ?? <dynamic>[];
    if (list.isEmpty) return null;
    final artist = list.first as Map<String, dynamic>;
    final id = artist['id'].toString();
    final names = <String>[];
    final ids = <String>[];
    final self = (artist['name'] ?? name).toString().toLowerCase();
    try {
      final rel = await _get('/artist/$id/related', {'limit': '50'});
      for (final a in (rel['data'] as List?) ?? <dynamic>[]) {
        if (a is Map<String, dynamic> && a['name'] != null) {
          names.add(a['name'] as String);
          ids.add(a['id'].toString());
        }
      }
    } catch (_) {}
    // Parecidos de los parecidos: más variedad de artistas.
    final extra = await Future.wait([
      for (final rid in ids.take(16))
        () async {
          try {
            final r = await _get('/artist/$rid/related', {'limit': '30'});
            return [
              for (final a in (r['data'] as List?) ?? <dynamic>[])
                if (a is Map<String, dynamic> && a['name'] != null)
                  a['name'] as String,
            ];
          } catch (_) {
            return <String>[];
          }
        }(),
    ]);
    final seen = <String>{self, ...names.map((n) => n.toLowerCase())};
    for (final l in extra) {
      for (final n in l) {
        if (seen.add(n.toLowerCase())) names.add(n);
      }
    }
    return RadioResult(
      artistName: (artist['name'] ?? name) as String,
      similar: names,
      tracks: <Song>[],
    );
  }

  Future<RadioResult?> artistRadio(String name) async {
    final found = await _get('/search/artist', {'q': name, 'limit': '1'});
    final list = (found['data'] as List?) ?? <dynamic>[];
    if (list.isEmpty) return null;
    final artist = list.first as Map<String, dynamic>;
    final id = artist['id'].toString();
    final artistName = (artist['name'] ?? name) as String;

    Future<List<Song>> safeTracks(String path, String limit) async {
      try {
        return _tracks(await _get(path, {'limit': limit}));
      } catch (_) {
        return <Song>[];
      }
    }

    // Todo en paralelo: radio + top del artista + artistas parecidos.
    final similarNames = <String>[];
    final similarIds = <String>[];
    try {
      final rel = await _get('/artist/$id/related', {'limit': '50'});
      for (final a in (rel['data'] as List?) ?? <dynamic>[]) {
        if (a is Map<String, dynamic> && a['name'] != null) {
          similarNames.add(a['name'] as String);
          similarIds.add(a['id'].toString());
        }
      }
    } catch (_) {}

    final futures = <Future<List<Song>>>[
      safeTracks('/artist/$id/top', '50'),
      safeTracks('/artist/$id/radio', '100'),
      for (final sid in similarIds.take(25)) safeTracks('/artist/$sid/top', '25'),
    ];
    final lists = await Future.wait(futures);

    // Primero lo del artista; luego los parecidos. Sin duplicados.
    final seen = <String>{};
    final tracks = <Song>[];
    for (final l in lists) {
      for (final t in l) {
        final key = '${t.artist}|${t.title}'.toLowerCase();
        if (seen.add(key) && tracks.length < 500) tracks.add(t);
      }
    }

    return RadioResult(
      artistName: artistName,
      similar: similarNames,
      tracks: tracks,
    );
  }
}
