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
    this.options = const LayoutOptions(),
    this.measurer = const ApproxTextMeasurer(),
  });

  final Score score;

  /// Gezeigte Spuren (null = alle), von oben nach unten.
  final List<int>? tracks;
  final LayoutOptions options;
  final TextMeasurer measurer;

  /// Abstand zwischen den Spuren einer Zeile.
  static const staffGap = 2.0;

  /// Abstand zwischen zwei Zeilen der Partitur.
  static const systemGap = 5.0;

  static const _nameSize = 1.35;

  late final List<Engraver> _engs;
  final _slots = <List<_Slot>>[];
  final _padL = <double>[];
  final _padR = <double>[];
  final _changeW = <double>[];

  ScoreLayout layout() {
    final idx = tracks ?? [for (var i = 0; i < score.tracks.length; i++) i];
    final opts = LayoutOptions(
      pageWidth: options.pageWidth,
      pageHeight: options.pageHeight,
      marginLeft: options.marginLeft,
      marginRight: options.marginRight,
      marginTop: options.marginTop,
      marginBottom: options.marginBottom,
      showTab: options.showTab,
      showNotation: options.showNotation,
      tabLineSpacing: options.tabLineSpacing,
      systemGap: options.systemGap,
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
    if (first || n.length <= 6) return n;
    // Kurzform ab der zweiten Zeile: erstes Wort gekürzt, der Rest bleibt („Viol. 1“)
    final parts = n.split(' ');
    final w = parts.first;
    final short = w.length > 5 ? '${w.substring(0, 4)}.' : w;
    return [short, ...parts.skip(1)].join(' ');
  }

  double _namesWidth(bool first) {
    var w = 0.0;
    for (final e in _engs) {
      w = math.max(w, measurer.width(_name(e, first), TextRole.credit, _nameSize));
    }
    return w > 0 ? w + 1.6 : 0;
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
      while (i + count < n) {
        final add = _natural(i + count, count == 0);
        if (count > 0 && w + add > avail) break;
        w += add;
        count++;
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
    var page = PageDisplay(options.pageWidth, options.pageHeight);
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
    for (var r = 0; r < all.length; r++) {
      // Alle Spuren dieser Zeile zeichnen
      final outs = <({List<DisplayItem> items, double top, double bottom})>[];
      final builders = <_SystemBuilder>[];
      for (var k = 0; k < _engs.length; k++) {
        final sb = _SystemBuilder(_engs[k], all[r][k], r, perTrack[k]);
        outs.add(sb.build(prevKeys[k]));
        builders.add(sb);
        prevKeys[k] = _engs[k]._keyOf(all[r][k].measures.last.mb);
      }
      var height = 0.0;
      for (var k = 0; k < outs.length; k++) {
        height += outs[k].bottom - outs[k].top + (k > 0 ? staffGap : 0);
      }
      var top = firstOnPage ? y : y + systemGap;
      if (top + height > options.pageHeight - options.marginBottom && !firstOnPage) {
        page = PageDisplay(options.pageWidth, options.pageHeight);
        pages.add(page);
        top = options.marginTop;
      }
      final s0 = all[r].first;
      var cursor = top;
      double? lineTop, lineBottom;
      for (var k = 0; k < outs.length; k++) {
        final e = _engs[k], out = outs[k], sb = builders[k], s = all[r][k];
        if (k > 0) cursor += staffGap;
        final dy = cursor - out.top;
        for (final it in out.items) {
          page.items.add(shift(it, 0, dy));
        }
        final h = out.bottom - out.top;
        page.systems.add(e._box(s, sb, cursor, h, out.top));
        // Lage der Linien dieser Spur (Noten bzw. Tabulatur)
        final staffTop = e._tabOnly ? sb._tabTop : 0.0;
        final staffBottom = e._tab ? sb._tabBottom : 4.0;
        lineTop ??= staffTop + dy;
        lineBottom = staffBottom + dy;
        // Name links, auf der Höhe der Linien
        final name = _name(e, s.first);
        if (name.isNotEmpty) {
          page.items.add(
            TextItem(
              name,
              s0.x0 - 1.0,
              (staffTop + staffBottom) / 2 + dy + _nameSize * 0.35,
              TextRole.credit,
              _nameSize,
              align: TextAlign.right,
            ),
          );
        }
        cursor += h;
      }
      // Linie und Klammer links über alle Spuren der Zeile
      final lt = lineTop!, lb = lineBottom!;
      page.items.add(LineItem(s0.x0, lt - _staffLineT / 2, s0.x0, lb + _staffLineT / 2, _thinT));
      page.items.add(LineItem(s0.x0 - 0.55, lt - 0.3, s0.x0 - 0.55, lb + 0.3, _thickT));
      y = cursor;
      firstOnPage = false;
    }
    final cr = score.info.copyright;
    if (cr.isNotEmpty) {
      pages.first.items.add(
        TextItem(
          cr,
          options.pageWidth / 2,
          options.pageHeight - options.marginBottom / 2,
          TextRole.small,
          _smallSize,
          align: TextAlign.center,
        ),
      );
    }
    if (pages.length > 1) {
      for (var p = 0; p < pages.length; p++) {
        pages[p].items.add(
          TextItem(
            '${p + 1} / ${pages.length}',
            options.pageWidth - options.marginRight,
            options.pageHeight - options.marginBottom / 2,
            TextRole.small,
            _smallSize,
            align: TextAlign.right,
          ),
        );
      }
    }
    return ScoreLayout(pages);
  }
}
