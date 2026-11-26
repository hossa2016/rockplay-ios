import 'package:flutter/material.dart';
import '../services/block_service.dart';

import '../services/data_saver.dart';
import '../theme/app_theme.dart';
import '../widgets/section_header.dart';

/// Ajustes de datos y caché.
class DataSettingsScreen extends StatefulWidget {
  const DataSettingsScreen({super.key});

  @override
  State<DataSettingsScreen> createState() => _DataSettingsScreenState();
}

class _DataSettingsScreenState extends State<DataSettingsScreen> {
  final DataSaver _ds = DataSaver.instance;
  int _bytes = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    await _ds.load();
    final b = await _ds.sizeBytes();
    if (mounted) setState(() => _bytes = b);
  }

  Future<void> _apply() async {
    await _ds.save();
    await _ds.prune();
    await _refresh();
  }

  String _size(int b) {
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
    return '${(b / (1024 * 1024)).toStringAsFixed(1).replaceAll('.', ',')} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: AppTitle('Almacenamiento')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: AppColors.outline),
            ),
            child: Row(children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text('En uso: ${_size(_bytes)}',
                      maxLines: 1,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: AppType.body)),
                ),
              ),
              OutlinedButton(
                onPressed: () async {
                  await _ds.clear();
                  await _refresh();
                },
                child: const Text('Borrar caché'),
              ),
            ]),
          ),
          const SizedBox(height: 14),
          Text(
            'El caché guarda portadas y datos de artistas en tu teléfono para no '
            'bajarlos otra vez. No guarda música.',
            style: TextStyle(color: AppColors.textDim, height: 1.4),
          ),
          const SizedBox(height: 16),
          // Un solo control: cuánto espacio puede usar (antes eran 4 modos).
          Text('Espacio para guardar',
              style: const TextStyle(
                  fontWeight: FontWeight.w800, fontSize: AppType.body)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Nada'),
                selected: _ds.mode == CacheMode.off,
                onSelected: (_) {
                  setState(() => _ds.mode = CacheMode.off);
                  _apply();
                },
              ),
              for (final mb in DataSaver.limitsMb)
                ChoiceChip(
                  label: Text(mb >= 1000 ? '1 GB' : '$mb MB'),
                  selected: (_ds.mode == CacheMode.limit ||
                          _ds.mode == CacheMode.favorites) &&
                      _ds.limitMb == mb,
                  onSelected: (_) {
                    setState(() {
                      _ds.mode = CacheMode.limit;
                      _ds.limitMb = mb;
                    });
                    _apply();
                  },
                ),
              ChoiceChip(
                label: const Text('Sin límite'),
                selected: _ds.mode == CacheMode.unlimited,
                onSelected: (_) {
                  setState(() => _ds.mode = CacheMode.unlimited);
                  _apply();
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('Cuando se llena, borra lo más viejo.',
              style: TextStyle(color: AppColors.textDim, fontSize: AppType.caption)),
          const SizedBox(height: 18),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            title: const Text('Con datos móviles, no bajar portadas nuevas',
                style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(
                'Las que ya están guardadas sí se ven. Las nuevas esperan al WiFi.',
                style: TextStyle(color: AppColors.textDim)),
            value: _ds.noMobileImages,
            onChanged: (v) {
              setState(() => _ds.noMobileImages = v);
              _apply();
            },
          ),
          const SizedBox(height: 10),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.bug_report_outlined),
            title: const Text('Registro de canciones saltadas'),
            subtitle: Text('Motivo técnico de las últimas canciones que no sonaron.',
                style: TextStyle(color: AppColors.textDim, fontSize: AppType.caption)),
            onTap: () => showDialog<void>(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text('Canciones saltadas'),
                content: SizedBox(
                  width: double.maxFinite,
                  child: SkipLog.entries.isEmpty
                      ? const Text('Todavía no se ha saltado ninguna.')
                      : ListView(
                          shrinkWrap: true,
                          children: [
                            for (final e in SkipLog.entries)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Text(e, style: const TextStyle(fontSize: AppType.caption)),
                              ),
                          ],
                        ),
                ),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text('Cerrar')),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
