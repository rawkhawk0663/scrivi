part of 'engraver.dart';

/// Ein gemeinsamer Platz für einen Zeitpunkt im Takt: Was in allen Spuren
/// gleichzeitig erklingt, steht genau übereinander.
class _Slot {
  _Slot(this.onset);
  final Fraction onset;
  double accW = 0;
  double minW = 1.6;
  double spring = 0;
  double x = 0;
  double get natural => accW + math.max(spring, minW);
}

/// Setzt mehrere Spuren als Partitur: alle Spuren einer Zeile untereinander,
/// mit gemeinsamen Takten und Schlägen, links die Namen der Instrumente.
///
/// Jede Spur wird von ihrem eigenen [Engraver] vorbereitet und gezeichnet; die
/// Partitur legt nur fest, wo Takte und Schläge stehen, und stapelt die Zeilen.
class ScoreEngraver {
  ScoreEngraver(
    this.score, {
    this.tracks,
    LayoutOptions options = const LayoutOptions(),
    TextMeasurer measurer = const ApproxTextMeasurer(),
  }) : options = options.withPage(score.pageSetup),
       measurer = FontMeasurer.of(measurer, score.pageSetup.fonts);

  final Score score;

  /// Gezeigte Spuren (null = alle), von oben nach unten.
  final List<int>? tracks;
  final LayoutOptions options;
  final TextMeasurer measurer;

  /// Abstand zwischen den Spuren einer Zeile.
  static const staffGap = 2.0;

  /// Abstand zwischen zwei Zeilen der Partitur (grösser als bei einer Spur).
  double get systemGap => options.systemGap * 5 / 3;

  static const _nameSize = 1.35;

  late final List<Engraver> _engs;
  final _slots = <List<_Slot>>[];
  final _padL = <double>[];
  final _padR = <double>[];
  final _changeW = <double>[];

  ScoreLayout layout() {
    final idx = tracks ?? [for (var i = 0; i < score.tracks.length; i++) i];
    final opts = LayoutOptions(
      showTab: options.showTab,
      showNotation: options.showNotation,
      tabLineSpacing: options.tabLineSpacing,
      useLayoutHint: false,
      showChordDiagrams: false,
      germanNoteNames: options.germanNoteNames,
      transposed: options.transposed,
    );
    if (idx.length <= 1 || score.masterBars.isEmpty) {
      return Engraver(score, trackIndex: idx.isEmpty ? 0 : idx.first, options: opts, measurer: measurer).layout();
    }
    _engs = [
      for (var k = 0; k < idx.length; k++)
        Engraver(score, trackIndex: idx[k], options: opts, measurer: measurer)
          .._inScore = true
          .._topStaff = k == 0,
    ];
    for (final e in _engs) {
      e._build();
    }
    _shareSlots();
    final systems = _breakSystems();
    return _paginate(systems);
  }

  // ───────────────────────── Gemeinsame Schläge ─────────────────────────

  void _shareSlots() {
    final e0 = _engs.first;
    for (var i = 0; i < score.masterBars.length; i++) {
      final ms = [for (final e in _engs) e._measures[i]];
      final onsets = <Fraction>{
        for (final m in ms)
          for (final c in m.cols) c.onset,
      }.toList()..sort((a, b) => a.compareTo(b));
      final end = ms.first.mb.time.length;
      final slots = <_Slot>[];
      for (var k = 0; k < onsets.length; k++) {
        final slot = _Slot(onsets[k]);
        final next = k + 1 < onsets.length ? onsets[k + 1] : end;
        var delta = next - onsets[k];
        if (delta <= Fraction.zero) delta = Fraction(1, 16);
        slot.spring = e0._springFor(delta);
        for (final m in ms) {
          for (final c in m.cols) {
            if (c.onset != onsets[k]) continue;
            slot.accW = math.max(slot.accW, c.accW);
            slot.minW = math.max(slot.minW, c.minW);
          }
        }
        slots.add(slot);
      }
      _slots.add(slots);
      _padL.add(ms.map((m) => m.padL).reduce(math.max));
      _padR.add(ms.map((m) => m.padR).reduce(math.max));
      var change = 0.0;
      for (var k = 0; k < ms.length; k++) {
        final e = _engs[k], m = ms[k];
        final w =
            (m.keyChange ? e._keyWidth(e._keyOf(m.mb)) + 0.4 : 0.0) + (m.timeChange ? e._timeWidth(m.mb.time) : 0.0);
        change = math.max(change, w);
      }
      _changeW.add(change);
    }
  }

  double _slotSum(int i) => _slots[i].fold(0.0, (s, c) => s + c.natural) + (_slots[i].isEmpty ? 6 : 0);

