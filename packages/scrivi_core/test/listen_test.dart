import 'dart:typed_data';

import 'package:scrivi_core/scrivi_core.dart';
import 'package:test/test.dart';

/// Hört eine gerechnete Tonspur wie das Mikrofon ab (20 Werte pro Sekunde).
List<int> _listen(Float32List audio, {int rate = 44100, double minFrequency = 70}) {
  final det = PitchDetector(sampleRate: rate, minFrequency: minFrequency);
  final listener = NoteListener();
  final heard = <int>[];
  final hop = rate ~/ 20;
  for (var end = det.windowSize; end <= audio.length; end += hop) {
    final r = det.detect(Float32List.sublistView(audio, end - det.windowSize, end));
    final m = listener.add(r);
    if (m != null) heard.add(m);
  }
  return heard;
}

void main() {
  test('Mikrofon: Töne erkennen, gleicher Ton nach Pause zählt nochmals', () {
    final score = ScoreEditor.newScore(bars: 1);
    final t = score.tracks.first;
    final notes = [
      PlayNote(start: 0.1, duration: 0.5, midi: 40),
      PlayNote(start: 0.9, duration: 0.5, midi: 40),
      PlayNote(start: 1.4, duration: 0.5, midi: 45),
      PlayNote(start: 2.1, duration: 0.6, midi: 64),
    ];
    final audio = Synth.renderTrack(PlayTrack(0, t, notes), 3.0);
    expect(_listen(audio), [40, 40, 45, 64]);
  });

  test('Mikrofon: derselbe Ton zweimal ohne Pause, tiefer Bass', () {
    final t = ScoreEditor.newScore(bars: 1).tracks.first;
    final again = Synth.renderTrack(
      PlayTrack(0, t, [PlayNote(start: 0.1, duration: 0.45, midi: 52), PlayNote(start: 0.55, duration: 0.5, midi: 52)]),
      1.3,
    );
    expect(_listen(again), [52, 52]);
    final bass = ScoreEditor.newScore(bars: 1, kind: NewPieceKind.bass).tracks.first;
    final low = Synth.renderTrack(
      PlayTrack(0, bass, [
        PlayNote(start: 0.1, duration: 0.6, midi: 28),
        PlayNote(start: 0.8, duration: 0.6, midi: 33),
      ]),
      1.6,
    );
    expect(_listen(low, minFrequency: 38), [28, 33]);
  });

  test('Mikrofon: Stille und Rauschen ergeben nichts', () {
    final quiet = Float32List(44100);
    expect(_listen(quiet), isEmpty);
    var seed = 1;
    final noise = Float32List.fromList([
      for (var i = 0; i < 44100; i++) ((seed = (seed * 1103515245 + 12345) & 0x7fffffff) / 0x7fffffff - 0.5) * 0.2,
    ]);
    expect(_listen(noise), isEmpty);
  });

  test('Mikrofon: gehörter Ton an den Cursor, dann weiter', () {
    final e = ScoreEditor(ScoreEditor.newScore(bars: 1));
    e.inputHeard(52);
    e.inputHeard(55);
    final beats = e.beatsOf(0);
    expect(beats[0].notes.single.pitch.midi, 52);
    expect(beats[0].notes.single.fret, isNotNull);
    expect(beats[1].notes.single.pitch.midi, 55);
    expect(e.cursor.beat, 2);
  });
}
