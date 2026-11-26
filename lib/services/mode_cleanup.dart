import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'artist_pools.dart';
import '../models/song.dart';
import 'song_fix.dart';
import 'general_catalog.dart';

/// Arreglo de una sola vez: en la versión anterior, si cambiabas de modo con
/// música sonando, canciones de «Todos los géneros» quedaban en el historial
/// y las escuchas de rock. Aquí se devuelven a su modo.
class ModeCleanup {
  ModeCleanup._();

  static const _flag = 'fix_mode_mix_v1';
  // Desde que existe el modo Pulso (24 nov 2026, 11 p. m. hora Colombia).
  static const _since = 1795579200;

  static String _k(String a, String t) =>
      '${a.toLowerCase().trim()}|${t.toLowerCase().trim()}';

  static Future<void> run() async {
    try {
      final sp = await SharedPreferences.getInstance();
      if (sp.getBool(_flag) == true) return;
      await sp.setBool(_flag, true);

      final rockArtists = <String>{
        for (final l in kMixArtistPools.values)
          for (final a in l) a.toLowerCase()
      };
      final generalArtists = <String>{
        for (final l in GeneralCatalog.pools.values)
          for (final a in l) a.toLowerCase(),
        for (final d in GeneralCatalog.genre)
          for (final a in d.artists) a.toLowerCase(),
        for (final d in GeneralCatalog.mood)
          for (final a in d.artists) a.toLowerCase(),
      }..removeAll(rockArtists);

      // Lo que ya sonó en Pulso.
      final gSongs = <String>{};
      final gPlaysRaw = sp.getString('g_plays_v1');
      final gPlays = gPlaysRaw == null ? <dynamic>[] : jsonDecode(gPlaysRaw) as List;
      for (final e in gPlays) {
        final l = e as List;
        gSongs.add(_k(l[1] as String, l[2] as String));
      }
      for (final raw in sp.getStringList('g_history') ?? const <String>[]) {
        try {
          final j = jsonDecode(raw) as Map<String, dynamic>;
          gSongs.add(_k('${j['artist'] ?? ''}', '${j['title'] ?? ''}'));
        } catch (_) {}
      }

      bool isGeneral(String artist, String title) =>
          gSongs.contains(_k(artist, title)) ||
          generalArtists.contains(artist.toLowerCase().trim());

      // Escuchas de rock desde que existe Pulso.
      final playsRaw = sp.getString('plays_v1');
      if (playsRaw != null) {
        final keep = <dynamic>[];
        final move = <dynamic>[];
        for (final e in jsonDecode(playsRaw) as List) {
          final l = e as List;
          final recent = (l[0] as int) >= _since;
          (recent && isGeneral(l[1] as String, l[2] as String) ? move : keep)
              .add(l);
        }
        if (move.isNotEmpty) {
          await sp.setString('plays_v1', jsonEncode(keep));
          await sp.setString('g_plays_v1', jsonEncode([...gPlays, ...move]));
        }
      }

      // Historial de rock.
      final hist = sp.getStringList('history');
      if (hist != null) {
        final keep = <String>[];
        final seen = <String>{};
        for (final raw in hist) {
          try {
            final j = jsonDecode(raw) as Map<String, dynamic>;
            final a = '${j['artist'] ?? ''}', t = '${j['title'] ?? ''}';
            if (isGeneral(a, t)) continue;
            if (!seen.add(_k(a, t))) continue; // repetidas
            keep.add(raw);
          } catch (_) {
            keep.add(raw);
          }
        }
        await sp.setStringList('history', keep);
      }
    } catch (_) {}
  }

  /// Corrige canciones guardadas con título o artista dudoso («1993 /
  /// Killing In The Name», canales como artista) en historial, favoritas,
  /// la cola guardada y las escuchas, de los dos modos. Se marca como hecho
  /// solo si Deezer respondió; si no, reintenta en la siguiente apertura.
  static Future<void> fixTitles() async {
    try {
      final sp = await SharedPreferences.getInstance();
      if (sp.getBool('fix_titles_v4') == true) return;
      var pending = 0;
      final fixes = <String, Song>{};

      Future<Map<String, dynamic>> fix(Map<String, dynamic> j) async {
        final s = Song.fromJson(j);
        if (!SongFix.doubtful(s)) return j;
        final f = await SongFix.verify(s);
        if (f.title == s.title && f.artist == s.artist) {
          pending++;
          return j;
        }
        fixes['${s.artist}|${s.title}'] = f;
        return {...j, 'title': f.title, 'artist': f.artist};
      }

      for (final key in const ['history', 'g_history', 'favorites', 'g_favorites']) {
        final list = sp.getStringList(key);
        if (list == null) continue;
        final out = <String>[];
        for (final raw in list) {
          try {
            out.add(jsonEncode(await fix(jsonDecode(raw) as Map<String, dynamic>)));
          } catch (_) {
            out.add(raw);
          }
        }
        await sp.setStringList(key, out);
      }
      final q = sp.getString('queue_v1');
      if (q != null) {
        final j = jsonDecode(q) as Map<String, dynamic>;
        j['s'] = [
          for (final e in (j['s'] as List))
            await fix(Map<String, dynamic>.from(e as Map))
        ];
        await sp.setString('queue_v1', jsonEncode(j));
      }
      for (final key in const ['plays_v1', 'g_plays_v1']) {
        final raw = sp.getString(key);
        if (raw == null) continue;
        final list = jsonDecode(raw) as List;
        for (final e in list) {
          final l = e as List;
          final k = '${l[1]}|${l[2]}';
          // Escuchas sueltas (ya fuera del historial) también se corrigen.
          if (!fixes.containsKey(k)) {
            final s0 = Song(title: '${l[2]}', artist: '${l[1]}');
            if (SongFix.doubtful(s0)) {
              final f0 = await SongFix.verify(s0);
              if (f0.title != s0.title || f0.artist != s0.artist) fixes[k] = f0;
            }
          }
          final f = fixes[k];
          if (f != null) {
            l[1] = f.artist;
            l[2] = f.title;
          }
        }
        await sp.setString(key, jsonEncode(list));
      }
      // Quedaron dudosas sin respuesta (sin internet): se reintenta luego,
      // como mucho 5 veces.
      final tries = (sp.getInt('fix_titles_tries4') ?? 0) + 1;
      await sp.setInt('fix_titles_tries4', tries);
      if (pending == 0 || tries >= 5) await sp.setBool('fix_titles_v4', true);
    } catch (_) {}
  }
}
