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

    test('Dynamik, Gabel, Anschlag, Tenuto', () {
      final e = fresh();
      e.inputFret(3);
      e.setDynamic(Dynamic.p);
      expect(e.currentBeat!.dynamic, Dynamic.p);
      e.toggleHairpin(Hairpin.crescendo);
      expect(e.currentBeat!.hairpin, Hairpin.crescendo);
      e.toggleHairpin(Hairpin.crescendo);
      expect(e.currentBeat!.hairpin, Hairpin.none);
      e.togglePickStroke(1);
      expect(e.currentBeat!.pickStroke, 1);
      e.toggleTechnique(Technique.tenuto);
      expect(e.hasTechnique(Technique.tenuto), isTrue);
      e.setDynamic(null);
      expect(e.currentBeat!.dynamic, isNull);
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

  group('Spuren', () {
    test('Stimmung ändern: Töne bleiben, Bünde wandern (Drop D)', () {
      final e = ScoreEditor(ScoreEditor.newScore(bars: 1));
      e.cursor = e.cursor.copyWith(string: 0);
      e.inputFret(3); // G2 auf der tiefen E-Saite
      e.setTuning(const [38, 45, 50, 55, 59, 64]);
      expect(_bar(e, 0).first, 'q:0/5');
      expect(e.currentBeat!.notes.single.pitch.midi, 43);
      expect(e.score.tracks[0].staff.tuning.first, 38);
    });

    test('Stimmung ändern mit gleichen Griffen: Töne klingen tiefer', () {
      final e = ScoreEditor(ScoreEditor.newScore(bars: 1));
      e.cursor = e.cursor.copyWith(string: 5);
      e.inputFret(0);
      e.setTuning(const [39, 44, 49, 54, 58, 63], keepFrets: true); // Es-Stimmung
      expect(_bar(e, 0).first, 'q:5/0');
      expect(e.currentBeat!.notes.single.pitch.midi, 63);
      e.undo();
      expect(e.currentBeat!.notes.single.pitch.midi, 64);
    });

    test('Kapo: Töne bleiben, Bünde zählen ab dem Kapo', () {
      final e = ScoreEditor(ScoreEditor.newScore(bars: 1));
      e.cursor = e.cursor.copyWith(string: 4);
      e.inputFret(5);
      e.setTuning(const [40, 45, 50, 55, 59, 64], capo: 2);
      expect(_bar(e, 0).first, 'q:4/3');
      expect(e.score.tracks[0].staff.capo, 2);
    });

    test('Spur hinzufügen, umbenennen, Klang, löschen', () {
      final e = ScoreEditor(ScoreEditor.newScore(bars: 3));
      e.addTrack(NewPieceKind.bass);
      expect(e.score.tracks, hasLength(2));
      expect(e.track, 1);
      expect(e.score.tracks[1].bars, hasLength(3));
      expect(e.score.tracks[1].staff.stringCount, 4);
      e.setTrackInfo(1, name: ' E-Bass ', program: 34);
      expect(e.score.tracks[1].name, 'E-Bass');
      expect(e.score.tracks[1].program, 34);
      final back = ScriviFormat.decode(ScriviFormat.encode(e.score));
      expect(back.tracks[1].name, 'E-Bass');
      e.removeTrack(0);
      expect(e.score.tracks.single.name, 'E-Bass');
      expect(e.track, 0);
      e.removeTrack(0); // die letzte bleibt
      expect(e.score.tracks, hasLength(1));
    });
  });

  group('Schnell-Eingaben', () {
    ScoreEditor fresh([int bars = 4]) => ScoreEditor(ScoreEditor.newScore(bars: bars));
    String? chordOf(ScoreEditor e, int bar, int beat) {
      final id = e.beatsOf(bar)[beat].chordId;
      return id == null ? null : e.score.tracks[e.track].chords[id]!.name;
    }

    test('Akkordzeile zerlegen', () {
      expect(ScoreEditor.parseChordLine('G Em C D'), [
        ['G'],
        ['Em'],
        ['C'],
        ['D'],
      ]);
      expect(ScoreEditor.parseChordLine('| G | Em | C D | % |'), [
        ['G'],
        ['Em'],
        ['C', 'D'],
        ['C', 'D'],
      ]);
      expect(ScoreEditor.parseChordLine('G - - D | Am7'), [
        ['G', '-', '-', 'D'],
        ['Am7'],
      ]);
    });

    test('Akkordzeile setzt Akkorde, teilt Pausen, hängt Takte an', () {
      final e = fresh(2);
      final r = e.setChordLine('G | Em | C D');
      expect(r, (0, 2));
      expect(e.score.masterBars, hasLength(3));
      expect(chordOf(e, 0, 0), 'G');
      expect(chordOf(e, 1, 0), 'Em');
      expect(chordOf(e, 2, 0), 'C');
      // D auf der zweiten Hälfte: die Ganze-Pause wurde geteilt
      expect(_bar(e, 2), ['h:r', 'h:r']);
      expect(chordOf(e, 2, 1), 'D');
      expect(e.chordAt(2, Fraction(3, 4)), 'D');
      expect(e.chordAt(3 - 1, Fraction.zero), 'C');
    });

    test('Begleitmuster: Pop-Anschlag mit Griffen', () {
      final e = fresh(2);
      e.setChordLine('G | C D');
      e.applyPattern(StrumPattern.byId('pop')!, 0, 1);
      final b0 = e.beatsOf(0);
      expect(b0.map((b) => b.duration.value), [
        NoteValue.quarter,
        NoteValue.eighth,
        NoteValue.quarter,
        NoteValue.eighth,
        NoteValue.eighth,
        NoteValue.eighth,
      ]);
      expect(_sum(e, 0), Fraction(1));
      // G-Griff 320003: abwärts alle sechs Saiten, aufwärts die hohen
      expect(b0[0].notes.map((n) => '${n.string}/${n.fret}'), ['0/3', '1/2', '2/0', '3/0', '4/0', '5/3']);
      expect(b0[0].pickStroke, 1);
      expect(b0[2].pickStroke, -1);
      expect(b0[2].notes, hasLength(4));
      expect(chordOf(e, 0, 0), 'G');
      // Takt 2: Wechsel zu D auf der Hälfte, das gehaltene Aufwärts wird geteilt
      expect(_sum(e, 1), Fraction(1));
      final b1 = e.beatsOf(1);
      final d = b1.indexWhere((b) => b.chordId != null && e.score.tracks[0].chords[b.chordId]!.name == 'D');
      expect(e.onsetOf(1, d), Fraction(1, 2));
      expect(b1[d].notes.map((n) => n.string), [3, 4, 5]); // D-Griff xx0232, aufwärts ohne Bass
      final plan = PlaybackPlan.build(e.score);
      expect(plan.tracks.single.notes, isNotEmpty);
    });

    test('Zupfmuster mit Bass und Saiten von oben gezählt', () {
      final e = fresh(1);
      e.setChordLine('Am');
      e.applyPattern(StrumPattern.byId('zupf')!, 0, 0);
      final strings = [for (final b in e.beatsOf(0)) b.notes.single.string];
      // Am x02210: Bass A-Saite, dann G, H, e, H, G, H, e
      expect(strings, [1, 3, 4, 5, 4, 3, 4, 5]);
      expect(e.beatsOf(0).first.notes.single.letRing, isTrue);
    });

    test('Griffe für andere Stimmungen und mit Kapo', () {
      // Drop D: G mit dem Grundton auf der tiefen Saite (Bund 5)
      final g = ChordLibrary.voicing('G', const [38, 45, 50, 55, 59, 64])!;
      expect(g.first, 5);
      // Mit Kapo 2: A klingt wie der G-Griff
      final a = ChordLibrary.voicing('A', const [40, 45, 50, 55, 59, 64], capo: 2)!;
      for (var s = 0; s < 6; s++) {
        if (a[s] >= 0) expect((const [40, 45, 50, 55, 59, 64][s] + 2 + a[s]) % 12, isIn([9, 1, 4]));
      }
      expect(ChordLibrary.voicing('Bbdim7', const [40, 45, 50, 55, 59, 64]), isNotNull);
    });

    test('Liedtext verteilen, Pausen und Haltebögen auslassen', () {
      expect(ScoreEditor.parseLyrics('Son-nen-schein ü-ber _ mir'), [
        'Son-',
        'nen-',
        'schein',
        'ü-',
        'ber',
        '_',
        'mir',
      ]);
      final e = fresh(2);
      e.cursor = e.cursor.copyWith(string: 5);
      for (var i = 0; i < 6; i++) {
        e.inputFret(i);
        e.moveBeat(1);
      }
      e.cursor = const EditCursor();
      final n = e.setLyricsText('Hal-lo Welt _ du');
      expect(n, 5);
      final lyr = [
        for (final b in [...e.beatsOf(0), ...e.beatsOf(1)])
          if (b.lyrics.isNotEmpty) b.lyrics.first,
      ];
      expect(lyr, ['Hal-', 'lo', 'Welt', 'du']);
    });

    test('Formteil kopieren: Takte, Akkorde und Name kommen mit', () {
      final e = fresh(4);
      e.setChordLine('G | D | Em | C');
      e.cursor = const EditCursor(bar: 2);
      e.setSection('Refrain');
      expect(e.sections, [('Refrain', 2, 3)]);
      e.copyBars(2, 3, 4);
      expect(e.score.masterBars, hasLength(6));
      expect(e.score.masterBars[4].section?.label, 'Refrain');
      expect(chordOf(e, 4, 0), 'Em');
      expect(chordOf(e, 5, 0), 'C');
      expect(e.cursor.bar, 4);
      expect(e.sections, [('Refrain', 2, 3), ('Refrain', 4, 5)]);
      e.undo();
      expect(e.score.masterBars, hasLength(4));
    });
  });

  group('Transponierende Instrumente und Swing', () {
    Score trumpet() {
      final s = ScoreEditor.newScore(bars: 2, kind: NewPieceKind.leadSheet);
      final e = ScoreEditor(s)..setTrackInfo(0, name: 'Trompete', program: 56, instrumentKey: 2);
      return e.score;
    }

    test('Töne mit der passenden Stufe transponieren', () {
      expect(const Pitch(1, -1, 5).transposedBy(2), const Pitch(2, -1, 5)); // Des → Es
      expect(const Pitch(3, 1, 4).transposedBy(2), const Pitch(4, 1, 4)); // Fis → Gis
      expect(const Pitch(6, 0, 4).transposedBy(2), const Pitch(0, 1, 5)); // H → Cis
      expect(const Pitch(0, 0, 4).transposedBy(9), const Pitch(5, 0, 4)); // C → A (Altsax)
    });

    test('Tonart verschieben', () {
      expect(const KeySignature(-1).transposed(2).fifths, 1); // d-Moll → e-Moll
      expect(const KeySignature(0).transposed(9).fifths, 3); // Altsax in Es: A-Dur
      expect(const KeySignature(-1).transposed(7).fifths, 0); // Horn in F
      expect(const KeySignature(2).transposed(14).fifths, 4);
    });

    test('Ansicht transponiert: Trompete in B zwei Halbtöne höher, Tonart mit', () {
      final e = ScoreEditor(trumpet());
      e.inputStep(0); // C (klingend, Ansicht klingend)
      expect(e.currentBeat!.notes.single.pitch.midi % 12, 0);
      Iterable<GlyphItem> glyphs(bool t) => Engraver(
        e.score,
        options: LayoutOptions(transposed: t),
      ).layout().pages.expand((p) => p.items).whereType<GlyphItem>();
      double headY(bool t) => glyphs(t).firstWhere((g) => g.name.startsWith('notehead')).y;
      // Transponiert eine Stufe höher (D statt C), mit zwei Kreuzen vorne
      expect(headY(false) - headY(true), closeTo(0.5, 0.02)); // eine Stufe (Zeilenlage kann minimal abweichen)
      expect(glyphs(true).where((g) => g.name == 'accidentalSharp'), hasLength(2));
      expect(glyphs(false).where((g) => g.name == 'accidentalSharp'), isEmpty);
    });

    test('Eingabe in der Ansicht transponiert wird zurückgerechnet', () {
      final e = ScoreEditor(trumpet())..viewShift = 2;
      e.inputStep(1); // geschriebenes D → klingt C
      expect(e.currentBeat!.notes.single.pitch.midi % 12, 0);
      final back = ScriviFormat.decode(ScriviFormat.encode(e.score));
      expect(back.tracks.single.instrumentKey, 2);
    });

    test('Stift: Note setzen, Akkordton dazu, gleiche Stelle ändert nichts', () {
      final e = ScoreEditor(ScoreEditor.newScore(kind: NewPieceKind.guitarNotation, bars: 1));
      const g4 = 4 * 7 + 4, h4 = 4 * 7 + 6;
      expect(e.penNote(g4), isTrue);
      expect(e.currentBeat!.notes.single.pitch.toString(), 'G3'); // Gitarre klingt eine Oktave tiefer
      final rev = e.revision;
      expect(e.penNote(g4), isFalse);
      expect(e.revision, rev);
      expect(e.penNote(h4), isTrue);
      expect(e.currentBeat!.notes.map((n) => n.pitch.midi).toList()..sort(), [55, 59]);
    });

    test('Swing: Achtel lang–kurz, ab dem Cursor, gespeichert', () {
      final e = ScoreEditor(ScoreEditor.newScore(bars: 2));
      e.cursor = const EditCursor(bar: 1);
      e.setSwing(true);
      expect(e.score.masterBars[0].swing, isFalse);
      expect(e.score.masterBars[1].swing, isTrue);
      final plan = PlaybackPlan.build(e.score);
      final straight = plan.bars[0], swung = plan.bars[1];
      final q = straight.secondsAt(0.25);
      expect(straight.secondsAt(0.125), closeTo(q / 2, 1e-9));
      expect(swung.secondsAt(0.125), closeTo(q * 2 / 3, 1e-9));
      expect(swung.secondsAt(0.25), closeTo(q, 1e-9));
      expect(swung.positionAt(q * 2 / 3), closeTo(0.125, 1e-9));
      expect(ScriviFormat.decode(ScriviFormat.encode(e.score)).masterBars[1].swing, isTrue);
      final texts = Engraver(e.score).layout().pages.expand((p) => p.items).whereType<TextItem>().map((t) => t.text);
      expect(texts, contains('Swing'));
    });
  });
}
