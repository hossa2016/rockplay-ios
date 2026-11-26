import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/song.dart';
import '../services/library_service.dart';
import '../theme/app_theme.dart';
import 'playback_ui.dart';

/// Botón de favorito. Se desactiva mientras la canción no tenga videoId
/// (LibraryService guarda favoritos por videoId).
class FavoriteButton extends StatefulWidget {
  final Song song;
  final double size;

  const FavoriteButton({super.key, required this.song, this.size = 28});

  @override
  State<FavoriteButton> createState() => _FavoriteButtonState();
}

class _FavoriteButtonState extends State<FavoriteButton> {
  bool _fav = false;

  @override
  void initState() {
    super.initState();
    PlaybackUi.instance.libraryRevision.addListener(_refresh);
    _refresh();
  }

  @override
  void didUpdateWidget(FavoriteButton old) {
    super.didUpdateWidget(old);
    if (old.song.videoId != widget.song.videoId ||
        old.song.title != widget.song.title) {
      _refresh();
    }
  }

  @override
  void dispose() {
    PlaybackUi.instance.libraryRevision.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _refresh() async {
    final id = widget.song.videoId;
    if (id.isEmpty) {
      if (mounted && _fav) setState(() => _fav = false);
      return;
    }
    bool f = false;
    try {
      f = await LibraryService.instance.isFavorite(id);
    } catch (_) {}
    if (!mounted || id != widget.song.videoId) return;
    setState(() => _fav = f);
  }

  Future<void> _toggle() async {
    HapticFeedback.lightImpact();
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final f = await LibraryService.instance.toggleFavorite(widget.song);
      if (!mounted) return;
      setState(() => _fav = f);
      PlaybackUi.instance.bumpLibrary();
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          duration: const Duration(milliseconds: 1400),
          content: Text(f ? 'Añadida a favoritos' : 'Quitada de favoritos'),
        ));
    } catch (_) {
      messenger?.showSnackBar(
        const SnackBar(content: Text('No se pudo guardar el favorito')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.song.videoId.isNotEmpty;
    return IconButton(
      iconSize: widget.size,
      tooltip: enabled
          ? (_fav ? 'Quitar de favoritos' : 'Añadir a favoritos')
          : 'Disponible cuando la canción esté lista',
      onPressed: enabled ? _toggle : null,
      disabledColor: AppColors.textFaint,
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        transitionBuilder: (child, anim) =>
            ScaleTransition(scale: anim, child: child),
        child: Icon(
          _fav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          key: ValueKey<bool>(_fav),
          color: _fav ? AppColors.redText : (enabled ? Colors.white : null),
        ),
      ),
    );
  }
}
