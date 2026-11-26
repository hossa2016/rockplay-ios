import 'package:flutter/material.dart';

import '../models/song.dart';
import '../services/playback_service.dart';
import '../services/radio_service.dart';
import '../services/music_mode.dart';
import '../theme/app_theme.dart';
import '../widgets/mini_player.dart';
import '../widgets/playback_ui.dart';
import '../widgets/section_header.dart';
import '../widgets/player_route.dart';
import '../widgets/state_views.dart';

/// Logo de emisora con placeholder (inicial en ámbar) si falta o falla.
class StationLogo extends StatelessWidget {
  final RadioStation station;
  final double size;
  final double radius;
  const StationLogo(
      {super.key, required this.station, this.size = 48, this.radius = 10});

  Widget _placeholder() {
    final c = station.name.trim().isEmpty
        ? '♪'
        : String.fromCharCode(station.name.trim().runes.first).toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2A2A34), Color(0xFF14141A)],
        ),
      ),
      child: Text(c,
          style: TextStyle(
              fontSize: size * 0.42,
              fontWeight: FontWeight.w900,
              color: AppColors.amber)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (station.favicon.isEmpty) return _placeholder();
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.network(
        station.favicon,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(),
        loadingBuilder: (c, child, p) => p == null ? child : _placeholder(),
      ),
    );
  }
}

/// ¿Está sonando esta emisora ahora?
bool stationIsCurrent(RadioStation s) =>
    PlaybackUi.instance.song.value?.query == 'radio:${s.id}';

/// Cola de canciones que sonaba antes de poner la radio, para volver a ella.
class SongQueueMemory {
  SongQueueMemory._();
  static final ValueNotifier<List<Song>?> queue =
      ValueNotifier<List<Song>?>(null);
  static int index = 0;
  static Duration position = Duration.zero;

  static void saveIfSongs() {
    final pb = PlaybackUi.instance;
    final cur = pb.song.value;
    final q = pb.queue.value;
    if (cur == null || cur.isRadio || q.isEmpty) return;
    queue.value = List<Song>.of(q);
    index = (pb.index.value ?? 0).clamp(0, q.length - 1);
    position = pb.position.value;
  }

  static Future<void> resume() async {
    final q = queue.value;
    if (q == null || q.isEmpty) return;
    queue.value = null;
    await PlaybackService.instance.playQueue(q, index);
    if (position > const Duration(seconds: 5)) {
      await PlaybackService.instance.seek(position);
    }
  }
}

void playStation(BuildContext context, RadioStation s) {
  SongQueueMemory.saveIfSongs();
  RadioService.instance.setLast(s);
  playSongs(context, [s.toSong()], 0);
}

class RadioScreen extends StatefulWidget {
  /// true = va dentro de la pestaña Buscar (sin barra ni mini player propios).
  final bool embedded;
  const RadioScreen({super.key, this.embedded = false});

  @override
  State<RadioScreen> createState() => _RadioScreenState();
}

class _RadioScreenState extends State<RadioScreen> {
  final RadioService _svc = RadioService.instance;
  final TextEditingController _q = TextEditingController();
  List<RadioStation> _saved = [];
  List<RadioStation> _results = [];
  bool _colombia = true;
  bool _loading = true;
  bool _offline = false;
  String _lastQuery = '';

  @override
  void initState() {
    super.initState();
    _svc.revision.addListener(_loadSaved);
    _loadSaved();
    _search();
  }

  @override
  void dispose() {
    _svc.revision.removeListener(_loadSaved);
    _q.dispose();
    super.dispose();
  }

  Future<void> _loadSaved() async {
    final s = await _svc.saved();
    if (mounted) setState(() => _saved = s);
  }

  Future<void> _search() async {
    final query = _q.text.trim();
    setState(() {
      _loading = true;
      _offline = false;
      _lastQuery = query;
    });
    try {
      final r = await _svc.search(query, colombiaOnly: _colombia);
      if (!mounted || query != _lastQuery) return;
      setState(() {
        _results = r;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _results = [];
        _loading = false;
        _offline = true;
      });
    }
  }

