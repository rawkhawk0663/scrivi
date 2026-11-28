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
  });

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
    );
  }
}
