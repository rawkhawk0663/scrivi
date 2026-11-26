import 'dart:math' as math;
import 'dart:typed_data';

import 'package:scrivi_core/scrivi_core.dart';
import 'package:test/test.dart';

/// Stück mit [bars] Takten 4/4, je eine ganze Note (Takt k: MIDI 60 + k).
Score _score(
  int bars, {
  Map<int, MasterBar Function(MasterBar)> change = const {},
  double bpm = 120,
  List<Beat> Function(int bar)? beats,
  List<int> tuning = const [],
}) {
  const ts = TimeSignature(4, 4);
  const key = KeySignature(0);
  final mbs = [for (var i = 0; i < bars; i++) (change[i] ?? (m) => m)(MasterBar(time: ts, key: key))];
  final track = Track(
    name: 'Test',
    staff: StaffDef(tuning: tuning),
    bars: [
      for (var i = 0; i < bars; i++)
        Bar(
          clef: Clef.treble,
          voices: [
            Voice(
              beats?.call(i) ??
                  [
                    Beat(
                      duration: const NoteDuration(NoteValue.whole),
                      notes: [Note(pitch: Pitch.fromMidi(60 + i))],
                    ),
                  ],
            ),
          ],
        ),
    ],
  );
  return Score(
    info: const ScoreInfo(),
    masterBars: mbs,
    tracks: [track],
    tempos: [TempoMark(bar: 0, bpm: bpm)],
  );
}

MasterBar _with(
  MasterBar m, {
  bool repeatStart = false,
  int repeatEnd = 0,
  Set<int>? endings,
  Set<Direction>? directions,
}) => MasterBar(
  time: m.time,
  key: m.key,
  repeatStart: repeatStart,
  repeatEnd: repeatEnd,
  endings: endings,
  directions: directions,
);

/// Grundfrequenz über Autokorrelation (genau mit Zwischenwert).
double _pitch(Float32List s, int from, int len, double want) {
  double ac(int lag) {
    var v = 0.0;
    for (var i = from; i < from + len; i++) {
      v += s[i] * s[i + lag];
    }
    return v;
  }

  final p = Synth.rate / want;
  var best = 0;
  var bestV = -double.infinity;
  for (var lag = (p * 0.75).floor(); lag <= (p * 1.3).ceil(); lag++) {
    final v = ac(lag);
    if (v > bestV) {
      bestV = v;
      best = lag;
    }
  }
  final a = ac(best - 1), b = bestV, c = ac(best + 1);
  return Synth.rate / (best + (a - c) / (2 * (a - 2 * b + c)));
}

double _hz(int midi) => 440 * math.pow(2, (midi - 69) / 12).toDouble();

