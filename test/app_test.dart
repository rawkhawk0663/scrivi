import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrivi/app/device_settings.dart';
import 'package:scrivi/app/l10n.dart';
import 'package:scrivi/app/updater.dart';
import 'package:scrivi/core/files/recent_files.dart';
import 'package:scrivi/core/files/score_files.dart';
import 'package:scrivi/main.dart';
import 'package:scrivi_core/scrivi_core.dart' as core;

void main() {
  group('Versionen vergleichen', () {
    test('liest alle drei Teile', () {
      expect(Updater.partsOf('v0.1.42'), (0, 1, 42));
      expect(Updater.partsOf('Testversion'), isNull);
    });

    test('neuer ist neuer, auch über den vorderen Teil hinweg', () {
      expect(Updater.newerThan('v0.2.0', 'v0.1.99'), isTrue);
      expect(Updater.newerThan('v0.1.5', 'v0.1.5'), isFalse);
      expect(Updater.newerThan('v0.1.4', 'v0.1.5'), isFalse);
      // Eine Testversion gilt als ganz alt.
      expect(Updater.newerThan('v0.0.1', 'Testversion'), isTrue);
    });
  });

  group('Geräte-Einstellungen', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('scrivi_test'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('werden gespeichert und wieder gelesen', () async {
      final a = await DeviceSettings.load(dir.path);
      expect(a.themeMode.value, ThemeMode.dark);
      expect(a.language.value, isNull);
      await a.setThemeMode(ThemeMode.light);
      await a.setLanguage(AppLanguage.en);
      final b = await DeviceSettings.load(dir.path);
      expect(b.themeMode.value, ThemeMode.light);
      expect(b.language.value, AppLanguage.en);
      expect(b.effectiveLanguage, AppLanguage.en);
    });

    test('eine kaputte Datei ergibt die Grundwerte', () async {
      File('${dir.path}/einstellungen.json').writeAsStringSync('{kaputt');
      final s = await DeviceSettings.load(dir.path);
      expect(s.themeMode.value, ThemeMode.dark);
    });
  });

  group('Zuletzt geöffnet', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('scrivi_recent'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('übernimmt beim ersten Start die Stücke der alten Bibliothek', () async {
      final pieces = Directory('${dir.path}/Bibliothek/Stücke')..createSync(recursive: true);
      await ScoreFiles.writeScrivi('${pieces.path}/Alt.scrivi', core.ScoreEditor.newScore(title: 'Altes Lied'));
      final r = RecentFiles(dir.path);
      await r.init();
      expect(r.entries.map((e) => e.fileName), ['Alt.scrivi']);
      // Beim zweiten Start aus der eigenen Liste
      final again = RecentFiles(dir.path);
      await again.init();
      expect(again.entries, hasLength(1));
    });

    test('Entwurf anlegen, oben einreihen, beim Entfernen löschen', () async {
      final r = RecentFiles(dir.path);
      await r.init();
      final path = await r.newDraft(core.ScoreEditor.newScore(title: 'Neu'));
      expect(r.isDraft(path), isTrue);
      expect(File(path).existsSync(), isTrue);
      expect(r.entries.first.draft, isTrue);
      expect(r.entries.first.title, 'Neu');
      final other = '${dir.path}/Woanders/Lied.scrivi';
      await ScoreFiles.writeScrivi(other, core.ScoreEditor.newScore(title: 'Lied'));
      await r.touch(other, core.ScoreEditor.newScore(title: 'Lied'));
      expect(r.entries.first.path, other);
      await r.remove(path);
      expect(File(path).existsSync(), isFalse);
      expect(r.entries.map((e) => e.path), [other]);
    });
  });

  testWidgets('Scrivi startet mit der Startseite, Einstellungen erreichbar', (tester) async {
    L10n.language.value = AppLanguage.de;
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('scrivi_start');
    addTearDown(() => dir.deleteSync(recursive: true));
    final recent = RecentFiles(dir.path);
    await tester.runAsync(recent.init);
    await tester.pumpWidget(ScriviApp(settings: DeviceSettings.memory(), recent: recent));
    await tester.pumpAndSettle();
    expect(find.text('Neues Stück'), findsOneWidget);
    expect(find.text('Noch nichts geöffnet'), findsOneWidget);
    await tester.tap(find.byTooltip('Einstellungen'));
    await tester.pumpAndSettle();
    expect(find.text('Sprache · Language'), findsOneWidget);
    // Sprache wechseln: alles auf Englisch.
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(find.text('Appearance'), findsOneWidget);
    L10n.language.value = AppLanguage.de;
  });
}
