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
}
