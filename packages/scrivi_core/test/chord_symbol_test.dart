import 'package:scrivi_core/scrivi_core.dart';
import 'package:test/test.dart';

String _f(String name, [ChordStyle style = ChordStyle.standard, bool german = false]) =>
    ChordSymbol.format(name, style, germanNames: german).join();

void main() {
  test('Grundeinstellung: einheitlich und mit ♯/♭', () {
    expect(_f('C'), 'C');
    expect(_f('Am'), 'Am');
    expect(_f('F#m7'), 'F♯m7');
    expect(_f('Bbmaj7'), 'B♭maj7');
    expect(_f('CM7'), 'Cmaj7');
    expect(_f('CΔ'), 'Cmaj7');
    expect(_f('Cmin7'), 'Cm7');
    expect(_f('C-7'), 'Cm7');
    expect(_f('Cm7b5'), 'Cm7♭5');
    expect(_f('Cø'), 'Cm7♭5');
    expect(_f('Cdim7'), 'Cdim7');
    expect(_f('C°'), 'Cdim');
    expect(_f('C+'), 'Caug');
    expect(_f('C7#5'), 'Caug7');
    expect(_f('C7b9'), 'C7♭9');
    expect(_f('C7(#9,b13)'), 'C7♯9♭13');
    expect(_f('Csus'), 'Csus4');
    expect(_f('C7sus4'), 'C7sus4');
    expect(_f('Cadd9'), 'Cadd9');
    expect(_f('C2'), 'Csus2');
    expect(_f('C5'), 'C5');
    expect(_f('C69'), 'C6/9');
    expect(_f('G/B'), 'G/B');
    expect(_f('D/F#'), 'D/F♯');
    expect(_f('CmM7'), 'Cm(maj7)');
    expect(_f('N.C.'), 'N.C.'); // unbekannt: bleibt
  });

  test('Eigene Einstellungen', () {
    const jazz = ChordStyle(
      minor: '-',
      major7: 'Δ',
      plusMinus: true,
      raised: true,
      parentheses: true,
      upperWords: true,
      showSus4: false,
      symbols: true,
      dimSeven: false,
    );
    expect(_f('Am7', jazz), 'A−^7');
    expect(_f('Cmaj7', jazz), 'C^Δ');
    expect(_f('Cmaj9', jazz), 'C^Δ9');
    expect(_f('C7b9', jazz), 'C^7(−9)');
    expect(_f('Csus4', jazz), 'C^SUS');
    expect(_f('Cdim7', jazz), 'C^°');
    expect(_f('Cm7b5', jazz), 'C^ø');
    expect(_f('C+', jazz), 'C^+');
    expect(_f('Cadd9', jazz), 'C^ADD9');
    expect(ChordSymbol.format('C7b9', jazz).map((p) => p.raised).toList(), [false, true]);
  });

  test('Deutsche Namen: H und B', () {
    const de = ChordStyle(rootNames: 2);
    expect(_f('B7', de), 'H7');
    expect(_f('Bbm', de), 'Bm');
    expect(_f('G/B', de), 'G/H');
    expect(_f('B7'), 'B7');
    expect(_f('B7', ChordStyle.standard, true), 'H7'); // nach der Sprache
    expect(_f('B7', const ChordStyle(rootNames: 1), true), 'B7');
  });

  test('In der Datei nur Abweichungen', () {
    expect(ChordStyle.standard.toJson(), isEmpty);
    const s = ChordStyle(minor: 'mi', raised: true, diagrams: false);
    final back = ChordStyle.fromJson(s.toJson());
    expect((back.minor, back.raised, back.diagrams, back.major7), ('mi', true, false, 'maj7'));
  });
}
