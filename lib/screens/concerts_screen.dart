import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/concert_service.dart';
import '../services/music_mode.dart';
import '../theme/app_theme.dart';
import '../services/radar_service.dart';
import 'prep_screen.dart';

/// Cuadrito con mes y día.
class ConcertDateBox extends StatelessWidget {
  final DateTime? date;
  final double size;
  const ConcertDateBox({super.key, required this.date, this.size = 54});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size * 1.15,
      decoration: BoxDecoration(
        color: AppColors.surfaceWarm,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: date == null
          ? Center(
              child: Text('POR\nCONF.',
                  textAlign: TextAlign.center,
                  textScaler: TextScaler.linear(1.0),
                  style: TextStyle(
                      fontSize: AppType.micro,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                      color: AppColors.redSoft)),
            )
          : Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(kMonthsShort[date!.month - 1].toUpperCase(),
              textScaler: const TextScaler.linear(1.0),
              style: TextStyle(
                  fontSize: AppType.caption,
                  fontWeight: FontWeight.w800,
                  color: AppColors.redSoft)),
          Text('${date!.day}',
              textScaler: const TextScaler.linear(1.0),
              style: TextStyle(
                  fontSize: AppType.title, fontFamily: AppType.head, fontVariations: [FontVariation('wght', 700)], fontWeight: FontWeight.w700, height: 1.1)),
        ],
      ),
    );
  }
}

const String concertTbd = 'Lugar por confirmar';

/// Estilo del lugar: atenuado y en cursiva si está por confirmar.
TextStyle concertPlaceStyle(String place, TextStyle base) =>
    place == concertTbd || place.endsWith('lugar por confirmar')
        ? base.copyWith(color: AppColors.textFaint, fontStyle: FontStyle.italic)
        : base;

String concertPlace(Concert c) {
  String f(String s) => s
      .toLowerCase()
      .replaceAll(RegExp('[áà]'), 'a')
      .replaceAll(RegExp('[éè]'), 'e')
      .replaceAll(RegExp('[íì]'), 'i')
      .replaceAll(RegExp('[óò]'), 'o')
      .replaceAll(RegExp('[úù]'), 'u');
  final v = c.venue.trim(), city = concertCity(c);
  if (v.isEmpty && city.isEmpty) return concertTbd;
  // Ciudad sin lugar: «Bogotá · lugar por confirmar».
  if (v.isEmpty) return '$city · lugar por confirmar';
  // Toque sin cartel: el título ya es el lugar; solo la ciudad.
  if (v.isNotEmpty && f(v) == f(c.band.trim())) return city.isEmpty ? '' : city;
  // La ciudad no se repite si ya va en el nombre del lugar.
  if (v.isNotEmpty && city.isNotEmpty && f(v).contains(f(city))) return v;
  return [v, city].where((e) => e.isNotEmpty).join(' · ');
}

Future<void> openConcertLink(BuildContext context, String url) async {
  final ok = url.isNotEmpty &&
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir el enlace')));
  }
}

/// Lista completa. Al tocar "Escuchar banda" se cierra devolviendo el
/// nombre de la banda para buscarla.
class ConcertsScreen extends StatefulWidget {
  const ConcertsScreen({super.key, this.focusBand});

  /// Abre la pantalla mostrando solo los conciertos de esa banda (el aviso
  /// de Inicio «The Strokes en Bogotá» lleva directo a ese concierto).
  final String? focusBand;

  @override
  State<ConcertsScreen> createState() => _ConcertsScreenState();
}

class _ConcertsScreenState extends State<ConcertsScreen> {
  static const String _mine = 'Tus bandas';
  static const List<String> _cities = [
    _mine,
    'Todas',
    'Bogotá',
    'Medellín',
    'Cali',
    'Bares',
    'Otras'
  ];
  static const List<String> _main = ['bogot', 'medell', 'cali'];
  String _city = 'Todas';

