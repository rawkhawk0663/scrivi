# Scrivi – Hinweise für die Entwicklung

Scrivi ist ein Notenschreibprogramm für Noten, Tabulatur und Partituren. Hauptziel ist Windows (Surface Pro mit Stift), danach Android; macOS und iPadOS vielleicht später. Der Besitzer ist Berufsmusiker und Gitarrenlehrer und programmiert nicht selbst. Erkläre Änderungen deshalb in einfacher Sprache und ohne Fachjargon.

Scrivi gehört zur Familie von **Volti** (Noten lesen), **Suona** (Noten lernen) und **Conti** (Buchhaltung), alle im selben GitHub-Konto. Gestaltung, Grundsätze und viele Bausteine stammen von dort; bei Fragen zuerst nachsehen, wie es dort gelöst ist.

Der Plan mit allen Etappen steht in **`BAUPLAN.md`**. Nach jeder Etappe dort den Stand nachführen.

## Sprache
- Die Oberfläche gibt es auf **Deutsch** (Grundsprache, Schweizer Schreibweise: „ss“ statt „ß“) und **Englisch** (britische Schreibweise: colour, licence). Die Code-Kommentare sind auf Deutsch, Bezeichner im Code auf Englisch.
- **Jeder sichtbare Text** steht als `tr('Deutsch', 'English')` im Code (`lib/app/l10n.dart`). `tr` ist nicht `const`: kein `const` um Widgets mit `tr(...)`.
- Die Sprache wählt man unter Einstellungen → „Sprache · Language“ (absichtlich zweisprachig). Ohne Wahl wie das System.
- **Nie übersetzen:** Ordner- und Dateinamen auf der Festplatte, Schlüssel in JSON-Dateien, Inhalte von `fehler.log`/`update.log`.
- Die Beschreibung steht in `README.md` (Deutsch) und `README.en.md` (Englisch). Bei neuen Grundfunktionen dort nachtragen.
- **Keine Hinweise auf andere Programme** (Wunsch des Besitzers, wie in Volti): Kommentare im Code, Tests und diese Datei erklären nur, was Scrivi macht, nie „wie bei …“ oder „angelehnt an …“ ein anderes Notenprogramm. Dateiformate, die Scrivi tatsächlich liest oder schreibt (Guitar-Pro-Dateien, MusicXML, MIDI), und Dienste, mit denen es arbeitet (Dropbox), dürfen genannt werden. Die Schwester-Apps Volti, Suona und Conti dürfen genannt werden.

## Technik
- Flutter `3.47.9` (in `.github/workflows/build.yml` festgelegt), Material 3.
- **Lizenz: GPL-3.0.** Neue Pakete, Schriften und Klänge müssen dazu passen (MIT, BSD, Apache-2.0, LGPL, MPL-2.0, OFL: ja; ohne Lizenz oder „nur nicht-kommerziell“: nein). Schriften-Lizenzen in `_registerFontLicenses` (`main.dart`).
- Builds über GitHub Actions: Jeder Push auf `main` erzeugt ein Release mit `Scrivi-Setup.exe`, `Scrivi-Windows.zip` und `Scrivi-Android.apk`. Weitergabe zwischen den Schritten über den Cache, nicht über „Artifacts“. Android wird mit `SCRIVI_KEYSTORE`/`SCRIVI_KEYSTORE_PASSWORD` signiert (Geheimnisse im GitHub-Projekt; fehlen sie, Test-Schlüssel).
- Das Installationsprogramm (`windows/installer/scrivi.iss`) hat eine eigene `AppId`. Nie die von Volti oder Conti übernehmen, sonst überschreiben sich die Installationen.
- App-Symbol: `tool/make_icon.py` (Verlauf Pink → Violett; weisser Schwung – Federstrich und Bogen zugleich –, der einen schrägen Notenkopf umfängt. Vom Besitzer gewählt; abstrakt wie Volti, aber bewusst eine andere Gestalt).
- Windows-Teil (`windows/runner/flutter_window.cpp`): Stift-Verzögerungen abgeschaltet (`DisablePenDelays`), Bildschirmtastatur über den Kanal `scrivi/keyboard`, Bildschirm wach halten über `scrivi/screen` (Dart-Seite kommt mit dem Abspielen).

## Aufbau
```
packages/scrivi_core/   Herz von Scrivi, reines Dart ohne Flutter (eigene Tests: dart test)
  model/      Fraction (genaue Notenlängen), Pitch (mit Schreibweise), Score/MasterBar/Track/Bar/Voice/Beat/Note
  io/         GpReader: .gp (ZIP mit Content/score.gpif)
  layout/     Engraver (Notensatz → Seiten), shapes (Bögen, Balken, Gabeln)
  render/     Zeichenliste (DisplayItem), Glyphs (Bravura-Umrisse, erzeugt), SVG-Ausgabe
lib/
  app/        Theme (ScriviColors), l10n, Updater, Fehlerprotokoll, Fensterknöpfe,
              Bildschirmtastatur, Geräte-Einstellungen (einstellungen.json)
  core/library/  LibraryController (Bibliothek, Import, Papierkorb), Thumbnails (Vorschaubilder)
  features/
    shell/    Rahmen: Leiste links (breit) bzw. unten (schmal), ein Navigator pro Bereich
    library/  Bibliothek (Raster mit Vorschau, Suche, Import, Ziehen und Ablegen)
    score/    Notenansicht (Seiten, Zoom, Blättern, Spurwahl), score_painter (Zeichenliste → Bild)
    settings/ Einstellungen, Über Scrivi, Updates
  widgets/    gemeinsame Bausteine (ScriviMark, SectionCard, EmptyState …)
tool/         make_icon.py (Symbol), make_glyphs.py (Notenzeichen aus Bravura)
```

