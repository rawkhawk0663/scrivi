import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrivi/app/device_settings.dart';
import 'package:scrivi/app/l10n.dart';
import 'package:scrivi/app/updater.dart';
import 'package:scrivi/core/library/library_controller.dart';
import 'package:scrivi/core/library/thumbnails.dart';
import 'package:scrivi/main.dart';

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

  testWidgets('Scrivi startet mit der Bibliothek, Einstellungen erreichbar', (tester) async {
    L10n.language.value = AppLanguage.de;
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('scrivi_lib');
    addTearDown(() => dir.deleteSync(recursive: true));
    final library = LibraryController(dir.path);
    await tester.runAsync(library.init);
    await tester.pumpWidget(
      ScriviApp(settings: DeviceSettings.memory(), library: library, thumbnails: Thumbnails(library.metaDir)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Noch keine Stücke'), findsOneWidget);
    await tester.tap(find.text('Einstellungen'));
    await tester.pumpAndSettle();
    expect(find.text('Sprache · Language'), findsOneWidget);
    // Sprache wechseln: alles auf Englisch.
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(find.text('Appearance'), findsOneWidget);
    L10n.language.value = AppLanguage.de;
  });
}
