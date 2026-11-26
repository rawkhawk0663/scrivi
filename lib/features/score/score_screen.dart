import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scrivi_core/scrivi_core.dart' as core;

import '../../app/device_settings.dart';
import '../../app/error_log.dart';
import '../../app/l10n.dart';
import '../../app/theme.dart';
import '../../core/library/library_controller.dart';
import '../../widgets/visuals.dart';
import 'score_painter.dart';

/// Zeigt ein Stück als Seiten mit Noten und Tabulatur.
class ScoreScreen extends StatefulWidget {
  const ScoreScreen({super.key, required this.piece});
  final Piece piece;

  @override
  State<ScoreScreen> createState() => _ScoreScreenState();
}

class _ScoreScreenState extends State<ScoreScreen> {
  core.Score? _score;
  List<core.PageDisplay>? _pages;
  List<ui.Picture>? _pictures;
  Object? _error;
  int _track = 0;
  ScoreView _view = ScoreView.both;
  final _viewer = GlobalKey<_PagesViewerState>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  DeviceSettings? get _settings => context.getInheritedWidgetOfExactType<SettingsScope>()?.settings;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _view = _settings?.scoreView.value ?? ScoreView.both;
  }

  bool get _stringed => _score != null && _score!.tracks.isNotEmpty && _score!.tracks[_track].staff.isStringed;

  void _setView(ScoreView v) {
    _view = v;
    _settings?.setScoreView(v);
    _engrave();
  }

  Future<void> _load() async {
    try {
      final score = await LibraryController.load(widget.piece.path);
      if (!mounted) return;
      _score = score;
      _engrave();
    } catch (e, st) {
      ErrorLog.record(e, st, where: 'Stück öffnen: ${widget.piece.fileName}');
      if (mounted) setState(() => _error = e);
    }
  }

  /// Die gewählte Spur setzen und als Bilder aufnehmen.
  void _engrave() {
    final score = _score;
    if (score == null) return;
    try {
      final options = core.LayoutOptions(
        showTab: _view != ScoreView.notation,
        showNotation: _view != ScoreView.tab,
        germanNoteNames: !L10n.isEnglish,
      );
      final layout = core.Engraver(
        score,
        trackIndex: _track,
        options: options,
        measurer: FlutterTextMeasurer(),
      ).layout();
      final pictures = layout.pages.map(PagePictures.record).toList();
      final old = _pictures;
      setState(() {
        _pages = layout.pages;
        _pictures = pictures;
      });
      // Alte Bilder erst nach dem nächsten Bild freigeben.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final p in old ?? const <ui.Picture>[]) {
          p.dispose();
        }
      });
    } catch (e, st) {
      ErrorLog.record(e, st, where: 'Stück öffnen: ${widget.piece.fileName}');
      if (mounted) setState(() => _error = e);
    }
  }

  String _viewName(ScoreView v) => switch (v) {
    ScoreView.both => tr('Noten und Tabulatur', 'Notation and tab'),
    ScoreView.notation => tr('Nur Noten', 'Notation only'),
    ScoreView.tab => tr('Nur Tabulatur', 'Tab only'),
  };

  String _trackName(int i) {
    final n = _score!.tracks[i].name;
    return n.isEmpty ? tr('Spur ${i + 1}', 'Track ${i + 1}') : n;
  }

  @override
  void dispose() {
    for (final p in _pictures ?? const <ui.Picture>[]) {
      p.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final info = _score?.info;
    final title = (info?.title.isNotEmpty ?? false) ? info!.title : widget.piece.displayTitle;
    final artist = info?.artist ?? widget.piece.artist;
    return Scaffold(
      backgroundColor: ScriviColors.pageSurround,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
            if (artist.isNotEmpty)
              Text(
                artist,
                style: TextStyle(fontSize: 13, color: context.scrivi.muted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        actions: [
          if ((_score?.tracks.length ?? 0) > 1)
            PopupMenuButton<int>(
              tooltip: tr('Spur wählen', 'Choose track'),
              initialValue: _track,
              onSelected: (i) {
                _track = i;
                _engrave();
              },
              itemBuilder: (context) => [
                for (var i = 0; i < _score!.tracks.length; i++)
                  PopupMenuItem(
                    value: i,
                    child: Text(
                      _score!.tracks[i].name.isEmpty ? tr('Spur ${i + 1}', 'Track ${i + 1}') : _score!.tracks[i].name,
                    ),
                  ),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.queue_music_outlined),
                    const SizedBox(width: 6),
                    Text(_trackName(_track)),
                    const Icon(Icons.arrow_drop_down),
                  ],
                ),
              ),
            ),
          if (_pages != null && _stringed)
            PopupMenuButton<ScoreView>(
              tooltip: tr('Ansicht', 'View'),
              initialValue: _view,
              icon: const Icon(Icons.view_agenda_outlined),
              onSelected: _setView,
              itemBuilder: (context) => [
                for (final v in ScoreView.values)
                  CheckedPopupMenuItem(value: v, checked: v == _view, child: Text(_viewName(v))),
              ],
            ),
          if (_pages != null) ...[
            IconButton(
              tooltip: tr('Kleiner', 'Zoom out'),
              icon: const Icon(Icons.zoom_out),
              onPressed: () => _viewer.currentState?.zoomBy(1 / 1.25),
            ),
            IconButton(
              tooltip: tr('Grösser', 'Zoom in'),
              icon: const Icon(Icons.zoom_in),
              onPressed: () => _viewer.currentState?.zoomBy(1.25),
            ),
            IconButton(
              tooltip: tr('Ganze Breite', 'Fit width'),
              icon: const Icon(Icons.fit_screen_outlined),
              onPressed: () => _viewer.currentState?.reset(),
            ),
          ],
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_error != null) {
      return EmptyState(
        icon: Icons.error_outline,
        title: tr('Das Stück lässt sich nicht öffnen', 'The piece can’t be opened'),
        text: problemText(_error!),
      );
    }
    final pages = _pages, pictures = _pictures;
    if (pages == null || pictures == null) return const Center(child: CircularProgressIndicator());
    return _PagesViewer(key: _viewer, pages: pages, pictures: pictures);
  }
}

