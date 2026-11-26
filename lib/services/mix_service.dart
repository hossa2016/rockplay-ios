import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../models/song.dart';
import 'artist_pools.dart';
import 'general_catalog.dart';
import 'music_mode.dart';
import 'library_service.dart';
import 'music_api_service.dart';
import 'data_saver.dart';
import 'block_service.dart';
import '../theme/app_theme.dart';
import 'stats_service.dart';

class MixDef {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> colors;
  final List<String> artists;

  const MixDef(this.title, this.subtitle, this.icon, this.colors, this.artists);
}

/// Mixes armados con canciones de YouTube de varios artistas a la vez.
class MixService {
  static List<MixDef> get genre =>
      MusicModeService.general ? GeneralCatalog.genre : _rockGenre;
  static List<MixDef> get mood =>
      MusicModeService.general ? GeneralCatalog.mood : _rockMood;

  static List<MixDef> get _rockGenre => [
    MixDef('Rock clásico', '70s', Icons.album_rounded,
        AppPalettes.amber, [
      'Led Zeppelin', 'Deep Purple', 'Pink Floyd', 'Queen',
      'The Rolling Stones', 'Black Sabbath', 'The Who', 'Lynyrd Skynyrd',
    ]),
    MixDef('Rock 80s', 'Himnos y guitarras', Icons.bolt_rounded,
        AppPalettes.fire, [
      "Guns N' Roses", 'AC/DC', 'Bon Jovi', 'Def Leppard', 'Van Halen',
      'Scorpions', 'Journey', 'Europe',
    ]),
    MixDef('Grunge y 90s', 'Camisas de franela', Icons.grain_rounded,
        AppPalettes.brass, [
      'Nirvana', 'Pearl Jam', 'Soundgarden', 'Alice In Chains',
      'Stone Temple Pilots', 'Foo Fighters', 'Red Hot Chili Peppers',
      'Green Day',
    ]),
    MixDef('Alternativo 2000s', 'Nu metal y emo', Icons.graphic_eq_rounded,
        AppPalettes.graphite, [
      'Linkin Park', 'Green Day', 'Fall Out Boy', 'My Chemical Romance',
      'The Killers', 'Muse', 'Paramore', 'Evanescence',
    ]),
    MixDef('Heavy metal', 'Pesado', Icons.local_fire_department_rounded,
        AppPalettes.wine, [
      'Metallica', 'Iron Maiden', 'Megadeth', 'Judas Priest', 'Slayer',
      'Pantera', 'Dio', 'Motörhead',
    ]),
    MixDef('Punk rock', 'Rápido y directo', Icons.flash_on_rounded,
        AppPalettes.rust, [
      'Ramones', 'The Clash', 'Sex Pistols', 'Blink-182', 'Sum 41',
      'Rancid', 'The Offspring', 'Bad Religion',
    ]),
    MixDef('Rock en español', 'Clásicos', Icons.language_rounded,
        AppPalettes.burgundy, [
      'Soda Stereo', 'Maná', 'Enanitos Verdes', 'Caifanes',
      'Héroes del Silencio', 'Los Prisioneros', 'Fito Páez', 'La Ley',
    ]),
    MixDef('Baladas rock', 'Para cantar', Icons.favorite_rounded,
        AppPalettes.fire, [
      'Scorpions', 'Bon Jovi', 'Aerosmith', "Guns N' Roses", 'Extreme',
      'Journey', 'Heart', 'Whitesnake',
    ]),
    MixDef('Hard rock', 'Riffs', Icons.music_note_rounded,
        AppPalettes.amber, [
      'AC/DC', 'Aerosmith', 'Kiss', 'Whitesnake', 'Mötley Crüe',
      'Foreigner', 'Van Halen', 'Deep Purple',
    ]),
    MixDef('Indie y brit', 'Guitarras claras', Icons.wb_twilight_rounded,
        AppPalettes.steel, [
      'Arctic Monkeys', 'The Strokes', 'Radiohead', 'Coldplay', 'Oasis',
      'Blur', 'Franz Ferdinand', 'Kings of Leon',
    ]),
  ];