  /// Filtro por género (solo en el modo «Todos los géneros»).
  static const List<String> _genres = [
    'Todos',
    'Mis géneros',
    'Pop',
    'Salsa',
    'Urbano',
    'Vallenato',
    'Rock',
    'Electrónica',
    'Jazz y clásica',
    'Otros',
  ];
  static const Map<String, List<String>> _genreWords = {
    'Pop': ['pop', 'pop latino', 'balada', 'baladas'],
    'Salsa': ['salsa', 'tropical', 'merengue', 'bachata'],
    'Urbano': ['urban', 'regue', 'trap', 'hip', 'rap'],
    'Vallenato': ['vallenato', 'regional', 'popular'],
    'Rock': ['rock', 'metal', 'punk', 'grunge', 'indie', 'alternativ'],
    'Electrónica': ['electrónica', 'electronica', 'house', 'techno', 'edm'],
    'Jazz y clásica': ['jazz', 'clásica', 'clasica', 'sinfónica', 'ópera', 'opera'],
  };
  String _genre = 'Todos';

  /// Tus géneros favoritos (Ajustes) llevados a los grupos del filtro.
  static const Map<String, String> _favMap = {
    'Pop': 'Pop',
    'Pop latino': 'Pop',
    'Baladas': 'Pop',
    'Salsa': 'Salsa',
    'Reguetón': 'Urbano',
    'Vallenato': 'Vallenato',
    'Rock': 'Rock',
    'Electrónica': 'Electrónica',
    'Jazz': 'Jazz y clásica',
    'Clásica': 'Jazz y clásica',
  };

  bool _inGenre(Concert c, String g) {
    if (g == 'Mis géneros') {
      final groups = {
        for (final f in PulsoPrefs.favGenres.value) _favMap[f] ?? f
      };
      return groups.any((x) => _inGenre(c, x));
    }
    final t = c.genre.toLowerCase();
    if (g == 'Otros') {
      return !_genreWords.keys.any((k) => _inGenre(c, k));
    }
    // Palabra completa (o prefijo de palabra): «popular» no es «pop».
    final words = t.split(RegExp(r'[^a-záéíóúñü]+'));
    return (_genreWords[g] ?? const []).any((w) => w.contains(' ')
        ? t.contains(w)
        : words.any((x) => x == w || (w.length >= 5 && x.startsWith(w))));
  }
  final ConcertService _svc = ConcertService.instance;
  List<String> _myBands = const [];

  @override
  void initState() {
    super.initState();
    _focus = widget.focusBand;
    RadarService.instance.bands().then((b) {
      if (mounted) setState(() => _myBands = b);
    });
  }

  String? _mineOf(Concert c) => RadarService.matchBand(c, _myBands);

  static String _daysTo(DateTime? d) {
    if (d == null) return '';
    final now = DateTime.now();
    final n = DateTime(d.year, d.month, d.day)
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;
    if (n < 0) return '';
    return n == 0 ? 'Hoy' : (n == 1 ? 'Mañana' : 'En $n días');
  }

  bool _isMain(String city) {
    final c = city.toLowerCase();
    return _main.any(c.contains);
  }

  String? _focus;

  /// Separa el nombre de la gira entre paréntesis al final.
  static (String, String) _tourSplit(String t) {
    final m = RegExp(r'^(.+?)\s*\(([^()]{6,})\)\s*$').firstMatch(t);
    if (m == null) return (t, '');
    return (m.group(1)!.trim(), m.group(2)!.trim());
  }

  List<Concert> _filter(List<Concert> all) {
    final f = _focus?.toLowerCase();
    if (f != null && f.isNotEmpty) {
      // Palabra completa: «Ghost» no es «Ghostemane».
      final re = RegExp('(^|[^a-záéíóúñü0-9])${RegExp.escape(f)}(\$|[^a-záéíóúñü0-9])');
      final only = all
          .where((c) => !isTribute(c) && re.hasMatch(c.band.toLowerCase()))
          .toList();
      if (only.isNotEmpty) return only;
    }
    if (MusicModeService.general && _genre != 'Todos') {
      all = all.where((c) => _inGenre(c, _genre)).toList();
    }
    if (_city == _mine) return all.where((c) => _mineOf(c) != null).toList();
    if (_city == 'Todas') return all;
    if (_city == 'Bares') return all.where(_svc.isBar).toList();
    if (_city == 'Otras') return all.where((c) => !_isMain(concertCity(c))).toList();
    final k = _city.toLowerCase().substring(0, 4);
    return all.where((c) => concertCity(c).toLowerCase().contains(k)).toList();
  }

