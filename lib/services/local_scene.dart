import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'mix_service.dart';
import 'music_mode.dart';

/// «Hecho en Colombia»: la escena local curada a mano (rock en RockPlay,
/// géneros colombianos en Pulso). Los mixes se completan con artistas
/// parecidos al sonar.
class LocalScene {
  LocalScene._();

  static const Map<String, List<String>> _rockCities = {
    'Bogotá': [
      'Aterciopelados', 'Diamante Eléctrico', '1280 Almas', 'Doctor Krápula',
      'La Pestilencia', 'Revólver Plateado', 'Ultrágeno', 'The Mills',
      'Los Petit Fellas', 'Don Tetto', 'Ciegossordomudos',
    ],
    'Medellín': [
      'Kraken', 'Masacre', 'Ekhymosis', 'Pornomotora', 'Parabellum',
      'Tenebrarum', 'Nepentes', 'Witchtrap',
    ],
  };

  /// Filtros de ciudad (rock) o de género (Pulso).
  static List<String> get filters => MusicModeService.general
      ? const ['Todo', 'Salsa', 'Vallenato', 'Urbano', 'Pop', 'Tropical']
      // Cali vuelve cuando haya al menos 4 bandas confirmadas.
      : const ['Todo', 'Bogotá', 'Medellín'];

  static List<MixDef> mixes(String filter) {
    final c = AppPalettes.cards;
    if (MusicModeService.general) {
      final all = <MixDef>[
        MixDef('Salsa caleña', 'Niche, Guayacán y más', Icons.music_note_rounded, c[0],
            const ['Grupo Niche', 'Guayacán Orquesta', 'Orquesta La 33', 'Fruko y sus Tesos', 'Joe Arroyo']),
        MixDef('Vallenato', 'Vives, Silvestre y más', Icons.piano_rounded, c[1],
            const ['Carlos Vives', 'Silvestre Dangond', 'Jorge Celedón', 'Diomedes Díaz', 'Binomio de Oro', 'Peter Manjarrés']),
        MixDef('Urbano paisa', 'Medellín al mundo', Icons.graphic_eq_rounded, c[2],
            const ['J Balvin', 'Karol G', 'Maluma', 'Feid', 'Blessd', 'Ryan Castro', 'Reykon']),
        MixDef('Pop colombiano', 'Shakira, Morat y más', Icons.star_rounded, c[3],
            const ['Shakira', 'Juanes', 'Morat', 'Camilo', 'Sebastián Yatra', 'Fonseca']),
        MixDef('Cumbia y tropical', 'De la costa al mundo', Icons.waves_rounded, c[4],
            const ['Totó la Momposina', 'Lucho Bermúdez', 'Pastor López', 'Bomba Estéreo', 'Los Corraleros de Majagual']),
      ];
      if (filter == 'Todo') return all;
      // Filtro → mix (antes un substring(0, 4) fallaba con «Pop»).
      const map = {
        'Salsa': 'Salsa caleña',
        'Vallenato': 'Vallenato',
        'Urbano': 'Urbano paisa',
        'Pop': 'Pop colombiano',
        'Tropical': 'Cumbia y tropical',
      };
      return all.where((m) => m.title == map[filter]).toList();
    }
    final out = <MixDef>[];
    if (filter == 'Todo') {
      out.add(MixDef('Leyendas de Rock al Parque', 'Bandas colombianas del festival',
          Icons.festival_rounded, c[0], const [
        'Aterciopelados', 'Kraken', 'La Pestilencia', '1280 Almas',
        'Doctor Krápula', 'Masacre', 'Diamante Eléctrico', 'Superlitio',
        'Ultrágeno', 'Ekhymosis',
      ]));
      out.add(MixDef('Metal paisa', 'Medellín pesado', Icons.bolt_rounded, c[2],
          const ['Masacre', 'Parabellum', 'Tenebrarum', 'Witchtrap', 'Nepentes', 'Kraken']));
    }
    var i = 3;
    for (final e in _rockCities.entries) {
      if (filter != 'Todo' && filter != e.key) continue;
      out.add(MixDef('Rock de ${e.key}', e.value.take(2).join(', '),
          Icons.location_city_rounded, c[i++ % c.length], e.value));
    }
    return out;
  }

  /// Todos los artistas de la escena (para el chip «Colombia» de Descubrir).
  static List<String> get artists {
    final s = <String>{};
    for (final m in mixes('Todo')) {
      s.addAll(m.artists);
    }
    return s.toList();
  }
}
