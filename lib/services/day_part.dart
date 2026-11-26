/// Un solo reloj del día para toda la app: saludo, portada y mixes de
/// Inicio usan los mismos cortes (antes el saludo contaba la mañana
/// desde las 6 y lo demás desde las 5).
enum DayPart { madrugada, manana, tarde, noche }

DayPart dayPart([DateTime? t]) {
  final h = (t ?? DateTime.now()).hour;
  if (h < 5) return DayPart.madrugada;
  if (h < 12) return DayPart.manana;
  if (h < 19) return DayPart.tarde;
  return DayPart.noche;
}
