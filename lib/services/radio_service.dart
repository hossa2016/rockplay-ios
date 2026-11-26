import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/song.dart';
import 'music_mode.dart';

class RadioStation {
  final String id;
  final String name;
  final String url;
  final String favicon;
  final String country;
  final String tags;
  final int bitrate;
  final String state;

  const RadioStation({
    required this.id,
    required this.name,
    required this.url,
    this.favicon = '',
    this.country = '',
    this.tags = '',
    this.bitrate = 0,
    this.state = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'favicon': favicon,
        'country': country,
        'tags': tags,
        'bitrate': bitrate,
        'state': state,
      };

  factory RadioStation.fromJson(Map<String, dynamic> j) => RadioStation(
        id: (j['id'] ?? '') as String,
        name: (j['name'] ?? '') as String,
        url: (j['url'] ?? '') as String,
        favicon: (j['favicon'] ?? '') as String,
        country: (j['country'] ?? '') as String,
        tags: (j['tags'] ?? '') as String,
        bitrate: (j['bitrate'] as num?)?.toInt() ?? 0,
        state: (j['state'] ?? '') as String,
      );

  /// Ciudad entre paréntesis en cualquier parte del nombre.
  static final RegExp _cityParen = RegExp(r'\s*\(([^)]+)\)\s*');

  static const List<String> _cities = [
    'Bogotá', 'Medellín', 'Cali', 'Barranquilla', 'Cartagena', 'Bucaramanga',
    'Pereira', 'Manizales', 'Cúcuta', 'Ibagué', 'Santa Marta', 'Villavicencio',
    'Pasto', 'Neiva', 'Armenia', 'Montería', 'Popayán', 'Tunja', 'Valledupar',
    'Sincelejo', 'Riohacha', 'Quibdó', 'Yopal', 'Florencia',
    'Ciudad de México', 'Monterrey', 'Guadalajara', 'Buenos Aires',
    'Santiago', 'Lima', 'Quito', 'Caracas', 'Madrid', 'Barcelona',
  ];

  static String _fold(String s) => s
      .toLowerCase()
      .replaceAll(RegExp('[áà]'), 'a')
      .replaceAll(RegExp('[éè]'), 'e')
      .replaceAll(RegExp('[íì]'), 'i')
      .replaceAll(RegExp('[óò]'), 'o')
      .replaceAll(RegExp('[úù]'), 'u');

  /// Ciudad: la del paréntesis, la de la lista que aparezca en el nombre o,
  /// como respaldo, el departamento/estado que trae Radio Browser.
  String get city {
    final p = _cityParen.firstMatch(name)?.group(1)?.trim() ?? '';
    if (p.isNotEmpty && !RegExp(r'\d').hasMatch(p)) return _accent(p);
    final n = _fold(name);
    for (final c in _cities) {
      if (RegExp('\\b${RegExp.escape(_fold(c))}\\b').hasMatch(n)) return c;
    }
    return _accent(state);
  }

  /// «Medellin» → «Medellín» si está en la lista.
  static String _accent(String c) {
    final f = _fold(c.trim());
    for (final x in _cities) {
      if (_fold(x) == f) return x;
    }
    return c.trim();
  }

  /// Nombre sin la ciudad entre paréntesis: «Radioacktiva (Medellín)».
  /// Nombre limpio: sin la ciudad, el país, la frecuencia, el indicativo
  /// (HJJK) ni el dueño («PRISA Radio»), que ya van en el subtítulo.
  /// «La Ochentera Medellin Colombia» → «La Ochentera».
  String get shortName {
    var n = name.replaceAll(_cityParen, ' ');
    final c = city;
    final drop = <String>[
      if (c.isNotEmpty) c,
      if (country.isNotEmpty) country,
      'Colombia',
    ];
    for (final d in drop) {
      final f = _fold(d);
      n = n.replaceAllMapped(RegExp(r'[^\s\-–|,]+(\s+[^\s\-–|,]+)*', unicode: true), (m) {
        return _fold(m[0]!) == f ? '' : m[0]!;
      });
      // Palabra suelta (sin tildes) igual a la ciudad o al país.
      n = n
          .split(' ')
          .where((w) => _fold(w.replaceAll(RegExp(r'[,.]'), '')) != f || f.contains(' '))
          .join(' ');
      if (f.contains(' ')) {
        n = n.replaceAll(RegExp(RegExp.escape(d), caseSensitive: false), '');
      }
    }
    n = n
        .replaceAll(RegExp(r'\b\d{2,3}[.,]\d\s*(fm|am)?\b', caseSensitive: false), '')
        .replaceAll(RegExp(r'\b(prisa|caracol|rcn|todelar|olímpica|olimpica)\s*radio\b', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*[-–|]\s*([-–|]\s*)*'), ' - ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'^[\s\-–|,]+|[\s\-–|,]+$'), '')
        // «HJCK El Mundo en» (tras quitar Bogotá): sin conector colgando.
        .replaceAll(RegExp(r'\s+(en|de|desde|para|y)$', caseSensitive: false), '')
        .trim();
    // Indicativo colombiano (HJJK) al final, sobre el nombre ya limpio:
    // nunca si es la primera palabra («HJCK» es la marca) y solo si quedan
    // al menos 2 palabras de verdad.
    // «Tropicana - HJJK» / «Olímpica | HJJK»: tras un separador al final,
    // se quita siempre (aunque quede una sola palabra).
    final tail = RegExp(r'^(.*\S)\s*[-–|·/,]\s*H[JK][A-Z]{2}(\s*\d+(\.\d+)?)?\s*$')
        .firstMatch(n);
    if (tail != null && tail[1]!.trim().length >= 2) n = tail[1]!.trim();
    final cs = RegExp(r'(?<=\S.*)\bH[JK][A-Z]{2}\b').firstMatch(n);
    if (cs != null) {
      final rest = n.replaceFirst(cs[0]!, ' ').split(RegExp(r'[\s\-–|,]+'))
        ..removeWhere((w) => w.isEmpty);
      if (rest.length >= 2) {
        n = n
            .replaceFirst(cs[0]!, ' ')
            .replaceAll(RegExp(r'\s*[-–|]\s*([-–|]\s*)*'), ' - ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .replaceAll(RegExp(r'^[\s\-–|,]+|[\s\-–|,]+$'), '')
            .trim();
      }
    }
    return n.length < 2 ? name : n;
  }

  static const Map<String, String> _tagEs = {
    'alternative': 'Alternativa', 'alternative rock': 'Rock alternativo',
    'classic rock': 'Rock clásico', 'rock': 'Rock', 'pop': 'Pop',
    'news': 'Noticias', 'talk': 'Habladas', 'sports': 'Deportes',
    'latin': 'Latina', 'salsa': 'Salsa', 'tropical': 'Tropical',
    'vallenato': 'Vallenato', 'reggaeton': 'Reguetón', 'electronic': 'Electrónica',
    'dance': 'Dance', 'jazz': 'Jazz', 'classical': 'Clásica', 'metal': 'Metal',
    'oldies': 'Clásicos', '80s': 'Años 80', '90s': 'Años 90', 'hits': 'Éxitos',
    'music': '', 'variety': 'Variada', 'christian': 'Cristiana',
    'top 40': 'Éxitos', 'cumbia': 'Cumbia', 'merengue': 'Merengue',
    'bachata': 'Bachata', 'regional mexicana': 'Regional mexicana',
    'ranchera': 'Ranchera', 'romantic': 'Romántica', 'ballads': 'Baladas',
    'urban': 'Urbana', 'hip hop': 'Hip hop', 'hip-hop': 'Hip hop',
    'indie': 'Indie', 'folk': 'Folk', 'electronica': 'Electrónica',
    'house': 'House', 'techno': 'Techno', 'blues': 'Blues', 'soul': 'Soul',
    'funk': 'Funk', 'reggae': 'Reggae', 'punk': 'Punk', 'grunge': 'Grunge',
    'hard rock': 'Hard rock', 'heavy metal': 'Heavy metal', 'news talk': 'Noticias',
    'popular': 'Popular', 'tropical music': 'Tropical', 'latin pop': 'Pop latino',
  };

  /// «Medellín · 91.9 FM · Alternativa». El país solo fuera de Colombia
  /// (dentro de la pestaña Colombia sobra).
  String get subtitle {
    final city = this.city;
    final fc = _fold(city);
    // AM/FM real: «1340 AM» o «99.1 FM» (sin banda, FM).
    final fm = RegExp(r'\b(\d{2,3}[.,]\d)\s*(fm|am)?\b', caseSensitive: false)
        .firstMatch('$name $tags');
    final am = RegExp(r'\b(\d{3,4})\s*(am|khz)\b', caseSensitive: false)
        .firstMatch('$name $tags');
    final String? freq = fm != null
        ? '${fm.group(1)!.replaceAll(',', '.')} ${(fm.group(2) ?? 'fm').toUpperCase()}'
        : (am != null ? '${am.group(1)} AM' : null);
    String tag = '';
    for (final t in tags.split(',')) {
      final k = t.trim().toLowerCase();
      if (k.isEmpty || RegExp(r'\d').hasMatch(k)) continue;
      // Etiquetas que repiten la ciudad o el país no aportan.
      if (fc.isNotEmpty && _fold(k).contains(fc)) continue;
      if (k == country.toLowerCase() || k == 'colombia') continue;
      // Solo etiquetas conocidas y traducidas (nada de «Armenian»).
      tag = _tagEs[k] ?? '';
      if (tag.isNotEmpty) break;
    }
    final parts = <String>[
      if (city.isNotEmpty) city,
      if (country.isNotEmpty && country.toLowerCase() != 'colombia' && city.isEmpty)
        country,
      if (freq != null) freq,
      if (tag.isNotEmpty) tag,
    ];
    return parts.isEmpty ? 'Radio en vivo' : parts.join(' · ');
  }

  Song toSong() => Song(
        title: name,
        artist: 'Radio en vivo',
        image: favicon,
        url: url,
        query: 'radio:$id',
      );
}

/// Emisoras guardadas (en el teléfono) y búsqueda en el directorio gratuito
/// Radio Browser.
class RadioService {
  RadioService._();
  static final RadioService instance = RadioService._();

  // Cada modo de música tiene sus emisoras guardadas.
  static String get _key => modeKey('radio_v1');
  MusicMode? _savedMode;
  static const List<String> _hosts = [
    'https://de1.api.radio-browser.info',
    'https://at1.api.radio-browser.info',
    'https://nl1.api.radio-browser.info',
    'https://all.api.radio-browser.info',
  ];

  /// Sube cada vez que cambian las emisoras guardadas.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);
  List<RadioStation>? _saved;

  Future<List<RadioStation>> saved() async {
    if (_saved != null && _savedMode == MusicModeService.mode.value) {
      return List<RadioStation>.of(_saved!);
    }
    _savedMode = MusicModeService.mode.value;
    final out = <RadioStation>[];
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_key);
      if (raw != null) {
        for (final e in jsonDecode(raw) as List) {
          if (e is Map<String, dynamic>) out.add(RadioStation.fromJson(e));
        }
      }
    } catch (_) {}
    _saved = out;
    return List<RadioStation>.of(out);
  }

