# Scrivi – Bauplan

Stand: 26. November 2026 · Name: **Scrivi** (ital. „schreib!“) · Etappen 0 bis 5 fertig

Scrivi ist ein Notenschreibprogramm für Noten, Tabulatur und Partituren. Es läuft mit Flutter
auf Windows und Android, später vielleicht auch auf macOS und iPadOS. Es gehört zur gleichen
Familie wie Volti (Noten lesen), Suona (Noten lernen) und Conti (Buchhaltung).

---

## 1. Was Scrivi können soll, und was nicht

### Ziel
Ein Programm, mit dem ein Berufsmusiker und Gitarrenlehrer im Alltag alles schreibt, was er
braucht:

- **Gitarre:** Noten und Tabulatur gekoppelt, Griffbilder, Rhythmus-Schreibweise (Slashes),
  Spieltechniken (Bending, Slide, Hammer-on, Pull-off, Vibrato, Flageolett, Palm Mute,
  Let ring, Tapping), beliebige Stimmungen und Kapo, 6-, 7- und 8-saitige Gitarre, Bass.
- **Leadsheets:** Melodie, Akkordsymbole, Liedtext, Formteile (Intro, Strophe, Refrain),
  Wiederholungen, Häuser, Segno und Coda.
- **Partituren:** mehrere Instrumente, Klammern, Stimmen-Auszüge, Transposition für
  transponierende Instrumente, Dynamik, Artikulation, Bögen, Liedtext.
- **Abspielen:** Klang für alle Instrumente, mitlaufende Markierung, Tempo, Schleife,
  Einzähler, Metronom, Lautstärke und Stumm/Solo pro Spur.
- **Unterrichtsmaterial:** Übungsblätter, Tonleitern und Griffbrett-Diagramme schnell erstellt.
- **Austausch:** vorhandene Dateien einlesen (MusicXML, Guitar-Pro-Dateien, MIDI), schöne PDFs
  ausgeben, direkt an Volti weitergeben.

### Ehrliche Grenzen
- **Notensatz auf Verlagsniveau für grosse Orchesterpartituren** ist eine Arbeit von
  Jahrzehnten. Scrivi soll für Band, Ensemble, Unterricht und Leadsheets sehr gut aussehen.
  Eine Sinfonie mit 30 Systemen wird lange Zeit Handarbeit brauchen.
- **Die bisherigen Dateien aus dem Partitur-Programm (`.sib`)** sind ein geschlossenes,
  nicht beschriebenes Format. Scrivi kann sie nicht direkt öffnen. Der Weg führt über
  **MusicXML**: Im alten Programm alle Stücke als MusicXML speichern (es gibt dort eine
  Stapel-Umwandlung für ganze Ordner), dann in Scrivi einlesen. Das machen wir einmal
  gemeinsam, bevor das Abo ausläuft.
- **Guitar-Pro-Dateien** (`.gp`, `.gpx`, `.gp5`, `.gp4`, `.gp3`) sind gut erforscht, das
  Einlesen ist machbar. Kleinigkeiten (besondere Effekte, Klangeinstellungen) gehen dabei
  eventuell verloren. Der Klang wird nicht derselbe sein.
- **Handschrift mit dem Stift erkennen** (Noten von Hand schreiben, Scrivi setzt sie) ist
  sehr schwierig. Das steht ganz am Schluss und nur als „vielleicht“.
- **iPad:** Ohne EU-Mitgliedschaft der Schweiz gibt es dort nur den App Store. Das braucht
  ein Apple-Entwicklerkonto (jährliche Gebühr) und die Prüfung durch Apple.

---

## 2. Grundsätze (wie bei Volti, Suona und Conti)

1. **Kein Konto, keine Daten sammeln, keine Werbung, funktioniert ohne Internet.**
   Internet nur für Updates und den eigenen Dropbox-Abgleich.
2. **Deutsch und Englisch**, jeder sichtbare Text als `tr('Deutsch', 'English')`,
   Schweizer Schreibweise („ss“), Englisch britisch.
3. **GPL-3.0**, alles öffentlich. Neue Pakete, Schriften und Klänge müssen zur GPL passen.
4. **Gleiche Gestaltung wie die Familie:** Material 3, Markenverlauf, hell und dunkel,
   Fenster ohne Titelleiste mit drei runden Knöpfen, Leiste links.