## Notensatz (packages/scrivi_core)
- **Masseinheit Linienabstand (sp)**, y nach unten, oberste Notenlinie einer Zeile bei y = 0. Seite A4 = 120 × 169,7 sp (1 sp = 1,75 mm).
- **Notenzeichen** kommen als Umrisse aus `glyphs.g.dart` (erzeugt mit `tool/make_glyphs.py` aus `assets/fonts/Bravura.otf`, `glyphnames.json` der SMuFL und `Bravura.json` aus dem Bravura-Paket; nicht von Hand ändern). Neue Zeichen: in die Liste `GLYPHS` eintragen und neu erzeugen. Masse und Ansatzpunkte (Hals am Notenkopf, Fähnchen) stammen aus den Metadaten.
- Der Notensatz liefert eine **Zeichenliste** (`PageDisplay` mit `GlyphItem`, `LineItem`, `RectItem`, `PathItem`, `TextItem`). Die App zeichnet sie (`PagePictures`), `pageToSvg` schreibt SVG. Texte misst ein `TextMeasurer` (App: echte Schriften, Tests: Schätzung).
- **Gitarre** wird eine Oktave höher geschrieben als sie klingt (`Track.transposeSemitones = 12`, Violinschlüssel mit kleiner 8). `Note.pitch` ist klingend, `Note.written` geschrieben (Schreibweise aus der Datei; fehlt sie, wird die klingende um Oktaven verschoben).
- **Zeilen:** Die Takte pro Zeile aus der Datei (`SystemsLayout`) werden übernommen, solange sie passen; sonst wird gefüllt. Jede Zeile im Blocksatz.
- **Tabulatur:** Saite 0 = tiefste. Schläge mit Rhythmus-Schrägstrichen zeigen in der Tab nichts. Gehaltene Noten nur am Zeilenanfang in Klammern.
- **Dynamik** erscheint nur bei Wechseln (die Dateien schreiben „mf“ an jeden Schlag).
- Vorschlagsnoten werden noch übersprungen (nehmen keine Zeit).

## Bibliothek
- `<ApplicationSupport>/Bibliothek/Stücke/` enthält Kopien der importierten Dateien (heute `.gp`), `Bibliothek/Papierkorb/` Gelöschtes, `Bibliothek/.scrivi/index.json` (Format `scrivi-library` v1: Titel, Interpret, Takte, Grösse, Änderungszeit pro Datei) und `.scrivi/vorschau/` (Vorschaubilder, Name mit Grösse und Änderungszeit).
- Import prüft jede Datei (im Hintergrund), erkennt Doppelte (gleicher Inhalt) und meldet ältere Formate als „kommt bald“.
- Das eigene Format `.scrivi` kommt mit dem Schreiben (Etappe 5).

## Grundsätze
1. **Kein Konto, keine Daten sammeln, keine Werbung, funktioniert ohne Internet.** Internet nur für Updates und (später) den eigenen Dropbox-Abgleich.
2. **Nie Daten verlieren:** Dateien erst in eine Zwischendatei schreiben, dann umbenennen. Alte Formate bleiben lesbar.
3. **Scrivi verwaltet seine Stücke selbst** in einer Bibliothek im Datenordner (Wunsch des Besitzers, wie Volti), dazu Import und Export einzelner Dateien.
4. **Gerätespezifisch** (nie abgeglichen): `<ApplicationSupport>/einstellungen.json` (Darstellung, Sprache), `fehler.log`, `update.log`.
5. **Bedienbar mit Stift, Finger, Maus und Tastatur.** Langes Drücken = Rechtsklick.
6. **Flüssig auf dem Surface:** messen statt raten; fertige Teile als Bild zwischenspeichern, keine Schatten und Durchsichtigkeit auf grossen Flächen (Erfahrung aus Volti).

## Testmaterial
- Die Guitar-Pro-Dateien des Besitzers sind **urheberrechtlich geschützte Lieder**. Sie dürfen **nie ins Projekt** (es ist öffentlich). Tests im Projekt nutzen nur selbst gebaute Beispiele; echte Dateien prüft man lokal ausserhalb des Projektordners.

## Prüfen
- `flutter analyze` und `flutter test` müssen sauber sein, ebenso im Kern: `cd packages/scrivi_core && dart analyze && dart test` (läuft auch im Bau auf GitHub).
- Notensatz schnell ansehen ohne App: echte Dateien lokal mit `GpReader` + `Engraver` + `pageToSvg` als SVG schreiben und im Browser (Playwright) als Bild aufnehmen. Diese Hilfsskripte gehören nicht ins Projekt.
- Anschauen ohne Surface: Linux-Build (`flutter build linux`, braucht `libgtk-3-dev`) unter Xvfb starten und mit `xdotool` bedienen, Bildschirmfoto mit `import -window root`.
