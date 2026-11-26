import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/playback_service.dart';

import '../models/song.dart';
import '../services/ai_json.dart';
import '../services/lyrics_service.dart';
import '../services/lyrics_translate.dart';
import '../theme/app_theme.dart';
import 'playback_ui.dart';

/// Letra de la canción: sincronizada (resalta la línea actual) si existe,
/// o texto simple desplazable.
class LyricsView extends StatefulWidget {
  final Song song;
  const LyricsView({super.key, required this.song});

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  final PlaybackUi pb = PlaybackUi.instance;
  Lyrics? _l;
  bool _loading = true;
  int _cur = -1;
  List<GlobalKey> _keys = [];
  // Traducción: 0 Original, 1 Español, 2 Ambas.
  int _view = 0;
  bool _canTranslate = false;
  bool _translating = false;
  LyricsTranslation? _tr;
  final ScrollController _sc = ScrollController();

  @override
  void initState() {
    super.initState();
    pb.position.addListener(_tick);
    _load();
  }

  @override
  void didUpdateWidget(covariant LyricsView old) {
    super.didUpdateWidget(old);
    if (old.song.title != widget.song.title ||
        old.song.artist != widget.song.artist) {
      _load();
    }
  }

  @override
  void dispose() {
    pb.position.removeListener(_tick);
    _sc.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _l = null;
      _cur = -1;
      _tr = null;
      _view = 0;
      _canTranslate = false;
    });
    final s = widget.song;
    final l = await LyricsService.instance.fetch(s.artist, s.title,
        seconds: pb.duration.value?.inSeconds);
    if (!mounted ||
        s.title != widget.song.title ||
        s.artist != widget.song.artist) return;
    final ai = await AiJson.available();
    if (!mounted) return;
    setState(() {
      _l = l;
      _loading = false;
      _keys = List.generate(l?.synced.length ?? 0, (_) => GlobalKey());
      // Solo si hay IA y la letra no está ya en español.
      _canTranslate = ai && l != null && !l.isEmpty &&
          !LyricsTranslate.isSpanish(_lines(l));
    });
  }

  static List<String> _lines(Lyrics l) => l.synced.isNotEmpty
      ? [for (final x in l.synced) x.text]
      : l.plain.split('\n');

  Future<LyricsTranslation?> _ensureTr() async {
    if (_tr != null) return _tr;
    final l = _l;
    if (l == null) return null;
    setState(() => _translating = true);
    final s = widget.song;
    final t = await LyricsTranslate.get(s.artist, s.title, _lines(l));
    if (!mounted) return null;
    // Cambió la canción mientras traducía: esa traducción ya no sirve.
    if (s.title != widget.song.title || s.artist != widget.song.artist ||
        !identical(l, _l)) {
      setState(() => _translating = false);
      return null;
    }
    setState(() {
      _tr = t;
      _translating = false;
    });
    if (t == null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No se pudo traducir ahora. Inténtalo en un momento.')));
    }
    return t;
  }

  Future<void> _setView(int v) async {
    if (v != 0 && await _ensureTr() == null) return;
    if (mounted) setState(() => _view = v);
  }

  Future<void> _about() async {
    final t = await _ensureTr();
    if (t == null || !mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('¿De qué habla?',
                  style: TextStyle(
                      fontSize: AppType.title, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              Text(t.about.isEmpty ? 'Sin explicación disponible.' : t.about,
                  style: const TextStyle(fontSize: AppType.body, height: 1.5)),
              const SizedBox(height: 10),
              Text('Explicación hecha con IA; puede tener errores.',
                  style: TextStyle(
                      color: AppColors.textFaint, fontSize: AppType.caption)),
            ],
          ),
        ),
      ),
    );
  }

  /// Barra: Original · Español · Ambas y «¿De qué habla?».
  Widget _bar() {
    if (!_canTranslate) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Row(children: [
        Expanded(
          child: SegmentedButton<int>(
            showSelectedIcon: false,
            style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.padded),
            segments: const [
              ButtonSegment(value: 0, label: Text('Original')),
              ButtonSegment(value: 1, label: Text('Español')),
              ButtonSegment(value: 2, label: Text('Ambas')),
            ],
            selected: {_view},
            onSelectionChanged: _translating ? null : (v) => _setView(v.first),
          ),
        ),
        const SizedBox(width: 8),
        _translating
            ? const SizedBox(
                width: 40,
                height: 40,
                child: Padding(
                    padding: EdgeInsets.all(10),
                    child: CircularProgressIndicator(strokeWidth: 2)))
            : IconButton(
                tooltip: '¿De qué habla?',
                icon: const Icon(Icons.lightbulb_outline_rounded),
                onPressed: _about,
              ),
      ]),
    );
  }

  String _trLine(int i) {
    final t = _tr;
    if (t == null || i >= t.lines.length) return '';
    return t.lines[i];
  }

  void _tick() {
    final l = _l;
    if (l == null || l.synced.isEmpty) return;
    final p = pb.position.value;
    var idx = -1;
    for (var i = 0; i < l.synced.length; i++) {
      if (l.synced[i].at <= p) {
        idx = i;
      } else {
        break;
      }
    }
    if (idx != _cur) {
      setState(() => _cur = idx);
      if (idx >= 0 && idx < _keys.length) {
        final ctx = _keys[idx].currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(ctx,
              alignment: 0.35,
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOut);
        }
      }
    }
  }

  /// Una línea: la actual grande y nítida; las lejanas más chicas y
  /// difuminadas. Tocar una línea salta a ese momento de la canción.
  Widget _line(Lyrics l, int i, bool reduced) {
    final d = _cur < 0 ? (i + 1) : (i - _cur).abs();
    final active = i == _cur;
    final blur = reduced || active ? 0.0 : (d.clamp(0, 4) * 0.6).toDouble();
    final opacity = active ? 1.0 : (d == 1 ? 0.55 : 0.32);
    final orig = l.synced[i].text.isEmpty ? '♪' : l.synced[i].text;
    final es = _trLine(i);
    final Widget text = _view == 1 && es.isNotEmpty
        ? Text(es, textAlign: TextAlign.left, style: AppType.oswald(27, height: 1.2))
        : (_view == 2 && es.isNotEmpty && l.synced[i].text.isNotEmpty)
            ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(orig, style: AppType.oswald(27, height: 1.2)),
                const SizedBox(height: 2),
                Text(es,
                    style: TextStyle(
                        fontSize: AppType.body,
                        height: 1.3,
                        color: AppColors.textDim)),
              ])
            : Text(orig, textAlign: TextAlign.left, style: AppType.oswald(27, height: 1.2));
    return Padding(
      key: _keys[i],
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () {
          HapticFeedback.selectionClick();
          PlaybackService.instance.seek(l.synced[i].at);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
          child: AnimatedScale(
            scale: active ? 1.0 : 0.94,
            alignment: Alignment.centerLeft,
            duration: reduced ? Duration.zero : const Duration(milliseconds: 420),
            curve: Curves.easeOutBack,
            child: AnimatedOpacity(
              opacity: opacity,
              duration: reduced ? Duration.zero : const Duration(milliseconds: 300),
              child: blur == 0
                  ? text
                  : ImageFiltered(
                      imageFilter:
                          ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                      child: text,
                    ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Center(
          child: Text('Buscando la letra…',
              style: TextStyle(color: AppColors.textDim)));
    }
    final l = _l;
    if (l == null || l.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('No encontré la letra de esta canción.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textDim)),
        ),
      );
    }
    if (l.synced.isNotEmpty) {
      final reduced = AppMotion.reduced(context);
      return Column(children: [
        _bar(),
        Expanded(child: ShaderMask(
        // Desvanece arriba y abajo para que la letra «flote».
        shaderCallback: (r) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.white, Colors.white, Colors.transparent],
          stops: [0, 0.12, 0.85, 1],
        ).createShader(r),
        blendMode: BlendMode.dstIn,
        child: SingleChildScrollView(
          controller: _sc,
          padding: const EdgeInsets.fromLTRB(28, 80, 28, 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < l.synced.length; i++)
                _line(l, i, reduced),
            ],
          ),
        ),
      )),
      ]);
    }
    final plainLines = l.plain.split('\n');
    final shown = _view == 0 || _tr == null
        ? l.plain
        : [
            for (var i = 0; i < plainLines.length; i++)
              _view == 1
                  ? (_trLine(i).isEmpty ? plainLines[i] : _trLine(i))
                  : (plainLines[i].trim().isEmpty || _trLine(i).isEmpty
                      ? plainLines[i]
                      : '${plainLines[i]}\n${_trLine(i)}'),
          ].join('\n');
    return Column(children: [
      _bar(),
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Text(
            shown,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: AppType.titleSm, height: 1.6, color: Colors.white70),
          ),
        ),
      ),
    ]);
  }
}
