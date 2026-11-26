import 'package:flutter/material.dart';

import '../models/song.dart';
import '../services/stats_service.dart';
import '../theme/app_theme.dart';
import '../widgets/player_route.dart';
import '../widgets/section_header.dart';
import 'artist_screen.dart';
import '../services/ai_settings.dart';
import '../widgets/state_views.dart';

/// Lo que más escuchas: artistas y canciones por semana, mes o siempre.
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  int _range = 0; // 0 semana, 1 mes, 2 siempre
  List<PlayEntry> _plays = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _pattern() {
    if (_plays.length < 10) return '';
    var night = 0;
    for (final p in _plays) {
      final h = DateTime.fromMillisecondsSinceEpoch(p.ts * 1000).hour;
      if (h >= 20 || h < 6) night++;
    }
    final pct = (night * 100 / _plays.length).round();
    if (pct >= 60) return 'Escuchas sobre todo de noche ($pct\u00A0%).';
    if (pct <= 30) return 'Escuchas sobre todo de día (${100 - pct}\u00A0%).';
    return 'Escuchas a lo largo de todo el día.';
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Borrar lo aprendido'),
        content: const Text(
            'Se borra el registro de lo que has escuchado (Tus números). Tus favoritos y listas no se tocan.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Borrar')),
        ],
      ),
    );
    if (ok != true) return;
    await StatsService.instance.clear();
    await _load();
  }

  Future<void> _load() async {
    await AiSettings.instance.load();
    setState(() => _loading = true);
    final days = _range == 0 ? 7 : (_range == 1 ? 30 : null);
    final p = await StatsService.instance.plays(days: days);
    if (!mounted) return;
    setState(() {
      _plays = p;
      _loading = false;
    });
  }

  Song _song(PlayEntry p) {
    final s = Song(
        title: p.title,
        artist: p.artist,
        image: p.image,
        query: '${p.artist} ${p.title}');
    return p.videoId.isEmpty ? s : s.withVideoId(p.videoId);
  }

  Widget _bar(String label, int count, int max, {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: AppType.bodySm)),
                ),
                const SizedBox(width: 12),
                Text('$count',
                    style: TextStyle(
                        color: AppColors.textDim,
                        fontFeatures: const [FontFeature.tabularFigures()])),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.xs),
              child: LinearProgressIndicator(
                value: max == 0 ? 0 : count / max,
                minHeight: 6,
                color: AppColors.redText,
                backgroundColor: const Color.fromRGBO(255, 255, 255, 0.08),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final artists = StatsService.topArtists(_plays);
    final songs = StatsService.topSongs(_plays);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Volver',
                    icon: const Icon(Icons.arrow_back_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const PageHeader(
                title: 'Tus números',
                subtitle: 'Lo que más escuchas y lo que la app sabe de tu gusto'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                children: [
                  for (var i = 0; i < 3; i++)
                    ChoiceChip(
                      label: Text(['Semana', 'Mes', 'Siempre'][i]),
                      selected: _range == i,
                      onSelected: (_) {
                        _range = i;
                        _load();
                      },
                    ),
                ],
              ),
            ),
            if (_loading)
              const SkeletonList(count: 6, shrinkWrap: true)
            else if (_plays.isEmpty)
              const StateMessage(
                icon: Icons.insights_rounded,
                title: 'Todavía sin datos',
                message:
                    'No hay canciones en este período. Escucha música y vuelve aquí.',
              )
            else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                // El dato principal, grande; la explicación, debajo.
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${_plays.length}',
                        style: AppType.oswald(48, height: 1.0)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                            '${_plays.length == 1 ? 'escucha' : 'escuchas'} ${['esta semana', 'este mes', 'desde siempre'][_range]}',
                            style: TextStyle(
                                fontSize: AppType.body,
                                color: AppColors.textDim)),
                      ),
                    ),
                  ],
                ),
              ),
              const SectionTitle('Artistas más escuchados'),
              for (final a in artists)
                _bar(a.name, a.count, artists.first.count,
                    onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                            builder: (_) => ArtistScreen(name: a.name)))),
              const SectionTitle('Canciones más escuchadas'),
              for (final s in songs)
                _bar(s.name, s.count, songs.first.count,
                    onTap: s.sample == null
                        ? null
                        : () => playSongs(
                            context, [for (final x in songs) _song(x.sample!)],
                            songs.indexOf(s))),
            ],
            const SizedBox(height: 16),
            // Antes «Tu gusto» era otra pantalla con lo mismo: ahora vive aquí.
            const SectionTitle('Lo que aprende el asistente'),
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              title: const Text('Aprender de lo que escucho'),
              subtitle: Text(
                  'Usa tus escuchas para personalizar listas y mixes. No sale de tu teléfono, salvo nombres de artistas al pedir una lista a la IA.',
                  style: TextStyle(color: AppColors.textDim)),
              value: AiSettings.instance.learn,
              onChanged: (v) async {
                setState(() => AiSettings.instance.learn = v);
                await AiSettings.instance.save();
              },
            ),
            if (_pattern().isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: Row(children: [
                  Icon(Icons.schedule_rounded, size: 18, color: AppColors.textDim),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(_pattern(),
                          style: TextStyle(color: AppColors.textBody))),
                ]),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: _clear,
                  child: Text('Borrar lo aprendido',
                      style: TextStyle(color: AppColors.redText)),
                ),
              ),
            ),

          ],
        ),
      ),
    );
  }
}
