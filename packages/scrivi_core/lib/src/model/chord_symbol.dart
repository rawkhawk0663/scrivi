/// Akkordsymbole: Namen zerlegen und nach den Einstellungen des Stücks schreiben.
library;

/// Wie Akkordsymbole im Stück geschrieben werden (gehört zum Stück, steht in der Datei).
class ChordStyle {
  const ChordStyle({
    this.minor = 'm',
    this.major7 = 'maj7',
    this.plusMinus = false,
    this.raised = false,
    this.parentheses = false,
    this.upperWords = false,
    this.showSus4 = true,
    this.symbols = false,
    this.dimSeven = true,
    this.rootNames = 0,
    this.diagrams = true,
  });

  /// Moll: „m“, „mi“, „min“ oder „-“.
  final String minor;

  /// Grosse Septime: „maj7“, „ma7“, „M7“, „Δ7“ oder „Δ“.
  final String major7;

  /// Veränderte Töne mit + und − statt ♯ und ♭ (C7+5, C7−9).
  final bool plusMinus;

  /// Zusätze (7, 9, sus4, ♭9 …) klein und hochgestellt.
  final bool raised;

  /// Veränderte Töne in Klammern: C7(♭9).
  final bool parentheses;

  /// SUS, ADD, NO statt sus, add, no.
  final bool upperWords;

  /// „sus4“ statt nur „sus“.
  final bool showSus4;

  /// Zeichen statt Wörter: + ° ø statt aug, dim, m7♭5.
  final bool symbols;

  /// Bei vermindert und halbvermindert die 7 zeigen (C°7, Cø7).
  final bool dimSeven;

  /// Namen der Grundtöne: 0 nach der Sprache, 1 immer international (B), 2 immer deutsch (H).
  final int rootNames;

  /// Griffbilder oben auf der ersten Seite.
  final bool diagrams;

  static const standard = ChordStyle();

  bool get isStandard => toJson().isEmpty;

  ChordStyle copyWith({
    String? minor,
    String? major7,
    bool? plusMinus,
    bool? raised,
    bool? parentheses,
    bool? upperWords,
    bool? showSus4,
    bool? symbols,
    bool? dimSeven,
    int? rootNames,
    bool? diagrams,
  }) => ChordStyle(
    minor: minor ?? this.minor,
    major7: major7 ?? this.major7,
    plusMinus: plusMinus ?? this.plusMinus,
    raised: raised ?? this.raised,
    parentheses: parentheses ?? this.parentheses,
    upperWords: upperWords ?? this.upperWords,
    showSus4: showSus4 ?? this.showSus4,
    symbols: symbols ?? this.symbols,
    dimSeven: dimSeven ?? this.dimSeven,
    rootNames: rootNames ?? this.rootNames,
    diagrams: diagrams ?? this.diagrams,
  );

  static const minors = ['m', 'mi', 'min', '-'];
  static const major7s = ['maj7', 'ma7', 'M7', 'Δ7', 'Δ'];

  /// Nur was vom Grundwert abweicht (für die Datei).
  Map<String, dynamic> toJson() => {
    if (minor != 'm') 'minor': minor,
    if (major7 != 'maj7') 'major7': major7,
    if (plusMinus) 'plusMinus': true,
    if (raised) 'raised': true,
    if (parentheses) 'parentheses': true,
    if (upperWords) 'upperWords': true,
    if (!showSus4) 'showSus4': false,
    if (symbols) 'symbols': true,
    if (!dimSeven) 'dimSeven': false,
    if (rootNames != 0) 'rootNames': rootNames,
    if (!diagrams) 'diagrams': false,
  };

  static ChordStyle fromJson(Object? j) {
    if (j is! Map) return standard;
    String pick(Object? v, List<String> allowed, String fallback) => allowed.contains(v) ? v as String : fallback;
    bool flag(Object? v, bool fallback) => v is bool ? v : fallback;
    final r = j['rootNames'];
    return ChordStyle(
      minor: pick(j['minor'], minors, 'm'),
      major7: pick(j['major7'], major7s, 'maj7'),
      plusMinus: flag(j['plusMinus'], false),
      raised: flag(j['raised'], false),
      parentheses: flag(j['parentheses'], false),
      upperWords: flag(j['upperWords'], false),
      showSus4: flag(j['showSus4'], true),
      symbols: flag(j['symbols'], false),
      dimSeven: flag(j['dimSeven'], true),
      rootNames: r is int && r >= 0 && r <= 2 ? r : 0,
      diagrams: flag(j['diagrams'], true),
    );
  }
}

/// Ein Stück eines geschriebenen Akkordsymbols; [raised] = klein und hochgestellt.
class ChordPart {
  const ChordPart(this.text, {this.raised = false});
  final String text;
  final bool raised;

