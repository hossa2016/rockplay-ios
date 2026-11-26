import 'package:flutter/foundation.dart';

/// Pide cambiar de pestaña principal (0 Inicio, 1 Buscar, 2 Mi música,
/// 3 Asistente). Lo escucha la pantalla principal.
final ValueNotifier<int> mainTabWant = ValueNotifier<int>(-1);
