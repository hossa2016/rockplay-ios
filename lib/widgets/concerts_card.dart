import 'package:flutter/material.dart';

import '../screens/concerts_screen.dart';
import '../services/concert_service.dart';
import '../services/music_mode.dart';
import '../theme/app_theme.dart';

/// Tarjeta de Inicio con los próximos conciertos. Al tocarla abre la lista
/// completa. [onListen] recibe la banda cuando eliges «Escuchar banda».
class ConcertsCard extends StatefulWidget {
  final ValueChanged<String> onListen;
  const ConcertsCard({super.key, required this.onListen});

  @override
  State<ConcertsCard> createState() => _ConcertsCardState();
}

class _ConcertsCardState extends State<ConcertsCard> {
  @override
  void initState() {
    super.initState();
    ConcertService.instance.ensureLoaded();
  }

  Future<void> _open() async {
    final band = await Navigator.of(context).push<String>(
        MaterialPageRoute<String>(builder: (_) => const ConcertsScreen()));
    if (band != null && band.isNotEmpty && mounted) widget.onListen(band);
  }

  /// Toques de un bar que aún no publica quién toca, en una sola fila.
  Widget _venueRow(_Venue v) {
    final c = v.items.first;
    final days = v.items
        .where((e) => e.date != null)
        .map((e) => e.date!.day)
        .toSet()
        .toList()
      ..sort();
    const m = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
    final when = days.isEmpty || c.date == null
        ? ''
        : '${days.length == 1 ? days.first : '${days.sublist(0, days.length - 1).join(', ')} y ${days.last}'} ${m[c.date!.month - 1]}';
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.md),
      child: Row(children: [
        ConcertDateBox(date: c.date, size: 46),
        const SizedBox(width: AppSpace.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(c.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: AppType.body, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(
                  [c.city, when, 'Cartel por anunciar']
                      .where((e) => e.isNotEmpty)
                      .join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: AppType.label,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textDim)),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _row(Concert c) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.md),
      child: Row(children: [
        ConcertDateBox(date: c.date, size: 46),
        const SizedBox(width: AppSpace.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(c.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: AppType.body, fontWeight: FontWeight.w800)),
              if (isTribute(c))
                Text('TRIBUTO',
                    style: TextStyle(
                        fontSize: AppType.caption,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w800,
                        color: AppColors.amber)),
              if (concertPlace(c).isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(concertPlace(c),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: concertPlaceStyle(
                        concertPlace(c),
                        TextStyle(
                            fontSize: AppType.label,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textDim))),
              ],
            ],
          ),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ConcertState>(
      valueListenable: ConcertService.instance.state,
      builder: (context, s, _) {
        // Primero los que dicen quién toca; los toques sin cartel del mismo
        // bar se juntan en una sola fila.
        // Las bandas reales antes que los tributos («Tributo a Queen»).
        final named = [
          ...s.items.where((c) => !c.lineupUnknown && !isTribute(c)),
          ...s.items.where((c) => !c.lineupUnknown && isTribute(c)),
        ];
        final unknown = s.items.where((c) => c.lineupUnknown).toList();
        final items = named.take(3).toList();
        _Venue? venueRow;
        if (items.length < 3 && unknown.isNotEmpty) {
          final v = unknown.first.venue;
          final same = unknown.where((c) => c.venue == v).toList();
          venueRow = _Venue(same);
        }
        String? msg;
        if (items.isEmpty && venueRow == null) {
          if (s.loading) {
            msg = byMode('Buscando conciertos de rock en Colombia…', 'Buscando conciertos en Colombia…');
          } else if (s.noKey) {
            msg =
                'Para ver conciertos, pon tu clave gratis en Ajustes → Inteligencia artificial.';
          } else if (s.error != null) {
            msg = s.error;
          } else {
            msg = 'No se encontraron conciertos en los próximos 12 meses.';
          }
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
          child: Material(
            color: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.xl),
              side: BorderSide(color: AppColors.borderAccent),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: _open,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpace.xl, AppSpace.lg, AppSpace.md, AppSpace.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(Icons.confirmation_number_outlined,
                          color: AppColors.amber, size: 20),
                      const SizedBox(width: AppSpace.sm),
                      Expanded(
                        child: Text('PRÓXIMOS CONCIERTOS',
                            style: AppType.overline),
                      ),
                      if (s.loading)
                        const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                      else
                        Icon(Icons.chevron_right_rounded,
                            color: AppColors.textDim),
                    ]),
                    if (msg != null)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpace.md),
                        child: Text(msg,
                            style: TextStyle(
                                fontSize: AppType.bodySm,
                                height: 1.35,
                                color: AppColors.textDim)),
                      )
                    else
                    ...[
                      for (final c in items) _row(c),
                      if (venueRow != null) _venueRow(venueRow),
                    ],
                    const SizedBox(height: AppSpace.md),
                    // «Ver todos ›» se ve como enlace; la fecha, aparte.
                    Row(children: [
                      Text(
                          items.isEmpty && venueRow == null
                              ? 'Ver todos y tus bares ›'
                              : 'Ver todos ›',
                          style: const TextStyle(
                              fontSize: AppType.label,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textBody)),
                      const Spacer(),
                      if (items.isNotEmpty || venueRow != null)
                        Text(concertsUpdatedLabel(s.updatedAt),
                            style: TextStyle(
                                fontSize: AppType.caption,
                                color: AppColors.textDim)),
                      const SizedBox(width: AppSpace.sm),
                    ]),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Venue {
  final List<Concert> items;
  _Venue(this.items);
}
