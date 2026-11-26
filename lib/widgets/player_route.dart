import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/song.dart';
import '../screens/player_screen.dart';
import '../services/playback_service.dart';
import 'playback_ui.dart';

/// Ruta que sube desde abajo hacia la pantalla de reproducción.
Route<void> playerRoute() {
  return PageRouteBuilder<void>(
    opaque: true,
    transitionDuration: const Duration(milliseconds: 380),
    reverseTransitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (context, animation, secondary) => const PlayerScreen(),
    transitionsBuilder: (context, animation, secondary, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
            .animate(curved),
        child: child,
      );
    },
  );
}

void openPlayer(BuildContext context) {
  Navigator.of(context).push(playerRoute());
}

Future<void> _safePlay(List<Song> songs, int index) async {
  try {
    await PlaybackService.instance.playQueue(songs, index);
  } catch (_) {
    // El error se refleja en PlaybackService.error.
  }
}

/// Arranca la cola. La pantalla completa solo se abre la primera vez (cuando
/// no sonaba nada) o si [openFull] es true; después basta el mini player,
/// así no se corta la navegación por los resultados.
void playSongs(BuildContext context, List<Song> songs, int index,
    {bool? openFull}) {
  if (songs.isEmpty || index < 0 || index >= songs.length) return;
  final first = PlaybackUi.instance.song.value == null;
  HapticFeedback.mediumImpact();
  _safePlay(List<Song>.of(songs), index);
  if (openFull ?? first) openPlayer(context);
}
