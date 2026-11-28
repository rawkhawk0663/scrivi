/// Akkordsymbole: Namen zerlegen und nach den Einstellungen des Stücks schreiben.
library;

/// Wie Akkordsymbole im Stück geschrieben werden (gehört zum Stück, steht in der Datei).
class ChordStyle {
  const ChordStyle({
    this.show = 0,
    this.diagramsStringedOnly = true,
    this.diagrams = true,
    this.triads = 0,
    this.major7 = 2,
    this.plusMinus = false,
    this.accAfter = false,
    this.moveAlts = true,
    this.moveAlways = false,
    this.stacked = true,
    this.invertOrder = false,
    this.raised = true,
    this.upperWords = false,
    this.noInsteadOfOmit = false,
    this.showSus4 = true,
    this.symbols = true,
    this.symbolsRaised = true,
    this.dimSeven = true,
    this.augBefore = true,
    this.rootAccRaised = false,
    this.parenAlts = true,
    this.parenMin = 1,
    this.parenWords = true,
    this.parenMinMaj7 = true,
    this.rootNames = 0,
  });

  /// Was über den Noten steht: 0 nur der Name, 1 nur das Griffbild, 2 Name und Griffbild.
  final int show;

  /// Griffbilder über den Noten nur bei Saiteninstrumenten.
  final bool diagramsStringedOnly;

  /// Übersicht der Griffbilder oben auf der ersten Seite.
  final bool diagrams;

  /// Dur/Moll: Index in [triadOptions].
  final int triads;

  /// Grosse Septime: Index in [major7Options].
  final int major7;

  /// Veränderte Töne mit + und − statt ♯ und ♭; [accAfter]: ♯/♭ hinter der Zahl (9♭).
  final bool plusMinus;
  final bool accAfter;

  /// Veränderte Töne ans Ende des Akkords: wenn sie gleich nach dem Grundton kämen bzw. [moveAlways] immer.
  final bool moveAlts;
  final bool moveAlways;

  /// Mehrere veränderte Töne übereinander ([invertOrder]: der tiefste oben) statt nebeneinander.
  final bool stacked;
  final bool invertOrder;

  /// Zahlen und Zusätze (7, 9, sus4, ♭9 …) klein und hochgestellt.
  final bool raised;

  /// SUS, ADD, OMIT statt sus, add, omit; „no“ statt „omit“; „sus4“ statt „sus“.
  final bool upperWords;
  final bool noInsteadOfOmit;
  final bool showSus4;

  /// Zeichen statt Wörter: + ° ø statt aug, dim, m7♭5; [symbolsRaised]: klein und hochgestellt.
  final bool symbols;
  final bool symbolsRaised;

  /// Bei vermindert und halbvermindert die 7 zeigen (C°7, Cø7).
  final bool dimSeven;

  /// Übermässig vor der Zahl (Caug7, C+7) statt danach (C7aug, C7+).
  final bool augBefore;

  /// Vorzeichen des Grundtons hochgestellt.
  final bool rootAccRaised;

  /// Klammern um veränderte Töne/Zusätze ab [parenMin] Stück; um sus/add/omit; um maj7 bei Moll.
  final bool parenAlts;
  final int parenMin;
  final bool parenWords;
  final bool parenMinMaj7;

  /// Namen der Grundtöne: 0 nach der Sprache, 1 immer international (B), 2 immer deutsch (H).
  final int rootNames;

  static const standard = ChordStyle();

  /// Dur/Moll: (Wort für Dur, Wort für Moll, hochgestellt). Dur-Dreiklänge bleiben ohne Zusatz;
  /// das Dur-Wort erscheint nur, wo es nötig ist (Moll mit grosser Septime).
  static const triadOptions = <(String, String, bool)>[
    ('maj', 'm', false), // C / Cm
    ('ma', 'mi', false), // Cma / Cmi
    ('MA', 'MI', false), // CMA / CMI
    ('maj', 'min', false), // Cmaj / Cmin
    ('M', 'm', false), // CM / Cm
    ('M', 'm', true), // CM / Cm hochgestellt
    ('Δ', '−', false), // CΔ / C−
    ('Δ', '−', true), // CΔ / C− hochgestellt
  ];

  /// Grosse Septime: (Text, hochgestellt). Ohne „7“ (CΔ) steht die Zahl nur bei 9, 11, 13.
  static const major7Options = <(String, bool)>[
    ('ma7', false),
    ('MA7', false),
    ('maj7', false),
    ('M7', false),
    ('M7', true),
    ('Δ', false),
    ('Δ', true),
    ('Δ7', false),
    ('Δ7', true),
  ];

