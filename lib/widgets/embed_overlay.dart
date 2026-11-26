import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../services/embed_bridge.dart';

/// Aloja el WebView del reproductor de YouTube sobre toda la app. Cuando la
/// pantalla del reproductor está abierta, se coloca en su hueco; si no, se
/// deja fuera de pantalla (pero montado) para que la música siga.
class EmbedOverlay extends StatefulWidget {
  const EmbedOverlay({super.key, required this.child});
  final Widget child;

  @override
  State<EmbedOverlay> createState() => _EmbedOverlayState();
}

class _EmbedOverlayState extends State<EmbedOverlay> {
  final EmbedBridge eb = EmbedBridge.instance;
  YoutubePlayerController? _c;

  @override
  void initState() {
    super.initState();
    _c = eb.controller;
    eb.created.listen((c) {
      if (mounted) setState(() => _c = c);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      textDirection: TextDirection.ltr,
      children: [
        Positioned.fill(child: widget.child),
        if (_c != null)
          ValueListenableBuilder<bool>(
            valueListenable: eb.fullscreen,
            builder: (context, full, _) => ValueListenableBuilder<Rect?>(
              valueListenable: eb.slot,
              builder: (context, r, _) {
                final size = MediaQuery.of(context).size;
                final rect = full
                    ? Rect.fromLTWH(0, 0, size.width, size.height)
                    : (r ?? const Rect.fromLTWH(-600, 0, 320, 180));
                return Positioned(
                  left: rect.left,
                  top: rect.top,
                  width: rect.width,
                  height: rect.height,
                  child: ColoredBox(
                    color: Colors.black,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: YoutubePlayer(
                            controller: _c!,
                            aspectRatio: rect.width / rect.height,
                            backgroundColor: Colors.black,
                            keepAlive: true,
                            enableFullScreenOnVerticalDrag: false,
                            autoFullScreen: false,
                          ),
                        ),
                        if (full)
                          Positioned(
                            top: 12,
                            right: 12,
                            child: Material(
                              color: Colors.black54,
                              shape: const CircleBorder(),
                              child: IconButton(
                                tooltip: 'Salir de pantalla completa',
                                icon: const Icon(Icons.close_rounded,
                                    color: Colors.white),
                                onPressed: () {
                                  eb.fullscreen.value = false;
                                  SystemChrome.setPreferredOrientations(
                                      DeviceOrientation.values);
                                  SystemChrome.setEnabledSystemUIMode(
                                      SystemUiMode.edgeToEdge);
                                },
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