5. **Bedienbar mit Stift, Finger, Maus und Tastatur.** Hauptgerät ist das Surface mit Stift.
6. **Nie Daten verlieren:** automatisches Speichern, tägliche Sicherungen, Versionsverlauf
   pro Stück, Einspielen löscht nie etwas.
7. **Alte Dateien bleiben lesbar.** Jedes eigene Format hat eine Versionsnummer.
8. **Flüssig auf dem Surface:** Messen statt raten (Lehren aus Volti: fertige Teile als Bild
   zwischenspeichern, keine Schatten und Durchsichtigkeit beim Bearbeiten).
9. **Builds über GitHub Actions:** jeder Push auf `main` ergibt `Scrivi-Setup.exe`,
   `Scrivi-Windows.zip` und `Scrivi-Android.apk`, Updates in der App und über Obtainium.

---

## 3. Aufbau der Technik

Scrivi besteht aus zwei Teilen:

```
packages/scrivi_core/      Reines Dart, ohne Flutter (schnell testbar, auch für Volti/Suona nutzbar)
  model/                   Das Notenmodell (Stück, Instrumente, Takte, Noten …)
  edit/                    Bearbeitungsbefehle mit Rückgängig (jede Änderung ist ein Befehl)
  layout/                  Notensatz: rechnet aus dem Modell Seiten, Systeme und Zeichen-Positionen
  render/                  „Zeichenliste“ (Linien, Zeichen, Bögen) – unabhängig von Bildschirm oder PDF
  playback/                Aus dem Modell eine Abspiel-Liste (wann klingt welcher Ton wie lange)
  io/                      Einlesen und Ausgeben: scrivi, MusicXML, Guitar Pro, MIDI
  music/                   Tonhöhen, Intervalle, Tonarten, Akkordnamen, Stimmungen

lib/                       Die Flutter-App
  app/                     Theme, l10n, Updater, Fehlerprotokoll, Fensterknöpfe (wie in der Familie)
  core/                    Bibliothek, Sync, Sicherungen, Einstellungen, Klang-Technik
  features/
    library/               Bibliothek mit Ordnern, Suche, Vorschaubildern
    editor/                Notenansicht mit Eingabe, Paletten, Inspektor
    playback/              Mischpult, Transport, mitlaufende Markierung
    export/                PDF, Bilder, Audio, an Volti senden
    settings/
```

**Warum so getrennt?** Der Notensatz ist das Herz und der schwierigste Teil. Ohne Flutter lässt
er sich mit tausenden automatischen Tests prüfen, und Volti oder Suona können ihn später
mitbenutzen (z. B. Volti zeigt Scrivi-Stücke mit mitlaufender Markierung).

### Notenschrift
- **Bravura** (SMuFL, OFL), dieselbe Schrift wie in Volti und Suona. Später zusätzlich
  **Petaluma** (handschriftlicher Jazz-Look für Leadsheets) und **Leland**, alle OFL.
- Ein Werkzeug (`tool/make_glyphs.py`) holt die Umrisse der benötigten Zeichen aus der Schrift
  und legt sie als Vektordaten ab. So sehen Bildschirm und PDF garantiert gleich aus, und das
  PDF wird gestochen scharf.

### Darstellung
- Gezeichnet wird über `CustomPainter` aus der Zeichenliste. Jedes System wird als Bild
  zwischengespeichert; bei einer Änderung wird nur das betroffene System neu gesetzt.
- Ansichten: **Seitenansicht** (wie gedruckt) und **Endlos-Ansicht** (ein langes Band, gut
  zum Schreiben und auf dem Handy).

### Klang
- **Entscheid (27. November 2026):** Klänge fest mitliefern (funktioniert ohne Internet).
  Gitarren und Bass von FreePats (CC0 bzw. GPL mit Ausnahme), alle übrigen Instrumente und
  Schlagzeug aus FluidR3/MuseScore General (MIT). GeneralUser GS nicht (Herkunft der Klänge
  unsicher).