  double _natural(int i, bool atStart) => _padL[i] + _padR[i] + _slotSum(i) + (atStart ? 0 : _changeW[i]);

  double _header(int i, bool first) => [for (final e in _engs) e._headerWidth(e._measures[i], first)].reduce(math.max);

  // ───────────────────────── Namen der Instrumente ─────────────────────────

  String _name(Engraver e, bool first) {
    final n = e._track.name.trim();
    return first ? n : _short(n);
  }

  double _namesWidth(bool first) {
    var w = 0.0;
    for (final e in _engs) {
      w = math.max(w, measurer.width(_name(e, first), TextRole.credit, _nameSize));
    }
    // Platz für die Klammern links der Zeile
    final braces = _engs.any((e) => _braceBase(e._track) != null);
    return w > 0 ? w + 1.6 + (braces ? 2.6 : 0.8) : 0;
  }

  // ───────────────────────── Zeilen ─────────────────────────

  List<(int, int, bool)> _breakSystems() {
    final out = <(int, int, bool)>[];
    final n = score.masterBars.length;
    var i = 0;
    while (i < n) {
      final first = out.isEmpty;
      final avail = options.contentWidth - _namesWidth(first);
      var w = _header(i, first);
      var count = 0;
      final fixed = options.barsPerLine;
      final mbs = score.masterBars;
      while (i + count < n) {
        final add = _natural(i + count, count == 0);
        final keep = count > 0 && mbs[i + count - 1].breakAfter == -1;
        // Feste Zahl Takte pro Zeile, solange sie Platz haben
        if (fixed > 0 && count >= fixed && !keep) break;
        if (count > 0 && w + add > avail && !keep) break;
        w += add;
        count++;
        if (mbs[i + count - 1].breakAfter >= 1) break; // neue Zeile von Hand
      }
      out.add((i, i + count, first));
      i += count;
    }
    return out;
  }

  /// Takte und Schläge einer Zeile verteilen (Blocksatz) und allen Spuren mitgeben.
  List<_System> _justify(int from, int to, bool first, bool last) {
    final names = _namesWidth(first);
    final x0 = options.marginLeft + names;
    final avail = options.contentWidth - names;
    final header = _header(from, first);
    var fixed = header, springs = 0.0;
    for (var i = from; i < to; i++) {
      final nat = _natural(i, i == from);
      final cs = _slotSum(i);
      fixed += nat - cs;
      springs += cs;
    }
    var factor = springs > 0 ? (avail - fixed) / springs : 1.0;
    if (last && factor > 1.6) factor = 1.3;
    if (factor < 0.5) factor = 0.5;
    final mx = <double>[], mw = <double>[];
    var x = x0 + header;
    for (var i = from; i < to; i++) {
      final start = i == from ? x0 : x;
      var cx = x + _padL[i] + (i == from ? 0 : _changeW[i]);
      for (final slot in _slots[i]) {
        slot.x = cx + slot.accW;
        cx += slot.natural * factor;
      }
      if (_slots[i].isEmpty) cx += 6 * factor;
      cx += _padR[i];
      mx.add(start);
      mw.add(cx - start);
      x = cx;
    }
    final x1 = last && factor == 1.3 ? x : x0 + avail;
    mw[mw.length - 1] = x1 - mx.last;
    return [
      for (final e in _engs)
        () {
          final ms = e._measures.sublist(from, to);
          for (var j = 0; j < ms.length; j++) {
            final m = ms[j];
            m.x = mx[j];
            m.w = mw[j];
            m.changeW = j > 0 ? _changeW[from + j] : 0;
            final slots = {for (final sl in _slots[from + j]) sl.onset: sl};
            for (final c in m.cols) {
              c.x = slots[c.onset]!.x;
            }
          }
          return _System(ms)
            ..header = header
            ..first = first
            ..x0 = x0
            ..x1 = x1;
        }(),
    ];
  }

  // ───────────────────────── Seiten ─────────────────────────

