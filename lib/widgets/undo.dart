import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Aviso abajo con botón «Deshacer». Un solo estilo en toda la app.
void showUndo(BuildContext context, String message, VoidCallback onUndo) {
  final m = ScaffoldMessenger.of(context);
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(
    persist: false,
    duration: const Duration(seconds: 5),
    content: Text(message),
    action: SnackBarAction(label: 'Deshacer', onPressed: onUndo),
  ));
}

/// Pregunta antes de algo que no se puede deshacer. Devuelve true si acepta.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancelar')),
        TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(confirmLabel,
                style: TextStyle(color: AppColors.redText))),
      ],
    ),
  );
  return ok == true;
}
