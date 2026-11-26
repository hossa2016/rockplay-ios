import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/song.dart';
import '../widgets/playback_ui.dart';
import 'ai_json.dart';
import 'artist_info_service.dart';
import 'music_mode.dart';
import 'playback_service.dart';

/// Locutor con IA en español: cada 3 canciones baja la música y presenta lo
/// que viene («Eso fue System of a Down… ahora, Turnstile»). Usa la voz del
/// propio teléfono (gratis); el texto lo escribe Gemini/Groq o, sin clave,
/// una frase simple.
class DjVoice {
  DjVoice._();
  static final DjVoice instance = DjVoice._();

  final ValueNotifier<bool> on = ValueNotifier<bool>(false);
  final FlutterTts _tts = FlutterTts();
  bool _ready = false;
  Song? _prev;
  String _lastKey = '';
  int _count = 0;
  bool _speaking = false;

  Future<void> init() async {
    final sp = await SharedPreferences.getInstance();
    on.value = sp.getBool('dj_voice') ?? false;
    PlaybackUi.instance.song.addListener(_onSong);
  }

  Future<void> set(bool v) async {
    on.value = v;
    final sp = await SharedPreferences.getInstance();
    await sp.setBool('dj_voice', v);
    _count = 2; // que hable en la próxima canción
  }

  bool _ok = false;

  Future<void> _prepare() async {
    if (_ready) return;
    _ready = true;
    try {
      _tts.setErrorHandler((_) => PlaybackService.instance.duck(false));
      final langs = (await _tts.getLanguages as List?)?.map((e) => '$e').toList() ?? [];
      final lang = ['es-CO', 'es-US', 'es-MX', 'es-ES']
          .firstWhere(langs.contains, orElse: () => 'es-US');
      await _tts.setLanguage(lang);
      await _tts.setSpeechRate(0.5);
      await _tts.setPitch(MusicModeService.general ? 1.05 : 0.92);
      await _tts.awaitSpeakCompletion(true);
      // Sin motor de voz instalado no se baja la música.
      final engines = await _tts.getEngines;
      _ok = engines is List && engines.isNotEmpty;
    } catch (_) {
      _ok = false; // sin motor de voz: no se baja la música
    }
  }

  void _onSong() {
    final s = PlaybackUi.instance.song.value;
    if (s == null || s.isRadio) return;
    final key = '${s.artist}|${s.title}';
    if (key == _lastKey) return;
    _lastKey = key;
    final prev = _prev;
    _prev = s;
    if (!on.value || prev == null) return;
    if (++_count < 3) return;
    _count = 0;
    unawaited(_talk(prev, s));
  }

  Future<String> _line(Song prev, Song next) async {
    // Datos reales: la biografía de Wikipedia del artista que viene.
    var bio = '';
    try {
      bio = (await ArtistInfoService.instance.bio(next.artist)) ?? '';
      if (bio.length > 600) bio = bio.substring(0, 600);
    } catch (_) {}
    try {
      final j = await AiJson.ask(
        'Eres locutor de una emisora ${MusicModeService.general ? 'de música variada' : 'de rock'} '
            'en Colombia. Hablas en español neutro, cálido y breve. Respondes SOLO JSON.',
        'Presenta la transición en máximo 25 palabras. Usa SOLO datos de la '
            'biografía dada; si no hay biografía, no des datos (nada de fechas '
            'ni discos inventados).\n'
            'Biografía de ${next.artist}: ${bio.isEmpty ? '(no hay)' : bio}\n'
            'Acaba de sonar: "${prev.title}" de ${prev.artist}.\n'
            'Ahora suena: "${next.title}" de ${next.artist}.\n'
            'Formato: {"texto":"..."}',
      );
      if (j is Map && '${j['texto'] ?? ''}'.trim().isNotEmpty) {
        return '${j['texto']}'.trim();
      }
    } catch (_) {}
    return 'Eso fue ${prev.artist}. Ahora, ${next.title}, de ${next.artist}.';
  }

  Future<void> _talk(Song prev, Song next) async {
    if (_speaking) return;
    _speaking = true;
    try {
      await _prepare();
      if (!_ok) return;
      // El tono sigue al modo actual.
      await _tts.setPitch(MusicModeService.general ? 1.05 : 0.92);
      final text = await _line(prev, next);
      // Que la canción arranque un momento antes de hablar.
      await Future<void>.delayed(const Duration(seconds: 4));
      if (!PlaybackUi.instance.playing.value) return;
      await PlaybackService.instance.duck(true);
      // Tiempo límite: si el motor de voz no responde, la música vuelve.
      await _tts.speak(text).timeout(const Duration(seconds: 25));
    } catch (_) {
    } finally {
      await PlaybackService.instance.duck(false);
      _speaking = false;
    }
  }
}