- **Stand (27. November 2026):** umgesetzt. Klangsammlung `assets/sounds/scrivi.sf2` (38 Klänge,
  etwa 65 MB) mit `tool/make_sounds.py`; Scrivi liest SF2 selbst und spielt die Samples mit
  Bendings, Slides, Vibrato, Palm Mute, Hüllkurven und Schleifen. Ohne die Datei klingen die
  gerechneten Töne wie bisher. Noch offen: Hall, Stereo, eigene SoundFonts laden.
- **Erste Stufe:** Das Stück wird im Hintergrund in eine Tonspur umgerechnet und mit
  `flutter_soloud` abgespielt (gleiches Prinzip wie das Metronom in Volti: dadurch genau im
  Takt). Gitarre zuerst mit der gezupften Saite aus Suona und Volti, die es schon gibt.
- **Zweite Stufe:** SoundFont-Klänge (SF2/SF3) für alle Instrumente. Welche Klangsammlung,
  entscheiden wir nach Lizenz und Grösse; grosse Sammlungen eventuell als Download nach der
  Installation.
- **Dritte Stufe:** Echtzeit-Klang für ein MIDI-Keyboard und beim Eingeben.

### Pakete (Vorschlag, alle GPL-tauglich)
`path_provider`, `archive`, `uuid`, `file_selector`, `share_plus`, `url_launcher`,
`window_manager` 0.5.x, `flutter_soloud`, `flutter_recorder`, `pdf`, `xml`, `desktop_drop`,
`flutter_localizations`. Wo möglich dieselben Versionen wie in Volti.

---

## 4. Das Notenmodell (Kurzfassung)

```
Stück (Titel, Untertitel, Komponist, Bearbeiter, Copyright, Tempo …)
 └─ Instrumente (Name, Kürzel, Klang, Transposition, Stimmung, Kapo)
     └─ Systeme pro Instrument (Noten, Tabulatur, Rhythmus, Schlagzeug)
 └─ Taktfolge (für alle Instrumente gleich: Taktart, Tonart, Wiederholungen, Häuser,
               Segno/Coda, Formteile, Tempo-Wechsel, Akkordsymbole)
     └─ pro Instrument und Takt: Stimmen (1–4)
         └─ Ereignisse: Akkord/Note oder Pause, Dauer, Punktierung, n-tolen, Vorschläge
             └─ Noten: Tonhöhe **mit Schreibweise** (Fis ≠ Ges), Saite und Bund,
                       Haltebogen, Techniken, Artikulation, Notenkopf
 └─ Spannen über mehrere Noten: Bögen, Crescendo, Oktavierung, Pedal, Triller, Let ring …
 └─ Liedtext (mehrere Strophen), Texte, Probenzeichen
 └─ Satz-Einstellungen (Seitenformat, Abstände, Schriftgrössen, Umbrüche von Hand)
```

- Jedes Element hat eine **ID** (UUID), damit Rückgängig, Abgleich und Verschieben sicher sind.
- Noten und Tabulatur sind **ein** Modell: Schreibt man in die Tabulatur, entsteht die Note,
  und umgekehrt. Scrivi wählt Saite und Bund selbst (bequemste Lage), man kann es ändern.
- **Klingende Tonhöhe** wird gespeichert, die Schreibweise für transponierende Instrumente
  und Gitarre (Violinschlüssel mit kleiner 8) wird beim Setzen berechnet, wie in Suona.

### Eigenes Dateiformat `.scrivi`
Eine ZIP-Datei mit `score.json` (Format `scrivi-score`, Version 1), Vorschaubild, optional
Bildern und Tonaufnahmen. Gut lesbar, gut zu sichern, versioniert.

---

## 5. Eingabe

- **Tastatur** (schnellste Art): Buchstaben für Tonnamen, Zahlen für Notenwerte, Pfeile
  für Oktave und Schritt, Kürzel für Pause, Punkt, Haltebogen, Vorzeichen. In der Tabulatur:
  Bundzahl tippen, Pfeil hoch/runter wechselt die Saite.
- **Stift/Maus:** Notenwert wählen, auf das Notensystem tippen (wie „Note setzen“ in Suona),
  Paletten mit Zeichen, Ziehen zum Verschieben.
