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
    scoreView.value = ScoreView.fromName(data['ansicht'] as String?);
    showTools.value = data['werkzeuge'] as bool? ?? true;
    showFretboard.value = data['griffbrett'] as bool? ?? true;
    showTracks.value = data['spuren'] as bool? ?? true;
    showInspector.value = data['eigenschaften'] as bool? ?? true;
    final th = data['spurenhoehe'];
    tracksHeight.value = th is num ? th.toDouble() : null;
    endless.value = data['endlos'] as bool? ?? false;
    fullScore.value = data['partitur'] as bool? ?? false;
    cursorStrip.value = data['cursorleiste'] as bool? ?? true;
    transposed.value = data['transponiert'] as bool? ?? false;
    final groups = data['werkzeuggruppen'];
    if (groups is List) openToolGroups.value = {for (final g in groups) '$g'};
    // Neue Gruppe „Schnell“ einmal aufklappen, auch wenn schon Gruppen gemerkt sind
    if (data['schnell_gezeigt'] != true) openToolGroups.value = {...openToolGroups.value, 'quick'};
    // Neue Gruppe „Vorzeichen“ ebenso einmal aufklappen
    if (data['vorzeichen_gezeigt'] != true) openToolGroups.value = {...openToolGroups.value, 'accidental'};
    if (data['fingersatz_gezeigt'] != true) openToolGroups.value = {...openToolGroups.value, 'finger'};
  }

  final File? _file;
  final Map<String, dynamic> _data;

  /// Hell, dunkel oder wie das System.
  final themeMode = ValueNotifier<ThemeMode>(ThemeMode.dark);

  /// Gewählte Sprache (null = wie das System).
  final language = ValueNotifier<AppLanguage?>(null);

  /// Ansicht der Noten bei Saiteninstrumenten.
  final scoreView = ValueNotifier<ScoreView>(ScoreView.both);

  /// Werkzeugspalte links und Griffbrett unten eingeblendet.
  final showTools = ValueNotifier<bool>(true);
  final showFretboard = ValueNotifier<bool>(true);

  /// Spur-Bahnen unten und Eigenschaften rechts eingeblendet.
  final showTracks = ValueNotifier<bool>(true);
  final showInspector = ValueNotifier<bool>(true);

  /// Noten als eine lange Zeile statt als Seiten.
  final endless = ValueNotifier<bool>(false);

  Future<void> setShowTracks(bool v) => _set(showTracks, 'spuren', v);
  Future<void> setShowInspector(bool v) => _set(showInspector, 'eigenschaften', v);

  /// Höhe des Spurenbereichs unten (null = so hoch wie nötig, höchstens ein paar Spuren).
  final tracksHeight = ValueNotifier<double?>(null);
  Future<void> setTracksHeight(double v) async {
    tracksHeight.value = v;
    _data['spurenhoehe'] = v.roundToDouble();
    await _save();
  }

  Future<void> setEndless(bool v) => _set(endless, 'endlos', v);

  /// Alle Spuren untereinander als Partitur (statt nur die gewählte Spur).
  final fullScore = ValueNotifier<bool>(false);
  Future<void> setFullScore(bool v) => _set(fullScore, 'partitur', v);

  /// Leiste mit Werkzeugen unter der Zeile, in der man schreibt.
  final cursorStrip = ValueNotifier<bool>(true);
  Future<void> setCursorStrip(bool v) => _set(cursorStrip, 'cursorleiste', v);

  /// Transponierende Instrumente so zeigen, wie die Musiker lesen (statt klingend).
  final transposed = ValueNotifier<bool>(false);
  Future<void> setTransposed(bool v) => _set(transposed, 'transponiert', v);

  Future<void> _set(ValueNotifier<bool> n, String key, bool v) async {
    n.value = v;
    _data[key] = v;
    await _save();
  }

  /// Offene Gruppen der Werkzeugspalte (Namen wie im Code, nie übersetzen).
  final openToolGroups = ValueNotifier<Set<String>>({'duration', 'accidental', 'guitar', 'finger', 'quick'});

  Future<void> setShowTools(bool v) async {
    showTools.value = v;
    _data['werkzeuge'] = v;
    await _save();
  }

  Future<void> setShowFretboard(bool v) async {
    showFretboard.value = v;
    _data['griffbrett'] = v;
    await _save();
  }

  Future<void> setOpenToolGroups(Set<String> v) async {
    openToolGroups.value = v;
    _data['werkzeuggruppen'] = v.toList()..sort();
    _data['schnell_gezeigt'] = true;
    _data['vorzeichen_gezeigt'] = true;
    _data['fingersatz_gezeigt'] = true;
    await _save();
  }

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

  Future<void> setScoreView(ScoreView v) async {
    scoreView.value = v;
    _data['ansicht'] = v.name;
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

/// Was bei Saiteninstrumenten zu sehen ist.
enum ScoreView {
  /// Noten und Tabulatur
  both,

  /// Nur Noten
  notation,

  /// Nur Tabulatur, mit Rhythmus darunter
  tab;

  static ScoreView fromName(String? name) {
    for (final v in values) {
      if (v.name == name) return v;
    }
    return both;
  }
}
