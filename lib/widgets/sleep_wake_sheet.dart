import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../screens/alarm_edit_screen.dart';
import '../services/alarm_service.dart';
import '../services/playback_service.dart';
import '../services/music_mode.dart';
import '../theme/app_theme.dart';
import 'playback_ui.dart';

/// «Dormir y despertar»: temporizador para apagar la música y las alarmas
/// del despertador. [showTimer] = false cuando no suena nada (ej. Ajustes).
void showSleepWakeSheet(BuildContext context, {bool showTimer = true}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (ctx) => _SleepWake(showTimer: showTimer),
  );
}

class _SleepWake extends StatelessWidget {
  final bool showTimer;
  const _SleepWake({required this.showTimer});

  Widget _chip(BuildContext ctx, String label, bool on, VoidCallback go) {
    return Semantics(
      button: true,
      selected: on,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          go();
          Navigator.of(ctx).pop();
        },
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? AppColors.redBtn : AppColors.surfaceHigh,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: on ? AppColors.redBtn : AppColors.outline),
          ),
          child: Text(label,
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: AppType.bodySm,
                  color: on ? Colors.white : AppColors.textDim)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final svc = PlaybackService.instance;
    final pb = PlaybackUi.instance;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: AppColors.outline,
                      borderRadius: BorderRadius.circular(AppRadius.pill)),
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(byMode('DORMIR Y DESPERTAR', 'Dormir y despertar'),
                    style: AppType.oswald(AppType.title)),
              ),
              if (showTimer) ...[
                const SizedBox(height: 14),
                Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Text('APAGAR LA MÚSICA', style: AppType.overline),
                ),
                const SizedBox(height: 8),
                ValueListenableBuilder<String?>(
                  valueListenable: pb.sleepLabel,
                  builder: (ctx, label, _) => Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _chip(context, '15 min', false,
                          () => svc.setSleep(const Duration(minutes: 15))),
                      _chip(context, '30 min', false,
                          () => svc.setSleep(const Duration(minutes: 30))),
                      _chip(context, '1 h', false,
                          () => svc.setSleep(const Duration(hours: 1))),
                      _chip(context, 'Al terminar la canción', false,
                          () => svc.setSleep(null, endOfSong: true)),
                      if (label != null)
                        _chip(context, 'Cancelar ($label)', true,
                            () => svc.setSleep(null)),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Padding(
                padding: EdgeInsets.only(left: 4),
                child: Text('DESPERTADOR', style: AppType.overline),
              ),
              const SizedBox(height: 8),
              const _AlarmList(),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.redText,
                    side: BorderSide(color: AppColors.redBtn),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.lg)),
                    textStyle: const TextStyle(
                        fontSize: AppType.body, fontWeight: FontWeight.w800),
                  ),
                  onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                          builder: (_) => const AlarmEditScreen())),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Nueva alarma'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AlarmList extends StatelessWidget {
  const _AlarmList();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: AlarmService.instance.revision,
      builder: (context, _, __) => FutureBuilder<List<Alarm>>(
        future: AlarmService.instance.all(),
        builder: (context, snap) {
          final list = snap.data ?? const <Alarm>[];
          if (list.isEmpty) {
            return Padding(
              padding: EdgeInsets.fromLTRB(4, 0, 4, 4),
              child: Text(
                  'Aún no tienes alarmas. Despierta con Tu mix, una lista o la radio.',
                  style: TextStyle(
                      fontSize: AppType.bodySm, color: AppColors.textDim)),
            );
          }
          return Container(
            decoration: BoxDecoration(
              color: AppColors.surfaceHigh,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: AppColors.outline),
            ),
            child: Column(children: [
              for (var i = 0; i < list.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                _row(context, list[i]),
              ],
            ]),
          );
        },
      ),
    );
  }

  Widget _row(BuildContext context, Alarm a) {
    final on = a.enabled;
    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => AlarmEditScreen(alarm: a))),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(TextSpan(children: [
                  TextSpan(
                      text: a.time12,
                      style: AppType.oswald(30,
                          height: 1.1,
                          color: on ? AppColors.text : AppColors.textDim)),
                  TextSpan(
                      text: '  ${a.ampm}',
                      style: TextStyle(
                          fontSize: AppType.bodySm,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textDim)),
                ])),
                Text('${a.daysLabel} · ${a.sourceLabel}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: AppType.label, color: AppColors.textDim)),
              ],
            ),
          ),
          Switch(
            value: on,
            activeTrackColor: AppColors.redBtn,
            onChanged: (v) async {
              HapticFeedback.selectionClick();
              if (v) await AlarmService.instance.requestPermissions();
              await AlarmService.instance.setEnabled(a.id, v);
            },
          ),
        ]),
      ),
    );
  }
}
