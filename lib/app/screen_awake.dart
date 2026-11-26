import 'dart:io';

import 'package:flutter/services.dart';

/// Bildschirm wach halten (beim Abspielen). Unter Windows über den eigenen
/// Kanal `scrivi/screen`; auf anderen Geräten geschieht nichts.
class ScreenAwake {
  ScreenAwake._();

  static const _channel = MethodChannel('scrivi/screen');

  static Future<void> set(bool on) async {
    if (!Platform.isWindows) return;
    try {
      await _channel.invokeMethod<bool>('keepAwake', on);
    } catch (_) {}
  }
}
