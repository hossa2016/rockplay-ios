import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Botón principal con una sola regla en toda la app:
/// - sobre fondo oscuro: relleno del color de marca y texto blanco;
/// - sobre una tarjeta de color ([onColor] = true): relleno blanco y texto
///   oscuro, para que no se pierda contra la tarjeta.
/// Alto mínimo 48 dp y esquinas de píldora.
class AppButton extends StatelessWidget {
  const AppButton.primary({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.onColor = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool onColor;

  @override
  Widget build(BuildContext context) {
    final style = FilledButton.styleFrom(
      backgroundColor: onColor ? Colors.white : AppColors.redBtn,
      foregroundColor: onColor ? const Color(0xFF111118) : Colors.white,
      minimumSize: const Size(0, 48),
      padding: const EdgeInsets.symmetric(horizontal: 18),
      shape: const StadiumBorder(),
      textStyle: const TextStyle(fontWeight: FontWeight.w800),
    );
    return icon == null
        ? FilledButton(style: style, onPressed: onPressed, child: Text(label))
        : FilledButton.icon(
            style: style,
            onPressed: onPressed,
            icon: Icon(icon, size: 20),
            label: Text(label));
  }
}
