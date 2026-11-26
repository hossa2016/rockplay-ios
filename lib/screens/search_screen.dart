import 'dart:async';

import 'package:flutter/material.dart';
import '../services/deezer_service.dart';
import '../widgets/tip_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/song.dart';
import '../services/music_api_service.dart';
import '../services/music_mode.dart';
import '../theme/app_theme.dart';
import '../widgets/music_card.dart';
import '../widgets/player_route.dart';
import '../widgets/section_header.dart';
import '../widgets/undo.dart';
import '../widgets/state_views.dart';
import '../services/lyrics_service.dart';

/// Pide buscar algo en la pestaña Buscar desde fuera (ej. «Escuchar banda»).
final ValueNotifier<String?> searchWantQuery = ValueNotifier<String?>(null);

class SearchScreen extends StatefulWidget {
  final String title;
  final String hint;
  final String intro;
  final String querySuffix;

  const SearchScreen({
    super.key,
    this.title = 'Buscar',
    this.hint = 'Artista o canción',
    this.intro = 'Encuentra artistas, álbumes y canciones',
    this.querySuffix = '',
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  final MusicApiService _api = MusicApiService();
  List<Song> _results = [];
  bool _loading = false;
  bool _searched = false;
  String? _error;
  int _searchId = 0;
  bool _more = false;
  List<String> _history = [];

  // Sugerencias instantáneas mientras escribes (Deezer, sin pulsar Enter).
  final DeezerService _dz = DeezerService();
  List<String> _sugs = const <String>[];
  bool _showSugs = false;
  Timer? _debounce;
  String _lastTyped = '';

  void _onTyping() {
    final q = _controller.text.trim();
    if (q == _lastTyped) return;
    _lastTyped = q;
    _debounce?.cancel();
    if (q.length < 2) {
      if (_sugs.isNotEmpty || _showSugs) {
        setState(() {
          _sugs = const <String>[];
          _showSugs = false;
        });
      }
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final r = await _dz.suggest(q);
      if (!mounted || _controller.text.trim() != q) return;
      setState(() {
        _sugs = r;
        _showSugs = r.isNotEmpty;
      });
    });
  }

  Widget _suggestBox() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: AppColors.outline),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final t in _sugs.take(6))
            InkWell(
              onTap: () => _useSuggestion(t),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(children: [
                    Icon(
                        t.contains(' - ')
                            ? Icons.music_note_rounded
                            : Icons.person_rounded,
                        size: 20,
                        color: AppColors.textDim),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(t,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: AppType.bodySm,
                              fontWeight: FontWeight.w600)),
                    ),
                    Icon(Icons.north_west_rounded,
                        size: 18, color: AppColors.textFaint),
                  ]),
                ),
              ),
            ),
        ]),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadHistory();
    searchWantQuery.addListener(_wantQuery);
    _controller.addListener(_onTyping);
  }

  String get _histKey => modeKey('search_hist_${widget.title}');

  Future<void> _loadHistory() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final l = sp.getStringList(_histKey) ?? [];
      if (mounted) setState(() => _history = l);
    } catch (_) {}
  }

  Future<void> _saveHistory(String q) async {
    final l = [q, ..._history.where((e) => e.toLowerCase() != q.toLowerCase())]
        .take(10)
        .toList();
    _history = l;
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setStringList(_histKey, l);
    } catch (_) {}
  }

  Future<void> _clearHistory() async {
    final old = List<String>.of(_history);
    setState(() => _history = []);
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(_histKey);
    } catch (_) {}
    if (!mounted) return;
    showUndo(context, 'Búsquedas recientes borradas', () async {
      if (!mounted) return;
      setState(() => _history = old);
      try {
        final sp = await SharedPreferences.getInstance();
        await sp.setStringList(_histKey, old);
      } catch (_) {}
    });
  }

  void _wantQuery() {
    final q = searchWantQuery.value;
    if (q == null || q.isEmpty) return;
    searchWantQuery.value = null;
    _useSuggestion(q);
  }

  @override
  void dispose() {
    searchWantQuery.removeListener(_wantQuery);
    _debounce?.cancel();
    _controller.dispose();
    _api.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _controller.text.trim();
    if (q.isEmpty) return;
    FocusScope.of(context).unfocus();
    _saveHistory(q);
    _debounce?.cancel();
    _lastTyped = q;
    setState(() {
      _showSugs = false;
      _loading = true;
      _searched = true;
      _error = null;
    });
    final id = ++_searchId;
    _results = [];
    _more = true;
    try {
      var first = true;
      await for (final r
          in _api.searchStream('$q${widget.querySuffix}', max: 300)) {
        if (!mounted || id != _searchId) return;
        setState(() {
          _results = r;
          if (first) _loading = false;
          first = false;
        });
      }
      if (!mounted || id != _searchId) return;
      setState(() {
        _loading = false;
        _more = false;
      });
    } catch (e) {
      if (!mounted || id != _searchId) return;
      setState(() {
        _loading = false;
        _more = false;
        if (_results.isEmpty) {
          _error =
              'No se pudo buscar. Revisa tu conexión e inténtalo de nuevo.';
        }
      });
    }
  }

  void _useSuggestion(String q) {
    _controller.text = q;
    _search();
  }

  String _gFilter = 'Todos';

  List<String> get _genres {
    if (!MusicModeService.general) return _rockGenres;
    if (_gFilter == 'Mis géneros') {
      final f = PulsoPrefs.favGenres.value;
      if (f.isNotEmpty) return f;
    }
    if (_gFilter == 'En español') {
      return const [
        'Pop latino',
        'Salsa',
        'Reguetón',
        'Vallenato',
        'Baladas',
        'Rock en español',
        'Merengue',
        'Bachata',
      ];
    }
    return _allGenres;
  }

  static List<String> get _allGenres => MusicModeService.general
      ? const [
          'Pop',
          'Salsa',
          'Reguetón',
          'Vallenato',
          'Rock',
          'Electrónica',
          'Jazz',
          'Clásica',
        ]
      : _rockGenres;

  static const List<String> _rockGenres = [
    'Grunge',
    'Rock en español',
    'Heavy metal',
    'Rock clásico',
    'Hard rock',
    'Punk rock',
    'Rock alternativo',
    'Indie rock',
  ];

  Widget _label(String t, {String? action, VoidCallback? onAction}) =>
      SectionTitle(t,
          actionLabel: action,
          onAction: onAction,
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 8));

  Widget _genreTile(int i) {
    final name = _genres[i];
    final c = AppPalettes.cards[i % AppPalettes.cards.length];
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
            colors: c,
          ),
        ),
        child: InkWell(
          onTap: () => _useSuggestion(name),
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.all(14),
            child: Text(name,
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

  Widget _intro() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        if (_history.isNotEmpty) ...[
          const SizedBox(height: 10),
          _label('Recientes', action: 'Borrar', onAction: _clearHistory),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final h in _history)
                Material(
                  color: AppColors.surfaceHigh,
                  shape: StadiumBorder(
                      side: BorderSide(color: AppColors.outline)),
                  child: InkWell(
                    customBorder: const StadiumBorder(),
                    onTap: () => _useSuggestion(h),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      child: Text(h,
                          style: const TextStyle(
                              fontSize: AppType.label, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: 24),
        _label('Explorar por género'),
        // Filtros de la grilla de géneros, justo debajo de su título.
        if (MusicModeService.general)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Dense(
                child: Row(children: [
                  for (final f in const ['Todos', 'Mis géneros', 'En español'])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(f),
                        selected: _gFilter == f,
                        onSelected: (_) => setState(() => _gFilter = f),
                      ),
                    ),
                ]),
              ),
            ),
          ),
        Dense(child: GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2.3,
          children: [for (var i = 0; i < _genres.length; i++) _genreTile(i)],
        )),
      ],
    );
  }

  /// Buscar por letra: «la que dice algo de una luz que no se apaga…».
  Future<void> _byLyric() async {
    final q = _controller.text.trim();
    if (q.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: FutureBuilder<List<(String, String, String)>>(
          future: LyricsService.instance.byLyric(q),
          builder: (c, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final l = snap.data ?? const [];
            return ListView(shrinkWrap: true, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                    l.isEmpty ? 'No encontré esa letra.' : 'Canciones con esa letra',
                    style: const TextStyle(
                        fontSize: AppType.title, fontWeight: FontWeight.w800)),
              ),
              for (final (a, t, line) in l)
                ListTile(
                  title: Text('$t · $a',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: line.isEmpty
                      ? null
                      : Text('«$line»',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: AppColors.amber, fontStyle: FontStyle.italic)),
                  onTap: () {
                    Navigator.of(c).pop();
                    _controller.text = '$a $t';
                    _search();
                  },
                ),
            ]);
          },
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const SkeletonList();
    if (_error != null) {
      return StateMessage(
        icon: Icons.cloud_off_rounded,
        title: 'Sin conexión',
        message: _error!,
        actionLabel: 'Reintentar',
        onAction: _search,
        isError: true,
      );
    }
    if (!_searched) return _intro();
    if (_results.isEmpty) {
      return StateMessage(
        icon: Icons.search_off_rounded,
        title: 'Sin resultados',
        message: 'Prueba con otro nombre, o si recuerdas un pedazo de la letra, búscala por letra.',
        actionLabel: '¿Buscar por letra?',
        onAction: _byLyric,
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: _results.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _more
                      ? '${_results.length} canciones · cargando más…'
                      : '${_results.length} canciones',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 16),
                ),
                // Frase larga: quizá es un pedazo de la letra.
                if (_controller.text.trim().split(RegExp(r'\s+')).length >= 4)
                  TextButton.icon(
                    style: TextButton.styleFrom(
                        padding: EdgeInsets.zero, minimumSize: const Size(0, 40)),
                    onPressed: _byLyric,
                    icon: const Icon(Icons.lyrics_outlined, size: 18),
                    label: const Text('¿Es parte de una letra? Buscar por letra'),
                  ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 48)),
                      onPressed: () {
                        final list = List<Song>.of(_results)..shuffle();
                        playSongs(context, list, 0);
                      },
                      icon: const Icon(Icons.shuffle_rounded),
                      label: const Text('Aleatorio'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 48)),
                      onPressed: () => playSongs(context, _results, 0),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Reproducir'),
                    ),
                  ),
                ]),
              ],
            ),
          );
        }
        final idx = i - 1;
        final song = _results[idx];
        return FadeIn(
          order: idx,
          child: MusicCard(
            song: song,
            onTap: () => playSongs(context, _results, idx),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            AppSearchField(
              controller: _controller,
              hint: MusicModeService.general && widget.hint == 'Artista o canción'
                  ? 'Artista, canción o género'
                  : widget.hint,
              onSubmit: _search,
            ),
            if (_showSugs) _suggestBox(),
            const TipCard(
                id: 'buscar',
                text:
                    'Escribe un artista o una canción. Con los tres puntos de cada canción la guardas en una lista o la agregas a la cola.'),
            const SizedBox(height: 4),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: KeyedSubtree(
                  key: ValueKey<String>(
                      '$_loading-$_searched-${_error != null}-$_searchId-${_results.isEmpty}'),
                  child: _body(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
