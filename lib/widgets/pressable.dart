import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Se encoge un poco al presionar y vuelve con un rebote suave.
/// No captura el toque: el hijo sigue recibiendo onTap.
class Pressable extends StatefulWidget {
  final Widget child;
  final double scale;
  const Pressable({super.key, required this.child, this.scale = 0.94});

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final reduced = AppMotion.reduced(context);
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down && !reduced ? widget.scale : 1,
        duration: Duration(milliseconds: _down ? 90 : 260),
        curve: _down ? Curves.easeOut : Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}