  bool get isStandard => toJson().isEmpty;

  ChordStyle copyWith({
    int? show,
    bool? diagramsStringedOnly,
    bool? diagrams,
    int? triads,
    int? major7,
    bool? plusMinus,
    bool? accAfter,
    bool? moveAlts,
    bool? moveAlways,
    bool? stacked,
    bool? invertOrder,
    bool? raised,
    bool? upperWords,
    bool? noInsteadOfOmit,
    bool? showSus4,
    bool? symbols,
    bool? symbolsRaised,
    bool? dimSeven,
    bool? augBefore,
    bool? rootAccRaised,
    bool? parenAlts,
    int? parenMin,
    bool? parenWords,
    bool? parenMinMaj7,
    int? rootNames,
  }) => ChordStyle(
    show: show ?? this.show,
    diagramsStringedOnly: diagramsStringedOnly ?? this.diagramsStringedOnly,
    diagrams: diagrams ?? this.diagrams,
    triads: triads ?? this.triads,
    major7: major7 ?? this.major7,
    plusMinus: plusMinus ?? this.plusMinus,
    accAfter: accAfter ?? this.accAfter,
    moveAlts: moveAlts ?? this.moveAlts,
    moveAlways: moveAlways ?? this.moveAlways,
    stacked: stacked ?? this.stacked,
    invertOrder: invertOrder ?? this.invertOrder,
    raised: raised ?? this.raised,
    upperWords: upperWords ?? this.upperWords,
    noInsteadOfOmit: noInsteadOfOmit ?? this.noInsteadOfOmit,
    showSus4: showSus4 ?? this.showSus4,
    symbols: symbols ?? this.symbols,
    symbolsRaised: symbolsRaised ?? this.symbolsRaised,
    dimSeven: dimSeven ?? this.dimSeven,
    augBefore: augBefore ?? this.augBefore,
    rootAccRaised: rootAccRaised ?? this.rootAccRaised,
    parenAlts: parenAlts ?? this.parenAlts,
    parenMin: parenMin ?? this.parenMin,
    parenWords: parenWords ?? this.parenWords,
    parenMinMaj7: parenMinMaj7 ?? this.parenMinMaj7,
    rootNames: rootNames ?? this.rootNames,
  );

  /// Nur was vom Grundwert abweicht (für die Datei).
  Map<String, dynamic> toJson() {
    const d = standard;
    return {
      if (show != d.show) 'show': show,
      if (diagramsStringedOnly != d.diagramsStringedOnly) 'diagramsStringedOnly': diagramsStringedOnly,
      if (diagrams != d.diagrams) 'diagrams': diagrams,
      if (triads != d.triads) 'triads': triads,
      if (major7 != d.major7) 'major7Style': major7,
      if (plusMinus != d.plusMinus) 'plusMinus': plusMinus,
      if (accAfter != d.accAfter) 'accAfter': accAfter,
      if (moveAlts != d.moveAlts) 'moveAlts': moveAlts,
      if (moveAlways != d.moveAlways) 'moveAlways': moveAlways,
      if (stacked != d.stacked) 'stacked': stacked,
      if (invertOrder != d.invertOrder) 'invertOrder': invertOrder,
      if (raised != d.raised) 'raised': raised,
      if (upperWords != d.upperWords) 'upperWords': upperWords,
      if (noInsteadOfOmit != d.noInsteadOfOmit) 'noInsteadOfOmit': noInsteadOfOmit,
      if (showSus4 != d.showSus4) 'showSus4': showSus4,
      if (symbols != d.symbols) 'symbols': symbols,
      if (symbolsRaised != d.symbolsRaised) 'symbolsRaised': symbolsRaised,
      if (dimSeven != d.dimSeven) 'dimSeven': dimSeven,
      if (augBefore != d.augBefore) 'augBefore': augBefore,
      if (rootAccRaised != d.rootAccRaised) 'rootAccRaised': rootAccRaised,
      if (parenAlts != d.parenAlts) 'parenAlts': parenAlts,
      if (parenMin != d.parenMin) 'parenMin': parenMin,
      if (parenWords != d.parenWords) 'parenWords': parenWords,
      if (parenMinMaj7 != d.parenMinMaj7) 'parenMinMaj7': parenMinMaj7,
      if (rootNames != d.rootNames) 'rootNames': rootNames,
    };
  }

