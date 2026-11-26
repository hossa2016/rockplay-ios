import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ai_settings.dart';
import 'stats_service.dart';
import 'alarm_service.dart';
import 'playback_service.dart';

/// Copia de seguridad de todo lo tuyo (favoritas, listas, historial,
/// escuchas, emisoras, alarmas, ajustes y, si quieres, las claves de IA) en
/// un archivo .json que guardas donde quieras (Drive, WhatsApp, Archivos).
class BackupService {
  BackupService._();

  static const String _tag = 'rockplay-ia-backup';

  /// Sube cada vez que se hace una copia (Inicio y Ajustes se refrescan).
  static final ValueNotifier<int> done = ValueNotifier<int>(0);
  static const String _lastKey = 'backup_last_at';

  /// Claves que no vale la pena copiar (cachés y estados temporales).
  static bool _skip(String k) =>
      k.startsWith('flutter.') ||
      k == _lastKey ||
      k.startsWith('cache_') ||
      k.startsWith('tmp_') ||
      k.endsWith('_cache') ||
      k.endsWith('_cache_v1') ||
      AiSettings.keyNames.contains(k);

  /// Fecha de la última copia exportada (null si nunca).
  static Future<DateTime?> lastBackup() async {
    final sp = await SharedPreferences.getInstance();
    final ms = sp.getInt(_lastKey);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// ¿Toca recordar la copia? (nunca hecha o hace más de 30 días).
  static Future<bool> due() async {
    final l = await lastBackup();
    return l == null || DateTime.now().difference(l).inDays >= 30;
  }

  /// Recordatorio en Inicio: solo si hay algo que perder (20+ escuchas) y
  /// no se pospuso en los últimos 7 días.
  static Future<bool> shouldRemind() async {
    if (!await due()) return false;
    final sp = await SharedPreferences.getInstance();
    final snooze = sp.getInt('backup_snooze') ?? 0;
    if (DateTime.now().millisecondsSinceEpoch - snooze <
        const Duration(days: 7).inMilliseconds) {
      return false;
    }
    try {
      return (await StatsService.instance.plays()).length >= 20;
    } catch (_) {
      return false;
    }
  }

  static Future<void> snooze() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setInt('backup_snooze', DateTime.now().millisecondsSinceEpoch);
  }

  static Future<Map<String, dynamic>> _collect({required bool keys}) async {
    await StatsService.instance.flush();
    final sp = await SharedPreferences.getInstance();
    final data = <String, dynamic>{};
    for (final k in sp.getKeys()) {
      if (_skip(k)) continue;
      final v = sp.get(k);
      if (v is List) {
        data[k] = {'t': 'l', 'v': v.map((e) => '$e').toList()};
      } else if (v is String) {
        data[k] = {'t': 's', 'v': v};
      } else if (v is bool) {
        data[k] = {'t': 'b', 'v': v};
      } else if (v is int) {
        data[k] = {'t': 'i', 'v': v};
      } else if (v is double) {
        data[k] = {'t': 'd', 'v': v};
      }
    }
    final out = <String, dynamic>{
      'app': _tag,
      'v': 1,
      'at': DateTime.now().toIso8601String(),
      'data': data,
    };
    if (keys) {
      await AiSettings.instance.load();
      out['keys'] = AiSettings.instance.keysMap();
    }
    return out;
  }

  /// Crea el archivo y abre «Compartir» para guardarlo donde quieras.
  /// Devuelve cuántos datos se copiaron.
  static Future<int> export({bool keys = false}) async {
    final j = await _collect(keys: keys);
    final dir = await getTemporaryDirectory();
    final d = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final name = 'RockPlayIA_copia_${d.year}-${two(d.month)}-${two(d.day)}.json';
    final f = File('${dir.path}/$name');
    await f.writeAsString(jsonEncode(j));
    final res = await Share.shareXFiles(
        [XFile(f.path, mimeType: 'application/json')],
        subject: 'Copia de seguridad de RockPlay IA');
    // Solo cuenta como hecha si se compartió/guardó (no si se canceló).
    if (res.status == ShareResultStatus.dismissed) return -1;
    final sp = await SharedPreferences.getInstance();
    await sp.setInt(_lastKey, DateTime.now().millisecondsSinceEpoch);
    done.value++;
    return (j['data'] as Map).length;
  }

  /// Elige un archivo de copia y lo lee. Null si se canceló.
  static Future<Map<String, dynamic>?> pick() async {
    final r = await FilePicker.platform.pickFiles(withData: true);
    final file = r?.files.single;
    if (file == null) return null;
    final bytes = file.bytes ??
        (file.path == null ? null : await File(file.path!).readAsBytes());
    if (bytes == null) return null;
    final j = jsonDecode(utf8.decode(bytes));
    if (j is! Map<String, dynamic> || j['app'] != _tag) {
      throw const FormatException('No es una copia de RockPlay IA');
    }
    return j;
  }

