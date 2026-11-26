import 'dart:convert';

import '../models/song.dart';
import 'ai_client.dart';
import 'ai_settings.dart';
import 'block_service.dart';
import 'artist_info_service.dart';
import 'artist_pools.dart';
import 'general_catalog.dart';
import 'music_mode.dart';
import 'mix_service.dart';
import 'stats_service.dart';

class AssistantResult {
  final String reply;
  final String title;
  final List<Song> songs;

  /// 'Groq', 'Gemini' o 'Reglas simples'.
  final String source;

  /// Avisos (por ejemplo, por qué falló un servicio).
  final String? note;

  const AssistantResult(this.reply, this.title, this.songs, this.source,
      [this.note]);
}

/// Cerebro del asistente: intenta Groq, luego Gemini y, si ninguno responde,
/// usa reglas simples con los mixes y artistas que ya conoce la app.
class AssistantService {
  AssistantService._();
  static final AssistantService instance = AssistantService._();

  static String get _system =>
      (MusicModeService.general ? _introGeneral : _introRock) + _rules0;

  static const String _introRock = '''
Eres el asistente musical de una app de rock llamada RockPlay IA. Hablas en español, con tono cercano y breve.
Armas listas de canciones REALES de rock (cualquier época y subgénero, incluido rock en español) según lo que pida la persona: estado de ánimo, momento del día, actividad, artistas parecidos o descubrimiento.
''';

  static const String _introGeneral = '''
Eres «Tu guía musical», el asistente de una app de música llamada Pulso. Hablas en español, con tono cercano y breve.
Armas listas de canciones REALES de cualquier género (pop, pop latino, salsa, reguetón y urbano, vallenato, rock, electrónica, jazz, clásica, baladas, merengue, bachata y más) según lo que pida la persona: estado de ánimo, momento del día, actividad, artistas parecidos o descubrimiento. Si pide un género, respétalo. Si no pide uno, VARÍA los géneros (al menos tres distintos en la lista) y no armes una lista solo de rock ni de metal salvo que lo pida.
''';

  static const String _rules0 = '''
Reglas:
- Devuelve SOLO un objeto JSON con esta forma exacta: {"reply":"texto corto (máx. 2 frases)","title":"nombre corto de la lista","songs":[{"artist":"...","title":"..."}]}
- Entre __MIN__ y __MAX__ canciones, todas distintas. Mezcla canciones conocidas con algunas menos conocidas que encajen con sus gustos.
- No repitas artistas más de 2 veces y no pongas dos canciones seguidas del mismo artista. No inventes canciones: si dudas de una, no la incluyas.
- Si la persona pide cambiar la lista anterior (más tranquilo, más pesado, solo en español...), ajusta según eso.
- Usa el contexto de gustos solo para personalizar; no lo recites.
''';

  Future<String> _context() async {
    await AiSettings.instance.load();
    if (!AiSettings.instance.learn) return '';
    final b = StringBuffer();
    if (MusicModeService.general && PulsoPrefs.favGenres.value.isNotEmpty) {
      b.write('Géneros que más le gustan (úsalos como base cuando no pida uno): ');
      b.writeln(PulsoPrefs.favGenres.value.join(', '));
    }
    try {
      final plays = await StatsService.instance.plays(days: 60);
      final top = StatsService.topArtists(plays, n: 8);
      if (top.isNotEmpty) {
        b.write('Artistas que más escucha últimamente: ');
        b.writeln(top.map((e) => e.name).join(', '));
      }
      final fav = await MixService.personalArtists();
      if (fav.isNotEmpty) {
        b.write('Artistas de sus favoritos e historial: ');
        b.writeln(fav.take(12).join(', '));
      }
    } catch (_) {}
    final h = DateTime.now().hour;
    final part = h < 6
        ? 'madrugada'
        : h < 12
            ? 'mañana'
            : h < 19
                ? 'tarde'
                : 'noche';
    b.write('Momento del día ahora: $part.');
    return b.toString();
  }

  /// ¿Pide música nueva? La IA no conoce lo reciente, así que se resuelve
  /// con datos reales de Deezer.
  static bool _wantsNew(String text) {
    final t = text.toLowerCase();
    final y = DateTime.now().year;
    return t.contains('lanzamiento') ||
        RegExp(r'(últimos|ultimos|pasados)\s+(\d+|dos|tres)\s+años').hasMatch(t) ||
        t.contains('estreno') ||
        t.contains('recién salid') ||
        t.contains('recien salid') ||
        t.contains('reciente') ||
        t.contains('$y') ||
        t.contains('${y - 1}');
  }

