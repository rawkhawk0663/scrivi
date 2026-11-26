import 'package:scrivi_core/scrivi_core.dart';
import 'package:test/test.dart';

import 'core_test.dart' show gpif, zipped;

/// Kurzbeschreibung der Schläge eines Takts: „q:E4“, „8:r“ …
List<String> _bar(ScoreEditor e, int bar) => [
  for (final b in e.beatsOf(bar))
    '${switch (b.duration.value) {
      NoteValue.whole => 'w',
      NoteValue.half => 'h',
      NoteValue.quarter => 'q',
      NoteValue.eighth => '8',
      NoteValue.sixteenth => '16',
      _ => '?',
    }}${'.' * b.duration.dots}${b.duration.tuplet != null ? '3' : ''}:${b.isRest ? 'r' : b.notes.map((n) => n.fret != null ? '${n.string}/${n.fret}' : '${n.pitch}').join('+')}',
];

Fraction _sum(ScoreEditor e, int bar) =>
    e.beatsOf(bar).fold(Fraction.zero, (a, b) => b.grace == GraceType.none ? a + b.duration.length : a);

void main() {
  group('Dateiformat .scrivi', () {
    test('Rundlauf erhält das Stück', () {
      final s = GpReader.read(zipped(gpif()));
      final bytes = ScriviFormat.encode(s);
      expect(ScriviFormat.looksLike(bytes), isTrue);
      final back = GpReader.read(bytes);
      expect(ScriviFormat.toJson(back), ScriviFormat.toJson(s));
      expect(back.info.title, 'Testlied');
      expect(back.tracks.first.staff.capo, 2);
      expect(back.masterBars.first.repeatStart, isTrue);
      final n = back.tracks.first.bars.first.voices.first.beats.first.notes.first;
      expect(n.tieOrigin, isTrue);
      expect(n.written, s.tracks.first.bars.first.voices.first.beats.first.notes.first.written);
    });

    test('kaputte Datei wird erkannt', () {
      final bad = ScriviFormat.encode(ScoreEditor.newScore()).sublist(0, 60);
      expect(() => GpReader.read(bad), throwsA(isA<ScoreFileException>()));
    });

    test('neues Stück: volle Takte, Gitarre mit Tab', () {
      final s = ScoreEditor.newScore(title: 'Neu', bars: 4, time: const TimeSignature(3, 4));
      expect(s.masterBars, hasLength(4));
      final t = s.tracks.single;
      expect(t.staff.isStringed, isTrue);
      expect(t.bars.first.voices.first.beats.single.duration.dots, 1); // punktierte Halbe
      final lead = ScoreEditor.newScore(kind: NewPieceKind.leadSheet);
      expect(lead.tracks.single.staff.isStringed, isFalse);
    });
  });

  group('Eingabe', () {
    ScoreEditor fresh({TimeSignature time = const TimeSignature(4, 4)}) =>
        ScoreEditor(ScoreEditor.newScore(bars: 2, time: time));

    test('Bundzahl teilt die Ganze-Pause, Takt bleibt voll', () {
      final e = fresh();
      e.cursor = e.cursor.copyWith(string: 5);
      e.inputFret(3);
      expect(_bar(e, 0), ['q:5/3', 'q:r', 'h:r']);
      expect(_sum(e, 0), Fraction(1));
      // Klingend: hohe E-Saite + 3 = G4
      expect(e.currentBeat!.notes.single.pitch.midi, 67);
      expect(e.currentBeat!.notes.single.written!.octave, 5);
    });

    test('Akkord aus mehreren Saiten, nächster Schlag, Taktende hängt Takt an', () {
      final e = fresh();
      e.cursor = e.cursor.copyWith(string: 0);
      e.inputFret(3);
      e.cursor = e.cursor.copyWith(string: 1);
      e.inputFret(2);
      expect(_bar(e, 0).first, 'q:0/3+1/2');
      e.moveBeat(1);
      e.setDuration(NoteValue.half);
      e.inputFret(0);
      expect(_bar(e, 0), ['q:0/3+1/2', 'h:1/0', 'q:r']);
      e.moveBar(1);
      e.moveBeat(1);
      expect(e.score.masterBars, hasLength(3));
    });

    test('Notenname: Oktave nahe beim vorigen Ton, Vorzeichen aus der Tonart', () {
      final e = ScoreEditor(ScoreEditor.newScore(bars: 1, kind: NewPieceKind.leadSheet, key: const KeySignature(2)));
      e.inputStep(4); // G
      e.moveBeat(1);
      e.inputStep(3); // F → Fis in D-Dur
      final notes = [
        for (final b in e.beatsOf(0))
          if (!b.isRest) b.notes.single.pitch,
      ];
      expect(notes[1].alter, 1);
      expect((notes[1].diatonic - notes[0].diatonic).abs(), 1);
    });

    test('Gitarre: Notenname bekommt Saite und Bund', () {
      final e = fresh();
      e.inputStep(2); // E
      final n = e.currentBeat!.notes.single;
      expect(n.string, isNotNull);
      expect(n.fret, isNotNull);
      final st = e.score.tracks.first.staff;
      expect(st.tuning[n.string!] + n.fret!, n.pitch.midi);
    });

    test('Gitarre: hoher Ton auf der tiefen Saite wandert auf eine bequeme Saite', () {
      final e = fresh();
      e.cursor = e.cursor.copyWith(string: 0);
      e.inputDiatonic(const Pitch(0, 0, 5).diatonic); // c'' geschrieben = C4 klingend
      final n = e.currentBeat!.notes.single;
      expect(n.pitch.midi, 60);
      expect(n.fret! <= 12, isTrue);
      expect(n.string, isNot(0));
    });

    test('Notenwert ändern überschreibt bzw. füllt auf', () {
      final e = fresh();
      e.cursor = e.cursor.copyWith(string: 3);
      e.inputFret(5);
      e.setDuration(NoteValue.whole);
      expect(_bar(e, 0), ['w:3/5']);
      e.setDuration(NoteValue.eighth);
      expect(_bar(e, 0), ['8:3/5', '8:r', 'q:r', 'h:r']);
      e.toggleDot();
      expect(_bar(e, 0).first, '8.:3/5');
      expect(_sum(e, 0), Fraction(1));
    });

    test('Triole ein und aus', () {
      final e = fresh();
      e.setDuration(NoteValue.eighth);
      e.inputFret(0);
      e.toggleTriplet();
      expect(_bar(e, 0).take(3), ['83:0/0', '83:r', '83:r']);
      expect(_sum(e, 0), Fraction(1));
      e.toggleTriplet();
      expect(_bar(e, 0).take(2), ['8:0/0', '8:r']);
      expect(_sum(e, 0), Fraction(1));
    });

    test('Haltebogen übernimmt die Töne', () {
      final e = fresh();
      e.cursor = e.cursor.copyWith(string: 2);
      e.inputFret(7);
      e.moveBeat(1);
      e.toggleTie();
      final beats = e.beatsOf(0);
      expect(beats[1].notes.single.tieDestination, isTrue);
      expect(beats[1].notes.single.fret, 7);
      expect(beats[0].notes.single.tieOrigin, isTrue);
    });

    test('Pause, Technik, Akkord, Text, Liedtext', () {
      final e = fresh();
      e.inputFret(5);
      e.toggleTechnique(Technique.palmMute);
      expect(e.currentBeat!.notes.single.palmMuted, isTrue);
      expect(e.hasTechnique(Technique.palmMute), isTrue);
      e.toggleTechnique(Technique.bend);
      expect(e.currentBeat!.notes.single.bend!.maxSemitones, 2);
      e.setChord('Am7');
      expect(e.chordAtCursor(), 'Am7');
      e.setText('leise');
      e.setLyric('Hal');
      expect(e.currentBeat!.lyrics, ['Hal']);
      e.toRest();
      expect(e.currentBeat!.isRest, isTrue);
      expect(e.chordAtCursor(), 'Am7');
    });

    test('Rückgängig und Wiederholen', () {
      final e = fresh();
      e.inputFret(1);
      e.inputFret(2);
      expect(e.currentBeat!.notes.single.fret, 2);
      e.undo();
      expect(e.currentBeat!.notes.single.fret, 1);
      e.undo();
      expect(e.currentBeat!.isRest, isTrue);
      expect(e.canUndo, isFalse);
      e.redo();
      e.redo();
      expect(e.currentBeat!.notes.single.fret, 2);
    });
  });

  group('Takte und Stück', () {
    test('Takte einfügen und löschen, Tempo wandert mit', () {
      final e = ScoreEditor(ScoreEditor.newScore(bars: 3));
      e.cursor = e.cursor.copyWith(bar: 2);
      e.setTempo(80);
      e.cursor = e.cursor.copyWith(bar: 0);
      e.insertBars(after: false, count: 2);
      expect(e.score.masterBars, hasLength(5));
      expect(e.score.tempos.last.bar, 4);
      expect(e.score.tracks.first.bars, hasLength(5));
      e.anchor = const EditCursor(bar: 0);
      e.cursor = const EditCursor(bar: 1);
      e.deleteBars();
      expect(e.score.masterBars, hasLength(3));
      expect(e.score.tempos.last.bar, 2);
    });

    test('Taktart ändern passt die Takte an', () {
      final e = ScoreEditor(ScoreEditor.newScore(bars: 2));
      e.setDuration(NoteValue.half);
      e.inputFret(0);
      e.setTimeSignature(const TimeSignature(3, 4));
      expect(e.score.masterBars.every((m) => m.time.beats == 3), isTrue);
      expect(_sum(e, 0), Fraction(3, 4));
      expect(_sum(e, 1), Fraction(3, 4));
      expect(_bar(e, 0).first, 'h:0/0');
    });

    test('Wiederholung, Formteil, Titel', () {
      final e = ScoreEditor(ScoreEditor.newScore(bars: 2));
      e.toggleRepeatStart();
      e.cursor = e.cursor.copyWith(bar: 1);
      e.setRepeatEnd(2);
      e.setSection('Refrain');
      e.setInfo(title: 'Mein Lied', artist: 'Ich');
      expect(PlaybackPlan.playOrder(e.score), [0, 1, 0, 1]);
      expect(e.score.masterBars[1].section!.label, 'Refrain');
      expect(e.score.info.title, 'Mein Lied');
    });

    test('Transponieren: Töne, Bünde, Tonart und Akkorde', () {
      final e = ScoreEditor(ScoreEditor.newScore(bars: 1, key: const KeySignature(2)));
      e.cursor = e.cursor.copyWith(string: 4);
      e.inputFret(3); // D auf der H-Saite
      e.setChord('D/F#');
      e.transposeAll(2);
      final n = e.currentBeat!.notes.single;
      expect(n.pitch.midi, 64);
      expect(n.fret, 5);
      expect(e.score.masterBars.first.key.fifths, 4);
      expect(e.chordAtCursor(), 'E/G#');
      expect(ScoreEditor.transposeChordName('Hm7', 1, 0), 'Cm7');
    });

    test('Kopieren und Einfügen über den Taktstrich', () {
      final e = ScoreEditor(ScoreEditor.newScore(bars: 1));
      e.setDuration(NoteValue.half);
      e.inputFret(1);
      e.moveBeat(1);
      e.inputFret(2);
      e.selectAll();
      final clip = e.copy();
      expect(clip, hasLength(2));
      e.anchor = null;
      e.cursor = const EditCursor(bar: 0, beat: 1);
      e.paste(clip);
      expect(e.score.masterBars, hasLength(2));
      expect(_bar(e, 0), ['h:0/1', 'h:0/1']);
      expect(_bar(e, 1).first, 'h:0/2');
      expect(_sum(e, 1), Fraction(1));
    });

    test('bearbeitetes Stück lässt sich setzen und abspielen', () {
      final e = ScoreEditor(ScoreEditor.newScore(bars: 2));
      for (var f = 0; f < 6; f++) {
        e.inputFret(f);
        e.moveBeat(1);
      }
      final layout = Engraver(e.score).layout();
      expect(layout.pages, isNotEmpty);
      final plan = PlaybackPlan.build(e.score);
      expect(plan.tracks.single.notes, hasLength(6));
    });
  });
}
