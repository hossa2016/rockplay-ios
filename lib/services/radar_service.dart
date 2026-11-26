import 'package:android_intent_plus/android_intent.dart';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'alarm_service.dart';
import 'concert_service.dart';
import 'library_service.dart';
import 'music_mode.dart';
import 'stats_service.dart';

/// Radar: conciertos de TUS bandas (las más escuchadas en 90 días, tus
/// favoritas y las que sigues), con aviso cuando aparece uno nuevo.
class RadarService {
  RadarService._();
  static final RadarService instance = RadarService._();

  static String get _followKey => modeKey('followed_v1');
  static const String _seenKey = 'radar_seen_v1';

  static String fold(String s) => s
      .toLowerCase()
      .replaceAll(RegExp('[áà]'), 'a')
      .replaceAll(RegExp('[éè]'), 'e')
      .replaceAll(RegExp('[íì]'), 'i')
      .replaceAll(RegExp('[óò]'), 'o')
      .replaceAll(RegExp('[úù]'), 'u')
      .replaceAll(RegExp(r'^the\s+'), '')
      .replaceAll(RegExp(r'[^a-z0-9ñ ]'), '')
      .trim();

  Future<List<String>> followed() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getStringList(_followKey) ?? const [];
  }

  Future<bool> isFollowed(String artist) async =>
      (await followed()).any((a) => fold(a) == fold(artist));

  Future<bool> toggleFollow(String artist) async {
    final sp = await SharedPreferences.getInstance();
    final l = List<String>.of(sp.getStringList(_followKey) ?? const []);
    final i = l.indexWhere((a) => fold(a) == fold(artist));
    if (i >= 0) {
      l.removeAt(i);
    } else {
      l.insert(0, artist);
    }
    await sp.setStringList(_followKey, l);
    return i < 0;
  }

  /// Tus bandas: seguidas + 20 más escuchadas (90 días) + de tus favoritas.
  Future<List<String>> bands() async {
    final out = <String>[];
    final seen = <String>{};
    void add(String a) {
      final k = fold(a);
      if (k.length >= 2 && seen.add(k)) out.add(a);
    }

    for (final a in await followed()) {
      add(a);
    }
    try {
      final plays = await StatsService.instance.plays(days: 90);
      for (final a in StatsService.topArtists(plays, n: 20)) {
        add(StatsService.cleanArtist(a.name));
      }
    } catch (_) {}
    try {
      for (final s in (await LibraryService.instance.favorites()).take(60)) {
        add(StatsService.cleanArtist(s.artist));
      }
    } catch (_) {}
    return out;
  }

  /// Nombres demasiado genéricos para cruzarlos con un cartel.
  static const Set<String> _generic = {
    'rock', 'love', 'metal', 'punk', 'live', 'band', 'banda', 'grupo',
    'various artists', 'varios artistas', 'música', 'musica', 'tributo',
  };

  /// La banda de [c] (o del cartel del festival) que es tuya, si hay.
  /// Los tributos («Tributo a…», «Tribute») no cuentan como la banda real.
  static String? matchBand(Concert c, List<String> bands) {
    final full = fold(c.band);
    if (RegExp(r'\btribut').hasMatch(full)) return null;
    final t = ' $full ';
    for (final b in bands) {
      final k = fold(b);
      if (k.length < 4 && !RegExp(r'\d').hasMatch(k)) continue;
      if (_generic.contains(k)) continue;
      if (t.contains(' $k ')) return b;
    }
    return null;
  }

  /// Conciertos próximos de tus bandas, ordenados por fecha.
  Future<List<(Concert, String)>> matches() async {
    final bs = await bands();
    final now = DateTime.now();
    final out = <(Concert, String)>[];
    for (final c in ConcertService.instance.state.value.items) {
      if (c.date != null && c.date!.isBefore(DateTime(now.year, now.month, now.day))) {
        continue;
      }
      final b = matchBand(c, bs);
      if (b != null) out.add((c, b));
    }
    out.sort((a, b) {
      final da = a.$1.date, db = b.$1.date;
      if (da == null) return 1;
      if (db == null) return -1;
      return da.compareTo(db);
    });
    return out;
  }

  /// Avisa de los conciertos nuevos de tus bandas (una vez cada uno).
  Future<void> notifyNew() async {
    try {
      final l = await matches();
      if (l.isEmpty) return;
      final sp = await SharedPreferences.getInstance();
      final seen = Set<String>.of(
          (jsonDecode(sp.getString(_seenKey) ?? '[]') as List).map((e) => '$e'));
      var n = 0;
      for (final (c, b) in l) {
        final id = '${fold(c.band)}|${c.date?.toIso8601String() ?? c.when}|${fold(c.city)}';
        if (!seen.add(id)) continue;
        if (n++ >= 3) continue; // máximo 3 avisos de golpe
        final when = c.date == null
            ? c.when
            : '${c.date!.day} de ${_months[c.date!.month - 1]}';
        await AlarmService.instance.notify(
          7000 + id.hashCode.abs() % 1000,
          '$b toca en ${c.city.isEmpty ? 'Colombia' : c.city}',
          '${when.isEmpty ? 'Fecha por confirmar' : when}${c.venue.isEmpty ? '' : ' · ${c.venue}'}',
        );
      }
      await sp.setString(_seenKey, jsonEncode(seen.toList()));
    } catch (_) {}
  }

  static const List<String> _months = [
    'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio',
    'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
  ];

  /// Abre la app de calendario con el evento listo (ACTION_INSERT); si no
  /// hay app de calendario, abre Google Calendar en la web. False si falló.
  static Future<bool> addToCalendar(Concert c) async {
    final d = c.date;
    if (d == null) return false;
    try {
      await AndroidIntent(
        action: 'android.intent.action.INSERT',
        data: 'content://com.android.calendar/events',
        arguments: <String, dynamic>{
          'title': 'Concierto: ${c.band}',
          'eventLocation': [c.venue, c.city].where((e) => e.isNotEmpty).join(', '),
          'description': c.tickets.isNotEmpty ? 'Boletas: ${c.tickets}' : 'Desde RockPlay IA',
          'beginTime': DateTime(d.year, d.month, d.day).millisecondsSinceEpoch,
          'endTime': DateTime(d.year, d.month, d.day + 1).millisecondsSinceEpoch,
          'allDay': true,
        },
      ).launch();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Enlace para añadir el concierto a Google Calendar (abre la app).
  static Uri calendarUri(Concert c) {
    final d = c.date ?? DateTime.now();
    String ymd(DateTime x) =>
        '${x.year}${x.month.toString().padLeft(2, '0')}${x.day.toString().padLeft(2, '0')}';
    final end = d.add(const Duration(days: 1));
    return Uri.https('calendar.google.com', '/calendar/render', {
      'action': 'TEMPLATE',
      'text': 'Concierto: ${c.band}',
      'dates': '${ymd(d)}/${ymd(end)}',
      'location': [c.venue, c.city].where((e) => e.isNotEmpty).join(', '),
      'details': c.tickets.isNotEmpty ? 'Boletas: ${c.tickets}' : 'Desde RockPlay IA',
    });
  }
}