  /// Restaura una copia. [merge]: combina con lo que ya hay sin duplicar
  /// (canciones por videoId o artista+título; listas, alarmas y emisoras por
  /// id; escuchas ordenadas y recortadas a 3.000); si no, reemplaza todo.
  /// Antes deja todo quieto: pausa, guarda/descarta lo pendiente y cancela
  /// las alarmas programadas. Después hay que cerrar la app (exit).
  static Future<int> restore(Map<String, dynamic> j, {bool merge = true}) async {
    try {
      await PlaybackService.instance.pause();
    } catch (_) {}
    await StatsService.instance.flush();
    StatsService.instance.discardPending();
    await AlarmService.instance.cancelAllScheduled();
    final sp = await SharedPreferences.getInstance();
    final data = (j['data'] as Map).cast<String, dynamic>();
    // Valida toda la copia ANTES de borrar nada.
    for (final e in data.values) {
      final m = e as Map;
      final t = m['t'];
      final v = m['v'];
      final ok = (t == 'l' && v is List) || (t == 's' && v is String) ||
          (t == 'b' && v is bool) || ((t == 'i' || t == 'd') && v is num);
      if (!ok) throw const FormatException('copia dañada');
    }
    if (!merge) {
      for (final k in sp.getKeys().toList()) {
        if (!_skip(k)) await sp.remove(k);
      }
    }
    var n = 0;
    for (final e in data.entries) {
      final m = (e.value as Map).cast<String, dynamic>();
      final v = m['v'];
      switch (m['t']) {
        case 'l':
          final incoming = (v as List).map((x) => '$x').toList();
          final cur = merge ? (sp.getStringList(e.key) ?? const <String>[]) : const <String>[];
          await sp.setStringList(e.key, _mergeItems(cur, incoming));
        case 's':
          final cur = sp.getString(e.key);
          if (merge && cur != null && cur != v) {
            await sp.setString(e.key, _mergeJson(e.key, cur, v as String));
          } else {
            await sp.setString(e.key, v as String);
          }
        case 'b':
          if (!merge || !sp.containsKey(e.key)) await sp.setBool(e.key, v as bool);
        case 'i':
          if (!merge || !sp.containsKey(e.key)) {
            await sp.setInt(e.key, (v as num).toInt());
          }
        case 'd':
          if (!merge || !sp.containsKey(e.key)) {
            await sp.setDouble(e.key, (v as num).toDouble());
          }
      }
      n++;
    }
    final keys = j['keys'];
    if (keys is Map) {
      await AiSettings.instance.load();
      await AiSettings.instance.restoreKeys(keys.cast<String, dynamic>());
    }
    return n;
  }

  /// Clave de un elemento: canción → videoId o artista|título; con id → id.
  static String _itemKey(dynamic x) {
    if (x is Map) {
      if (x['id'] != null && x['id'].toString().isNotEmpty) return 'id:${x['id']}';
      final vid = '${x['videoId'] ?? ''}';
      if (vid.isNotEmpty) return 'v:$vid';
      if (x['artist'] != null || x['title'] != null) {
        return 's:${'${x['artist'] ?? ''}'.toLowerCase()}|${'${x['title'] ?? ''}'.toLowerCase()}';
      }
    }
    return 'j:${jsonEncode(x)}';
  }

  /// Une listas de JSON (favoritas, historial…) sin duplicar: una canción
  /// se repite si coincide por videoId O por artista+título.
  static List<String> _mergeItems(List<String> cur, List<String> inc) {
    final seen = <String>{};
    final out = <String>[];
    for (final raw in [...cur, ...inc]) {
      final keys = <String>[];
      try {
        final x = jsonDecode(raw);
        keys.add(_itemKey(x));
        if (x is Map && (x['artist'] != null || x['title'] != null)) {
          keys.add('s:${'${x['artist'] ?? ''}'.toLowerCase()}|${'${x['title'] ?? ''}'.toLowerCase()}');
        }
      } catch (_) {
        keys.add('r:$raw');
      }
      if (keys.any(seen.contains)) continue;
      seen.addAll(keys);
      out.add(raw);
    }
    return out;
  }

  /// Une dos JSON guardados según su tipo.
  static String _mergeJson(String key, String cur, String inc) {
    try {
      final a = jsonDecode(cur), b = jsonDecode(inc);
      if (a is List && b is List) {
        // Escuchas: [ts, artista, título, …] → unir, ordenar, recortar.
        if (key.endsWith('plays_v1')) {
          final seen = <String>{};
          final all = [
            for (final x in [...a, ...b])
              if (x is List && x.length >= 3 && seen.add('${x[0]}|${x[1]}|${x[2]}')) x
          ]..sort((p, q) => (p[0] as num).compareTo(q[0] as num));
          return jsonEncode(all.length > 3000 ? all.sublist(all.length - 3000) : all);
        }
        // Listas, alarmas, emisoras: por id; las listas unen sus canciones.
        final byKey = <String, dynamic>{};
        for (final x in a) {
          byKey[_itemKey(x)] = x;
        }
        for (final x in b) {
          final k = _itemKey(x);
          final have = byKey[k];
          if (have == null) {
            byKey[k] = x;
          } else if (have is Map && x is Map && have['songs'] is List && x['songs'] is List) {
            final seen = <String>{for (final s in have['songs'] as List) _itemKey(s)};
            (have['songs'] as List).addAll(
                (x['songs'] as List).where((s) => seen.add(_itemKey(s))));
          }
        }
        return jsonEncode(byKey.values.toList());
      }
      return cur;
    } catch (_) {
      return cur.isEmpty ? inc : cur;
    }
  }
}
