import 'dart:convert';
import 'dart:typed_data';

import 'package:scrivi_core/scrivi_core.dart';
import 'package:test/test.dart';

import 'core_test.dart' show gpif, zipped;

/// Kurzes MusicXML-Stück: Vorschlagsnote, Halbe mit Tremolo und Fermate, Pause.
const _graceXml = '''<?xml version="1.0" encoding="UTF-8"?>
<score-partwise version="3.1">
<part-list><score-part id="P1"><part-name>Gitarre</part-name></score-part></part-list>
<part id="P1"><measure number="1">
<attributes><divisions>1</divisions><time><beats>4</beats><beat-type>4</beat-type></time><clef><sign>G</sign><line>2</line></clef></attributes>
<note><grace slash="yes"/><pitch><step>D</step><octave>5</octave></pitch><type>eighth</type></note>
<note><pitch><step>E</step><octave>5</octave></pitch><duration>2</duration><type>half</type>
<notations><ornaments><tremolo type="single">2</tremolo></ornaments><fermata/></notations></note>
<note><rest/><duration>2</duration><type>half</type></note>
</measure></part></score-partwise>''';

Iterable<T> _all<T>(ScoreLayout l) => l.pages.expand((p) => p.items).whereType<T>();

Iterable<String> _texts(ScoreLayout l) => _all<TextItem>(l).map((t) => t.text);

Iterable<String> _glyphs(ScoreLayout l) => _all<GlyphItem>(l).map((g) => g.name);

