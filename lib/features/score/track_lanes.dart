import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scrivi_core/scrivi_core.dart' as core;

import '../../app/l10n.dart';
import '../../app/theme.dart';
import 'score_player.dart';

/// Farbe einer Spur (in Bahnen, Köpfen und Eigenschaften gleich).
Color trackColor(int i) => const [
  Color(0xFFFF7AC6),
  Color(0xFF9A6BFF),
  Color(0xFF5B8CFF),
  Color(0xFF5FE3E0),
  Color(0xFF6EF0B5),
  Color(0xFFFFC83D),
  Color(0xFFFF9B54),
  Color(0xFFFF6F91),
][i % 8];

/// Spur-Bahnen unten: oben ein Lineal mit Taktnummern, Formteilen und
/// Schleife, darunter pro Spur ein Kopf (Name, Stumm, Solo, Lautstärke) und
/// die Takte als Kästchen mit kleinen Notenstrichen.
///
/// Antippen setzt den Cursor (und wählt die Spur), Ziehen im Lineal legt die
/// Schleife fest, Strg + Mausrad zoomt.
class TrackLanes extends StatefulWidget {
  const TrackLanes({
    super.key,
    required this.editor,
    required this.player,
    required this.cursorTick,
    required this.onSelect,
    required this.onTrackMenu,
    required this.onAddTrack,
    this.maxLanes = 4,
  });

  /// So viele Spuren sind ohne Blättern zu sehen.
  final int maxLanes;

  final core.ScoreEditor editor;
  final ScorePlayer? player;
  final Listenable cursorTick;

  /// Spur, Takt und Stelle im Takt (ganze Noten) angetippt.
  final void Function(int track, int bar, double position) onSelect;

  /// Kopf einer Spur mit rechts bzw. lange gedrückt (Menü an [at]).
  final void Function(int track, Offset at) onTrackMenu;
  final void Function(Offset at) onAddTrack;

  static const laneHeight = 34.0;
  static const rulerHeight = 40.0;
  static const headerWidth = 250.0;

  @override
  State<TrackLanes> createState() => _TrackLanesState();
}

class _TrackLanesState extends State<TrackLanes> {
  final _hLanes = ScrollController();
  final _hRuler = ScrollController();
  final _vLanes = ScrollController();

  /// Pixel pro ganze Note.
  double _zoom = 34;

  /// Während des Ziehens im Lineal: Schleife von–bis.
  (int, int)? _dragLoop;
  int? _dragFrom;

  _Summary? _summary;

  @override
  void initState() {
    super.initState();
    _hLanes.addListener(() {
      if (_hRuler.hasClients) _hRuler.jumpTo(_hLanes.offset.clamp(0, _hRuler.position.maxScrollExtent));
    });
    widget.cursorTick.addListener(_follow);
    widget.player?.position.addListener(_followPlay);
  }

  @override
  void didUpdateWidget(TrackLanes old) {
    super.didUpdateWidget(old);
    if (old.cursorTick != widget.cursorTick) {
      old.cursorTick.removeListener(_follow);
      widget.cursorTick.addListener(_follow);
    }
    if (old.player != widget.player) {
      old.player?.position.removeListener(_followPlay);
      widget.player?.position.addListener(_followPlay);
    }
  }

  @override
  void dispose() {
    widget.cursorTick.removeListener(_follow);
    widget.player?.position.removeListener(_followPlay);
    _hLanes.dispose();
    _hRuler.dispose();
    _vLanes.dispose();
    super.dispose();
  }

  _Summary get _data {
    final e = widget.editor;
    final s = _summary;
    if (s != null && s.revision == e.revision && identical(s.score, e.score) && s.zoom == _zoom) return s;
    return _summary = _Summary.of(e.score, e.revision, _zoom);
  }

  /// Den Cursor sichtbar halten.
  void _follow() {
    if (!mounted) return;
    setState(() {});
    final p = widget.player;
    if (p != null && p.playing) return;
    _reveal(_data.xOf(widget.editor.cursor.bar, widget.editor.cursorOnset.toDouble()));
  }

  void _followPlay() {
    final p = widget.player;
    if (p == null || !p.playing || !mounted) return;
    final (bar, pos) = p.location;
    _reveal(_data.xOf(bar, pos), ahead: true);
  }

