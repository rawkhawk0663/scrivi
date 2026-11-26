import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app/device_settings.dart';
import 'app/error_log.dart';
import 'app/l10n.dart';
import 'app/theme.dart';
import 'app/touch_keyboard.dart';
import 'app/updater.dart';
import 'app/window_buttons.dart';
import 'core/library/library_controller.dart';
import 'core/library/thumbnails.dart';
import 'features/library/library_screen.dart';
import 'features/shell/home_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Scrivis eigener Datenordner (Einstellungen, Fehlerprotokoll, später die Bibliothek).
  final support = (await getApplicationSupportDirectory()).path;
  // Fehler in eine Datei schreiben (Einstellungen → Über Scrivi → Fehlerprotokoll).
  ErrorLog.install(support);
  _registerFontLicenses();
  // Windows: eigene Fensterknöpfe statt der Titelleiste, maximiert.
  await prepareWindow();
  // Windows: Bildschirmtastatur beim Antippen von Textfeldern (Tablet-Modus).
  TouchKeyboard.install();
  final settings = await DeviceSettings.load(support);
  L10n.language.value = settings.effectiveLanguage;
  // Die Bibliothek mit den Stücken (wird im Hintergrund eingelesen).
  final library = LibraryController(p.join(support, 'Bibliothek'));
  library.init();
  // Nach einem Update: alte, beiseitegeschobene Programmdateien wegräumen.
  Future<void>.delayed(const Duration(seconds: 5), Updater.cleanUp);
  runApp(ScriviApp(settings: settings, library: library, thumbnails: Thumbnails(library.metaDir)));
}

class ScriviApp extends StatelessWidget {
  const ScriviApp({super.key, required this.settings, required this.library, required this.thumbnails});
  final DeviceSettings settings;
  final LibraryController library;
  final Thumbnails thumbnails;

  @override
  Widget build(BuildContext context) {
    return SettingsScope(
      settings: settings,
      child: LibraryScope(
        library: library,
        thumbnails: thumbnails,
        child: ListenableBuilder(
          listenable: Listenable.merge([settings.themeMode, L10n.language]),
          builder: (context, home) => MaterialApp(
            title: 'Scrivi',
            debugShowCheckedModeBanner: false,
            theme: buildScriviTheme(Brightness.light),
            darkTheme: buildScriviTheme(Brightness.dark),
            themeMode: settings.themeMode.value,
            // Eingebaute Texte (Kopieren/Einfügen, Lizenzen …) in der Sprache der App,
            // Deutsch in Schweizer Schreibweise.
            locale: L10n.language.value.locale,
            supportedLocales: const [Locale('de', 'CH'), Locale('de'), Locale('en')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            builder: (context, child) => WindowButtonsOverlay(child: child ?? const SizedBox.shrink()),
            home: home,
          ),
          child: const HomeShell(),
        ),
      ),
    );
  }
}

/// Lizenzen der Schriften, die Scrivi mitbringt (Über Scrivi → Lizenzen).
void _registerFontLicenses() {
  const fonts = {'Bravura': 'OFL-Bravura.txt', 'IBM Plex Sans': 'OFL-IBMPlexSans.txt', 'Sora': 'OFL-Sora.txt'};
  LicenseRegistry.addLicense(() async* {
    for (final e in fonts.entries) {
      try {
        yield LicenseEntryWithLineBreaks([e.key], await rootBundle.loadString('assets/fonts/${e.value}'));
      } catch (_) {}
    }
  });
}