  Future<void> _persist() async {
    revision.value++;
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(
          _key, jsonEncode([for (final s in _saved!) s.toJson()]));
    } catch (_) {}
  }

  /// Última emisora escuchada en este modo («Seguir con…» en Inicio).
  final ValueNotifier<int> lastChanged = ValueNotifier<int>(0);

  Future<void> setLast(RadioStation s) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(modeKey('radio_last'), jsonEncode(s.toJson()));
      lastChanged.value++;
    } catch (_) {}
  }

  Future<RadioStation?> last() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(modeKey('radio_last'));
      if (raw == null) return null;
      return RadioStation.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<bool> isSaved(String id) async =>
      (await saved()).any((s) => s.id == id);

  Future<void> save(RadioStation s) async {
    await saved();
    if (_saved!.any((x) => x.id == s.id)) return;
    _saved!.insert(0, s);
    await _persist();
  }

  Future<void> remove(String id) async {
    await saved();
    _saved!.removeWhere((s) => s.id == id);
    await _persist();
  }

  /// Emisora creada con un enlace pegado a mano.
  RadioStation custom(String name, String url) => RadioStation(
        id: 'c${url.hashCode.abs()}',
        name: name.trim(),
        url: url.trim(),
      );

  Future<dynamic> _get(String path) async {
    Object? last;
    for (final h in _hosts) {
      try {
        final r = await http.get(Uri.parse('$h$path'), headers: const {
          'User-Agent': 'RockPlayIA/1.0 (uso personal)'
        }).timeout(const Duration(seconds: 8));
        if (r.statusCode == 200) return jsonDecode(utf8.decode(r.bodyBytes));
        last = 'HTTP ${r.statusCode}';
      } catch (e) {
        last = e;
      }
    }
    throw Exception('Radio Browser no responde: $last');
  }

  List<RadioStation> _parse(dynamic j) {
    final out = <RadioStation>[];
    final seen = <String>{};
    for (final e in (j as List? ?? const [])) {
      if (e is! Map) continue;
      final url = ((e['url_resolved'] ?? '') as String).trim().isNotEmpty
          ? (e['url_resolved'] as String).trim()
          : ((e['url'] ?? '') as String).trim();
      final name = ((e['name'] ?? '') as String).trim();
      if (url.isEmpty || name.isEmpty) continue;
      final id = ((e['stationuuid'] ?? '') as String).isNotEmpty
          ? e['stationuuid'] as String
          : 'u${url.hashCode.abs()}';
      if (!seen.add(id)) continue;
      out.add(RadioStation(
        id: id,
        name: name,
        url: url,
        favicon: ((e['favicon'] ?? '') as String).trim(),
        country: ((e['country'] ?? '') as String).trim(),
        tags: ((e['tags'] ?? '') as String).trim(),
        bitrate: (e['bitrate'] as num?)?.toInt() ?? 0,
        state: ((e['state'] ?? '') as String).trim(),
      ));
    }
    return out;
  }

  /// [query] vacío con [colombiaOnly] = populares de Colombia.
  Future<List<RadioStation>> search(String query,
      {bool colombiaOnly = true}) async {
    final q = Uri.encodeQueryComponent(query.trim());
    final params = StringBuffer('limit=40&hidebroken=true&order=votes&reverse=true');
    if (q.isNotEmpty) params.write('&name=$q');
    if (colombiaOnly) params.write('&countrycode=CO');
    if (q.isEmpty && !colombiaOnly && MusicModeService.rock) {
      params.write('&tag=rock');
    }
    final j = await _get('/json/stations/search?$params');
    return _parse(j);
  }
}
