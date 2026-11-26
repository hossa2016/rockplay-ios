import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'ai_settings.dart';
import 'stats_service.dart';
import 'music_mode.dart';
import 'radar_service.dart';

/// Un concierto encontrado en internet.
class Concert {
  final String band;
  final String city;
  final String venue;
  /// Nula cuando el concierto está anunciado sin fecha exacta.
  final DateTime? date;
  /// Lo que se sabe de la fecha si no es exacta ("Marzo 2027").
  final String when;
  final String time;
  final String tickets;
  final String source;
  /// Género principal (punk, grunge, metal…).
  final String genre;
  /// "bar", "escenario" o "festival".
  final String kind;

  /// El bar publicó la fecha pero no quién toca: la «banda» es el lugar
  /// («La Cúpula» en La Cúpula Rock Bar).
  bool get lineupUnknown {
    final b = ConcertService._fuzzy(band), v = ConcertService._fuzzy(venue);
    if (b.isEmpty) return true;
    if (v.isEmpty) return false;
    return v.contains(b) || b.contains(v);
  }

  /// Nombre para mostrar.
  String get title => lineupUnknown
      ? 'Toques en ${venue.isNotEmpty ? venue : band}'
      : band;

  const Concert({
    required this.band,
    required this.city,
    required this.venue,
    required this.date,
    this.when = '',
    this.time = '',
    this.tickets = '',
    this.source = '',
    this.genre = '',
    this.kind = '',
  });

  Map<String, dynamic> toJson() => {
        'banda': band,
        'ciudad': city,
        'lugar': venue,
        'fecha': date == null ? '' : _ymd(date!),
        'cuando': when,
        'hora': time,
        'boletas': tickets,
        'fuente': source,
        'genero': genre,
        'tipo': kind,
      };

  /// «Teatro universidad de medellín» → «Teatro Universidad de Medellín».
  /// Respeta lo que ya trae mayúsculas internas (siglas, «BarCo»).
  static String _cap(String s) {
    const small = {'de', 'del', 'la', 'las', 'el', 'los', 'y', 'en', 'a'};
    var i = 0;
    return s.split(' ').map((w) {
      final first = i++ == 0;
      if (w.isEmpty) return w;
      if (w != w.toLowerCase()) return w;
      if (!first && small.contains(w)) return w;
      return w[0].toUpperCase() + w.substring(1);
    }).join(' ');
  }

  static Concert? fromJson(dynamic j) {
    if (j is! Map) return null;
    String s(String k) => (j[k] ?? '').toString().trim();
    // Sin banda pero con lugar = toque sin cartel («Toques en…»).
    final band = s('banda').isEmpty ? s('lugar') : s('banda');
    final date = DateTime.tryParse(s('fecha'));
    if (band.isEmpty) return null;
    return Concert(
      band: band,
      city: s('ciudad'),
      venue: _cap(s('lugar')),
      date: date == null ? null : DateTime(date.year, date.month, date.day),
      when: date == null ? (s('cuando').isEmpty ? 'Por confirmar' : s('cuando')) : '',
      time: s('hora'),
      tickets: _url(s('boletas')).isNotEmpty
          ? _url(s('boletas'))
          : (isTicketSite(s('fuente')) ? _url(s('fuente')) : ''),
      source: _url(s('fuente')),
      genre: s('genero'),
      kind: s('tipo').toLowerCase(),
    );
  }

  /// Boleterías conocidas: si la fuente es una de ellas, es el enlace de compra.
  static const List<String> ticketSites = [
    'tuboleta.com',
    'eticket.co',
    'ticketmaster.co',
    'ticketmaster.com',
    'taquillalive.com',
    'primerafila.com.co',
    'colboletos.com',
    'passline.com',
    'livepass.com',
    'ticketshop.com.co',
  ];

  static bool isTicketSite(String url) {
    final h = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    return h.isNotEmpty && ticketSites.any((t) => h == t || h.endsWith('.$t'));
  }

  /// Búsqueda en Google de boletas para cuando no hay enlace directo.
  String get ticketSearchUrl => Uri.https('www.google.com', '/search', {
        'q': '$band ${city.isEmpty ? 'Colombia' : city} boletas',
      }).toString();