  ScoreLayout _paginate(List<(int, int, bool)> ranges) {
    final e0 = _engs.first;
    final pages = <PageDisplay>[];
    var page = PageDisplay(
      options.pageWidth,
      options.pageHeight,
      spaceMm: options.spaceMm,
      fonts: score.pageSetup.fonts,
    );
    pages.add(page);
    var y = e0._drawHeader(page, options.marginTop);
    final perTrack = [for (final _ in _engs) <_System>[]];
    final all = <List<_System>>[];
    for (var r = 0; r < ranges.length; r++) {
      final (from, to, first) = ranges[r];
      final systems = _justify(from, to, first, r == ranges.length - 1);
      all.add(systems);
      for (var k = 0; k < _engs.length; k++) {
        perTrack[k].add(systems[k]);
      }
    }
    final prevKeys = [for (final _ in _engs) const KeySignature(0)];
    var firstOnPage = true;
    final placed = <_Placed>[];
    for (var r = 0; r < all.length; r++) {
      // Welche Spuren in dieser Zeile stehen (leere auf Wunsch weg, nie in der ersten Zeile)
      final vis = [
        for (var k = 0; k < _engs.length; k++)
          if (!score.pageSetup.hideEmpty || r == 0 || _hasNotes(_engs[k], all[r][k])) k,
      ];
      if (vis.isEmpty) vis.add(0);
      // Formteile, Tempo, Häuser, Sprünge und Taktnummern über der obersten gezeigten Spur
      for (var k = 0; k < _engs.length; k++) {
        _engs[k]._topStaff = k == vis.first;
      }
      // Alle Spuren dieser Zeile zeichnen
      final outs = <int, ({List<DisplayItem> items, double top, double bottom})>{};
      final builders = <int, _SystemBuilder>{};
      for (var k = 0; k < _engs.length; k++) {
        final sb = _SystemBuilder(_engs[k], all[r][k], r, perTrack[k]);
        final out = sb.build(prevKeys[k]);
        prevKeys[k] = _engs[k]._keyOf(all[r][k].measures.last.mb);
        if (!vis.contains(k)) continue;
        outs[k] = out;
        builders[k] = sb;
      }
      var height = 0.0;
      for (final k in vis) {
        height += outs[k]!.bottom - outs[k]!.top + (k != vis.first ? staffGap : 0);
      }
      var top = firstOnPage ? y : y + systemGap;
      final pageBreak = r > 0 && all[r - 1].first.measures.last.mb.breakAfter == 2;
      if ((top + height > options.pageHeight - options.marginBottom || pageBreak) && !firstOnPage) {
        page = PageDisplay(
          options.pageWidth,
          options.pageHeight,
          spaceMm: options.spaceMm,
          fonts: score.pageSetup.fonts,
        );
        pages.add(page);
        top = options.marginTop;
      }
      final s0 = all[r].first;
      placed.add(_Placed(page, page.items.length, page.handles.length, page.breakMarks.length, page.systems.length));
      top = e0._systemNudge(page, s0, top, height, x0: options.marginLeft);
      var cursor = top;
      // Lage der Linien jeder gezeigten Spur (für Namen und Klammern)
      final lines = <int, (double, double)>{};
      for (final k in vis) {
        final e = _engs[k], out = outs[k]!, sb = builders[k]!, s = all[r][k];
        if (k != vis.first) cursor += staffGap;
        final dy = cursor - out.top;
        for (final it in out.items) {
          page.items.add(shift(it, 0, dy));
        }
        for (final hd in sb.handles) {
          page.handles.add(hd.shifted(0, dy));
        }
        final h = out.bottom - out.top;
        page.systems.add(e._box(s, sb, cursor, h, out.top));
        final staffTop = e._tabOnly ? sb._tabTop : 0.0;
        final staffBottom = e._tab ? sb._tabBottom : 4.0;
        lines[k] = (staffTop + dy, staffBottom + dy);
        cursor += h;
      }
      _drawGroups(page, vis, lines, s0.x0, s0.first);
      y = cursor;
      placed.last.bottom = y;
      firstOnPage = false;
    }
    if (score.pageSetup.fillPages) e0._fillPages(placed);
    e0._drawCopyright(pages.first);
    e0._pageNumbers(pages);
    return ScoreLayout(pages);
  }

  /// Hat die Spur in dieser Zeile etwas zu spielen?
  static bool _hasNotes(Engraver e, _System s) => s.measures.any(
    (m) =>
        m.index < e._track.bars.length &&
        e._track.bars[m.index].voices.any((v) => v.beats.any((b) => b.notes.isNotEmpty)),
  );

  static final _partOf = RegExp(r'^(.*) \((\d+)\)$');

  /// Mehrere Notenzeilen eines Instruments („Klavier (1)“, „Klavier (2)“): gemeinsamer Name.
  static String? _braceBase(Track t) => _partOf.firstMatch(t.name.trim())?.group(1);

  /// Familie für die eckige Klammer: Tasten, Gitarren und Bass, Streicher, Bläser
  /// (Schlagzeug und Unbekanntes stehen allein).
  static String? _family(Track t) {
    if (t.percussion) return null;
    final p = t.program;
    if (p < 0) return t.staff.isStringed ? 'guitar' : null;
    if (p < 24) return 'keys';
    if (p < 40) return 'guitar';
    if (p < 56) return 'strings';
    if (p < 80) return 'winds';
    return null;
  }

