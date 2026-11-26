import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Cómo opera la app: solo rock (RockPlay) o todos los géneros (Pulso).
enum MusicMode { rock, general }

class MusicModeService {
  MusicModeService._();

  static const _key = 'music_mode';
  static const _chosenKey = 'music_mode_chosen';

  /// Cambia el tema, los textos, los géneros y el asistente al instante.
  static final ValueNotifier<MusicMode> mode = ValueNotifier(MusicMode.rock);

  /// true si la persona ya respondió «¿Qué vas a escuchar?».
  static final ValueNotifier<bool> chosenN = ValueNotifier(false);
  static bool get chosen => chosenN.value;

  /// Cambia cada vez que cambia el modo: sirve para descartar búsquedas
  /// que empezaron en el otro modo.
  static int generation = 0;

  static bool get general => mode.value == MusicMode.general;

  /// Modo en que se armó la cola que está sonando. Si cambias de modo con
  /// música sonando, esas canciones se siguen anotando en el historial y
  /// las escuchas del modo donde empezaron, no en el nuevo.
  static MusicMode? queueMode;
  static MusicMode get playMode => queueMode ?? mode.value;
  static bool get rock => mode.value == MusicMode.rock;

  /// Nombre visible de la app según el modo.
  static String get appName => general ? PulsoPrefs.brand.value : 'RockPlay IA';

  static Future<void> load() async {
    await PulsoPrefs.load();
    try {
      final sp = await SharedPreferences.getInstance();
      mode.value =
          sp.getString(_key) == 'general' ? MusicMode.general : MusicMode.rock;
      // Quien ya usaba la app antes de esta versión sigue en rock sin
      // que le pregunten nada.
      var c = sp.getBool(_chosenKey);
      if (c == null) {
        // Quien ya tenía música guardada de versiones anteriores sigue en
        // rock sin que le pregunten.
        c = const ['favorites', 'history', 'plays_v1'].any(sp.containsKey);
        if (c) await sp.setBool(_chosenKey, true);
      }
      chosenN.value = c;
    } catch (_) {}
  }

  static Future<void> set(MusicMode m) async {
    if (m != mode.value) generation++;
    mode.value = m;
    chosenN.value = true;
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_key, m == MusicMode.general ? 'general' : 'rock');
      await sp.setBool(_chosenKey, true);
    } catch (_) {}
  }
}

/// Texto según el modo: `byMode('NOCHE DE RIFFS', 'Tu noche')`.
String byMode(String rock, String general) =>
    MusicModeService.general ? general : rock;

/// Clave de guardado propia de cada modo: el historial, las escuchas, las
/// favoritas y las búsquedas de «Todos los géneros» no se mezclan con las
/// de rock. En rock se usan las claves de siempre.
String modeKey(String key) => MusicModeService.general ? 'g_$key' : key;

/// Igual que [modeKey], pero para el modo de la cola que está sonando.
String playKey(String key) =>
    MusicModeService.playMode == MusicMode.general ? 'g_$key' : key;

/// Ajustes propios del modo «Todos los géneros» y del saludo.
class PulsoPrefs {
  PulsoPrefs._();

  /// Géneros que más te gustan (Buscar → «Mis géneros», conciertos,
  /// asistente y orden de los mixes en Inicio).
  static final ValueNotifier<List<String>> favGenres =
      ValueNotifier(const ['Pop', 'Salsa', 'Vallenato', 'Rock']);

  /// Nombre de la app en pantalla en el modo Pulso.
  static final ValueNotifier<String> brand = ValueNotifier('Pulso');

  /// Tu nombre para el saludo de Inicio (vacío = sin nombre).
  static final ValueNotifier<String> userName = ValueNotifier('');

  static const allGenres = [
    'Pop',
    'Pop latino',
    'Salsa',
    'Reguetón',
    'Vallenato',
    'Rock',
    'Electrónica',
    'Jazz',
    'Clásica',
    'Baladas',
  ];

  static Future<void> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final g = sp.getStringList('pulso_fav_genres');
      if (g != null && g.isNotEmpty) favGenres.value = g;
      brand.value = sp.getString('pulso_brand') ?? 'Pulso';
      userName.value = sp.getString('user_name') ?? '';
    } catch (_) {}
  }

  static Future<void> setGenres(List<String> g) async {
    favGenres.value = List.unmodifiable(g);
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setStringList('pulso_fav_genres', g);
    } catch (_) {}
  }

  static Future<void> setBrand(String b) async {
    brand.value = b.trim().isEmpty ? 'Pulso' : b.trim();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString('pulso_brand', brand.value);
    } catch (_) {}
  }

  static Future<void> setUserName(String n) async {
    userName.value = n.trim();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString('user_name', userName.value);
    } catch (_) {}
  }
}
