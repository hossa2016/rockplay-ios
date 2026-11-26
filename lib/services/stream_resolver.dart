import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// URL de audio lista para reproducir con just_audio.
class ResolvedStream {
  final Uri uri;
  final Map<String, String> headers;
  final DateTime expiresAt;

  /// Etiqueta de origen, p. ej. "yt:androidVr:audio-mp4" o "inv:inv.nadeko.net".
  final String source;

  ResolvedStream({
    required this.uri,
    required this.headers,
    required this.expiresAt,
    required this.source,
  });

  bool get expired => DateTime.now().isAfter(expiresAt);
}

class StreamResolveException implements Exception {
  final String message;
  StreamResolveException(this.message);
  @override
  String toString() => message;
}

class _Candidate {
  final Uri uri;
  final String label;
  final Map<String, String> headers;
  _Candidate(this.uri, this.label, [this.headers = const {}]);
}

/// Convierte un videoId de YouTube en una URL de audio directa.
///
/// Cadena: (1) youtube_explode_dart con varios clientes de API, probando cada
/// URL con una petición Range antes de usarla (así se detectan los 403 por
/// PO token); (2) instancias Invidious / Piped configurables; (3) excepción
/// con mensaje legible.
class StreamResolver {
  StreamResolver._();
  static final StreamResolver instance = StreamResolver._();

  /// Instancias de respaldo editables en tiempo de ejecución.
  /// Invidious: se usa /api/v1/videos/ID?local=true (el proxy evita que la URL
  /// quede atada a la IP de la instancia).
  static final List<String> invidiousInstances = <String>[
    'https://inv.nadeko.net',
    'https://invidious.nerdvpn.de',
    'https://yewtu.be',
    'https://invidious.privacyredirect.com',
    'https://iv.ggtyler.dev',
    'https://invidious.jing.rocks',
    'https://yt.chocolatemoo53.com',
    'https://invidious.tiekoetter.com',
  ];

  /// Piped: se usa /streams/ID (URL base de la API, no del frontend).
  static final List<String> pipedInstances = <String>[
    'https://pipedapi.kavin.rocks',
    'https://pipedapi.adminforge.de',
    'https://api.piped.private.coffee',
    'https://pipedapi.leptons.xyz',
  ];

  /// Diagnóstico: recibe el progreso de la resolución.
  static void Function(String)? onProgress;

  static const Duration _ttl = Duration(hours: 5);
  static const Duration _margin = Duration(minutes: 10);
  static const Duration _deadline = Duration(seconds: 25);

  final YoutubeExplode _yt = YoutubeExplode();
  final http.Client _http = http.Client();
  final Map<String, ResolvedStream> _cache = <String, ResolvedStream>{};
  final Map<String, Future<ResolvedStream>> _inflight =
      <String, Future<ResolvedStream>>{};

  // User-Agent que acompaña a cada cliente (las URL de googlevideo a veces
  // validan que coincida). Valores aproximados; si cambian, el probe fallará y
  // se pasa al siguiente cliente.
  static const String _uaAndroid =
      'com.google.android.youtube/19.44.38 (Linux; U; Android 11) gzip';
  static const String _uaAndroidVr =
      'com.google.android.apps.youtube.vr.oculus/1.60.19 '
      '(Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip';
  static const String _uaIos =
      'com.google.ios.youtube/19.45.4 (iPhone16,2; U; CPU iOS 18_1_0 like Mac OS X;)';
  static const String _uaBrowser =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/124.0 Mobile Safari/537.36';

  void invalidate(String videoId) => _cache.remove(videoId);

  void clear() => _cache.clear();

  /// [force] ignora la caché. [exclude] descarta fuentes cuyo label empiece por
  /// alguno de esos prefijos (útil tras un fallo real en el reproductor).
  Future<ResolvedStream> resolve(
    String videoId, {
    bool force = false,
    Set<String> exclude = const <String>{},
  }) {
    if (!force && exclude.isEmpty) {
      final c = _cache[videoId];
      if (c != null && !c.expired) return Future.value(c);
    }
    final key = '$videoId|${exclude.join(",")}|$force';
    final running = _inflight[key];
    if (running != null) return running;
    final errs = <String>[];
    final f = _resolve(videoId, exclude, errs)
        .timeout(const Duration(seconds: 60),
            onTimeout: () => throw StreamResolveException(
                'Tiempo agotado: ${errs.join(" | ")}'))
        .then((r) {
      _cache[videoId] = r;
      return r;
    }).whenComplete(() => _inflight.remove(key));
    _inflight[key] = f;
    return f;
  }