  static List<MixDef> get _rockMood => [
    MixDef('Energía', 'Sube el volumen', Icons.bolt_rounded,
        AppPalettes.fire, [
      'Rage Against the Machine', 'Metallica', 'Linkin Park',
      'System of a Down', 'Slipknot', 'Disturbed', 'Pantera', 'Papa Roach',
    ]),
    MixDef('Para entrenar', 'Sin pausa', Icons.fitness_center_rounded,
        AppPalettes.rust, [
      'Disturbed', 'Godsmack', 'Five Finger Death Punch', 'Shinedown',
      'Breaking Benjamin', 'Avenged Sevenfold', 'Trivium', 'Rammstein',
    ]),
    MixDef('Para manejar', 'Carretera', Icons.directions_car_rounded,
        AppPalettes.steel, [
      'Tom Petty', 'Foo Fighters', 'Queen', 'AC/DC',
      'Creedence Clearwater Revival', 'Eagles', 'Bruce Springsteen',
      'Red Hot Chili Peppers',
    ]),
    MixDef('Tranquilo', 'Bajando revoluciones', Icons.nightlight_round,
        AppPalettes.graphite, [
      'Pink Floyd', 'Radiohead', 'Coldplay', 'The Cranberries',
      'Snow Patrol', 'Oasis', 'Eagles', 'Evanescence',
    ]),
    MixDef('Nostalgia', 'Los de siempre', Icons.history_rounded,
        AppPalettes.amber, [
      'Bon Jovi', 'Queen', "Guns N' Roses", 'Journey', 'Europe',
      'Scorpions', 'Aerosmith', 'Def Leppard',
    ]),
  ];

  /// Artistas adicionales por mix: se elige al azar entre todos cada vez.
  static const Map<String, List<String>> _extra = {
    'Rock clásico': ['Cream', 'Jimi Hendrix', 'The Doors', 'Creedence Clearwater Revival', 'Santana', 'Eagles', 'Kansas', 'Boston'],
    'Rock 80s': ['Dire Straits', 'Twisted Sister', 'Poison', 'Whitesnake', 'Foreigner', 'Toto', 'Survivor', 'Kiss'],
    'Grunge y 90s': ['Bush', 'Live', 'Collective Soul', 'Soul Asylum', 'Hole', 'The Smashing Pumpkins', 'Rage Against the Machine', 'Candlebox'],
    'Alternativo 2000s': ['Three Days Grace', 'Breaking Benjamin', 'Nickelback', 'Hoobastank', 'Simple Plan', '30 Seconds to Mars', 'Panic! at the Disco', 'Good Charlotte'],
    'Heavy metal': ['Sepultura', 'Anthrax', 'Testament', 'Ozzy Osbourne', 'Dream Theater', 'Accept', 'Helloween', 'Black Label Society'],
    'Punk rock': ['Green Day', 'Social Distortion', 'NOFX', 'Pennywise', 'Descendents', 'Dead Kennedys', 'Simple Plan', 'Good Charlotte'],
    'Rock en español': ['Café Tacvba', 'Los Fabulosos Cadillacs', 'Zoé', 'Molotov', 'Hombres G', 'Bunbury', 'Charly García', 'Gustavo Cerati', 'Andrés Calamaro', 'Divididos', 'Los Auténticos Decadentes'],
    'Baladas rock': ['Mr. Big', 'Cinderella', 'Poison', 'Skid Row', 'Chicago', 'Bryan Adams', 'Foreigner', 'REO Speedwagon'],
    'Hard rock': ["Guns N' Roses", 'Bad Company', 'Thin Lizzy', 'Rainbow', 'Skid Row', 'Ratt', 'Dokken', 'Cinderella'],
    'Indie y brit': ['The Killers', 'Vampire Weekend', 'Tame Impala', 'Interpol', 'Pixies', 'The Smiths', 'Placebo', 'Keane', 'Snow Patrol'],
    'Energía': ['Korn', 'Limp Bizkit', 'Rammstein', 'Megadeth', 'Sepultura', 'Static-X', 'Mudvayne', 'Metallica'],
    'Para entrenar': ['Metallica', 'Korn', 'Limp Bizkit', 'Rob Zombie', 'Bullet for My Valentine', 'Sevendust', 'Seether', 'Three Days Grace'],
    'Para manejar': ['Dire Straits', 'ZZ Top', 'Bob Seger', 'Lynyrd Skynyrd', 'Fleetwood Mac', 'The Black Keys', 'Kings of Leon', 'Aerosmith'],
    'Tranquilo': ['Pearl Jam', 'Nirvana', 'Fleetwood Mac', 'Dire Straits', 'Keane', 'The Verve', 'Travis', 'Lifehouse'],
    'Nostalgia': ['Kiss', 'Whitesnake', 'Poison', 'Mötley Crüe', 'Skid Row', 'Twisted Sister', 'Cinderella', 'Foreigner'],
  };