  static String _url(String u) =>
      u.startsWith('http://') || u.startsWith('https://') ? u : '';
}

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Escenarios conocidos y su ciudad real (la búsqueda a veces pone «Cota»
/// o «Chía» para un concierto en Bogotá).
const Map<String, String> _venueCity = {
  'vive claro': 'Bogotá',
  'movistar arena': 'Bogotá',
  'coliseo medplus': 'Bogotá',
  'coliseo live': 'Bogotá',
  'estadio el campín': 'Bogotá',
  'estadio el campin': 'Bogotá',
  'parque simón bolívar': 'Bogotá',
  'parque simon bolivar': 'Bogotá',
  'royal center': 'Bogotá',
  'teatro colsubsidio': 'Bogotá',
  'teatro jorge eliécer gaitán': 'Bogotá',
  'teatro jorge eliecer gaitan': 'Bogotá',
  'ágora bogotá': 'Bogotá',
  'agora bogota': 'Bogotá',
  'estadio atanasio girardot': 'Medellín',
  'la macarena': 'Medellín',
  'teatro metropolitano': 'Medellín',
  'arena cañaveralejo': 'Cali',
  'arena canaveralejo': 'Cali',
  'estadio pascual guerrero': 'Cali',
};

/// ¿Es un tributo y no la banda real? («Tributo a Soda Stereo», «… Tribute»).
bool isTribute(Concert c) => RegExp(
        r'\btribut[oe]s?\b|\btribute\b|\bhomenaje\b|\bcover band\b',
        caseSensitive: false)
    .hasMatch('${c.band} ${c.venue}');

/// Ciudad del concierto, corregida por el escenario cuando se conoce.
String concertCity(Concert c) {
  final v = c.venue.toLowerCase();
  for (final e in _venueCity.entries) {
    if (v.contains(e.key)) return e.value;
  }
  return c.city.trim();
}

const List<String> kMonthsShort = [
  'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
  'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic',
];
const List<String> kMonthsLong = [
  'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
  'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
];

class ConcertState {
  final List<Concert> items;
  final DateTime? updatedAt;
  final bool loading;
  final String? error;
  final bool noKey;

  const ConcertState({
    this.items = const [],
    this.updatedAt,
    this.loading = false,
    this.error,
    this.noKey = false,
  });
}

/// Busca en internet (Gemini + Google) los conciertos de rock en Colombia
/// de los próximos 12 meses. Guarda el resultado y solo vuelve a buscar
/// cada 3 días o cuando el usuario lo pide.
class ConcertService {
  ConcertService._();
  static final ConcertService instance = ConcertService._();

  static const Duration refreshEvery = Duration(days: 3);
  static String get _cacheKey => MusicModeService.general
      ? 'concerts_cache_general_v1'
      : 'concerts_cache_v1';

  /// Géneros de la búsqueda según el modo.
  static String get _scope => MusicModeService.general
      ? 'de todos los géneros: pop, pop latino, salsa, reguetón y urbano, '
          'vallenato, merengue, bachata, rock, electrónica, jazz, música '
          'clásica, baladas y regional'
      : 'de rock: rock clásico, hard rock, metal y sus variantes, punk, '
          'hardcore, ska punk, grunge, rock alternativo, indie rock, '
          'post-punk, stoner y rock en español';

  static String get _genreList => MusicModeService.general
      ? 'pop|salsa|urbano|vallenato|rock|electrónica|jazz|clásica|baladas|tropical|festival'
      : 'rock|metal|punk|grunge|alternativo|indie|rock en español|festival';

  /// Al cambiar de modo: cada modo tiene su propia lista guardada.
  void resetForMode() {
    _cacheRead = false;
    // Los bares de rock son solo del modo rock; en el general, los tuyos.
    bars = MusicModeService.general ? <String>[] : List<String>.of(defaultBars);
    state.value = const ConcertState();
  }

  /// Bares de rock que el usuario sigue; se buscan uno por uno.
  static const List<String> defaultBars = [
    'Barnaby Jones',
    'Kings Rock',
    'La Cúpula',
    'Virus Pub',
    'Jungle Burger',
  ];
  static String get _barsKey =>
      MusicModeService.general ? 'concert_bars_general_v1' : 'concert_bars_v1';
  List<String> bars = MusicModeService.general
      ? <String>[]
      : List<String>.of(defaultBars);

  Future<void> saveBars(List<String> list) async {
    bars = list.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setStringList(_barsKey, bars);
    } catch (_) {}
  }

  /// Cada línea es "Nombre del bar @usuario" (el @usuario es opcional).
  /// Acepta "Nombre @usuario", "Nombre instagram.com/usuario" o el enlace
  /// que da Instagram al tocar «Copiar enlace del perfil».
  static final RegExp _igLink =
      RegExp(r'(?:https?://)?(?:www\.)?instagram\.com/([A-Za-z0-9._]+)[^\s]*');

  static String barName(String line) {
    var t = line.replaceAll(_igLink, '');
    final i = t.indexOf('@');
    if (i >= 0) t = t.substring(0, i);
    return t.trim();
  }

  static String? barHandle(String line) {
    final l = _igLink.firstMatch(line);
    if (l != null) return l.group(1);
    final m = RegExp(r'@([A-Za-z0-9._]+)').firstMatch(line);
    return m?.group(1);
  }

  List<String> get barNames =>
      bars.map(barName).where((e) => e.isNotEmpty).toList();

  /// ¿El lugar del concierto es uno de los bares guardados?
  bool isFavoriteBar(Concert c) {
    final v = '${c.venue} ${c.band}'.toLowerCase();
    return barNames.any((b) => v.contains(b.toLowerCase()));
  }

  static final RegExp _barWords = RegExp(
      r'\b(bar|pub|taberna|bodega|club|caf[eé]|cantina|pascasia)\b',
      caseSensitive: false);

  /// Toques en bares: tus bares o cualquier bar, pub o club.
  bool isBar(Concert c) =>
      c.kind == 'bar' || isFavoriteBar(c) || _barWords.hasMatch(c.venue);

  final ValueNotifier<ConcertState> state =
      ValueNotifier<ConcertState>(const ConcertState());
  bool _cacheRead = false;

  /// Lee la caché y busca de nuevo si está vieja.
  Future<void> ensureLoaded() async {
    if (!_cacheRead) {
      _cacheRead = true;
      await _readCache();
      // Radar: revisa al abrir la app (una vez al día) si hay conciertos
      // de tus bandas que aún no te avisé.
      unawaited(RadarService.instance.notifyNew());
    }
    final s = state.value;
    if (s.loading) return;
    final old = s.updatedAt == null ||
        DateTime.now().difference(s.updatedAt!) > refreshEvery;
    if (old) await refresh();
  }

  Future<void> refresh() async {
    if (state.value.loading) return;
    final prev = state.value;
    state.value = ConcertState(
        items: prev.items, updatedAt: prev.updatedAt, loading: true);
    await AiSettings.instance.load();
    if (AiSettings.instance.geminiKey.trim().isEmpty &&
        AiSettings.instance.groqKey.trim().isEmpty) {
      state.value = ConcertState(
          items: prev.items, updatedAt: prev.updatedAt, noKey: true);
      return;
    }
    final gen = MusicModeService.generation;
    try {
      final found = await _search();
      // Cambió el modo mientras buscaba: este resultado es del otro modo.
      if (gen != MusicModeService.generation) return;
      final list = _merge(found, prev.items);
      final now = DateTime.now();
      state.value = ConcertState(items: list, updatedAt: now);
      _writeCache(list, now);
      // Radar: avisa si apareció un concierto de tus bandas.
      unawaited(RadarService.instance.notifyNew());
    } catch (e) {
      if (gen != MusicModeService.generation) return;
      state.value = ConcertState(
        items: _upcoming(prev.items),
        updatedAt: prev.updatedAt,
        error: e is String ? e : 'No se pudo buscar conciertos.',
      );
    }
  }

  Future<void> _readCache() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final saved = sp.getStringList(_barsKey);
      if (saved != null) bars = saved;
      final raw = sp.getString(_cacheKey);
      if (raw == null) return;
      final j = jsonDecode(raw);
      final at = DateTime.tryParse((j['at'] ?? '').toString());
      final items = <Concert>[
        for (final e in (j['items'] as List? ?? const []))
          if (Concert.fromJson(e) != null) Concert.fromJson(e)!,
      ];
      state.value = ConcertState(items: _upcoming(items), updatedAt: at);
    } catch (_) {}
  }

  Future<void> _writeCache(List<Concert> list, DateTime at) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(
          _cacheKey,
          jsonEncode({
            'at': at.toIso8601String(),
            'items': [for (final c in list) c.toJson()],
          }));
    } catch (_) {}
  }

  /// Une lo nuevo con lo que ya se había encontrado: una búsqueda nueva
  /// puede dejar por fuera un concierto que sigue vigente (p. ej. Slipknot).
  /// Los viejos se quedan hasta que pase su fecha.
  static List<Concert> _merge(List<Concert> fresh, List<Concert> old) {
    String key(Concert c) {
      final b = c.band.toLowerCase().split('(').first.trim();
      return c.date == null ? b : '$b|${_ymd(c.date!)}';
    }
    final have = {for (final c in fresh) key(c)};
    final bands = {
      for (final c in fresh) c.band.toLowerCase().split('(').first.trim()
    };
    return _upcoming([
      ...fresh,
      for (final c in old)
        if (!have.contains(key(c)) &&
            // Si ahora tiene fecha exacta, descarta el viejo "por confirmar".
            !(c.date == null &&
                bands.contains(c.band.toLowerCase().split('(').first.trim())))
          c,
    ]);
  }

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  static String _fuzzy(String s) {
    const from = 'áàäâéèëêíìïîóòöôúùüûñç';
    const to = 'aaaaeeeeiiiioooouuuunc';
    final b = StringBuffer();
    String prev = '';
    for (final ch in s.toLowerCase().split('')) {
      final i = from.indexOf(ch);
      final c = i >= 0 ? to[i] : ch;
      if (!RegExp(r'[a-z0-9]').hasMatch(c) || c == prev) continue;
      b.write(c);
      prev = c;
    }
    final r = b.toString();
    return r.startsWith('the') && r.length > 5 ? r.substring(3) : r;
  }

  static DateTime _limit() {
    final t = _today();
    return DateTime(t.year + 1, t.month, t.day);
  }

  /// Quita los que ya pasaron o están a más de 12 meses, ordena por fecha,
  /// deja al final los de fecha por confirmar y quita repetidos.
  static List<Concert> _upcoming(List<Concert> list) {
    final from = _today();
    final to = _limit();
    final seen = <String>{};
    final dated = <Concert>[];
    final tbd = <Concert>[];
    for (final c in list) {
      final d = c.date;
      if (d != null && (d.isBefore(from) || d.isAfter(to))) continue;
      // Nombre "difuso": sin tildes/símbolos y sin letras repetidas, así
      // "Kakkmaddafakk" y "Kakkmadafakk" cuentan como la misma banda.
      final k = '${_fuzzy(c.band)}|${d == null ? '' : _ymd(d)}';
      final k3 = d != null && c.city.trim().isNotEmpty
          ? '${_fuzzy(c.band)}|${_fuzzy(c.city)}|${_ymd(d)}'
          : null;
      // Mismo lugar y misma fecha = mismo evento aunque lo nombren distinto.
      final v = c.venue.toLowerCase().trim();
      final k2 = d != null && v.length > 3 && v != 'tba' ? '$v|${_ymd(d)}' : null;
      if (!seen.add(k)) continue;
      if (k2 != null && !seen.add(k2)) continue;
      if (k3 != null && !seen.add(k3)) continue;
      (d == null ? tbd : dated).add(c);
    }
    dated.sort((a, b) => a.date!.compareTo(b.date!));
    return [...dated, ...tbd];
  }

  Future<List<Concert>> _search() async {
    final s = AiSettings.instance;
    final from = _ymd(_today());
    final to = _ymd(_limit());
    final prompt =
        'Hoy es $from. Busca en internet los conciertos y festivales '
        '${MusicModeService.general ? 'de música' : 'de rock'} '
        'que se van a presentar en Colombia entre $from y $to (los próximos '
        '12 meses). Incluye todos los géneros $_scope; '
        'artistas internacionales y '
        'colombianas; en cualquier ciudad del país. Revisa varias fuentes '
        '(boleterías como Tuboleta, eTicket, Ticketmaster y Taquilla Live, '
        'medios de música y redes oficiales de los festivales). Incluye solo '
        'eventos anunciados oficialmente, con fecha dentro de ese rango. No '
        'inventes nada: si no conoces un dato, déjalo vacío. Para un festival '
        'usa como "banda" el nombre del festival seguido de las bandas '
        'principales entre paréntesis. Si un concierto ya está anunciado '
        'pero aún no tiene fecha exacta, inclúyelo igual: deja "fecha" vacía '
        'y pon en "cuando" lo que se sepa (por ejemplo "Marzo 2027" o '
        '"Por confirmar"). Incluye también los que aún no tienen boletería '
        'abierta.\n'
        'Responde SOLO con JSON válido, sin texto adicional, con esta forma:\n'
        '{"conciertos":[{"banda":"","ciudad":"","lugar":"","fecha":"AAAA-MM-DD o vacío","cuando":"",'
        '"hora":"","boletas":"url de compra o vacío","fuente":"url donde se '
        'anunció","genero":"$_genreList","tipo":"bar|escenario|festival"}]}';

    final errors = <String>[];
    // 1) Tavily busca en la web y Gemini/Groq (sin búsqueda) ordenan.
    if (s.tavilyKey.trim().isNotEmpty) {
      try {
        return await _viaTavily(s.tavilyKey.trim(), from, to);
      } catch (e) {
        errors.add('Tavily: $e');
      }
    }
    final geminiKey = s.geminiKey.trim();
    if (geminiKey.isNotEmpty) {
      for (final model in <String>{s.geminiModel, 'gemini-2.5-flash'}) {
        try {
          return _parse(await _gemini(model, geminiKey, prompt));
        } catch (e) {
          errors.add('Gemini ($model): $e');
        }
      }
    }
    final groqKey = s.groqKey.trim();
    if (groqKey.isNotEmpty) {
      for (final model in const ['groq/compound', 'groq/compound-mini']) {
        try {
          return _parse(await _groq(model, groqKey, prompt));
        } catch (e) {
          errors.add('Groq ($model): $e');
        }
      }
    }
    debugPrint('Conciertos: ${errors.join(' | ')}');
    if (errors.isEmpty) throw 'Falta una clave de Gemini o Groq.';
    // Muestra el error de la opción principal (Tavily si hay clave).
    throw 'No se pudo buscar en internet (${errors.first}). Intenta más tarde.';
  }

  /// Detalle de la última búsqueda (para revisar qué encontró cada grupo).
  final ValueNotifier<String> lastLog = ValueNotifier<String>('');

  /// Busca por grupos, en orden de prioridad, y ordena cada grupo por
  /// separado: así una respuesta larga no se corta y lo importante (tus
  /// bandas, escenarios grandes, tus bares) nunca queda al final.
  Future<List<Concert>> _viaTavily(String key, String from, String to) async {
    final now = DateTime.now();
    final y1 = now.year;
    final y2 = y1 + 1;
    final mes = kMonthsLong[now.month - 1].toLowerCase();
    var favs = <String>[];
    try {
      // Radar: las 10 primeras de tus bandas (seguidas, más escuchadas y
      // favoritas) se buscan una por una en cada actualización (cada 3 días).
      favs = (await RadarService.instance.bands())
          .where((e) => e.trim().isNotEmpty)
          .take(10)
          .toList();
    } catch (_) {}

    Map<String, dynamic> q(String text, [int n = 6]) =>
        {'query': text, 'max_results': n};
    final g = MusicModeService.general;
    final groups = <MapEntry<String, List<Map<String, dynamic>>>>[
      if (g) ...[
        MapEntry('Tus artistas', [
          for (final a in favs) q('$a concierto Colombia $y1 $y2', 4),
        ]),
        MapEntry('Escenarios grandes', [
          q('Vive Claro Bogotá conciertos $y2'),
          q('Movistar Arena Bogotá conciertos $y2'),
          q('Estadio Atanasio Girardot Medellín concierto $y2'),
          {
            ...q('conciertos Colombia $y1 $y2 boletas', 8),
            'include_domains': Concert.ticketSites,
          },
        ]),
        MapEntry('Géneros', [
          q('conciertos de pop en Colombia $y1 $y2'),
          q('conciertos de salsa en Colombia $y1 $y2'),
          q('conciertos de reguetón y urbano Colombia $y1 $y2'),
          q('conciertos de vallenato $y1 $y2'),
          q('conciertos de rock en Colombia $y1 $y2'),
          q('conciertos de música electrónica Colombia $y1 $y2'),
          q('conciertos de jazz y música clásica Colombia $y1 $y2'),
        ]),
        MapEntry('Medellín', [
          q('agenda de conciertos Medellín $mes $y1'),
          q('conciertos Medellín $y1 $y2'),
        ]),
        MapEntry('Festivales', [
          q('festivales de música Colombia $y2 cartel confirmado'),
          q('artistas internacionales gira Colombia $y2 boletas'),
        ]),
      ] else ...[
      MapEntry('Tus bandas', [
        for (final a in favs) q('$a concierto Colombia $y1 $y2', 4),
      ]),
      MapEntry('Escenarios grandes', [
        q('Vive Claro Bogotá conciertos $y2'),
        q('Movistar Arena Bogotá conciertos $y2 rock metal'),
        q('gira Sudamérica $y2 Bogotá confirmado rock metal'),
        {
          ...q('concierto rock metal Colombia $y1 $y2', 8),
          'include_domains': Concert.ticketSites,
        },
      ]),
      MapEntry('Bares de Medellín', [
        for (final b in barNames) q('"$b" Medellín rock', 4),
        {
          ...q('rock bar Medellín $mes $y1', 8),
          'include_domains': const [
            'eventbrite.co',
            'eventbrite.com',
            'passline.com',
            'tuboleta.com',
          ],
        },
        q('toques de rock en bares de Medellín $mes $y1'),
      ]),
      MapEntry('Agendas de Medellín', const [
        {
          'extract': [
            'https://www.eventworld.com/medellin/concerts/rock',
            'https://www.bandsintown.com/c/medellin-colombia',
            'https://www.songkick.com/metro-areas/28331-colombia-medellin',
          ],
        },
      ]),
      MapEntry('Medellín', [
        q('agenda conciertos rock punk metal Medellín $mes $y1'),
        q('conciertos rock Medellín $y1 $y2'),
      ]),
      MapEntry('Géneros', [
        q('conciertos de rock en Colombia $y1 $y2'),
        q('conciertos de metal en Colombia $y1 $y2'),
        q('conciertos punk hardcore ska Colombia $y1 $y2'),
        q('conciertos grunge rock alternativo indie Colombia $y1 $y2'),
        q('rock en español gira Colombia $y1 $y2'),
      ]),
      MapEntry('Festivales', [
        q('festivales de rock Colombia $y2 cartel confirmado'),
        q('bandas internacionales de rock gira Colombia $y2 boletas'),
      ]),
      ],
    ];

    final seen = <String>{};
    final all = <Concert>[];
    final log = <String>[];
    String? firstErr;
    var okGroups = 0;
    // Instagram de tus bares (Apify), si hay token y @usuarios.
    final handles = [
      for (final b in bars)
        if (barHandle(b) != null) barHandle(b)!,
    ];
    final apify = AiSettings.instance.apifyKey.trim();
    if (apify.isNotEmpty && handles.isNotEmpty) {
      try {
        final list = await _instagram(apify, handles, from, to);
        all.addAll(list);
        okGroups++;
        log.add('Instagram de bares: $_igStats → $_lastRaw eventos, '
            '${list.length} vigentes');
      } catch (e) {
        log.add('Instagram de bares: ${_igStats.isEmpty ? '' : '$_igStats → '}error: $e');
      }
    } else if (apify.isEmpty) {
      log.add('Instagram de bares: falta el token de Apify');
    } else {
      log.add('Instagram de bares: escribe el @usuario en Mis bares');
    }
    for (final g in groups) {
      if (g.value.isEmpty) continue;
      final found = <String>[];
      String? searchErr;
      for (final job in g.value) {
        if (job['extract'] is List) {
          found.addAll(await _extract(key, (job['extract'] as List).cast<String>()));
          continue;
        }
        try {
          final r = await http
              .post(
                Uri.parse('https://api.tavily.com/search'),
                headers: {
                  'Authorization': 'Bearer $key',
                  'Content-Type': 'application/json',
                },
                body: jsonEncode({'search_depth': 'basic', ...job}),
              )
              .timeout(const Duration(seconds: 30));
          if (r.statusCode != 200) {
            searchErr = r.statusCode == 401 || r.statusCode == 403
                ? 'clave de Tavily rechazada'
                : r.statusCode == 429 || r.statusCode == 432
                    ? 'se acabaron las búsquedas gratis de Tavily'
                    : 'Tavily error ${r.statusCode}';
            if (r.statusCode == 401 || r.statusCode == 403) {
              lastLog.value = searchErr;
              throw searchErr;
            }
            continue;
          }
          final j = jsonDecode(utf8.decode(r.bodyBytes));
          for (final it in (j['results'] as List? ?? const [])) {
            if (it is! Map) continue;
            final url = (it['url'] ?? '').toString();
            if (url.isEmpty || !seen.add(url)) continue;
            var content = (it['content'] ?? '').toString();
            if (content.length > 500) content = content.substring(0, 500);
            found.add('- ${it['title'] ?? ''}\n  URL: $url\n  $content');
          }
        } on String {
          rethrow;
        } catch (_) {
          searchErr = 'sin conexión';
        }
      }
      // Pausa corta entre grupos para no saturar el plan gratis de la IA.
      if (okGroups > 0 || log.isNotEmpty) {
        await Future<void>.delayed(const Duration(seconds: 2));
      }
      if (found.isEmpty) {
        log.add('${g.key}: 0 resultados${searchErr == null ? '' : ' ($searchErr)'}');
        continue;
      }
      try {
        final list = await _organize(found.join('\n'), from, to);
        all.addAll(list);
        okGroups++;
        log.add('${g.key}: ${found.length} resultados → ${list.length} conciertos');
      } catch (e) {
        firstErr ??= '$e';
        log.add('${g.key}: ${found.length} resultados → error: $e');
      }
    }
    lastLog.value = log.join('\n');
    if (okGroups == 0) {
      throw firstErr ?? 'Tavily no encontró resultados';
    }
    return _upcoming(all);
  }

  /// Lee páginas de agenda con Tavily Extract.
  Future<List<String>> _extract(String key, List<String> urls) async {
    try {
      final r = await http
          .post(
            Uri.parse('https://api.tavily.com/extract'),
            headers: {
              'Authorization': 'Bearer $key',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'urls': urls}),
          )
          .timeout(const Duration(seconds: 45));
      if (r.statusCode != 200) return const [];
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      return [
        for (final it in (j['results'] as List? ?? const []))
          if (it is Map)
            '- Agenda ${it['url']}\n  URL: ${it['url']}\n  ${_cut((it['raw_content'] ?? '').toString(), 6000)}',
      ];
    } catch (_) {
      return const [];
    }
  }

  static String _cut(String t, int n) => t.length > n ? t.substring(0, n) : t;

  /// Ejecuta un actor de Apify, espera a que termine y devuelve sus datos.
  Future<List<dynamic>> _apifyRun(
      String token, String actor, Map<String, dynamic> input) async {
    // Se lanza la ejecución y se espera a que termine (puede tardar 1-3
    // min); así se sabe si falló y por qué.
    http.Response r;
    try {
      r = await http
          .post(
            Uri.parse('https://api.apify.com/v2/acts/$actor/runs?token=$token'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(input),
          )
          .timeout(const Duration(seconds: 30));
    } catch (_) {
      throw 'Apify no respondió';
    }
    if (r.statusCode == 401 || r.statusCode == 403) throw 'token de Apify rechazado';
    if (r.statusCode == 402) throw 'se acabó el crédito gratis de Apify';
    if (r.statusCode != 200 && r.statusCode != 201) {
      throw 'Apify error ${r.statusCode}: ${_cut(utf8.decode(r.bodyBytes), 120)}';
    }
    var run = (jsonDecode(utf8.decode(r.bodyBytes)) as Map)['data'] as Map;
    final runId = run['id'];
    var status = (run['status'] ?? '').toString();
    final until = DateTime.now().add(const Duration(minutes: 4));
    while ((status == 'READY' || status == 'RUNNING') &&
        DateTime.now().isBefore(until)) {
      await Future<void>.delayed(const Duration(seconds: 8));
      try {
        final st = await http
            .get(Uri.parse('https://api.apify.com/v2/actor-runs/$runId?token=$token'))
            .timeout(const Duration(seconds: 20));
        if (st.statusCode == 200) {
          run = (jsonDecode(utf8.decode(st.bodyBytes)) as Map)['data'] as Map;
          status = (run['status'] ?? '').toString();
        }
      } catch (_) {}
    }
    final msg = (run['statusMessage'] ?? '').toString();
    if (status == 'RUNNING' || status == 'READY') {
      throw 'Apify sigue trabajando; vuelve a actualizar en unos minutos';
    }
    final dsId = run['defaultDatasetId'];
    try {
      r = await http
          .get(Uri.parse('https://api.apify.com/v2/datasets/$dsId/items'
              '?token=$token&clean=true&format=json'))
          .timeout(const Duration(seconds: 30));
    } catch (_) {
      throw 'no se pudieron descargar las publicaciones';
    }
    if (status != 'SUCCEEDED' && r.bodyBytes.length < 5) {
      throw 'Apify terminó con estado $status${msg.isEmpty ? '' : ': ${_cut(msg, 150)}'}';
    }
    final items = jsonDecode(utf8.decode(r.bodyBytes));
    final posts = items is List
        ? items.where((e) => e is Map && e['url'] != null && e['error'] == null).toList()
        : <dynamic>[];
    if (posts.isEmpty) {
      throw 'sin publicaciones ($status${msg.isEmpty ? '' : ': ${_cut(msg, 150)}'})';
    }
    return posts;
  }

  /// Lee las publicaciones recientes de los bares con Apify y le pasa a
  /// Gemini el texto y las imágenes de los flyers.
  Future<List<Concert>> _instagram(
      String token, List<String> handles, String from, String to) async {
    // 1) Lector económico; 2) si Instagram lo bloquea, el lector oficial
    //    de Apify (más caro, pero con conexiones que bloquean menos).
    List<dynamic> items = const [];
    var note = '';
    try {
      items = await _apifyRun(token, 'themineworks~instagram-post-scraper', {
        'usernames': handles,
        'maxPostsPerProfile': 12,
        'newerThan': '45 days',
        'skipPinned': false,
      });
    } catch (e) {
      note = 'económico: $e';
    }
    if (items.isEmpty) {
      try {
        items = await _apifyRun(token, 'apify~instagram-scraper', {
          'directUrls': [for (final h in handles) 'https://www.instagram.com/$h/'],
          'resultsType': 'posts',
          'resultsLimit': 12,
          'onlyPostsNewerThan': '45 days',
          'addParentData': false,
        });
      } catch (e) {
        throw 'Instagram bloqueó la lectura (oficial: $e; $note)';
      }
    }

    _igStats = '';
    final texts = <String>[];
    final images = <Map<String, dynamic>>[];
    var bytes = 0;
    for (final it in items) {
      if (it is! Map) continue;
      final user = (it['ownerUsername'] ?? it['username'] ?? '').toString();
      final when = (it['timestamp'] ?? '').toString();
      final url = (it['url'] ?? '').toString();
      final cap = _cut((it['caption'] ?? '').toString(), 700);
      texts.add('- [${images.length < 14 ? 'IMAGEN ${images.length + 1}' : 'sin imagen'}] '
          '@$user publicado $when\n  URL: $url\n  $cap');
      final img = (it['displayUrl'] ?? '').toString();
      if (img.isEmpty || images.length >= 14 || bytes > 5000000) continue;
      try {
        final ir = await http.get(Uri.parse(img)).timeout(const Duration(seconds: 15));
        if (ir.statusCode == 200 && ir.bodyBytes.length < 1500000) {
          bytes += ir.bodyBytes.length;
          images.add({
            'inline_data': {
              'mime_type': ir.headers['content-type']?.split(';').first ?? 'image/jpeg',
              'data': base64Encode(ir.bodyBytes),
            }
          });
        }
      } catch (_) {}
    }
    final users = <String>{
      for (final it in items)
        if (it is Map) (it['ownerUsername'] ?? it['username'] ?? '').toString()
    }..remove('');
    final missing = handles.where((h) => !users.contains(h)).toList();
    _igStats = '${items.length} publicaciones de ${users.length} perfiles, '
        '${images.length} flyers leídos'
        '${missing.isEmpty ? '' : '; sin publicaciones: @${missing.join(', @')}'}';
    final prompt =
        'Estas son publicaciones recientes de Instagram de bares ${MusicModeService.general ? 'con música en vivo' : 'de rock'} de '
        'Medellín, con sus flyers como imágenes (IMAGEN 1, 2… en el mismo '
        'orden). Hoy es $from. Extrae SOLO los toques, conciertos o eventos de '
        'música en vivo anunciados entre $from y $to: lee la fecha, la hora, '
        'las bandas y el cover en el texto o en la imagen del flyer. Si el '
        'flyer no dice el año, asume el próximo que corresponda a esa fecha; '
        'si solo dice el día de la semana ("este sábado"), calcúlalo a partir '
        'de la fecha de publicación. '
        'Ignora promociones de comida o tragos sin música en vivo. En '
        '"ciudad" pon Medellín, en "lugar" el nombre del bar, en "tipo" pon '
        '"bar", en "fuente" la '
        'URL de la publicación y en "hora" la hora y el cover si aparecen. '
        'Si no hay ninguno, responde {"conciertos":[]}. Responde solo con '
        'JSON: {"conciertos":[{"banda":"","ciudad":"","lugar":"",'
        '"fecha":"AAAA-MM-DD o vacío","cuando":"","hora":"","boletas":"",'
        '"fuente":"","genero":"","tipo":"bar|escenario|festival"}]}\n\nPublicaciones:\n${texts.join('\n')}';
    final s = AiSettings.instance;
    final gKey = s.geminiKey.trim();
    final errs = <String>[];
    if (gKey.isNotEmpty) {
      for (final model in <String>{s.geminiModel, 'gemini-flash-lite-latest'}) {
        for (var attempt = 0; attempt < 3; attempt++) {
          try {
            return _parse(await _gemini(model, gKey, prompt,
                search: false, extraParts: images));
          } catch (e) {
            if ('$e'.contains('503') && attempt < 2) {
              await Future<void>.delayed(Duration(seconds: 4 * (attempt + 1)));
              continue;
            }
            errs.add('Gemini: $e');
            break;
          }
        }
      }
    }
    // Sin Gemini: Groq solo con el texto de las publicaciones.
    final qKey = s.groqKey.trim();
    if (qKey.isNotEmpty) {
      try {
        return _parse(await _groq(s.groqModel, qKey, _cut(prompt, 14000), json: true));
      } catch (e) {
        errs.add('Groq: $e');
      }
    }
    throw errs.isEmpty ? 'falta clave de Gemini' : errs.join('; ');
  }

  /// Pide a Gemini (o Groq) que convierta resultados de búsqueda en la lista.
  Future<List<Concert>> _organize(String results, String from, String to) async {
    final system =
        'Extrae conciertos ${MusicModeService.general ? 'de música' : 'de rock'} de estos resultados de búsqueda. Hoy es '
        '$from. Usa SOLO la información de los resultados, no inventes nada. '
        'Si no sabes qué banda o artista toca, deja "banda" vacía: nunca '
        'pongas el nombre del lugar como banda. '
        'Incluye conciertos, festivales y toques en bares $_scope, que se hagan '
        'en Colombia entre $from y $to. Fíjate bien en el AÑO: los resultados '
        'pueden traer noticias viejas de la misma banda; descarta solo lo que '
        'ya pasó y conserva el anuncio nuevo. Si un evento está anunciado sin '
        'fecha exacta, deja "fecha" vacía y pon en "cuando" lo que se sepa. '
        'En "fuente" pon la URL del resultado. Si la URL es de una boletería '
        'o de Eventbrite, ponla también en "boletas". Para festivales usa como '
        '"banda" el nombre del festival y entre paréntesis las bandas '
        'principales. En "lugar" pon el escenario o el nombre del bar. En '
        '"tipo" pon "bar" si es en un bar, pub, club o café; "festival" si es '
        'un festival; si no, "escenario". Si no '
        'hay ningún concierto, responde {"conciertos":[]}. Responde solo con '
        'JSON: {"conciertos":[{"banda":"","ciudad":"","lugar":"",'
        '"fecha":"AAAA-MM-DD o vacío","cuando":"","hora":"","boletas":"",'
        '"fuente":"","genero":"$_genreList","tipo":"bar|escenario|festival"}]}';
    final errs = <String>[];
    final s = AiSettings.instance;
    final gKey = s.geminiKey.trim();
    if (gKey.isNotEmpty) {
      for (final model in <String>{
        s.geminiModel,
        'gemini-flash-lite-latest',
        'gemini-2.5-flash',
      }) {
        // 503 = servidores saturados: espera y reintenta hasta 2 veces.
        for (var attempt = 0; attempt < 3; attempt++) {
          try {
            return _parse(await _gemini(
                model, gKey, '$system\n\nResultados de búsqueda:\n$results',
                search: false));
          } catch (e) {
            final busy = '$e'.contains('503') || '$e'.contains('límite');
            if (busy && attempt < 2) {
              await Future<void>.delayed(Duration(seconds: 4 * (attempt + 1)));
              continue;
            }
            errs.add('Gemini ($model): $e');
            break;
          }
        }
      }
    }
    final qKey = s.groqKey.trim();
    if (qKey.isNotEmpty) {
      final short =
          results.length > 14000 ? results.substring(0, 14000) : results;
      for (final model in <String>{s.groqModel, 'openai/gpt-oss-20b'}) {
        for (var attempt = 0; attempt < 2; attempt++) {
          try {
            // Segundo intento sin modo JSON estricto (Groq lo rechaza si
            // el modelo se desvía un poco).
            return _parse(await _groq(
                model, qKey, '$system\n\nResultados de búsqueda:\n$short',
                json: attempt == 0));
          } catch (e) {
            if ('$e'.contains('límite') && attempt == 0) {
              await Future<void>.delayed(const Duration(seconds: 8));
            }
            if (attempt == 1) errs.add('Groq ($model): $e');
          }
        }
      }
    }
    throw errs.isEmpty ? 'falta clave de Gemini o Groq' : errs.join('; ');
  }

  static String _why(int code) {
    if (code == 429) return 'límite alcanzado o búsqueda no incluida en el plan gratis';
    if (code == 401 || code == 403) return 'clave rechazada';
    if (code == 404) return 'modelo no disponible';
    if (code == 400) return 'solicitud rechazada (400)';
    return 'error $code';
  }

  Future<String> _gemini(String model, String key, String prompt,
      {bool search = true,
      List<Map<String, dynamic>> extraParts = const []}) async {
    http.Response r;
    try {
      r = await http
          .post(
            Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/'
                '$model:generateContent'),
            headers: {'x-goog-api-key': key, 'Content-Type': 'application/json'},
            body: jsonEncode({
              'contents': [
                {
                  'role': 'user',
                  'parts': [
                    {'text': prompt},
                    ...extraParts,
                  ],
                }
              ],
              if (search)
                'tools': [
                  {'google_search': {}}
                ],
              'generationConfig': {
                'temperature': 0.2,
                'maxOutputTokens': 16000,
                if (!search) 'responseMimeType': 'application/json',
                if (!search)
                  'thinkingConfig': model.contains('2.5')
                      ? {'thinkingBudget': 0}
                      : {'thinkingLevel': 'low'},
              },
            }),
          )
          .timeout(const Duration(seconds: 90));
    } catch (_) {
      throw 'sin conexión o tardó demasiado';
    }
    if (r.statusCode != 200) throw _why(r.statusCode);
    String reason = '';
    try {
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      final c = j['candidates'][0];
      reason = (c['finishReason'] ?? '').toString();
      final parts = c['content']['parts'] as List;
      final t = parts
          .where((p) => p is Map && p['thought'] != true)
          .map((p) => (p as Map)['text'] ?? '')
          .join('\n');
      if (t.trim().isNotEmpty) return t;
    } catch (_) {}
    throw reason.isEmpty || reason == 'STOP'
        ? 'respuesta vacía'
        : 'respuesta cortada ($reason)';
  }

  /// Groq Compound busca en la web por su cuenta.
  Future<String> _groq(String model, String key, String prompt,
      {bool json = false}) async {
    http.Response r;
    try {
      r = await http
          .post(
            Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
            headers: {
              'Authorization': 'Bearer $key',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': model,
              'temperature': 0.2,
              if (json) 'response_format': {'type': 'json_object'},
              if (model.startsWith('openai/gpt-oss')) 'reasoning_effort': 'low',
              'messages': [
                {'role': 'user', 'content': prompt}
              ],
            }),
          )
          .timeout(const Duration(seconds: 90));
    } catch (_) {
      throw 'sin conexión o tardó demasiado';
    }
    if (r.statusCode != 200) throw _why(r.statusCode);
    try {
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      final t = j['choices'][0]['message']['content'];
      if (t is String && t.trim().isNotEmpty) return t;
    } catch (_) {}
    throw 'respuesta vacía';
  }

  /// Eventos leídos en la última respuesta, antes de quitar los vencidos.
  static int _lastRaw = 0;
  String _igStats = '';

  static List<Concert> _parse(String text) {
    final t = text.trim();
    final obj = t.indexOf('{');
    final arr = t.indexOf('[');
    final useArr = arr >= 0 && (obj < 0 || arr < obj);
    final start = useArr ? arr : obj;
    final end = useArr ? t.lastIndexOf(']') : t.lastIndexOf('}');
    if (start < 0 || end <= start) {
      final peek = t.length > 60 ? '${t.substring(0, 60)}…' : t;
      throw 'respuesta sin datos: "$peek"';
    }
    try {
      final j = jsonDecode(t.substring(start, end + 1));
      List raw = const [];
      if (j is List) {
        raw = j;
      } else if (j is Map) {
        final v = j['conciertos'] ?? j['concerts'] ??
            j.values.firstWhere((e) => e is List, orElse: () => null);
        if (v is List) raw = v;
      }
      final all = <Concert>[
        for (final e in raw)
          if (Concert.fromJson(e) != null) Concert.fromJson(e)!,
      ];
      _lastRaw = all.length;
      return _upcoming(all);
    } catch (_) {
      throw 'respuesta incompleta';
    }
  }
}

/// "hace 2 días", "justo ahora"…
String concertsUpdatedLabel(DateTime? at) {
  if (at == null) return 'Aún no se ha buscado';
  final d = DateTime.now().difference(at);
  if (d.inMinutes < 2) return 'Actualizado justo ahora';
  if (d.inHours < 1) return 'Actualizado hace ${d.inMinutes} min';
  if (d.inDays < 1) {
    return 'Actualizado hace ${d.inHours} ${d.inHours == 1 ? 'hora' : 'horas'}';
  }
  return 'Actualizado hace ${d.inDays} ${d.inDays == 1 ? 'día' : 'días'}';
}
