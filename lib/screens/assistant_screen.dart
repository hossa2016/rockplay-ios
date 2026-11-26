import 'package:flutter/material.dart';

import '../widgets/undo.dart';
import '../widgets/section_header.dart';

import '../models/song.dart';
import '../services/ai_client.dart';
import '../services/ai_settings.dart';
import '../services/assistant_service.dart';
import '../services/deezer_service.dart';
import '../widgets/cover_art.dart';
import '../services/playlist_service.dart';
import '../services/music_mode.dart';
import '../theme/app_theme.dart';
import '../widgets/player_route.dart';
import '../widgets/playback_ui.dart';
import 'ai_settings_screen.dart';
import 'song_list_screen.dart';
import '../widgets/tip_card.dart';
import '../services/dj_voice.dart';

class _Msg {
  final bool fromUser;
  final String text;
  final AssistantResult? result;
  _Msg(this.fromUser, this.text, [this.result]);
}

/// Pide al asistente algo desde fuera (ej. la tarjeta de Inicio).
final ValueNotifier<String?> assistantWantPrompt = ValueNotifier<String?>(null);

/// Chat con el asistente: pide listas por ánimo o con tus propias palabras.
class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  static List<String> get _tweaks => [
    'Más tranquilo',
    byMode('Más pesado', 'Más movido'),
    'Solo en español',
    'Más canciones nuevas',
  ];

  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<_Msg> _msgs = [];
  bool _busy = false;
  bool _noKeys = false;

  void _wantPrompt() {
    final p = assistantWantPrompt.value;
    if (p == null || p.isEmpty) return;
    assistantWantPrompt.value = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _send(p);
    });
  }

  @override
  void initState() {
    super.initState();
    assistantWantPrompt.addListener(_wantPrompt);
    AiSettings.instance.load().then((_) {
      final s = AiSettings.instance;
      if (mounted) {
        setState(() =>
            _noKeys = s.groqKey.trim().isEmpty && s.geminiKey.trim().isEmpty);
      }
    });
  }

  @override
  void dispose() {
    assistantWantPrompt.removeListener(_wantPrompt);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent + 200,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _send(String text) async {
    final t = text.trim();
    if (t.isEmpty || _busy) return;
    FocusScope.of(context).unfocus();
    final history = [
      for (final m in _msgs)
        AiMessage(m.fromUser, m.fromUser ? m.text : _summary(m)),
    ];
    setState(() {
      _msgs.add(_Msg(true, t));
      _busy = true;
      _input.clear();
    });
    _toBottom();
    AssistantResult r;
    try {
      r = await AssistantService.instance.ask(t, history);
    } catch (_) {
      r = const AssistantResult(
          'No pude armar la lista ahora. Revisa tu conexión e inténtalo de nuevo.',
          '',
          <Song>[],
          'Reglas simples');
    }
    if (!mounted) return;
    setState(() {
      _msgs.add(_Msg(false, r.reply, r));
      _busy = false;
    });
    _toBottom();
    _loadCovers(r);
    // Si la IA trajo bastante menos del máximo, pide un lote más.
    final mx = AiSettings.instance.maxSongs;
    if ((r.source == 'Gemini' || r.source == 'Groq') &&
        r.songs.length >= 3 &&
        mx >= 60 &&
        r.songs.length < mx * 0.8) {
      await _expand(r);
    }
  }

  final Set<AssistantResult> _covering = {};

  /// Busca las portadas reales de toda la lista, una por una (Deezer limita
  /// el ritmo de peticiones).
  Future<void> _loadCovers(AssistantResult r) async {
    if (!_covering.add(r)) return;
    final dz = DeezerService();
    try {
      for (var i = 0; i < r.songs.length; i++) {
        if (!mounted) return;
        final s = r.songs[i];
        if (s.image.isNotEmpty) continue;
        try {
          final c = await dz.coverForTrack(s.artist, s.title);
          if (c.isNotEmpty) {
            r.songs[i] = Song(
              title: s.title,
              artist: s.artist,
              album: s.album,
              image: c,
              url: s.url,
              videoId: s.videoId,
              query: s.query,
            );
            if (mounted && (i < 8 || i % 5 == 0)) setState(() {});
          }
        } catch (_) {}
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      if (mounted) setState(() {});
    } finally {
      _covering.remove(r);
    }
  }

  /// Resumen de la respuesta anterior para que la IA tenga contexto.
  String _summary(_Msg m) {
    final r = m.result;
    if (r == null || r.songs.isEmpty) return m.text;
    final names = r.songs.take(10).map((s) => '${s.artist} - ${s.title}');
    return '${m.text} Lista "${r.title}": ${names.join('; ')}';
  }

  Future<void> _save(AssistantResult r) async {
    final p = await PlaylistService.instance.create(r.title);
    await PlaylistService.instance.addMany(p.id, r.songs);
    PlaybackUi.instance.bumpLibrary();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            duration: const Duration(seconds: 3),
            content: Text('Guardada como "${p.name}" en Mi música.')));
  }

  void _close(_Msg m) {
    final i = _msgs.indexOf(m);
    if (i < 0) return;
    _Msg? q;
    setState(() {
      _msgs.removeAt(i);
      if (i - 1 >= 0 && _msgs[i - 1].fromUser) q = _msgs.removeAt(i - 1);
    });
    final at = q != null ? i - 1 : i;
    final mm = ScaffoldMessenger.of(context);
    mm.clearSnackBars();
    mm.showSnackBar(SnackBar(
      duration: const Duration(seconds: 4),
      persist: false,
      content: const Text('Lista descartada'),
      action: SnackBarAction(
        label: 'Deshacer',
        onPressed: () {
          if (!mounted) return;
          setState(() {
            final pos = at.clamp(0, _msgs.length);
            if (q != null) {
              _msgs.insert(pos, q!);
              _msgs.insert(pos + 1, m);
            } else {
              _msgs.insert(pos, m);
            }
          });
        },
      ),
    ));
  }

  Future<void> _expand(AssistantResult cur) async {
    if (_busy) return;
    setState(() => _busy = true);
    _toBottom();
    try {
      final mx = AiSettings.instance.maxSongs;
      final room = mx - cur.songs.length;
      if (room <= 0) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      final r = await AssistantService.instance.ask(
          'Amplía la lista "${cur.title}" con ${room > 50 ? 50 : room} canciones más, distintas a las '
              'que ya tienes: ${cur.songs.take(40).map((s) => '${s.artist} - ${s.title}').join('; ')}',
          const <AiMessage>[]);
      final seen = {
        for (final s in cur.songs) '${s.artist}|${s.title}'.toLowerCase()
      };
      var added = 0;
      for (final s in r.songs) {
        if (cur.songs.length >= mx) break;
        if (seen.add('${s.artist}|${s.title}'.toLowerCase())) {
          cur.songs.add(s);
          added++;
        }
      }
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: const Duration(seconds: 3),
          content: Text(added > 0
              ? 'Se agregaron $added canciones (${cur.songs.length} en total).'
              : 'No encontré más canciones nuevas.')));
      _loadCovers(cur);
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _chip(String label, VoidCallback onTap) => Material(
        color: AppColors.surfaceHigh,
        shape: StadiumBorder(side: BorderSide(color: AppColors.outline)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: _busy ? null : onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                widthFactor: 1,
                child: Text(label,
                    style: const TextStyle(
                        fontSize: AppType.bodySm, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ),
      );

  /// Aviso claro cuando la IA no respondió (cuota gratis agotada o error)
  /// y la lista salió con reglas simples.
  Widget _quotaBanner(String detail) {
    final quota = detail.contains('límite');
    return Container(
      margin: const EdgeInsets.only(top: AppSpace.sm),
      padding: const EdgeInsets.fromLTRB(
          AppSpace.md, AppSpace.md, AppSpace.md, AppSpace.md),
      decoration: BoxDecoration(
        color: AppColors.amberTint,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.amberLine),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.info_outline_rounded,
            color: AppColors.amber, size: 20),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Text(
            quota
                ? 'Se acabó tu cuota gratis de IA por hoy, así que usé reglas simples. Mañana vuelve a pensar con IA.'
                : 'La IA no respondió esta vez, así que usé reglas simples. Prueba de nuevo en un rato.',
            style: TextStyle(
                fontSize: AppType.label,
                height: 1.35,
                color: AppColors.amber),
          ),
        ),
      ]),
    );
  }

  /// Convierte notas técnicas («Gemini: error 503») en algo entendible.
  /// La nota puede traer varias partes separadas por « · ».
  static String _humanNote(String note, String source) {
    final rules = source.isEmpty || source.toLowerCase().contains('regla');
    final other = rules ? 'reglas simples' : source;
    final parts = <String>{};
    for (final raw in note.split(RegExp(r'\s+·\s+|;\s*'))) {
      final n = raw.toLowerCase().trim();
      if (n.isEmpty) continue;
      if (n.contains('lanzamiento')) {
        parts.add('No pude consultar los lanzamientos ahora.');
        continue;
      }
      final who = n.startsWith('groq')
          ? 'Groq'
          : n.startsWith('gemini')
              ? 'Gemini'
              : 'La IA';
      if (n.contains('límite') || n.contains('limite') || n.contains('429') || n.contains('quota')) {
        parts.add('$who llegó a su límite gratis de hoy.');
      } else if (n.contains('503') || n.contains('500') || n.contains('overload')) {
        parts.add('$who estaba saturado en este momento.');
      } else if (n.contains('conexi') || n.contains('socket') || n.contains('internet')) {
        parts.add('No había conexión estable con $who.');
      } else {
        parts.add('$who no respondió bien.');
      }
    }
    if (parts.isEmpty) return note;
    return '${parts.join(' ')} Armé la lista con $other.';
  }

  Widget _infoBanner(String text) => Container(
        margin: const EdgeInsets.only(top: AppSpace.sm),
        padding: const EdgeInsets.all(AppSpace.md),
        decoration: BoxDecoration(
          color: AppColors.amberTint,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.amberLine),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info_outline_rounded,
              color: AppColors.amber, size: 20),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    fontSize: AppType.label,
                    height: 1.35,
                    color: AppColors.amber)),
          ),
        ]),
      );

  void _clearChat() {
    final old = List<_Msg>.of(_msgs);
    setState(() => _msgs.clear());
    showUndo(context, 'Conversación borrada', () {
      if (mounted) setState(() => _msgs..clear()..addAll(old));
    });
  }

  Widget _avatar(double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
            shape: BoxShape.circle, gradient: AppColors.accent),
        child: Icon(Icons.auto_awesome_rounded,
            color: Colors.white, size: size * 0.5),
      );

  Widget _bubble(_Msg m, bool last) {
    final r = m.result;
    final user = m.fromUser;
    final box = Container(
      constraints: const BoxConstraints(maxWidth: 300),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: user
            ? AppColors.accent
            : null,
        color: user ? null : AppColors.surface,
        border: user ? null : Border.all(color: AppColors.outline),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(AppRadius.lg),
          topRight: const Radius.circular(AppRadius.lg),
          bottomLeft: Radius.circular(user ? AppRadius.lg : AppRadius.xs),
          bottomRight: Radius.circular(user ? AppRadius.xs : AppRadius.lg),
        ),
      ),
      child: Text(m.text, style: const TextStyle(fontSize: AppType.body, height: 1.45)),
    );
    if (user) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Align(alignment: Alignment.centerRight, child: box),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _avatar(32),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Align(alignment: Alignment.centerLeft, child: box),
                if (r != null && r.songs.isNotEmpty) _playlistCard(r, () => _close(m)),
                if (r != null && r.source == 'Reglas simples' && !_noKeys)
                  _quotaBanner(r.note ?? ''),
                if (r != null && r.note != null && r.source != 'Reglas simples')
                  _infoBanner(_humanNote(r.note!, r.source)),
                if (r != null && last && r.songs.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Dense(
                      max: 1.15,
                      child: Wrap(spacing: 8, runSpacing: 8, children: [
                        _chip('Ampliar a ${AiSettings.instance.maxSongs}', () => _expand(r)),
                        for (final t in _tweaks) _chip(t, () => _send(t)),
                      ]),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static List<List<Color>> get _grads => AppPalettes.cards;

  BoxDecoration _grad(int i) => BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _grads[i % _grads.length],
        ),
      );

  Widget _mosaic(double size, List<Song> songs) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: SizedBox(
        width: size,
        height: size,
        child: Column(children: [
          for (var r = 0; r < 2; r++)
            Expanded(
              child: Row(children: [
                for (var c = 0; c < 2; c++)
                  Expanded(
                    child: Container(
                        margin: EdgeInsets.only(
                            right: c == 0 ? 1 : 0, bottom: r == 0 ? 1 : 0),
                        decoration: _grad(r * 2 + c),
                        child: (r * 2 + c) < songs.length &&
                                songs[r * 2 + c].image.isNotEmpty
                            ? CoverArt(
                                url: songs[r * 2 + c].image,
                                radius: 0,
                                seed: songs[r * 2 + c].artist)
                            : null),
                  ),
              ]),
            ),
        ]),
      ),
    );
  }

  Widget _playlistCard(AssistantResult r, VoidCallback onClose) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.outline),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            _mosaic(68, r.songs),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 3),
                  Text('${r.songs.length} canciones',
                      style: TextStyle(
                          color: AppColors.textDim, fontSize: AppType.caption)),
                  const SizedBox(height: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceHigh,
                      border: Border.all(color: AppColors.outline),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(r.source,
                        style: TextStyle(
                            fontSize: AppType.caption,
                            fontWeight: FontWeight.w700,
                            color: AppColors.amber)),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Cerrar lista',
              onPressed: onClose,
              icon: Icon(Icons.close_rounded,
                  color: AppColors.textDim, size: 22),
            ),
          ]),
          const SizedBox(height: 8),
          for (var i = 0; i < r.songs.length && i < 3; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                SizedBox(
                  width: 40,
                  height: 40,
                  child: CoverArt(
                      url: r.songs[i].image,
                      radius: AppRadius.sm,
                      seed: r.songs[i].artist),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.songs[i].title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: AppType.bodySm)),
                        Text(r.songs[i].artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: AppColors.textDim, fontSize: AppType.caption)),
                      ]),
                ),
              ]),
            ),
          if (r.songs.length > 3)
            InkWell(
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => SongListScreen(
                        title: r.title,
                        subtitle: '${r.songs.length} canciones',
                        songs: r.songs,
                        emptyMessage: 'Lista vacía.',
                      ))),
              child: Container(
                height: 48,
                alignment: Alignment.centerLeft,
                child: Text('Ver las ${r.songs.length - 3} restantes',
                    style: TextStyle(
                        color: AppColors.amber,
                        fontSize: AppType.label,
                        fontWeight: FontWeight.w700)),
              ),
            ),
          const SizedBox(height: 8),
          // Principal arriba a lo ancho; secundarios en dos columnas: con
          // letra grande nada queda cortado.
          Dense(
            max: 1.15,
            child: Column(children: [
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                      backgroundColor: AppColors.redBtn,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 48),
                      shape: const StadiumBorder()),
                  onPressed: () => playSongs(context, r.songs, 0),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Reproducir'),
                ),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        side: BorderSide(color: AppColors.outline),
                        shape: const StadiumBorder()),
                    onPressed: () {
                      final mix = List<Song>.of(r.songs)..shuffle();
                      playSongs(context, mix, 0);
                    },
                    icon: const Icon(Icons.shuffle_rounded, size: 20),
                    label: const Text('Aleatorio',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        side: BorderSide(color: AppColors.outline),
                        shape: const StadiumBorder()),
                    onPressed: () => _save(r),
                    icon: const Icon(Icons.bookmark_border_rounded, size: 20),
                    label: const Text('Guardar',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ]),
            ]),
          ),
        ],
      ),
    );
  }

  static List<List<Object>> get _moodTiles => [
    ['Con energía', AppPalettes.fire],
    ['Melancólico', AppPalettes.graphite],
    ['Para concentrarme', AppPalettes.steel],
    ['De carretera', AppPalettes.rust],
    ['Quiero algo nuevo', AppPalettes.amber],
    MusicModeService.general
        ? ['Para bailar', AppPalettes.burgundy]
        : ['Para entrenar', AppPalettes.burgundy],
  ];

  Widget _moodTile(List<Object> t) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: t[1] as List<Color>,
          ),
        ),
        child: InkWell(
          onTap: _busy ? null : () => _send(t[0] as String),
          child: Container(
            height: 84,
            alignment: Alignment.center,
            padding: const EdgeInsets.all(14),
            child: Text(t[0] as String,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: AppType.body, height: 1.1)),
          ),
        ),
      ),
    );
  }

  Widget _welcome() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: AppColors.heroGradient,
            borderRadius: BorderRadius.circular(AppRadius.xl),
            border: Border.all(color: AppColors.borderAccent),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('¿QUÉ SUENA HOY?', style: AppType.overlineOnAccent),
              const SizedBox(height: 6),
              Text(byMode('CUÉNTAME CÓMO ESTÁS\nY ARMO TU LISTA', 'Cuéntame cómo estás\ny armo tu lista'),
                  style: AppType.oswald(AppType.title, height: 1.15)),
              const SizedBox(height: 14),
              Text(byMode('Escribe abajo, por ejemplo: rock para estudiar de noche.', 'Escribe abajo, por ejemplo: salsa para una tarde con amigos.'),
                  style: const TextStyle(
                      color: Color(0xE6FFFFFF),
                      fontSize: AppType.bodySm,
                      height: 1.4)),
            ],
          ),
        ),
        if (_noKeys) ...[
          const SizedBox(height: 14),
          Material(
            color: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              side: BorderSide(color: AppColors.outline),
            ),
            child: InkWell(
              customBorder: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.lg)),
              onTap: _openSettings,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                        color: AppColors.surfaceHigh,
                        borderRadius: BorderRadius.circular(AppRadius.md)),
                    child: Icon(Icons.key_rounded,
                        color: AppColors.amber, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Activa la IA gratis',
                            style: TextStyle(
                                fontWeight: FontWeight.w800, fontSize: AppType.bodySm)),
                        SizedBox(height: 2),
                        Text('Sin clave funciona con reglas simples',
                            style: TextStyle(
                                color: AppColors.textDim, fontSize: AppType.caption)),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded,
                      color: AppColors.textDim),
                ]),
              ),
            ),
          ),
        ],
        const SizedBox(height: 22),
        const SectionTitle('Elige un ánimo',
            padding: EdgeInsets.fromLTRB(0, 0, 0, 10)),
        Dense(child: GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.9,
          children: [for (final t in _moodTiles) _moodTile(t)],
        )),
      ],
    );
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => const AiSettingsScreen()));
    final s = AiSettings.instance;
    if (mounted) {
      setState(() =>
          _noKeys = s.groqKey.trim().isEmpty && s.geminiKey.trim().isEmpty);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 8, 8),
              child: Row(children: [
                _avatar(44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(byMode('ASISTENTE', 'Asistente'),
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontSize: AppType.title)),
                      ),
                      Text(byMode('Tu guía de rock', 'Tu guía musical'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: AppColors.textDim, fontSize: AppType.caption)),
                    ],
                  ),
                ),
                // Locutor IA: presenta las canciones cada 3.
                ValueListenableBuilder<bool>(
                  valueListenable: DjVoice.instance.on,
                  builder: (context, on, _) => TextButton.icon(
                    style: TextButton.styleFrom(
                        foregroundColor: on ? AppColors.amber : AppColors.textDim,
                        padding: const EdgeInsets.symmetric(horizontal: 8)),
                    icon: Icon(on ? Icons.record_voice_over_rounded
                        : Icons.voice_over_off_rounded, size: 20),
                    label: Text(on ? 'Locutor: sí' : 'Locutor: no',
                        style: TextStyle(
                            fontSize: AppType.caption, fontWeight: FontWeight.w700)),
                    onPressed: () {
                      DjVoice.instance.set(!on);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(!on
                              ? 'Locutor encendido: cada 3 canciones te cuento qué suena.'
                              : 'Locutor apagado.')));
                    },
                  ),
                ),
                if (_msgs.isNotEmpty)
                  IconButton(
                    tooltip: 'Limpiar conversación',
                    icon: const Icon(Icons.delete_sweep_rounded),
                    onPressed: _clearChat,
                  ),
              ]),
            ),
            Expanded(
              // Desvanecido abajo: lo que sigue se ve como «hay más», no
              // como botones cortados contra el campo de texto.
              child: ShaderMask(
                shaderCallback: (r) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.white, Colors.white, Colors.transparent],
                  stops: [0, 0.94, 1],
                ).createShader(r),
                blendMode: BlendMode.dstIn,
                child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  const TipCard(
                      id: 'asistente',
                      text:
                          'Toca un ánimo o escribe lo que quieras. El asistente arma la lista y puedes mezclarla, guardarla o ampliarla.'),
                  if (_msgs.isEmpty) _welcome(),
                  for (var i = 0; i < _msgs.length; i++)
                    _bubble(_msgs[i], i == _msgs.length - 1 && !_busy),
                  if (_busy)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(children: [
                        _avatar(32),
                        const SizedBox(width: 10),
                        SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppColors.amber)),
                        const SizedBox(width: 10),
                        Text('Armando tu lista…',
                            style: TextStyle(color: AppColors.textDim)),
                      ]),
                    ),
                ],
              ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    textInputAction: TextInputAction.send,
                    onSubmitted: _send,
                    decoration: InputDecoration(
                      hintText: 'Pide una lista…',
                      filled: true,
                      fillColor: AppColors.surfaceHigh,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        borderSide: BorderSide(color: AppColors.outline),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        borderSide: BorderSide(color: AppColors.outline),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        borderSide: BorderSide(color: AppColors.red),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Material(
                  color: Colors.transparent,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: Ink(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle, gradient: AppColors.accent),
                    child: Semantics(
                      button: true,
                      label: 'Enviar',
                      child: InkWell(
                        onTap: _busy ? null : () => _send(_input.text),
                        child: const Tooltip(
                          message: 'Enviar',
                          child: Icon(Icons.arrow_forward_rounded,
                              color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
