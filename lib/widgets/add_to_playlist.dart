import 'package:flutter/material.dart';

import '../models/song.dart';
import '../services/playlist_service.dart';
import '../theme/app_theme.dart';
import 'playback_ui.dart';

/// Pide el nombre de una lista nueva. Devuelve null si se cancela.
Future<String?> askPlaylistName(BuildContext context) {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('Nueva lista'),
      content: TextField(
        controller: c,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(hintText: 'Nombre de la lista'),
        onSubmitted: (v) => Navigator.of(ctx).pop(v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(c.text),
          child: const Text('Crear'),
        ),
      ],
    ),
  );
}

/// Hoja inferior para guardar [song] en una lista (o crear una nueva).
Future<void> showAddToPlaylist(BuildContext context, Song song) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (song.videoId.isEmpty) {
    messenger?.showSnackBar(const SnackBar(
        content: Text('Espera a que cargue la canción para guardarla.')));
    return;
  }
  final lists = await PlaylistService.instance.all();
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (sheetCtx) {
      return StatefulBuilder(builder: (ctx, _) {
        Future<void> addTo(Playlist p) async {
          final ok = await PlaylistService.instance.addSong(p.id, song);
          PlaybackUi.instance.bumpLibrary();
          if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
          messenger
            ?..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(
              content: Text(ok
                  ? 'Añadida a «${p.name}»'
                  : 'Ya estaba en «${p.name}»'),
            ));
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.outline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Guardar en una lista',
                        style: Theme.of(ctx).textTheme.titleLarge),
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.add_rounded, color: AppColors.amber),
                  title: const Text('Nueva lista'),
                  onTap: () async {
                    final name = await askPlaylistName(ctx);
                    if (name == null) return;
                    final p = await PlaylistService.instance.create(name);
                    await addTo(p);
                  },
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final p in lists)
                        ListTile(
                          leading: const Icon(Icons.queue_music_rounded),
                          title: Text(p.name),
                          subtitle: Text('${p.songs.length} canciones'),
                          onTap: () => addTo(p),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      });
    },
  );
}
