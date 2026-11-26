import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../services/alarm_service.dart';
import '../services/library_service.dart';
import '../services/playlist_service.dart';
import '../services/radio_service.dart';
import '../services/music_mode.dart';
import '../theme/app_theme.dart';
import '../widgets/undo.dart';
import '../widgets/section_header.dart';

/// Crear o editar una alarma: hora, días, qué suena, volumen que sube y
/// tono de respaldo.
class AlarmEditScreen extends StatefulWidget {
  final Alarm? alarm;
  const AlarmEditScreen({super.key, this.alarm});

  @override
  State<AlarmEditScreen> createState() => _AlarmEditScreenState();
}

class _AlarmEditScreenState extends State<AlarmEditScreen> {
  late Alarm _a;
  bool _isNew = true;

  @override
  void initState() {
    super.initState();
    if (widget.alarm != null) {
      _a = widget.alarm!.copy();
      _isNew = false;
    } else {
      _a = Alarm(id: 0);
      AlarmService.instance.newId().then((id) {
        if (mounted) setState(() => _a = Alarm.fromJson(_a.toJson()..['id'] = id));
      });
    }
  }

  String _untilLabel() {
    final d = _a.nextFire().difference(DateTime.now());
    final h = d.inHours, m = d.inMinutes % 60;
    if (h == 0) return 'Suena en $m min';
    return 'Suena en $h h $m min';
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _a.hour, minute: _a.minute),
      helpText: 'Hora de la alarma',
    );
    if (t == null) return;
    setState(() {
      _a.hour = t.hour;
      _a.minute = t.minute;
    });
  }

  void _setAmPm(bool am) {
    if (am && _a.hour >= 12) setState(() => _a.hour -= 12);
    if (!am && _a.hour < 12) setState(() => _a.hour += 12);
  }

  Future<void> _pickRadio() async {
    final list = await RadioService.instance.saved();
    if (!mounted) return;
    if (list.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Guarda primero una emisora en Buscar → Radio en vivo.')));
      return;
    }
    final st = await showModalBottomSheet<RadioStation>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (c) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          const ListTile(
              title: Text('Elige la emisora',
                  style: TextStyle(fontWeight: FontWeight.w800))),
          for (final s in list)
            ListTile(
              leading: const Icon(Icons.sensors_rounded),
              title: Text(s.name),
              onTap: () => Navigator.pop(c, s),
            ),
        ]),
      ),
    );
    if (st == null) return;
    setState(() {
      _a.source = AlarmSource.radio;
      _a.payload = jsonEncode(st.toJson());
      _a.sourceLabel = st.name;
    });
  }

  Future<void> _pickList() async {
    final lists = await PlaylistService.instance.all();
    final favs = await LibraryService.instance.favorites();
    if (!mounted) return;
    final r = await showModalBottomSheet<(AlarmSource, String, String)>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (c) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (c, sc) => ListView(controller: sc, children: [
          const ListTile(
              title: Text('Listas',
                  style: TextStyle(fontWeight: FontWeight.w800))),
          ListTile(
            leading: Icon(Icons.favorite_rounded, color: AppColors.redText),
            title: const Text('Tus favoritas'),
            subtitle: Text('${favs.length} canciones · en orden aleatorio'),
            onTap: () => Navigator.pop(
                c, (AlarmSource.list, 'fav', 'Tus favoritas')),
          ),
          for (final p in lists)
            ListTile(
              leading: const Icon(Icons.queue_music_rounded),
              title: Text(p.name),
              subtitle: Text('${p.songs.length} canciones'),
              onTap: () =>
                  Navigator.pop(c, (AlarmSource.list, p.id, p.name)),
            ),
          if (favs.isNotEmpty)
            const ListTile(
                title: Text('Una canción',
                    style: TextStyle(fontWeight: FontWeight.w800))),
          for (final s in favs.take(60))
            ListTile(
              leading: const Icon(Icons.music_note_rounded),
              title: Text(s.title,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(s.artist,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => Navigator.pop(c,
                  (AlarmSource.song, jsonEncode(s.toJson()), s.title)),
            ),
        ]),
      ),
    );
    if (r == null) return;
    setState(() {
      _a.source = r.$1;
      _a.payload = r.$2;
      _a.sourceLabel = r.$3;
    });
  }

  Future<void> _pickBackupFile() async {
    try {
      final res = await FilePicker.platform.pickFiles(type: FileType.audio);
      final path = res?.files.single.path;
      if (path == null) return;
      final dir = await getApplicationDocumentsDirectory();
      final name = res!.files.single.name;
      final dest = File('${dir.path}/alarma_${_a.id}_$name');
      await File(path).copy(dest.path);
      setState(() {
        _a.backupPath = dest.path;
        _a.backupLabel = name;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No pude usar ese archivo. Prueba con un MP3.')));
    }
  }

  Future<void> _save() async {
    HapticFeedback.mediumImpact();
    _a.enabled = true;
    await AlarmService.instance.requestPermissions();
    await AlarmService.instance.save(_a);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Alarma lista. ${_untilLabel()}.')));
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final ok = await confirmAction(context,
        title: '¿Borrar esta alarma?',
        message: 'La alarma de las ${_a.time12} ${_a.ampm} dejará de sonar.',
        confirmLabel: 'Borrar');
    if (!ok) return;
    await AlarmService.instance.delete(_a.id);
    if (mounted) Navigator.of(context).pop();
  }

  Widget _chip(String label, bool on, VoidCallback tap, {double? w}) {
    return Semantics(
      button: true,
      selected: on,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          tap();
        },
        child: AnimatedContainer(
          duration: AppMotion.of(context, AppMotion.fast),
          width: w,
          height: 44,
          constraints: const BoxConstraints(minWidth: 44),
          padding: EdgeInsets.symmetric(horizontal: w == null ? 16 : 0),
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

  Widget _source(IconData icon, String title, String sub, bool on,
      VoidCallback tap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: on ? AppColors.redBtn.withValues(alpha: 0.12) : AppColors.surfaceHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: BorderSide(color: on ? AppColors.redBtn : AppColors.outline),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: tap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    gradient: on
                        ? LinearGradient(colors: AppPalettes.fire)
                        : null,
                    color: on ? null : AppColors.outline,
                  ),
                  child: Icon(icon,
                      size: 20, color: on ? Colors.white : AppColors.textDim),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: AppType.body)),
                      Text(sub,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: AppType.label,
                              color: AppColors.textDim)),
                    ],
                  ),
                ),
                Icon(
                    on
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    color: on ? AppColors.redText : AppColors.textFaint),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const dayL = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];
    const dayFull = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
    final isList = _a.source == AlarmSource.list || _a.source == AlarmSource.song;
    return Scaffold(
      appBar: AppBar(
        title: AppTitle(_isNew ? 'Nueva alarma' : 'Editar alarma'),
        actions: [
          if (!_isNew)
            IconButton(
              tooltip: 'Borrar alarma',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: _delete,
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
          child: SizedBox(
            height: 56,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.redBtn,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.lg)),
                textStyle: const TextStyle(
                    fontSize: AppType.body, fontWeight: FontWeight.w800),
              ),
              onPressed: _a.id == 0 ? null : _save,
              child: const Text('Guardar alarma'),
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Center(
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              onTap: _pickTime,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Semantics(
                  button: true,
                  label: 'Cambiar la hora',
                  child: Text(_a.time12,
                      style: AppType.oswald(84, height: 1.0)
                          .copyWith(letterSpacing: 1)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _chip('a. m.', _a.hour < 12, () => _setAmPm(true)),
            const SizedBox(width: 6),
            _chip('p. m.', _a.hour >= 12, () => _setAmPm(false)),
          ]),
          const SizedBox(height: 10),
          Center(
            child: Text(_untilLabel(),
                style: TextStyle(
                    fontSize: AppType.label, color: AppColors.textDim)),
          ),
          const SizedBox(height: 22),
          Text('REPETIR', style: AppType.overline),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < 7; i++)
                Semantics(
                  label: dayFull[i],
                  child: _chip(dayL[i], _a.days.contains(i + 1), () {
                    setState(() {
                      if (!_a.days.remove(i + 1)) _a.days.add(i + 1);
                    });
                  }, w: 44),
                ),
            ],
          ),
          if (_a.days.isEmpty)
            Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('Sin días marcados: suena una sola vez.',
                  style: TextStyle(
                      fontSize: AppType.caption, color: AppColors.textDim)),
            ),
          const SizedBox(height: 22),
          Text('QUÉ SUENA', style: AppType.overline),
          const SizedBox(height: 8),
          _source(Icons.music_note_rounded, 'Tu mix', 'Tus artistas de siempre',
              _a.source == AlarmSource.mix, () {
            setState(() {
              _a.source = AlarmSource.mix;
              _a.payload = '';
              _a.sourceLabel = 'Tu mix';
            });
          }),
          _source(
              Icons.sensors_rounded,
              'Radio en vivo',
              _a.source == AlarmSource.radio
                  ? '${_a.sourceLabel} · arranca más rápido'
                  : 'Una de tus emisoras · arranca más rápido',
              _a.source == AlarmSource.radio,
              _pickRadio),
          _source(
              Icons.queue_music_rounded,
              'Una canción o lista',
              isList ? _a.sourceLabel : 'Elige de tus favoritas o listas',
              isList,
              _pickList),
          const SizedBox(height: 22),
          Row(children: [
            Text('VOLUMEN DE LA ALARMA', style: AppType.overline),
            const Spacer(),
            Text('${(_a.volume * 100).round()} %',
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: AppType.body)),
          ]),
          Row(children: [
            Icon(Icons.volume_down_rounded, color: AppColors.textDim),
            Expanded(
              child: Slider(
                value: _a.volume,
                min: 0.3,
                max: 1.0,
                divisions: 7,
                activeColor: AppColors.redBtn,
                label: '${(_a.volume * 100).round()} %',
                onChanged: (v) {
                  if (v != _a.volume) HapticFeedback.selectionClick();
                  setState(() => _a.volume = v);
                },
              ),
            ),
            Icon(Icons.volume_up_rounded, color: AppColors.textDim),
          ]),
          Text(
              'Pone el volumen del celular a este nivel mientras suena y lo deja como estaba al apagar.',
              style: TextStyle(fontSize: AppType.caption, color: AppColors.textDim)),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: AppColors.outline),
            ),
            child: Column(children: [
              SwitchListTile(
                title: const Text('Subir el volumen poco a poco',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('Empieza al 40 % y llega al máximo en 30 s',
                    style: TextStyle(color: AppColors.textDim)),
                value: _a.ramp,
                activeTrackColor: AppColors.redBtn,
                onChanged: (v) => setState(() => _a.ramp = v),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              SwitchListTile(
                title: const Text('Tono de respaldo',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                    'Si en 15 s no arranca la música, suena un tono guardado',
                    style: TextStyle(color: AppColors.textDim)),
                value: _a.backup,
                activeTrackColor: AppColors.redBtn,
                onChanged: (v) => setState(() => _a.backup = v),
              ),
              if (_a.backup) ...[
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  minVerticalPadding: 12,
                  leading: Icon(Icons.graphic_eq_rounded,
                      color: AppColors.amber),
                  title: Text(_a.backupPath.isEmpty
                      ? byMode('Riff de rock (incluido)', 'Tono suave (incluido)')
                      : _a.backupLabel),
                  subtitle: Text(
                      _a.backupPath.isEmpty
                          ? 'Toca para usar una canción tuya del celular'
                          : 'Canción tuya · toca para cambiarla',
                      style: TextStyle(color: AppColors.textDim)),
                  trailing: _a.backupPath.isEmpty
                      ? const Icon(Icons.chevron_right_rounded)
                      : IconButton(
                          tooltip: byMode('Volver al riff de rock', 'Volver al tono suave'),
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => setState(() {
                            _a.backupPath = '';
                            _a.backupLabel = '';
                          }),
                        ),
                  onTap: _pickBackupFile,
                ),
              ],
            ]),
          ),
          if (_a.backup && _a.backupPath.isNotEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(4, 8, 4, 0),
              child: Text(
                  byMode('Si la app no alcanza a abrir, igual suena el riff de rock desde el aviso del sistema.', 'Si la app no alcanza a abrir, igual suena el tono suave desde el aviso del sistema.'),
                  style: TextStyle(
                      fontSize: AppType.caption, color: AppColors.textDim)),
            ),
        ],
      ),
    );
  }
}
