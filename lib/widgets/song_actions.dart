import 'package:flutter/material.dart';

import '../models/song.dart';
import '../services/playback_service.dart';
import '../theme/app_theme.dart';
import 'add_to_playlist.dart';
import '../services/share_service.dart';

/// Menú al mantener pulsada una canción: cola y listas.
void showSongActions(BuildContext context, Song song) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (sheet) {
      void done(String msg) {
        Navigator.of(sheet).pop();
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
      }

      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                song.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 6),
            ListTile(
              leading: const Icon(Icons.queue_play_next_rounded),
              title: const Text('Tocar a continuación'),
              onTap: () {
                PlaybackService.instance.queuePlayNext(song);
                done('Sonará a continuación');
              },
            ),
            ListTile(
              leading: const Icon(Icons.playlist_play_rounded),
              title: const Text('Añadir al final de la cola'),
              onTap: () {
                PlaybackService.instance.queueAdd(song);
                done('Añadida a la cola');
              },
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add_rounded),
              title: const Text('Guardar en una lista'),
              onTap: () {
                Navigator.of(sheet).pop();
                showAddToPlaylist(context, song);
              },
            ),
            ListTile(
              leading: const Icon(Icons.share_rounded),
              title: const Text('Compartir'),
              onTap: () {
                Navigator.of(sheet).pop();
                ShareService.song(song);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}
