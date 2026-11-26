import 'package:flutter/material.dart';

/// Diálogo de progreso que no se cierra tocando fuera. Devuelve una
/// función para actualizar el texto y otra para cerrarlo.
(void Function(String), void Function()) showProgress(
    BuildContext context, String text) {
  final msg = ValueNotifier<String>(text);
  var open = true;
  final nav = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (c) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(children: [
          const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5)),
          const SizedBox(width: 16),
          Expanded(
            child: ValueListenableBuilder<String>(
              valueListenable: msg,
              builder: (_, t, __) => Text(t),
            ),
          ),
        ]),
      ),
    ),
  );
  return (
    (t) => msg.value = t,
    () {
      if (open) {
        open = false;
        nav.pop();
      }
    },
  );
}
