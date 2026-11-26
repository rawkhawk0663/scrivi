import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scrivi_core/scrivi_core.dart' as core;

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
  final _viewer = GlobalKey<_PagesViewerState>();

  @override
  void initState() {
    super.initState();
    _load();
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
      final layout = core.Engraver(score, trackIndex: _track, measurer: FlutterTextMeasurer()).layout();
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

class _PagesViewerState extends State<_PagesViewer> {
  final _controller = TransformationController();
  final _focus = FocusNode();
  Size _viewport = Size.zero;
  double _contentHeight = 0;

  static const _gap = 16.0;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  double get _scale => _controller.value.getMaxScaleOnAxis();

  void _set(double scale, double tx, double ty) {
    final w = _viewport.width, h = _viewport.height;
    final contentW = w * scale, contentH = _contentHeight * scale;
    tx = tx.clamp(math.min(0.0, w - contentW), 0.0);
    ty = ty.clamp(math.min(0.0, h - contentH), 0.0);
    _controller.value = Matrix4.identity()
      ..translateByDouble(tx, ty, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
  }

  Offset get _translation {
    final m = _controller.value;
    return Offset(m.getTranslation().x, m.getTranslation().y);
  }

  void scrollBy(double dy, [double dx = 0]) {
    final t = _translation;
    _set(_scale, t.dx - dx, t.dy - dy);
  }

  void zoomBy(double factor, [Offset? focal]) {
    final f = focal ?? Offset(_viewport.width / 2, _viewport.height / 2);
    final s0 = _scale;
    final s1 = (s0 * factor).clamp(1.0, 4.0);
    final t = _translation;
    // Punkt unter dem Zeiger bleibt stehen.
    final cx = (f.dx - t.dx) / s0, cy = (f.dy - t.dy) / s0;
    _set(s1, f.dx - cx * s1, f.dy - cy * s1);
  }

  void reset() => _set(1, 0, _translation.dy / _scale);

  void _onSignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    GestureBinding.instance.pointerSignalResolver.register(e, (event) {
      final s = event as PointerScrollEvent;
      final ctrl = HardwareKeyboard.instance.isControlPressed;
      if (ctrl) {
        zoomBy(s.scrollDelta.dy < 0 ? 1.1 : 1 / 1.1, s.localPosition);
      } else {
        final shift = HardwareKeyboard.instance.isShiftPressed;
        scrollBy(shift ? 0 : s.scrollDelta.dy, shift ? s.scrollDelta.dy : s.scrollDelta.dx);
      }
    });
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
      _set(_scale, _translation.dx, 0);
    } else if (k == LogicalKeyboardKey.end) {
      _set(_scale, _translation.dx, -double.infinity);
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
        _contentHeight = heights.fold(_gap, (s, h) => s + h + _gap);
        return Focus(
          focusNode: _focus,
          autofocus: true,
          onKeyEvent: _onKey,
          child: InteractiveViewer(
            transformationController: _controller,
            constrained: false,
            minScale: 1,
            maxScale: 4,
            boundaryMargin: EdgeInsets.zero,
            child: Listener(
              onPointerSignal: _onSignal,
              child: SizedBox(
                width: box.maxWidth,
                height: math.max(_contentHeight, box.maxHeight),
                child: Column(
                  children: [
                    const SizedBox(height: _gap),
                    for (var i = 0; i < widget.pages.length; i++) ...[
                      SizedBox(
                        width: pageW,
                        child: ScorePageView(picture: widget.pictures[i], page: widget.pages[i]),
                      ),
                      const SizedBox(height: _gap),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
