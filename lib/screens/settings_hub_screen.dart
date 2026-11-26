import 'package:flutter/material.dart';
import 'dart:io';

import '../services/backup_service.dart';
import '../widgets/app_button.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/eq_service.dart';
import 'eq_screen.dart';

import '../services/ai_settings.dart';
import '../services/block_service.dart';
import '../services/data_saver.dart';
import '../theme/app_theme.dart';
import 'ai_settings_screen.dart';
import 'data_settings_screen.dart';
import '../widgets/undo.dart';
import '../widgets/sleep_wake_sheet.dart';
import 'onboarding_screen.dart';
import '../services/help_settings.dart';
import '../services/music_mode.dart';
import '../services/stats_service.dart';
import 'mode_pick_screen.dart';
import '../widgets/section_header.dart';
import '../services/dj_voice.dart';

/// Un solo lugar para todos los ajustes (agrupados).
class SettingsHubScreen extends StatefulWidget {
  const SettingsHubScreen({super.key});

  @override
  State<SettingsHubScreen> createState() => _SettingsHubScreenState();
}

class _SettingsHubScreenState extends State<SettingsHubScreen> {
  int _bytes = 0;

  @override
  void initState() {
    super.initState();
    HelpSettings.showTips.addListener(_refresh);
    _load();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    HelpSettings.showTips.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _load() async {
    await AiSettings.instance.load();
    await DataSaver.instance.load();
    await BlockService.instance.ensureLoaded();
    await BadVideos.load();
    final b = await DataSaver.instance.sizeBytes();
    var plays = 0;
    try {
      plays = (await StatsService.instance.plays()).length;
    } catch (_) {}
    final lb = await BackupService.lastBackup();
    final due = await BackupService.due();
    if (mounted) {
      setState(() {
        _lastBackup = lb;
        _backupDue = due;
        _bytes = b;
        _plays = plays;
      });
    }
  }

  int _plays = 0;
  DateTime? _lastBackup;
  bool _backupDue = false;

  String _backupLabel() {
    final l = _lastBackup;
    if (l == null) return 'Nunca la has hecho';
    final d = DateTime.now().difference(l).inDays;
    return d == 0 ? 'Última: hoy' : 'Última: hace $d ${d == 1 ? 'día' : 'días'}';
  }

  Future<void> _showBackup() async {
    var keys = false;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Copia de seguridad',
                    style: TextStyle(fontSize: AppType.title, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(
                    'Crea un archivo con tus favoritas, listas, historial, escuchas, emisoras, alarmas y ajustes de los dos modos. Guárdalo en Drive o envíatelo por WhatsApp.',
                    style: TextStyle(color: AppColors.textDim, height: 1.4)),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Incluir las claves de IA'),
                  subtitle: Text('Quien tenga el archivo podrá verlas.',
                      style: TextStyle(color: AppColors.textDim, fontSize: AppType.caption)),
                  value: keys,
                  onChanged: (v) => set(() => keys = v),
                ),
                const SizedBox(height: 8),
                AppButton.primary(
                  label: 'Exportar copia',
                  icon: Icons.upload_file_rounded,
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    try {
                      await BackupService.export(keys: keys);
                    } catch (_) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                            content: Text('No se pudo crear la copia.')));
                      }
                    }
                    _load();
                  },
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    _importBackup();
                  },
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('Restaurar desde un archivo'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _importBackup() async {
    Map<String, dynamic>? j;
    try {
      j = await BackupService.pick();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Ese archivo no es una copia de RockPlay IA.')));
      }
      return;
    }
    if (j == null || !mounted) return;
    final merge = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('¿Cómo restaurar?'),
        content: const Text(
            '«Combinar» suma la copia a lo que ya tienes, sin repetir canciones.\n'
            '«Reemplazar» cambia tus datos por los de la copia.\n\n'
            'Al terminar, la app se cierra; ábrela de nuevo para ver tus datos.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Reemplazar')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Combinar')),
        ],
      ),
    );
    if (merge == null || !mounted) return;
    // Aviso antes de restaurar: después se cierra al instante, sin que nada
    // alcance a escribir datos viejos encima.
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (c) => const AlertDialog(
        content: Row(children: [
          SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 16),
          Expanded(child: Text('Restaurando… la app se cerrará al terminar.')),
        ]),
      ),
    );
    try {
      await BackupService.restore(j, merge: merge);
    } catch (_) {
      // Copia dañada: se cierra el aviso y se explica; la app no se cierra.
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No se pudo restaurar: el archivo está dañado o incompleto.')));
      }
      return;
    }
    exit(0);
  }

  /// Porcentaje de lo que suena que la app cambió por otra versión.
  String _badPct(int bad) {
    if (bad == 0) return 'todo suena bien';
    final total = _plays + bad;
    final p = (bad * 100 / total).round();
    return p < 1
        ? 'menos del 1 % se cambia solo'
        : '$p % de lo que suena se cambia solo';
  }

  Future<void> _go(Widget page) async {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => page));
    _load();
  }

  String _size(int b) {
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
    return '${(b / (1024 * 1024)).toStringAsFixed(1).replaceAll('.', ',')} MB';
  }

  /// Caja de ícono común (la misma de cada fila de Ajustes).
  Widget _iconBox(IconData icon) => Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Icon(icon, size: 22),
      );

  /// Fila con interruptor, alineada con las demás filas.
  Widget _switchRow(IconData icon, String title, String subtitle, bool value,
      ValueChanged<bool> onChanged) {
    return Semantics(
      toggled: value,
      label: title,
      child: InkWell(
        onTap: () => onChanged(!value),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(children: [
              _iconBox(icon),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontSize: AppType.body, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: TextStyle(
                            fontSize: AppType.label, color: AppColors.textDim)),
                  ],
                ),
              ),
              Switch(value: value, onChanged: onChanged),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _group(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: Text(t,
            style: TextStyle(
                fontSize: AppType.caption,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w700,
                color: AppColors.amber)),
      );

  Widget _box(List<Widget> rows) => Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.outline),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, color: AppColors.outline),
            rows[i],
          ],
        ]),
      );

  Widget _row(IconData icon, String title, String value, VoidCallback onTap,
      {String? badge, String? tip}) {
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.surfaceHigh,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Icon(icon, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: AppType.body, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(value,
                      style: TextStyle(
                          fontSize: AppType.label, color: AppColors.textDim)),
                  if (tip != null && HelpSettings.showTips.value) ...[
                    const SizedBox(height: 4),
                    Text(tip,
                        style: TextStyle(
                            fontSize: AppType.caption,
                            height: 1.3,
                            color: AppColors.amber)),
                  ],
                ],
              ),
            ),
            if (badge != null)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(badge,
                    style: TextStyle(
                        color: AppColors.amber,
                        fontWeight: FontWeight.w800)),
              ),
            Icon(Icons.chevron_right_rounded,
                color: AppColors.textDim),
          ]),
        ),
      ),
    );
  }

  Widget _chips(List<int> opts, int cur, void Function(int) on) => Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final n in opts)
            ChoiceChip(
              label: Text('$n'),
              selected: cur == n,
              onSelected: (_) => on(n),
            ),
        ],
      );

  void _pickListSize() {
    showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c, set) {
        final ai = AiSettings.instance;
        return AlertDialog(
          title: const Text('Canciones por lista'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  'Máximo de canciones que trae el asistente. Menos canciones = respuesta más rápida y menos gasto de tu cuota gratis.',
                  style: TextStyle(color: AppColors.textDim, fontSize: AppType.caption)),
              const SizedBox(height: 12),
              _chips(AiSettings.maxOptions, ai.maxSongs, (n) {
                set(() => ai.maxSongs = n);
                ai.save();
              }),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('Listo')),
          ],
        );
      }),
    ).then((_) => _load());
  }

  void _pickMixSize() {
    showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c, set) {
        final ds = DataSaver.instance;
        return AlertDialog(
          title: const Text('Tamaño de los mixes'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    'Aplica a Tu mix, los mixes por género y la emisora de artista. Menos = carga más rápida y menos datos.',
                    style:
                        TextStyle(color: AppColors.textDim, fontSize: AppType.caption)),
                const SizedBox(height: 12),
                const Text('Canciones (máximo)',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                _chips(DataSaver.mixSongOptions, ds.mixSongs, (n) {
                  set(() => ds.mixSongs = n);
                  ds.save();
                }),
                const SizedBox(height: 12),
                const Text('Artistas (máximo)',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                _chips(DataSaver.mixArtistOptions, ds.mixArtists, (n) {
                  set(() => ds.mixArtists = n);
                  ds.save();
                }),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('Listo')),
          ],
        );
      }),
    ).then((_) => _load());
  }

  void _showSkipped() => showSkippedDialog(context).then((_) => _load());

  /// «Filtros»: artistas bloqueados y canciones que no sonaron, juntos.
  void _showFilters() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 18, 20, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Filtros',
                  style: TextStyle(
                      fontSize: AppType.titleSm, fontWeight: FontWeight.w800)),
            ),
          ),
          ListTile(
            minVerticalPadding: 12,
            leading: const Icon(Icons.block_rounded),
            title: const Text('Artistas bloqueados'),
            subtitle: Text(
                '${BlockService.instance.names.length} en total · no salen en búsquedas ni mixes',
                style: TextStyle(color: AppColors.textDim)),
            onTap: () {
              Navigator.pop(c);
              _showBlocked();
            },
          ),
          ListTile(
            minVerticalPadding: 12,
            leading: const Icon(Icons.bug_report_outlined),
            title: const Text('Versiones reemplazadas'),
            subtitle: Text(
                '${BadVideos.ids.length} que YouTube no deja reproducir',
                style: TextStyle(color: AppColors.textDim)),
            onTap: () {
              Navigator.pop(c);
              _showSkipped();
            },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  void _showBlocked() {
    showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c, set) {
        final names = BlockService.instance.names;
        return AlertDialog(
          title: const Text('Artistas bloqueados'),
          content: SizedBox(
            width: double.maxFinite,
            child: names.isEmpty
                ? const Text('No has bloqueado ningún artista.')
                : ListView(shrinkWrap: true, children: [
                    for (final n in names)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(n),
                        trailing: TextButton(
                          onPressed: () async {
                            await BlockService.instance.remove(n);
                            set(() {});
                          },
                          child: const Text('Desbloquear'),
                        ),
                      ),
                  ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('Cerrar')),
          ],
        );
      }),
    ).then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    final ai = AiSettings.instance;
    final ds = DataSaver.instance;
    final aiOn = ai.groqKey.trim().isNotEmpty || ai.geminiKey.trim().isNotEmpty;
    final aiLabel = ai.geminiKey.trim().isNotEmpty
        ? 'Gemini activa'
        : ai.groqKey.trim().isNotEmpty
            ? 'Groq activa'
            : 'Sin claves · usa reglas simples';
    final bad = BadVideos.ids.length;
    final blocked = BlockService.instance.names.length;
    return Scaffold(
      appBar: AppBar(title: AppTitle('Ajustes')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          _group('MODO DE MÚSICA'),
          _box([
            _row(
                MusicModeService.general
                    ? Icons.graphic_eq_rounded
                    : Icons.bolt_rounded,
                'Modo de música',
                MusicModeService.general
                    ? 'Todos los géneros · Pulso'
                    : 'Solo rock · RockPlay',
                () => _go(const MusicModeScreen()),
                tip: 'Decide si la app es solo de rock o de todos los géneros. Cambia colores, textos, mixes, asistente y conciertos.'),
          ]),
          _group('ASISTENTE Y MIXES'),
          _box([
            _row(Icons.vpn_key_rounded, 'Inteligencia artificial', aiLabel,
                () => _go(const AiSettingsScreen()),
                badge: aiOn ? null : '!',
                tip: 'Pega aquí tus claves gratis de Gemini o Groq para que el asistente piense con IA.'),
          ]),
          _group('DATOS'),
          _box([
            _row(Icons.backup_rounded, 'Copia de seguridad',
                _backupLabel(), _showBackup,
                badge: _backupDue ? '!' : null,
                tip: 'Guarda tus favoritas, listas, historial y ajustes en un archivo para no perderlos si reinstalas.'),
            _row(Icons.storage_rounded, 'Almacenamiento',
                '${_size(_bytes)} en uso',
                () => _go(const DataSettingsScreen()),
                tip: 'Guarda portadas y datos para no bajarlos otra vez. Aquí puedes borrarlo.'),
          ]),
          _group('REPRODUCCIÓN'),
          _box([
            _row(Icons.equalizer_rounded, 'Ecualizador',
                EqService.instance.enabled ? 'Activo · ${EqService.instance.preset}' : 'Apagado',
                () => _go(const EqScreen()),
                tip: 'Ajusta graves y agudos con preajustes; el asistente sugiere el mejor para cada canción.'),
            ValueListenableBuilder<bool>(
              valueListenable: DjVoice.instance.on,
              builder: (context, on, _) => _switchRow(
                  Icons.record_voice_over_rounded,
                  'Locutor IA',
                  'Cada 3 canciones baja la música y te cuenta qué suena',
                  on,
                  (v) => DjVoice.instance.set(v)),
            ),
            // iPhone: el despertador depende de Android.
            if (!Platform.isIOS)
              _row(Icons.alarm_rounded, 'Despertador',
                'Despierta con Tu mix, una lista o la radio',
                () => showSleepWakeSheet(context, showTimer: false),
                tip: 'Alarmas que suenan con tu música a la hora que elijas.'),
            _row(Icons.filter_alt_outlined, 'Filtros',
                blocked == 0 ? 'Ningún artista bloqueado' : '$blocked ${blocked == 1 ? 'artista bloqueado' : 'artistas bloqueados'}',
                _showFilters,
                tip: 'Artistas que bloqueaste. Si YouTube no deja sonar una versión en apps, la app busca otra sola; no tienes que hacer nada.'),
          ]),
          // Perillas técnicas, plegadas.
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: AppColors.outline),
              ),
              clipBehavior: Clip.antiAlias,
              child: Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  leading: _iconBox(Icons.settings_suggest_rounded),
                  tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  title: const Text('Avanzado',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('Tamaños de listas y mixes',
                      style: TextStyle(
                          color: AppColors.textDim, fontSize: AppType.label)),
                  children: [
                    Divider(height: 1, color: AppColors.outline),
                    _row(Icons.format_list_numbered_rounded, 'Listas del asistente',
                        '${ai.maxSongs} canciones como máximo', _pickListSize,
                        tip: 'Cuántas canciones como máximo trae el asistente. Menos es más rápido.'),
                    Divider(height: 1, color: AppColors.outline),
                    _row(Icons.tune_rounded, 'Mixes',
                        'Hasta ${ds.mixSongs} canciones y ${ds.mixArtists} artistas',
                        _pickMixSize,
                        tip: 'Cuántas canciones y artistas usan Tu mix, los géneros y la emisora.'),
                    Divider(height: 1, color: AppColors.outline),
                    _row(Icons.swap_horiz_rounded, 'Versiones reemplazadas',
                        _badPct(bad), _showFilters,
                        tip: 'Si YouTube no deja sonar una versión en apps, la app busca otra sola.'),
                  ],
                ),
              ),
            ),
          ),
          _group('AYUDA'),
          _box([
            _row(Icons.slideshow_rounded, 'Ver la guía de bienvenida',
                'Repasa para qué sirve cada parte', () async {
              await HelpSettings.resetTips();
              if (!mounted) return;
              await Navigator.of(context).push(MaterialPageRoute<void>(
                  fullscreenDialog: true,
                  builder: (_) => const OnboardingScreen()));
            }),
            _switchRow(Icons.lightbulb_outline_rounded, 'Mostrar explicaciones',
                'Textos de ayuda bajo cada opción y consejos',
                HelpSettings.showTips.value, HelpSettings.setShowTips),
          ]),
          const SizedBox(height: 18),
          FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (context, snap) {
              final p = snap.data;
              return Center(
                child: Text(
                  p == null ? MusicModeService.appName : '${MusicModeService.appName} ${p.version} · compilación ${p.buildNumber}',
                  style: TextStyle(fontSize: AppType.caption, color: AppColors.textFaint),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

Future<void> showSkippedDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
      builder: (c) => StatefulBuilder(builder: (c, set) {
        final counts = <String, int>{};
        for (final v in BadVideos.names.values.toList().reversed) {
          counts[v] = (counts[v] ?? 0) + 1;
        }
        final saved = [
          for (final e in counts.entries)
            e.value > 1 ? '${e.key}  (${e.value} versiones)' : e.key
        ];
        final unnamed = BadVideos.ids.length - BadVideos.names.length;
        return AlertDialog(
          title: const Text('Versiones reemplazadas'),
          content: SizedBox(
            width: double.maxFinite,
            child: BadVideos.ids.isEmpty && SkipLog.entries.isEmpty
                ? const Text('Todavía no se ha saltado ninguna.')
                : ListView(shrinkWrap: true, children: [
                    Text(
                        '${BadVideos.ids.length} versiones de YouTube no se pueden reproducir en apps. La app ya las cambia por otra versión de la misma canción; no tienes que hacer nada.',
                        style: TextStyle(
                            color: AppColors.textDim, fontSize: AppType.caption)),
                    const SizedBox(height: 10),
                    for (final e in saved)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(e, style: const TextStyle(fontSize: AppType.bodySm)),
                      ),
                    if (unnamed > 0)
                      Text('Y $unnamed más guardadas antes, sin nombre.',
                          style: TextStyle(
                              color: AppColors.textDim, fontSize: AppType.caption)),
                    if (SkipLog.entries.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text('De esta sesión (motivo técnico)',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      for (final e in SkipLog.entries)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(e,
                              style: const TextStyle(fontSize: AppType.caption)),
                        ),
                    ],
                  ]),
          ),
          actions: [
            if (BadVideos.ids.isNotEmpty)
              TextButton(
                onPressed: () async {
                  final ok = await confirmAction(c,
                      title: '¿Olvidar todas?',
                      message:
                          'Volverán a salir en tus búsquedas y la app intentará reproducirlas otra vez.',
                      confirmLabel: 'Olvidar');
                  if (!ok) return;
                  await BadVideos.clear();
                  set(() {});
                },
                child: const Text('Olvidar todas'),
              ),
            TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('Cerrar')),
          ],
        );
      }),
  );
}

