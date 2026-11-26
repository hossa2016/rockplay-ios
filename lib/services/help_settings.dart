import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ayudas de la app: guía de bienvenida, explicaciones en Ajustes y consejos.
class HelpSettings {
  static final ValueNotifier<bool> showTips = ValueNotifier<bool>(true);
  static const List<String> tipIds = ['asistente', 'buscar'];

  static Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      showTips.value = p.getBool('help_tips') ?? true;
    } catch (_) {}
  }

  static Future<void> setShowTips(bool v) async {
    showTips.value = v;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool('help_tips', v);
    } catch (_) {}
  }

  static Future<bool> onboardingSeen() async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getBool('help_onboarding') ?? false;
    } catch (_) {
      return true;
    }
  }

  static Future<void> markOnboarding(bool seen) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool('help_onboarding', seen);
    } catch (_) {}
  }

  static Future<bool> tipSeen(String id) async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getBool('help_tip_$id') ?? false;
    } catch (_) {
      return true;
    }
  }

  static Future<void> markTip(String id, bool seen) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool('help_tip_$id', seen);
    } catch (_) {}
  }

  /// Vuelve a mostrar los consejos de cada pantalla.
  static Future<void> resetTips() async {
    for (final id in tipIds) {
      await markTip(id, false);
    }
  }
}
