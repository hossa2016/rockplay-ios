import 'dart:async';

import 'package:flutter/material.dart';

import '../models/song.dart';
import '../theme/app_theme.dart';
import '../widgets/music_card.dart';
import '../widgets/player_route.dart';
import '../widgets/state_views.dart';
import '../widgets/undo.dart';
import '../widgets/playback_ui.dart';
import '../services/playlist_service.dart';
import '../services/share_service.dart';

/// Lista de canciones con botones Aleatorio / En orden. Sirve para mixes
/// (llegan por [stream]) y para listas propias ([songs] + [onRemove]).
class SongListScreen extends StatefulWidget {
  final String title;
  final String subtitle;
  final List<Color>? _colors;
  List<Color> get colors => _colors ?? AppPalettes.wine;
  final Stream<List<Song>>? stream;
  final List<Song>? songs;
  final Future<void> Function(Song song)? onRemove;
  final VoidCallback? onDeleteList;
  final String emptyMessage;
  /// Lista propia de donde salen las canciones (para «Deshacer» al quitar).
  final String? playlistId;

  const SongListScreen({
    super.key,
    required this.title,
    this.subtitle = '',
    List<Color>? colors,
    this.stream,
    this.songs,
    this.onRemove,
    this.onDeleteList,
    this.emptyMessage = 'No hay canciones todavía.',
    this.playlistId,
  }) : _colors = colors;

  @override
  State<SongListScreen> createState() => _SongListScreenState();
}

class _SongListScreenState extends State<SongListScreen> {
  List<Song> _songs = <Song>[];
  bool _loading = false;
  StreamSubscription<List<Song>>? _sub;

  @override
  void initState() {
    super.initState();
    final st = widget.stream;
    if (st != null) {
      _loading = true;
      _sub = st.listen(
        (l) {
          if (mounted) setState(() => _songs = l);
        },
        onError: (Object _) {
          if (mounted) setState(() => _loading = false);
        },
        onDone: () {
          if (mounted) setState(() => _loading = false);
        },
      );
    } else {
      _songs = List<Song>.of(widget.songs ?? const <Song>[]);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _remove(Song song, int idx) async {
    await widget.onRemove!(song);
    if (!mounted) return;
    setState(() => _songs.removeAt(idx));
    final id = widget.playlistId;
    if (id == null) return;
    showUndo(context, 'Quitada «${song.title}»', () async {
      await PlaylistService.instance.insertSong(id, song, idx);
      PlaybackUi.instance.bumpLibrary();
      if (mounted) {
        setState(() => _songs.insert(idx.clamp(0, _songs.length), song));
      }
    });
  }

  void _shuffle() {
    if (_songs.isEmpty) return;
    final l = List<Song>.of(_songs)..shuffle();
    playSongs(context, l, 0);
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [widget.colors.first, AppColors.bg],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Volver',
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                const Spacer(),
                if (_songs.isNotEmpty)
                  IconButton(
                    tooltip: 'Compartir lista',
                    icon: const Icon(Icons.share_rounded),
                    onPressed: () => ShareService.list(widget.title, _songs),
                  ),
                if (widget.onDeleteList != null)
                  IconButton(
                    tooltip: 'Borrar lista',
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: widget.onDeleteList,
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(widget.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.displaySmall),
            if (widget.subtitle.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(widget.subtitle,
                  style: TextStyle(color: AppColors.textDim)),
            ],
            const SizedBox(height: 6),
            Text(
              _loading
                  ? '${_songs.length} canciones · cargando más…'
                  : '${_songs.length} canciones',
              style: TextStyle(color: AppColors.textDim, fontSize: AppType.caption),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _songs.isEmpty
                      ? null
                      : () => playSongs(context, _songs, 0),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Reproducir'),
                ),
                OutlinedButton.icon(
                  onPressed: _songs.isEmpty ? null : _shuffle,
                  icon: const Icon(Icons.shuffle_rounded),
                  label: const Text('Aleatorio'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: ListView.builder(
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: _songs.length + 2,
        itemBuilder: (context, i) {
          if (i == 0) return _header();
          if (i == _songs.length + 1) {
            if (_songs.isEmpty && _loading) {
              return const SkeletonList(count: 6, shrinkWrap: true);
            }
            if (_songs.isEmpty) {
              return StateMessage(
                icon: Icons.queue_music_rounded,
                title: 'Sin canciones',
                message: widget.emptyMessage,
              );
            }
            return const SizedBox.shrink();
          }
          final idx = i - 1;
          final song = _songs[idx];
          return FadeIn(
            order: idx < 12 ? idx : 0,
            child: MusicCard(
              song: song,
              onTap: () => playSongs(context, _songs, idx),
              trailing: widget.onRemove == null
                  ? null
                  : IconButton(
                      tooltip: 'Quitar de la lista',
                      icon: Icon(Icons.remove_circle_outline_rounded,
                          color: AppColors.textFaint),
                      onPressed: () => _remove(song, idx),
                    ),
            ),
          );
        },
      ),
    );
  }
}
