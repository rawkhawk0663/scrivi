import 'score.dart';

/// Eingebaute Griffbilder für Gitarre in Normalstimmung (E A D G H E).
///
/// Für Akkorde ohne Griffbild in der Datei: zuerst die üblichen offenen Griffe,
/// sonst ein Barré-Griff (Grundton auf der tiefen E- oder der A-Saite).
class ChordLibrary {
  ChordLibrary._();

  /// Normalstimmung, tiefste Saite zuerst (MIDI).
  static const standardTuning = [40, 45, 50, 55, 59, 64];

  /// Griffbild für [name] oder null, wenn der Name unbekannt ist.
  /// Nur für sechs Saiten in Normalstimmung.
  static ChordDiagram? lookup(String name, List<int> tuning) {
    if (tuning.length != 6) return null;
    for (var i = 0; i < 6; i++) {
      if (tuning[i] != standardTuning[i]) return null;
    }
    final c = parse(name);
    if (c == null) return null;
    final key = '${_rootNames[c.root]}${c.quality}${c.bass == null ? '' : '/${_rootNames[c.bass!]}'}';
    final open = _open[key];
    if (open != null) return _diagram(open);
    if (c.bass != null) {
      // Bassnote ohne bekannten Griff: nur, wenn sie ohnehin der Grundton ist.
      if (c.bass != c.root) return null;
    }
    return _barre(c.root, c.quality);
  }

  /// Zerlegt einen Akkordnamen in Grundton (0 = C), Art und Bassnote.
  /// Gibt null zurück, wenn die Art nicht bekannt ist.
  static ({int root, String quality, int? bass})? parse(String name) {
    var s = name.trim().replaceAll('♯', '#').replaceAll('♭', 'b').replaceAll(' ', '');
    if (s.isEmpty) return null;
    int? bass;
    final slash = s.indexOf('/');
    if (slash > 0) {
      final b = _note(s.substring(slash + 1));
      if (b == null || b.$2 != s.length - slash - 1) return null;
      bass = b.$1;
      s = s.substring(0, slash);
    }
    final r = _note(s);
    if (r == null) return null;
    final quality = _qualities[s.substring(r.$2)];
    if (quality == null) return null;
    return (root: r.$1, quality: quality, bass: bass == r.$1 ? null : bass);
  }

  /// Notenname am Anfang von [s]: (Tonklasse, Länge).
  static (int, int)? _note(String s) {
    if (s.isEmpty) return null;
    final base = switch (s[0]) {
      'C' => 0,
      'D' => 2,
      'E' => 4,
      'F' => 5,
      'G' => 7,
      'A' => 9,
      'B' || 'H' => 11,
      _ => null,
    };
    if (base == null) return null;
    if (s.length > 1 && s[1] == '#') return ((base + 1) % 12, 2);
    if (s.length > 1 && s[1] == 'b') return ((base + 11) % 12, 2);
    return (base, 1);
  }