void main() {
  group('Abspiel-Reihenfolge', () {
    test('ohne Wiederholungen', () {
      expect(PlaybackPlan.playOrder(_score(3)), [0, 1, 2]);
    });

    test('Wiederholung mit Häusern', () {
      final s = _score(
        5,
        change: {
          1: (m) => _with(m, repeatStart: true),
          2: (m) => _with(m, endings: {1}, repeatEnd: 2),
          3: (m) => _with(m, endings: {2}),
        },
      );
      expect(PlaybackPlan.playOrder(s), [0, 1, 2, 1, 3, 4]);
    });

    test('dreimal wiederholen, ohne Anfangszeichen ab Beginn', () {
      final s = _score(3, change: {1: (m) => _with(m, repeatEnd: 3)});
      expect(PlaybackPlan.playOrder(s), [0, 1, 0, 1, 0, 1, 2]);
    });

    test('D.C. al Fine: ohne Wiederholung bis Fine', () {
      final s = _score(
        4,
        change: {
          0: (m) => _with(m, repeatStart: true),
          1: (m) => _with(m, repeatEnd: 2, directions: {Direction.fine}),
          3: (m) => _with(m, directions: {Direction.daCapoAlFine}),
        },
      );
      expect(PlaybackPlan.playOrder(s), [0, 1, 0, 1, 2, 3, 0, 1]);
    });

    test('D.S. al Coda', () {
      final s = _score(
        6,
        change: {
          1: (m) => _with(m, directions: {Direction.segno}),
          2: (m) => _with(m, directions: {Direction.toCoda}),
          3: (m) => _with(m, directions: {Direction.dalSegnoAlCoda}),
          5: (m) => _with(m, directions: {Direction.coda}),
        },
      );
      expect(PlaybackPlan.playOrder(s), [0, 1, 2, 3, 1, 2, 5]);
    });
  });

  group('Zeiten und Töne', () {
    test('Tempo: ein 4/4-Takt bei 120 dauert 2 Sekunden', () {
      final plan = PlaybackPlan.build(_score(3));
      expect(plan.duration, closeTo(6, 1e-9));
      expect(plan.bars[1].start, closeTo(2, 1e-9));
      expect(PlaybackPlan.build(_score(3), tempoFactor: 0.5).duration, closeTo(12, 1e-9));
    });

    test('Stelle zur Zeit und zurück', () {
      final plan = PlaybackPlan.build(_score(3));
      final (bar, pos) = plan.locate(3.0);
      expect(bar, 1);
      expect(pos, closeTo(0.5, 1e-9));
      expect(plan.bars[plan.barAt(5.9)].bar, 2);
    });

    test('Tempowechsel', () {
      final s = _score(2);
      s.tempos.add(const TempoMark(bar: 1, bpm: 60));
      final plan = PlaybackPlan.build(s);
      expect(plan.bars[1].duration, closeTo(4, 1e-9));
    });

    test('Haltebogen verlängert den Ton', () {
      final s = _score(
        2,
        beats: (i) => [
          Beat(
            duration: const NoteDuration(NoteValue.whole),
            notes: [Note(pitch: Pitch.fromMidi(64), tieOrigin: i == 0, tieDestination: i == 1)],
          ),
        ],
      );
      final notes = PlaybackPlan.build(s).tracks.single.notes;
      expect(notes, hasLength(1));
      expect(notes.single.duration, closeTo(4, 1e-9));
    });

    test('Metronom und Einzähler', () {
      final plan = PlaybackPlan.build(_score(2));
      expect(plan.clicks, hasLength(8));
      expect(plan.clicks.first.accent, isTrue);
      expect(plan.clicks[1].time, closeTo(0.5, 1e-9));
      final count = plan.countIn(plan.bars.first);
      expect(count, hasLength(4));
      expect(count.first.time, closeTo(-2, 1e-9));
    });

    test('Wiederholte Takte erklingen zweimal', () {
      final s = _score(2, change: {0: (m) => _with(m, repeatStart: true, repeatEnd: 2)});
      final notes = PlaybackPlan.build(s).tracks.single.notes;
      expect(notes.map((n) => n.midi), [60, 60, 61]);
    });
  });

  group('Klang', () {
    final guitar = Track(
      name: 'Gitarre',
      staff: const StaffDef(tuning: [40, 45, 50, 55, 59, 64]),
      bars: [],
    );

    test('Saite und Klavier treffen die Tonhöhe', () {
      for (final midi in [40, 52, 64]) {
        for (final v in [Voicing.guitar, Voicing.piano]) {
          final pcm = Synth.renderTrack(
            PlayTrack(0, guitar, [PlayNote(start: 0, duration: 1, midi: midi)]),
            1.2,
            voicing: v,
          );
          final f = _pitch(pcm, 4410, 4000, _hz(midi));
          // höchstens 8 Cent daneben (Klavier: leicht gestreckte Obertöne)
          expect((1200 * math.log(f / _hz(midi)) / math.ln2).abs(), lessThan(8), reason: '$v $midi');
        }
      }
    });

    test('Saitenziehen hebt den Ton', () {
      final n = PlayNote(start: 0, duration: 1, midi: 64, bend: const [(0, 0), (0.4, 2), (1, 2)]);
      final pcm = Synth.renderTrack(PlayTrack(0, guitar, [n]), 1.2, voicing: Voicing.guitar);
      final end = _pitch(pcm, 30000, 3000, _hz(66));
      expect((1200 * math.log(end / _hz(66)) / math.ln2).abs(), lessThan(10));
    });

    test('Klangfarbe nach Spur', () {
      expect(Synth.voicingFor(PlayTrack(0, guitar, const [])), Voicing.guitar);
      final bass = Track(
        name: 'Bass',
        staff: const StaffDef(tuning: [28, 33, 38, 43]),
        bars: [],
      );
      expect(Synth.voicingFor(PlayTrack(0, bass, const [])), Voicing.bass);
      final od = Track(
        name: 'E',
        staff: const StaffDef(tuning: [40]),
        bars: [],
        program: 29,
      );
      expect(Synth.voicingFor(PlayTrack(0, od, const [])), Voicing.overdrive);
    });

    test('ganzes Stück: hörbar, ohne Übersteuerung, WAV', () {
      final plan = PlaybackPlan.build(_score(2, tuning: const [40, 45, 50, 55, 59, 64]));
      final pcm = Synth.renderTrack(plan.tracks.single, plan.duration + 1);
      final peak = pcm.fold(0.0, (m, x) => math.max(m, x.abs()));
      expect(peak, greaterThan(0.05));
      expect(peak, lessThanOrEqualTo(1.0));
      final wav = Synth.wav(pcm);
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(wav.length, 44 + pcm.length * 2);
      final clicks = Synth.renderClicks(plan.clicks, plan.duration);
      expect(clicks.any((x) => x.abs() > 0.3), isTrue);
    });
  });
}
