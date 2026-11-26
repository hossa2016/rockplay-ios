import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'ai_json.dart';

/// Traducción al español y explicación de una letra, con la IA. Se guarda
/// por canción (las últimas 80) para no gastar cuota otra vez.
class LyricsTranslation {
  final List<String> lines; // misma cantidad que la original
  final String about; // «¿De qué habla?» (≤ 3 frases)
  const LyricsTranslation(this.lines, this.about);
}

class LyricsTranslate {
  LyricsTranslate._();
  static const String _prefKey = 'lyr_tr_v1';
  static Map<String, dynamic>? _mem;

  static const Set<String> _es = {
    'que', 'de', 'la', 'el', 'y', 'en', 'no', 'me', 'mi', 'tu', 'te', 'se',
    'por', 'con', 'para', 'una', 'lo', 'los', 'las', 'es', 'yo', 'quiero',
  };

  /// ¿La letra ya está en español? (no hace falta traducir).
  static bool isSpanish(List<String> lines) {
    var es = 0, all = 0;
    for (final l in lines) {
      for (final w in l.toLowerCase().split(RegExp(r"[^a-záéíóúñü']+"))) {
        if (w.isEmpty) continue;
        all++;
        if (_es.contains(w)) es++;
      }
    }
    return all > 0 && es / all > 0.12;
  }

  static Future<Map<String, dynamic>> _store() async {
    if (_mem != null) return _mem!;
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_prefKey);
      _mem = raw == null ? {} : (jsonDecode(raw) as Map).cast<String, dynamic>();
    } catch (_) {
      _mem = {};
    }
    return _mem!;
  }

  static Future<void> _save() async {
    final m = _mem;
    if (m == null) return;
    while (m.length > 80) {
      m.remove(m.keys.first);
    }
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_prefKey, jsonEncode(m));
    } catch (_) {}
  }

  static LyricsTranslation? cached(String key) {
    final e = _mem?[key];
    if (e is! Map) return null;
    return LyricsTranslation(
        ((e['es'] as List?) ?? const []).map((x) => '$x').toList(),
        '${e['about'] ?? ''}');
  }

  static Future<LyricsTranslation?> get(
      String artist, String title, List<String> lines) async {
    final key = '${artist.toLowerCase()}|${title.toLowerCase()}';
    final st = await _store();
    final c = cached(key);
    if (c != null && c.lines.length == lines.length) return c;
    final numbered = [
      for (var i = 0; i < lines.length; i++) {'i': i, 't': lines[i]}
    ];
    final j = await AiJson.ask(
      'Eres traductor musical. Traduces letras de canciones al español '
          'latinoamericano, natural y fiel al sentido (no literal palabra por '
          'palabra). Respondes SOLO JSON.',
      'Canción: "$title" de $artist.\n'
          'Traduce cada línea y explica de qué habla la canción en máximo 3 '
          'frases cortas, sin inventar datos.\n'
          'Formato: {"es":[{"i":0,"t":"..."},...],"about":"..."}\n'
          'Líneas: ${jsonEncode(numbered)}',
    );
    if (j is! Map) return null;
    final out = List<String>.filled(lines.length, '');
    for (final e in (j['es'] as List?) ?? const []) {
      if (e is Map && e['i'] is num) {
        final i = (e['i'] as num).toInt();
        if (i >= 0 && i < out.length) out[i] = '${e['t'] ?? ''}';
      }
    }
    if (out.where((x) => x.isNotEmpty).length < lines.length ~/ 2) return null;
    st[key] = {'es': out, 'about': '${j['about'] ?? ''}'};
    await _save();
    return LyricsTranslation(out, '${j['about'] ?? ''}');
  }
}
