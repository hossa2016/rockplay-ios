import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'music_mode.dart';

/// Qué suena en una alarma.
enum AlarmSource { mix, radio, list, song }

/// Una alarma del despertador.
class Alarm {
  final int id; // 1..99
  int hour; // 0..23
  int minute;
  Set<int> days; // 1 = lunes … 7 = domingo; vacío = una sola vez
  bool enabled;
  AlarmSource source;
  /// Datos de lo que suena: emisora (json), id de lista ('fav' = favoritas)
  /// o canción (json). Vacío para Tu mix.
  String payload;
  /// Nombre a mostrar de lo que suena (ej. «Radioacktiva»).
  String sourceLabel;
  bool ramp;
  bool backup;
  /// Volumen del celular mientras suena (0.3–1.0). Se restaura al apagar.
  double volume;
  /// MP3 propio como respaldo (copiado dentro de la app). Vacío = riff.
  String backupPath;
  String backupLabel;

  Alarm({
    required this.id,
    this.hour = 6,
    this.minute = 30,
    Set<int>? days,
    this.enabled = true,
    this.source = AlarmSource.mix,
    this.payload = '',
    this.sourceLabel = 'Tu mix',
    this.ramp = true,
    this.backup = true,
    this.volume = 1.0,
    this.backupPath = '',
    this.backupLabel = '',
  }) : days = days ?? {1, 2, 3, 4, 5};

  Map<String, dynamic> toJson() => {
        'id': id,
        'h': hour,
        'm': minute,
        'd': days.toList()..sort(),
        'on': enabled,
        'src': source.name,
        'p': payload,
        'sl': sourceLabel,
        'r': ramp,
        'b': backup,
        'v': volume,
        'bp': backupPath,
        'bl': backupLabel,
      };

  factory Alarm.fromJson(Map<String, dynamic> j) => Alarm(
        id: (j['id'] as num?)?.toInt() ?? 1,
        hour: (j['h'] as num?)?.toInt() ?? 6,
        minute: (j['m'] as num?)?.toInt() ?? 30,
        days: {
          for (final d in (j['d'] as List?) ?? const []) (d as num).toInt()
        },
        enabled: j['on'] != false,
        source: AlarmSource.values.firstWhere((s) => s.name == j['src'],
            orElse: () => AlarmSource.mix),
        payload: (j['p'] as String?) ?? '',
        sourceLabel: (j['sl'] as String?) ?? 'Tu mix',
        ramp: j['r'] != false,
        backup: j['b'] != false,
        volume: ((j['v'] as num?)?.toDouble() ?? 1.0).clamp(0.3, 1.0),
        backupPath: (j['bp'] as String?) ?? '',
        backupLabel: (j['bl'] as String?) ?? '',
      );

  Alarm copy() => Alarm.fromJson(toJson());

  static const _dayShort = ['', 'Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];

  String get daysLabel {
    if (days.isEmpty) return 'Una vez';
    if (days.length == 7) return 'Todos los días';
    final s = days.toList()..sort();
    if (s.length == 5 && s.first == 1 && s.last == 5) return 'Lun a vie';
    if (s.length == 2 && s.contains(6) && s.contains(7)) return 'Sáb y dom';
    return s.map((d) => _dayShort[d]).join(', ');
  }

  /// Hora en formato 12 h: «6:30» y «a. m.».
  String get time12 {
    final h = hour % 12 == 0 ? 12 : hour % 12;
    return '$h:${minute.toString().padLeft(2, '0')}';
  }

  String get ampm => hour < 12 ? 'a. m.' : 'p. m.';

  /// Próxima vez que debe sonar, desde [from].
  DateTime nextFire([DateTime? from]) {
    final now = from ?? DateTime.now();
    var c = DateTime(now.year, now.month, now.day, hour, minute);
    for (var i = 0; i < 8; i++) {
      if (c.isAfter(now) && (days.isEmpty || days.contains(c.weekday))) {
        return c;
      }
      c = DateTime(c.year, c.month, c.day + 1, hour, minute);
    }
    return c;
  }
}

/// Despertador: guarda las alarmas y las programa con alarmas exactas de
/// Android. Cada alarma usa dos avisos:
///  - el principal (silencioso, pantalla completa) que abre la app y pone
///    la música;
///  - el de respaldo, 15 s después, con el riff guardado en el celular y
///    repitiéndose, por si la app no abrió o no hay internet. La app lo
///    cancela apenas suena la música.
class AlarmService {
  AlarmService._();
  static final AlarmService instance = AlarmService._();

