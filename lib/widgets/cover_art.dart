import '../services/deezer_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';

import '../models/song.dart';
import '../services/data_saver.dart';
import '../services/music_mode.dart';
import '../services/track_info_service.dart';
import '../theme/app_theme.dart';

/// Portada con esquinas redondeadas y placeholder elegante.
/// Debe recibir tamaño ([size]) o restricciones ajustadas del padre.
class CoverArt extends StatelessWidget {
  final String url;
  final double? size;
  final double radius;
  final bool shadow;

  /// Texto (artista o título) para dar identidad al placeholder.
  final String? seed;

  const CoverArt({
    super.key,
    required this.url,
    this.size,
    this.radius = 10,
    this.shadow = false,
    this.seed,
  });

  static List<List<Color>> get _tones =>
      MusicModeService.general ? _tonesPulso : _tonesRock;

  static const List<List<Color>> _tonesPulso = [
    [Color(0xFF3A2C8C), Color(0xFF15142A)],
    [Color(0xFF233E7A), Color(0xFF111628)],
    [Color(0xFF14505A), Color(0xFF0E1A20)],
    [Color(0xFF4A2A6E), Color(0xFF16122A)],
    [Color(0xFF2A2A3A), Color(0xFF111118)],
  ];

  static const List<List<Color>> _tonesRock = [
    [Color(0xFF6B1A16), Color(0xFF17171E)],
    [Color(0xFF7A2A22), Color(0xFF1A1114)],
    [Color(0xFF5A3A12), Color(0xFF17171E)],
    [Color(0xFF3A1A24), Color(0xFF14141A)],
    [Color(0xFF2A2A33), Color(0xFF111116)],
  ];

  Widget _placeholder() {
    final s = (seed ?? '').trim();
    var h = 0;
    for (final c in s.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    final tone = _tones[h % _tones.length];
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: tone,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          final side = box.maxWidth.isFinite && box.maxHeight.isFinite
              ? (box.maxWidth < box.maxHeight ? box.maxWidth : box.maxHeight)
              : 48.0;
          if (s.isEmpty) {
            return Center(
              child: Icon(
                Icons.music_note_rounded,
                size: side * 0.42,
                color: MusicModeService.general
                    ? AppColors.text.withValues(alpha: 0.6)
                    : AppColors.amber.withValues(alpha: 0.65),
              ),
            );
          }
          return Center(
            child: Text(
              s.substring(0, 1).toUpperCase(),
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontFamily: AppType.head,
                fontWeight: FontWeight.w700,
                fontVariations: const [FontVariation('wght', 700)],
                fontSize: side * 0.5,
                height: 1.0,
                color: MusicModeService.general
                    ? AppColors.text.withValues(alpha: 0.6)
                    : AppColors.amber.withValues(alpha: 0.7),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget image = url.isEmpty
        ? _placeholder()
        : _CoverImage(url: url, placeholder: _placeholder(), size: size);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        color: AppColors.surfaceHigh,
        boxShadow: shadow ? AppShadow.card : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: image,
      ),
    );
  }
}

/// Imagen con caché en disco (ver DataSaver).
class _CoverImage extends StatefulWidget {
  final String url;
  final Widget placeholder;
  final double? size;
  const _CoverImage({required this.url, required this.placeholder, this.size});

  @override
  State<_CoverImage> createState() => _CoverImageState();
}

class _CoverImageState extends State<_CoverImage> {
  late Future<ImageProvider?> _f;
  /// Última imagen mostrada: se mantiene mientras carga la nueva (sin
  /// parpadeo al llegar una carátula mejor).
  ImageProvider? _last;

  @override
  void initState() {
    super.initState();
    _f = DataSaver.instance.image(widget.url);
  }

  @override
  void didUpdateWidget(covariant _CoverImage old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      _f = DataSaver.instance.image(widget.url);
    }
  }

  /// Decodifica al tamaño en que se muestra (no 600×600 para 44 dp).
  ImageProvider _sized(ImageProvider p) {
    final s = widget.size;
    if (s == null || s <= 0) return p;
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 3;
    return ResizeImage.resizeIfNeeded((s * dpr).round(), null, p);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ImageProvider?>(
      future: _f,
      builder: (context, snap) {
        final p = snap.data != null ? _sized(snap.data!) : _last;
        if (p == null) return widget.placeholder;
        if (snap.data != null) _last = p;
        return Image(
          image: p,
          width: double.infinity,
          height: double.infinity,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (context, error, stack) => widget.placeholder,
        );
      },
    );
  }
}


/// Carátula de una canción resuelta como en el reproductor: la de
/// TrackInfoService (Deezer/iTunes) si la canción no trae una buena
/// (vacía o un fotograma de YouTube); si no, la que trae.
class SongArtwork {
  SongArtwork._();
  // Caché en disco (sobrevive al cierre): clave → [url, ms]. «''» = sin
  // resultado (se reintenta a los 7 días).
  static final Map<String, List<dynamic>> _cache = {};
  static final Map<String, Future<String>> _pending = {};
  static bool _loaded = false;
  static Future<void>? _loading;
  static Timer? _saveT;
  static int _running = 0;
  static final List<Completer<void>> _wait = [];
  static const String _prefKey = 'art_cache_v2';

