import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/song.dart';
import 'ai_settings.dart';

class SetlistSong {
  final String title;
  final int times; // en cuántos de los últimos conciertos salió
  const SetlistSong(this.title, this.times);
}

class SetlistResult {
  final List<SetlistSong> songs;
  final int shows; // conciertos analizados
  final String error;
  const SetlistResult(this.songs, this.shows, [this.error = '']);
}

/// Setlist probable (setlist.fm): las canciones que más tocó la banda en
/// sus últimos 10 conciertos, en el orden habitual. Se guarda 3 días.
class SetlistService {
  SetlistService._();

  static Future<bool> hasKey() async {
    await AiSettings.instance.load();
    return AiSettings.instance.setlistKey.trim().isNotEmpty;
  }

  static Future<SetlistResult> probable(String artist) async {
    await AiSettings.instance.load();
    final key = AiSettings.instance.setlistKey.trim();
    if (key.isEmpty) return const SetlistResult([], 0, 'sin clave');
    final ck = 'setlist_${artist.toLowerCase()}';
    final sp = await SharedPreferences.getInstance();
    try {
      final raw = sp.getString(ck);
      if (raw != null) {
        final j = jsonDecode(raw) as Map;
        if (DateTime.now().millisecondsSinceEpoch - (j['at'] as num) <
            const Duration(days: 3).inMilliseconds) {
          return SetlistResult([
            for (final e in j['s'] as List)
              SetlistSong('${e[0]}', (e[1] as num).toInt())
          ], (j['n'] as num).toInt());
        }
      }
    } catch (_) {}
    try {
      final r = await http.get(
        Uri.https('api.setlist.fm', '/rest/1.0/search/setlists',
            {'artistName': artist, 'p': '1'}),
        headers: {'x-api-key': key, 'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 12));
      if (r.statusCode == 404) return const SetlistResult([], 0);
      if (r.statusCode != 200) {
        return SetlistResult([], 0,
            r.statusCode == 403 ? 'clave no válida' : 'error ${r.statusCode}');
      }
      final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map;
      final want = artist.toLowerCase();
      final count = <String, int>{};
      final pos = <String, double>{};
      final names = <String, String>{};
      var shows = 0;
      for (final sl in (j['setlist'] as List?) ?? const []) {
        if (shows >= 10) break;
        final an = '${(sl['artist'] as Map?)?['name'] ?? ''}'.toLowerCase();
        if (an.isNotEmpty && an != want && !an.contains(want)) continue;
        final songs = <String>[];
        for (final set in ((sl['sets'] as Map?)?['set'] as List?) ?? const []) {
          for (final s in (set['song'] as List?) ?? const []) {
            final n = '${s['name'] ?? ''}'.trim();
            if (n.isEmpty || s['tape'] == true) continue;
            songs.add(n);
          }
        }
        if (songs.isEmpty) continue;
        shows++;
        for (var i = 0; i < songs.length; i++) {
          final k = songs[i].toLowerCase();
          names.putIfAbsent(k, () => songs[i]);
          count[k] = (count[k] ?? 0) + 1;
          pos[k] = (pos[k] ?? 0) + i / songs.length;
        }
      }
      // Las que salieron en al menos 1 de cada 3 conciertos, en su orden
      // habitual (posición media).
      final keep = count.keys
          .where((k) => count[k]! * 3 >= shows || count.length <= 20)
          .toList()
        ..sort((a, b) =>
            (pos[a]! / count[a]!).compareTo(pos[b]! / count[b]!));
      final out = [for (final k in keep.take(25)) SetlistSong(names[k]!, count[k]!)];
      await sp.setString(
          ck,
          jsonEncode({
            'at': DateTime.now().millisecondsSinceEpoch,
            'n': shows,
            's': [for (final s in out) [s.title, s.times]],
          }));
      return SetlistResult(out, shows);
    } catch (_) {
      return const SetlistResult([], 0, 'sin conexión');
    }
  }

  /// Canciones listas para la cola (se buscan en YouTube al sonar).
  static List<Song> toSongs(String artist, List<SetlistSong> l) => [
        for (final s in l)
          Song(title: s.title, artist: artist, query: '$artist ${s.title}')
      ];
}
