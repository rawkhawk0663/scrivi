import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:scrivi_core/scrivi_core.dart';
import 'package:test/test.dart';

/// Kleine, selbst gebaute Guitar-Pro-Datei (score.gpif) zum Testen.
String gpif({String bars = '', String extraMasterBar = '', String time = '4/4', int masterBars = 2}) {
  final mbs = StringBuffer();
  for (var i = 0; i < masterBars; i++) {
    mbs.write('''
<MasterBar>
  <Key><AccidentalCount>${i == 0 ? 2 : 2}</AccidentalCount><Mode>Major</Mode></Key>
  <Time>$time</Time>
  ${i == 0 ? '<Repeat start="true" end="false" count="0"/><Section><Letter><![CDATA[A]]></Letter><Text><![CDATA[Intro]]></Text></Section>' : '<Repeat start="false" end="true" count="2"/><AlternateEndings>1 2</AlternateEndings>'}
  $extraMasterBar
  <Bars>$i</Bars>
</MasterBar>''');
  }
  return '''<?xml version="1.0" encoding="utf-8"?>
<GPIF>
<Score><Title><![CDATA[Testlied]]></Title><Artist><![CDATA[Niemand]]></Artist><Copyright><![CDATA[]]></Copyright></Score>
<MasterTrack><Tracks>0</Tracks><Automations><Automation><Type>Tempo</Type><Bar>0</Bar><Position>0</Position><Visible>true</Visible><Value>96 2</Value></Automation></Automations></MasterTrack>
<Tracks><Track id="0"><Name><![CDATA[Gitarre]]></Name><SystemsLayout>2</SystemsLayout>
<Transpose><Chromatic>0</Chromatic><Octave>-1</Octave></Transpose>
<Staves><Staff><Properties>
<Property name="Tuning"><Pitches>40 45 50 55 59 64</Pitches></Property>
<Property name="CapoFret"><Fret>2</Fret></Property>
<Property name="DiagramCollection"><Items><Item id="0" name="D"><Diagram stringCount="6" fretCount="5" baseFret="0"><Fret string="3" fret="2"/></Diagram></Item></Items></Property>
</Properties></Staff></Staves></Track></Tracks>
<MasterBars>$mbs</MasterBars>
<Bars>
<Bar id="0"><Clef>G2</Clef><Voices>0 -1 -1 -1</Voices></Bar>
<Bar id="1"><Clef>G2</Clef><Voices>1 -1 -1 -1</Voices></Bar>
$bars
</Bars>
<Voices>
<Voice id="0"><Beats>0 1 2 2 3</Beats></Voice>
<Voice id="1"><Beats>4</Beats></Voice>
</Voices>
<Beats>
<Beat id="0"><Rhythm ref="1"/><Chord>0</Chord><Notes>0 1</Notes><Dynamic>MF</Dynamic></Beat>
<Beat id="1"><Rhythm ref="1"/><Notes>2</Notes><FreeText><![CDATA[leise]]></FreeText></Beat>
<Beat id="2"><Rhythm ref="0"/><Notes>3</Notes><Slashed/></Beat>
<Beat id="3"><Rhythm ref="2"/></Beat>
<Beat id="4"><Rhythm ref="3"/><Notes>4</Notes><Hairpin>Crescendo</Hairpin></Beat>
</Beats>
<Notes>
<Note id="0"><Tie origin="true" destination="false"/><Properties><Property name="String"><String>3</String></Property><Property name="Fret"><Fret>2</Fret></Property><Property name="Midi"><Number>57</Number></Property>
<Property name="ConcertPitch"><Pitch><Step>A</Step><Accidental/><Octave>4</Octave></Pitch></Property>
<Property name="TransposedPitch"><Pitch><Step>A</Step><Accidental/><Octave>5</Octave></Pitch></Property></Properties></Note>
<Note id="1"><Properties><Property name="String"><String>4</String></Property><Property name="Fret"><Fret>7</Fret></Property><Property name="Midi"><Number>66</Number></Property>
<Property name="ConcertPitch"><Pitch><Step>G</Step><Accidental>b</Accidental><Octave>5</Octave></Pitch></Property>
<Property name="PalmMuted"><Enable/></Property><Property name="HopoOrigin"><Enable/></Property></Properties></Note>
<Note id="2"><Tie origin="false" destination="true"/><Properties><Property name="String"><String>3</String></Property><Property name="Fret"><Fret>2</Fret></Property><Property name="Midi"><Number>57</Number></Property><Property name="Slide"><Flags>2</Flags></Property></Properties></Note>
<Note id="3"><Properties><Property name="String"><String>2</String></Property><Property name="Fret"><Fret>0</Fret></Property><Property name="Muted"><Enable/></Property></Properties></Note>
<Note id="4"><Properties><Property name="String"><String>0</String></Property><Property name="Fret"><Fret>3</Fret></Property>
<Property name="Bended"><Enable/></Property><Property name="BendOriginOffset"><Float>0</Float></Property><Property name="BendOriginValue"><Float>0</Float></Property>
<Property name="BendDestinationOffset"><Float>60</Float></Property><Property name="BendDestinationValue"><Float>100</Float></Property></Properties></Note>
</Notes>
<Rhythms>
<Rhythm id="0"><NoteValue>Quarter</NoteValue></Rhythm>
<Rhythm id="1"><NoteValue>Eighth</NoteValue></Rhythm>
<Rhythm id="2"><NoteValue>Half</NoteValue><AugmentationDot count="1"/><PrimaryTuplet num="3" den="2"/></Rhythm>
<Rhythm id="3"><NoteValue>Whole</NoteValue></Rhythm>
</Rhythms>
</GPIF>''';
}