  /// Linke Seite einer Zeile: Linie über alle Spuren, eckige Klammern um Familien, geschweifte
  /// um die Notenzeilen eines Instruments, Namen links davon.
  void _drawGroups(PageDisplay page, List<int> vis, Map<int, (double, double)> lines, double x0, bool first) {
    final lt = lines[vis.first]!.$1, lb = lines[vis.last]!.$2;
    page.items.add(LineItem(x0, lt - _staffLineT / 2, x0, lb + _staffLineT / 2, _thinT));
    // Läufe gleicher Gruppen
    List<List<int>> runs(String? Function(Track) key) {
      final out = <List<int>>[];
      for (final k in vis) {
        final g = key(_engs[k]._track);
        if (g != null && out.isNotEmpty && key(_engs[out.last.last]._track) == g) {
          out.last.add(k);
        } else {
          out.add([k]);
        }
      }
      return out;
    }

    final braces = runs(_braceBase).where((r) => r.length > 1).toList();
    final braced = {for (final r in braces) ...r};
    // Eckige Klammern um Familien mit mehreren Spuren (ein Klavier allein bekommt nur die geschweifte);
    // gibt es keine solche Familie, eine Klammer über alle
    final brackets = [
      for (final run in runs(_family))
        if (run.length > 1 && !braces.any((b) => b.length == run.length && b.first == run.first)) run,
    ];
    if (brackets.isEmpty && vis.length > 1 && braces.every((b) => b.length < vis.length)) brackets.add(vis);
    const bracketX = -0.55;
    for (final run in brackets) {
      _bracket(page, x0 + bracketX, lines[run.first]!.$1, lines[run.last]!.$2);
    }
    // Geschweifte Klammern links der eckigen
    final braceX = x0 - (brackets.isEmpty ? 0.5 : 1.9);
    for (final run in braces) {
      _brace(page, braceX, lines[run.first]!.$1, lines[run.last]!.$2);
    }
    // Namen links, auf der Höhe der Linien (bei geschweifter Klammer einmal in der Mitte)
    final nameRight = braces.isNotEmpty ? braceX - 1.6 : (brackets.isEmpty ? x0 - 1.0 : x0 - 1.8);
    void name(String t, double mid) {
      if (t.isEmpty) return;
      page.items.add(
        TextItem(t, nameRight, mid + _nameSize * 0.35, TextRole.credit, _nameSize, align: TextAlign.right),
      );
    }

    for (final run in braces) {
      final base = _braceBase(_engs[run.first]._track)!;
      name(first ? base : _short(base), (lines[run.first]!.$1 + lines[run.last]!.$2) / 2);
    }
    for (final k in vis) {
      if (braced.contains(k)) continue;
      name(_name(_engs[k], first), (lines[k]!.$1 + lines[k]!.$2) / 2);
    }
  }

  /// Eckige Klammer: dicker Strich mit Haken oben und unten.
  void _bracket(PageDisplay page, double x, double top, double bottom) {
    const t = 0.5;
    page.items.add(LineItem(x - t / 2, top - 0.25, x - t / 2, bottom + 0.25, t));
    page.items.add(GlyphItem('bracketTop', x - t, top - 0.25));
    page.items.add(GlyphItem('bracketBottom', x - t, bottom + 0.25));
  }

  /// Geschweifte Klammer, nur in der Höhe gestreckt.
  void _brace(PageDisplay page, double x, double top, double bottom) {
    final g = Glyphs.get('brace');
    final sy = (bottom - top) / (g.top - g.bottom);
    const sx = 3.2;
    final c = g.path;
    final out = <double>[];
    var i = 0;
    while (i < c.length) {
      final op = c[i].toInt();
      out.add(op.toDouble());
      final n = switch (op) {
        0 || 1 => 1,
        3 => 3,
        _ => 0,
      };
      for (var j = 0; j < n; j++) {
        out
          ..add(x - g.right * sx + c[i + 1 + j * 2] * sx)
          ..add(bottom - (c[i + 2 + j * 2] - g.bottom) * sy);
      }
      i += 1 + n * 2;
    }
    page.items.add(PathItem(out));
  }

  /// Kurzform ab der zweiten Zeile: erstes Wort gekürzt, der Rest bleibt („Viol. 1“).
  String _short(String n) {
    if (n.length <= 6) return n;
    final parts = n.split(' ');
    final w = parts.first;
    return [w.length > 5 ? '${w.substring(0, 4)}.' : w, ...parts.skip(1)].join(' ');
  }
}
