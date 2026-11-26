import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/song.dart';
import 'music_mode.dart';

class Playlist {
  final String id;
  String name;
  List<Song> songs;

  /// Modo donde se ve: 'rock', 'general' o 'both' (los dos).
  /// Las listas de antes de los modos son de rock.
  String mode;

  Playlist(
      {required this.id,
      required this.name,
      List<Song>? songs,
      this.mode = 'rock'})
      : songs = songs ?? <Song>[];

  bool get inBoth => mode == 'both';

  bool visibleIn(MusicMode m) =>
      mode == 'both' || mode == (m == MusicMode.general ? 'general' : 'rock');

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'mode': mode,
        'songs': songs.map((s) => s.toJson()).toList(),
      };

  factory Playlist.fromJson(Map<String, dynamic> j) => Playlist(
        id: (j['id'] ?? '') as String,
        name: (j['name'] ?? '') as String,
        mode: (j['mode'] ?? 'rock') as String,
        songs: [
          for (final s in (j['songs'] as List? ?? <dynamic>[]))
            if (s is Map<String, dynamic>) Song.fromJson(s),
        ],
      );
}

/// Listas de reproducción propias, guardadas en el teléfono.
class PlaylistService {
  PlaylistService._();
  static final PlaylistService instance = PlaylistService._();

  static const String _key = 'playlists_v1';

  /// Listas que se ven en el modo actual.
  Future<List<Playlist>> all() async => [
        for (final p in await _raw())
          if (p.visibleIn(MusicModeService.mode.value)) p
      ];

  /// Listas del otro modo (no se ven aquí).
  Future<List<Playlist>> others() async => [
        for (final p in await _raw())
          if (!p.visibleIn(MusicModeService.mode.value)) p
      ];

  /// Lista visible solo en el modo donde se creó, o en los dos.
  Future<void> setBoth(String id, bool both) async {
    final lists = await _raw();
    for (final p in lists) {
      if (p.id == id) {
        p.mode = both
            ? 'both'
            : (MusicModeService.general ? 'general' : 'rock');
      }
    }
    await _save(lists);
  }

  /// Todas las listas guardadas, de los dos modos.
  Future<List<Playlist>> _raw() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return <Playlist>[];
    try {
      final list = jsonDecode(raw) as List;
      return [
        for (final p in list)
          if (p is Map<String, dynamic>) Playlist.fromJson(p),
      ];
    } catch (_) {
      return <Playlist>[];
    }
  }

  Future<void> _save(List<Playlist> lists) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, jsonEncode(lists.map((p) => p.toJson()).toList()));
  }

  Future<Playlist> create(String name) async {
    final lists = await _raw();
    final p = Playlist(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name.trim().isEmpty ? 'Mi lista' : name.trim(),
      mode: MusicModeService.general ? 'general' : 'rock',
    );
    lists.insert(0, p);
    await _save(lists);
    return p;
  }

  /// Cambia el orden de las canciones (mismas canciones).
  Future<void> setOrder(String id, List<Song> songs) async {
    final lists = await _raw();
    for (final p in lists) {
      if (p.id == id) {
        p.songs
          ..clear()
          ..addAll(songs);
      }
    }
    await _save(lists);
  }

  Future<void> rename(String id, String name) async {
    final lists = await _raw();
    for (final p in lists) {
      if (p.id == id && name.trim().isNotEmpty) p.name = name.trim();
    }
    await _save(lists);
  }

  /// Borra la lista y la devuelve (con su posición) para poder deshacer.
  Future<(Playlist, int)?> delete(String id) async {
    final lists = await _raw();
    final i = lists.indexWhere((p) => p.id == id);
    if (i < 0) return null;
    final p = lists.removeAt(i);
    await _save(lists);
    return (p, i);
  }

  /// Vuelve a poner una lista borrada en su sitio (para «Deshacer»).
  Future<void> restore(Playlist p, int index) async {
    final lists = await _raw();
    if (lists.any((x) => x.id == p.id)) return;
    lists.insert(index.clamp(0, lists.length), p);
    await _save(lists);
  }

  /// Vuelve a poner una canción quitada en su posición (para «Deshacer»).
  Future<void> insertSong(String id, Song song, int index) async {
    final lists = await _raw();
    final i = lists.indexWhere((p) => p.id == id);
    if (i < 0) return;
    final p = lists[i];
    p.songs.insert(index.clamp(0, p.songs.length), song);
    await _save(lists);
  }

  /// true = añadida; false = ya estaba.
  Future<bool> addSong(String id, Song song) async {
    final lists = await _raw();
    final i = lists.indexWhere((p) => p.id == id);
    if (i < 0) return false;
    final p = lists[i];
    if (p.songs.any((s) => s.videoId == song.videoId)) return false;
    p.songs.add(song);
    await _save(lists);
    return true;
  }

  /// Añade varias canciones (también las que aún no tienen videoId).
  Future<int> addMany(String id, List<Song> songs) async {
    final lists = await _raw();
    final i = lists.indexWhere((p) => p.id == id);
    if (i < 0) return 0;
    final p = lists[i];
    String key(Song s) => s.videoId.isNotEmpty
        ? s.videoId
        : '${s.artist.toLowerCase()}|${s.title.toLowerCase()}';
    final have = <String>{for (final s in p.songs) key(s)};
    var n = 0;
    for (final s in songs) {
      if (have.add(key(s))) {
        p.songs.add(s);
        n++;
      }
    }
    await _save(lists);
    return n;
  }

  Future<void> removeSong(String id, String videoId) async {
    final lists = await _raw();
    final i = lists.indexWhere((p) => p.id == id);
    if (i < 0) return;
    lists[i].songs.removeWhere((s) => s.videoId == videoId);
    await _save(lists);
  }
}