  Future<ResolvedStream> _resolve(String id, Set<String> exclude, List<String> errors) async {
    final sw = Stopwatch()..start();
    void note(String m) {
      errors.add(m);
      onProgress?.call(errors.join(' | '));
    }
    bool skip(String label) => exclude.any(label.startsWith);

    // (1) youtube_explode_dart, un cliente a la vez.
    final clients = <(String, YoutubeApiClient, String?)>[
      ('androidVr', YoutubeApiClient.androidVr, _uaAndroidVr),
      ('ios', YoutubeApiClient.ios, _uaIos),
      ('tv', YoutubeApiClient.tv, null),
      ('safari', YoutubeApiClient.safari, null),
    ];
    var botBlocked = false;
    for (final (name, client, ua) in clients) {
      if (botBlocked || sw.elapsed > _deadline) break;
      if (skip('yt:$name')) continue;
      try {
        note('->$name');
        final cands = await _ytCandidates(id, name, client, ua);
        final ok = await _firstWorking(cands, exclude, maxProbes: 2);
        if (ok != null) return ok;
        note('yt:$name sin URL válida');
      } catch (e) {
        if ('$e'.contains('not a bot')) botBlocked = true;
        note('yt:$name ${_short(e)}');
      }
    }

    // (2) Instancias alternativas, todas a la vez: gana la primera válida.
    final futures = <Future<ResolvedStream?>>[];
    for (final base in List<String>.of(invidiousInstances)) {
      final host = Uri.tryParse(base)?.host ?? base;
      if (skip('inv:$host')) continue;
      futures.add(() async {
        try {
          final cands = await _invidiousCandidates(base, id);
          final r = await _firstWorking(cands, exclude, maxProbes: 2);
          if (r == null) note('inv:$host sin URL válida');
          return r;
        } catch (e) {
          note('inv:$host ${_short(e)}');
          return null;
        }
      }());
    }
    for (final base in List<String>.of(pipedInstances)) {
      final host = Uri.tryParse(base)?.host ?? base;
      if (skip('piped:$host')) continue;
      futures.add(() async {
        try {
          final cands = await _pipedCandidates(base, id);
          final r = await _firstWorking(cands, exclude, maxProbes: 2);
          if (r == null) note('piped:$host sin URL válida');
          return r;
        } catch (e) {
          note('piped:$host ${_short(e)}');
          return null;
        }
      }());
    }
    note('probando ${futures.length} instancias');
    final winner = await _firstNonNull(futures);
    if (winner != null) return winner;

    // (3) Error legible.
    // ignore: avoid_print
    print('StreamResolver($id) falló: ${errors.join(" | ")}');
    throw StreamResolveException(
        'Fallaron todas las fuentes: ${errors.join(" | ")}');
  }

  // ---------------------------------------------------------------- YouTube

  Future<List<_Candidate>> _ytCandidates(
    String id,
    String name,
    YoutubeApiClient client,
    String? ua,
  ) async {
    final manifest = await _yt.videos.streams
        .getManifest(id, ytClients: [client])
        .timeout(const Duration(seconds: 8));
    final headers = <String, String>{if (ua != null) 'User-Agent': ua};

    final audio = manifest.audioOnly.toList()
      ..sort((a, b) =>
          b.bitrate.bitsPerSecond.compareTo(a.bitrate.bitsPerSecond));
    final mp4 = audio.where((s) => s.container.name == 'mp4').toList();
    final other = audio.where((s) => s.container.name != 'mp4').toList();
    final muxed = manifest.muxed.toList()
      ..sort((a, b) =>
          a.bitrate.bitsPerSecond.compareTo(b.bitrate.bitsPerSecond));

    return <_Candidate>[
      if (mp4.isNotEmpty)
        _Candidate(mp4.first.url, 'yt:$name:audio-mp4', headers),
      if (other.isNotEmpty)
        _Candidate(other.first.url, 'yt:$name:audio-webm', headers),
      // El stream muxed (360p con audio) suele seguir funcionando cuando los
      // adaptativos devuelven 403 por falta de PO token.
      if (muxed.isNotEmpty)
        _Candidate(muxed.first.url, 'yt:$name:muxed', headers),
    ];
  }

  // -------------------------------------------------------------- Invidious

  Future<List<_Candidate>> _invidiousCandidates(String base, String id) async {
    final root = base.replaceAll(RegExp(r'/+$'), '');
    final host = Uri.parse(root).host;
    final uri = Uri.parse(
        '$root/api/v1/videos/$id?local=true&fields=adaptiveFormats,formatStreams');
    final r = await _http
        .get(uri, headers: {'User-Agent': _uaBrowser})
        .timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) throw 'HTTP ${r.statusCode}';
    final j = jsonDecode(utf8.decode(r.bodyBytes));
    if (j is! Map) throw 'respuesta inesperada';

