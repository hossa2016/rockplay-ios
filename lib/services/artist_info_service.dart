import 'data_saver.dart';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../models/song.dart';
import 'block_service.dart';
import 'music_mode.dart';

class ArtistInfo {
  final String id;
  final String name;
  final String picture;
  final int fans;
  const ArtistInfo(this.id, this.name, this.picture, this.fans);
}

class AlbumInfo {
  final String id;
  final String title;
  final String cover;
  final int? year;
  const AlbumInfo(this.id, this.title, this.cover, this.year);
}

class ReleaseItem {
  final AlbumInfo album;
  final String artist;
  const ReleaseItem(this.album, this.artist);
}

/// Ficha de artista con APIs gratuitas: Deezer (foto, discos, canciones) y
/// Wikipedia en español (biografía corta).
class ArtistInfoService {
  ArtistInfoService._();
  static final ArtistInfoService instance = ArtistInfoService._();

  static const String _dz = 'https://api.deezer.com';
  final Map<String, ArtistInfo?> _artistCache = <String, ArtistInfo?>{};
  final Map<String, String?> _bioCache = <String, String?>{};

  Future<dynamic> _json(String url) => DataSaver.instance.getJson(url,
      headers: const {'User-Agent': 'RockPlay personal app'});

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9áéíóúñü ]'), '')
      .trim();

  Future<ArtistInfo?> artist(String name) async {
    final key = _norm(name);
    if (_artistCache.containsKey(key)) return _artistCache[key];
    try {
      final j = await _json(
          '$_dz/search/artist?limit=3&q=${Uri.encodeQueryComponent(name)}');
      final list = (j['data'] as List?) ?? const [];
      Map<String, dynamic>? best;
      for (final e in list) {
        if (e is! Map<String, dynamic>) continue;
        best ??= e;
        if (_norm((e['name'] ?? '') as String) == key) {
          best = e;
          break;
        }
      }
      if (best == null) return _artistCache[key] = null;
      return _artistCache[key] = ArtistInfo(
        best['id'].toString(),
        (best['name'] ?? name) as String,
        _pic((best['picture_xl'] ?? best['picture_big'] ?? best['picture_medium'] ?? '')
            as String),
        (best['nb_fan'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null; // sin red: no se guarda
    }
  }

  List<Song> _songs(dynamic json, {String cover = '', String? artistName}) {
    final out = <Song>[];
    for (final t in (json['data'] as List?) ?? const []) {
      if (t is! Map<String, dynamic>) continue;
      final title = (t['title'] ?? '') as String;
      if (title.isEmpty) continue;
      final a = t['artist'];
      final artist = a is Map
          ? (a['name'] ?? artistName ?? '') as String
          : (artistName ?? '');
      final al = t['album'];
      final albumTitle = al is Map ? (al['title'] ?? '') as String : '';
      final img = cover.isNotEmpty
          ? cover
          : (al is Map ? (al['cover_medium'] ?? '') as String : '');
      out.add(Song(
        title: title,
        artist: artist,
        album: albumTitle,
        image: img,
        query: '$artist $title',
      ));
    }
    return out;
  }

  /// Discos de los últimos [days] días de los artistas dados; si salen pocos,
  /// completa con los lanzamientos destacados de rock de Deezer.
  Future<List<ReleaseItem>> recentReleases(List<String> names,
      {int days = 120, int max = 14}) async {
    await BlockService.instance.ensureLoaded();
    final from = DateTime.now().subtract(Duration(days: days));
    final out = <ReleaseItem>[];
    final seen = <String>{};

    void add(Map<String, dynamic> e, String artist) {
      final d = DateTime.tryParse((e['release_date'] ?? '') as String);
      if (d == null || d.isBefore(from) || d.isAfter(DateTime.now())) return;
      final type = (e['record_type'] ?? 'album') as String;
      if (type != 'album' && type != 'ep' && type != 'single') return;
      if (BlockService.instance.isBlockedAuthor(artist)) return;
      final title = (e['title'] ?? '') as String;
      if (!seen.add('${_norm(artist)}|${_norm(title)}')) return;
      out.add(ReleaseItem(
        AlbumInfo(e['id'].toString(), title,
            (e['cover_big'] ?? e['cover_medium'] ?? '') as String, d.year),
        artist,
      ));
    }

    await Future.wait([
      for (final n in names)
        () async {
          try {
            final a = await artist(n);
            if (a == null) return;
            final j = await _json('$_dz/artist/${a.id}/albums?limit=100');
            for (final e in (j['data'] as List?) ?? const []) {
              if (e is Map<String, dynamic>) add(e, a.name);
            }
          } catch (_) {}
        }(),
    ]);

    if (out.length < 6) {
      try {
        // 152 = Rock en Deezer; 0 = todos los géneros.
        final j = await _json('$_dz/editorial/${MusicModeService.general ? 0 : 152}/releases?limit=40');
        for (final e in (j['data'] as List?) ?? const []) {
          if (e is! Map<String, dynamic>) continue;
          final art = e['artist'];
          add(e, art is Map ? (art['name'] ?? '') as String : '');
        }
      } catch (_) {}
    }
    out.sort((a, b) => (int.tryParse(b.album.id) ?? 0)
        .compareTo(int.tryParse(a.album.id) ?? 0));
    return out.take(max).toList();
  }

  /// Presentaciones en vivo (canciones sueltas de 2 a 12 min) de un artista.
  Future<List<Song>> liveSongs(String artistName) async {
    await BlockService.instance.ensureLoaded();
    final yt = YoutubeExplode();
    final needle = BlockService.norm(artistName);
    final liveRe = RegExp(r'\b(live|en vivo|concert|concierto|unplugged|acoustic session)\b',
        caseSensitive: false);
    final out = <Song>[];
    final seen = <String>{};
    try {
      VideoSearchList? page = await yt.search.search('$artistName live');
      var pages = 0;
      while (page != null && pages < 3 && out.length < 30) {
        for (final v in page) {
          if (v.isLive) continue;
          final d = v.duration;
          if (d == null || d.inSeconds < 120 || d.inSeconds > 720) continue;
          if (!liveRe.hasMatch(v.title)) continue;
          if (!BlockService.norm('${v.title} ${v.author}').contains(needle)) {
            continue;
          }
          if (BlockService.instance.isBlockedAuthor(v.author)) continue;
          if (!seen.add(v.id.value)) continue;
          out.add(Song.fromYoutube(
            title: v.title,
            channel: v.author,
            image: v.thumbnails.mediumResUrl,
            videoId: v.id.value,
          ));
        }
        pages++;
        try {
          page = await page.nextPage().timeout(const Duration(seconds: 8));
        } catch (_) {
          break;
        }
      }
    } catch (_) {
    } finally {
      yt.close();
    }
    return out;
  }

  Future<List<Song>> topTracks(String artistId, String artistName) async {
    final j = await _json('$_dz/artist/$artistId/top?limit=50');
    return _songs(j, artistName: artistName);
  }

  Future<List<AlbumInfo>> albums(String artistId) async {
    final j = await _json('$_dz/artist/$artistId/albums?limit=100');
    final byTitle = <String, AlbumInfo>{};
    for (final e in (j['data'] as List?) ?? const []) {
      if (e is! Map<String, dynamic>) continue;
      final type = (e['record_type'] ?? '') as String;
      if (type != 'album' && type != 'ep') continue;
      final title = (e['title'] ?? '') as String;
      final base = _norm(title.replaceAll(RegExp(r'[\[\(][^\]\)]*[\]\)]'), ' '));
      final d = DateTime.tryParse((e['release_date'] ?? '') as String);
      final a = AlbumInfo(
        e['id'].toString(),
        title,
        (e['cover_big'] ?? e['cover_medium'] ?? '') as String,
        d?.year,
      );
      final prev = byTitle[base];
      if (prev == null || (a.year ?? 9999) < (prev.year ?? 9999)) {
        byTitle[base] = a;
      }
    }
    final list = byTitle.values.toList()
      ..sort((a, b) => (a.year ?? 9999).compareTo(b.year ?? 9999));
    return list;
  }

  Future<List<Song>> albumTracks(AlbumInfo a, String artistName) async {
    final j = await _json('$_dz/album/${a.id}/tracks?limit=100');
    final songs = _songs(j, cover: a.cover, artistName: artistName);
    return [
      for (final s in songs)
        Song(
          title: s.title,
          artist: s.artist.isEmpty ? artistName : s.artist,
          album: a.title,
          image: a.cover,
          query: '${s.artist.isEmpty ? artistName : s.artist} ${s.title}',
        ),
    ];
  }

  /// Resumen corto de Wikipedia (español); null si no hay uno fiable.
  Future<String?> bio(String name) async {
    final key = _norm(name);
    if (_bioCache.containsKey(key)) return _bioCache[key];
    final first = key.split(' ').first;
    final kind = RegExp(
        r'banda|grupo|cantante|músic|rock|metal|punk|artista|dúo|trío|guitarr|compositor|orquesta|rapero|dj|pianista|salsa|vallenat|regguet|reguet',
        caseSensitive: false);
    try {
      for (final q in [
        MusicModeService.general ? '$name cantante' : '$name banda de rock',
        name
      ]) {
        final s = await _json(
            'https://es.wikipedia.org/w/api.php?action=query&list=search&format=json&origin=*&srlimit=3&srsearch=${Uri.encodeQueryComponent(q)}');
        final hits = (s['query']?['search'] as List?) ?? const [];
        for (final h in hits) {
          final title = (h['title'] ?? '') as String;
          if (title.isEmpty) continue;
          final p = await _json(
              'https://es.wikipedia.org/api/rest_v1/page/summary/${Uri.encodeComponent(title)}');
          final extract = ((p['extract'] ?? '') as String).trim();
          final desc = ((p['description'] ?? '') as String);
          if (extract.length < 60) continue;
          if (!_norm(title).contains(first) && !_norm(extract).contains(first)) {
            continue;
          }
          if (!kind.hasMatch(desc) && !kind.hasMatch(extract)) continue;
          var out = extract;
          if (out.length > 700) {
            final cut = out.lastIndexOf('. ', 700);
            out = cut > 200 ? out.substring(0, cut + 1) : '${out.substring(0, 700)}…';
          }
          return _bioCache[key] = out;
        }
      }
      return _bioCache[key] = null;
    } catch (_) {
      return null;
    }
  }

  /// Artistas parecidos a [seeds] con pocos seguidores en Deezer.
  Future<List<ArtistInfo>> emerging(List<String> seeds,
      {Map<String, String> groupOf = const {}}) async {
    await BlockService.instance.ensureLoaded();
    final known = <String>{for (final s in seeds) _norm(s)};
    final found = <String, ArtistInfo>{};
    // Cuántos salen de cada semilla: máximo 2, para que una sola banda (o
    // un solo género) no llene la fila.
    final perSeed = <String, List<ArtistInfo>>{};
    await Future.wait([
      for (final seed in seeds.take(6))
        () async {
          try {
            final a = await artist(seed);
            if (a == null) return;
            final j = await _json('$_dz/artist/${a.id}/related?limit=40');
            for (final e in (j['data'] as List?) ?? const []) {
              if (e is! Map<String, dynamic>) continue;
              final fans = (e['nb_fan'] as num?)?.toInt() ?? 0;
              final name = (e['name'] ?? '') as String;
              if (name.isEmpty || fans < 500 || fans > 250000) continue;
              final nn = _norm(name);
              if (known.contains(nn)) continue;
              // Fuera proyectos solistas o derivados de las semillas
              // («Kurt Cobain & …», «Pearl Jam Tribute»).
              if (known.any((k) => k.length >= 4 && (nn.contains(k) || k.contains(nn)))) {
                continue;
              }
              if (BlockService.instance.isBlockedAuthor(name)) continue;
              final mine = perSeed.putIfAbsent(groupOf[seed] ?? seed, () => []);
              if (mine.length >= 2 || found.containsKey(nn)) continue;
              final info = ArtistInfo(
                  e['id'].toString(),
                  name,
                  _pic((e['picture_big'] ?? e['picture_medium'] ?? '') as String),
                  fans);
              mine.add(info);
              found[nn] = info;
            }
          } catch (_) {}
        }(),
    ]);
    final list = found.values.toList()..shuffle();
    // Fuera los homónimos pequeños de bandas grandes («Korn» con 900 fans
    // no es Korn): si la búsqueda exacta da otro con muchos fans, se omite.
    final checked = await Future.wait([
      for (final a in list.take(28))
        () async {
          try {
            final big = await artist(a.name);
            if (big != null && big.id != a.id && big.fans > 250000) return null;
          } catch (_) {}
          return a;
        }(),
    ]);
    return checked.whereType<ArtistInfo>().take(20).toList();
  }

  /// La foto por defecto de Deezer (silueta gris) cuenta como sin foto, para
  /// que se vea la inicial del artista.
  static String _pic(String url) =>
      url.contains('/artist//') || url.contains('/images/artist/-') ? '' : url;
}
