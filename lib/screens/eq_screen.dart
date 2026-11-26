import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/eq_service.dart';
import '../theme/app_theme.dart';
import '../widgets/section_header.dart';
import '../widgets/app_button.dart';

/// Ecualizador de 10 bandas con preajustes de rock y sugerencia del asistente.
class EqScreen extends StatefulWidget {
  const EqScreen({super.key});

  @override
  State<EqScreen> createState() => _EqScreenState();
}

class _EqScreenState extends State<EqScreen> {
  final EqService eq = EqService.instance;

  static Color get rockRed => AppColors.redBtn;

  @override
  void initState() {
    super.initState();
    eq.addListener(_up);
    // Sin sugerencia, o una que no es de este modo: se pide de nuevo.
    final sg = eq.suggestion;
    if ((sg == null || !EqService.visible.contains(sg.preset)) && !eq.suggesting) {
      eq.suggestCurrent();
    }
  }

  @override
  void dispose() {
    eq.removeListener(_up);
    super.dispose();
  }

  void _up() {
    if (mounted) setState(() {});
  }

  String get _statusText {
    switch (eq.embedStatus) {
      case 'activo':
        return 'Activo en las canciones de YouTube y en la radio';
      case 'apagado':
        return 'Ecualizador apagado';
      case 'esperando':
      case 'sin-video':
      case 'sin-reproductor':
      case '':
        return 'Se aplica cuando empiece a sonar una canción';
      case 'bloqueado':
      case 'sin-webaudio':
        return 'En las canciones de YouTube este celular no lo permite; en la radio sí funciona';
      default:
        return eq.embedStatus.startsWith('error')
            ? 'No se pudo aplicar en YouTube (${eq.embedStatus.substring(6).trim()})'
            : eq.embedStatus;
    }
  }

