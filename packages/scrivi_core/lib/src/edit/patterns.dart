import '../model/score.dart';

/// Ein Begleitmuster für Gitarre (Anschlag oder Zupfmuster), für einen Takt.
///
/// Die Schritte teilen den Takt gleichmässig (bei 8 Schritten im 4/4-Takt
/// also Achtel). Zeichen:
/// - `D` Anschlag abwärts (alle Saiten des Griffs), `U` aufwärts (die hohen Saiten)
/// - `B` Bassnote des Griffs, `A` Wechselbass (nächste gespielte Saite darüber)
/// - `1` höchste gespielte Saite, `2` die zweithöchste, `3`, `4` …
/// - `-` den vorigen Schritt halten, `.` Pause
class StrumPattern {
  const StrumPattern(this.id, this.de, this.en, this.steps, this.time, {this.picked = false});

  /// Kennung (nie übersetzen).
  final String id;
  final String de;
  final String en;
  final String steps;

  /// Taktart, für die das Muster gedacht ist.
  final TimeSignature time;

  /// Zupfmuster (einzelne Saiten) statt Anschlag.
  final bool picked;

  /// Pfeile zum Anzeigen, z. B. „↓ · ↓↑ · ↑↓↑“.
  String get arrows => steps
      .split('')
      .map(
        (c) => switch (c) {
          'D' => '↓',
          'U' => '↑',
          '-' => '·',
          '.' => ' ',
          _ => c,
        },
      )
      .join();

  static const _t44 = TimeSignature(4, 4);
  static const _t34 = TimeSignature(3, 4);
  static const _t68 = TimeSignature(6, 8);

  static const all = [
    StrumPattern('ganze', 'Ganze, klingen lassen', 'Whole note, let ring', 'D-------', _t44),
    StrumPattern('viertel', 'Viertel abwärts', 'Quarters down', 'D-D-D-D-', _t44),
    StrumPattern('achtel', 'Achtel ab und auf', 'Eighths down and up', 'DUDUDUDU', _t44),
    StrumPattern('pop', 'Pop / Folk', 'Pop / folk', 'D-DU-UDU', _t44),
    StrumPattern('rock', 'Rock', 'Rock', 'D-D-DUDU', _t44),
    StrumPattern('boomchick', 'Bass und Schlag', 'Bass and strum', 'B-D-A-D-', _t44),
    StrumPattern('reggae', 'Offbeat', 'Offbeat', '.D.D.D.D', _t44),
    StrumPattern('zupf', 'Zupfmuster auf und ab', 'Picking up and down', 'B3212321', _t44, picked: true),
    StrumPattern('travis', 'Wechselbass mit Melodie', 'Alternating bass picking', 'B1A2B1A2', _t44, picked: true),
    StrumPattern('arpeggio', 'Arpeggio aufwärts', 'Arpeggio upwards', 'B321B321', _t44, picked: true),
    StrumPattern('walzer', 'Walzer', 'Waltz', 'B-D-D-', _t34),
    StrumPattern('zupf34', 'Zupfmuster im Dreiertakt', 'Picking in three', 'B32123', _t34, picked: true),
    StrumPattern('sechsachtel', 'Sechsachtel', 'Six-eight', 'D-UD-U', _t68),
    StrumPattern('zupf68', 'Zupfmuster Sechsachtel', 'Picking in six-eight', 'B32123', _t68, picked: true),
  ];

  /// Muster, die zur Taktart passen (andere gehen auch, werden aber auf den Takt verteilt).
  static List<StrumPattern> forTime(TimeSignature t) {
    final fit = all.where((p) => p.time.beats == t.beats && p.time.beatType == t.beatType).toList();
    return fit.isEmpty ? all.where((p) => p.time == _t44).toList() : fit;
  }

  static StrumPattern? byId(String id) => all.where((p) => p.id == id).firstOrNull;
}