  static ChordStyle fromJson(Object? j) {
    if (j is! Map) return standard;
    const d = standard;
    bool flag(String k, bool fallback) => j[k] is bool ? j[k] as bool : fallback;
    int number(String k, int fallback, int max) {
      final v = j[k];
      return v is int && v >= 0 && v <= max ? v : fallback;
    }

    // Frühere Schreibweise der Einstellungen (Moll und grosse Septime als Text)
    final oldMinor = switch (j['minor']) {
      'mi' => 1,
      'min' => 3,
      '-' => 6,
      _ => null,
    };
    final oldMajor7 = switch (j['major7']) {
      'ma7' => 0,
      'M7' => 3,
      'Δ7' => 7,
      'Δ' => 5,
      _ => null,
    };
    return ChordStyle(
      show: number('show', d.show, 2),
      diagramsStringedOnly: flag('diagramsStringedOnly', d.diagramsStringedOnly),
      diagrams: flag('diagrams', d.diagrams),
      triads: number('triads', oldMinor ?? d.triads, triadOptions.length - 1),
      major7: number('major7Style', oldMajor7 ?? d.major7, major7Options.length - 1),
      plusMinus: flag('plusMinus', d.plusMinus),
      accAfter: flag('accAfter', d.accAfter),
      moveAlts: flag('moveAlts', d.moveAlts),
      moveAlways: flag('moveAlways', d.moveAlways),
      stacked: flag('stacked', d.stacked),
      invertOrder: flag('invertOrder', d.invertOrder),
      raised: flag('raised', d.raised),
      upperWords: flag('upperWords', d.upperWords),
      noInsteadOfOmit: flag('noInsteadOfOmit', d.noInsteadOfOmit),
      showSus4: flag('showSus4', d.showSus4),
      symbols: flag('symbols', d.symbols),
      symbolsRaised: flag('symbolsRaised', d.symbolsRaised),
      dimSeven: flag('dimSeven', d.dimSeven),
      augBefore: flag('augBefore', d.augBefore),
      rootAccRaised: flag('rootAccRaised', d.rootAccRaised),
      parenAlts: flag('parenAlts', d.parenAlts),
      parenMin: number('parenMin', d.parenMin, 9).clamp(1, 9),
      parenWords: flag('parenWords', d.parenWords),
      parenMinMaj7: flag('parenMinMaj7', d.parenMinMaj7),
      rootNames: number('rootNames', d.rootNames, 2),
    );
  }
}

/// Ein Stück eines geschriebenen Akkordsymbols: [raised] = klein und hochgestellt;
/// [stack] = Zeilen übereinander (oberste zuerst); [parens] = hohe Klammern um den Stapel.
class ChordPart {
  const ChordPart(this.text, {this.raised = false, this.stack, this.parens = false});
  final String text;
  final bool raised;
  final List<String>? stack;
  final bool parens;

  @override
  String toString() {
    if (stack != null) return parens ? '([${stack!.join('|')}])' : '[${stack!.join('|')}]';
    return raised ? '^$text' : text;
  }
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
      final n = RegExp(r'^(69|6/9|13|11|9|7|6|5|4|3|2)').firstMatch(s);
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