- **Griffbrett** zum Antippen (aus Suona) und **Klaviatur** am unteren Rand.
- **Mikrofon:** Gitarre spielen, Scrivi erkennt den Ton (Tonerkennung aus Volti und Suona).
- **MIDI-Keyboard** (später).
- **Handschrift** (ganz später, vielleicht).
- **Werkzeuge bei der Note** (Wunsch des Besitzers): Die Werkzeuge (Notenwerte, Pause, Punkt,
  Vorzeichen, Techniken …) schweben als kleine Leiste immer bei der Note, an der man gerade
  arbeitet, statt weit weg am Bildschirmrand. Mit dem Stift muss man so kaum hin und her.

---

## 6. Zusammenspiel mit der Familie

| App | Verbindung |
|---|---|
| **Volti** | „An Volti senden“: PDF (und später das Scrivi-Stück selbst) landet in Voltis Bibliothek, mit Tempo und Taktart in den Infos. Später zeigt Volti Scrivi-Stücke direkt an, mit Klang und mitlaufender Markierung. Gemeinsame Bausteine: Metronom, Stimmgerät, Tonerkennung, Dropbox-Abgleich. |
| **Suona** | Scrivi als Werkzeug für Lehrpersonen: Lieder für die Akkord-Tour und Lehrpläne schreiben und an Suona geben. Gemeinsame Bausteine: Notensystem, Griffbrett, Notennamen (H/B), gezupfte Saite. |
| **Conti** | Keine inhaltliche Verbindung. Gemeinsam sind Gestaltung, Updater, Sicherungen und Dropbox-Abgleich. |

**Gemeinsamer Code:** Heute hat jede App ihre eigene Kopie von l10n, Theme, Updater,
Fensterknöpfen und Sync. Für Scrivi kopieren wir sie zuerst ebenfalls. Sobald es sich lohnt,
legen wir sie in ein gemeinsames Paket, das alle vier Apps benutzen.

---

## 7. Etappen

Grösse: S = eine bis zwei Sitzungen, M = einige Sitzungen, L = viele Sitzungen, XL = sehr viele.
Jede Etappe endet mit einem Release, das man ausprobieren kann.

| # | Etappe | Inhalt | Fertig, wenn … | Grösse |
|---|---|---|---|---|
| 0 | **Grundgerüst** ✅ | Flutter-Projekt, Theme, l10n, Fensterknöpfe, Updater, Fehlerprotokoll, Bau über GitHub Actions, README, CLAUDE.md, Lizenz | Scrivi startet auf Surface und Android und aktualisiert sich selbst | S |
| 1 | **Guitar-Pro-Dateien öffnen und zeigen** ✅ | Notenmodell; Einlesen von `.gp` (das Format der eigenen Dateien); Bibliothek mit Import und Vorschaubildern; Notensatz für ein Instrument: Schlüssel, Tonart, Taktart, Noten und Pausen, Punkte, Vorzeichen, Hälse, Balken, Haltebögen, Taktstriche, Wiederholungen, Häuser, Formteile, Akkordsymbole; Tabulatur darunter; Zeilen- und Seitenumbruch | die eigenen Stücke sehen in Scrivi sauber gesetzt aus | L |
| 2 | **Weitere Formate einlesen** ✅ | ältere Guitar-Pro-Dateien (`.gpx`, `.gp5/4/3`), MusicXML (für die Partitur-Dateien), MIDI | alle alten Dateien lassen sich öffnen | M–L |
| 3 | **Tabulatur vollständig** ✅ | alle Spieltechniken in Noten und Tab (Bending-Kurven, Vibrato, Flageolett, Tapping …), alle Stimmungen, Kapo, Rhythmus in der Tab, 7- und 8-saitige Gitarre, Bass | Gitarrenstücke mit allen Spieltechniken sehen vollständig aus | L |
| 4 | **Abspielen** ✅ | Abspiel-Liste, Gitarrenklang, Tempo, Schleife, Einzähler, Metronom, mitlaufende Markierung, Mischpult; danach SoundFont-Klänge | ein Stück klingt richtig, auch mit Wiederholungen, Bends und Slides | M–L |
| 5 | **Schreiben** ✅ | Cursor, Eingabe über Tastatur, Stift und Griffbrett, Auswahl, Kopieren, Rückgängig, Transponieren, Takte einfügen und löschen, Akkordsymbole, Liedtext, Titel | ein Leadsheet und eine Tab lassen sich vollständig in Scrivi schreiben | L |
| 6 | **Ausgeben** | PDF, PNG/SVG, MusicXML, MIDI, Tonspur (WAV), „An Volti senden“, Drucken | ein PDF ist bereit für Schüler und Band | M |
| 7 | **Partitur** | Mehrere Instrumente, Klammern, Stimmen-Auszüge, Transposition, mehrere Stimmen pro System, Dynamik, Bögen, n-tolen, Vorschläge, Schlagzeug | ein Band-Arrangement mit Auszügen ist druckreif | XL |
| 8 | **Feinschliff Notensatz** | Kollisionen vermeiden, Abstände von Hand, Stilvorlagen, Schriften (Petaluma), Umbrüche, Kopf- und Fusszeilen | Ergebnis braucht kaum Handarbeit | L |
| 9 | **Extras** | Dropbox-Abgleich, Mikrofon-Eingabe, MIDI-Keyboard, Übungsblatt-Generator, Lieder an Suona, macOS, iPadOS | nach Wunsch | je M |

