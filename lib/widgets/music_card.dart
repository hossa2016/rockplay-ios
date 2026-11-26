import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../services/playback_service.dart';
import 'package:flutter/services.dart';

import '../models/song.dart';
import '../theme/app_theme.dart';
import 'cover_art.dart';
import 'playback_ui.dart';
import 'song_actions.dart';

/// Fila de canción con portada, resaltada si es la que suena.
class MusicCard extends StatelessWidget {
  final Song song;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool actions;

  const MusicCard({
    super.key,
    required this.song,
    required this.onTap,
    this.trailing,
    this.actions = true,
  });

  @override
  Widget build(BuildContext context) {
    final pb = PlaybackUi.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([pb.song, pb.playing]),
      builder: (context, _) {
        final cur = pb.song.value;
        final isCurrent =
            cur != null && cur.title == song.title && cur.artist == song.artist;
        // Sin ▶ redundante (toda la fila ya reproduce): la que suena muestra
        // el ecualizador; el menú ⋮ va aparte.
        final Widget end = trailing ??
            (isCurrent
                // Ecualizador: ámbar si suena, gris si está en pausa (antes
                // un ícono de pausa que contradecía al mini player).
                ? Semantics(
                    label: pb.playing.value ? 'Sonando' : 'En pausa',
                    child: PlayingBars(playing: pb.playing.value))
                : const SizedBox.shrink());
        final card = Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            onLongPress:
                actions ? () => showSongActions(context, song) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
              child: Row(
                children: [
                  SongCover(song, size: 56, radius: 8),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          song.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: AppType.body,
                            fontWeight: FontWeight.w600,
                            height: 1.2,
                            // En pausa, título neutro: el estado lo dicen las
                            // barras (quietas) y no solo el color.
                            color: isCurrent && pb.playing.value
                                ? AppColors.amber
                                : AppColors.text,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          song.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: AppType.label,
                            color: AppColors.textDim,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  end,
                  if (actions && trailing == null)
                    SizedBox(
                      width: 48,
                      height: 48,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        tooltip: 'Más opciones',
                        icon: Icon(Icons.more_vert_rounded,
                            color: AppColors.textDim),
                        onPressed: () => showSongActions(context, song),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
        if (!actions) return card;
        return Dismissible(
          key: ValueKey<String>('mc-${song.videoId}-${song.title}-${song.artist}'),
          direction: DismissDirection.startToEnd,
          confirmDismiss: (_) async {
            HapticFeedback.mediumImpact();
            PlaybackService.instance.queuePlayNext(song);
            ScaffoldMessenger.maybeOf(context)
              ?..clearSnackBars()
              ..showSnackBar(const SnackBar(
                  content: Text('Sonará a continuación'),
                  duration: Duration(seconds: 2)));
            return false;
          },
          background: Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.only(left: 24),
            color: AppColors.red.withValues(alpha: 0.18),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.queue_play_next_rounded, color: AppColors.amber),
              SizedBox(width: 10),
              Text('A continuación',
                  style: TextStyle(
                      color: AppColors.amber, fontWeight: FontWeight.w700)),
            ]),
          ),
          child: card,
        );
      },
    );
  }
}


/// Barras de reproducción: se mueven al sonar; en pausa quedan bajas, quietas
/// y en gris (el estado no depende solo del color).
class PlayingBars extends StatefulWidget {
  const PlayingBars({super.key, required this.playing, this.size = 22});
  final bool playing;
  final double size;

  @override
  State<PlayingBars> createState() => _PlayingBarsState();
}

class _PlayingBarsState extends State<PlayingBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant PlayingBars old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final reduce = WidgetsBinding.instance.platformDispatcher
        .accessibilityFeatures.disableAnimations;
    if (widget.playing && !reduce) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.playing ? AppColors.amber : AppColors.textFaint;
    final s = widget.size;
    return SizedBox(
      width: s,
      height: s,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          const phases = [0.0, 0.35, 0.7];
          // En pausa: escalonadas y quietas (no tres puntos iguales que
          // parezcan un menú).
          const still = [0.45, 0.85, 0.6];
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < phases.length; i++)
                Container(
                  width: s / 6,
                  margin: EdgeInsets.symmetric(horizontal: s / 24),
                  height: widget.playing
                      ? s * (0.3 + 0.7 * (0.5 + 0.5 * math.sin(2 * math.pi * (_c.value + phases[i]))))
                      : s * still[i],
                  decoration: BoxDecoration(
                      color: color, borderRadius: BorderRadius.circular(2)),
                ),
            ],
          );
        },
      ),
    );
  }
}
