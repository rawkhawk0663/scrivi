import 'package:flutter/services.dart';
import 'package:scrivi_core/scrivi_core.dart' as core;

import 'error_log.dart';

/// Die mitgelieferte Klangsammlung (`assets/sounds/scrivi.sf2`): aufgenommene
/// Gitarren und Bässe (FreePats) und alle übrigen Instrumente samt
/// Schlagzeug (FluidR3). Wird beim ersten Abspielen geladen und gemerkt.
/// Fehlt sie, klingt Scrivi wie bisher mit gerechneten Tönen.
class Sounds {
  Sounds._();

  static const asset = 'assets/sounds/scrivi.sf2';

  static Future<Uint8List?>? _bytes;
  static core.SoundFont? _font;

  /// Die ganze Datei (zum Weitergeben an das Rechnen im Hintergrund).
  static Future<Uint8List?> bytes() => _bytes ??= _load();

  /// Gelesen (für einzelne Töne beim Schreiben).
  static Future<core.SoundFont?> font() async {
    if (_font != null) return _font;
    final b = await bytes();
    if (b == null) return null;
    try {
      return _font = core.SoundFont.parse(b);
    } catch (e, st) {
      ErrorLog.record(e, st, where: 'Klangsammlung lesen');
      return null;
    }
  }

  static Future<Uint8List?> _load() async {
    try {
      final d = await rootBundle.load(asset);
      return d.buffer.asUint8List(d.offsetInBytes, d.lengthInBytes);
    } catch (e, st) {
      ErrorLog.record(e, st, where: 'Klangsammlung laden');
      return null;
    }
  }
}