**Warum Einlesen so früh?** Die eigenen Guitar-Pro-Dateien sind das beste
Testmaterial. So sehen wir sofort an echten Stücken, wo der Notensatz noch hinkt, und Scrivi
ist schon zum Lesen und Abspielen nützlich, bevor man darin schreiben kann.

**Realistisch:** Nach den Etappen 0 bis 6 ersetzt Scrivi das Gitarren-Programm im Alltag
(Tabs, Leadsheets, Abspielen, PDF). Das Partitur-Programm ersetzt es nach Etappe 7 und 8
für Band und Ensemble. Für grosse Orchesterpartituren bleibt es lange schwächer.

---

## 8. Risiken und wie wir damit umgehen

| Risiko | Gegenmittel |
|---|---|
| Notensatz sieht „billig“ aus | Satzregeln aus der Fachliteratur (Elaine Gould, *Behind Bars*), Bild-Vergleichstests für jede Regel, eigene Stücke als Prüfstein |
| Langsam bei grossen Stücken | nur geänderte Systeme neu setzen, Systeme als Bild zwischenspeichern, früh auf dem Surface messen |
| Guitar-Pro-Dateien mit Eigenheiten | viele echte Dateien als Testsammlung, unbekannte Teile überspringen statt abbrechen, Hinweis was fehlte |
| Klang klingt künstlich | gute, lizenzfreie Klangsammlung wählen, Gitarre mit eigenen Effekten (Bend, Slide, Palm Mute) |
| PDF und Bildschirm unterschiedlich | beide zeichnen aus derselben Zeichenliste mit denselben Vektor-Umrissen |
| Projekt wird zu gross | jede Etappe ist einzeln nützlich; klare Reihenfolge, Wünsche kommen in eine Liste |

---

### Stand nach Etappe 1 (26. November 2026)

Fertig: Notenmodell und Notensatz als eigenes Paket (`packages/scrivi_core`), Einlesen von
`.gp`, Bibliothek mit Import (Dateien, Ordner, Ziehen), Vorschaubildern, Suche und Papierkorb,
Notenansicht mit Seiten, Zoom und Blättern, Spurwahl. Geprüft mit den vier Beispieldateien.

Bewusst noch offen (kommt später):
- Vorschlagsnoten (werden übersprungen, verschieben aber nichts) → Etappe 3
- Griffbilder über den Noten → Etappe 3
- Mehrere Stimmen pro System sind angelegt, aber noch kaum geprüft → Etappe 7
- Ausgabe als PDF/SVG: Die Zeichenliste kann schon SVG, in der App kommt es mit Etappe 6

### Stand nach Etappe 2 (26. November 2026)

Fertig: Guitar Pro 3, 4, 5 (Binärformat), Guitar Pro 6 (`.gpx`), MusicXML (`.musicxml`, `.xml`,
`.mxl`, auch die seltene „timewise“-Form) und MIDI. Geprüft mit 90 GP3/4/5-, 36 GPX- und 67
MusicXML-Testdateien aus dem offenen Notenprojekt alphaTab (nur lokal, nicht im Projekt) und
eigenen Tests für jedes Format. Die Bibliothek nimmt alle Formate an und behält die Endung.