void main() {
  group('Griffbilder', () {
    const std = ChordLibrary.standardTuning;

    test('offene Griffe', () {
      expect(ChordLibrary.lookup('D', std)!.frets, [-1, -1, 0, 2, 3, 2]);
      expect(ChordLibrary.lookup('Am7', std)!.frets, [-1, 0, 2, 0, 1, 0]);
      expect(ChordLibrary.lookup('D/F♯', std)!.frets, [2, -1, 0, 2, 3, 2]);
      expect(ChordLibrary.lookup('Em', std)!.barres, isEmpty);
    });

    test('Barré-Griffe auf der E- oder A-Saite', () {
      final fsm = ChordLibrary.lookup('F#m', std)!;
      expect(fsm.frets, [2, 4, 4, 2, 2, 2]);
      expect(fsm.barres.single.fret, 2);
      expect(ChordLibrary.lookup('Bb', std)!.frets, [-1, 1, 3, 3, 3, 1]);
      expect(ChordLibrary.lookup('C#m7', std)!.frets, [-1, 4, 6, 4, 5, 4]);
      // Deutsche Schreibweise: H = B
      expect(ChordLibrary.lookup('Hm', std)!.frets, [-1, 2, 4, 4, 3, 2]);
    });

    test('unbekannte Akkorde und andere Stimmungen ergeben nichts', () {
      expect(ChordLibrary.lookup('Cdim7', std), isNull);
      expect(ChordLibrary.lookup('E/D#', std), isNull);
      expect(ChordLibrary.lookup('D', [38, 45, 50, 55, 59, 64]), isNull);
      expect(ChordLibrary.parse('G/B'), (root: 7, quality: '', bass: 11));
    });

    test('erscheinen oben auf der ersten Seite', () {
      // Ohne Kapo: das unvollständige Griffbild der Datei wird durch den eingebauten D-Griff ersetzt.
      final xml = gpif().replaceAll('<Property name="CapoFret"><Fret>2</Fret></Property>', '');
      final layout = Engraver(GpReader.read(zipped(xml))).layout();
      final nut = _all<LineItem>(layout).where((l) => (l.thickness - 0.3).abs() < 0.001);
      expect(nut, hasLength(1));
      expect(_texts(layout).where((t) => t == 'D'), hasLength(2)); // Griffbild und Akkordsymbol
    });

    test('mit Kapo nur aus der Datei', () {
      final layout = Engraver(GpReader.read(zipped(gpif()))).layout();
      expect(_all<LineItem>(layout).where((l) => (l.thickness - 0.3).abs() < 0.001), isEmpty);
      expect(_texts(layout), contains('Capo 2'));
    });
  });

  group('Stimmung', () {
    final dropD = gpif().replaceAll('40 45 50 55 59 64', '38 45 50 55 59 64');

    test('Saitennamen vor der Tabulatur, deutsch mit H', () {
      final layout = Engraver(
        GpReader.read(zipped(dropD)),
        options: const LayoutOptions(germanNoteNames: true),
      ).layout();
      final small = _all<TextItem>(layout).where((t) => t.role == TextRole.small).map((t) => t.text).toList();
      expect(small, containsAll(['D', 'A', 'G', 'H', 'E']));
    });

    test('englisch mit B, ohne Tabulatur über der ersten Zeile', () {
      final layout = Engraver(GpReader.read(zipped(dropD)), options: const LayoutOptions(showTab: false)).layout();
      expect(_texts(layout).any((t) => t.contains('D A D G B E')), isTrue);
    });

    test('Normalstimmung ohne Saitennamen', () {
      final layout = Engraver(GpReader.read(zipped(gpif()))).layout();
      expect(_all<TextItem>(layout).where((t) => t.role == TextRole.small && t.text == 'H'), isEmpty);
    });
  });

  group('Ansichten', () {
    final score = GpReader.read(zipped(gpif()));

    test('Noten und Tabulatur', () {
      final g = _glyphs(Engraver(score).layout());
      expect(g, contains('gClef8vb'));
      expect(g, contains('6stringTabClef'));
    });

    test('nur Noten', () {
      final g = _glyphs(Engraver(score, options: const LayoutOptions(showTab: false)).layout());
      expect(g, contains('gClef8vb'));
      expect(g, isNot(contains('6stringTabClef')));
    });

    test('nur Tabulatur mit Rhythmus darunter', () {
      final layout = Engraver(score, options: const LayoutOptions(showNotation: false)).layout();
      final g = _glyphs(layout);
      expect(g, isNot(contains('gClef8vb')));
      expect(g, isNot(contains('noteheadBlack')));
      expect(g, contains('6stringTabClef'));
      expect(g, contains('timeSig4'));
      // Hälse unter der Tabulatur: unterhalb der tiefsten Saite
      final tabLines = _all<LineItem>(layout).where((l) => l.y1 == l.y2 && l.x2 - l.x1 > 50).map((l) => l.y1);
      final lowest = tabLines.reduce((a, b) => a > b ? a : b);
      final stems = _all<LineItem>(layout).where((l) => l.x1 == l.x2 && l.y1 > lowest);
      expect(stems, isNotEmpty);
    });

    test('ohne Saiten immer mit Noten', () {
      final piano = utf8.encode(_graceXml.replaceAll('Gitarre', 'Klavier'));
      final s = GpReader.read(Uint8List.fromList(piano));
      final g = _glyphs(Engraver(s, options: const LayoutOptions(showNotation: false)).layout());
      expect(g, contains('noteheadHalf'));
    });
  });

  group('Schlagzeug', () {
    test('eigene Lage pro Instrument, Becken als Kreuz, keine Tonart', () {
      Note d(int k) => Note(pitch: Pitch.fromMidi(k));
      final score = Score(
        info: const ScoreInfo(),
        masterBars: [MasterBar(time: const TimeSignature(4, 4), key: const KeySignature(3))],
        tracks: [
          Track(
            name: 'Schlagzeug',
            staff: const StaffDef(),
            bars: [
              Bar(
                clef: Clef.neutral,
                voices: [
                  Voice([
                    for (final k in [36, 38, 42, 49])
                      Beat(duration: const NoteDuration(NoteValue.quarter), notes: [d(k)]),
                  ]),
                ],
              ),
            ],
          ),
        ],
      );
      final layout = Engraver(score).layout();
      final heads = _all<GlyphItem>(layout).where((g) => g.name.startsWith('notehead')).toList()
        ..sort((a, b) => a.x.compareTo(b.x));
      expect(heads.map((g) => g.name), ['noteheadBlack', 'noteheadBlack', 'noteheadXBlack', 'noteheadXBlack']);
      // Bassdrum unten, Snare in der Mitte, Hi-Hat und Crash über der obersten Linie
      expect(heads[0].y, greaterThan(heads[1].y));
      final top = layout.pages.first.systems.first.staffTop!;
      expect(heads[2].y, lessThan(top + 0.01));
      expect(heads[3].y, lessThan(heads[2].y));
      expect(_glyphs(layout).where((n) => n.startsWith('accidental')), isEmpty);
    });
  });

  group('Endlos-Ansicht', () {
    test('alle Takte in einer Zeile, Seite so breit wie nötig', () {
      final e = ScoreEditor(ScoreEditor.newScore(bars: 40));
      e.cursor = e.cursor.copyWith(string: 5);
      for (var i = 0; i < 12; i++) {
        e.inputFret(i);
        e.moveBeat(1);
      }
      final pages = Engraver(e.score, options: const LayoutOptions(endless: true)).layout().pages;
      expect(pages, hasLength(1));
      final page = pages.single;
      expect(page.systems, hasLength(1));
      final sys = page.systems.single;
      expect(sys.firstBar, 0);
      expect(sys.lastBar, 39);
      expect(page.width, greaterThan(const LayoutOptions().pageWidth * 3));
      expect(page.height, lessThan(45));
      // Takte von links nach rechts, ohne Lücken
      for (var b = 1; b < sys.bars.length; b++) {
        expect(sys.bars[b].x0, closeTo(sys.bars[b - 1].x1, 0.01));
      }
      expect(sys.bars.last.x1, lessThan(page.width));
    });
  });

  group('Vorschläge und Spieltechniken', () {
    final score = GpReader.read(Uint8List.fromList(utf8.encode(_graceXml)));

    test('MusicXML: Vorschlag nimmt keine Zeit, Tremolo und Fermate', () {
      final beats = score.tracks.first.bars.first.voices.first.beats;
      expect(beats.first.grace, GraceType.beforeBeat);
      final main = beats[1];
      expect(main.grace, GraceType.none);
      expect(main.tremolo, 2);
      expect(main.fermata, isTrue);
      // Takt voll trotz Vorschlag: Halbe + Halbe
      final total = beats.where((b) => b.grace == GraceType.none).fold(Fraction.zero, (a, b) => a + b.duration.length);
      expect(total, Fraction(1, 1));
    });

    test('Notensatz: kleine Note mit Querstrich, Fermate', () {
      final layout = Engraver(score).layout();
      final small = _all<GlyphItem>(layout).where((g) => g.name == 'noteheadBlack' && g.scale < 1);
      expect(small, hasLength(1));
      expect(_glyphs(layout), contains('fermataAbove'));
      // Tremolo: zwei schräge Striche (gefüllte Vierecke)
      final slashes = _all<PathItem>(layout).where((p) => p.fill && p.commands.length == 13);
      expect(slashes, hasLength(2));
    });
  });
}