  @override
  String toString() => raised ? '^$text' : text;
}

/// Ein zerlegter Akkordname.
class ChordSymbol {
  ChordSymbol._(this.root, this.rootAcc, this.bass, this.bassAcc);

  /// Grundton als Buchstabe (C … B) und Vorzeichen (−1, 0, 1).
  final String root;
  final int rootAcc;
  final String? bass;
  final int bassAcc;

  bool minor = false;
  bool major7 = false;

  /// 0 = Dur/Moll, sonst 'dim', 'aug', 'half' (halbvermindert), 'power' (C5).
  String kind = '';

  /// Höchste Stufe ('', '6', '7', '9', '11', '13', '69').
  String ext = '';
  String sus = '';
  final adds = <String>[];
  final omits = <String>[];

  /// Veränderte Töne: (−1 oder +1, Stufe).
  final alts = <(int, String)>[];

  /// Zerlegt [name]; null, wenn er nicht verstanden wird (dann bleibt er, wie er ist).
  static ChordSymbol? parse(String name) {
    final s = name.trim().replaceAll('♯', '#').replaceAll('♭', 'b').replaceAll('−', '-').replaceAll(' ', '');
    final m = RegExp(r'^([A-H])([#b]?)(.*?)(?:/([A-H])([#b]?))?$').firstMatch(s);
    if (m == null) return null;
    int acc(String? a) => a == '#' ? 1 : (a == 'b' ? -1 : 0);
    var root = m[1]!, rootAcc = acc(m[2]);
    if (root == 'H') root = 'B';
    var bass = m[4];
    if (bass == 'H') bass = 'B';
    final c = ChordSymbol._(root, rootAcc, bass, acc(m[5]));
    if (!c._suffix(m[3]!)) return null;
    return c;
  }

  /// Liest den Teil nach dem Grundton. Unbekanntes → false.
  bool _suffix(String input) {
    var s = input.replaceAll('(', '').replaceAll(')', '').replaceAll(',', '');
    bool take(String p) {
      if (!s.startsWith(p)) return false;
      s = s.substring(p.length);
      return true;
    }

    bool takeI(String p) {
      if (s.length < p.length || s.substring(0, p.length).toLowerCase() != p) return false;
      s = s.substring(p.length);
      return true;
    }

    String? number() {
      final n = RegExp(r'^(69|6/9|13|11|9|7|6|5|4|2)').firstMatch(s);
      if (n == null) return null;
      s = s.substring(n[0]!.length);
      return n[0]!.replaceAll('/', '');
    }

    // Art
    if (take('ø')) {
      kind = 'half';
      take('7');
    } else if (take('°') || take('o') || takeI('dim')) {
      kind = 'dim';
      if (take('7')) ext = '7';
    } else if (take('+') || takeI('aug')) {
      kind = 'aug';
    } else if (s.startsWith('maj') ||
        s.startsWith('Maj') ||
        s.startsWith('MAJ') ||
        s.startsWith('ma') ||
        s.startsWith('Δ') ||
        s.startsWith('^') ||
        RegExp(r'^M(?!i)').hasMatch(s)) {
      // Grosse Septime (ohne Zahl: maj = maj7)
      take('maj') || take('Maj') || take('MAJ') || take('ma') || take('Δ') || take('^') || take('M');
      major7 = true;
      ext = number() ?? '7';
      if (ext == '6' || ext == '69') {
        // „M6“ gibt es nicht als grosse Septime: dann nur Dur
        major7 = false;
      }
    } else if (takeI('min') || takeI('mi') || take('m') || take('-')) {
      minor = true;
      if (take('maj') || take('Maj') || take('ma') || take('Δ') || take('M')) {
        major7 = true;
        ext = number() ?? '7';
      }
    }
    if (kind == '' && !major7 && ext.isEmpty) {
      final n = number();
      if (n == '5' && !minor) {
        kind = 'power';
      } else if (n == '2' || n == '4') {
        sus = n!; // C2 = Csus2, C4 = Csus4
      } else if (n != null) {
        ext = n;
      }
    }
    if (kind == 'aug' && ext.isEmpty) ext = number() ?? '';
    if (kind == 'dim' && ext.isEmpty && take('7')) ext = '7';
    // m7b5 = halbvermindert
    if (minor && ext == '7' && (s.startsWith('b5') || s.startsWith('-5'))) {
      s = s.substring(2);
      minor = false;
      kind = 'half';
      ext = '';
    }
    while (s.isNotEmpty) {
      if (takeI('sus')) {
        final n = number();
        sus = n == '2' ? '2' : '4';
      } else if (takeI('add')) {
        final n = number();
        if (n == null) return false;
        adds.add(n);
      } else if (takeI('omit') || takeI('no')) {
        final n = number();
        if (n == null) return false;
        omits.add(n);
      } else if (s.startsWith('#') || s.startsWith('b') || s.startsWith('+') || s.startsWith('-')) {
        final dir = s[0] == '#' || s[0] == '+' ? 1 : -1;
        s = s.substring(1);
        final n = number();
        if (n == null) return false;
        if (n == '5' && dir == 1 && kind == '' && !minor && alts.isEmpty) {
          // C7#5 = übermässig mit Septime
          kind = 'aug';
          continue;
        }
        alts.add((dir, n));
      } else if (takeI('alt')) {
        alts.add((0, 'alt'));
      } else {
        final n = number();
        if (n == null) return false;
        if (ext.isEmpty || ext == '7') {
          ext = n;
        } else {
          adds.add(n);
        }
      }
    }
    return true;
  }

