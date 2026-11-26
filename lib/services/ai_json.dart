import 'dart:convert';

import 'ai_client.dart';
import 'ai_settings.dart';

/// Pide un JSON a la IA (Gemini y, si falla, Groq). Null si no hay clave o
/// ninguna respondió bien.
class AiJson {
  AiJson._();

  static Future<bool> available() async {
    await AiSettings.instance.load();
    final s = AiSettings.instance;
    return s.geminiKey.trim().isNotEmpty || s.groqKey.trim().isNotEmpty;
  }

  static Future<dynamic> ask(String system, String user) async {
    if (!await available()) return null;
    final msgs = [AiMessage(true, user)];
    final tries = <Future<String> Function()>[
      () => AiClient.instance.gemini(system, msgs),
      () => AiClient.instance.groq(system, msgs),
    ];
    for (final t in tries) {
      try {
        final raw = await t();
        final j = _decode(raw);
        if (j != null) return j;
      } catch (_) {}
    }
    return null;
  }

  static dynamic _decode(String raw) {
    var t = raw.trim();
    t = t.replaceAll(RegExp(r'^```(json)?', multiLine: true), '').replaceAll('```', '').trim();
    try {
      return jsonDecode(t);
    } catch (_) {}
    final a = t.indexOf(RegExp(r'[\[{]'));
    final b = t.lastIndexOf(RegExp(r'[\]}]'));
    if (a >= 0 && b > a) {
      try {
        return jsonDecode(t.substring(a, b + 1));
      } catch (_) {}
    }
    return null;
  }
}