  Widget _card(Concert c) {
    final hasTickets = c.tickets.isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ConcertDateBox(date: c.date),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // «The Strokes (Reality Awaits South America 2026)»: la
                  // gira va en una línea aparte, más pequeña.
                  Text(_tourSplit(c.title).$1,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800)),
                  if (_tourSplit(c.title).$2.isNotEmpty)
                    Text(_tourSplit(c.title).$2,
                        style: TextStyle(
                            fontSize: AppType.label,
                            fontStyle: FontStyle.italic,
                            color: AppColors.textDim)),
                  if (c.lineupUnknown)
                    Text('Cartel por anunciar',
                        style: TextStyle(
                            fontSize: 13, color: AppColors.textDim)),
                  if (c.genre.isNotEmpty)
                    Text(c.genre.toUpperCase(),
                        style: TextStyle(
                            fontSize: AppType.caption,
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.w800,
                            color: AppColors.amber)),
                  if (concertPlace(c).isNotEmpty)
                  Text(concertPlace(c),
                      style: concertPlaceStyle(
                          concertPlace(c),
                          TextStyle(
                              fontSize: AppType.bodySm,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textDim))),
                  // «Por confirmar» ya lo dicen la sección y la caja de la
                  // fecha; solo se muestra si hay algo más («Marzo 2027»).
                  if (c.date == null &&
                      c.when.trim().isNotEmpty &&
                      !RegExp(r'confirmar|tbd|tba', caseSensitive: false)
                          .hasMatch(c.when))
                    Text('Fecha: ${c.when}',
                        style: TextStyle(
                            fontSize: AppType.label,
                            fontWeight: FontWeight.w700,
                            color: AppColors.amber))
                  else if (c.time.isNotEmpty)
                    Text(c.time,
                        style: const TextStyle(
                            fontSize: AppType.label, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            // Para conciertos que no son de tus bandas, Calendario y
            // Prepárate van en un ⋮ (tarjeta más liviana).
            if (!c.lineupUnknown && _mineOf(c) == null)
              PopupMenuButton<String>(
                tooltip: 'Más opciones',
                icon: Icon(Icons.more_vert_rounded, color: AppColors.textDim),
                onSelected: (v) {
                  if (v == 'cal') {
                    RadarService.addToCalendar(c).then((ok) {
                      if (!ok && context.mounted) {
                        openConcertLink(context, RadarService.calendarUri(c).toString());
                      }
                    });
                  } else {
                    Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => PrepScreen(band: _bandQuery(c.band), concert: c)));
                  }
                },
                itemBuilder: (_) => [
                  if (c.date != null)
                    const PopupMenuItem(value: 'cal', child: Text('Añadir al calendario')),
                  const PopupMenuItem(value: 'prep', child: Text('Prepárate (setlist)')),
                ],
              ),
          ]),
          const SizedBox(height: 12),
          // Radar: una de tus bandas → cuenta regresiva, calendario y previa.
          if (_mineOf(c) != null) ...[
            const SizedBox(height: 10),
            Row(children: [
              Icon(Icons.radar_rounded, size: 18, color: AppColors.amber),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                    [byMode('Una de tus bandas', 'Uno de tus artistas'), _daysTo(c.date)]
                        .where((e) => e.isNotEmpty)
                        .join(' · '),
                    style: TextStyle(
                        color: AppColors.amber,
                        fontWeight: FontWeight.w800,
                        fontSize: AppType.label)),
              ),
            ]),
          ],
          const SizedBox(height: 8),
          if (!c.lineupUnknown && _mineOf(c) != null)
            Row(children: [
              if (c.date != null) Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                  icon: const Icon(Icons.event_rounded, size: 18),
                  label: const FittedBox(fit: BoxFit.scaleDown, child: Text('Calendario', maxLines: 1)),
                  // Sin fecha exacta no se crea un evento «hoy».
                  onPressed: c.date == null
                      ? null
                      : () async {
                          if (!await RadarService.addToCalendar(c) && context.mounted) {
                            await openConcertLink(
                                context, RadarService.calendarUri(c).toString());
                          }
                        },
                ),
              ),
              if (c.date != null) const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                  icon: const Icon(Icons.queue_music_rounded, size: 18),
                  label: const FittedBox(fit: BoxFit.scaleDown, child: Text('Prepárate', maxLines: 1)),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => PrepScreen(
                          band: _mineOf(c) ?? _bandQuery(c.band), concert: c))),
                ),
              ),
            ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    backgroundColor: AppColors.redBtn),
                onPressed: () => openConcertLink(
                    context, hasTickets ? c.tickets : c.ticketSearchUrl),
                child: FittedBox(fit: BoxFit.scaleDown, child: Text(hasTickets ? 'Boletas' : 'Buscar boletas', maxLines: 1)),
              ),
            ),
            const SizedBox(width: 8),
            if (!c.lineupUnknown) Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                onPressed: () => Navigator.of(context).pop(_bandQuery(c.band)),
                child: FittedBox(fit: BoxFit.scaleDown, child: Text(byMode('Escuchar banda', 'Escuchar artista'), maxLines: 1)),
              ),
            ),
          ]),
          if (c.source.isNotEmpty && c.source != c.tickets) ...[
            const SizedBox(height: 4),
            TextButton(
              style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 48),
                  foregroundColor: AppColors.textFaint),
              onPressed: () => openConcertLink(context, c.source),
              child: Text('Fuente: ${Uri.tryParse(c.source)?.host ?? c.source}',
                  style: const TextStyle(fontSize: AppType.caption)),
            ),
          ],
        ],
      ),
    );
  }

  /// Para festivales "Festival X (Banda A, Banda B)" busca la primera banda.
  static String _bandQuery(String band) {
    final i = band.indexOf('(');
    if (i < 0) return band;
    final inside = band.substring(i + 1).replaceAll(')', '');
    final first = inside.split(',').first.trim();
    return first.isEmpty ? band.substring(0, i).trim() : first;
  }

  Future<void> _editBars() async {
    final ctrl = TextEditingController(text: _svc.bars.join('\n'));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(byMode('Mis bares de rock', 'Mis bares con música en vivo')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                'Uno por línea: nombre del bar y su @usuario de Instagram '
                '(o el enlace del perfil).\n'
                'Ejemplo: ${byMode('Kings Rock @kingsrockbar', 'Café Teatro @cafeteatro')}\n'
                'Con el @usuario y el token de Apify, la app lee sus flyers.',
                style: TextStyle(color: AppColors.textDim, fontSize: AppType.label)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              minLines: 4,
              maxLines: 10,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Nombre del bar @usuario'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Guardar y buscar')),
        ],
      ),
    );
    final text = ctrl.text;
    WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.dispose());
    if (ok != true) return;
    await _svc.saveBars(text.split('\n'));
    if (mounted) setState(() => _city = 'Bares');
    _svc.refresh();
  }

  static String _group(Concert c) {
    final d = c.date;
    if (d == null) return 'FECHA POR CONFIRMAR';
    return '${kMonthsLong[d.month - 1]} ${d.year}'.toUpperCase();
  }

  Widget _genreChips() {
    if (!MusicModeService.general) return const SizedBox.shrink();
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final g in _genres)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(g),
                selected: _genre == g,
                onSelected: (_) => setState(() => _genre = g),
              ),
            ),
        ],
      ),
    );
  }

  Widget _chips() {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final c in _cities)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(c == _mine ? byMode('Tus bandas', 'Tus artistas') : c),
                selected: _city == c,
                showCheckmark: false,
                selectedColor: AppColors.redBtn,
                backgroundColor: AppColors.surface,
                side: BorderSide(color: AppColors.outline),
                labelStyle: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: _city == c ? Colors.white : AppColors.textDim),
                onSelected: (_) => setState(() => _city = c),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: const Text('Conciertos',
            style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          IconButton(
            tooltip: 'Mis bares',
            onPressed: _editBars,
            icon: const Icon(Icons.local_bar_rounded),
          ),
          ValueListenableBuilder<ConcertState>(
            valueListenable: _svc.state,
            builder: (_, s, __) => IconButton(
              tooltip: 'Buscar de nuevo',
              onPressed: s.loading ? null : _svc.refresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ),
        ],
      ),
      body: ValueListenableBuilder<ConcertState>(
        valueListenable: _svc.state,
        builder: (context, s, _) {
          final list = _filter(s.items);
          final status = s.loading
              ? 'Buscando conciertos en internet…'
              : s.noKey
                  ? 'Falta una clave de Gemini o Groq (Ajustes → Inteligencia artificial).'
                  : s.error ?? concertsUpdatedLabel(s.updatedAt);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: Row(children: [
                  if (s.loading) ...[
                    const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text('$status · próximos 12 meses',
                        style: TextStyle(
                            fontSize: AppType.caption,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textFaint)),
                  ),
                ]),
              ),
              if (_focus != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: InputChip(
                    label: Text('Solo $_focus'),
                    onDeleted: () => setState(() => _focus = null),
                    deleteButtonTooltipMessage: 'Ver todos',
                  ),
                )
              else ...[
                _genreChips(),
                _chips(),
              ],
              const SizedBox(height: 10),
              Expanded(
                child: list.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            s.loading
                                ? 'Esto puede tardar hasta un minuto.'
                                : _city == _mine
                                    ? (_myBands.isEmpty
                                        ? 'Escucha música para que sepa cuáles son tus bandas, o sigue a un artista desde su página.'
                                        : 'Ninguna de tus bandas tiene conciertos anunciados en Colombia por ahora. Te aviso cuando aparezca uno.')
                                : _city == 'Bares'
                                    ? 'Todavía no hay toques en tus bares.\n\nPara leer sus flyers de Instagram, toca la copa de arriba y escribe el @usuario de cada bar.'
                                    : 'No hay conciertos encontrados${_city == 'Todas' ? '' : ' en esta ciudad'}.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.textDim),
                          ),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        children: [
                          for (var i = 0; i < list.length; i++) ...[
                            if (i == 0 ||
                                _group(list[i]) != _group(list[i - 1]))
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(4, 8, 4, 10),
                                child: Text(_group(list[i]),
                                    style: TextStyle(
                                        fontSize: AppType.caption,
                                        letterSpacing: 1.5,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.amber)),
                              ),
                            _card(list[i]),
                          ],
                          ValueListenableBuilder<String>(
                            valueListenable: _svc.lastLog,
                            builder: (_, log, __) => log.isEmpty
                                ? const SizedBox.shrink()
                                : ExpansionTile(
                                    tilePadding: EdgeInsets.zero,
                                    title: Text(
                                        'Detalles de la última búsqueda',
                                        style: TextStyle(
                                            fontSize: AppType.label,
                                            color: AppColors.textDim)),
                                    children: [
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: SelectableText(log,
                                            style: TextStyle(
                                                fontSize: AppType.caption,
                                                height: 1.5,
                                                color: AppColors.textFaint)),
                                      ),
                                    ],
                                  ),
                          ),
                          Padding(
                            padding: EdgeInsets.only(top: 4),
                            child: Text(
                              'Datos buscados en internet con IA. Confirma la fecha en la fuente antes de comprar.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: AppType.caption, color: AppColors.textFaint),
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