  Future<void> _toggleSave(RadioStation s, bool saved) async {
    if (saved) {
      await _svc.remove(s.id);
    } else {
      await _svc.save(s);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        persist: false,
        duration: const Duration(seconds: 3),
        content: Text(saved ? 'Quitada de tus emisoras' : 'Guardada'),
        action: SnackBarAction(
          label: 'Deshacer',
          onPressed: () => saved ? _svc.save(s) : _svc.remove(s.id),
        ),
      ));
  }

  Future<void> _addByLink() async {
    final r = await showModalBottomSheet<RadioStation>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
      builder: (_) => const _AddSheet(),
    );
    if (r != null) {
      await _svc.save(r);
      if (mounted) playStation(context, r);
    }
  }

  Widget _tile(RadioStation s) {
    final saved = _saved.any((x) => x.id == s.id);
    return ListenableBuilder(
      listenable: Listenable.merge(
          [PlaybackUi.instance.song, PlaybackUi.instance.playing]),
      builder: (context, _) {
        final current = stationIsCurrent(s);
        final playing = current && PlaybackUi.instance.playing.value;
        final failed = current &&
            (PlaybackUi.instance.error.value ?? '').contains('emisora');
        // TalkBack: la tarjeta es un botón «reproducir» con nombre limpio; el
        // botón de guardar sigue accesible por separado.
        return Semantics(
          container: true,
          button: true,
          label: '${s.shortName}, ${s.subtitle}${playing ? ', sonando' : ''}',
          onTapHint: 'reproducir',
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            decoration: BoxDecoration(
              color: current ? AppColors.surfaceHigh : AppColors.surface,
              border: Border.all(
                  color: current || failed ? AppColors.red : AppColors.outline,
                  width: current ? 1.5 : 1),
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              onTap: () => playStation(context, s),
              // Alto mínimo (no fijo): con nombres de 2 líneas el
              // subtítulo ya no se sale de la tarjeta.
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 72),
                child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    const SizedBox(width: 12),
                    ExcludeSemantics(child: Stack(
                      alignment: Alignment.center,
                      children: [
                        StationLogo(station: s),
                        if (playing)
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: const Color.fromRGBO(0, 0, 0, 0.55),
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                            ),
                            child: Icon(Icons.graphic_eq_rounded,
                                color: AppColors.amber),
                          ),
                      ],
                    )),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ExcludeSemantics(child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.shortName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: AppType.body,
                                  fontWeight: FontWeight.w700,
                                  color: current
                                      ? AppColors.redText
                                      : AppColors.text)),
                          const SizedBox(height: 2),
                          Text(
                              failed
                                  ? 'No se pudo reproducir · toca para reintentar'
                                  : (current ? 'EN VIVO' : s.subtitle),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: AppType.caption,
                                  color: failed
                                      ? AppColors.amber
                                      : AppColors.textDim)),
                        ],
                      )),
                    ),
                    IconButton(
                      tooltip: saved
                          ? 'Quitar de mis emisoras'
                          : 'Guardar en mis emisoras',
                      icon: Icon(
                          saved
                              ? Icons.bookmark_rounded
                              : Icons.bookmark_border_rounded,
                          color: saved ? AppColors.amber : AppColors.textDim),
                      onPressed: () => _toggleSave(s, saved),
                    ),
                  ],
                ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _label(String t) => SectionTitle(t);

  @override
  Widget build(BuildContext context) {
    final list = _body();
    if (widget.embedded) return list;
    // Pantalla suelta (por si se abre fuera de Buscar).
    return Scaffold(
      appBar: AppBar(title: AppTitle('Radio en vivo')),
      bottomNavigationBar: const MiniPlayer(),
      body: list,
    );
  }

  Widget _body() {
    final savedIds = {for (final s in _saved) s.id};
    final shown = [for (final s in _results) if (!savedIds.contains(s.id)) s];
    return ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 4, 0),
            child: Row(children: [
              Expanded(
                child: TextField(
              controller: _q,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                hintText: 'Buscar emisora',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _q.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Limpiar',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _q.clear();
                          _search();
                        },
                      ),
              ),
              onChanged: (_) => setState(() {}),
                ),
              ),
              // Acción visible en vez de un ⋮ que no decía qué tenía.
              IconButton(
                tooltip: 'Agregar emisora por enlace',
                icon: const Icon(Icons.add_link_rounded),
                onPressed: _addByLink,
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Dense(child: SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: true, label: Text('Colombia')),
                ButtonSegment(value: false, label: Text('Mundo')),
              ],
              selected: {_colombia},
              onSelectionChanged: (v) {
                setState(() => _colombia = v.first);
                _search();
              },
            )),
          ),
          if (_saved.isNotEmpty) ...[
            _label('MIS EMISORAS'),
            for (final s in _saved) _tile(s),
          ],
          _label(_lastQuery.isEmpty
              ? (_colombia ? 'Populares en Colombia' : byMode('Rock en el mundo', 'Populares en el mundo'))
              : 'RESULTADOS'),
          if (_loading)
            const SkeletonList(count: 5, shrinkWrap: true)
          else if (_offline)
            StateMessage(
              icon: Icons.cloud_off_rounded,
              title: 'Sin conexión con el directorio',
              message: 'Tus emisoras guardadas siguen funcionando.',
              actionLabel: 'Reintentar',
              onAction: _search,
              isError: true,
            )
          else if (shown.isEmpty)
            StateMessage(
              icon: Icons.search_off_rounded,
              title: _lastQuery.isEmpty
                  ? 'No hay emisoras para mostrar'
                  : 'Sin resultados para «$_lastQuery»',
              message: 'Prueba otro nombre o cambia a Mundo.',
            )
          else
            for (final s in shown) _tile(s),
        ],
    );
  }
}

class _AddSheet extends StatefulWidget {
  const _AddSheet();

  @override
  State<_AddSheet> createState() => _AddSheetState();
}

class _AddSheetState extends State<_AddSheet> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _url = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  String? get _nameErr {
    if (_name.text.isEmpty) return null;
    if (_name.text.trim().length > 40) return 'Máximo 40 letras';
    return null;
  }

  String? get _urlErr {
    final u = _url.text.trim();
    if (u.isEmpty) return null;
    if (!(u.startsWith('http://') || u.startsWith('https://'))) {
      return 'Debe empezar con http:// o https://';
    }
    return null;
  }

  bool get _valid =>
      _name.text.trim().isNotEmpty &&
      _name.text.trim().length <= 40 &&
      _url.text.trim().isNotEmpty &&
      _urlErr == null;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Agregar emisora',
              style: TextStyle(fontSize: AppType.titleSm, fontWeight: FontWeight.w900)),
          const SizedBox(height: 14),
          TextField(
            controller: _name,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
                labelText: 'Nombre', errorText: _nameErr),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            autocorrect: false,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
                labelText: 'Enlace de la transmisión',
                hintText: 'https://…',
                errorText: _urlErr),
          ),
          Padding(
            padding: EdgeInsets.only(top: 8, bottom: 14),
            child: Text(
                'Pega el enlace directo del audio (suele estar en la web de la emisora).',
                style: TextStyle(color: AppColors.textDim, fontSize: AppType.caption)),
          ),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _valid
                  ? () => Navigator.pop(context,
                      RadioService.instance.custom(_name.text, _url.text))
                  : null,
              child: const Text('Guardar y escuchar'),
            ),
          ),
        ],
      ),
    );
  }
}
