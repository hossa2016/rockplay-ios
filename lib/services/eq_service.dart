import 'package:audio_session/audio_session.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/song.dart';
import 'music_mode.dart';
import 'ai_client.dart';
import 'embed_bridge.dart';
import 'playback_service.dart';

/// Sugerencia del asistente para una canción.
class EqSuggestion {
  final String preset;
  final String reason;
  final String source; // Gemini, Groq o Reglas
  const EqSuggestion(this.preset, this.reason, this.source);
}

/// Ecualizador de 10 bandas.
/// - YouTube integrado: filtros de Web Audio dentro del WebView del reproductor.
/// - Radio / just_audio: AndroidEqualizer del sistema.
class EqService extends ChangeNotifier {
  EqService._();
  static final EqService instance = EqService._();

  static const List<int> freqs = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000];
  static const List<String> labels = ['31', '62', '125', '250', '500', '1k', '2k', '4k', '8k', '16k'];

  static const Map<String, List<double>> presets = {
    'Rock': [5, 4, 3, 1, -1, -1, 1, 3, 4, 5],
    'Metal': [6, 5, 2, 0, -2, -1, 2, 4, 5, 4],
    'Grunge': [4, 4, 3, 2, 0, -1, 1, 2, 2, 2],
    'Punk': [3, 3, 2, 0, 0, 1, 3, 4, 4, 3],
    'Clásico': [3, 3, 2, 1, 0, 0, 1, 2, 3, 3],
    'Acústico': [2, 2, 1, 1, 0, 1, 2, 3, 3, 2],
    'En vivo': [2, 2, 1, 0, -1, 0, 1, 2, 3, 3],
    'Voces': [-2, -1, 0, 1, 3, 4, 4, 3, 1, 0],
    'Graves': [7, 6, 4, 2, 0, 0, 0, 0, 0, 0],
    'Plano': [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    // Modo «Todos los géneros».
    'Pop': [-1, 0, 2, 3, 3, 2, 1, 1, 2, 2],
    'Urbano': [7, 6, 4, 1, -1, 0, 1, 1, 2, 2],
    'Salsa': [3, 3, 1, 0, 1, 2, 3, 4, 3, 2],
  };

  /// Nombres viejos (antes había dos por curva) → el único actual.
  static const Map<String, String> _renamed = {
    'Voz': 'Voces',
    'Más graves': 'Graves',
  };

  static const List<String> _rockNames = [
    'Rock', 'Metal', 'Grunge', 'Punk', 'Clásico', 'Acústico', 'En vivo',
    'Voces', 'Graves', 'Plano',
  ];
  static const List<String> _generalNames = [
    'Pop', 'Urbano', 'Salsa', 'Acústico', 'Voces', 'Graves', 'En vivo', 'Plano',
  ];

  /// Preajustes que se muestran en el modo actual.
  static List<String> get visible =>
      MusicModeService.general ? _generalNames : _rockNames;

  static String get defaultPreset => MusicModeService.general ? 'Pop' : 'Rock';

  /// Al cambiar de modo: si el preajuste no existe en el nuevo, se pasa al
  /// de por defecto (los ajustes personalizados se respetan).
  void syncMode() {
    // La sugerencia era del otro modo («Pop» en rock): se descarta y se
    // pide de nuevo para la canción actual.
    if (suggestion != null && !visible.contains(suggestion!.preset)) {
      suggestion = null;
      suggestionFor = '';
      final s = _lastSong;
      if (auto && s != null && !s.isRadio) unawaited(_suggestAndApply(s));
      notifyListeners();
    }
    if (preset == 'Personalizado' || visible.contains(preset)) return;
    applyPreset(defaultPreset);
  }

  /// Ecualizador del sistema para el reproductor just_audio (radio y audio directo).
  final AndroidEqualizer androidEq = AndroidEqualizer();

  bool enabled = true;
  bool auto = false;
  /// Recordar un preajuste por audífono o salida (parlante, Bluetooth…).
  bool perDevice = false;
  String device = 'Parlante del teléfono';
  Map<String, String> _devPreset = {};
  String preset = defaultPreset;
  List<double> gains = List<double>.from(presets[defaultPreset]!);

  /// Estado del ecualizador en el reproductor de YouTube, para mostrarlo.
  String embedStatus = '';
  EqSuggestion? suggestion;
  String suggestionFor = '';
  bool suggesting = false;

  final Map<String, EqSuggestion> _cache = {};

  /// Consultas de IA hechas hoy por el ecualizador.
  int aiToday = 0;

  static String _today() {
    final d = DateTime.now();
    return '${d.year}-${d.month}-${d.day}';
  }

  Future<void> _countAi() async {
    aiToday++;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('eq_ai_day', _today());
      await p.setInt('eq_ai_count', aiToday);
    } catch (_) {}
  }

  Future<void> _saveCache() async {
    try {
      final entries = _cache.entries.toList();
      final keep = entries.length > 400 ? entries.sublist(entries.length - 400) : entries;
      final p = await SharedPreferences.getInstance();
      await p.setString('eq_cache', jsonEncode({
        for (final e in keep) e.key: [e.value.preset, e.value.reason, e.value.source]
      }));
    } catch (_) {}
  }
  Timer? _timer;
  bool _inited = false;

  Future<void> init() async {
    if (_inited) return;
    _inited = true;
    try {
      final p = await SharedPreferences.getInstance();
      enabled = p.getBool('eq_on') ?? true;
      auto = p.getBool('eq_auto') ?? false;
      perDevice = p.getBool('eq_per_device') ?? false;
      final dp = p.getString('eq_dev_presets');
      if (dp != null) {
        _devPreset = (jsonDecode(dp) as Map).map((k, v) => MapEntry('$k', '$v'));
      }
      preset = p.getString('eq_preset') ?? defaultPreset;
      preset = _renamed[preset] ?? preset;
      final c = p.getString('eq_cache');
      if (c != null) {
        final m = jsonDecode(c) as Map<String, dynamic>;
        m.forEach((k, v) {
          if (v is List && v.length == 3) {
            _cache[k] = EqSuggestion(v[0].toString(), v[1].toString(), v[2].toString());
          }
        });
      }
      final today = _today();
      aiToday = p.getString('eq_ai_day') == today ? (p.getInt('eq_ai_count') ?? 0) : 0;
      final g = p.getString('eq_gains');
      if (g != null) {
        final l = (jsonDecode(g) as List).map((e) => (e as num).toDouble()).toList();
        if (l.length == 10) gains = l;
      }
    } catch (_) {}
    // Preajuste guardado de rock («Metal») abriendo en modo general.
    syncMode();
    // Reaplica cada 3 s: YouTube puede cambiar el elemento de video al pasar de canción.
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _applyEmbed());
    try {
      PlaybackService.instance.currentSong.listen(_onSong);
    } catch (_) {}
    unawaited(applyAll());
    unawaited(_watchDevices());
  }

  /// Salida actual: audífonos Bluetooth/cable si hay, si no el parlante.
  Future<void> _watchDevices() async {
    try {
      final session = await AudioSession.instance;
      Future<void> check() async {
        final ds = await session.getDevices(includeInputs: false);
        AudioDevice? best;
        // Por nombre del tipo: cubre Bluetooth clásico, LE Audio/BLE,
        // cable y USB-C (los nombres exactos cambian entre versiones).
        final wanted = RegExp(r'bluetooth|ble|headset|headphones|usb|hearing',
            caseSensitive: false);
        for (final d in ds) {
          if (wanted.hasMatch(d.type.name)) {
            best = d;
            break;
          }
        }
        final name = best == null
            ? 'Parlante del teléfono'
            : (best.name.trim().isEmpty ? 'Audífonos' : best.name.trim());
        if (name == device) return;
        device = name;
        final pr = _devPreset[name];
        if (perDevice && pr != null && presets.containsKey(pr)) {
          applyPreset(pr);
        } else {
          notifyListeners();
        }
      }

      await check();
      session.devicesChangedEventStream.listen((_) async {
        try {
          await check();
        } catch (_) {}
      });
    } catch (_) {}
  }

  Future<void> setPerDevice(bool v) async {
    perDevice = v;
    if (v && preset != 'Personalizado') _devPreset[device] = preset;
    await _save();
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool('eq_on', enabled);
      await p.setBool('eq_auto', auto);
      await p.setBool('eq_per_device', perDevice);
      await p.setString('eq_dev_presets', jsonEncode(_devPreset));
      await p.setString('eq_preset', preset);
      await p.setString('eq_gains', jsonEncode(gains));
    } catch (_) {}
  }

  // ------------------------------------------------------------ cambios

  void setEnabled(bool v) {
    enabled = v;
    _changed();
  }

  void setAuto(bool v) {
    auto = v;
    _changed();
    if (v) {
      final s = _lastSong;
      if (s != null) unawaited(_suggestAndApply(s));
    }
  }

  void applyPreset(String name) {
    name = _renamed[name] ?? name;
    final p = presets[name];
    if (p == null) return;
    preset = name;
    if (perDevice) _devPreset[device] = name;
    gains = List<double>.from(p);
    _changed();
  }

  void setGain(int band, double db) {
    gains[band] = db.clamp(-12, 12).toDouble();
    preset = 'Personalizado';
    _changed();
  }

  void _changed() {
    notifyListeners();
    unawaited(_save());
    unawaited(applyAll());
  }

  Future<void> applyAll() async {
    await _applyEmbed();
    await applyAndroid();
  }

  // ------------------------------------------------------------ YouTube (Web Audio)

  String _js() {
    final g = '[${gains.map((e) => e.toStringAsFixed(1)).join(',')}]';
    return '''
(function(g,on){try{
 var f=document.querySelector('iframe'); if(!f) return 'sin-reproductor';
 var d=null; try{d=f.contentDocument;}catch(e){return 'bloqueado';}
 if(!d) return 'bloqueado';
 var v=d.querySelector('video'); if(!v) return 'sin-video';
 var w=window; var e=w.__rpeq;
 if(!e){ var AC=w.AudioContext||w.webkitAudioContext; if(!AC) return 'sin-webaudio';
   e={ctx:new AC(),v:null}; w.__rpeq=e; }
 if(e.ctx.state!=='running'){ e.ctx.resume(); if(!e.v) return 'esperando'; }
 if(e.v!==v){
   if(!on && !e.v) return 'apagado';
   var ctx=e.ctx; var src=ctx.createMediaElementSource(v);
   var pre=ctx.createGain();
   var fr=[31,62,125,250,500,1000,2000,4000,8000,16000];
   var fs=fr.map(function(x,i){var b=ctx.createBiquadFilter();
     b.type=i==0?'lowshelf':(i==fr.length-1?'highshelf':'peaking');
     b.frequency.value=x; b.Q.value=1.1; return b;});
   src.connect(pre); var n=pre; fs.forEach(function(b){n.connect(b); n=b;}); n.connect(ctx.destination);
   e.v=v; e.pre=pre; e.fs=fs;
 }
 var mx=0; for(var i=0;i<10;i++){ var x=on?g[i]:0; e.fs[i].gain.value=x; if(x>mx) mx=x; }
 e.pre.gain.value=Math.pow(10,-(mx*0.6)/20);
 return on?'activo':'apagado';
}catch(err){return 'error: '+err.message;}})($g,$enabled)''';
  }

  bool _busy = false;
  Future<void> _applyEmbed() async {
    if (_busy) return;
    final c = EmbedBridge.instance.controller;
    if (c == null) return;
    _busy = true;
    try {
      final r = await c.webViewController
          .runJavaScriptReturningResult(_js())
          .timeout(const Duration(seconds: 3));
      var s = r.toString();
      if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) s = s.substring(1, s.length - 1);
      if (s != embedStatus) {
        embedStatus = s;
        notifyListeners();
      }
    } catch (_) {
    } finally {
      _busy = false;
    }
  }

  // ------------------------------------------------------------ just_audio (Android)

  Future<void> applyAndroid() async {
    try {
      await androidEq.setEnabled(enabled);
      if (!enabled) return;
      final params = await androidEq.parameters.timeout(const Duration(seconds: 4));
      for (final band in params.bands) {
        final db = _gainAt(band.centerFrequency).clamp(params.minDecibels, params.maxDecibels);
        await band.setGain(db.toDouble());
      }
    } catch (_) {
      // Sin fuente cargada todavía: se aplica al cargar la siguiente.
    }
  }

  /// Interpola la curva de 10 bandas en escala logarítmica.
  double _gainAt(double hz) {
    final x = math.log(hz.clamp(31, 16000));
    for (var i = 0; i < freqs.length - 1; i++) {
      final a = math.log(freqs[i].toDouble());
      final b = math.log(freqs[i + 1].toDouble());
      if (x <= b) {
        final t = ((x - a) / (b - a)).clamp(0.0, 1.0);
        return gains[i] + (gains[i + 1] - gains[i]) * t;
      }
    }
    return gains.last;
  }

  // ------------------------------------------------------------ asistente

  Song? _lastSong;

  void _onSong(Song? s) {
    _lastSong = s;
    // El reproductor de radio/audio directo crea su sesión al cargar: reaplicar.
    unawaited(Future<void>.delayed(const Duration(seconds: 2), applyAndroid));
    if (s == null || s.isRadio) return;
    final key = '${MusicModeService.general ? 'g|' : ''}${s.artist}|${s.title}';
    if (key == suggestionFor) return;
    if (auto) {
      unawaited(_suggestAndApply(s));
    } else {
      suggestion = null;
      suggestionFor = '';
      notifyListeners();
    }
  }

  Future<void> _suggestAndApply(Song s) async {
    final gen = MusicModeService.generation;
    final r = await suggest(s);
    if (gen != MusicModeService.generation) return;
    if (r != null && visible.contains(r.preset) && auto && presets.containsKey(r.preset)) applyPreset(r.preset);
  }

  Future<EqSuggestion?> suggestCurrent() async {
    final s = _lastSong;
    if (s == null || s.isRadio) return null;
    return suggest(s);
  }

  Song? get currentSong => _lastSong;

  Future<EqSuggestion?> suggest(Song s) async {
    final key = '${MusicModeService.general ? 'g|' : ''}${s.artist}|${s.title}';
    final cached = _cache[key];
    if (cached != null && visible.contains(cached.preset)) {
      suggestion = cached;
      suggestionFor = key;
      notifyListeners();
      return cached;
    }
    // Reglas primero: si el artista o el título ya lo dicen, no se gasta IA.
    EqSuggestion? out = _rules(s, known: true);
    if (out != null) {
      _cache[key] = out;
      unawaited(_saveCache());
      suggestion = out;
      suggestionFor = key;
      notifyListeners();
      return out;
    }
    suggesting = true;
    notifyListeners();
    var counted = false;
    final system =
        'Eres un ingeniero de sonido experto en ${MusicModeService.general ? 'todos los géneros musicales' : 'rock'}. Elige el mejor preajuste de ecualizador '
        'para escuchar la canción con audífonos inalámbricos. Opciones exactas: '
        '${visible.where((n) => n != 'Plano').join(', ')}. Responde SOLO JSON: '
        '{"preset":"<opción>","reason":"<una frase corta en español, máximo 18 palabras>"}';
    final msgs = [AiMessage(true, 'Canción: "${s.title}" de ${s.artist}.')];
    for (final entry in <MapEntry<String, Future<String> Function()>>[
      MapEntry('Gemini', () => AiClient.instance.gemini(system, msgs)),
      MapEntry('Groq', () => AiClient.instance.groq(system, msgs)),
    ]) {
      try {
        if (!counted) { counted = true; unawaited(_countAi()); }
        final raw = await entry.value().timeout(const Duration(seconds: 20));
        final a = raw.indexOf('{');
        final z = raw.lastIndexOf('}');
        if (a < 0 || z <= a) continue;
        final j = jsonDecode(raw.substring(a, z + 1));
        final p = (j['preset'] ?? '').toString().trim();
        if (!visible.contains(p)) continue;
        out = EqSuggestion(p, (j['reason'] ?? '').toString().trim(), entry.key);
        break;
      } catch (_) {}
    }
    out ??= _rules(s)!;
    _cache[key] = out;
    unawaited(_saveCache());
    suggestion = out;
    suggestionFor = key;
    suggesting = false;
    notifyListeners();
    return out;
  }

  static const Map<String, List<String>> _artists = {
    'Metal': ['metallica', 'slayer', 'megadeth', 'system of a down', 'slipknot', 'korn', 'mudvayne',
      'pantera', 'iron maiden', 'judas priest', 'sepultura', 'lamb of god', 'disturbed', 'tool',
      'black sabbath', 'motörhead', 'motorhead', 'avenged sevenfold', 'gojira', 'rammstein',
      'trivium', 'machine head', 'deftones', 'mastodon', 'anthrax', 'testament', 'dream theater',
      'linkin park', 'papa roach', 'godsmack', 'five finger death punch', 'kreator'],
    'Grunge': ['nirvana', 'pearl jam', 'soundgarden', 'alice in chains', 'stone temple pilots',
      'silverchair', 'audioslave', 'temple of the dog', 'mudhoney', 'screaming trees', 'bush', 'hole'],
    'Punk': ['ramones', 'green day', 'blink-182', 'blink 182', 'the offspring', 'offspring',
      'sex pistols', 'the clash', 'rancid', 'bad religion', 'nofx', 'sum 41', 'misfits',
      'dead kennedys', 'pennywise', 'social distortion', 'rise against', 'the casualties'],
    'Clásico': ['led zeppelin', 'the beatles', 'beatles', 'rolling stones', 'queen', 'ac/dc', 'acdc',
      'deep purple', 'pink floyd', 'the doors', 'creedence', 'kiss', 'the who', 'aerosmith',
      'guns n\' roses', 'guns n roses', 'scorpions', 'bon jovi', 'van halen', 'eagles', 'boston',
      'rush', 'def leppard', 'whitesnake', 'soda stereo', 'héroes del silencio', 'heroes del silencio'],
  };

  static const Map<String, List<String>> _generalArtists = {
    'Urbano': ['bad bunny', 'karol g', 'j balvin', 'daddy yankee', 'feid', 'maluma', 'ozuna',
      'rauw alejandro', 'anuel', 'myke towers', 'nicky jam', 'don omar', 'wisin', 'farruko',
      'blessd', 'ryan castro', 'sech', 'arcángel', 'jhayco', 'quevedo', 'young miko', 'eminem',
      'drake', 'kendrick lamar', 'travis scott', '50 cent', 'dr. dre'],
    'Salsa': ['grupo niche', 'marc anthony', 'joe arroyo', 'héctor lavoe', 'hector lavoe',
      'celia cruz', 'willie colón', 'willie colon', 'rubén blades', 'ruben blades', 'guayacán',
      'guayacan', 'oscar d\'león', 'fruko', 'gilberto santa rosa', 'victor manuelle',
      'gran combo', 'frankie ruiz', 'eddie santiago', 'jerry rivera', 'la india', 'tito nieves'],
    'Acústico': ['norah jones', 'jorge drexler', 'natalia lafourcade', 'ed sheeran',
      'jack johnson', 'john mayer', 'bon iver', 'ludovico einaudi', 'chopin', 'debussy'],
    'Voces': ['adele', 'luis miguel', 'whitney houston', 'ella fitzgerald', 'laura pausini',
      'marco antonio solís', 'ricardo arjona', 'alejandro sanz', 'rocío dúrcal', 'juan gabriel',
      'diomedes díaz', 'silvestre dangond', 'jorge celedón', 'binomio de oro'],
    'Graves': ['calvin harris', 'david guetta', 'avicii', 'daft punk', 'martin garrix', 'tiësto',
      'skrillex', 'marshmello', 'swedish house mafia', 'major lazer', 'diplo'],
  };

  /// Con [known] = true devuelve null si no reconoce nada (para preguntar a la IA).
  EqSuggestion? _rules(Song s, {bool known = false}) {
    if (MusicModeService.general) return _rulesGeneral(s, known: known);
    return _rulesRock(s, known: known);
  }

  EqSuggestion? _rulesGeneral(Song s, {bool known = false}) {
    final t = s.title.toLowerCase();
    final a = s.artist.toLowerCase();
    if (t.contains('live') || t.contains('en vivo') || t.contains('directo')) {
      return const EqSuggestion('En vivo', 'Grabación en vivo: más aire y presencia de público.', 'Reglas');
    }
    if (t.contains('acoustic') || t.contains('acústic') || t.contains('acustic') || t.contains('unplugged')) {
      return const EqSuggestion('Acústico', 'Versión acústica: cuerdas y voz con más detalle.', 'Reglas');
    }
    for (final e in _generalArtists.entries) {
      if (e.value.any((n) => a.contains(n))) {
        final why = {
          'Urbano': 'Bajos profundos y voz clara para el sonido urbano.',
          'Salsa': 'Metales y percusión al frente, con bajo firme.',
          'Acústico': 'Cuerdas, piano y voz con más detalle.',
          'Voces': 'La voz al frente, con medios claros.',
          'Graves': 'Más bajo y bombo para la electrónica.',
        }[e.key]!;
        return EqSuggestion(e.key, why, 'Reglas');
      }
    }
    if (known) return null;
    return const EqSuggestion('Pop', 'Voz presente y brillo suave, equilibrado para casi todo.', 'Reglas');
  }

  EqSuggestion? _rulesRock(Song s, {bool known = false}) {
    final t = s.title.toLowerCase();
    final a = s.artist.toLowerCase();
    if (t.contains('live') || t.contains('en vivo') || t.contains('directo')) {
      return const EqSuggestion('En vivo', 'Grabación en vivo: más aire y presencia de público.', 'Reglas');
    }
    if (t.contains('acoustic') || t.contains('acústic') || t.contains('acustic') || t.contains('unplugged')) {
      return const EqSuggestion('Acústico', 'Versión acústica: cuerdas y voz con más detalle.', 'Reglas');
    }
    for (final e in _artists.entries) {
      if (e.value.any((n) => a.contains(n))) {
        final why = {
          'Metal': 'Guitarras con cuerpo y doble bombo bien marcado.',
          'Grunge': 'Guitarras gruesas y medios cálidos, típicos del grunge.',
          'Punk': 'Guitarras al frente y voces con más ataque.',
          'Clásico': 'Sonido equilibrado y cálido para rock clásico.',
        }[e.key]!;
        return EqSuggestion(e.key, why, 'Reglas');
      }
    }
    if (known) return null;
    return const EqSuggestion('Rock', 'Graves y agudos realzados, el sonido rock de siempre.', 'Reglas');
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
