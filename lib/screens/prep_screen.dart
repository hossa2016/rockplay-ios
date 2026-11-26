import 'package:flutter/material.dart';

import '../services/concert_service.dart';
import '../services/setlist_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_button.dart';
import '../widgets/player_route.dart';
import '../widgets/section_header.dart';
import 'ai_settings_screen.dart';

/// «Prepárate»: el setlist probable de la banda (setlist.fm) para llegar al
/// concierto sabiéndote las canciones, con la cuenta regresiva.
class PrepScreen extends StatefulWidget {
  final String band;
  final Concert? concert;
  const PrepScreen({super.key, required this.band, this.concert});

  @override
  State<PrepScreen> createState() => _PrepScreenState();
}

class _PrepScreenState extends State<PrepScreen> {
  SetlistResult? _r;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final r = await SetlistService.probable(widget.band);
    if (!mounted) return;
    setState(() {
      _r = r;
      _loading = false;
    });
  }

  String _countdown() {
    final d = widget.concert?.date;
    if (d == null) return '';
    final now = DateTime.now();
    final days = DateTime(d.year, d.month, d.day)
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;
    if (days < 0) return '';
    if (days == 0) {
      final t = widget.concert!.time;
      return t.isEmpty ? 'Hoy es el concierto' : 'Hoy, $t';
    }
    return days == 1 ? 'Mañana' : 'Faltan $days días';
  }

  @override
  Widget build(BuildContext context) {
    final r = _r;
    final cd = _countdown();
    return Scaffold(
      appBar: AppBar(title: AppTitle('Prepárate')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 32),
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: AppPalettes.cards.first),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('SETLIST PROBABLE', style: AppType.overlineOnAccent),
                const SizedBox(height: 6),
                Text(widget.band,
                    style: AppType.oswald(AppType.display)),
                if (cd.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(cd,
                      style: const TextStyle(
                          fontSize: AppType.body, fontWeight: FontWeight.w800)),
                ],
                if (widget.concert != null)
                  Text(
                      [widget.concert!.venue, widget.concert!.city]
                          .where((e) => e.isNotEmpty)
                          .join(' · '),
                      style: const TextStyle(color: Color(0xE6FFFFFF))),
                const SizedBox(height: 14),
                if (r != null && r.songs.isNotEmpty)
                  AppButton.primary(
                    label: 'Reproducir la previa',
                    icon: Icons.play_arrow_rounded,
                    onColor: true,
                    onPressed: () => playSongs(context,
                        SetlistService.toSongs(widget.band, r.songs), 0),
                  ),
              ],
            ),
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (r == null || r.error == 'sin clave')
            _msg(
                'Para armar el setlist probable necesito una clave gratis de setlist.fm.',
                action: 'Poner la clave',
                onTap: () async {
                  await Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => const AiSettingsScreen()));
                  _load();
                })
          else if (r.error.isNotEmpty)
            _msg('No pude consultar setlist.fm (${r.error}).',
                action: 'Reintentar', onTap: _load)
          else if (r.songs.isEmpty)
            _msg('setlist.fm no tiene conciertos recientes de ${widget.band}.')
          else ...[
            SectionTitle('Según sus últimos ${r.shows} conciertos'),
            for (var i = 0; i < r.songs.length; i++)
              ListTile(
                leading: SizedBox(
                  width: 28,
                  child: Text('${i + 1}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: AppColors.textDim, fontWeight: FontWeight.w800)),
                ),
                title: Text(r.songs[i].title,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('${r.songs[i].times} de ${r.shows}',
                    style: TextStyle(color: AppColors.textDim)),
                onTap: () => playSongs(context,
                    SetlistService.toSongs(widget.band, r.songs), i),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Text('Datos de setlist.fm. El concierto real puede cambiar.',
                  style: TextStyle(
                      color: AppColors.textFaint, fontSize: AppType.caption)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _msg(String text, {String? action, VoidCallback? onTap}) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textDim, height: 1.4)),
          if (action != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onTap, child: Text(action)),
          ],
        ]),
      );
}
