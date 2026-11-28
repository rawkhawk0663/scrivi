import 'package:scrivi_core/scrivi_core.dart';
import 'package:test/test.dart';

List<String> _glyphs(Score s, {LayoutOptions options = const LayoutOptions()}) => Engraver(
  s,
  options: options,
).layout().pages.expand((p) => p.items).whereType<GlyphItem>().map((g) => g.name).toList();

void main() {
  ScoreEditor melody() {
    final e = ScoreEditor(ScoreEditor.newScore(kind: NewPieceKind.leadSheet, bars: 3));
    e.duration = const NoteDuration(NoteValue.quarter);
    e.inputStep(0); // C
    e.moveBeat(-1);
    return e;
  }

  test('Vorzeichen: ♯ hebt die Note auf ihrer Linie, 𝄫 und Erinnerung in Klammern', () {
    final e = melody();
    final before = e.currentBeat!.notes.single.pitch;
    e.setAccidental(1);
    final n = e.currentBeat!.notes.single;
    expect(n.pitch.midi, before.midi + 1);
    expect(n.pitch.step, before.step);
    expect(_glyphs(e.score), contains('accidentalSharp'));
    e.setAccidental(-2);
    expect(e.currentBeat!.notes.single.pitch.midi, before.midi - 2);
    expect(_glyphs(e.score), contains('accidentalDoubleFlat'));
    e.setAccidental(0);
    e.toggleCourtesy();
    final g = _glyphs(e.score);
    expect(g, containsAll(['accidentalNatural', 'accidentalParensLeft', 'accidentalParensRight']));
    expect(
      ScriviFormat.decode(ScriviFormat.encode(e.score)).tracks[0].bars[0].voices[0].beats[0].notes[0].courtesy,
      isTrue,
    );
  });

  test('Doppelpunkt, Quintole, Vorschlag', () {
    final e = melody();
    e.toggleDoubleDot();
    expect(e.currentBeat!.duration.dots, 2);
    expect(e.currentBeat!.duration.length, Fraction(7, 16));
    final e2 = melody();
    e2.setDuration(NoteValue.eighth);
    e2.toggleTuplet(5);
    final beats = e2.beatsOf(0).where((b) => b.duration.tuplet != null).toList();
    expect(beats.length, 5);
    expect(beats.first.duration.tuplet!.actual, 5);
    expect(beats.first.duration.tuplet!.normal, 4);
    // Noten in die freien Plätze der Quintole schreiben: sie bleibt ganz
    for (var k = 0; k < 4; k++) {
      e2.moveBeat(1);
      e2.inputStep(k + 1);
    }
    final quint = e2.beatsOf(0).where((b) => b.duration.tuplet != null).toList();
    expect(quint.length, 5);
    expect(quint.every((b) => !b.isRest), isTrue);
    var sum = Fraction.zero;
    for (final b in e2.beatsOf(0)) {
      sum = sum + b.duration.length;
    }
    expect(sum, Fraction(1, 1));
    e2.cursor = const EditCursor(bar: 0);
    e2.toggleTuplet(5);
    expect(e2.beatsOf(0).any((b) => b.duration.tuplet != null), isFalse);
    // Vorschlag: die nächste Note kommt vor den Schlag
    final e3 = melody();
    e3.toggleGrace();
    expect(e3.graceNext, isTrue);
    e3.inputStep(1); // D als Vorschlag
    final b0 = e3.beatsOf(0);
    expect(b0.first.grace, GraceType.beforeBeat);
    expect(b0[1].notes.single.pitch.step, 0); // die Hauptnote C bleibt
    expect(e3.hasGraceBefore, isTrue);
    e3.toggleGrace();
    expect(e3.beatsOf(0).any((b) => b.grace != GraceType.none), isFalse);
  });

  test('Häuser, Sprungzeichen, Wiederholungszeichen für einen Takt', () {
    final e = melody();
    e.cursor = const EditCursor(bar: 1);
    e.setEndings({1});
    e.toggleDirection(Direction.segno);
    expect(e.score.masterBars[1].endings, {1});
    expect(e.score.masterBars[1].directions, contains(Direction.segno));
    // % in Takt 2: Noten von Takt 1 werden mitkopiert und klingen
    e.setSimile(1);
    expect(e.score.tracks[0].bars[1].simile, 1);
    expect(e.beatsOf(1).first.notes.single.pitch.step, 0);
    expect(_glyphs(e.score), contains('repeat1Bar'));
    // Vorlage ändern: das Zeichen folgt
    e.cursor = const EditCursor(bar: 0);
    e.inputStep(4); // G
    expect(e.score.tracks[0].bars[1].simile, 1);
    expect(e.beatsOf(1).first.notes.single.pitch.step, 4);
    // Im Takt mit dem Zeichen schreiben: das Zeichen fällt weg
    e.cursor = const EditCursor(bar: 1);
    e.inputStep(2);
    expect(e.score.tracks[0].bars[1].simile, 0);
  });

  test('8va: Noten eine Oktave tiefer geschrieben, mit Linie', () {
    final e = melody();
    double headY(Score sc) {
      final page = Engraver(sc).layout().pages.first;
      final head = page.items.whereType<GlyphItem>().firstWhere((g) => g.name == 'noteheadBlack');
      return head.y - page.systems.first.staffTop!;
    }

    final yBefore = headY(e.score);
    e.setOttava(1);
    expect(e.currentBeat!.ottava, 1);
    final items = Engraver(e.score).layout().pages.first.items;
    final yAfter = headY(e.score);
    expect(yAfter - yBefore, closeTo(3.5, 1e-9)); // eine Oktave = 3,5 Linienabstände tiefer
    expect(items.whereType<GlyphItem>().map((g) => g.name), contains('ottavaAlta'));
    expect(items.whereType<LineItem>().any((l) => l.dash != null), isTrue);
    e.setOttava(1);
    expect(e.currentBeat!.ottava, 0);
  });

  test('Gitarre (Paket 2): Zeichen in Tab und Noten, Klang', () {
    final e = ScoreEditor(ScoreEditor.newScore(bars: 2));
    e.duration = const NoteDuration(NoteValue.half);
    e.cursor = const EditCursor(string: 3);
    e.inputFret(2);
    e.toggleTechnique(Technique.artificialHarmonic);
    e.toggleTechnique(Technique.trill);
    e.setFade(1);
    e.moveBeat(1);
    // Akkord, gebrochen aufwärts, mit Hinausgleiten
    e.cursor = e.cursor.copyWith(string: 2);
    e.inputFret(2);
    e.cursor = e.cursor.copyWith(string: 3);
    e.inputFret(2);
    e.cursor = e.cursor.copyWith(string: 4);
    e.inputFret(1);
    e.setArpeggio(1);
    e.toggleTechnique(Technique.slideOutDown);
    e.setWhammy(-1);
    final page = Engraver(e.score).layout().pages.first;
    final texts = page.items.whereType<TextItem>().map((t) => t.text).join(' ');
    expect(texts, contains('A.H.'));
    expect(texts, contains('w/bar'));
    expect(page.items.whereType<GlyphItem>().map((g) => g.name), containsAll(['ornamentTrill', 'arrowheadBlackUp']));
    // Gespeichert
    final back = ScriviFormat.decode(ScriviFormat.encode(e.score));
    final b0 = back.tracks[0].bars[0].voices[0].beats;
    expect(b0[0].notes.single.harmonicType, 1);
    expect(b0[0].notes.single.trill, 2);
    expect(b0[0].fade, 1);
    expect(b0[1].arpeggio, 1);
    expect(b0[1].whammy, -1);
    // Klang
    final plan = PlaybackPlan.build(e.score);
    final notes = plan.tracks[0].notes;
    final first = notes.where((n) => n.start < 1.19).toList();
    expect(first.map((n) => n.midi).toSet().length, 2); // Triller: Hauptton und oberer Ton
    expect(first.first.midi, e.score.tracks[0].bars[0].voices[0].beats[0].notes.single.pitch.midi + 12); // A.H.
    expect(first.first.fade, 1);
    final chord = notes.where((n) => n.start >= 1.19).toList()..sort((a, b) => a.start.compareTo(b.start));
    expect(chord.length, 3);
    expect(chord[1].start - chord[0].start, closeTo(0.06, 1e-9));
    expect(chord.first.midi, lessThan(chord.last.midi)); // aufwärts: tiefster zuerst
    expect(chord.every((n) => n.slideOut == -1 || n.slideOut == 0), isTrue);
    expect(chord.any((n) => n.bend.isNotEmpty), isTrue); // Hebel als kurzes Hinunter und Zurück
  });

  test('Copyright bekommt das ©-Zeichen von selbst', () {
    expect(const ScoreInfo(copyright: '2026 Muster').copyrightLine, '© 2026 Muster');
    expect(const ScoreInfo(copyright: '© 2026 Muster').copyrightLine, '© 2026 Muster');
    expect(const ScoreInfo(copyright: 'Copyright 2026').copyrightLine, 'Copyright 2026');
    expect(const ScoreInfo().copyrightLine, '');
  });

  test('Paket 3: Fingersätze, Saitennummer, Pedal', () {
    final e = ScoreEditor(ScoreEditor.newScore(bars: 2));
    e.duration = const NoteDuration(NoteValue.quarter);
    e.cursor = const EditCursor(string: 3);
    e.inputFret(2);
    e.setFinger(left: 2);
    e.setFinger(right: 2);
    e.toggleTechnique(Technique.stringNumber);
    var n = e.currentBeat!.notes.single;
    expect((n.leftFinger, n.rightFinger, n.stringNumber), (2, 2, true));
    expect(e.fingerAtCursor(), 2);
    final g = _glyphs(e.score);
    expect(g, containsAll(['fingering2', 'fingeringILower', 'fingering3'])); // ③ = Saite 3 von oben
    e.setFinger(left: 2); // nochmals = weg
    expect(e.currentBeat!.notes.single.leftFinger, 0);
    e.setFinger(left: 5);
    expect(_glyphs(e.score), contains('fingeringTUpper'));
    n = ScriviFormat.decode(ScriviFormat.encode(e.score)).tracks[0].bars[0].voices[0].beats[0].notes[0];
    expect((n.leftFinger, n.rightFinger, n.stringNumber), (5, 2, true));

    // Pedal: Töne klingen bis zum Loslassen (Melodie ohne Saiten)
    final m = ScoreEditor(ScoreEditor.newScore(kind: NewPieceKind.leadSheet, bars: 2));
    m.duration = const NoteDuration(NoteValue.quarter);
    m.inputStep(0);
    m.moveBeat(-1);
    m.setPedal(1);
    m.moveBeat(1);
    m.inputStep(2);
    m.moveBeat(1);
    m.setPedal(2);
    expect(_glyphs(m.score), containsAll(['keyboardPedalPed', 'keyboardPedalUp']));
    final notes = PlaybackPlan.build(m.score).tracks.first.notes;
    final quarter = PlaybackPlan.build(m.score).bars.first.duration / 4;
    final first = notes.firstWhere((p) => p.start < 0.01);
    final second = notes.firstWhere((p) => (p.start - quarter).abs() < 0.01);
    expect(first.duration, greaterThan(quarter * 1.5)); // klingt über den eigenen Schlag hinaus
    expect(first.end, closeTo(second.end, 0.01)); // beide bis zum Loslassen
    expect(ScriviFormat.decode(ScriviFormat.encode(m.score)).tracks[0].bars[0].voices[0].beats[0].pedal, 1);
  });

  test('Layout: Elemente verschieben, Anfasser mit Anker', () {
    final e = ScoreEditor(ScoreEditor.newScore(kind: NewPieceKind.leadSheet, title: 'Lied', bars: 2));
    e.setChordLine('G | C');
    LayoutHandle find(String key) => Engraver(e.score).layout().pages.first.handles.firstWhere((h) => h.ref.key == key);
    final title = find('title');
    final chord = find('chord');
    expect(chord.label, contains('G'));
    // Akkord hängt an seiner Note über der obersten Linie
    expect(chord.bottom, lessThan(chord.anchorY));
    e.setNudge(chord.ref, const Nudge(1, -2));
    final moved = find('chord');
    expect(moved.left, closeTo(chord.left + 1, 0.01));
    expect(moved.top, closeTo(chord.top - 2, 0.01));
    e.setNudge(title.ref, const Nudge(0, 3));
    expect(find('title').top, closeTo(title.top + 3, 0.01));
    // In der Datei und zurück
    final back = ScriviFormat.decode(ScriviFormat.encode(e.score));
    expect(back.nudges['title'], const Nudge(0, 3));
    expect(back.tracks[0].bars[0].voices[0].beats[0].nudges['chord'], const Nudge(1, -2));
    e.undo();
    expect(e.nudgeOf(title.ref), Nudge.zero);
    e.resetAllNudges();
    expect(e.nudgeOf(chord.ref), Nudge.zero);
  });

  test('Seite einrichten: Papier, Notengrösse, Takte pro Zeile, Nummern', () {
    final e = ScoreEditor(ScoreEditor.newScore(kind: NewPieceKind.leadSheet, title: 'Seite', bars: 24));
    final normal = Engraver(e.score).layout().pages;
    expect(normal.first.width, closeTo(120, 0.01));
    e.setPageSetup(e.score.pageSetup.copyWith(landscape: true));
    expect(Engraver(e.score).layout().pages.first.width, closeTo(297 / 1.75, 0.01));
    e.setPageSetup(e.score.pageSetup.copyWith(landscape: false, spaceMm: 2.5), joinUndo: true);
    final big = Engraver(e.score).layout().pages;
    expect(big.first.width, closeTo(84, 0.01)); // grössere Noten: weniger Linienabstände pro Seite
    expect(big.first.spaceMm, 2.5);
    e.setPageSetup(PageSetup.standard.copyWith(barsPerLine: 3, barNumbers: 2, pageNumbers: 3));
    final pages = Engraver(e.score).layout().pages;
    for (final sys in pages.expand((p) => p.systems)) {
      expect(sys.lastBar - sys.firstBar + 1, lessThanOrEqualTo(3));
    }
    expect(pages.first.systems.first.lastBar, 2);
    final texts = pages.expand((p) => p.items).whereType<TextItem>().map((t) => t.text).toSet();
    expect(texts, containsAll(['2', '3', '4'])); // jede Taktnummer
    expect(texts.any((t) => t.contains(' / ')), isFalse); // keine Seitenzahlen
    final back = ScriviFormat.decode(ScriviFormat.encode(e.score)).pageSetup;
    expect((back.barsPerLine, back.barNumbers, back.pageNumbers), (3, 2, 3));
    // Ein Schritt rückgängig: Querformat und Notengrösse zusammen
    e.undo();
    e.undo();
    expect(e.score.pageSetup.isStandard, isTrue);
  });
}
