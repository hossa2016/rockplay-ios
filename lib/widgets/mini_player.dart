import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/song.dart';
import '../services/playback_service.dart';
import '../services/cover_color.dart';
import '../theme/app_theme.dart';
import 'cover_art.dart';
import 'player_route.dart';
import 'playback_ui.dart';
import '../services/music_mode.dart';
import '../services/radio_now.dart';

/// Etiqueta Hero de la carátula: vuela del mini player al reproductor.
const String kNowPlayingHero = 'now-playing-cover';

/// Mini-reproductor persistente; aparece solo si hay canción.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Song?>(
      valueListenable: PlaybackUi.instance.song,
      builder: (context, song, _) {
        return AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          alignment: Alignment.bottomCenter,
          child: song == null
              ? const SizedBox(width: double.infinity)
              : Dense(child: _MiniBody(song: song)),
        );
      },
    );
  }
}

class _MiniBody extends StatelessWidget {
  final Song song;
  const _MiniBody({required this.song});

  @override
  Widget build(BuildContext context) {
    final pb = PlaybackUi.instance;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      child: FutureBuilder<Color?>(
        // El color sale de la misma carátula que se muestra.
        future: SongArtwork.of(song).then(CoverColor.of),
        initialData: CoverColor.peek(SongArtwork.peek(song)),
        builder: (context, snap) => AnimatedContainer(
          duration: const Duration(milliseconds: 500),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.borderSubtle),
            boxShadow: AppShadow.card,
            gradient: LinearGradient(colors: [
              Color.lerp(
                      AppColors.surfaceHigh,
                      snap.data == null
                          ? AppColors.surfaceHigh
                          : MusicModeService.general
                              ? Color.lerp(snap.data, const Color(0xFF6A4CF0), 0.5)!
                              : snap.data!,
                      0.7) ??
                  AppColors.surfaceHigh,
              AppColors.surfaceHigh,
            ]),
          ),
          child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        clipBehavior: Clip.antiAlias,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragEnd: (d) {
            final v = d.primaryVelocity ?? 0;
            final svc = PlaybackService.instance;
            if (v < -300 && svc.hasNext) svc.next();
            if (v > 300 && svc.hasPrevious) svc.previous();
          },
          onVerticalDragEnd: (d) {
            if ((d.primaryVelocity ?? 0) < -300) openPlayer(context);
          },
          child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            openPlayer(context);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
                child: Row(
                  children: [
                    Hero(
                      tag: kNowPlayingHero,
                      child: SongCover(song,
                          size: 44, radius: AppRadius.sm),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: AppType.bodySm,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          ValueListenableBuilder<String?>(
                            valueListenable: pb.error,
                            builder: (context, err, _) => ValueListenableBuilder<(String, String)?>(
                              valueListenable: RadioNow.song,
                              builder: (context, rn, _) {
                              final hasErr = err != null && err.isNotEmpty;
                              // Radio: lo que suena ahora (confirmado con Deezer).
                              final now = song.isRadio ? rn : null;
                              return Text(
                                hasErr
                                    ? err
                                    : (now != null ? 'Ahora: ${now.$1} — ${now.$2}' : (song.isRadio ? 'Radio en vivo' : song.artist)),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: AppType.caption,
                                  color: hasErr
                                      ? AppColors.amber
                                      : AppColors.textDim,
                                ),
                              );
                            }),
                          ),
                        ],
                      ),
                    ),
                    ListenableBuilder(
                      listenable: Listenable.merge(
                          [pb.playing, pb.loading, pb.index, pb.queue]),
                      builder: (context, _) {
                        final svc = PlaybackService.instance;
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (pb.loading.value)
                              const SizedBox(
                                width: 48,
                                height: 48,
                                child: Center(
                                  child: SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                    ),
                                  ),
                                ),
                              )
                            else
                              IconButton(
                                iconSize: 32,
                                color: Colors.white,
                                tooltip: pb.playing.value ? 'Pausar' : 'Reproducir',
                                icon: AnimatedSwitcher(
                                  duration: AppMotion.of(context, AppMotion.fast),
                                  transitionBuilder: (c, a) =>
                                      ScaleTransition(scale: a, child: c),
                                  child: Icon(
                                    pb.playing.value
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    key: ValueKey<bool>(pb.playing.value),
                                  ),
                                ),
                                onPressed: () {
                                  HapticFeedback.lightImpact();
                                  pb.playing.value ? svc.pause() : svc.play();
                                },
                              ),
                            IconButton(
                              iconSize: 28,
                              color: Colors.white,
                              disabledColor: AppColors.textFaint,
                              tooltip: 'Siguiente',
                              icon: const Icon(Icons.skip_next_rounded),
                              onPressed: svc.hasNext
                                  ? () {
                                      HapticFeedback.lightImpact();
                                      svc.next();
                                    }
                                  : null,
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
              ListenableBuilder(
                listenable: Listenable.merge([pb.position, pb.duration]),
                builder: (context, _) {
                  final total = pb.duration.value?.inMilliseconds ?? 0;
                  final pos = pb.position.value.inMilliseconds;
                  final v = total <= 0 ? 0.0 : (pos / total).clamp(0.0, 1.0);
                  return LinearProgressIndicator(
                    value: v,
                    minHeight: 2.5,
                    color: AppColors.red,
                    backgroundColor: const Color.fromRGBO(255, 255, 255, 0.08),
                  );
                },
              ),
            ],
          ),
        ),
        ),
      ),
        ),
      ),
    );
  }
}
