import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;

/// Color dominante (oscurecido) de una portada, calculado una vez y guardado.
class CoverColor {
  static final Map<String, Color?> _cache = <String, Color?>{};
  static final Map<String, Future<Color?>> _pending = <String, Future<Color?>>{};

  static Color? peek(String url) => _cache[url];

  static Future<Color?> of(String url) {
    if (url.isEmpty) return Future<Color?>.value(null);
    if (_cache.containsKey(url)) return Future<Color?>.value(_cache[url]);
    return _pending[url] ??= _compute(url).then((c) {
      _cache[url] = c;
      _pending.remove(url);
      return c;
    });
  }

  static Future<Color?> _compute(String url) async {
    try {
      final r = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 8));
      if (r.statusCode != 200 || r.bodyBytes.isEmpty) return null;
      final codec =
          await ui.instantiateImageCodec(r.bodyBytes, targetWidth: 16);
      final frame = await codec.getNextFrame();
      final data =
          await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return null;
      final Uint8List px = data.buffer.asUint8List();
      double rs = 0, gs = 0, bs = 0, ws = 0;
      for (var i = 0; i + 3 < px.length; i += 4) {
        final r0 = px[i] / 255, g0 = px[i + 1] / 255, b0 = px[i + 2] / 255;
        final mx = [r0, g0, b0].reduce((a, b) => a > b ? a : b);
        final mn = [r0, g0, b0].reduce((a, b) => a < b ? a : b);
        final sat = mx == 0 ? 0.0 : (mx - mn) / mx;
        final w = 0.1 + sat * sat * mx; // favorece colores vivos
        rs += r0 * w;
        gs += g0 * w;
        bs += b0 * w;
        ws += w;
      }
      if (ws == 0) return null;
      final c = Color.fromARGB(
          255, (rs / ws * 255).round(), (gs / ws * 255).round(), (bs / ws * 255).round());
      final hsl = HSLColor.fromColor(c);
      return hsl
          // Sin mínimo: una portada gris debe seguir siendo gris (así el
          // reproductor usa el color de marca y no un azul inventado).
          .withSaturation(hsl.saturation.clamp(0.0, 0.85))
          .withLightness(0.22)
          .toColor();
    } catch (_) {
      return null;
    }
  }
}