  static const String _key = 'alarms_v1';
  static const Duration backupDelay = Duration(seconds: 15);
  static const Duration snoozeTime = Duration(minutes: 10);

  final FlutterLocalNotificationsPlugin _n = FlutterLocalNotificationsPlugin();
  final ValueNotifier<int> revision = ValueNotifier<int>(0);
  /// La app pide abrir la pantalla de alarma (el id de la alarma).
  final ValueNotifier<int?> ringRequest = ValueNotifier<int?>(null);

  List<Alarm>? _cache;
  bool _ready = false;
  int? _ringing;

  int? get ringingId => _ringing;

  static int _mainId(int a) => a * 10 + 1;
  static int _backupId(int a) => a * 10 + 2;

  /// Aviso simple (Radar de conciertos, novedades). Abre la app al tocarlo.
  Future<void> notify(int id, String title, String body) async {
    await init();
    try {
      await _n.show(
        id,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'rp_info',
            'Avisos de tus artistas',
            channelDescription: 'Conciertos y lanzamientos de lo que escuchas',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
        ),
      );
    } catch (_) {}
  }

  Future<void> init() async {
    if (_ready) return;
    _ready = true;
    try {
      tz_data.initializeTimeZones();
    } catch (_) {}
    try {
      await _n.initialize(
        const InitializationSettings(
            android: AndroidInitializationSettings('@mipmap/ic_launcher'),
            iOS: DarwinInitializationSettings(
                requestAlertPermission: false,
                requestBadgePermission: false,
                requestSoundPermission: false)),
        onDidReceiveNotificationResponse: (r) => _onTap(r.payload),
      );
      final launch = await _n.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        _onTap(launch?.notificationResponse?.payload);
      }
    } catch (_) {}
  }

  void _onTap(String? payload) {
    final id = int.tryParse(payload ?? '');
    if (id != null) ringRequest.value = id;
  }

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _n.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  /// Pide los permisos que necesita el despertador (una sola vez).
  Future<void> requestPermissions() async {
    final a = _android;
    if (a == null) return;
    try {
      await a.requestNotificationsPermission();
    } catch (_) {}
    try {
      await a.requestExactAlarmsPermission();
    } catch (_) {}
    try {
      await a.requestFullScreenIntentPermission();
    } catch (_) {}
  }

  Future<List<Alarm>> all() async {
    if (_cache != null) return List<Alarm>.of(_cache!);
    final out = <Alarm>[];
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key);
      if (raw != null) {
        for (final e in jsonDecode(raw) as List) {
          if (e is Map<String, dynamic>) out.add(Alarm.fromJson(e));
        }
      }
    } catch (_) {}
    out.sort((a, b) =>
        (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute));
    _cache = out;
    return List<Alarm>.of(out);
  }

  Future<Alarm?> byId(int id) async {
    for (final a in await all()) {
      if (a.id == id) return a;
    }
    return null;
  }

  Future<void> _persist() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
          _key, jsonEncode([for (final a in _cache!) a.toJson()]));
    } catch (_) {}
    revision.value++;
  }

  Future<int> newId() async {
    final used = {for (final a in await all()) a.id};
    for (var i = 1; i < 100; i++) {
      if (!used.contains(i)) return i;
    }
    return 99;
  }

  Future<void> save(Alarm a) async {
    await all();
    _cache!.removeWhere((x) => x.id == a.id);
    _cache!.add(a);
    _cache!.sort((x, y) =>
        (x.hour * 60 + x.minute).compareTo(y.hour * 60 + y.minute));
    await _persist();
    await schedule(a);
  }

  Future<void> delete(int id) async {
    await all();
    _cache!.removeWhere((x) => x.id == id);
    await _persist();
    await _cancel(id);
  }

  Future<void> setEnabled(int id, bool on) async {
    final a = await byId(id);
    if (a == null) return;
    a.enabled = on;
    await save(a);
  }

  Future<void> _cancel(int id) async {
    try {
      await _n.cancel(_mainId(id));
      await _n.cancel(_backupId(id));
    } catch (_) {}
  }

  /// Programa la próxima vez de todas las alarmas (al abrir la app).
  /// Cancela todo lo programado (antes de restaurar una copia; al abrir
  /// de nuevo, [scheduleAll] programa las alarmas restauradas).
  Future<void> cancelAllScheduled() async {
    await init();
    try {
      await _n.cancelAll();
    } catch (_) {}
  }

  Future<void> scheduleAll() async {
    for (final a in await all()) {
      if (_ringing == a.id) continue;
      await schedule(a);
    }
  }

  Future<void> schedule(Alarm a, {DateTime? at}) async {
    await _cancel(a.id);
    if (!a.enabled && at == null) return;
    final when = at ?? a.nextFire();
    await _scheduleAt(a, when);
  }

  Future<void> _scheduleAt(Alarm a, DateTime when) async {
    final main = tz.TZDateTime.from(when, tz.UTC);
    final back = tz.TZDateTime.from(when.add(backupDelay), tz.UTC);
    final title = 'Despertador · ${a.time12} ${a.ampm}';
    try {
      await _n.zonedSchedule(
        _mainId(a.id),
        title,
        'Suena ${a.sourceLabel}. Toca para abrir.',
        main,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'rp_alarm',
            'Despertador',
            channelDescription: 'Abre la app a la hora de la alarma',
            importance: Importance.max,
            priority: Priority.max,
            category: AndroidNotificationCategory.alarm,
            fullScreenIntent: true,
            playSound: false,
            enableVibration: true,
            visibility: NotificationVisibility.public,
            autoCancel: false,
            ongoing: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.alarmClock,
        payload: '${a.id}',
      );
      if (a.backup) {
        await _n.zonedSchedule(
          _backupId(a.id),
          title,
          'Toca para apagar la alarma',
          back,
          NotificationDetails(
            // El sonido de un canal no cambia una vez creado: cada tono
            // tiene su propio canal.
            android: AndroidNotificationDetails(
              MusicModeService.general ? 'rp_alarm_backup_soft' : 'rp_alarm_backup',
              MusicModeService.general
                  ? 'Despertador (respaldo suave)'
                  : 'Despertador (respaldo)',
              channelDescription: MusicModeService.general
                  ? 'Tono suave guardado en el celular si la música no arranca'
                  : 'Riff guardado en el celular si la música no arranca',
              importance: Importance.max,
              priority: Priority.max,
              category: AndroidNotificationCategory.alarm,
              fullScreenIntent: true,
              playSound: true,
              sound: RawResourceAndroidNotificationSound(
                  MusicModeService.general ? 'soft_chime' : 'rock_riff'),
              audioAttributesUsage: AudioAttributesUsage.alarm,
              enableVibration: true,
              visibility: NotificationVisibility.public,
              autoCancel: false,
              ongoing: true,
              // FLAG_INSISTENT: repite el sonido hasta que lo atiendas.
              additionalFlags: Int32List.fromList(<int>[4]),
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.alarmClock,
          payload: '${a.id}',
        );
      }
    } catch (e) {
      debugPrint('Despertador: no se pudo programar: $e');
    }
  }

  /// ¿Hay una alarma sonando ahora (su aviso está visible)? Devuelve su id.
  Future<int?> dueAlarm() async {
    final req = ringRequest.value;
    if (req != null) {
      ringRequest.value = null;
      return req;
    }
    try {
      final active = await _android?.getActiveNotifications() ?? const [];
      for (final n in active) {
        final id = n.id ?? 0;
        if (id % 10 == 1 || id % 10 == 2) return id ~/ 10;
      }
    } catch (_) {}
    return null;
  }

  /// La pantalla de alarma se abrió: quita el aviso principal; el de
  /// respaldo sigue hasta que suene la música.
  Future<void> startRinging(int id) async {
    _ringing = id;
    try {
      await _n.cancel(_mainId(id));
    } catch (_) {}
  }

  /// Ya suena la música (o el respaldo dentro de la app): fuera el riff.
  Future<void> musicStarted(int id) async {
    try {
      await _n.cancel(_backupId(id));
    } catch (_) {}
  }

  Future<void> snooze(int id) async {
    _ringing = null;
    final a = await byId(id);
    if (a == null) return;
    await _cancel(id);
    await _scheduleAt(a, DateTime.now().add(snoozeTime));
  }

  Future<void> dismiss(int id) async {
    _ringing = null;
    final a = await byId(id);
    if (a == null) return;
    await _cancel(id);
    if (a.days.isEmpty) {
      // Una sola vez: queda apagada.
      a.enabled = false;
      await save(a);
    } else {
      await schedule(a, at: a.nextFire(DateTime.now().add(const Duration(minutes: 1))));
    }
  }
}
