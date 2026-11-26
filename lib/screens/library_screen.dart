import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/song.dart';
import '../services/library_service.dart';
import '../services/playlist_service.dart';
import '../widgets/add_to_playlist.dart';
import '../widgets/cover_art.dart';
import 'stats_screen.dart';
import '../widgets/undo.dart';
import 'song_list_screen.dart';
import '../theme/app_theme.dart';
import '../widgets/music_card.dart';
import '../widgets/playback_ui.dart';
import '../widgets/player_route.dart';
import '../widgets/section_header.dart';
import '../widgets/state_views.dart';
import '../services/music_mode.dart';
import '../widgets/app_button.dart';
import '../widgets/nav_signals.dart';
import 'search_hub.dart';
import '../services/import_service.dart';
import '../services/energy_sort.dart';
import '../widgets/progress_dialog.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  List<Song> _favs = [];
  List<Song> _hist = [];
  List<Playlist> _lists = [];
  List<Playlist> _others = [];
  int _otherFavs = 0;
  bool _loading = true;
  String _q = '';
  int _sort = 0;
  final TextEditingController _qc = TextEditingController();
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    PlaybackUi.instance.libraryRevision.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    PlaybackUi.instance.libraryRevision.removeListener(_load);
    _qc.dispose();
    super.dispose();
  }

  Future<void> _showOthers() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                  'Listas de ${MusicModeService.general ? 'Solo rock' : 'Todos los géneros'}. «Traer» las muestra en los dos modos.',
                  style: TextStyle(color: AppColors.textDim, height: 1.4)),
            ),
            for (final p in _others)
              ListTile(
                title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('${p.songs.length} canciones'),
                trailing: TextButton(
                  onPressed: () async {
                    await PlaylistService.instance.setBoth(p.id, true);
                    if (ctx.mounted) Navigator.of(ctx).pop();
                    PlaybackUi.instance.bumpLibrary();
                  },
                  child: const Text('Traer'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _load() async {
    try {
      final f = await LibraryService.instance.favorites();
      final h = await LibraryService.instance.history();
      final pl = await PlaylistService.instance.all();
      final ot = await PlaylistService.instance.others();
      final of = await LibraryService.instance.otherModeFavoritesCount();
      if (!mounted) return;
      setState(() {
        _favs = f;
        _hist = h;
        _lists = pl;
        _others = ot;
        _otherFavs = of;
        _loading = false;
        _failed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _unfavorite(Song s) async {
    try {
      await LibraryService.instance.toggleFavorite(s);
    } catch (_) {}
    PlaybackUi.instance.bumpLibrary();
    if (!mounted) return;
    final m = ScaffoldMessenger.of(context);
    m.clearSnackBars();
    m.showSnackBar(SnackBar(
      duration: const Duration(seconds: 4),
      persist: false,
      content: const Text('Quitada de favoritos'),
      action: SnackBarAction(
        label: 'Deshacer',
        onPressed: () async {
          try {
            await LibraryService.instance.toggleFavorite(s);
          } catch (_) {}
          PlaybackUi.instance.bumpLibrary();
        },
      ),
    ));
  }

  Future<void> _confirmClearHistory() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Borrar historial'),
        content: const Text(
            'Se borrarán todas las canciones que has escuchado. Tus favoritos no se tocan.'),
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
    try {
      await LibraryService.instance.clearHistory();
    } catch (_) {}
    PlaybackUi.instance.bumpLibrary();
    if (mounted) _load();
  }

  Widget _list(List<Song> songs, {required bool favorites}) {
    if (_loading) return const SkeletonList();
    if (_failed) {
      return StateMessage(
        icon: Icons.error_outline_rounded,
        title: 'No se pudo cargar',
        message: 'Hubo un problema al leer tu biblioteca.',
        actionLabel: 'Reintentar',
        onAction: _load,
        isError: true,
      );
    }
    if (songs.isEmpty) {
      final other = favorites ? _otherFavs : 0;
      final otherName =
          MusicModeService.general ? 'Solo rock' : 'Todos los géneros';
      return favorites
          ? StateMessage(
              icon: Icons.favorite_border_rounded,
              title: 'Aún no tienes favoritos',
              message: other > 0
                  ? 'Toca el corazón en el reproductor para guardar tus temas. Tienes $other en $otherName.'
                  : 'Toca el corazón en el reproductor para guardar tus temas.',
              // Si hay favoritas en el otro modo, se ofrece ir allá.
              actionLabel: other > 0 ? 'Ver en $otherName' : 'Buscar canciones',
              onAction: other > 0
                  ? () => MusicModeService.set(MusicModeService.general
                      ? MusicMode.rock
                      : MusicMode.general)
                  : () {
                      searchHubWantMode.value = 0; // segmento Canciones
                      mainTabWant.value = 1;
                    },
            )
          : const StateMessage(
              icon: Icons.history_rounded,
              title: 'Nada por aquí todavía',
              message: 'Lo que escuches aparecerá en tu historial.',
            );
    }
    final all = songs;
    final q = _q.trim().toLowerCase();
    if (q.isNotEmpty) {
      songs = songs
          .where((x) =>
              x.title.toLowerCase().contains(q) ||
              x.artist.toLowerCase().contains(q))
          .toList();
    }
    if (_sort == 1) {
      songs = List<Song>.of(songs)
        ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    } else if (_sort == 2) {
      songs = List<Song>.of(songs)
        ..sort((a, b) => a.artist.toLowerCase().compareTo(b.artist.toLowerCase()));
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: songs.length + 2,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (all.length > 6)
                  TextField(
                    controller: _qc,
                    onChanged: (v) => setState(() => _q = v),
                    decoration: InputDecoration(
                      hintText: 'Buscar en esta lista',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _q.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Borrar búsqueda',
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () => setState(() {
                                    _qc.clear();
                                    _q = '';
                                  }),
                            ),
                    ),
                  ),
                if (all.length > 6) const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final e in const [
                      [0, 'Recientes'],
                      [1, 'A–Z'],
                      [2, 'Artista']
                    ])
                      ChoiceChip(
                        label: Text(e[1] as String),
                        selected: _sort == e[0],
                        onSelected: (_) => setState(() => _sort = e[0] as int),
                      ),
                  ],
                ),
              ],
            ),
          );
        }
        if (i == 1) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${songs.length} ${songs.length == 1 ? 'canción' : 'canciones'}',
                    style: TextStyle(color: AppColors.textDim),
                  ),
                ),
                if (!favorites)
                  IconButton(
                    tooltip: 'Borrar historial',
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: _confirmClearHistory,
                  ),
                AppButton.primary(
                  label: 'Reproducir',
                  icon: Icons.play_arrow_rounded,
                  onPressed: () => playSongs(context, songs, 0),
                ),
              ],
            ),
          );
        }
        final idx = i - 2;
        final song = songs[idx];
        return FadeIn(
          order: idx,
          child: MusicCard(
            song: song,
            onTap: () => playSongs(context, songs, idx),
            trailing: favorites
                ? IconButton(
                    tooltip: 'Quitar de favoritos',
                    icon: Icon(Icons.favorite_rounded,
                        color: AppColors.redText),
                    onPressed: () => _unfavorite(song),
                  )
                : null,
          ),
        );
      },
    );
  }

  /// Borra la lista y ofrece «Deshacer».
  Future<void> _deleteList(Playlist p) async {
    final r = await PlaylistService.instance.delete(p.id);
    PlaybackUi.instance.bumpLibrary();
    if (r == null || !mounted) return;
    showUndo(context, 'Lista «${p.name}» borrada', () async {
      await PlaylistService.instance.restore(r.$1, r.$2);
      PlaybackUi.instance.bumpLibrary();
    });
  }

  Future<void> _importList() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Importar lista'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                'Pega el enlace de una lista pública de YouTube, o una canción por línea: «Artista - Canción». También sirve el CSV de TuneMyMusic (para traer listas de Spotify).',
                style: TextStyle(color: AppColors.textDim, fontSize: AppType.label)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              minLines: 4,
              maxLines: 10,
              decoration: const InputDecoration(
                  hintText: 'https://youtube.com/playlist?list=…\nSoda Stereo - De música ligera'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Importar')),
        ],
      ),
    );
    final text = ctrl.text;
    // Se libera después de la animación de cierre del diálogo.
    WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.dispose());
    if (ok != true || text.trim().isEmpty || !mounted) return;
    final m = ScaffoldMessenger.of(context);
    final (_, close) = showProgress(context,
        ImportService.isYoutube(text) ? 'Leyendo la lista de YouTube…' : 'Importando…');
    try {
      final (name, songs) = await ImportService.parse(text);
      close();
      if (songs.isEmpty) {
        m.showSnackBar(const SnackBar(
            content: Text('No encontré canciones en eso. Revisa el formato.')));
        return;
      }
      final p = await PlaylistService.instance.create(name);
      final n = await PlaylistService.instance.addMany(p.id, songs);
      PlaybackUi.instance.bumpLibrary();
      m.showSnackBar(SnackBar(content: Text('Lista «$name» con $n canciones.')));
    } catch (_) {
      close();
      m.showSnackBar(const SnackBar(
          content: Text('No se pudo importar (¿la lista es pública?).')));
    }
  }

  Future<void> _newList() async {
    final name = await askPlaylistName(context);
    if (name == null || name.trim().isEmpty) return;
    await PlaylistService.instance.create(name);
    PlaybackUi.instance.bumpLibrary();
  }

  Widget _listsTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          minVerticalPadding: 8,
          leading: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.surfaceHigh,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: AppColors.redText),
            ),
            child: Icon(Icons.add_rounded, color: AppColors.redText),
          ),
          title: const Text('Nueva lista',
              style: TextStyle(fontWeight: FontWeight.w700)),
          onTap: _newList,
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          minVerticalPadding: 8,
          leading: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.surfaceHigh,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: AppColors.outline),
            ),
            child: Icon(Icons.download_rounded, color: AppColors.textDim),
          ),
          title: const Text('Importar lista',
              style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('Enlace de YouTube o texto «Artista - Canción»',
              style: TextStyle(color: AppColors.textDim, fontSize: AppType.caption)),
          onTap: _importList,
        ),
        // Mismo estilo de estado vacío que Favoritos e Historial.
        if (_lists.isEmpty && _others.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: StateMessage(
              icon: Icons.queue_music_rounded,
              title: 'Aún no tienes listas',
              message: 'Crea una arriba o guarda la que arme el asistente.',
              compact: true,
            ),
          ),
        // Las listas del otro modo no desaparecen: se ven y se pueden traer.
        if (_others.isNotEmpty)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.swap_horiz_rounded, color: AppColors.textDim),
            title: Text(
                'Tienes ${_others.length} ${_others.length == 1 ? 'lista' : 'listas'} en ${MusicModeService.general ? 'Solo rock' : 'Todos los géneros'}',
                style: TextStyle(color: AppColors.textDim)),
            trailing: Text('Ver ›',
                style: TextStyle(
                    color: AppColors.redText, fontWeight: FontWeight.w700)),
            onTap: _showOthers,
          ),
        for (final p in _lists)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: SizedBox(
              width: 52,
              height: 52,
              child: CoverArt(
                  url: p.songs.isEmpty ? '' : p.songs.first.image, radius: AppRadius.sm),
            ),
            title: Text(p.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(
                '${p.songs.length} canciones${p.inBoth ? ' · en los dos modos' : ''}',
                style: TextStyle(color: AppColors.textDim)),
            trailing: PopupMenuButton<String>(
              icon: Icon(Icons.more_vert_rounded,
                  color: AppColors.textDim),
              onSelected: (v) async {
                if (v == 'rename') {
                  final n = await askPlaylistName(context);
                  if (n == null || n.trim().isEmpty) return;
                  await PlaylistService.instance.rename(p.id, n);
                } else if (v == 'energy') {
                  final m = ScaffoldMessenger.of(context);
                  final (set, close) = showProgress(
                      context, 'Midiendo la energía de cada canción…');
                  final sorted = await EnergySort.sort(p.songs,
                      progress: (d, t) => set('Midiendo la energía… $d de $t'));
                  close();
                  if (sorted == null) {
                    m.showSnackBar(const SnackBar(
                        content: Text('No encontré el ritmo de suficientes canciones para ordenarla.')));
                    return;
                  }
                  await PlaylistService.instance.setOrder(p.id, sorted);
                  m.showSnackBar(const SnackBar(
                      content: Text('Lista ordenada: sube la energía y luego baja.')));
                } else if (v == 'both') {
                  await PlaylistService.instance.setBoth(p.id, !p.inBoth);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(p.inBoth
                            ? 'Ahora «${p.name}» solo se ve en este modo'
                            : 'Ahora «${p.name}» se ve en los dos modos')));
                  }
                } else {
                  await _deleteList(p);
                  return;
                }
                PlaybackUi.instance.bumpLibrary();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'rename', child: Text('Renombrar')),
                const PopupMenuItem(value: 'energy', child: Text('Ordenar por energía')),
                PopupMenuItem(
                    value: 'both',
                    child: Text(p.inBoth
                        ? 'Solo en este modo'
                        : 'Mostrar en los dos modos')),
                const PopupMenuItem(value: 'delete', child: Text('Borrar lista')),
              ],
            ),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => SongListScreen(
                title: p.name,
                subtitle: 'Tu lista',
                songs: p.songs,
                emptyMessage:
                    'Lista vacía. Guarda canciones desde el reproductor.',
                playlistId: p.id,
                onRemove: (s) async {
                  await PlaylistService.instance.removeSong(p.id, s.videoId);
                  PlaybackUi.instance.bumpLibrary();
                },
                onDeleteList: () async {
                  Navigator.of(context).pop();
                  await _deleteList(p);
                },
              ),
            )),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: _TabJump(child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PageHeader(
                title: 'Mi música',
                trailing: TextButton.icon(
                  style: TextButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      foregroundColor: AppColors.amber),
                  icon: const Icon(Icons.insights_rounded),
                  label: const Text('Tus números'),
                  onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                          builder: (_) => const StatsScreen())),
                ),
              ),
              Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: AppColors.outline),
                ),
                child: Dense(child: TabBar(
                  dividerColor: Colors.transparent,
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicator: BoxDecoration(
                    color: AppColors.redBtn,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  labelColor: Colors.white,
                  unselectedLabelColor: AppColors.textDim,
                  labelStyle: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: AppType.bodySm),
                  unselectedLabelStyle: const TextStyle(
                      fontWeight: FontWeight.w500, fontSize: AppType.bodySm),
                  onTap: (_) => HapticFeedback.selectionClick(),
                  tabs: const [
                    Tab(height: 48, text: 'Favoritos'),
                    Tab(height: 48, text: 'Listas'),
                    Tab(height: 48, text: 'Historial'),
                  ],
                )),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: TabBarView(
                  children: [
                    _list(_favs, favorites: true),
                    _listsTab(),
                    _list(_hist, favorites: false),
                  ],
                ),
              ),
            ],
          ),
        ),
      )),
    );
  }
}

/// Pide abrir una pestaña de Mi música desde fuera (0 favoritos, 1 listas,
/// 2 historial).
final ValueNotifier<int> libraryWantTab = ValueNotifier<int>(-1);

class _TabJump extends StatefulWidget {
  final Widget child;
  const _TabJump({required this.child});

  @override
  State<_TabJump> createState() => _TabJumpState();
}

class _TabJumpState extends State<_TabJump> {
  @override
  void initState() {
    super.initState();
    libraryWantTab.addListener(_jump);
  }

  void _jump() {
    final i = libraryWantTab.value;
    if (i < 0) return;
    libraryWantTab.value = -1;
    try {
      DefaultTabController.of(context).animateTo(i);
    } catch (_) {}
  }

  @override
  void dispose() {
    libraryWantTab.removeListener(_jump);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