/// Seiten untereinander, mit Zoom (zwei Finger, Strg + Mausrad, Knöpfe) und
/// Blättern (Mausrad, Wischen, Bild auf/ab, Pfeiltasten, Pedal).
class _PagesViewer extends StatefulWidget {
  const _PagesViewer({super.key, required this.pages, required this.pictures});
  final List<core.PageDisplay> pages;
  final List<ui.Picture> pictures;

  @override
  State<_PagesViewer> createState() => _PagesViewerState();
}

class _PagesViewerState extends State<_PagesViewer> with SingleTickerProviderStateMixin {
  // Eigene Steuerung statt eines fertigen Zoom-Bausteins: So bewegt das Mausrad nur
  // die Seiten (Zoomen nur mit Strg), und Finger, Stift und Touchpad verhalten sich gleich.
  double _scale = 1;
  Offset _offset = Offset.zero; // Verschiebung des Inhalts (≤ 0)
  final _focus = FocusNode();
  late final _fling = AnimationController.unbounded(vsync: this)..addListener(_onFling);
  Size _viewport = Size.zero;
  double _contentHeight = 0;

  // Gesten mit Finger, Stift, Maus (ziehen) und Touchpad
  double _gestureStartScale = 1;
  Offset _flingDirection = Offset.zero;
  double _flingLast = 0;

  static const _gap = 16.0;
  static const _minScale = 1.0;
  static const _maxScale = 4.0;