  void _reveal(double x, {bool ahead = false}) {
    if (!_hLanes.hasClients) return;
    final pos = _hLanes.position;
    final w = pos.viewportDimension;
    if (x >= pos.pixels + 24 && x <= pos.pixels + w - 48) return;
    final target = (ahead ? x - w * 0.15 : x - w * 0.35).clamp(0.0, pos.maxScrollExtent);
    _hLanes.jumpTo(target);
  }

  void _onWheel(PointerSignalEvent ev) {
    if (ev is! PointerScrollEvent) return;
    GestureBinding.instance.pointerSignalResolver.register(ev, (ev) {
      final e = ev as PointerScrollEvent;
      final hw = HardwareKeyboard.instance;
      if (hw.isControlPressed || hw.isMetaPressed) {
        final factor = e.scrollDelta.dy > 0 ? 1 / 1.15 : 1.15;
        final anchor = _hLanes.hasClients ? (_hLanes.offset + e.localPosition.dx) / _zoom : 0.0;
        setState(() => _zoom = (_zoom * factor).clamp(14.0, 160.0));
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_hLanes.hasClients) {
            _hLanes.jumpTo((anchor * _zoom - e.localPosition.dx).clamp(0.0, _hLanes.position.maxScrollExtent));
          }
        });
        return;
      }
      if (!_hLanes.hasClients) return;
      // Mausrad: waagrecht durch die Takte; mit Umschalt senkrecht durch die Spuren
      if (hw.isShiftPressed && _vLanes.hasClients) {
        _vLanes.jumpTo((_vLanes.offset + e.scrollDelta.dy).clamp(0.0, _vLanes.position.maxScrollExtent));
      } else {
        final d = e.scrollDelta.dx != 0 ? e.scrollDelta.dx : e.scrollDelta.dy;
        _hLanes.jumpTo((_hLanes.offset + d).clamp(0.0, _hLanes.position.maxScrollExtent));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.scrivi;
    final e = widget.editor;
    final d = _data;
    final score = e.score;
    final n = score.tracks.length;
    final p = widget.player;
    final lanesHeight = TrackLanes.laneHeight * n;
    final m = widget.maxLanes;
    final visibleLanes = math.min(n, m) * TrackLanes.laneHeight + (n > m ? TrackLanes.laneHeight / 2 : 0);
    return Container(
      color: c.card,
      height: TrackLanes.rulerHeight + 1 + visibleLanes,
      child: Column(
        children: [
          SizedBox(
            height: TrackLanes.rulerHeight,
            child: Row(
              children: [
                SizedBox(
                  width: TrackLanes.headerWidth,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 12, right: 4),
                    child: Row(
                      children: [
                        Text(
                          tr('Spuren', 'Tracks'),
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: c.muted),
                        ),
                        const Spacer(),
                        Builder(
                          builder: (context) => IconButton(
                            tooltip: tr('Spur hinzufügen', 'Add track'),
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.add_rounded, size: 20),
                            onPressed: () {
                              final box = context.findRenderObject() as RenderBox;
                              widget.onAddTrack(box.localToGlobal(box.size.bottomLeft(Offset.zero)));
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                VerticalDivider(width: 1, thickness: 1, color: c.line),
                Expanded(
                  child: Listener(
                    onPointerSignal: _onWheel,
                    child: SingleChildScrollView(
                      controller: _hRuler,
                      scrollDirection: Axis.horizontal,
                      physics: const NeverScrollableScrollPhysics(),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: (t) {
                          final bar = d.barAt(t.localPosition.dx);
                          widget.onSelect(e.track, bar, 0);
                        },
                        onHorizontalDragStart: (t) {
                          final bar = d.barAt(t.localPosition.dx);
                          setState(() {
                            _dragFrom = bar;
                            _dragLoop = (bar, bar);
                          });
                        },
                        onHorizontalDragUpdate: (t) {
                          final from = _dragFrom;
                          if (from == null) return;
                          final bar = d.barAt(t.localPosition.dx);
                          setState(() => _dragLoop = from <= bar ? (from, bar) : (bar, from));
                        },
                        onHorizontalDragEnd: (_) {
                          final l = _dragLoop;
                          setState(() {
                            _dragLoop = null;
                            _dragFrom = null;
                          });
                          if (l != null) p?.setLoop(l);
                        },
                        onSecondaryTapUp: (_) => p?.setLoop(null),
                        onLongPress: () => p?.setLoop(null),
                        child: Tooltip(
                          message: tr(
                            'Antippen: zum Takt · Ziehen: Schleife · Rechtsklick: Schleife aus',
                            'Tap: go to bar · Drag: loop · Right-click: loop off',
                          ),
                          waitDuration: const Duration(milliseconds: 900),
                          child: ListenableBuilder(
                            listenable: Listenable.merge([?p]),
                            builder: (context, _) => CustomPaint(
                              size: Size(d.width + 40, TrackLanes.rulerHeight),
                              painter: _RulerPainter(
                                d,
                                score,
                                cursorBar: e.cursor.bar,
                                loop: _dragLoop ?? p?.loop,
                                colors: c,
                                accent: Theme.of(context).colorScheme.primary,
                                textColor: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, color: c.line),
          Expanded(
            child: SingleChildScrollView(
              controller: _vLanes,
              child: SizedBox(
                height: lanesHeight,
                child: Row(
                  children: [
                    SizedBox(
                      width: TrackLanes.headerWidth,
                      child: Column(children: [for (var i = 0; i < n; i++) _header(context, i)]),
                    ),
                    VerticalDivider(width: 1, thickness: 1, color: c.line),
                    Expanded(
                      child: Listener(
                        onPointerSignal: _onWheel,
                        child: SingleChildScrollView(
                          controller: _hLanes,
                          scrollDirection: Axis.horizontal,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTapUp: (t) {
                              final track = (t.localPosition.dy ~/ TrackLanes.laneHeight).clamp(0, n - 1);
                              final bar = d.barAt(t.localPosition.dx);
                              final pos = d.positionIn(bar, t.localPosition.dx);
                              widget.onSelect(track, bar, pos);
                            },
                            child: RepaintBoundary(
                              child: CustomPaint(
                                size: Size(d.width + 40, lanesHeight),
                                painter: _LanesPainter(
                                  d,
                                  track: e.track,
                                  cursorBar: e.cursor.bar,
                                  loop: _dragLoop ?? p?.loop,
                                  colors: c,
                                ),
                                foregroundPainter: p == null
                                    ? null
                                    : _PlayheadPainter(d, p, Theme.of(context).colorScheme.onSurface),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, int i) {
    final c = context.scrivi;
    final e = widget.editor;
    final t = e.score.tracks[i];
    final p = widget.player;
    final selected = i == e.track;
    final name = t.name.isEmpty ? tr('Spur ${i + 1}', 'Track ${i + 1}') : t.name;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.onSelect(i, e.cursor.bar, i == e.track ? e.cursorOnset.toDouble() : 0),
      onSecondaryTapUp: (d) => widget.onTrackMenu(i, d.globalPosition),
      onLongPressStart: (d) => widget.onTrackMenu(i, d.globalPosition),
      child: Container(
        height: TrackLanes.laneHeight,
        color: selected ? c.cardHigh : null,
        child: Row(
          children: [
            Container(width: 4, color: trackColor(i)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
              ),
            ),
            if (p != null)
              ListenableBuilder(
                listenable: p,
                builder: (context, _) {
                  if (i >= p.volume.length) return const SizedBox.shrink();
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _small(context, 'M', tr('Stumm', 'Mute'), p.muted[i], () => p.toggleMute(i)),
                      const SizedBox(width: 3),
                      _small(context, 'S', tr('Solo', 'Solo'), p.solo[i], () => p.toggleSolo(i)),
                      SizedBox(
                        width: 86,
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 2,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                          ),
                          child: Tooltip(
                            message: '${tr('Lautstärke', 'Volume')} ${(p.volume[i] * 100).round()} %',
                            waitDuration: const Duration(milliseconds: 400),
                            child: Slider(value: p.volume[i], onChanged: (v) => p.setVolume(i, v)),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _small(BuildContext context, String letter, String tip, bool on, VoidCallback onTap) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tip,
      waitDuration: const Duration(milliseconds: 300),
      child: InkWell(
        borderRadius: BorderRadius.circular(5),
        onTap: onTap,
        child: Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? scheme.primary : null,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: on ? scheme.primary : context.scrivi.line),
          ),
          child: Text(
            letter,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: on ? scheme.onPrimary : null),
          ),
        ),
      ),
    );
  }
}

/// Lage der Takte und kleine Notenstriche pro Spur (einmal pro Änderung gerechnet).
class _Summary {
  _Summary(this.score, this.revision, this.zoom, this.xs, this.lengths, this.notes);

  final core.Score score;
  final int revision;
  final double zoom;

  /// Linker Rand jedes Takts (und am Ende die Gesamtbreite).
  final List<double> xs;

  /// Länge jedes Takts in ganzen Noten.
  final List<double> lengths;

  /// Pro Spur und Takt: Striche (Anfang, Ende als Anteil am Takt; Höhe 0..1).
  final List<List<List<(double, double, double)>>> notes;

  double get width => xs.last;

  static _Summary of(core.Score score, int revision, double zoom) {
    final xs = <double>[0];
    final lengths = <double>[];
    for (final mb in score.masterBars) {
      final l = mb.time.length.toDouble();
      lengths.add(l);
      xs.add(xs.last + math.max(16.0, l * zoom));
    }
    final notes = <List<List<(double, double, double)>>>[];
    for (final t in score.tracks) {
      var lo = 127, hi = 0;
      for (final b in t.bars) {
        for (final v in b.voices) {
          for (final beat in v.beats) {
            for (final n in beat.notes) {
              lo = math.min(lo, n.pitch.midi);
              hi = math.max(hi, n.pitch.midi);
            }
          }
        }
      }
      if (hi < lo) (lo, hi) = (60, 72);
      final span = math.max(12, hi - lo).toDouble();
      final mid = (lo + hi) / 2;
      final perBar = <List<(double, double, double)>>[];
      for (var bi = 0; bi < score.masterBars.length; bi++) {
        final out = <(double, double, double)>[];
        if (bi < t.bars.length) {
          final len = lengths[bi];
          for (final v in t.bars[bi].voices) {
            var at = 0.0;
            for (final beat in v.beats) {
              if (beat.grace != core.GraceType.none) continue;
              final d = beat.duration.length.toDouble();
              if (!beat.isRest) {
                for (final n in beat.notes) {
                  final h = (0.5 + (n.pitch.midi - mid) / span).clamp(0.0, 1.0);
                  out.add((at / len, math.min(1.0, (at + d) / len), h));
                }
              }
              at += d;
            }
          }
        }
        perBar.add(out);
      }
      notes.add(perBar);
    }
    return _Summary(score, revision, zoom, xs, lengths, notes);
  }

  int barAt(double x) {
    var lo = 0, hi = xs.length - 2;
    if (hi < 0) return 0;
    while (lo < hi) {
      final m = (lo + hi + 1) >> 1;
      if (xs[m] <= x) {
        lo = m;
      } else {
        hi = m - 1;
      }
    }
    return lo;
  }

  /// Stelle im Takt (ganze Noten) bei [x].
  double positionIn(int bar, double x) {
    final w = xs[bar + 1] - xs[bar];
    return ((x - xs[bar]) / w).clamp(0.0, 1.0) * lengths[bar];
  }

  double xOf(int bar, double position) {
    if (bar >= lengths.length) return xs.last;
    final w = xs[bar + 1] - xs[bar];
    return xs[bar] + w * (position / lengths[bar]).clamp(0.0, 1.0);
  }
}

class _RulerPainter extends CustomPainter {
  _RulerPainter(
    this.d,
    this.score, {
    required this.cursorBar,
    required this.loop,
    required this.colors,
    required this.accent,
    required this.textColor,
  });

  final _Summary d;
  final core.Score score;
  final Color textColor;
  final int cursorBar;
  final (int, int)? loop;
  final ScriviColors colors;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()..color = colors.line;
    final l = loop;
    if (l != null && l.$2 < d.lengths.length) {
      final r = Rect.fromLTRB(d.xs[l.$1], 0, d.xs[l.$2 + 1], 17);
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(4)), Paint()..color = accent.withAlpha(90));
    }
    // Taktnummern: so oft, wie Platz ist
    final step = d.zoom >= 30 ? 1 : (d.zoom >= 18 ? 2 : 4);
    for (var b = 0; b < d.lengths.length; b++) {
      final x = d.xs[b];
      canvas.drawLine(Offset(x, 12), Offset(x, 17), line);
      if (b % step == 0 || b == cursorBar) {
        _text(
          canvas,
          '${b + 1}',
          Offset(x + 3, 1),
          TextStyle(
            fontSize: 10.5,
            color: b == cursorBar ? accent : colors.muted,
            fontWeight: b == cursorBar ? FontWeight.w700 : FontWeight.w500,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        );
      }
    }
    // Formteile als Farbbänder
    final starts = <int>[];
    for (var b = 0; b < score.masterBars.length; b++) {
      if (score.masterBars[b].section != null) starts.add(b);
    }
    for (var k = 0; k < starts.length; k++) {
      final from = starts[k];
      final to = k + 1 < starts.length ? starts[k + 1] : score.masterBars.length;
      final r = Rect.fromLTRB(d.xs[from] + 1, 20, d.xs[to] - 1, size.height - 3);
      final color = trackColor(k + 2);
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(4)), Paint()..color = color.withAlpha(70));
      canvas.drawRect(Rect.fromLTWH(r.left, r.top, 3, r.height), Paint()..color = color);
      canvas.save();
      canvas.clipRect(r);
      _text(
        canvas,
        score.masterBars[from].section!.label,
        Offset(r.left + 7, r.top + 2),
        TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: textColor),
      );
      canvas.restore();
    }
  }

  void _text(Canvas canvas, String s, Offset at, TextStyle style) {
    (TextPainter(
      text: TextSpan(text: s, style: style),
      textDirection: TextDirection.ltr,
    )..layout()).paint(canvas, at);
  }

  @override
  bool shouldRepaint(_RulerPainter old) =>
      old.d != d || old.cursorBar != cursorBar || old.loop != loop || old.colors != colors || old.score != score;
}

class _LanesPainter extends CustomPainter {
  _LanesPainter(this.d, {required this.track, required this.cursorBar, required this.loop, required this.colors});

  final _Summary d;
  final int track;
  final int cursorBar;
  final (int, int)? loop;
  final ScriviColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    const h = TrackLanes.laneHeight;
    final l = loop;
    if (l != null && l.$2 < d.lengths.length) {
      canvas.drawRect(
        Rect.fromLTRB(d.xs[l.$1], 0, d.xs[l.$2 + 1], size.height),
        Paint()..color = colors.line.withAlpha(110),
      );
    }
    // Spalte des Cursors
    if (cursorBar < d.lengths.length) {
      canvas.drawRect(
        Rect.fromLTRB(d.xs[cursorBar], 0, d.xs[cursorBar + 1], size.height),
        Paint()..color = colors.cardHigh,
      );
    }
    final line = Paint()..color = colors.line;
    for (var t = 0; t < d.notes.length; t++) {
      final top = t * h;
      if (t > 0) canvas.drawLine(Offset(0, top), Offset(d.width, top), line);
      final color = trackColor(t);
      final fill = Paint()..color = color.withAlpha(t == track ? 70 : 45);
      final stroke = Paint()
        ..color = color
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      for (var b = 0; b < d.lengths.length; b++) {
        final notes = d.notes[t][b];
        final r = Rect.fromLTRB(d.xs[b] + 1, top + 4, d.xs[b + 1] - 1, top + h - 4);
        if (notes.isEmpty) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(r, const Radius.circular(3)),
            Paint()
              ..color = colors.line
              ..style = PaintingStyle.stroke,
          );
          continue;
        }
        canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(3)), fill);
        final inner = r.deflate(3);
        for (final (a, e, y) in notes) {
          final x0 = inner.left + inner.width * a;
          final x1 = math.max(x0 + 1.5, inner.left + inner.width * e - 1);
          final yy = inner.bottom - inner.height * y;
          canvas.drawLine(Offset(x0, yy), Offset(x1, yy), stroke);
        }
      }
      // Cursor in der gewählten Spur
      if (t == track && cursorBar < d.lengths.length) {
        final r = Rect.fromLTRB(d.xs[cursorBar] + 0.5, top + 2.5, d.xs[cursorBar + 1] - 0.5, top + h - 2.5);
        canvas.drawRRect(
          RRect.fromRectAndRadius(r, const Radius.circular(4)),
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_LanesPainter old) =>
      old.d != d || old.track != track || old.cursorBar != cursorBar || old.loop != loop || old.colors != colors;
}

/// Senkrechte Linie an der Stelle der Musik (nur beim Abspielen).
class _PlayheadPainter extends CustomPainter {
  _PlayheadPainter(this.d, this.player, this.color) : super(repaint: Listenable.merge([player, player.position]));
  final _Summary d;
  final ScorePlayer player;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (!player.playing) return;
    final (bar, pos) = player.location;
    final x = d.xOf(bar, pos);
    canvas.drawLine(
      Offset(x, 0),
      Offset(x, size.height),
      Paint()
        ..color = color
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_PlayheadPainter old) => old.d != d || old.player != player || old.color != color;
}
