import 'package:flutter/material.dart';

import '../services/music_mode.dart';
import '../theme/app_theme.dart';

/// Título grande de pantalla.
class PageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;

  const PageHeader(
      {super.key, required this.title, this.subtitle, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(MusicModeService.general ? title : title.toUpperCase(),
                    style: Theme.of(context).textTheme.displaySmall),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: TextStyle(
                        color: AppColors.textDim, fontSize: AppType.bodySm),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Título de sección con acción opcional.
class SectionTitle extends StatelessWidget {
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry padding;

  /// Único estilo de encabezado de sección de la app: barra roja-ámbar +
  /// título en Oswald mayúsculas. La acción va en gris (no ámbar).
  const SectionTitle(this.text,
      {super.key,
      this.actionLabel,
      this.onAction,
      this.padding = const EdgeInsets.fromLTRB(16, 24, 12, 12)});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          if (MusicModeService.rock) Container(
            width: 4,
            height: 22,
            margin: const EdgeInsets.only(right: 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [AppColors.red, AppColors.amber],
              ),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(MusicModeService.general ? text : text.toUpperCase(),
                  maxLines: 1, style: Theme.of(context).textTheme.titleLarge),
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              child: Text(
                actionLabel!,
                style: TextStyle(
                    color: AppColors.textDim, fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }
}

/// Campo de búsqueda en píldora, con botón de borrar.
class AppSearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final VoidCallback onSubmit;

  const AppSearchField({
    super.key,
    required this.controller,
    required this.hint,
    required this.onSubmit,
    this.icon = Icons.search_rounded,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) {
          return TextField(
            controller: controller,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => onSubmit(),
            cursorColor: AppColors.red,
            style: const TextStyle(fontSize: 16),
            decoration: InputDecoration(
              hintText: hint,
              prefixIcon: Icon(icon, color: AppColors.textDim),
              suffixIcon: value.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Borrar búsqueda',
                      icon: Icon(Icons.close_rounded,
                          color: AppColors.textDim),
                      onPressed: controller.clear,
                    ),
            ),
          );
        },
      ),
    );
  }
}

/// Título de AppBar con la regla del modo: mayúsculas en rock, normal en Pulso.
class AppTitle extends StatelessWidget {
  const AppTitle(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(MusicModeService.general ? text : text.toUpperCase());
}
