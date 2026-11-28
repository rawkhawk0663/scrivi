import 'package:scrivi_core/scrivi_core.dart';
import 'package:test/test.dart';

/// Schlichte Schreibweise (alles auf der Grundlinie, Wörter, keine Klammern).
const _plain = ChordStyle(raised: false, symbols: false, parenAlts: false, parenWords: false, stacked: false);

String _f(String name, [ChordStyle style = _plain, bool german = false]) =>
    ChordSymbol.format(name, style, germanNames: german).join();

void main() {
  test('Namen verstehen und einheitlich schreiben', () {
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

  test('Grundeinstellung: Zahlen hochgestellt, Zeichen, Klammern, übereinander', () {
    String f(String n) => _f(n, ChordStyle.standard);
    expect(f('C7'), 'C^7');
    expect(f('Cm7'), 'Cm^7');
    expect(f('Cmaj7'), 'C^maj7');
    expect(f('CmMaj7'), 'Cm^(maj7)');
    expect(f('Cdim7'), 'C^°7');
    expect(f('Cm7b5'), 'C^ø7');
    expect(f('C+'), 'C^+');
    expect(f('C7b9'), 'C^7(♭9)');
    expect(f('C7(b9,#11)'), 'C^7([♯11|♭9])'); // übereinander, höchste oben
    expect(f('C7sus4'), 'C^7(sus4)');
    expect(f('Csus4'), 'C^sus4');
  });

  test('Alle Wahlmöglichkeiten', () {
    expect(_f('Am', _plain.copyWith(triads: 1)), 'Ami');
    expect(_f('Am', _plain.copyWith(triads: 2)), 'AMI');
    expect(_f('Am', _plain.copyWith(triads: 3)), 'Amin');
    expect(_f('Am', _plain.copyWith(triads: 5)), 'A^m');
    expect(_f('Am', _plain.copyWith(triads: 6)), 'A−');
    expect(_f('Cmaj7', _plain.copyWith(major7: 0)), 'Cma7');
    expect(_f('Cmaj7', _plain.copyWith(major7: 1)), 'CMA7');
    expect(_f('Cmaj7', _plain.copyWith(major7: 3)), 'CM7');
    expect(_f('Cmaj7', _plain.copyWith(major7: 4)), 'C^M7');
    expect(_f('Cmaj7', _plain.copyWith(major7: 5)), 'CΔ');
    expect(_f('Cmaj9', _plain.copyWith(major7: 5)), 'CΔ9');
    expect(_f('Cmaj7', _plain.copyWith(major7: 8)), 'C^Δ7');
    expect(_f('C7b9', _plain.copyWith(plusMinus: true)), 'C7−9');
    expect(_f('C7b9', _plain.copyWith(accAfter: true)), 'C79♭');
    expect(_f('Cb5', _plain), 'C♭5');
    expect(_f('C7b9', _plain.copyWith(parenAlts: true)), 'C7(♭9)');
    expect(_f('C7b9', _plain.copyWith(parenAlts: true, parenMin: 2)), 'C7♭9');
    expect(_f('C7(b9,#11)', _plain.copyWith(stacked: true)), 'C7[♯11|♭9]');
    expect(_f('C7(b9,#11)', _plain.copyWith(stacked: true, invertOrder: true)), 'C7[♭9|♯11]');
    expect(_f('C7sus4', _plain.copyWith(upperWords: true)), 'C7SUS4');
    expect(_f('Csus4', _plain.copyWith(showSus4: false)), 'Csus');
    expect(_f('Cadd9omit3', _plain), 'Cadd9omit3');
    expect(_f('Cadd9omit3', _plain.copyWith(noInsteadOfOmit: true)), 'Cadd9no3');
    expect(_f('Cm7add11', _plain.copyWith(parenWords: true)), 'Cm7(add11)');
    expect(_f('Cdim7', _plain.copyWith(symbols: true, symbolsRaised: false)), 'C°7');
    expect(_f('Cdim7', _plain.copyWith(symbols: true, symbolsRaised: false, dimSeven: false)), 'C°');
    expect(_f('C7#5', _plain.copyWith(symbols: true, symbolsRaised: false)), 'C+7');
    expect(_f('C7#5', _plain.copyWith(symbols: true, symbolsRaised: false, augBefore: false)), 'C7+');
    expect(_f('C7#5', _plain.copyWith(augBefore: false)), 'C7aug');
    expect(_f('Bb7', _plain.copyWith(rootAccRaised: true)), 'B^♭7');
    expect(_f('Cm(maj7)', _plain.copyWith(parenMinMaj7: true)), 'Cm(maj7)');
    expect(_f('Cm(maj7)', _plain.copyWith(triads: 1, parenMinMaj7: true)), 'Cmi(ma7)');
  });

  test('Deutsche Namen: H und B', () {
    final de = _plain.copyWith(rootNames: 2);
    expect(_f('B7', de), 'H7');
    expect(_f('Bbm', de), 'Bm');
    expect(_f('G/B', de), 'G/H');
    expect(_f('B7'), 'B7');
    expect(_f('B7', _plain, true), 'H7'); // nach der Sprache
    expect(_f('B7', _plain.copyWith(rootNames: 1), true), 'B7');
  });

  test('In der Datei nur Abweichungen; frühere Einstellungen werden übernommen', () {
    expect(ChordStyle.standard.toJson(), isEmpty);
    final s = ChordStyle.standard.copyWith(triads: 1, raised: false, diagrams: false, show: 2);
    final back = ChordStyle.fromJson(s.toJson());
    expect((back.triads, back.raised, back.diagrams, back.show, back.major7), (1, false, false, 2, 2));
    final old = ChordStyle.fromJson({'minor': '-', 'major7': 'Δ'});
    expect((old.triads, old.major7), (6, 5));
  });
}
