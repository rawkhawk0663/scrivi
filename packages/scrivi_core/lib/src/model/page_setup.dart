/// Seite einrichten: Papier, Ränder, Notengrösse und Abstände (gehört zum Stück, steht in der Datei).
library;

class PageSetup {
  const PageSetup({
    this.paper = 'a4',
    this.landscape = false,
    this.marginTop = 14,
    this.marginBottom = 15.75,
    this.marginLeft = 14.875,
    this.marginRight = 14.875,
    this.spaceMm = 1.75,
    this.lineGap = 1.0,
    this.spacing = 1.0,
    this.barsPerLine = 0,
    this.barNumbers = 0,
    this.pageNumbers = 0,
    this.fonts = const {},
    this.fontScales = const {},
    this.hideEmpty = false,
    this.fillPages = false,
  });

  /// Zeilen gleichmässig verteilen, so dass jede volle Seite bis zum unteren Rand reicht
  /// (die letzte Seite bleibt oben).
  final bool fillPages;

  /// Partitur: Spuren, die in einer Zeile nichts zu spielen haben, weglassen (nicht in der ersten Zeile).
  final bool hideEmpty;

  /// Papierformat: 'a4', 'letter' oder 'a3'.
  final String paper;
  final bool landscape;

  /// Ränder in mm.
  final double marginTop, marginBottom, marginLeft, marginRight;

  /// Notengrösse: Abstand zweier Notenlinien in mm (das Notensystem ist viermal so hoch).
  final double spaceMm;

  /// Abstand zwischen den Zeilen (1 = normal).
  final double lineGap;

  /// Wie weit die Noten auseinanderstehen (1 = normal, kleiner = enger).
  final double spacing;

  /// Takte pro Zeile (0 = automatisch).
  final int barsPerLine;

  /// Taktnummern: 0 am Zeilenanfang, 1 alle 5 Takte, 2 bei jedem Takt, 3 keine.
  final int barNumbers;

  /// Seitenzahlen: 0 unten rechts, 1 unten in der Mitte, 2 aussen (abwechselnd), 3 keine.
  final int pageNumbers;

  /// Gewählte Schriften: Gruppe ('title', 'chord', 'lyrics', 'text') → Schrift ('sora', 'plex',
  /// 'garamond', 'kalam'); nur was vom Grundwert abweicht.
  final Map<String, String> fonts;

  /// Grösse der Texte pro Gruppe (1 = normal).
  final Map<String, double> fontScales;

  /// Gruppen, deren Schrift und Grösse man wählen kann.
  static const fontGroups = ['title', 'chord', 'lyrics', 'text'];
  static const fontKeys = ['sora', 'plex', 'garamond', 'kalam'];
  static const _defaultFonts = {'title': 'sora', 'chord': 'sora', 'lyrics': 'plex', 'text': 'plex'};

  /// Schrift einer Gruppe (mit Grundwert).
  String fontOf(String group) => fonts[group] ?? _defaultFonts[group] ?? 'plex';

  /// Grösse einer Gruppe (1 = normal).
  double scaleOf(String group) => fontScales[group] ?? 1.0;

  /// Schrift einer Gruppe setzen (Grundwert fällt aus der Liste).
  PageSetup withFont(String group, String font) => copyWith(
    fonts: {
      for (final e in fonts.entries)
        if (e.key != group) e.key: e.value,
      if (font != _defaultFonts[group]) group: font,
    },
  );

  /// Grösse einer Gruppe setzen.
  PageSetup withScale(String group, double scale) => copyWith(
    fontScales: {
      for (final e in fontScales.entries)
        if (e.key != group) e.key: e.value,
      if ((scale - 1).abs() > 0.001) group: scale,
    },
  );

  static const standard = PageSetup();

  static const papers = {'a4': (210.0, 297.0), 'letter': (215.9, 279.4), 'a3': (297.0, 420.0)};

  /// Breite und Höhe des Papiers in mm.
  (double, double) get paperMm {
    final (w, h) = papers[paper] ?? papers['a4']!;
    return landscape ? (h, w) : (w, h);
  }

  bool get isStandard => toJson().isEmpty;