  Future<AssistantResult?> _releases(String text) async {
    try {
      final now = DateTime.now();
      var year = now.year;
      var last = now.year;
      final m = RegExp(r'20\d\d').firstMatch(text);
      if (m != null) {
        year = int.parse(m.group(0)!);
        last = year;
      }
      final r2 = RegExp(r'(\d+|dos|tres)\s+años').firstMatch(text.toLowerCase());
      if (r2 != null) {
        final w = r2.group(1)!;
        final n = w == 'dos' ? 2 : w == 'tres' ? 3 : (int.tryParse(w) ?? 1);
        if (n >= 2 && n <= 5) {
          year = now.year - (n - 1);
          last = now.year;
        }
      }
      final from = DateTime(year, 1, 1);
      final days = now.difference(from).inDays + 1;
      if (days < 1) return null;

      final names = <String>{};
      try {
        names.addAll(await MixService.personalArtists());
      } catch (_) {}
      final pool = <String>{
        if (MusicModeService.general)
          for (final e in GeneralCatalog.pools.values) ...e
        else ...[
          for (final k in const ['Rock clásico', 'Rock en español'])
            ...?kMixArtistPools[k],
          for (final e in kMixArtistPools.values) ...e,
        ],
      }.toList()
        ..shuffle();
      names.addAll(pool.take(130));

      // Por tandas: Deezer limita las peticiones y, si se piden todas a la
      // vez, muchas fallan en silencio.
      final all = names.toList();
      var rel = <ReleaseItem>[];
      for (var i = 0; i < all.length && rel.length < 70; i += 10) {
        final part = await ArtistInfoService.instance
            .recentReleases(all.skip(i).take(10).toList(), days: days, max: 60);
        final have = {for (final r in rel) '${r.artist}|${r.album.title}'};
        for (final r in part) {
          if (have.add('${r.artist}|${r.album.title}')) rel.add(r);
        }
        if (i + 10 < all.length) {
          await Future<void>.delayed(const Duration(milliseconds: 900));
        }
      }
      rel = [
        for (final r in rel)
          if (r.album.year != null &&
              r.album.year! >= year &&
              r.album.year! <= last)
            r
      ];
      // Sin reediciones, en vivo ni recopilatorios; máximo 2 discos por banda.
      final bad = RegExp(
          r'\blive\b|en vivo|reissue|remaster|anniversary|aniversario|deluxe|'
          r'greatest|best of|collection|box set|expanded|\bdemos?\b|karaoke|'
          r'tribute|instrumental|director|\bversion\b|\bremix',
          caseSensitive: false);
      final perArtist = <String, int>{};
      rel.shuffle();
      rel = [
        for (final r in rel)
          if (!bad.hasMatch(r.album.title) &&
              (perArtist[r.artist] = (perArtist[r.artist] ?? 0) + 1) <= 3)
            r
      ];
      if (rel.length < 3) return null;

      final songs = <Song>[];
      final seen = <String>{};
      for (var i = 0; i < rel.length && songs.length < AiSettings.instance.maxSongs; i += 6) {
        final chunk = rel.skip(i).take(6).toList();
        final lists = await Future.wait([
          for (final r in chunk)
            ArtistInfoService.instance
                .albumTracks(r.album, r.artist)
                .catchError((Object _) => <Song>[]),
        ]);
        for (final l in lists) {
          for (final s in l.take(4)) {
            if (!bad.hasMatch(s.title) &&
                seen.add('${s.artist}|${s.title}'.toLowerCase())) songs.add(s);
          }
        }
      }
      if (songs.length < 5) return null;
      return AssistantResult(
        'Estos son lanzamientos reales de ${year == last ? '$year' : '$year a $last'} de ${byMode('bandas', 'artistas')} que te pueden gustar.',
        year == last ? 'Lanzamientos $year' : 'Lanzamientos $year-$last',
        songs,
        'Deezer',
      );
    } catch (_) {
      return null;
    }
  }