Bewusst offen:
- **Sibelius-Dateien (`.sib`)** bleiben geschlossen: Weg über MusicXML (siehe oben).
- MIDI: Triolen werden noch nicht erkannt (auf Sechzehntel eingerastet), Schlagzeug ohne
  Schlagzeug-Notation.
- MusicXML: Klavier mit zwei Systemen erscheint als zwei Spuren; die gemeinsame Darstellung kommt
  mit der Partitur (Etappe 7).
- Bei Dateien ohne gespeicherte Tonhöhe (ältere Guitar-Pro-Formate) zählen Bundzahlen ab dem
  Kapodaster. Mit einer echten Datei mit Kapo prüfen.

### Stand nach Etappe 3 (26. November 2026)

Fertig: Vorschlagsnoten (klein, mit Querstrich und Bogen, auch in der Tab), Vibrato,
Flageolett, Tapping, Anschlag auf/ab, Tremolo-Picking, Fermaten. Griffbilder aller Akkorde oben auf
der ersten Seite: aus der Datei (`.gp`, `.gpx`, `.gp3/4/5`, mit Barré), sonst aus einer eingebauten
Sammlung für Normalstimmung (offene Griffe, Schrägstrich-Akkorde wie D/F♯, sonst Barré auf der
E- oder A-Saite). Saitennamen vor der Tab bei besonderen Stimmungen (deutsch mit H), „Capo n“.
Drei Ansichten: Noten + Tab, nur Noten, nur Tab mit Rhythmus darunter (Wahl wird gemerkt).
Geprüft mit allen Spuren aller 198 Testdateien in allen drei Ansichten und den vier eigenen Liedern.

Bewusst offen:
- Bending-Kurven mit mehreren Punkten (z. B. Bend–Release–Bend) erscheinen vereinfacht als ein
  Pfeil hinauf und einer hinunter → Feinschliff (Etappe 8).
- Tremolo-Picking ist nur mit selbst gebauten Beispielen geprüft.
- Mit Kapo zeigt Scrivi nur Griffbilder aus der Datei (ob die Akkordnamen dann klingend oder als
  Griff gemeint sind, ist von Datei zu Datei verschieden).
- Ganze Noten haben in der reinen Tab-Ansicht kein Zeichen darunter.

### Stand nach Etappe 4 (26. November 2026)

Fertig: Abspiel-Liste im Kern (`packages/scrivi_core/lib/src/playback`): Wiederholungen, Häuser,
D.C./D.S. (al Fine, al Coda), Tempowechsel, Haltebögen, Vorschläge, Anschlag, Tremolo, Fermaten.
Klangerzeugung ohne Klangdateien: schwingende Saite mit veränderlicher Tonhöhe (Bendings, Slides,
Vibrato), Palm Mute, gedämpfte Noten, Flageolett, Verzerrung; Bass, Klavier, Orgel, Streicher,
Bläser, Flöte, Flächen, Schlagzeug. Jede Spur wird im Hintergrund als Tonspur gerechnet (ein Lied:
etwa 2 Sekunden) und mit `flutter_soloud` als eigene Stimme gespielt, das Metronom ebenso.
In der App: Leiste unten (Abspielen, Anfang, Stelle, Tempo, Einzähler, Metronom, Schleife,
Mischpult), mitlaufende Markierung mit Mitblättern, Takt antippen zum Springen, Leertaste,
Bildschirm bleibt beim Abspielen wach (Windows). Dazu: Hochscrollen zoomt nicht mehr (eigene
Steuerung für Scrollen und Zoomen). Geprüft mit Tests (Reihenfolge, Zeiten, Tonhöhe auf wenige
Cent genau) und in der Linux-App mit einer virtuellen Soundkarte.

Bewusst offen:
- Klang ist gerechnet, nicht aufgenommen: gut zum Üben, aber kein Studio-Klang. SoundFont-Klänge
  als nächste Stufe (Lizenz und Grösse der Sammlung klären).
- Ein anderes Tempo rechnet die Tonspuren neu (ein paar Sekunden Warten).
- Gehört habe ich (Claude) den Klang nicht selbst, nur gemessen: Rückmeldung zum Klang erwünscht.
- Mehrere Spuren mit Wiederholungen nur mit Testdaten geprüft.