  /// Miniatura de YouTube o de un canal de letras: no es la carátula real.
  static bool _weak(String url) =>
      url.isEmpty || url.contains('ytimg.com') || url.contains('youtube.com') ||
      url.contains('ggpht.com') || url.contains('googleusercontent.com');

  /// ¿[url] es una carátula real (no una miniatura de video)?
  static bool isReal(String url) => !_weak(url);

  static String _key(Song s) => '${s.artist}|${s.title}'.toLowerCase();

  /// Carga la caché al arrancar (así el mini player ya tiene su carátula).
  static Future<void> warm() => _load();

  static Future<void> _load() => _loading ??= () async {
        try {
          final sp = await SharedPreferences.getInstance();
          final raw = sp.getString(_prefKey);
          if (raw != null) {
            (jsonDecode(raw) as Map).forEach((k, v) {
              if (v is List && v.length == 2) _cache['$k'] = v;
            });
          }
        } catch (_) {}
        _loaded = true;
      }();

  static void _save() {
    _saveT?.cancel();
    _saveT = Timer(const Duration(seconds: 3), () async {
      try {
        // Las 1.500 más recientes.
        if (_cache.length > 1500) {
          final ks = _cache.keys.toList()
            ..sort((a, b) =>
                (_cache[a]![1] as num).compareTo(_cache[b]![1] as num));
          for (final k in ks.take(_cache.length - 1500)) {
            _cache.remove(k);
          }
        }
        final sp = await SharedPreferences.getInstance();
        await sp.setString(_prefKey, jsonEncode(_cache));
      } catch (_) {}
    });
  }

  static String _fallback(Song s) => s.image.isNotEmpty
      ? s.image
      : (s.videoId.isNotEmpty
          ? 'https://i.ytimg.com/vi/${s.videoId}/mqdefault.jpg'
          : '');

  static String? _hit(Song s) {
    final e = _cache[_key(s)];
    if (e == null) return null;
    final url = '${e[0]}';
    final age = DateTime.now().millisecondsSinceEpoch - (e[1] as num);
    // Error de red o límite de iTunes: se reintenta en 1 hora.
    if (url == 'ERR') {
      return age > const Duration(hours: 1).inMilliseconds ? null : _fallback(s);
    }
    if (url.isEmpty && age > const Duration(days: 7).inMilliseconds) {
      return null; // «sin resultado» vencido: reintentar
    }
    return url.isEmpty ? _fallback(s) : url;
  }

  /// La mejor conocida ya, sin esperar.
  static String peek(Song s) {
    if (s.isRadio || !_weak(s.image)) return s.image;
    return (_loaded ? _hit(s) : null) ?? _fallback(s);
  }

  /// Máximo 2 búsquedas a la vez (iTunes limita las peticiones).
  static Future<T> _limited<T>(Future<T> Function() f) async {
    while (_running >= 2) {
      final c = Completer<void>();
      _wait.add(c);
      await c.future;
    }
    _running++;
    try {
      return await f();
    } finally {
      _running--;
      if (_wait.isNotEmpty) _wait.removeAt(0).complete();
    }
  }

  static Future<String> of(Song s) async {
    if (s.isRadio || !_weak(s.image)) return s.image;
    await _load();
    final hit = _hit(s);
    if (hit != null) return hit;
    final k = _key(s);
    return _pending[k] ??= _limited(() async {
      var u = '';
      var failed = false;
      // Deezer primero (límite más alto) y, si no lo tiene, iTunes.
      try {
        // Solo si el artista y el título coinciden (no el primer resultado).
        u = (await DeezerService().coverForTrack(s.artist, s.title))
            .replaceAll('250x250', '500x500');
      } catch (_) {
        failed = true;
      }
      if (u.isEmpty) {
        try {
          final i = await TrackInfoService.instance
              .fetch(s.artist, s.title, throwOnError: true);
          u = i?.artwork ?? '';
        } catch (_) {
          failed = true;
        }
      }
      _cache[k] = [u.isEmpty && failed ? 'ERR' : u, DateTime.now().millisecondsSinceEpoch];
      if (u.isEmpty && failed) {
        _save();
        return _fallback(s);
      }
      _save();
      return u.isEmpty ? _fallback(s) : u;
    }).whenComplete(() => _pending.remove(k));
  }
}

/// [CoverArt] para una canción, con la carátula de [SongArtwork].
class SongCover extends StatelessWidget {
  const SongCover(this.song,
      {super.key, this.size, this.radius = 10, this.shadow = false});
  final Song song;
  final double? size;
  final double radius;
  final bool shadow;

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
        key: ValueKey('${song.artist}|${song.title}|${song.image}'),
        future: SongArtwork.of(song),
        initialData: SongArtwork.peek(song),
        builder: (context, snap) => CoverArt(
            url: snap.data ?? song.image,
            size: size,
            radius: radius,
            shadow: shadow,
            seed: song.artist),
      );
}
