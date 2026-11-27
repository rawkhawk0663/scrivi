<p align="center"><img src="assets/brand/scrivi_icon.png" height="96" alt="Scrivi"></p>

<h1 align="center">Scrivi</h1>

<p align="center"><b>Noten, Tabulatur und Partituren schreiben.</b><br>
Für Windows und Android · Open Source (GPL-3.0) · <a href="README.en.md">English</a></p>

---

Scrivi ist ein Notenschreibprogramm für Musikerinnen und Musiker, gemacht für das **Surface mit Stift** unter Windows und für Android-Tablets. Es gehört zur Familie von [Volti](https://github.com/rawkhawk0663/volti) (Noten lesen), [Suona](https://github.com/rawkhawk0663/suona) (Noten lernen) und [Conti](https://github.com/rawkhawk0663/conti) (Buchhaltung).

Scrivi gibt es auf **Deutsch und Englisch**. Es braucht **kein Konto**, sammelt **keine Daten** und funktioniert **ohne Internet**.

> **Scrivi ist noch am Anfang.** Heute öffnet es Guitar-Pro-Dateien aller Versionen, MusicXML und MIDI, zeigt sie sauber als Noten mit Tabulatur, spielt sie ab, und du kannst darin schreiben. Als Nächstes: schnellere Eingabe (Akkordzeile, Schlagmuster, Liedtext). Den ganzen Plan findest du im [Bauplan](BAUPLAN.md).

## Was Scrivi heute kann

- **Startseite:** *Neues Stück* mit Vorlagen (Gitarre mit Tab, Gitarre nur Noten, Bass, Leadsheet) oder eigenen Einstellungen, *Öffnen …* für Dateien von überall, dazu *Zuletzt geöffnet* mit Vorschaubild, Titel und Ordner. Dateien lassen sich auch ins Fenster ziehen; unter Windows öffnet ein Doppelklick auf eine `.scrivi`-Datei Scrivi. Die Einstellungen erreichst du über das Zahnrad oben rechts.
- **Dateiformate:** Guitar Pro aller Versionen (`.gp`, `.gpx`, `.gp5`, `.gp4`, `.gp3`), MusicXML (`.musicxml`, `.xml`, gepackt `.mxl`) und MIDI (`.mid`). Bei MIDI rastet Scrivi die Töne auf Sechzehntel ein und teilt sie in Takte. Bei MusicXML wird jede Notenzeile eines Instruments zu einer eigenen Spur; eine Tabulatur zum selben Instrument liefert Saiten und Bünde.
- **Noten mit Tabulatur:** sauber gesetzt auf A4-Seiten, mit den Zeilen so aufgeteilt wie in der Datei vorgesehen. Dazu gehören Titel und Interpret, Tempo, Formteile (Intro, Strophe, Refrain …), Akkordsymbole, Wiederholungen und Häuser, Doppelstriche, Tonart- und Taktwechsel, Haltebögen, Balken, Punktierungen, n-tolen, Vorzeichen, Rhythmus-Schrägstriche, Dynamik und Gabeln, Liedtext und freier Text.
- **Gitarrentechniken:** Palm Mute (P.M.), gedämpfte Noten (x), Hammer-on und Pull-off (H/P), Slides, Bendings mit Angabe (½, full …), Geisternoten, Akzente, let ring, Vibrato, Flageolett, Tapping (T), Anschlag auf und ab, Tremolo-Picking, Fermaten und Vorschlagsnoten.
- **Griffbilder:** Oben auf der ersten Seite stehen die Griffbilder aller Akkorde des Stücks. Sie kommen aus der Datei; fehlen sie, nimmt Scrivi bei Normalstimmung die üblichen Griffe (offen oder als Barré).
- **Stimmung und Kapo:** Bei besonderen Stimmungen (z. B. Drop D, Es-Stimmung) stehen die Saitennamen vor der Tabulatur, deutsch mit H. Ein Kapodaster erscheint als „Capo 2“ über den Noten. Gitarren mit 7 und 8 Saiten und Bass gehen auch.
- **Ansicht wählen:** Noten und Tabulatur, nur Noten oder nur Tabulatur. In der reinen Tabulatur zeigen Hälse und Balken darunter den Rhythmus. Scrivi merkt sich die Wahl.
- **Ansehen:** blättern mit Mausrad, Wischen, Bild auf/ab, Pfeiltasten oder Pedal. Zoomen mit zwei Fingern, Strg + Mausrad oder den Knöpfen oben. Hat eine Datei mehrere Spuren, wählst du die Spur unten in den Spur-Bahnen oder oben in der Anzeige.
- **Abspielen:** Oben in der Leiste, ab dem Cursor, mit allen Wiederholungen, Häusern und Sprüngen (D.C., D.S., Coda, Fine). Eine farbige Markierung läuft mit, die Seiten blättern von selbst. Die Leertaste startet und hält an; danach steht der Cursor dort, wo die Musik war. Dazu: Tempo (25 bis 200 %, die Tonhöhe bleibt), Einzähler, Metronom, Schleife über beliebige Takte und ein Mischpult (Lautstärke, stumm, solo pro Spur). Die Klänge sind echte Aufnahmen, die mit Scrivi installiert werden (funktioniert ohne Internet): Konzert- und Westerngitarre, Jazz- und E-Gitarre (auch verzerrt), E-Bass mit Fingern und Plektrum, dazu Klavier, E-Piano, Orgel, Streicher, Chor, Bläser, Saxofon, Flöte, Synthesizer und Schlagzeug, mit Bendings, Slides, Vibrato, Palm Mute und Flageoletts. Die Klänge stammen von FreePats und FluidR3 (freie Lizenzen, siehe Lizenzen).

- **Schreiben:** Jedes Stück ist sofort zum Schreiben bereit, der Cursor ist immer da. Ein Stück füllt den ganzen Bildschirm. Links die **Werkzeugspalte** mit Notenzeichen, nach Gruppen geordnet (Notenwert und Gitarre offen; Ausdruck, Takt, Text und Stück zum Aufklappen); ein Hinweis mit Name und Tastenkürzel erscheint beim Darüberfahren. Was am Cursor gesetzt ist, leuchtet, was dort nicht geht, ist blass. Unten das **Griffbrett**: Saite und Bund antippen setzt den Ton, weitere Saiten ergeben einen Akkord; die Töne des Takts leuchten mit. Jeder eingegebene Ton klingt kurz an. Mit dem Stift tippst du Noten auch direkt ins Notensystem. Die **Suche** (Lupe oder Strg+K) findet jedes Werkzeug. Werkzeugspalte und Griffbrett lassen sich oben ein- und ausblenden.
- **Spuren unten** (wie in einem Tonstudio-Programm): oben die Taktnummern und die Formteile als Farbbänder, darunter jede Spur als Bahn mit ihren Takten und kleinen Notenstrichen. Antippen springt zu Spur und Takt, Ziehen über die Taktnummern legt eine Schleife fest (Rechtsklick hebt sie auf), Strg + Mausrad zoomt. Pro Spur Stumm, Solo und Lautstärke; mit Rechtsklick auf den Namen umbenennen, Klang wählen, Stimmung und Kapo ändern oder löschen; mit + kommt eine Spur dazu.
- **Eigenschaften rechts:** was am Cursor steht (Ton, Notenwert, Saite und Bund, Akkord), der Takt (Taktart, Tonart, Tempo, Formteil, Wiederholung), die Spur (Name, Klang, Stimmung, Kapo, Lautstärke, links/rechts) und das Stück. Antippen ändert den Wert.
- **Stimmung und Kapo:** bekannte Stimmungen (Drop D, Halbton tiefer, Open G, DADGAD …) oder jede Saite einzeln, Kapo bis Bund 12. Wahlweise bleiben die Töne gleich (die Bünde wandern) oder die Griffe (die Töne klingen anders).
- **Schnell schreiben** (Gruppe „Schnell“ in der Werkzeugspalte): *Akkordzeile* tippen, z. B. „G | Em | C D | Am7“ (Takte mit |, % wiederholt den Takt), und auf Wunsch gleich die Begleitung dazu; *Begleitmuster* für beliebige Takte: Anschlag (Viertel, Achtel, Pop/Folk, Rock, Bass und Schlag, Offbeat, Walzer, Sechsachtel) oder Zupfmuster (auf und ab, Wechselbass, Arpeggio) mit passenden Griffen, auch in anderen Stimmungen und mit Kapo; *Liedtext einfügen* als ganzen Text, Scrivi verteilt die Silben auf die Noten (Silben mit - trennen); *Formteil wiederholen*, z. B. den Refrain nach der Bridge nochmals einfügen.
- **Transponierende Instrumente:** Pro Spur einstellbar, wie das Instrument notiert wird (in B, Es, F, A …). Unter *Ansicht → Transponiert* erscheinen Trompete, Saxofon, Klarinette und Horn so, wie die Musiker sie lesen, mit passender Tonart und Akkordsymbolen; sonst klingend (C-Partitur). Eingaben in der transponierten Ansicht rechnet Scrivi zurück.
- **Swing:** Ab einem beliebigen Takt die Achtel als Swing spielen (Werkzeug *Swing* oder Eigenschaften → Achtel); im Notenbild steht dort „Swing“ bzw. „Gerade“.
- **Beispiele** auf der Startseite: *Sonntagmorgen* (Gitarren-Band), *Ode an die Freude* (Orchester, Beethoven) und *Wüstenwind* (Latin-Jazz mit Swing) zum Ausprobieren und Weiterschreiben.
- **Endlos-Ansicht:** Unter *Ansicht* stehen alle Takte in einer langen Zeile, die man waagrecht durchblättert; beim Abspielen läuft sie mit.
- **Tastatur beim Schreiben:** Bundzahl tippen (zwei Ziffern schnell nacheinander für 10–24), ↑/↓ wechselt die Saite, ←/→ geht von Note zu Note (am Ende kommt ein neuer Takt dazu), A–G bzw. H setzt eine Note (mit Umschalt zum Akkord dazu), + / − kürzer/länger, Punkt, T Triole, L Haltebogen, K Akkord, Y Liedtext, Entf Pause, Umschalt + ↑/↓ Halbton, Strg + Z/Y, Strg + C/X/V.
- **Speichern:** Stücke sind `.scrivi`-Dateien, die du speicherst, wo du willst (*Speichern* bzw. Strg+S). Danach sichert Scrivi jede Änderung von selbst in diese Datei. Ein neues Stück ist bis zum ersten Speichern ein Entwurf, der ebenfalls laufend gesichert wird und unter *Zuletzt geöffnet* bleibt; es geht also nichts verloren. Andere Formate (Guitar Pro, MusicXML, MIDI) überschreibt Scrivi nie: Änderungen daran werden als neue `.scrivi`-Datei gespeichert.

Noch nicht: mehrere Instrumente gleichzeitig (Partitur), Ausgabe als PDF. Das kommt in den nächsten Etappen. Das kommt in den nächsten Etappen.

## Was Scrivi können soll

- **Gitarre:** Noten und Tabulatur gekoppelt, Griffbilder, Rhythmus-Schreibweise, Spieltechniken (Bending, Slide, Hammer-on, Pull-off, Palm Mute …), beliebige Stimmungen und Kapo.
- **Leadsheets:** Melodie, Akkordsymbole, Liedtext, Formteile, Wiederholungen, Häuser, Segno und Coda.
- **Partituren:** mehrere Instrumente, Stimmen-Auszüge, Transposition, Dynamik, Artikulation.
- **Abspielen** mit mitlaufender Markierung, Tempo, Schleife, Einzähler und Metronom.
- **Einlesen:** Guitar-Pro-Dateien, MusicXML, MIDI. **Ausgeben:** PDF, MusicXML, MIDI, direkt an Volti.

## Installieren

Sobald die erste Version bereit ist, liegt sie unter [Releases](https://github.com/rawkhawk0663/scrivi/releases/latest).

- **Windows 10/11:** `Scrivi-Setup.exe` herunterladen und starten. Meldet Windows „Der Computer wurde durch Windows geschützt“: *Weitere Informationen → Trotzdem ausführen*. Ohne Installation: `Scrivi-Windows.zip` entpacken und `Scrivi.exe` starten.
- **Android:** `Scrivi-Android.apk` herunterladen und öffnen.
- **Android mit automatischen Updates:** In der App [Obtainium](https://github.com/ImranR98/Obtainium) „App hinzufügen“ wählen und `https://github.com/rawkhawk0663/scrivi` eintragen.

**Updates** unter Windows direkt in der App: *Einstellungen → Über Scrivi → Nach Updates suchen*.

## Lizenz

Scrivi ist freie Software unter der [GPL-3.0](LICENSE). Die Notenschrift Bravura und die Schriften IBM Plex Sans und Sora stehen unter der SIL Open Font License.