  PageSetup copyWith({
    String? paper,
    bool? landscape,
    double? marginTop,
    double? marginBottom,
    double? marginLeft,
    double? marginRight,
    double? spaceMm,
    double? lineGap,
    double? spacing,
    int? barsPerLine,
    int? barNumbers,
    int? pageNumbers,
    Map<String, String>? fonts,
    Map<String, double>? fontScales,
    bool? hideEmpty,
    bool? fillPages,
  }) => PageSetup(
    paper: paper ?? this.paper,
    landscape: landscape ?? this.landscape,
    marginTop: marginTop ?? this.marginTop,
    marginBottom: marginBottom ?? this.marginBottom,
    marginLeft: marginLeft ?? this.marginLeft,
    marginRight: marginRight ?? this.marginRight,
    spaceMm: spaceMm ?? this.spaceMm,
    lineGap: lineGap ?? this.lineGap,
    spacing: spacing ?? this.spacing,
    barsPerLine: barsPerLine ?? this.barsPerLine,
    barNumbers: barNumbers ?? this.barNumbers,
    pageNumbers: pageNumbers ?? this.pageNumbers,
    fonts: fonts ?? this.fonts,
    fontScales: fontScales ?? this.fontScales,
    hideEmpty: hideEmpty ?? this.hideEmpty,
    fillPages: fillPages ?? this.fillPages,
  );

  static double _r(double v) => (v * 1000).roundToDouble() / 1000;

  /// Nur was vom Grundwert abweicht.
  Map<String, dynamic> toJson() {
    const d = standard;
    return {
      if (paper != d.paper) 'paper': paper,
      if (landscape) 'landscape': true,
      if (marginTop != d.marginTop) 'marginTop': _r(marginTop),
      if (marginBottom != d.marginBottom) 'marginBottom': _r(marginBottom),
      if (marginLeft != d.marginLeft) 'marginLeft': _r(marginLeft),
      if (marginRight != d.marginRight) 'marginRight': _r(marginRight),
      if (spaceMm != d.spaceMm) 'spaceMm': _r(spaceMm),
      if (lineGap != d.lineGap) 'lineGap': _r(lineGap),
      if (spacing != d.spacing) 'spacing': _r(spacing),
      if (barsPerLine != 0) 'barsPerLine': barsPerLine,
      if (barNumbers != 0) 'barNumbers': barNumbers,
      if (pageNumbers != 0) 'pageNumbers': pageNumbers,
      if (hideEmpty) 'hideEmpty': true,
      if (fillPages) 'fillPages': true,
      if (fonts.isNotEmpty) 'fonts': {...fonts},
      if (fontScales.isNotEmpty) 'fontSizes': {for (final e in fontScales.entries) e.key: _r(e.value)},
    };
  }

  static PageSetup fromJson(Object? j) {
    if (j is! Map) return standard;
    const d = standard;
    double number(String k, double fallback, double min, double max) {
      final v = j[k];
      return v is num ? v.toDouble().clamp(min, max) : fallback;
    }

    int whole(String k, int max) {
      final v = j[k];
      return v is int && v >= 0 && v <= max ? v : 0;
    }

    return PageSetup(
      paper: papers.containsKey(j['paper']) ? j['paper'] as String : d.paper,
      landscape: j['landscape'] == true,
      marginTop: number('marginTop', d.marginTop, 0, 80),
      marginBottom: number('marginBottom', d.marginBottom, 0, 80),
      marginLeft: number('marginLeft', d.marginLeft, 0, 80),
      marginRight: number('marginRight', d.marginRight, 0, 80),
      spaceMm: number('spaceMm', d.spaceMm, 0.8, 4),
      lineGap: number('lineGap', d.lineGap, 0.3, 4),
      spacing: number('spacing', d.spacing, 0.5, 2),
      barsPerLine: whole('barsPerLine', 16),
      barNumbers: whole('barNumbers', 3),
      pageNumbers: whole('pageNumbers', 3),
      hideEmpty: j['hideEmpty'] == true,
      fillPages: j['fillPages'] == true,
      fonts: {
        if (j['fonts'] case final Map f)
          for (final e in f.entries)
            if (fontGroups.contains(e.key) && fontKeys.contains(e.value) && e.value != _defaultFonts[e.key])
              e.key as String: e.value as String,
      },
      fontScales: {
        if (j['fontSizes'] case final Map f)
          for (final e in f.entries)
            if (fontGroups.contains(e.key) && e.value is num && ((e.value as num) - 1).abs() > 0.001)
              e.key as String: (e.value as num).toDouble().clamp(0.5, 2.0),
      },
    );
  }
}
