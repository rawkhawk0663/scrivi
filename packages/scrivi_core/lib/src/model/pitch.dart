/// Tonhöhe mit Schreibweise: Fis und Ges klingen gleich, sind aber
/// verschiedene Noten. Oktave wie üblich gezählt: c' = C4 = MIDI 60.
class Pitch {
  const Pitch(this.step, this.alter, this.octave);

  /// Stammton: 0 = C, 1 = D, 2 = E, 3 = F, 4 = G, 5 = A, 6 = B (H).
  final int step;

  /// Vorzeichen: -2 Doppel-b, -1 b, 0 keins, 1 Kreuz, 2 Doppelkreuz.
  final int alter;

  final int octave;

  static const _stepSemitones = [0, 2, 4, 5, 7, 9, 11];
  static const _letters = ['C', 'D', 'E', 'F', 'G', 'A', 'B'];

  int get midi => (octave + 1) * 12 + _stepSemitones[step] + alter;

  /// Stammtöne seit C0 gezählt (für die Lage im Notensystem).
  int get diatonic => octave * 7 + step;

  /// Aus Stammton, Vorzeichen und MIDI-Nummer: Die Oktave folgt aus dem Klang.
  /// So ist es egal, wie eine Datei ihre Oktaven zählt.
  factory Pitch.fromMidiSpelled(int midi, int step, int alter) {
    final base = _stepSemitones[step] + alter;
    final octave = ((midi - base) / 12).round() - 1;
    return Pitch(step, alter, octave);
  }

  /// Schreibweise aus der Tonart wählen ([fifths] > 0: Kreuze, < 0: b).
  factory Pitch.fromMidi(int midi, {int fifths = 0}) {
    final pc = midi % 12;
    const sharps = [(0, 0), (0, 1), (1, 0), (1, 1), (2, 0), (3, 0), (3, 1), (4, 0), (4, 1), (5, 0), (5, 1), (6, 0)];
    const flats = [(0, 0), (1, -1), (1, 0), (2, -1), (2, 0), (3, 0), (4, -1), (4, 0), (5, -1), (5, 0), (6, -1), (6, 0)];
    final (step, alter) = (fifths < 0 ? flats : sharps)[pc];
    return Pitch.fromMidiSpelled(midi, step, alter);
  }

  /// Um ganze Oktaven verschoben.
  Pitch octaves(int n) => Pitch(step, alter, octave + n);

  String get letter => _letters[step];

  @override
  bool operator ==(Object other) =>
      other is Pitch && other.step == step && other.alter == alter && other.octave == octave;

  @override
  int get hashCode => Object.hash(step, alter, octave);

  @override
  String toString() {
    const acc = {-2: 'bb', -1: 'b', 0: '', 1: '#', 2: '##'};
    return '$letter${acc[alter]}$octave';
  }
}