Uint8List zipped(String xml) {
  final a = Archive()..add(ArchiveFile.bytes('Content/score.gpif', utf8.encode(xml)));
  return Uint8List.fromList(ZipEncoder().encodeBytes(a));
}

void main() {
  group('Bruchzahlen', () {
    test('rechnen genau und kürzen', () {
      expect(Fraction(1, 4) + Fraction(1, 8), Fraction(3, 8));
      expect(Fraction(2, 4), Fraction(1, 2));
      expect(Fraction(1, 2) > Fraction(1, 3), isTrue);
      expect((Fraction(3, 8) - Fraction(1, 8)).toString(), '1/4');
    });

    test('Notenlängen mit Punkten und Triolen', () {
      expect(const NoteDuration(NoteValue.quarter, dots: 1).length, Fraction(3, 8));
      expect(const NoteDuration(NoteValue.eighth, dots: 2).length, Fraction(7, 32));
      expect(const NoteDuration(NoteValue.eighth, tuplet: Tuplet(3, 2)).length, Fraction(1, 12));
    });
  });

  group('Tonhöhen', () {
    test('MIDI und Oktave', () {
      expect(const Pitch(0, 0, 4).midi, 60);
      expect(Pitch.fromMidiSpelled(66, 3, 1), const Pitch(3, 1, 4)); // Fis
      expect(Pitch.fromMidiSpelled(66, 4, -1), const Pitch(4, -1, 4)); // Ges
      // H/Ces über die Oktavgrenze
      expect(Pitch.fromMidiSpelled(59, 0, -1).octave, 4);
    });

    test('Schreibweise aus der Tonart', () {
      expect(Pitch.fromMidi(61, fifths: 2).toString(), 'C#4');
      expect(Pitch.fromMidi(61, fifths: -3).toString(), 'Db4');
    });

    test('Tonart gibt Vorzeichen', () {
      const d = KeySignature(2);
      expect(d.alterFor(3), 1); // F → Fis
      expect(d.alterFor(0), 1); // C → Cis
      expect(d.alterFor(4), 0);
      expect(const KeySignature(-1).alterFor(6), -1); // B → b
    });
  });

  group('Guitar-Pro-Dateien', () {
    test('liest Angaben, Takte, Noten und Techniken', () {
      final s = GpReader.read(zipped(gpif()));
      expect(s.info.title, 'Testlied');
      expect(s.info.artist, 'Niemand');
      expect(s.initialTempo!.bpm, 96);
      expect(s.masterBars.length, 2);
      expect(s.masterBars.first.repeatStart, isTrue);
      expect(s.masterBars.first.section!.label, 'A Intro');
      expect(s.masterBars[1].repeatEnd, 2);
      expect(s.masterBars[1].endings, {1, 2});
      expect(s.masterBars.first.key.fifths, 2);
      final t = s.tracks.single;
      expect(t.name, 'Gitarre');
      expect(t.staff.tuning, [40, 45, 50, 55, 59, 64]);
      expect(t.staff.capo, 2);
      expect(t.transposeSemitones, 12);
      expect(t.layoutHint, [2]);
      expect(t.chords[0]!.name, 'D');
      expect(t.chords[0]!.diagram!.frets[3], 2);
      expect(t.bars.first.clef, Clef.treble8vb);
      final beats = t.bars.first.voices.single.beats;
      expect(beats.length, 5);
      expect(beats.first.chordId, 0);
      expect(beats[1].text, 'leise');
      expect(beats[2].slashed, isTrue);
      expect(beats[4].isRest, isTrue);
      expect(beats[4].duration.dots, 1);
      expect(beats[4].duration.tuplet!.actual, 3);
      final n0 = beats.first.notes.first;
      expect(n0.pitch.toString(), 'A3');
      expect(n0.written.toString(), 'A4');
      expect(n0.tieOrigin, isTrue);
      final n1 = beats.first.notes[1];
      expect(n1.pitch.toString(), 'Gb4'); // Schreibweise aus der Datei
      expect(n1.palmMuted, isTrue);
      expect(n1.hammerOrigin, isTrue);
      expect(beats[1].notes.single.slide, 2);
      expect(beats[2].notes.single.dead, isTrue);
      // aus Saite und Bund; Bundzahlen zählen ab dem Kapodaster (hier Bund 2)
      expect(beats[2].notes.single.pitch.midi, 52);
      final bend = t.bars[1].voices.single.beats.single.notes.single.bend!;
      expect(bend.maxSemitones, 2);
      expect(t.bars[1].voices.single.beats.single.hairpin, Hairpin.crescendo);
    });

    test('erkennt fremde und ältere Formate', () {
      // Kaputte Guitar-Pro-6-Datei
      expect(
        () => GpReader.read(Uint8List.fromList('BCFZ0000'.codeUnits)),
        throwsA(isA<ScoreFileException>().having((e) => e.problem, 'problem', ScoreFileProblem.damaged)),
      );
      expect(
        () => GpReader.read(Uint8List.fromList('hallo welt'.codeUnits)),
        throwsA(isA<ScoreFileException>().having((e) => e.problem, 'problem', ScoreFileProblem.unknownFormat)),
      );
      expect(
        () => GpReader.read(zipped('<GPIF><kaputt')),
        throwsA(isA<ScoreFileException>().having((e) => e.problem, 'problem', ScoreFileProblem.damaged)),
      );
    });
  });

  group('Notensatz', () {
    test('setzt ein Stück ohne Fehler auf Seiten', () {
      final s = GpReader.read(zipped(gpif(masterBars: 2)));
      final layout = Engraver(s).layout();
      expect(layout.pages, isNotEmpty);
      final page = layout.pages.first;
      expect(page.systems.length, 1); // Vorgabe: 2 Takte pro Zeile
      expect(page.systems.first.firstBar, 0);
      expect(page.systems.first.lastBar, 1);
      final texts = page.items.whereType<TextItem>().map((t) => t.text).toList();
      expect(texts, containsAll(['Testlied', 'Niemand', 'A Intro', 'D', 'leise', 'P.M.', '2', 'H', 'full', '1. 2.']));
      // Schrägstrich-Schläge zeigen in der Tabulatur nichts (auch nicht die gedämpfte Note)
      expect(texts, isNot(contains('x')));
      final glyphs = page.items.whereType<GlyphItem>().map((g) => g.name).toSet();
      expect(
        glyphs,
        containsAll([
          'gClef8vb',
          'accidentalSharp',
          'noteheadBlack',
          'noteheadSlashHorizontalEnds',
          'repeatDot',
          'metNoteQuarterUp',
          '6stringTabClef',
        ]),
      );
      // Ges in D-Dur braucht ein b-Vorzeichen
      expect(glyphs, contains('accidentalFlat'));
    });

    test('bricht lange Stücke um und verteilt sie auf Seiten', () {
      final s = GpReader.read(zipped(gpif()));
      // 60 gleiche Takte (aus den zwei Takten der Datei)
      final many = Score(
        info: s.info,
        masterBars: List.generate(60, (i) => s.masterBars[i % 2]),
        tracks: [
          Track(
            name: 'G',
            staff: s.tracks.first.staff,
            bars: List.generate(60, (i) => s.tracks.first.bars[i % 2]),
            transposeSemitones: 12,
          ),
        ],
      );
      final layout = Engraver(many).layout();
      expect(layout.pages.length, greaterThan(1));
      final bars = layout.pages.expand((p) => p.systems).toList();
      expect(bars.first.firstBar, 0);
      expect(bars.last.lastBar, 59);
      for (var i = 1; i < bars.length; i++) {
        expect(bars[i].firstBar, bars[i - 1].lastBar + 1);
      }
      // Kein Element ragt über die Seite hinaus
      for (final p in layout.pages) {
        for (final sys in p.systems) {
          expect(sys.bottom, lessThanOrEqualTo(p.height));
        }
      }
    });

    test('SVG enthält die Notenzeichen', () {
      final s = GpReader.read(zipped(gpif()));
      final svg = pageToSvg(Engraver(s).layout().pages.first);
      expect(svg, startsWith('<svg'));
      expect(svg, contains('id="g_noteheadBlack"'));
      expect(svg, contains('Testlied'));
    });
  });

  test('Notenzeichen haben Umrisse und Ansatzpunkte', () {
    final h = Glyphs.get('noteheadBlack');
    expect(h.path, isNotEmpty);
    expect(h.anchors['stemUpSE']!.x, closeTo(1.18, 0.01));
    expect(Glyphs.engraving('stemThickness'), closeTo(0.12, 0.001));
  });
}
