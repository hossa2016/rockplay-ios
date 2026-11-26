import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../models/song.dart';
import '../widgets/playback_ui.dart';
import 'song_fix.dart';
import 'stats_service.dart';

/// Registro (scrobbling) en Last.fm, opcional. Necesita una API key y su
/// secreto (gratis en last.fm/api) y tu usuario y contraseña de Last.fm
/// (solo para pedir la sesión; la contraseña no se guarda).
class LastFmService {
  LastFmService._();
  static final LastFmService instance = LastFmService._();

  static const FlutterSecureStorage _sec = FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true));
  static const String _api = 'https://ws.audioscrobbler.com/2.0/';

  String apiKey = '', secret = '', session = '', user = '';
  final ValueNotifier<bool> connected = ValueNotifier<bool>(false);

  Song? _cur;
  int _startTs = 0;
  bool _sent = false;

  Future<void> init() async {
    try {
      apiKey = await _sec.read(key: 'lfm_key') ?? '';
      secret = await _sec.read(key: 'lfm_secret') ?? '';
      session = await _sec.read(key: 'lfm_session') ?? '';
      user = await _sec.read(key: 'lfm_user') ?? '';
    } catch (_) {}
    connected.value = session.isNotEmpty;
    PlaybackUi.instance.song.addListener(_onSong);
    PlaybackUi.instance.position.addListener(_onPos);
  }

  String _sig(Map<String, String> p) {
    final keys = p.keys.toList()..sort();
    final b = StringBuffer();
    for (final k in keys) {
      b
        ..write(k)
        ..write(p[k]);
    }
    b.write(secret);
    return md5.convert(utf8.encode(b.toString())).toString();
  }

  Future<Map<String, dynamic>> _post(Map<String, String> p) async {
    final body = {...p, 'api_key': apiKey};
    body['api_sig'] = _sig(body);
    body['format'] = 'json';
    final r = await http
        .post(Uri.parse(_api), body: body)
        .timeout(const Duration(seconds: 12));
    return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// Pide la sesión. Devuelve null si salió bien, o el motivo del error.
  Future<String?> connect(
      String key, String sec, String username, String password) async {
    apiKey = key.trim();
    secret = sec.trim();
    try {
      final j = await _post({
        'method': 'auth.getMobileSession',
        'username': username.trim(),
        'password': password,
      });
      final s = (j['session'] as Map?)?['key'] as String?;
      if (s == null) return '${j['message'] ?? 'No se pudo conectar'}';
      session = s;
      user = username.trim();
      lastError.value = '';
      await _sec.write(key: 'lfm_key', value: apiKey);
      await _sec.write(key: 'lfm_secret', value: secret);
      await _sec.write(key: 'lfm_session', value: session);
      await _sec.write(key: 'lfm_user', value: user);
      connected.value = true;
      return null;
    } catch (_) {
      return 'Sin conexión';
    }
  }

  Future<void> disconnect() async {
    session = '';
    connected.value = false;
    await _sec.delete(key: 'lfm_session');
  }

  String _artist = '', _title = '';

  /// Artista y título reales (sin canales de YouTube), con SongFix/Deezer.
  Future<void> _resolveArtist(Song s) async {
    try {
      final f = await SongFix.verify(s);
      if (_cur == s) {
        _artist = StatsService.cleanArtist(f.artist);
        _title = f.title;
      }
    } catch (_) {}
  }

  /// Envía y revisa errores: sesión vencida (9) → desconecta y avisa.
  final ValueNotifier<String> lastError = ValueNotifier<String>('');

  Future<void> _send(Map<String, String> p) async {
    try {
      final j = await _post(p);
      final err = j['error'];
      if (err == 9) {
        await disconnect();
        lastError.value = 'La sesión de Last.fm venció: conéctate de nuevo.';
      } else if (err != null) {
        lastError.value = 'Last.fm: ${j['message'] ?? err}';
      }
    } catch (_) {}
  }

  void _onSong() {
    final s = PlaybackUi.instance.song.value;
    if (s == null || s.isRadio || session.isEmpty) {
      _cur = null;
      return;
    }
    // Misma canción repetida: se vuelve a registrar si empieza desde cero.
    if (_cur != null && _cur!.artist == s.artist && _cur!.title == s.title &&
        !_sent) {
      return;
    }
    _cur = s;
    _artist = '';
    unawaited(_resolveArtist(s));
    _sent = false;
    _startTs = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    unawaited(_send({
      'method': 'track.updateNowPlaying',
      'artist': StatsService.cleanArtist(s.artist),
      'track': s.title,
      'sk': session,
    }));
  }

  /// Se registra al pasar la mitad de la canción o los 4 minutos.
  void _onPos() {
    final s = _cur;
    if (s == null || _sent || session.isEmpty) return;
    final pos = PlaybackUi.instance.position.value.inSeconds;
    final dur = PlaybackUi.instance.duration.value?.inSeconds ?? 0;
    if (dur < 30) return;
    if (pos < dur / 2 && pos < 240) return;
    _sent = true;
    unawaited(_send({
      'method': 'track.scrobble',
      'artist[0]': _artist.isNotEmpty ? _artist : StatsService.cleanArtist(s.artist),
      'track[0]': _title.isNotEmpty ? _title : s.title,
      'timestamp[0]': '$_startTs',
      'sk': session,
    }));
  }
}
