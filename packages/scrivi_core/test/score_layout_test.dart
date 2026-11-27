import 'dart:convert';
import 'dart:io';

import 'package:scrivi_core/scrivi_core.dart';
import 'package:test/test.dart';

void main() {
  test('Partitur: alle Spuren untereinander, gleiche Schläge übereinander', () {
    final s = ScriviFormat.fromJson(
      jsonDecode(File('../../assets/examples/sonntagmorgen.scrivi').readAsStringSync()) as Map<String, dynamic>,
    );
    final pages = ScoreEngraver(s).layout().pages;
    expect(pages, isNotEmpty);
    final boxes = pages.first.systems;
    // Erste Zeile: eine Box pro Spur, von oben nach unten
    final first = boxes.where((b) => b.firstBar == 0).toList();
    expect(first.map((b) => b.track), [for (var i = 0; i < s.tracks.length; i++) i]);
    for (var k = 1; k < first.length; k++) {
      expect(first[k].top, greaterThan(first[k - 1].top));
      expect(first[k].lastBar, first[0].lastBar);
    }
    // Derselbe Zeitpunkt steht in allen Spuren an derselben Stelle
    for (final b in first.skip(1)) {
      for (var j = 0; j < b.bars.length; j++) {
        expect(b.bars[j].x0, closeTo(first[0].bars[j].x0, 1e-9));
        expect(b.bars[j].x1, closeTo(first[0].bars[j].x1, 1e-9));
        final top = {for (final (onset, x) in first[0].bars[j].beats) onset: x};
        for (final (onset, x) in b.bars[j].beats) {
          if (top.containsKey(onset)) expect(x, closeTo(top[onset]!, 1e-9));
        }
      }
    }
    // Namen der Instrumente stehen links
    final texts = pages.first.items.whereType<TextItem>().map((t) => t.text).toSet();
    for (final t in s.tracks) {
      expect(texts, contains(t.name));
    }
  });

  test('Partitur mit einer Spur = normale Seiten', () {
    final s = ScoreEditor.newScore(bars: 4);
    expect(ScoreEngraver(s).layout().pages.first.systems.first.track, isNull);
  });
}
