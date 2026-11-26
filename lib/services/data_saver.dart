import 'dart:convert';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'library_service.dart';
import 'stats_service.dart';

/// Cómo se guarda el caché (portadas y datos de artistas; nunca música).
enum CacheMode { off, unlimited, limit, favorites }

/// Caché en disco de portadas y respuestas de internet, configurable.
class DataSaver {
  DataSaver._();
  static final DataSaver instance = DataSaver._();

  static const List<int> limitsMb = [50, 100, 250, 500, 1000];

  CacheMode mode = CacheMode.limit;
  int limitMb = 250;
  bool noMobileImages = false;
  bool audioOnly = false;
  static const List<int> mixSongOptions = [50, 100, 200, 300, 500];
  static const List<int> mixArtistOptions = [10, 20, 40, 70, 100];
  int mixSongs = 500;
  int mixArtists = 100;

  Directory? _dir;
  String _dirError = '';
  bool _keepLoaded = false;
  Set<String> _keep = <String>{};

  Future<void>? _loading;

  Future<void> load() => _loading ??= _doLoad();

  Future<void> _doLoad() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final m = sp.getString('ds_mode');
      mode = CacheMode.values
          .firstWhere((e) => e.name == m, orElse: () => CacheMode.limit);
      limitMb = sp.getInt('ds_limit') ?? 250;
      noMobileImages = sp.getBool('ds_nomobile') ?? false;
      mixSongs = sp.getInt('ds_mixsongs') ?? 500;
      mixArtists = sp.getInt('ds_mixartists') ?? 100;
      audioOnly = false; // función retirada (YouTube bloquea la extracción)
    } catch (_) {}
    Directory? base;
    try {
      base = await getTemporaryDirectory();
    } catch (e) {
      _dirError = '$e';
    }
    if (base == null) {
      try {
        base = await getApplicationCacheDirectory();
      } catch (e) {
        _dirError = '$_dirError | $e';
      }
    }
    base ??= Directory.systemTemp;
    try {
      final d = Directory('${base.path}/rp_cache');
      if (!d.existsSync()) d.createSync(recursive: true);
      _dir = d;
    } catch (e) {
      _dirError = '$_dirError | crear: $e';
    }
    prune();
  }

  Future<void> save() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString('ds_mode', mode.name);
      await sp.setInt('ds_limit', limitMb);
      await sp.setBool('ds_nomobile', noMobileImages);
      await sp.setInt('ds_mixsongs', mixSongs);
      await sp.setInt('ds_mixartists', mixArtists);
    } catch (_) {}
  }

  bool get cacheOn => mode != CacheMode.off && _dir != null;

  static String _name(String key) {
    var a = 0x811c9dc5;
    var b = 0x01000193;
    for (final c in key.codeUnits) {
      a = ((a ^ c) * 16777619) & 0xFFFFFFFF;
      b = ((b * 31) + c) & 0xFFFFFFFF;
    }
    return '${a.toRadixString(16)}${b.toRadixString(16)}';
  }

  /// ¿Hay WiFi? (aproximado: busca una interfaz wlan con dirección).
  Future<bool> onWifi() async {
    try {
      final l = await NetworkInterface.list();
      return l.any((i) =>
          i.name.toLowerCase().startsWith('wlan') && i.addresses.isNotEmpty);
    } catch (_) {
      return true;
    }
  }

  /// URLs de portadas de favoritos y de las más escuchadas.
  Future<void> refreshKeep() async {
    try {
      final favs = await LibraryService.instance.favorites();
      final plays = await StatsService.instance.plays();
      final top = StatsService.topSongs(plays, n: 100);
      _keep = {
        for (final s in favs)
          if (s.image.isNotEmpty) s.image,
        for (final t in top)
          if (t.sample != null && t.sample!.image.isNotEmpty) t.sample!.image,
      };
      _keepLoaded = true;
    } catch (_) {}
  }

  final Map<String, Future<ImageProvider?>> _inflight = {};

  /// Imagen desde el disco; si no está, la baja (según el modo) y la guarda.
  Future<ImageProvider?> image(String url) {
    final cur = _inflight[url];
    if (cur != null) return cur;
    final f = _image(url);
    _inflight[url] = f;
    f.whenComplete(() => _inflight.remove(url)).ignore();
    return f;
  }

  Future<ImageProvider?> _image(String url) async {
    await load();
    if (!cacheOn) return NetworkImage(url);
    final file = File('${_dir!.path}/${_name(url)}.img');
    try {
      if (file.existsSync() && file.lengthSync() > 0) {
        try {
          file.setLastModifiedSync(DateTime.now());
        } catch (_) {}
        return FileImage(file);
      }
    } catch (_) {}
    if (noMobileImages && !await onWifi()) return null;
    try {
      final r = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 12));
      if (r.statusCode != 200 || r.bodyBytes.isEmpty) return NetworkImage(url);
      if (mode == CacheMode.favorites) {
        if (!_keepLoaded) await refreshKeep();
        if (!_keep.contains(url)) return MemoryImage(r.bodyBytes);
      }
      await file.writeAsBytes(r.bodyBytes);
      return FileImage(file);
    } catch (_) {
      return null;
    }
  }

  /// JSON de internet, guardado unas horas para repetir menos peticiones.
  Future<dynamic> getJson(
    String url, {
    Map<String, String>? headers,
    Duration ttl = const Duration(hours: 12),
  }) async {
    await load();
    final File? f = cacheOn ? File('${_dir!.path}/${_name(url)}.json') : null;
    try {
      if (f != null &&
          f.existsSync() &&
          DateTime.now().difference(f.lastModifiedSync()) < ttl) {
        return jsonDecode(f.readAsStringSync());
      }
    } catch (_) {}
    final r = await http
        .get(Uri.parse(url), headers: headers)
        .timeout(const Duration(seconds: 8));
    if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
    final text = utf8.decode(r.bodyBytes);
    if (f != null) {
      try {
        f.writeAsStringSync(text);
      } catch (_) {}
    }
    return jsonDecode(text);
  }

  List<File> _files() {
    final d = _dir;
    if (d == null) return <File>[];
    try {
      return d.listSync().whereType<File>().toList();
    } catch (_) {
      return <File>[];
    }
  }

  /// Para diagnóstico: estado de la carpeta del caché.
  String debugInfo() {
    final d = _dir;
    if (d == null) return 'Carpeta del caché no disponible: $_dirError';
    final m = {
      CacheMode.off: 'sin caché',
      CacheMode.unlimited: 'sin límite',
      CacheMode.limit: 'hasta ${limitMb >= 1000 ? "1 GB" : "$limitMb MB"}',
      CacheMode.favorites: 'solo favoritas',
    }[mode];
    return '${_files().length} archivos guardados · $m';
  }

  Future<int> sizeBytes() async {
    var t = 0;
    for (final f in _files()) {
      try {
        t += f.lengthSync();
      } catch (_) {}
    }
    return t;
  }

  Future<void> clear() async {
    for (final f in _files()) {
      try {
        f.deleteSync();
      } catch (_) {}
    }
  }

  /// Aplica la regla elegida: quita lo que sobre.
  Future<void> prune() async {
    await load();
    if (_dir == null) return;
    try {
      final files = _files();
      final now = DateTime.now();
      for (final f in List<File>.of(files)) {
        if (f.path.endsWith('.json') &&
            now.difference(f.lastModifiedSync()) > const Duration(days: 3)) {
          f.deleteSync();
          files.remove(f);
        }
      }
      if (mode == CacheMode.off) {
        await clear();
        return;
      }
      if (mode == CacheMode.favorites) {
        await refreshKeep();
        final keep = {for (final u in _keep) '${_name(u)}.img'};
        for (final f in files) {
          if (f.path.endsWith('.img') && !keep.contains(f.uri.pathSegments.last)) {
            f.deleteSync();
          }
        }
        return;
      }
      if (mode == CacheMode.limit) {
        final cap = limitMb * 1024 * 1024;
        var total = 0;
        for (final f in files) {
          total += f.lengthSync();
        }
        if (total > cap) {
          files.sort(
              (a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));
          for (final f in files) {
            if (total <= cap * 0.9) break;
            total -= f.lengthSync();
            f.deleteSync();
          }
        }
      }
    } catch (_) {}
  }
}