  /// Pide la lista y la recorta al máximo configurado.
  Future<AssistantResult> ask(String text, List<AiMessage> history) async {
    await BlockService.instance.ensureLoaded();
    final r = await _ask(text, history);
    final mx = AiSettings.instance.maxSongs;
    final songs = BlockService.instance.filter(r.songs);
    if (songs.length <= mx && songs.length == r.songs.length) return r;
    return AssistantResult(r.reply, r.title, songs.take(mx).toList(),
        r.source, r.note);
  }

  Future<AssistantResult> _ask(String text, List<AiMessage> history) async {
    await AiSettings.instance.load();
    var releaseFailed = false;
    if (_wantsNew(text)) {
      final r = await _releases(text);
      if (r != null) return r;
      releaseFailed = true;
    }
    await AiSettings.instance.load();
    final ctx = await _context();
    final mx = AiSettings.instance.maxSongs;
    final base = _system
        .replaceAll('__MAX__', '$mx')
        .replaceAll('__MIN__', '${mx >= 40 ? mx - 10 : mx - 5}');
    final system = ctx.isEmpty
        ? base
        : MusicModeService.general
            ? '$base\nContexto (solo una pista menor: como máximo 3 canciones de estos artistas en toda la lista; el resto, de otros artistas y géneros):\n$ctx'
            : '$base\nContexto:\n$ctx';
    final msgs = <AiMessage>[
      ...history.length > 6 ? history.sublist(history.length - 6) : history,
      AiMessage(true, text),
    ];

    final notes = <String>[
      if (releaseFailed)
        'No pude consultar lanzamientos reales; esta lista es de la IA y puede no ser tan reciente. Vuelve a pedirla en un momento.',
    ];
    final tries = <MapEntry<String, Future<String> Function()>>[
      MapEntry('Gemini', () => AiClient.instance.gemini(system, msgs)),
      MapEntry('Groq', () => AiClient.instance.groq(system, msgs)),
    ];
    for (final t in tries) {
      try {
        final raw = await t.value();
        final r = _parse(raw, t.key);
        if (r != null) {
          final songs = await _balance(r.songs);
          return AssistantResult(r.reply, r.title, songs, t.key,
              notes.isEmpty ? null : notes.join(' · '));
        }
        notes.add('${t.key}: respuesta no válida');
      } on AiFailure catch (e) {
        if (e.reason != 'sin clave') notes.add(e.toString());
      } catch (_) {
        notes.add('${t.key}: error inesperado');
      }
    }
    final r = await _rules(text);
    return AssistantResult(r.reply, r.title, r.songs, 'Reglas simples',
        notes.isEmpty ? null : notes.join(' · '));
  }

  /// Máximo 2 canciones por artista y artistas intercalados (que no salgan
  /// tres seguidas del mismo). En «Todos los géneros», los artistas de tu
  /// historial ocupan como mucho 3 puestos, para no volver a lo mismo.
  Future<List<Song>> _balance(List<Song> songs) async {
    final known = <String>{};
    if (MusicModeService.general) {
      try {
        final plays = await StatsService.instance.plays(days: 60);
        known.addAll(StatsService.topArtists(plays, n: 8)
            .map((e) => e.name.toLowerCase()));
        known.addAll(
            (await MixService.personalArtists()).map((e) => e.toLowerCase()));
      } catch (_) {}
    }
    final per = <String, int>{};
    var fromKnown = 0;
    final byArtist = <String, List<Song>>{};
    for (final s in songs) {
      final a = s.artist.toLowerCase().trim();
      if ((per[a] ?? 0) >= 2) continue;
      if (known.contains(a)) {
        if (fromKnown >= 3) continue;
        fromKnown++;
      }
      per[a] = (per[a] ?? 0) + 1;
      byArtist.putIfAbsent(a, () => []).add(s);
    }
    // Intercala: una de cada artista por vuelta, en el orden que dio la IA.
    final out = <Song>[];
    var round = 0;
    var added = true;
    while (added) {
      added = false;
      for (final l in byArtist.values) {
        if (round < l.length) {
          out.add(l[round]);
          added = true;
        }
      }
      round++;
    }
    return out.length >= 3 ? out : songs;
  }

