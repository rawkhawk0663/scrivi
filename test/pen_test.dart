import 'package:flutter_test/flutter_test.dart';
import 'package:scrivi/features/score/pen_gestures.dart';

List<Offset> _line(Offset a, Offset b, [int n = 20]) => [for (var i = 0; i <= n; i++) Offset.lerp(a, b, i / n)!];

void main() {
  test('Stift: antippen, Strich, Kritzeln, nach oben und unten', () {
    expect(classifyStroke([const Offset(100, 100), const Offset(102, 101)]), PenStroke.tap);
    expect(classifyStroke(_line(const Offset(100, 100), const Offset(260, 108))), PenStroke.line);
    expect(classifyStroke(_line(const Offset(100, 100), const Offset(104, 60))), PenStroke.flickUp);
    expect(classifyStroke(_line(const Offset(100, 100), const Offset(97, 140))), PenStroke.flickDown);
    // hin und her: erst nach rechts, dann zurück …
    final scribble = <Offset>[];
    for (var i = 0; i < 6; i++) {
      final from = Offset(i.isEven ? 100 : 160, 100.0 + i * 3);
      final to = Offset(i.isEven ? 160 : 100, 103.0 + i * 3);
      scribble.addAll(_line(from, to, 6));
    }
    expect(classifyStroke(scribble), PenStroke.scribble);
    // Zittern beim Strich ist kein Kritzeln
    final shaky = [for (var i = 0; i <= 40; i++) Offset(100 + i * 4 + (i.isEven ? 2 : -2), 100)];
    expect(classifyStroke(shaky), PenStroke.line);
    // Schräg und weder waagrecht noch senkrecht: nichts
    expect(classifyStroke(_line(const Offset(100, 100), const Offset(130, 140))), PenStroke.none);
  });
}
