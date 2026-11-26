import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Claves y opciones del asistente. Se guardan solo en este teléfono; las
/// claves, cifradas (almacenamiento seguro de Android).
class AiSettings {
  AiSettings._();
  static final AiSettings instance = AiSettings._();

  static const String defaultGroqModel = 'openai/gpt-oss-120b';
  static const String defaultGeminiModel = 'gemini-flash-latest';

  String groqKey = '';
  String geminiKey = '';
  /// Buscador web gratuito (1.000 búsquedas al mes) para los conciertos.
  String tavilyKey = '';
  /// Apify: lee el Instagram de tus bares (crédito gratis mensual).
  String apifyKey = '';
  /// setlist.fm: setlists de los conciertos (gratis, uso no comercial).
  String setlistKey = '';
  String groqModel = defaultGroqModel;
  String geminiModel = defaultGeminiModel;
  bool learn = true;
  static const List<int> maxOptions = [20, 40, 60, 80, 100];
  int maxSongs = 100;
  bool _loaded = false;

  static const FlutterSecureStorage _sec = FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true));
  static const List<String> keyNames = [
    'ai_groq_key',
    'ai_gemini_key',
    'ai_tavily_key',
    'ai_apify_key',
    'ai_setlist_key',
  ];

  /// Claves que no se pudieron leer (fallo del almacenamiento cifrado):
  /// no se sobrescriben con vacío al guardar.
  static final Set<String> _unreadable = {};

  /// Lee una clave cifrada; si aún estaba en texto plano, la mueve.
  static Future<String> _readKey(SharedPreferences sp, String k) async {
    try {
      final v = await _sec.read(key: k);
      if (v != null) return v;
      final old = sp.getString(k);
      if (old != null) {
        await _sec.write(key: k, value: old);
        await sp.remove(k);
        return old;
      }
    } catch (_) {
      final plain = sp.getString(k);
      if (plain == null) _unreadable.add(k);
      return plain ?? '';
    }
    return '';
  }

  static Future<void> _writeKey(SharedPreferences sp, String k, String v) async {
    // Si no se pudo leer y sigue vacía, se deja la que hay guardada.
    if (v.isEmpty && _unreadable.contains(k)) return;
    _unreadable.remove(k);
    try {
      await _sec.write(key: k, value: v);
      await sp.remove(k);
    } catch (_) {
      await sp.setString(k, v);
    }
  }

  /// Claves actuales (para la copia de seguridad, si el usuario lo pide).
  Map<String, String> keysMap() => {
        'ai_groq_key': groqKey,
        'ai_gemini_key': geminiKey,
        'ai_tavily_key': tavilyKey,
        'ai_apify_key': apifyKey,
        'ai_setlist_key': setlistKey,
      };

  /// Restaura claves desde una copia.
  Future<void> restoreKeys(Map<String, dynamic> m) async {
    String g(String k, String cur) =>
        (m[k] is String && (m[k] as String).isNotEmpty) ? m[k] as String : cur;
    groqKey = g('ai_groq_key', groqKey);
    geminiKey = g('ai_gemini_key', geminiKey);
    tavilyKey = g('ai_tavily_key', tavilyKey);
    apifyKey = g('ai_apify_key', apifyKey);
    setlistKey = g('ai_setlist_key', setlistKey);
    await save();
  }

  Future<void> load() async {
    if (_loaded) return;
    try {
      final sp = await SharedPreferences.getInstance();
      groqKey = await _readKey(sp, 'ai_groq_key');
      geminiKey = await _readKey(sp, 'ai_gemini_key');
      tavilyKey = await _readKey(sp, 'ai_tavily_key');
      apifyKey = await _readKey(sp, 'ai_apify_key');
      setlistKey = await _readKey(sp, 'ai_setlist_key');
      groqModel = sp.getString('ai_groq_model') ?? defaultGroqModel;
      // Modelos que Groq ya retiró: usa el actual.
      if (groqModel == 'llama-3.3-70b-versatile' ||
          groqModel == 'llama-3.1-8b-instant') {
        groqModel = defaultGroqModel;
      }
      geminiModel = sp.getString('ai_gemini_model') ?? defaultGeminiModel;
      learn = sp.getBool('ai_learn') ?? true;
      maxSongs = (sp.getInt('ai_max') ?? 100).clamp(20, 100);
    } catch (_) {}
    _loaded = true;
  }

  Future<void> save() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await _writeKey(sp, 'ai_groq_key', groqKey.trim());
      await _writeKey(sp, 'ai_gemini_key', geminiKey.trim());
      await _writeKey(sp, 'ai_tavily_key', tavilyKey.trim());
      await _writeKey(sp, 'ai_apify_key', apifyKey.trim());
      await _writeKey(sp, 'ai_setlist_key', setlistKey.trim());
      await sp.setString('ai_groq_model',
          groqModel.trim().isEmpty ? defaultGroqModel : groqModel.trim());
      await sp.setString('ai_gemini_model',
          geminiModel.trim().isEmpty ? defaultGeminiModel : geminiModel.trim());
      await sp.setBool('ai_learn', learn);
      await sp.setInt('ai_max', maxSongs);
    } catch (_) {}
  }
}
