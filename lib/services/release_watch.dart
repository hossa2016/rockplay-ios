import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'alarm_service.dart';
import 'artist_info_service.dart';
import 'mix_service.dart';
import 'music_mode.dart';

/// Novedades de tus artistas: marca los discos nuevos que no has visto y
/// avisa una vez por semana. Revisa como máximo una vez al día.
class ReleaseWatch {
  ReleaseWatch._();

  static final ValueNotifier<int> fresh = ValueNotifier<int>(0);
  static Set<String> _seen = {};
  static bool _loaded = false;
  static String _loadedKey = '';

  static String get _seenKey => modeKey('rel_seen_v1');
  static String get _checkKey => modeKey('rel_check_at');
  static String get _notifyKey => modeKey('rel_notify_at');

  static Future<void> _load() async {
    final sp = await SharedPreferences.getInstance();
    _seen = Set<String>.of(sp.getStringList(_seenKey) ?? const []);
    _loadedKey = _seenKey;
    _loaded = true;
  }

  /// Carga los «vistos» del modo actual (se recargan al cambiar de modo).
  static Future<void> ensureLoaded() async {
    if (!_loaded || _loadedKey != _seenKey) await _load();
  }

  static bool isNew(String albumId) =>
      _loaded && _loadedKey == _seenKey && !_seen.contains(albumId);

  static Future<void> markSeen(Iterable<String> ids) async {
    await ensureLoaded();
    _seen.addAll(ids);
    fresh.value = 0;
    final sp = await SharedPreferences.getInstance();
    final l = _seen.toList();
    await sp.setStringList(_seenKey, l.length > 500 ? l.sublist(l.length - 500) : l);
  }

  static Future<void> check() async {
    try {
      await ensureLoaded();
      final sp = await SharedPreferences.getInstance();
      final now = DateTime.now().millisecondsSinceEpoch;
      final last = sp.getInt(_checkKey) ?? 0;
      if (now - last < const Duration(hours: 20).inMilliseconds) return;
      await sp.setInt(_checkKey, now);
      final names = (await MixService.personalArtists()).take(12).toList();
      if (names.isEmpty) return;
      final rel = await ArtistInfoService.instance.recentReleases(names);
      final ids = [for (final r in rel) r.album.id];
      // Primera vez: todo cuenta como visto (no avisar de lo viejo).
      if (!sp.containsKey(_seenKey)) {
        await markSeen(ids);
        return;
      }
      final news = rel.where((r) => !_seen.contains(r.album.id)).toList();
      fresh.value = news.length;
      if (news.isEmpty) return;
      final ln = sp.getInt(_notifyKey) ?? 0;
      if (now - ln < const Duration(days: 6).inMilliseconds) return;
      await sp.setInt(_notifyKey, now);
      final first = news.first;
      await AlarmService.instance.notify(
        6100,
        news.length == 1
            ? 'Nuevo de ${first.artist}'
            : '${news.length} lanzamientos de tus ${MusicModeService.general ? 'artistas' : 'bandas'}',
        news.length == 1
            ? first.album.title
            : news.take(3).map((r) => r.artist).toSet().join(', '),
      );
    } catch (_) {}
  }
}