### Stand nach Etappe 5 (26. November 2026)

Fertig: eigenes Format `.scrivi` (lesbarer Text, Lesen und Schreiben, Rundlauf-Tests). Bearbeiten im
Kern (`ScoreEditor`): Überschreib-Eingabe, bei der jeder Takt voll bleibt (Pausen füllen zuerst bis
zum nächsten Schlag auf), Bundzahl oder Notenname, Stift ins Notensystem, Akkorde aus mehreren
Saiten, Notenwerte, Punkt, Triole, Pause, Haltebogen, Halbton, Spieltechniken, Fermate,
Akkordsymbol, Text, Liedtext, Takte einfügen/löschen, Taktart, Tonart, Tempo, Wiederholungen,
Formteil, Doppelstrich, Titel, Transponieren (mit Bünden, Tonart und Akkordsymbolen), Kopieren,
Ausschneiden, Einfügen, Rückgängig/Wiederholen. Gitarre: Saite und Bund werden bequem gewählt
(nahe beim vorigen Ton bzw. bis Bund 12). In der App: Bearbeiten-Knopf, **Werkzeugleiste, die beim
Cursor schwebt** (Wunsch des Besitzers), Tastatur, Antippen setzt Cursor (Takt, Schlag, Saite),
„Neues Stück“, automatisches Speichern (Original importierter Dateien bleibt in „Originale“),
Wiedergabe folgt den Änderungen.

Bewusst offen:
- Geschrieben wird nur in Stimme 1 einer Spur; zweite Stimmen und Schlagzeug-Eingabe → Etappe 7.
- Nach jeder Änderung wird das ganze Stück neu gesetzt. Bei langen Stücken auf dem Surface messen;
  falls zu langsam: nur die betroffenen Zeilen neu setzen.
- Vorschlagsnoten, Dynamik, Gabeln, Häuser und D.C./D.S. lassen sich noch nicht schreiben (nur lesen).
- Griffbrett zum Antippen (aus Suona) fehlt noch; die Bundzahlen-Tasten in der Werkzeugleiste
  ersetzen es vorerst.

### Schreiben neu gedacht (27. November 2026)

Rückmeldung des Besitzers: Scrivi ist zum Schreiben da, ein Bearbeiten-Modus ist falsch; die
Aufteilung des bisherigen Gitarren-Programms gefällt (Werkzeuge links, Noten Mitte, Eigenschaften
rechts, Spuren unten), nicht aber die Anordnung der Werkzeuge und das Aussehen. Kein Ring-Menü
(verdeckt die Noten), kein automatisches Weiterspringen (Akkorde!), Notenzeichen statt Wörter mit
schnell erscheinendem Hinweis. Vorschlag mit Skizze:
https://claude.ai/artifact/GpYAHjvszpKnWipUK5Lvgt

Plan in fünf Schritten:
1. **Neuer Bildschirm, immer schreiben** ✅ – obere Leiste (Bereiche ein/aus, Rückgängig, Zoom,
   Abspielen ab Cursor, Anzeige Spur/Takt/Zeit/Tempo/Taktart/Tonart, Tempo %, Schleife, Metronom,
   Einzähler, Mischpult, Ansicht, Suche), Werkzeugspalte links (Gruppen, Notenzeichen, Hinweis nach
   0,15 s, aktiv/blass, nur passende Werkzeuge, Suchfeld), Griffbrett unten (Akkorde durch weitere
   Saiten, Töne des Takts blass), Ton beim Eingeben, Befehlssuche (Strg+K).
2. **Aussehen wie ein Tonstudio-Programm** ✅ (Wunsch des Besitzers) – Spur-Bahnen unten (Lineal
   mit Taktnummern, Formteile als Farbbänder, Schleife durch Ziehen, pro Spur Name, Stumm, Solo,
   Lautstärke und die Takte als Kästchen mit kleinen Notenstrichen, Abspiel-Linie, Strg + Mausrad
   zoomt), Eigenschaften rechts (am Cursor, Takt, Spur mit Klang/Stimmung/Kapo/Lautstärke/
   Links-Rechts, Stück), Endlos-Ansicht (alle Takte in einer langen Zeile, waagrecht), Spuren
   hinzufügen, umbenennen, löschen, Klang wählen, Stimmung und Kapo ändern (Töne oder Griffe
   bleiben). Noch offen: Reiter für mehrere Stücke.