  @override
  void dispose() {
    _fling.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _set(double scale, Offset offset) {
    final w = _viewport.width, h = _viewport.height;
    final contentW = w * scale, contentH = _contentHeight * scale;
    final clamped = Offset(
      offset.dx.clamp(math.min(0.0, w - contentW), 0.0),
      offset.dy.clamp(math.min(0.0, h - contentH), 0.0),
    );
    if (scale == _scale && clamped == _offset) return;
    setState(() {
      _scale = scale;
      _offset = clamped;
    });
  }

  void scrollBy(double dy, [double dx = 0]) {
    _fling.stop();
    _set(_scale, _offset - Offset(dx, dy));
  }

  /// Zoomen um [factor]; der Punkt [focal] (im Fenster) bleibt stehen.
  void zoomBy(double factor, [Offset? focal]) => _zoomTo(_scale * factor, focal);

  void _zoomTo(double scale, Offset? focal) {
    _fling.stop();
    final f = focal ?? Offset(_viewport.width / 2, _viewport.height / 2);
    final s0 = _scale;
    final s1 = scale.clamp(_minScale, _maxScale);
    final content = (f - _offset) / s0;
    _set(s1, f - content * s1);
  }

  void reset() => _set(1, Offset(0, _offset.dy / _scale));

  void _onSignal(PointerSignalEvent e) {
    if (e is PointerScrollEvent) {
      GestureBinding.instance.pointerSignalResolver.register(e, (event) {
        final s = event as PointerScrollEvent;
        if (HardwareKeyboard.instance.isControlPressed) {
          zoomBy(s.scrollDelta.dy < 0 ? 1.1 : 1 / 1.1, s.localPosition);
        } else if (HardwareKeyboard.instance.isShiftPressed) {
          scrollBy(0, s.scrollDelta.dy);
        } else {
          scrollBy(s.scrollDelta.dy, s.scrollDelta.dx);
        }
      });
    } else if (e is PointerScaleEvent) {
      GestureBinding.instance.pointerSignalResolver.register(e, (event) {
        zoomBy((event as PointerScaleEvent).scale, event.localPosition);
      });
    }
  }

  void _onScaleStart(ScaleStartDetails d) {
    _fling.stop();
    _gestureStartScale = _scale;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    // Zuerst verschieben, dann um den Mittelpunkt der Finger zoomen.
    _set(_scale, _offset + d.focalPointDelta);
    if (d.pointerCount >= 2 || d.scale != 1.0) {
      _zoomTo(_gestureStartScale * d.scale, d.localFocalPoint);
    }
  }

  void _onScaleEnd(ScaleEndDetails d) {
    // Schwung nach dem Wischen (nur beim Verschieben, nicht beim Zoomen)
    final v = d.velocity.pixelsPerSecond;
    if (d.pointerCount > 0 || v.distance < 200) return;
    _flingDirection = v / v.distance;
    _flingLast = 0;
    final sim = FrictionSimulation(0.12, 0, v.distance);
    _fling.animateWith(sim);
  }

  void _onFling() {
    final pos = _fling.value;
    final delta = pos - _flingLast;
    _flingLast = pos;
    final before = _offset;
    _set(_scale, _offset + _flingDirection * delta);
    if (_offset == before) _fling.stop();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final page = _viewport.height * 0.85;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.pageDown || k == LogicalKeyboardKey.space || k == LogicalKeyboardKey.arrowRight) {
      scrollBy(page);
    } else if (k == LogicalKeyboardKey.pageUp || k == LogicalKeyboardKey.arrowLeft) {
      scrollBy(-page);
    } else if (k == LogicalKeyboardKey.arrowDown) {
      scrollBy(60);
    } else if (k == LogicalKeyboardKey.arrowUp) {
      scrollBy(-60);
    } else if (k == LogicalKeyboardKey.home) {
      _set(_scale, Offset(_offset.dx, 0));
    } else if (k == LogicalKeyboardKey.end) {
      _set(_scale, Offset(_offset.dx, -double.infinity));
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        _viewport = Size(box.maxWidth, box.maxHeight);
        final pageW = math.min(box.maxWidth - 2 * _gap, 1100.0);
        final heights = widget.pages.map((p) => pageW * p.height / p.width).toList();
        _contentHeight = math.max(heights.fold(_gap, (s, h) => s + h + _gap), box.maxHeight);
        // Nach einer Grössenänderung des Fensters wieder in die Grenzen holen.
        final w = box.maxWidth, h = box.maxHeight;
        _offset = Offset(
          _offset.dx.clamp(math.min(0.0, w - w * _scale), 0.0),
          _offset.dy.clamp(math.min(0.0, h - _contentHeight * _scale), 0.0),
        );
        return Focus(
          focusNode: _focus,
          autofocus: true,
          onKeyEvent: _onKey,
          child: Listener(
            onPointerSignal: _onSignal,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onScaleStart: _onScaleStart,
              onScaleUpdate: _onScaleUpdate,
              onScaleEnd: _onScaleEnd,
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.topLeft,
                  minWidth: box.maxWidth,
                  maxWidth: box.maxWidth,
                  minHeight: _contentHeight,
                  maxHeight: _contentHeight,
                  child: Transform(
                    transform: Matrix4.identity()
                      ..translateByDouble(_offset.dx, _offset.dy, 0, 1)
                      ..scaleByDouble(_scale, _scale, 1, 1),
                    child: Column(
                      children: [
                        const SizedBox(height: _gap),
                        for (var i = 0; i < widget.pages.length; i++) ...[
                          SizedBox(
                            width: pageW,
                            child: RepaintBoundary(
                              child: ScorePageView(picture: widget.pictures[i], page: widget.pages[i]),
                            ),
                          ),
                          const SizedBox(height: _gap),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
