import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'error_log.dart';
import 'l10n.dart';

/// Einstellungen, die nur für dieses Gerät gelten (nie abgeglichen):
/// Darstellung und Sprache. Liegen in `<Datenordner>/einstellungen.json`.
class DeviceSettings {
  DeviceSettings._(this._file, Map<String, dynamic> data) : _data = data {
    themeMode.value = _themeFrom(data['theme'] as String?);
    language.value = AppLanguage.fromCode(data['language'] as String?);
  }

  final File? _file;
  final Map<String, dynamic> _data;

  /// Hell, dunkel oder wie das System.
  final themeMode = ValueNotifier<ThemeMode>(ThemeMode.dark);

  /// Gewählte Sprache (null = wie das System).
  final language = ValueNotifier<AppLanguage?>(null);

  /// Sprache, die gerade gilt.
  AppLanguage get effectiveLanguage => language.value ?? AppLanguage.system;

  /// Einstellungen aus [dir] lesen. Fehlt die Datei oder ist sie kaputt,
  /// gelten die Grundwerte.
  static Future<DeviceSettings> load(String dir) async {
    final file = File(p.join(dir, 'einstellungen.json'));
    var data = <String, dynamic>{};
    try {
      if (await file.exists()) {
        final j = jsonDecode(await file.readAsString());
        if (j is Map<String, dynamic>) data = j;
      }
    } catch (e, s) {
      ErrorLog.record(e, s, where: 'Einstellungen lesen');
    }
    return DeviceSettings._(file, data);
  }

  /// Nur im Speicher (für Tests).
  factory DeviceSettings.memory() => DeviceSettings._(null, {});

  Future<void> setThemeMode(ThemeMode m) async {
    themeMode.value = m;
    _data['theme'] = m.name;
    await _save();
  }

  Future<void> setLanguage(AppLanguage? l) async {
    language.value = l;
    if (l == null) {
      _data.remove('language');
    } else {
      _data['language'] = l.name;
    }
    L10n.set(effectiveLanguage);
    await _save();
  }

  static ThemeMode _themeFrom(String? name) {
    for (final m in ThemeMode.values) {
      if (m.name == name) return m;
    }
    return ThemeMode.dark;
  }

  Future<void> _save() async {
    final f = _file;
    if (f == null) return;
    try {
      await f.parent.create(recursive: true);
      // Erst in eine Zwischendatei, dann umbenennen: So bleibt die alte Datei
      // heil, falls beim Schreiben etwas schiefgeht.
      final tmp = File('${f.path}.neu');
      await tmp.writeAsString(const JsonEncoder.withIndent('  ').convert(_data));
      await tmp.rename(f.path);
    } catch (e, s) {
      ErrorLog.record(e, s, where: 'Einstellungen speichern');
    }
  }
}

/// Macht die [DeviceSettings] überall in der App erreichbar.
class SettingsScope extends InheritedWidget {
  const SettingsScope({super.key, required this.settings, required super.child});
  final DeviceSettings settings;

  static DeviceSettings of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SettingsScope>()!.settings;

  @override
  bool updateShouldNotify(SettingsScope old) => old.settings != settings;
}