  /// Artistas de otros mixes parecidos, para completar hasta ~100.
  static const Map<String, List<String>> _neighbors = {
    'Rock clásico': ['Hard rock', 'Rock 80s', 'Nostalgia'],
    'Rock 80s': ['Hard rock', 'Baladas rock', 'Nostalgia', 'Rock clásico'],
    'Grunge y 90s': ['Alternativo 2000s', 'Punk rock', 'Indie y brit'],
    'Alternativo 2000s': ['Grunge y 90s', 'Punk rock', 'Indie y brit'],
    'Heavy metal': ['Hard rock', 'Energía', 'Para entrenar'],
    'Punk rock': ['Alternativo 2000s', 'Grunge y 90s'],
    'Rock en español': [],
    'Baladas rock': ['Rock 80s', 'Hard rock', 'Tranquilo'],
    'Hard rock': ['Rock 80s', 'Rock clásico', 'Heavy metal'],
    'Indie y brit': ['Alternativo 2000s', 'Grunge y 90s', 'Tranquilo'],
    'Energía': ['Heavy metal', 'Alternativo 2000s', 'Punk rock', 'Hard rock'],
    'Para entrenar': ['Heavy metal', 'Energía', 'Alternativo 2000s', 'Hard rock'],
    'Para manejar': ['Rock clásico', 'Hard rock', 'Rock 80s', 'Grunge y 90s'],
    'Tranquilo': ['Baladas rock', 'Indie y brit', 'Grunge y 90s', 'Rock clásico'],
    'Nostalgia': ['Rock clásico', 'Rock 80s', 'Hard rock', 'Baladas rock'],
  };

  /// Más rock en español (para llegar a ~100 sin mezclar otros idiomas).
  static const List<String> _esExtra = [
    'Los Rodríguez', 'Attaque 77', 'Los Piojos', 'Patricio Rey y sus Redonditos de Ricota',
    'Babasónicos', 'Intoxicados', 'La Renga', 'Vicentico', 'Los Pericos', 'Árbol',
    'Jaguares', 'El Tri', 'Mägo de Oz', 'Barón Rojo', 'Rosendo', 'Extremoduro',
    'Platero y Tú', 'Los Suaves', 'Fito y Fitipaldis', 'Leiva', 'Vetusta Morla',
    'Love of Lesbian', 'Sôber', 'Obús', 'Aterciopelados', 'Kraken', 'Don Tetto',
    'Diamante Eléctrico', 'Los Bunkers', 'Los Tres', 'Lucybell', 'Chancho en Piedra',
    'Maldita Vecindad', 'Enjambre', 'Panteón Rococó', 'Moderatto', 'Almafuerte',
    'Hermética', 'Sumo', 'Los Violadores', 'Virus', 'Pappo', 'Vox Dei',
    'Luis Alberto Spinetta', 'Las Pelotas', 'Bersuit Vergarabat', 'Cuarteto de Nos',
    'No Te Va Gustar', 'La Vela Puerca', 'Ratones Paranoicos', 'Los Abuelos de la Nada',
    'Miguel Mateos', 'Radio Futura', 'Nacha Pop', 'Los Secretos', 'Mecano',
  ];

  static List<String> _own(MixDef m) => MusicModeService.general
      ? <String>{
          ...m.artists,
          ...(GeneralCatalog.pools[m.title] ?? const <String>[]),
        }.toList()
      : <String>{
          ...(kMixArtistPools[m.title] ?? const <String>[]),
          ...m.artists,
          ...(_extra[m.title] ?? const <String>[]),
          if (m.title == 'Rock en español') ..._esExtra,
        }.toList();

  /// Artistas del mix (primero los propios, al azar; luego los de mixes
  /// parecidos, al azar), sin repetir. Úsalo con `keepOrder: true`.
  static List<String> pool(MixDef m) {
    final own = _own(m)..shuffle();
    final seen = <String>{...own};
    final extra = <String>[];
    final nb = MusicModeService.general ? GeneralCatalog.neighbors : _neighbors;
    for (final t in nb[m.title] ?? const <String>[]) {
      final def = [...genre, ...mood].where((d) => d.title == t);
      if (def.isEmpty) continue;
      for (final a in _own(def.first)) {
        if (seen.add(a)) extra.add(a);
      }
    }
    extra.shuffle();
    return [...own, ...extra];
  }

  static String _cleanArtist(String a) => SongMeta.cleanChannel(a);

  /// Artistas de arranque de cada modo (cuando aún hay pocos datos).
  static List<String> get modeSeeds => MusicModeService.general
      ? const ['Shakira', 'Karol G', 'Carlos Vives', 'Grupo Niche',
          'Bad Bunny', 'Dua Lipa', 'Morat', 'Silvestre Dangond']
      : const ['Metallica', 'Linkin Park', 'Nirvana', 'Queen', 'AC/DC',
          'Foo Fighters', "Guns N' Roses", 'Soda Stereo'];

  static List<String>? _paCache;
  static String _paMode = '';
  static DateTime _paAt = DateTime(2000);

