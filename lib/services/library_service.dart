import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';
import 'deezer_service.dart';
import 'music_mode.dart';
import 'song_fix.dart';

class LibraryService {
  LibraryService._();
  static final LibraryService instance = LibraryService._();

  // Cada modo de música tiene sus favoritas e historial.
  static String get _favKey => modeKey('favorites');
  static String get _histKey => modeKey('history');

  Future<List<Song>> _load(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(key) ?? <String>[];
    final out = <Song>[];
    for (final s in raw) {
      try {
        out.add(Song.fromJson(jsonDecode(s) as Map<String, dynamic>));
      } catch (_) {}
    }
    return out;
  }

  Future<void> _save(String key, List<Song> songs) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      key,
      songs.map((s) => jsonEncode(s.toJson())).toList(),
    );
  }

  Future<List<Song>> favorites() => _load(_favKey);

  /// Cuántas favoritas hay en el otro modo (para el estado vacío).
  Future<int> otherModeFavoritesCount() async {
    final k = MusicModeService.general ? 'favorites' : 'g_favorites';
    return (await _load(k)).length;
  }
  Future<List<Song>> history() => _load(_histKey);

  Future<bool> isFavorite(String videoId) async {
    final favs = await favorites();
    return favs.any((s) => s.videoId == videoId);
  }

  Future<bool> toggleFavorite(Song song) async {
    final favs = await favorites();
    final i = favs.indexWhere((s) => s.videoId == song.videoId);
    if (i >= 0) {
      favs.removeAt(i);
      await _save(_favKey, favs);
      return false;
    }
    favs.insert(0, song);
    await _save(_favKey, favs);
    return true;
  }

  /// Completa la portada con Deezer si la canción no la trae.
  Future<Song> _withCover(Song s) async {
    if (s.image.isNotEmpty) return s;
    try {
      final c = await DeezerService().coverForTrack(s.artist, s.title);
      if (c.isEmpty) return s;
      return Song(
        title: s.title,
        artist: s.artist,
        album: s.album,
        image: c,
        url: s.url,
        videoId: s.videoId,
        query: s.query,
      );
    } catch (_) {
      return s;
    }
  }

  Future<void> clearHistory() => _save(_histKey, <Song>[]);

  static String _same(Song s) =>
      '${s.artist.toLowerCase().trim()}|${s.title.toLowerCase().trim()}';

  Future<void> addToHistory(Song song) async {
    song = await SongFix.verify(song);
    // Va al historial del modo donde empezó la cola (no del que esté
    // abierto si cambiaste de modo con música sonando).
    final key = playKey('history');
    final h = await _load(key);
    // Sin repetidas: misma canción aunque YouTube la dé con otro video.
    h.removeWhere((s) => s.videoId == song.videoId || _same(s) == _same(song));
    h.insert(0, await _withCover(song));
    // Completa también algunas anteriores que quedaron sin portada.
    var fixed = 0;
    for (var i = 1; i < h.length && fixed < 6; i++) {
      if (h[i].image.isEmpty) {
        h[i] = await _withCover(h[i]);
        fixed++;
      }
    }
    await _save(key, h.take(50).toList());
  }
}