  @override
  Widget build(BuildContext context) {
    final on = eq.enabled;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: AppTitle('Ecualizador')),
      // Interruptor abajo, al alcance del pulgar.
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Material(
            color: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              side: BorderSide(color: on ? rockRed : AppColors.outline),
            ),
            clipBehavior: Clip.antiAlias,
            child: SwitchListTile(
              title: Text(on ? 'Ecualizador encendido' : 'Ecualizador apagado',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              value: on,
              activeColor: Colors.white,
              activeTrackColor: rockRed,
              onChanged: (v) {
                HapticFeedback.mediumImpact();
                eq.setEnabled(v);
              },
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          _suggestionCard(),
          const SizedBox(height: 8),
          // Un preajuste por audífono o salida.
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            secondary: const Icon(Icons.headphones_rounded),
            title: const Text('Recordar por audífono',
                style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('Ahora: ${eq.device}',
                style: TextStyle(color: AppColors.textDim)),
            value: eq.perDevice,
            onChanged: (v) => eq.setPerDevice(v),
          ),
          const SizedBox(height: 12),
          Text('PREAJUSTES',
              style: TextStyle(fontSize: AppType.caption, letterSpacing: 1.5, fontWeight: FontWeight.w700, color: AppColors.textDim)),
          const SizedBox(height: 6),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final p in EqService.visible)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(p),
                      selected: eq.preset == p,
                      showCheckmark: false,
                      selectedColor: rockRed,
                      backgroundColor: AppColors.surfaceHigh,
                      side: BorderSide(color: eq.preset == p ? rockRed : AppColors.outline),
                      labelStyle: TextStyle(
                          color: eq.preset == p ? Colors.white : AppColors.textDim,
                          fontWeight: FontWeight.w600),
                      onSelected: on
                          ? (_) {
                              HapticFeedback.selectionClick();
                              eq.applyPreset(p);
                            }
                          : null,
                    ),
                  ),
              ],
            ),
          ),
          if (eq.preset == 'Personalizado')
            Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Personalizado', style: TextStyle(color: AppColors.amber, fontWeight: FontWeight.w600)),
            ),
          const SizedBox(height: 18),
          Opacity(opacity: on ? 1 : 0.4, child: _bands()),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Graves', style: TextStyle(fontSize: AppType.caption, color: AppColors.textFaint)),
              Text('Medios', style: TextStyle(fontSize: AppType.caption, color: AppColors.textFaint)),
              Text('Agudos', style: TextStyle(fontSize: AppType.caption, color: AppColors.textFaint)),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Icon(eq.embedStatus == 'activo' ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                  size: 16, color: eq.embedStatus == 'activo' ? const Color(0xFF7FB38A) : AppColors.textFaint),
              const SizedBox(width: 8),
              Expanded(child: Text(_statusText, style: TextStyle(fontSize: AppType.caption, color: AppColors.textFaint))),
            ],
          ),
          const SizedBox(height: 6),
          Row(children: [
            Icon(Icons.auto_awesome_outlined, size: 16, color: AppColors.textFaint),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Consultas de IA del ecualizador hoy: ${eq.aiToday}. Los artistas conocidos y las canciones repetidas no gastan IA.',
                style: TextStyle(fontSize: AppType.caption, color: AppColors.textFaint)),
            ),
          ]),
          const SizedBox(height: 6),
          Text('Si en algún momento el sonido falla, apaga el ecualizador con el interruptor de abajo.',
              style: TextStyle(fontSize: AppType.caption, color: AppColors.textFaint)),
        ],
      ),
    );
  }

  Widget _suggestionCard() {
    final s = eq.suggestion;
    final song = eq.currentSong;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        gradient: LinearGradient(colors: [rockRed.withOpacity(0.24), AppColors.amber.withOpacity(0.08)]),
        border: Border.all(color: rockRed.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.auto_awesome_rounded, size: 16, color: AppColors.amber),
            const SizedBox(width: 6),
            Expanded(
              child: Text('SUGERENCIA DEL ASISTENTE',
                  style: TextStyle(fontSize: AppType.caption, letterSpacing: 1.2, color: AppColors.amber, fontWeight: FontWeight.w700)),
            ),
          ]),
          // Fuente (Gemini, Groq, reglas) como chip debajo del título.
          if (s != null && s.source.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: AppColors.outline),
              ),
              child: Text(s.source,
                  style: TextStyle(fontSize: AppType.micro, color: AppColors.textDim)),
            ),
          ],
          const SizedBox(height: 8),
          if (song == null || song.isRadio)
            const Text('Pon una canción y te sugiero el mejor ajuste para ella.',
                style: TextStyle(fontSize: AppType.bodySm, height: 1.4))
          else if (eq.suggesting)
            Row(children: [
              SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.amber)),
              SizedBox(width: 10),
              Text('Escuchando la canción…', style: TextStyle(fontSize: AppType.bodySm)),
            ])
          else if (s != null)
            RichText(
              text: TextSpan(style: const TextStyle(fontSize: AppType.bodySm, height: 1.4, color: AppColors.text), children: [
                const TextSpan(text: 'Para '),
                TextSpan(text: song.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: ' de ${song.artist} te recomiendo '),
                TextSpan(text: s.preset, style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.amber)),
                TextSpan(text: s.reason.isEmpty ? '.' : ': ${s.reason}'),
              ]),
            )
          else
            const Text('Toca "Sugerir" para que el asistente elija el ajuste.', style: TextStyle(fontSize: AppType.bodySm)),
          const SizedBox(height: 10),
          Row(children: [
            AppButton.primary(
              label: s != null ? 'Aplicar' : 'Sugerir',
              onPressed: (song == null || song.isRadio || eq.suggesting || !eq.enabled)
                  ? null
                  : () {
                      if (s != null) {
                        eq.applyPreset(s.preset);
                      } else {
                        eq.suggestCurrent();
                      }
                    },
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text('Auto en cada canción',
                  textAlign: TextAlign.end,
                  maxLines: 2,
                  style: TextStyle(fontSize: AppType.caption, color: AppColors.textDim)),
            ),
            Switch(
              value: eq.auto,
              activeColor: Colors.white,
              activeTrackColor: rockRed,
              onChanged: eq.enabled ? eq.setAuto : null,
            ),
          ]),
        ],
      ),
    );
  }

  Widget _bands() {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.outline),
      ),
      child: SizedBox(
        height: 220,
        child: Stack(
          children: [
            Positioned.fill(
              top: 22,
              bottom: 24,
              child: CustomPaint(painter: _CurvePainter(eq.gains, rockRed)),
            ),
            Row(
              children: [
                for (var i = 0; i < 10; i++)
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          '${eq.gains[i] > 0 ? '+' : ''}${eq.gains[i].round()}',
                          style: TextStyle(fontSize: AppType.micro, color: AppColors.textDim),
                        ),
                        Expanded(
                          child: RotatedBox(
                            quarterTurns: 3,
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 3,
                                activeTrackColor: rockRed,
                                inactiveTrackColor: AppColors.outline,
                                thumbColor: Colors.white,
                                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                              ),
                              child: Slider(
                                min: -12,
                                max: 12,
                                divisions: 24,
                                value: eq.gains[i],
                                onChanged: eq.enabled
                                    ? (v) {
                                        if (v != eq.gains[i]) HapticFeedback.selectionClick();
                                        eq.setGain(i, v);
                                      }
                                    : null,
                              ),
                            ),
                          ),
                        ),
                        Text(EqService.labels[i],
                            style: TextStyle(fontSize: AppType.micro, color: AppColors.textDim)),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CurvePainter extends CustomPainter {
  _CurvePainter(this.gains, this.color);
  final List<double> gains;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width / gains.length;
    final pts = <Offset>[
      for (var i = 0; i < gains.length; i++)
        Offset(w * i + w / 2, size.height / 2 - gains[i] / 12 * (size.height / 2)),
    ];
    final mid = Paint()
      ..color = Colors.white.withOpacity(0.06)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, size.height / 2), Offset(size.width, size.height / 2), mid);
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      final p0 = pts[i - 1];
      final p1 = pts[i];
      final cx = (p0.dx + p1.dx) / 2;
      path.cubicTo(cx, p0.dy, cx, p1.dy, p1.dx, p1.dy);
    }
    final fill = Path.from(path)
      ..lineTo(pts.last.dx, size.height)
      ..lineTo(pts.first.dx, size.height)
      ..close();
    canvas.drawPath(fill, Paint()..color = color.withOpacity(0.14));
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(covariant _CurvePainter old) => true;
}
