import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/music_mode.dart';
import '../theme/app_theme.dart';

/// Púa de guitarra con rayo: logo de RockPlay.
class PickLogo extends StatelessWidget {
  final double size;
  const PickLogo({super.key, this.size = 46});

  @override
  Widget build(BuildContext context) => CustomPaint(
      size: Size.square(size),
      painter: MusicModeService.general ? _PulsePainter() : _PickPainter());
}

/// Logo de Pulso (se dibuja igual en cualquier modo).
class PulseLogo extends StatelessWidget {
  final double size;
  const PulseLogo({super.key, this.size = 36});
  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _PulsePainter());
}

/// Logo de Pulso: cuadro redondeado violeta→cian con una línea de pulso.
class _PulsePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final r = RRect.fromRectAndRadius(
        Offset.zero & s, Radius.circular(w * 0.30));
    canvas.drawRRect(
        r,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF6A4CF0), Color(0xFF2EC5D3)],
          ).createShader(Offset.zero & s));
    final line = Path()
      ..moveTo(w * 0.14, h * 0.52)
      ..lineTo(w * 0.30, h * 0.52)
      ..lineTo(w * 0.40, h * 0.26)
      ..lineTo(w * 0.56, h * 0.80)
      ..lineTo(w * 0.66, h * 0.52)
      ..lineTo(w * 0.86, h * 0.52);
    canvas.drawPath(
        line,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.085
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _PickPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final path = Path()
      ..moveTo(w * 0.16, h * 0.14)
      ..quadraticBezierTo(w * 0.50, h * 0.04, w * 0.84, h * 0.14)
      ..quadraticBezierTo(w * 0.96, h * 0.20, w * 0.88, h * 0.40)
      ..quadraticBezierTo(w * 0.74, h * 0.80, w * 0.54, h * 0.95)
      ..quadraticBezierTo(w * 0.50, h * 0.98, w * 0.46, h * 0.95)
      ..quadraticBezierTo(w * 0.26, h * 0.80, w * 0.12, h * 0.40)
      ..quadraticBezierTo(w * 0.04, h * 0.20, w * 0.16, h * 0.14)
      ..close();
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [AppColors.red, AppColors.amber],
      ).createShader(Offset.zero & s);
    canvas.drawPath(path, paint);
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.025
          ..color = const Color.fromRGBO(255, 226, 170, 0.6));
    final bolt = Path()
      ..moveTo(w * 0.56, h * 0.20)
      ..lineTo(w * 0.34, h * 0.52)
      ..lineTo(w * 0.48, h * 0.52)
      ..lineTo(w * 0.42, h * 0.78)
      ..lineTo(w * 0.66, h * 0.44)
      ..lineTo(w * 0.52, h * 0.44)
      ..close();
    canvas.drawPath(bolt, Paint()..color = const Color(0xFF0E0C10));
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// Patrón de púas pequeñas (decoración de tarjetas).
class PickPatternPainter extends CustomPainter {
  final Color color;
  const PickPatternPainter(this.color);

  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()..color = color;
    const step = 34.0;
    var row = 0;
    for (double y = -8; y < s.height + step; y += step) {
      final off = (row % 2) * (step / 2);
      for (double x = -8 + off; x < s.width + step; x += step) {
        final t = Path()
          ..moveTo(x - 5, y - 5)
          ..lineTo(x + 5, y - 5)
          ..lineTo(x, y + 7)
          ..close();
        canvas.drawPath(t, p);
      }
      row++;
    }
  }

  @override
  bool shouldRepaint(covariant PickPatternPainter old) => old.color != color;
}

/// Ondas de sonido (decoración de banners).
class WavesPainter extends CustomPainter {
  final Color color;
  const WavesPainter(this.color);

  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()..color = color;
    const bw = 5.0, gap = 5.0;
    final n = (s.width / (bw + gap)).floor();
    for (var i = 0; i < n; i++) {
      final f = (math.sin(i * 0.55) + math.sin(i * 0.23 + 1.3) + 2) / 4;
      final bh = s.height * (0.15 + 0.7 * f);
      final x = i * (bw + gap);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(x, (s.height - bh) / 2, bw, bh),
            const Radius.circular(AppRadius.xs)),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(covariant WavesPainter old) => old.color != color;
}