  /// Artistas más presentes en favoritos (peso 2), historial (peso 1) y
  /// escuchas de los últimos 30 días (1 por escucha).
  static Future<List<String>> personalArtists() async {
    final mk = modeKey('pa');
    if (_paCache != null &&
        _paMode == mk &&
        DateTime.now().difference(_paAt) < const Duration(minutes: 10)) {
      return _paCache!;
    }
    final score = <String, int>{};
    final display = <String, String>{};
    final titles = <String>{};
    void add(List<Song> list, int w) {
      for (final s in list) titles.add(SongMeta.artistKey(s.title));
      for (final s in list) {
        final a = _cleanArtist(s.artist);
        if (a.isEmpty || !SongMeta.isPlausibleArtist(a)) continue;
        final k = SongMeta.artistKey(a);
        if (k.isEmpty) continue;
        display.putIfAbsent(k, () => a);
        score[k] = (score[k] ?? 0) + w;
      }
    }

    try {
      add(await LibraryService.instance.favorites(), 2);
      add(await LibraryService.instance.history(), 1);
    } catch (_) {}
    // Las escuchas también cuentan: el historial guarda cada canción una
    // sola vez, así que 6 escuchas de un artista valían 1.
    try {
      for (final p in await StatsService.instance.plays(days: 30)) {
        final a = _cleanArtist(p.artist);
        if (a.isEmpty || !SongMeta.isPlausibleArtist(a)) continue;
        final k = SongMeta.artistKey(a);
        if (k.isEmpty) continue;
        display.putIfAbsent(k, () => a);
        score[k] = (score[k] ?? 0) + 1;
      }
    } catch (_) {}
    // Fuera: nombres que en realidad son títulos de canción («Killing In
    // The Name» guardado como artista) y los que aparecen una sola vez.
    final keys = score.keys
        .where((k) => score[k]! >= 2 && !titles.contains(k))
        .toList()
      ..sort((a, b) => score[b]!.compareTo(score[a]!));
    final out = [for (final k in keys.take(30)) display[k]!];
    _paCache = out;
    _paMode = mk;
    _paAt = DateTime.now();
    return out;
  }

  /// Emite la lista acumulada (intercalando artistas) a medida que llegan
  /// resultados de YouTube.
  static Stream<List<Song>> buildMix(List<String> artists,
      {int pick = 70, int perArtist = 4, bool keepOrder = false}) {
    final ctrl = StreamController<List<Song>>();
    final names = List<String>.of(artists);
    if (!keepOrder) names.shuffle();
    final maxA = DataSaver.instance.mixArtists;
    final maxS = DataSaver.instance.mixSongs;
    final chosen = names.take(pick < maxA ? pick : maxA).toList();
    final api = MusicApiService();
    final got = List<List<Song>>.filled(chosen.length, <Song>[]);
    var cancelled = false;
    var pending = chosen.length;

    void emit() {
      if (cancelled || ctrl.isClosed) return;
      final seen = <String>{};
      final out = <Song>[];
      var i = 0;
      var any = true;
      while (any) {
        any = false;
        for (final l in got) {
          if (i < l.length) {
            any = true;
            if (!BlockService.instance.isBlockedSong(l[i]) && seen.add(l[i].videoId)) out.add(l[i]);
          }
        }
        i++;
      }
      ctrl.add(out.length > maxS ? out.take(maxS).toList() : out);
    }

    ctrl.onCancel = () {
      cancelled = true;
      try {
        api.dispose();
      } catch (_) {}
    };

    if (chosen.isEmpty) {
      ctrl.close();
      return ctrl.stream;
    }
    Future<void> job(int i) async {
      try {
        // Sufijo aleatorio y reserva: cada mix sale distinto.
        const suffixes = ['official audio', 'lyrics', 'official video', 'audio'];
        final suffix = suffixes[Random().nextInt(suffixes.length)];
        List<Song> last = <Song>[];
        await for (final l in api.searchStream('${chosen[i]} $suffix',
            max: perArtist * 3, maxPages: 2, mustMention: chosen[i])) {
          if (cancelled) return;
          last = l;
          got[i] = l.take(perArtist).toList();
          emit();
        }
        final pool = List<Song>.of(last)..shuffle();
        got[i] = pool.take(perArtist).toList();
        emit();
      } catch (_) {
      } finally {
        pending--;
        if (pending == 0 && !cancelled && !ctrl.isClosed) {
          try {
            api.dispose();
          } catch (_) {}
          ctrl.close();
        }
      }
    }

    // Máximo 8 búsquedas a la vez.
    var nextJob = 0;
    Future<void> worker() async {
      while (!cancelled) {
        final i = nextJob++;
        if (i >= chosen.length) return;
        await job(i);
      }
    }

    for (var w = 0; w < 14; w++) {
      worker();
    }
    return ctrl.stream;
  }
}