3. **Schnell-Eingaben** ✅ – Akkordzeile tippen („G | Em | C D | Am7“, % wiederholt, - hält), dazu
   gleich ein Begleitmuster; Begleitmuster für einen Bereich (Anschlag: Ganze, Viertel, Achtel,
   Pop/Folk, Rock, Bass und Schlag, Offbeat; Zupfen: auf und ab, Wechselbass, Arpeggio; 3/4 und
   6/8) mit Griffen aus der Griffbibliothek oder selbst gesucht (andere Stimmungen, Kapo);
   Liedtext als ganzen Text einfügen (Silben mit -, _ hält); Formteil wiederholen (alle Spuren,
   nach dem Cursor oder am Ende).
4. Stift-Gesten, waagrechte Band-Ansicht.
5. Mikrofon-Eingabe (einstimmig).

### Dateien statt Bibliothek (27. November 2026)

Entscheid des Besitzers: keine Bibliothek. Stücke sind `.scrivi`-Dateien, gespeichert, wo man
will. Startseite mit *Neues Stück* (Vorlagen: Gitarre mit Tab, Gitarre nur Noten, Bass,
Leadsheet, Eigene), *Öffnen …* und *Zuletzt geöffnet*; keine Seitenleiste mehr (Einstellungen über
das Zahnrad), ein Stück füllt den ganzen Bildschirm. Neue Stücke sind bis zum ersten Speichern
Entwürfe (laufend gesichert). Andere Formate werden nie überschrieben. Die Stücke der früheren
Bibliothek erscheinen beim ersten Start unter *Zuletzt geöffnet*. Windows: `.scrivi` per
Doppelklick.

## 9. Entscheidungen (26. November 2026)

1. **Umfang:** alles, was unter Punkt 1 steht.
2. **Alte Dateien:** sehr viele Guitar-Pro-Dateien. Vier Beispiele liegen vor (siehe unten).
3. **Bibliothek:** ~~Scrivi verwaltet seine Stücke selbst wie Volti~~ – am 27. November 2026 geändert: Stücke sind Dateien, siehe „Dateien statt Bibliothek“. Ursprünglich: Import und Export
   einzelner Dateien.
4. **Name:** Scrivi.

## 10. Was die eigenen Dateien brauchen

Ausgewertet wurden vier Beispiele (Worship-Lieder, je eine Gitarrenstimme). Sie sind
urheberrechtlich geschützt und kommen deshalb **nicht** ins öffentliche Projekt; sie dienen nur
lokal zum Prüfen.

- **Format:** `.gp` (neueres Format: eine ZIP-Datei mit `Content/score.gpif`, einer XML-Datei).
  Das ist das am besten lesbare der Guitar-Pro-Formate, ein guter Start.
- **Aufbau:** eine Spur „Overdriven Guitar“, Standardstimmung E A D G H E, 24 Bünde, ohne Kapo,
  53 bis 81 Takte, 4/4, Tempo um 78.
- **Was darin vorkommt** (danach richtet sich die Reihenfolge in Etappe 1):
  - **Formteile** (INTRO, VERSE 1, CHORUS, BRIDGE …) in jedem Stück
  - **Akkordsymbole** sehr häufig, dazu **Griffbilder**
  - **Wiederholungen** und **Häuser** (1., 2. …) sehr häufig, Doppelstriche
  - **Haltebögen**, **Slash-Rhythmus** (Schrägstriche statt Noten)
  - **Palm Mute**, **Slide**, **Hammer-on/Pull-off**, gedämpfte Noten (x), ein **Bending**
  - **Crescendo/Decrescendo-Gabeln**, freier Text, einmal Liedtext
  - Klangeinstellungen (Verzerrer usw.): werden beim Einlesen übergangen
- **Folgerung:** Die Stücke sind eher Bandcharts als dichte Notensätze. Formteile,
  Akkordsymbole, Wiederholungen und Slash-Rhythmus gehören deshalb schon in Etappe 1, nicht erst
  später.