  AssistantResult? _parse(String raw, String source) {
    try {
      final a = raw.indexOf('{');
      final z = raw.lastIndexOf('}');
      if (a < 0 || z <= a) return null;
      final j = jsonDecode(raw.substring(a, z + 1));
      final songs = <Song>[];
      final seen = <String>{};
      for (final e in (j['songs'] as List? ?? const [])) {
        if (e is! Map) continue;
        final artist = (e['artist'] ?? '').toString().trim();
        final title = (e['title'] ?? '').toString().trim();
        if (artist.isEmpty || title.isEmpty) continue;
        if (!seen.add('${artist.toLowerCase()}|${title.toLowerCase()}')) {
          continue;
        }
        songs.add(Song(
            title: title, artist: artist, query: '$artist $title'));
      }
      if (songs.length < 3) return null;
      final title = (j['title'] ?? '').toString().trim();
      final reply = (j['reply'] ?? '').toString().trim();
      return AssistantResult(
        reply.isEmpty ? 'Armé esta lista para ti.' : reply,
        title.isEmpty ? 'Lista del asistente' : title,
        songs,
        source,
      );
    } catch (_) {
      return null;
    }
  }

  // ---------- Reglas simples (sin IA) ----------

  static const Map<String, List<String>> _keywords = {
    'Energía': ['energ', 'pesado', 'fuerte', 'animad', 'subir', 'metal'],
    'Fiesta': ['fiesta', 'rumba', 'bailar', 'baile', 'parche', 'farra'],
    'Para entrenar': ['entren', 'gym', 'gimnasio', 'correr', 'ejercicio'],
    'Para manejar': ['manej', 'carretera', 'viaje', 'conducir'],
    'Tranquilo': [
      'tranquil',
      'relaj',
      'calma',
      'melanc',
      'triste',
      'concentr',
      'estudi',
      'dormir',
      'lento',
      'suave'
    ],
    'Nostalgia': ['nostalg', 'clásic', 'clasic', 'viejo', 'recuerd', 'antigu'],
  };

  Future<AssistantResult> _rules(String text) async {
    final t = text.toLowerCase();
    final artists = <String>[];
    String title = 'Mix del asistente';
    String reply = 'Sin IA disponible, armé esta lista con mis reglas simples.';

    for (final e in _keywords.entries) {
      if (e.value.any(t.contains)) {
        final found = MixService.mood.where((x) => x.title == e.key);
        if (found.isEmpty) continue;
        final m = found.first;
        artists.addAll(MixService.pool(m));
        title = m.title;
        reply = 'Armé una lista "${m.title}" para ti (modo reglas simples).';
        break;
      }
    }
    if (MusicModeService.general) {
      // ¿Nombró un género? (salsa, vallenato, pop…)
      for (final g in MixService.genre) {
        final k = g.title.toLowerCase();
        if (RegExp('(^|[^a-záéíóúñ])${RegExp.escape(k)}(\$|[^a-záéíóúñ])').hasMatch(t) ||
            (k == 'reguetón' && (t.contains('regueton') || t.contains('urbano')))) {
          // El género manda sobre el ánimo.
          artists
            ..clear()
            ..addAll(MixService.pool(g));
          title = g.title;
          reply = 'Armé una lista de ${g.title.toLowerCase()} (modo reglas simples).';
          break;
        }
      }
    } else if (t.contains('español') || t.contains('espanol')) {
      artists.addAll(kMixArtistPools['Rock en español'] ?? const <String>[]);
      title = 'Rock en español';
      reply = 'Armé una lista de rock en español (modo reglas simples).';
    }
    if (t.contains('nuev') || t.contains('descubr') || t.contains('algo diferente')) {
      artists.addAll(await MixService.personalArtists());
      title = 'Para descubrir';
    }
    if (artists.isEmpty) {
      final personal = await MixService.personalArtists();
      artists.addAll(personal);
      artists.addAll(MusicModeService.general
          ? (GeneralCatalog.pools['Pop latino'] ?? const <String>[])
          : (kMixArtistPools['Rock clásico'] ?? const <String>[]));
      title = 'Mix del asistente';
    }
    final uniq = <String>{...artists}.toList();
    var songs = <Song>[];
    await for (final l in MixService.buildMix(uniq, pick: AiSettings.instance.maxSongs < 40 ? AiSettings.instance.maxSongs : 40, perArtist: 3)) {
      songs = l;
    }
    return AssistantResult(reply, title, songs, 'Reglas simples');
  }
}