    Uri? abs(dynamic u) {
      if (u is! String || u.isEmpty) return null;
      return u.startsWith('/') ? Uri.parse('$root$u') : Uri.tryParse(u);
    }

    final out = <_Candidate>[];
    final adaptive = <Map>[
      for (final f in (j['adaptiveFormats'] as List? ?? const []))
        if (f is Map && '${f['type']}'.startsWith('audio/')) f
    ]..sort((a, b) => _int(b['bitrate']).compareTo(_int(a['bitrate'])));
    adaptive.sort((a, b) =>
        ('${b['type']}'.contains('mp4') ? 1 : 0) -
        ('${a['type']}'.contains('mp4') ? 1 : 0));
    for (final f in adaptive.take(2)) {
      final u = abs(f['url']);
      if (u != null) out.add(_Candidate(u, 'inv:$host:audio'));
    }
    for (final f in (j['formatStreams'] as List? ?? const [])) {
      final u = f is Map ? abs(f['url']) : null;
      if (u != null) {
        out.add(_Candidate(u, 'inv:$host:muxed'));
        break;
      }
    }
    return out;
  }

  // ------------------------------------------------------------------ Piped

  Future<List<_Candidate>> _pipedCandidates(String base, String id) async {
    final root = base.replaceAll(RegExp(r'/+$'), '');
    final host = Uri.parse(root).host;
    final r = await _http
        .get(Uri.parse('$root/streams/$id'), headers: {'User-Agent': _uaBrowser})
        .timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) throw 'HTTP ${r.statusCode}';
    final j = jsonDecode(utf8.decode(r.bodyBytes));
    if (j is! Map) throw 'respuesta inesperada';
    final audio = <Map>[
      for (final f in (j['audioStreams'] as List? ?? const []))
        if (f is Map && f['url'] is String) f
    ]..sort((a, b) => _int(b['bitrate']).compareTo(_int(a['bitrate'])));
    audio.sort((a, b) =>
        ('${b['mimeType']}'.contains('mp4') ? 1 : 0) -
        ('${a['mimeType']}'.contains('mp4') ? 1 : 0));
    return <_Candidate>[
      for (final f in audio.take(2))
        if (Uri.tryParse(f['url'] as String) != null)
          _Candidate(Uri.parse(f['url'] as String), 'piped:$host:audio'),
    ];
  }

  // ---------------------------------------------------------------- Helpers

  static String _short(Object e) {
    final t = '$e'.replaceAll(RegExp(r'\s+'), ' ');
    return t.length > 70 ? t.substring(0, 70) : t;
  }

  Future<ResolvedStream?> _firstNonNull(List<Future<ResolvedStream?>> fs) {
    final c = Completer<ResolvedStream?>();
    var left = fs.length;
    if (left == 0) {
      c.complete(null);
      return c.future;
    }
    for (final f in fs) {
      f.then((v) {
        if (v != null && !c.isCompleted) c.complete(v);
      }).whenComplete(() {
        left--;
        if (left == 0 && !c.isCompleted) c.complete(null);
      });
    }
    return c.future;
  }

  static int _int(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

  Future<ResolvedStream?> _firstWorking(
    List<_Candidate> cands,
    Set<String> exclude, {
    required int maxProbes,
  }) async {
    var probes = 0;
    for (final c in cands) {
      if (exclude.any(c.label.startsWith)) continue;
      if (probes >= maxProbes) break;
      probes++;
      if (await _probe(c.uri, c.headers)) {
        return ResolvedStream(
          uri: c.uri,
          headers: c.headers,
          expiresAt: _expiry(c.uri),
          source: c.label,
        );
      }
    }
    return null;
  }

  /// Petición Range de 2 bytes: 200/206 = la URL es utilizable.
  Future<bool> _probe(Uri uri, Map<String, String> headers) async {
    try {
      final req = http.Request('GET', uri)
        ..headers.addAll(headers)
        ..headers['Range'] = 'bytes=0-1';
      final resp = await _http.send(req).timeout(const Duration(seconds: 7));
      final ok = resp.statusCode == 200 || resp.statusCode == 206;
      // No descargar el cuerpo completo si el servidor ignora Range.
      unawaited(resp.stream.listen((_) {}, onError: (_) {}).cancel());
      return ok;
    } catch (_) {
      return false;
    }
  }

  DateTime _expiry(Uri uri) {
    final now = DateTime.now();
    final e = int.tryParse(uri.queryParameters['expire'] ?? '');
    if (e != null) {
      final t = DateTime.fromMillisecondsSinceEpoch(e * 1000);
      final capped = now.add(_ttl);
      final chosen = t.isBefore(capped) ? t : capped;
      return chosen.subtract(_margin);
    }
    return now.add(_ttl).subtract(_margin);
  }
}