  static const _rootNames = ['C', 'C#', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B'];

  /// Schreibweisen der Akkordarten → einheitlicher Name.
  static const _qualities = {
    '': '',
    'maj': '',
    'M': '',
    'm': 'm',
    'min': 'm',
    '-': 'm',
    '7': '7',
    'm7': 'm7',
    'min7': 'm7',
    '-7': 'm7',
    'maj7': 'maj7',
    'M7': 'maj7',
    'Maj7': 'maj7',
    'ma7': 'maj7',
    'Δ': 'maj7',
    'Δ7': 'maj7',
    'sus4': 'sus4',
    'sus': 'sus4',
    'sus2': 'sus2',
    '5': '5',
    'add9': 'add9',
    '2': 'add9',
    '7sus4': '7sus4',
  };

  /// Offene Griffe: Bünde von der tiefen E-Saite an, x = nicht gespielt.
  static const _open = {
    'C': 'x32010',
    'C7': 'x32310',
    'Cmaj7': 'x32000',
    'Cadd9': 'x32030',
    'Csus2': 'x30013',
    'Csus4': 'x33011',
    'C/E': '032010',
    'C/G': '332010',
    'C/B': 'x22010',
    'D': 'xx0232',
    'Dm': 'xx0231',
    'D7': 'xx0212',
    'Dm7': 'xx0211',
    'Dmaj7': 'xx0222',
    'Dsus2': 'xx0230',
    'Dsus4': 'xx0233',
    'D5': 'xx023x',
    'Dadd9': 'xx0230',
    'D/F#': '2x0232',
    'D/A': 'x00232',
    'D/C': 'x30232',
    'E': '022100',
    'Em': '022000',
    'E7': '020100',
    'Em7': '022030',
    'Emaj7': '021100',
    'Esus4': '022200',
    'E5': '022xxx',
    'E7sus4': '020200',
    'Em/D': 'xx0000',
    'Em/G': '3x2000',
    'Em/B': 'x22000',
    'E/G#': '4x2100',
    'F': '133211',
    'Fmaj7': 'xx3210',
    'F/A': 'x03211',
    'F/C': 'x33211',
    'G': '320003',
    'G7': '320001',
    'Gmaj7': '320002',
    'Gsus4': '3x0013',
    'Gadd9': '300003',
    'G5': '355xxx',
    'G/B': 'x20003',
    'G/D': 'xx0003',
    'G/F#': '2x0003',
    'A': 'x02220',
    'Am': 'x02210',
    'A7': 'x02020',
    'Am7': 'x02010',
    'Amaj7': 'x02120',
    'Asus2': 'x02200',
    'Asus4': 'x02230',
    'A5': 'x022xx',
    'A7sus4': 'x02030',
    'Aadd9': 'x02420',
    'A/C#': 'x42220',
    'A/E': '002220',
    'Am/G': '3x2210',
    'Am/C': 'x32210',
    'Am/E': '002210',
    'B7': 'x21202',
  };

  /// Barré-Formen: Abstand zum Barré-Bund pro Saite, −1 = nicht gespielt.
  static const _eShape = {
    '': [0, 2, 2, 1, 0, 0],
    'm': [0, 2, 2, 0, 0, 0],
    '7': [0, 2, 0, 1, 0, 0],
    'm7': [0, 2, 0, 0, 0, 0],
    'sus4': [0, 2, 2, 2, 0, 0],
    '5': [0, 2, 2, -1, -1, -1],
    '7sus4': [0, 2, 0, 2, 0, 0],
  };
  static const _aShape = {
    '': [-1, 0, 2, 2, 2, 0],
    'm': [-1, 0, 2, 2, 1, 0],
    '7': [-1, 0, 2, 0, 2, 0],
    'm7': [-1, 0, 2, 0, 1, 0],
    'maj7': [-1, 0, 2, 1, 2, 0],
    'sus4': [-1, 0, 2, 2, 3, 0],
    'sus2': [-1, 0, 2, 2, 0, 0],
    '5': [-1, 0, 2, 2, -1, -1],
    'add9': [-1, 0, 2, 4, 2, 0],
    '7sus4': [-1, 0, 2, 0, 3, 0],
  };

  static ChordDiagram? _barre(int root, String quality) {
    final e = _eShape[quality], a = _aShape[quality];
    // Barré-Bund mit Grundton auf der tiefen E- (Ton 4) bzw. A-Saite (Ton 9)
    var fe = (root - 4) % 12, fa = (root - 9) % 12;
    if (fe == 0) fe = 12;
    if (fa == 0) fa = 12;
    List<int> shape;
    int fret;
    if (e != null && (a == null || fe <= fa)) {
      shape = e;
      fret = fe;
    } else if (a != null) {
      shape = a;
      fret = fa;
    } else {
      return null;
    }
    final frets = [for (final d in shape) d < 0 ? -1 : fret + d];
    final first = shape.indexWhere((d) => d == 0);
    final last = shape.lastIndexWhere((d) => d == 0);
    return ChordDiagram(
      stringCount: 6,
      baseFret: 0,
      frets: frets,
      barres: last > first ? [ChordBarre(fret: fret, from: first, to: last)] : const [],
    );
  }

  static ChordDiagram _diagram(String s) {
    final frets = [for (final ch in s.split('')) ch == 'x' ? -1 : int.parse(ch)];
    final barres = <ChordBarre>[];
    // Barré, wenn der tiefste gegriffene Bund auf der tiefsten und der höchsten Saite liegt (z. B. F).
    final played = [
      for (var i = 0; i < 6; i++)
        if (frets[i] > 0) i,
    ];
    if (played.length >= 4) {
      final minF = played.map((i) => frets[i]).reduce((a, b) => a < b ? a : b);
      final at = played.where((i) => frets[i] == minF).toList();
      if (at.length >= 2 && at.first == played.first && at.last == 5) {
        barres.add(ChordBarre(fret: minF, from: at.first, to: at.last));
      }
    }
    return ChordDiagram(stringCount: 6, baseFret: 0, frets: frets, barres: barres);
  }
}
