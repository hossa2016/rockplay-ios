import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../services/music_mode.dart';
import '../services/stats_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_button.dart';
import '../widgets/section_header.dart';

const List<String> kMonthNames = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto',
  'septiembre', 'octubre', 'noviembre', 'diciembre',
];

/// Resumen del mes anterior (o del actual si se pide).
class MonthSummary {
  final String month;
  final int plays;
  final List<CountItem> artists;
  final List<CountItem> songs;
  final int hours;
  const MonthSummary(this.month, this.plays, this.artists, this.songs, this.hours);

  static Future<MonthSummary?> previous() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month - 1, 1);
    final end = DateTime(now.year, now.month, 1);
    final all = await StatsService.instance.plays();
    final l = [
      for (final p in all)
        if (p.ts >= start.millisecondsSinceEpoch ~/ 1000 &&
            p.ts < end.millisecondsSinceEpoch ~/ 1000)
          p
    ];
    if (l.length < 10) return null;
    return MonthSummary(kMonthNames[start.month - 1], l.length,
        StatsService.topArtists(l, n: 5), StatsService.topSongs(l, n: 3),
        (l.length * 3.5 / 60).round());
  }
}

/// «Tu mes en rock»: tarjeta vertical para compartir (como el Wrapped, pero
/// cada mes).
class MonthCardScreen extends StatefulWidget {
  final MonthSummary summary;
  const MonthCardScreen({super.key, required this.summary});

  @override
  State<MonthCardScreen> createState() => _MonthCardScreenState();
}

class _MonthCardScreenState extends State<MonthCardScreen> {
  final GlobalKey _key = GlobalKey();
  bool _busy = false;

  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      final b = _key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      // 1080 px de ancho.
      final img = await b.toImage(pixelRatio: 1080 / b.size.width);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/tu_mes_${widget.summary.month}.png');
      await f.writeAsBytes(data!.buffer.asUint8List());
      await Share.shareXFiles([XFile(f.path, mimeType: 'image/png')]);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No se pudo crear la imagen.')));
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.summary;
    final g = MusicModeService.general;
    final colors = g
        ? const [Color(0xFF6A4CF0), Color(0xFF2EC5D3), Color(0xFF0E0E16)]
        : const [Color(0xFFC0392B), Color(0xFFE8A33D), Color(0xFF0E0E10)];
    return Scaffold(
      appBar: AppBar(title: AppTitle('Tu mes')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        children: [
          RepaintBoundary(
            key: _key,
            // Imagen sin esquinas transparentes y con letra fija (no se
            // desborda con la letra grande del teléfono).
            child: MediaQuery.withNoTextScaling(child: AspectRatio(
              aspectRatio: 9 / 16,
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: colors,
                    stops: const [0, 0.45, 1],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(g ? 'Tu ${s.month} en Pulso' : 'TU ${s.month.toUpperCase()} EN ROCK',
                        style: g
                            ? const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)
                            : AppType.oswald(26)),
                    const Spacer(),
                    Text('${s.plays}',
                        style: AppType.oswald(72, height: 1)),
                    Text('escuchas · unas ${s.hours} horas',
                        style: const TextStyle(color: Colors.white70, fontSize: 15)),
                    const SizedBox(height: 22),
                    Text(g ? 'Tus artistas' : 'TUS BANDAS',
                        style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            letterSpacing: 1.5,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    for (var i = 0; i < s.artists.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text('${i + 1}. ${s.artists[i].name}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: i == 0 ? 22 : 16,
                                fontWeight: i == 0 ? FontWeight.w900 : FontWeight.w600)),
                      ),
                    if (s.songs.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(g ? 'Tu canción' : 'TU CANCIÓN',
                          style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              letterSpacing: 1.5,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(s.songs.first.name.replaceFirst('|', ' · '),
                          maxLines: 2,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                    ],
                    const Spacer(),
                    Text(g ? 'Pulso' : 'ROCKPLAY IA',
                        style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                            letterSpacing: 2,
                            fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            )),
          ),
          const SizedBox(height: 18),
          AppButton.primary(
            label: _busy ? 'Creando…' : 'Compartir',
            icon: Icons.share_rounded,
            onPressed: _busy ? null : _share,
          ),
        ],
      ),
    );
  }
}