  /// Teile zum Zeichnen nach [style].
  List<ChordPart> parts(ChordStyle style, {bool germanNames = false}) {
    final german = style.rootNames == 2 || (style.rootNames == 0 && germanNames);
    final out = <ChordPart>[];
    // Steht nach dem Grundton schon etwas? (dann kommen Wörter in Klammern)
    var rootDone = false, suffix = false;
    void put(String t, {bool raised = false}) {
      if (t.isEmpty) return;
      if (rootDone) suffix = true;
      if (out.isNotEmpty && out.last.stack == null && out.last.raised == raised) {
        out[out.length - 1] = ChordPart(out.last.text + t, raised: raised);
      } else {
        out.add(ChordPart(t, raised: raised));
      }
    }

    // Grundton (Vorzeichen auf Wunsch hochgestellt)
    final rootName = _note(root, rootAcc, german);
    if (style.rootAccRaised && rootName.length > 1) {
      put(rootName.substring(0, 1));
      put(rootName.substring(1), raised: true);
    } else {
      put(rootName);
    }
    rootDone = true;
    final hi = style.raised;
    String word(String w) => style.upperWords ? w.toUpperCase() : w;
    final (majorWord, minorWord, triadRaised) = ChordStyle.triadOptions[style.triads];
    final (m7Text, m7Raised) = ChordStyle.major7Options[style.major7];
    final symRaised = style.symbols && style.symbolsRaised;
    // Art und Stufe
    switch (kind) {
      case 'power':
        put('5', raised: hi);
      case 'dim':
        if (style.symbols) {
          put('°', raised: symRaised);
          if (ext == '7' && style.dimSeven) put('7', raised: hi || symRaised);
        } else {
          put(word('dim'));
          if (ext == '7') put('7', raised: hi);
        }
      case 'half':
        if (style.symbols) {
          put('ø', raised: symRaised);
          if (style.dimSeven) put('7', raised: hi || symRaised);
        } else {
          put(minorWord, raised: triadRaised);
          put('7${style.plusMinus ? '−5' : '♭5'}', raised: hi);
        }
      case 'aug':
        final a = style.symbols ? '+' : word('aug');
        final ar = style.symbols ? symRaised : false;
        if (ext.isEmpty) {
          put(a, raised: ar);
        } else if (style.augBefore) {
          put(a, raised: ar);
          put(ext, raised: hi || ar);
        } else {
          put(ext, raised: hi);
          put(a, raised: ar || hi);
        }
      default:
        if (minor) put(minorWord, raised: triadRaised);
        if (major7) {
          // Grosse Septime: mit Zahl, ausser bei „Δ“ ohne 7 (dort nur 9, 11, 13)
          final noSeven = !m7Text.endsWith('7');
          final word7 = noSeven ? m7Text : m7Text.substring(0, m7Text.length - 1);
          final number = ext == '7' ? (noSeven ? '' : '7') : ext;
          var t = '$word7$number';
          // Bei Moll mit grosser Septime das Dur-Wort der Dreiklänge (z. B. „ma“) statt „maj“
          if (minor && !m7Text.startsWith('Δ') && style.triads != 0 && style.triads != 3) {
            t = '$majorWord${number.isEmpty ? '7' : number}';
          }
          if (minor && style.parenMinMaj7) t = '($t)';
          put(t, raised: m7Raised || hi);
        } else if (ext.isNotEmpty) {
          put(ext == '69' ? '6/9' : ext, raised: hi);
        }
    }
    // Veränderte Töne (sortiert nach Stufe)
    String alt((int, String) a) {
      final (d, n) = a;
      if (d == 0) return 'alt';
      final sign = style.plusMinus ? (d > 0 ? '+' : '−') : (d > 0 ? '♯' : '♭');
      return style.accAfter && !style.plusMinus ? '$n$sign' : '$sign$n';
    }

    final sorted = [...alts]..sort((a, b) => (int.tryParse(a.$2) ?? 99).compareTo(int.tryParse(b.$2) ?? 99));
    final altTexts = [for (final a in sorted) alt(a)];
    void putAlts() {
      if (altTexts.isEmpty) return;
      final paren = style.parenAlts && altTexts.length >= style.parenMin;
      if (style.stacked && altTexts.length > 1) {
        // Höchste Stufe oben (umgekehrt: tiefste oben)
        final lines = style.invertOrder ? altTexts : altTexts.reversed.toList();
        out.add(ChordPart('', raised: true, stack: lines, parens: paren));
        suffix = true;
      } else {
        final t = altTexts.join();
        put(paren ? '($t)' : t, raised: hi);
      }
    }

    // Wörter: sus, add, omit/no
    final words = <String>[
      if (sus.isNotEmpty) word('sus') + (sus == '2' || style.showSus4 ? sus : ''),
      for (final a in adds) '${word('add')}$a',
      for (final o in omits) '${word(style.noInsteadOfOmit ? 'no' : 'omit')}$o',
    ];
    void putWords() {
      if (words.isEmpty) return;
      final t = words.join();
      put(style.parenWords && suffix ? '($t)' : t, raised: hi);
    }

    // Veränderte Töne ans Ende: immer, oder wenn sie sonst gleich nach dem Grundton kämen
    final toEnd = style.moveAlts && (style.moveAlways || (ext.isEmpty && kind.isEmpty && !minor));
    if (toEnd) {
      putWords();
      putAlts();
    } else {
      putAlts();
      putWords();
    }
    if (bass != null) put('/${_note(bass!, bassAcc, german)}');
    return out;
  }

  /// Akkordname nach [style] in Teilen; nicht verstandene Namen bleiben, wie sie sind
  /// (nur ♯/♭ werden schön gesetzt).
  static List<ChordPart> format(String name, ChordStyle style, {bool germanNames = false}) {
    final c = parse(name);
    if (c != null) return c.parts(style, germanNames: germanNames);
    return [ChordPart(name.replaceAll('#', '♯').replaceAllMapped(RegExp(r'([A-G])b'), (m) => '${m[1]}♭'))];
  }
}
