import 'package:flutter/services.dart';

// ignore: avoid_classes_with_only_static_members
class SoundService {
  static const platform = MethodChannel('com.randil.pos/sounds');

  static Future<void> playBeep() async {
    try {
      // Try platform-specific beep first
      await platform.invokeMethod('playBeep');
    } catch (e) {
      // Fallback: Use system sound
      try {
        await SystemSound.play(SystemSoundType.click);
      } catch (e) {
        // Silent fail - beep not available
      }
    }
  }

  static Future<void> playError() async {
    try {
      await platform.invokeMethod('playError');
    } catch (e) {
      await SystemSound.play(SystemSoundType.alert);
    }
  }

  static Future<void> playSuccess() async {
    try {
      await platform.invokeMethod('playSuccess');
    } catch (e) {
      // No fallback needed
    }
  }
}
