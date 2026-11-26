import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'theme/app_theme.dart';
import 'services/alarm_service.dart';
import 'services/data_saver.dart';
import 'services/block_service.dart';
import 'services/concert_service.dart';
import 'services/eq_service.dart';
import 'services/mode_cleanup.dart';
import 'services/music_mode.dart';
import 'services/playback_service.dart';
import 'widgets/playback_ui.dart';
import 'widgets/cover_art.dart';
import 'services/release_watch.dart';
import 'services/dj_voice.dart';
import 'services/lastfm_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Primero el modo de música: define colores, textos y géneros.
  await MusicModeService.load();
  unawaited(SongArtwork.warm());
  unawaited(Future<void>.delayed(const Duration(seconds: 20), ReleaseWatch.check));
  await ModeCleanup.run();
  unawaited(ModeCleanup.fixTitles());
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.surface,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  MusicModeService.mode.addListener(() {
    EqService.instance.syncMode();
    unawaited(AlarmService.instance.scheduleAll());
    ConcertService.instance.resetForMode();
      SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.surface,
      systemNavigationBarIconBrightness: Brightness.light,
    ));
  });
  try {
    await DataSaver.instance.load();
  } catch (_) {}
  try {
    await BlockService.instance.ensureLoaded();
  } catch (_) {}
  try {
    await PlaybackService.instance.init();
    PlaybackUi.instance.start();
    unawaited(DjVoice.instance.init());
    unawaited(LastFmService.instance.init());
    unawaited(EqService.instance.init());
  } catch (_) {
    // La interfaz debe abrir aunque el audio falle al iniciar.
  }
  try {
    await AlarmService.instance.init();
    unawaited(AlarmService.instance.scheduleAll());
    ConcertService.instance.resetForMode();
  } catch (_) {}
  runApp(const RockPlayApp());
}