  String _note(String letter, int a, bool german) {
    // Deutsch: H statt B, B statt B♭
    if (german && letter == 'B') return a == -1 ? 'B' : (a == 1 ? 'H♯' : 'H');
    return '$letter${a == 1 ? '♯' : (a == -1 ? '♭' : '')}';
  }

  /// Teile zum Zeichnen: der Grundton in voller Grösse, der Rest nach [style].
  List<ChordPart> parts(ChordStyle style, {bool germanNames = false}) {
    final german = style.rootNames == 2 || (style.rootNames == 0 && germanNames);
    final out = <ChordPart>[ChordPart(_note(root, rootAcc, german))];
    final word = style.upperWords ? (String w) => w.toUpperCase() : (String w) => w;
    // Art und Septime auf der Grundlinie bzw. hochgestellt
    var base = '';
    final high = <String>[];
    switch (kind) {
      case 'power':
        high.add('5');
      case 'dim':
        base = style.symbols ? '°' : word('dim');
        if (ext == '7' && (style.dimSeven || !style.symbols)) high.add('7');
      case 'half':
        if (style.symbols) {
          base = 'ø';
          if (style.dimSeven) high.add('7');
        } else {
          base = style.minor == '-' ? '−' : style.minor;
          high.addAll(['7', style.plusMinus ? '−5' : '♭5']);
        }
      case 'aug':
        base = style.symbols ? '+' : word('aug');
        if (ext.isNotEmpty) high.add(ext);
      default:
        if (minor) base = style.minor == '-' ? '−' : style.minor;
        if (major7) {
          final m7 = style.major7;
          final symbol = m7.startsWith('Δ');
          final word7 = symbol ? 'Δ' : m7.replaceAll('7', '');
          final number = ext == '7' ? (m7 == 'Δ' ? '' : '7') : ext;
          // Moll mit grosser Septime: das Septim-Zeichen in Klammern, damit es nicht wie zwei Akkorde aussieht
          high.add(minor ? '($word7$number)' : '$word7$number');
        } else if (ext.isNotEmpty) {
          high.add(ext == '69' ? '6/9' : ext);
        }
    }
    if (sus.isNotEmpty) high.add(word('sus') + (sus == '2' || style.showSus4 ? sus : ''));
    for (final a in adds) {
      high.add('${word('add')}$a');
    }
    final alt = <String>[
      for (final (d, n) in alts)
        if (d == 0) 'alt' else '${d > 0 ? (style.plusMinus ? '+' : '♯') : (style.plusMinus ? '−' : '♭')}$n',
    ];
    for (final o in omits) {
      high.add('${word('no')}$o');
    }
    if (alt.isNotEmpty) high.add(style.parentheses ? '(${alt.join(',')})' : alt.join());
    if (base.isNotEmpty) out.add(ChordPart(base, raised: style.raised && (base == '°' || base == 'ø' || base == '+')));
    final rest = high.join();
    if (rest.isNotEmpty) out.add(ChordPart(rest, raised: style.raised));
    if (bass != null) out.add(ChordPart('/${_note(bass!, bassAcc, german)}'));
    // Benachbarte Teile gleicher Lage zusammenfassen
    final merged = <ChordPart>[];
    for (final p in out) {
      if (merged.isNotEmpty && merged.last.raised == p.raised) {
        merged[merged.length - 1] = ChordPart(merged.last.text + p.text, raised: p.raised);
      } else {
        merged.add(p);
      }
    }
    return merged;
  }

  /// Akkordname nach [style] in Teilen; nicht verstandene Namen bleiben, wie sie sind
  /// (nur ♯/♭ werden schön gesetzt).
  static List<ChordPart> format(String name, ChordStyle style, {bool germanNames = false}) {
    final c = parse(name);
    if (c != null) return c.parts(style, germanNames: germanNames);
    return [ChordPart(name.replaceAll('#', '♯').replaceAllMapped(RegExp(r'([A-G])b'), (m) => '${m[1]}♭'))];
  }
}
