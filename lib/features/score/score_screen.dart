import 'dart:async';
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
import '../library/library_screen.dart' show LibraryScope;
import 'edit_tools.dart';
import 'score_painter.dart';
import 'score_player.dart';
import 'transport_bar.dart';

/// Zeigt ein Stück als Seiten mit Noten und Tabulatur.
class ScoreScreen extends StatefulWidget {
  const ScoreScreen({super.key, required this.piece, this.startEditing = false});
  final Piece piece;

  /// Gleich im Bearbeiten-Modus öffnen (neues Stück).
  final bool startEditing;

  @override
  State<ScoreScreen> createState() => _ScoreScreenState();
}

class _ScoreScreenState extends State<ScoreScreen> implements EditHost {
  core.Score? _score;
  late Piece _piece = widget.piece;

  // Bearbeiten
  core.ScoreEditor? _editor;
  bool _penNotes = false;
  bool _paletteOpen = true;
  int _savedRevision = 0;
  Timer? _saveTimer;
  Future<void>? _saving;
  String _fretDigits = '';
  DateTime _fretTime = DateTime(0);
  core.EditCursor? _fretCursor;
  static List<core.Beat> _clipboard = const [];

  /// Zählt Cursor-Bewegungen (die Markierung zeichnet sich dann neu).
  final _cursorTick = ValueNotifier<int>(0);
  List<core.PageDisplay>? _pages;
  List<ui.Picture>? _pictures;
  Object? _error;
  int _track = 0;
  ScoreView _view = ScoreView.both;
  ScorePlayer? _player;
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
    _library = context.getInheritedWidgetOfExactType<LibraryScope>()?.library;
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
      _player = ScorePlayer(score);
      if (widget.startEditing) _editor = core.ScoreEditor(score, track: _track);
      _engrave();
    } catch (e, st) {
      ErrorLog.record(e, st, where: 'Stück öffnen: ${widget.piece.fileName}');
      if (mounted) setState(() => _error = e);
    }
  }

  /// Die gewählte Spur setzen und als Bilder aufnehmen.
  void _engrave() {
    final score = _editor?.score ?? _score;
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

  // ───────────────────────── Bearbeiten ─────────────────────────

  @override
  core.ScoreEditor get editor => _editor!;

  bool get _editing => _editor != null;

  @override
  bool get penNotes => _penNotes;
  @override
  set penNotes(bool v) => setState(() => _penNotes = v);

  @override
  bool get showsNotation => _view != ScoreView.tab || !_stringed;

  void _toggleEditing() {
    if (_editing) {
      _flushSave();
      setState(() => _editor = null);
      _cursorTick.value++;
    } else {
      final score = _score;
      if (score == null) return;
      unawaited(_player?.pause());
      setState(() => _editor = core.ScoreEditor(score, track: _track));
      _cursorTick.value++;
    }
  }

  @override
  void apply(void Function(core.ScoreEditor e) op) {
    final e = _editor;
    if (e == null) return;
    final rev = e.revision;
    try {
      op(e);
    } catch (err, st) {
      ErrorLog.record(err, st, where: 'Bearbeiten');
    }
    if (e.revision != rev) _afterEdit();
    _cursorTick.value++;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => _viewer.currentState?.revealCursor());
  }

  void _afterEdit() {
    final e = _editor!;
    _score = e.score;
    _engrave();
    unawaited(_player?.updateScore(e.score));
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), _flushSave);
  }

  /// Ungespeicherte Änderungen jetzt speichern.
  void _flushSave() {
    _saveTimer?.cancel();
    final e = _editor;
    final score = _score;
    if (score == null) return;
    if (e != null && e.revision == _savedRevision) return;
    if (e == null && _savedRevision == 0) return;
    final rev = e?.revision ?? _savedRevision;
    final lib = _library;
    if (lib == null) return;
    final prev = _saving ?? Future.value();
    _saving = prev.then((_) async {
      try {
        final updated = await lib.save(_piece, score);
        _piece = updated;
        _savedRevision = rev;
      } catch (err, st) {
        ErrorLog.record(err, st, where: 'Speichern: ${_piece.fileName}');
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(tr('Speichern ist fehlgeschlagen.', 'Saving failed.'))));
        }
      }
    });
  }

  LibraryController? _library;

  @override
  Future<void> editChord() async {
    final r = await askText(
      context,
      title: tr('Akkordsymbol', 'Chord symbol'),
      initial: editor.chordAtCursor(),
      hint: tr('z. B. Am7, D/F#, Gsus4', 'e.g. Am7, D/F#, Gsus4'),
    );
    if (r != null) apply((e) => e.setChord(r.$1));
  }

  @override
  Future<void> editText() async {
    final r = await askText(
      context,
      title: tr('Text über der Note', 'Text above the note'),
      initial: editor.currentBeat?.text ?? '',
    );
    if (r != null) apply((e) => e.setText(r.$1));
  }

  @override
  Future<void> editLyrics() async {
    // Silbe für Silbe: „Weiter“ springt zur nächsten Note
    while (mounted) {
      final b = editor.currentBeat;
      final r = await askText(
        context,
        title: tr('Liedtext (Takt ${editor.cursor.bar + 1})', 'Lyrics (bar ${editor.cursor.bar + 1})'),
        initial: b != null && b.lyrics.isNotEmpty ? b.lyrics.first : '',
        hint: tr('Silbe, mit - für Trennung', 'Syllable, use - to split words'),
        next: true,
      );
      if (r == null) return;
      apply((e) => e.setLyric(r.$1));
      if (!r.$2) return;
      apply((e) => e.nextNote());
    }
  }

  @override
  void showMoreMenu(Offset globalPosition) async {
    final e = editor;
    final mb = e.score.masterBars[e.cursor.bar];
    final sel = e.selection != null;
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        globalPosition.dx + 1,
        globalPosition.dy + 1,
      ),
      items: [
        PopupMenuItem(value: 'before', child: Text(tr('Takt davor einfügen', 'Insert bar before'))),
        PopupMenuItem(value: 'after', child: Text(tr('Takt danach einfügen', 'Insert bar after'))),
        PopupMenuItem(
          value: 'delete',
          child: Text(sel ? tr('Ausgewählte Takte löschen', 'Delete selected bars') : tr('Takt löschen', 'Delete bar')),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'time', child: Text(tr('Taktart …', 'Time signature …'))),
        PopupMenuItem(value: 'key', child: Text(tr('Tonart …', 'Key …'))),
        PopupMenuItem(value: 'tempo', child: Text(tr('Tempo …', 'Tempo …'))),
        PopupMenuItem(value: 'section', child: Text(tr('Formteil …', 'Section …'))),
        CheckedPopupMenuItem(
          value: 'repeatStart',
          checked: mb.repeatStart,
          child: Text(tr('Wiederholung: Anfang', 'Repeat: start')),
        ),
        CheckedPopupMenuItem(
          value: 'repeatEnd',
          checked: mb.hasRepeatEnd,
          child: Text(tr('Wiederholung: Ende …', 'Repeat: end …')),
        ),
        CheckedPopupMenuItem(
          value: 'double',
          checked: mb.doubleBar,
          child: Text(tr('Doppelstrich', 'Double bar line')),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'copy', child: Text(tr('Kopieren  (Strg+C)', 'Copy  (Ctrl+C)'))),
        PopupMenuItem(value: 'cut', child: Text(tr('Ausschneiden  (Strg+X)', 'Cut  (Ctrl+X)'))),
        PopupMenuItem(
          value: 'paste',
          enabled: _clipboard.isNotEmpty,
          child: Text(tr('Einfügen  (Strg+V)', 'Paste  (Ctrl+V)')),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'title', child: Text(tr('Titel und Interpret …', 'Title and artist …'))),
        PopupMenuItem(
          value: 'transpose',
          child: Text(tr('Ganzes Stück transponieren …', 'Transpose the whole piece …')),
        ),
      ],
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case 'before':
        apply((e) => e.insertBars(after: false));
      case 'after':
        apply((e) => e.insertBars());
      case 'delete':
        apply((e) => e.deleteBars());
      case 'time':
        final t = await askTimeSignature(context, mb.time);
        if (t != null) apply((e) => e.setTimeSignature(t));
      case 'key':
        final k = await askKey(context, mb.key);
        if (k != null) apply((e) => e.setKey(k));
      case 'tempo':
        final v = await askNumber(
          context,
          title: tr('Tempo (Viertel pro Minute)', 'Tempo (quarters per minute)'),
          initial: e.tempoAtCursor.round(),
          min: 20,
          max: 400,
        );
        if (v != null) apply((e) => e.setTempo(v.toDouble()));
      case 'section':
        final r = await askText(
          context,
          title: tr('Formteil', 'Section'),
          initial: mb.section?.label ?? '',
          suggestions: sectionSuggestions(),
        );
        if (r != null) apply((e) => e.setSection(r.$1));
      case 'repeatStart':
        apply((e) => e.toggleRepeatStart());
      case 'repeatEnd':
        final v = await askNumber(
          context,
          title: tr('Wie oft spielen? (0 = keine Wiederholung)', 'How many times? (0 = no repeat)'),
          initial: mb.hasRepeatEnd ? mb.repeatEnd : 2,
          min: 0,
          max: 9,
        );
        if (v != null) apply((e) => e.setRepeatEnd(v));
      case 'double':
        apply((e) => e.toggleDoubleBar());
      case 'copy':
        _clipboard = e.copy();
      case 'cut':
        apply((e) => _clipboard = e.cut());
      case 'paste':
        apply((e) => e.paste(_clipboard));
      case 'title':
        final r = await askTitle(context, e.score.info.title, e.score.info.artist);
        if (r != null) apply((e) => e.setInfo(title: r.$1.trim(), artist: r.$2.trim()));
      case 'transpose':
        final v = await askTranspose(context);
        if (v != null && v != 0) apply((e) => e.transposeAll(v));
    }
  }

  /// Tastatur beim Bearbeiten. Gibt true zurück, wenn die Taste verwendet wurde.
  bool _onEditKey(KeyEvent ev) {
    final e = _editor;
    if (e == null || (ev is! KeyDownEvent && ev is! KeyRepeatEvent)) return false;
    final hw = HardwareKeyboard.instance;
    final ctrl = hw.isControlPressed || hw.isMetaPressed;
    final shift = hw.isShiftPressed;
    final k = ev.logicalKey;
    if (ctrl) {
      if (k == LogicalKeyboardKey.keyZ) {
        apply((e) => shift ? e.redo() : e.undo());
      } else if (k == LogicalKeyboardKey.keyY) {
        apply((e) => e.redo());
      } else if (k == LogicalKeyboardKey.keyC) {
        _clipboard = e.copy();
      } else if (k == LogicalKeyboardKey.keyX) {
        apply((e) => _clipboard = e.cut());
      } else if (k == LogicalKeyboardKey.keyV) {
        apply((e) => e.paste(_clipboard));
      } else if (k == LogicalKeyboardKey.keyA) {
        apply((e) => e.selectAll());
      } else if (k == LogicalKeyboardKey.arrowLeft) {
        apply((e) => e.moveBar(-1, select: shift));
      } else if (k == LogicalKeyboardKey.arrowRight) {
        apply((e) => e.moveBar(1, select: shift));
      } else {
        return false;
      }
      return true;
    }
    // Bundzahlen: zwei Ziffern kurz nacheinander ergeben eine zweistellige Zahl
    final digit = int.tryParse(ev.character ?? '');
    if (digit != null && digit >= 0 && digit <= 9 && e.stringed) {
      final now = DateTime.now();
      final combined = '$_fretDigits$digit';
      // Zweistellig nur am selben Ton (gleicher Takt, Schlag und Saite)
      final quick = now.difference(_fretTime) < const Duration(milliseconds: 800) && e.cursor == _fretCursor;
      final max = e.score.tracks[e.track].staff.fretCount;
      if (quick && _fretDigits.isNotEmpty && int.parse(combined) <= max) {
        _fretDigits = combined;
      } else {
        _fretDigits = '$digit';
      }
      _fretTime = now;
      final f = int.parse(_fretDigits);
      apply((e) => e.inputFret(f));
      _fretCursor = e.cursor;
      return true;
    }
    final ch = (ev.character ?? '').toUpperCase();
    const steps = {'C': 0, 'D': 1, 'E': 2, 'F': 3, 'G': 4, 'A': 5, 'B': 6, 'H': 6};
    if (steps.containsKey(ch) && !hw.isAltPressed) {
      apply((e) => e.inputStep(steps[ch]!, addToChord: shift));
      return true;
    }
    if (k == LogicalKeyboardKey.arrowLeft) {
      apply((e) => e.moveBeat(-1, select: shift));
    } else if (k == LogicalKeyboardKey.arrowRight) {
      apply((e) => e.moveBeat(1, select: shift));
    } else if (k == LogicalKeyboardKey.arrowUp) {
      apply((e) => shift ? e.transposeSelection(1) : e.moveString(1));
    } else if (k == LogicalKeyboardKey.arrowDown) {
      apply((e) => shift ? e.transposeSelection(-1) : e.moveString(-1));
    } else if (k == LogicalKeyboardKey.delete || k == LogicalKeyboardKey.backspace) {
      apply((e) => e.toRest());
    } else if (ch == '+' || k == LogicalKeyboardKey.numpadAdd) {
      apply((e) => e.setDuration(_shorter(e)));
    } else if (ch == '-' || k == LogicalKeyboardKey.numpadSubtract) {
      apply((e) => e.setDuration(_longer(e)));
    } else if (ch == '.' || k == LogicalKeyboardKey.numpadDecimal) {
      apply((e) => e.toggleDot());
    } else if (ch == 'T') {
      apply((e) => e.toggleTriplet());
    } else if (ch == 'L') {
      apply((e) => e.toggleTie());
    } else if (ch == 'K') {
      editChord();
    } else if (ch == 'Y') {
      editLyrics();
    } else if (k == LogicalKeyboardKey.escape) {
      apply((e) => e.anchor = null);
    } else {
      return false;
    }
    return true;
  }

  core.NoteValue _shorter(core.ScoreEditor e) {
    final v = e.currentBeat?.duration.value ?? e.duration.value;
    return core.NoteValue.values[(v.index + 1).clamp(1, core.NoteValue.values.length - 2)];
  }

  core.NoteValue _longer(core.ScoreEditor e) {
    final v = e.currentBeat?.duration.value ?? e.duration.value;
    return core.NoteValue.values[(v.index - 1).clamp(1, core.NoteValue.values.length - 2)];
  }

  /// Angetippt beim Bearbeiten: Cursor dorthin, mit „Stift setzt Noten“ auch eine Note.
  void _onEditTap(_PageHit hit) {
    apply((e) {
      e.setCursor(hit.bar, hit.position, string: hit.string, select: HardwareKeyboard.instance.isShiftPressed);
      if (_penNotes && hit.diatonic != null && hit.string == null) e.inputDiatonic(hit.diatonic!);
    });
  }

  @override
  void dispose() {
    _flushSave();
    _cursorTick.dispose();
    _player?.dispose();
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
          if (_editing) ...[
            IconButton(
              tooltip: tr('Rückgängig  (Strg+Z)', 'Undo  (Ctrl+Z)'),
              icon: const Icon(Icons.undo_rounded),
              onPressed: editor.canUndo ? () => apply((e) => e.undo()) : null,
            ),
            IconButton(
              tooltip: tr('Wiederholen  (Strg+Y)', 'Redo  (Ctrl+Y)'),
              icon: const Icon(Icons.redo_rounded),
              onPressed: editor.canRedo ? () => apply((e) => e.redo()) : null,
            ),
            IconButton(
              tooltip: _paletteOpen ? tr('Werkzeuge ausblenden', 'Hide tools') : tr('Werkzeuge zeigen', 'Show tools'),
              icon: Icon(_paletteOpen ? Icons.handyman : Icons.handyman_outlined),
              onPressed: () => setState(() => _paletteOpen = !_paletteOpen),
            ),
          ],
          if (_pages != null)
            _editing
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: FilledButton.icon(
                      onPressed: _toggleEditing,
                      icon: const Icon(Icons.check_rounded),
                      label: Text(tr('Fertig', 'Done')),
                    ),
                  )
                : IconButton(
                    tooltip: tr('Bearbeiten', 'Edit'),
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: _toggleEditing,
                  ),
          if ((_score?.tracks.length ?? 0) > 1)
            PopupMenuButton<int>(
              tooltip: tr('Spur wählen', 'Choose track'),
              initialValue: _track,
              onSelected: (i) {
                _track = i;
                _editor?.track = i;
                _engrave();
                _cursorTick.value++;
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
      bottomNavigationBar: _player == null || _pages == null ? null : TransportBar(player: _player!),
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
    return _PagesViewer(
      key: _viewer,
      pages: pages,
      pictures: pictures,
      player: _player,
      onBarTap: (bar) => _player?.seekToBar(bar),
      editor: _editor,
      cursorTick: _cursorTick,
      onEditTap: _onEditTap,
      onEditKey: _onEditKey,
      palette: _editing && _paletteOpen ? EditPalette(host: this) : null,
    );
  }
}

/// Seiten untereinander, mit Zoom (zwei Finger, Strg + Mausrad, Knöpfe) und
/// Blättern (Mausrad, Wischen, Bild auf/ab, Pfeiltasten, Pedal).
/// Angetippte Stelle: Takt, Stelle im Takt (ganze Noten), Saite bzw. Stammton.
class _PageHit {
  const _PageHit(this.bar, this.position, this.string, this.diatonic);
  final int bar;
  final double position;
  final int? string;
  final int? diatonic;
}

class _PagesViewer extends StatefulWidget {
  const _PagesViewer({
    super.key,
    required this.pages,
    required this.pictures,
    this.player,
    this.onBarTap,
    this.editor,
    this.cursorTick,
    this.onEditTap,
    this.onEditKey,
    this.palette,
  });
  final List<core.PageDisplay> pages;
  final List<ui.Picture> pictures;
  final ScorePlayer? player;

  /// Antippen eines Takts (Partitur-Nummer).
  final ValueChanged<int>? onBarTap;

  /// Bearbeiten: Cursor, Antippen, Tasten, Werkzeugleiste.
  final core.ScoreEditor? editor;
  final ValueNotifier<int>? cursorTick;
  final ValueChanged<_PageHit>? onEditTap;
  final bool Function(KeyEvent)? onEditKey;
  final Widget? palette;

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

  // Lage der Seiten im Inhalt (ungezoomt)
  List<double> _pageTops = const [];
  double _pageW = 0;
  double _pageLeft = 0;
  core.SystemBox? _followed;

  static const _gap = 16.0;
  static const _minScale = 1.0;
  static const _maxScale = 4.0;

  @override
  void initState() {
    super.initState();
    widget.player?.position.addListener(_follow);
  }

  @override
  void didUpdateWidget(_PagesViewer old) {
    super.didUpdateWidget(old);
    if (old.player != widget.player) {
      old.player?.position.removeListener(_follow);
      widget.player?.position.addListener(_follow);
    }
  }

  @override
  void dispose() {
    widget.player?.position.removeListener(_follow);
    _fling.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Beim Abspielen mitblättern: Kommt die Markierung in eine Zeile, die nicht
  /// ganz zu sehen ist, wird sie oben ins Bild gerückt.
  void _follow() {
    final player = widget.player;
    if (player == null || !player.playing || _pageTops.isEmpty) return;
    final (bar, _) = player.location;
    for (var i = 0; i < widget.pages.length; i++) {
      for (final sys in widget.pages[i].systems) {
        if (bar < sys.firstBar || bar > sys.lastBar) continue;
        if (identical(sys, _followed)) return;
        _followed = sys;
        final k = _pageW / widget.pages[i].width;
        final top = (_pageTops[i] + sys.top * k) * _scale + _offset.dy;
        final bottom = (_pageTops[i] + sys.bottom * k) * _scale + _offset.dy;
        if (top < 0 || bottom > _viewport.height) {
          _fling.stop();
          _set(_scale, Offset(_offset.dx, _offset.dy - top + _viewport.height * 0.12));
        }
        return;
      }
    }
  }

  /// Angetippter Takt: Fensterpunkt → Seite → Zeile → Takt.
  void _onTapUp(TapUpDetails d) {
    _focus.requestFocus();
    if (widget.editor != null) {
      final hit = _hitAt(d.localPosition);
      if (hit != null) widget.onEditTap?.call(hit);
      return;
    }
    final cb = widget.onBarTap;
    if (cb == null) return;
    final p = (d.localPosition - _offset) / _scale;
    for (var i = 0; i < widget.pages.length && i < _pageTops.length; i++) {
      final page = widget.pages[i];
      final k = _pageW / page.width;
      final h = page.height * k;
      if (p.dy < _pageTops[i] || p.dy > _pageTops[i] + h) continue;
      final x = (p.dx - _pageLeft) / k, y = (p.dy - _pageTops[i]) / k;
      for (final sys in page.systems) {
        if (y < sys.top - 2 || y > sys.bottom + 2) continue;
        for (final b in sys.bars) {
          if (x >= b.x0 - 1 && x <= b.x1) {
            cb(b.bar);
            return;
          }
        }
      }
    }
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

  /// Fensterpunkt → Takt, Stelle, Saite bzw. Stammton.
  _PageHit? _hitAt(Offset local) {
    final p = (local - _offset) / _scale;
    for (var i = 0; i < widget.pages.length && i < _pageTops.length; i++) {
      final page = widget.pages[i];
      final k = _pageW / page.width;
      if (p.dy < _pageTops[i] || p.dy > _pageTops[i] + page.height * k) continue;
      final x = (p.dx - _pageLeft) / k, y = (p.dy - _pageTops[i]) / k;
      core.SystemBox? best;
      var bestDist = double.infinity;
      for (final sys in page.systems) {
        final dist = y < sys.top ? sys.top - y : (y > sys.bottom ? y - sys.bottom : 0.0);
        if (dist < bestDist) {
          bestDist = dist;
          best = sys;
        }
      }
      if (best == null || bestDist > 4) return null;
      for (final b in best.bars) {
        if (x < b.x0 - 1 || x > b.x1) continue;
        // Nächster Schlag nach x
        var pos = 0.0, d = double.infinity;
        for (final (onset, bx) in b.beats) {
          if ((bx - x).abs() < d) {
            d = (bx - x).abs();
            pos = onset;
          }
        }
        final tabTop = best.tabTop;
        final inTab = tabTop != null && y > tabTop - best.tabSpacing && y < tabTop + best.strings * best.tabSpacing;
        return _PageHit(b.bar, pos, inTab ? best.stringAt(y) : null, inTab ? null : best.diatonicAt(y));
      }
    }
    return null;
  }

  /// Rechteck des Cursors im Fenster (null = nicht sichtbar bzw. kein Bearbeiten).
  Rect? _cursorRect() {
    final e = widget.editor;
    if (e == null || _pageTops.isEmpty) return null;
    final bar = e.cursor.bar;
    final onset = e.cursorOnset.toDouble();
    for (var i = 0; i < widget.pages.length && i < _pageTops.length; i++) {
      final page = widget.pages[i];
      for (final sys in page.systems) {
        if (bar < sys.firstBar || bar > sys.lastBar) continue;
        final x = sys.xAt(bar, onset);
        if (x == null) continue;
        final k = _pageW / page.width;
        Offset tr(double px, double py) => Offset(_pageLeft + px * k, _pageTops[i] + py * k) * _scale + _offset;
        return Rect.fromPoints(tr(x - 1.2, sys.top), tr(x + 1.2, sys.bottom));
      }
    }
    return null;
  }

  /// Cursor ins Bild holen (nach Tastatur-Eingaben).
  void revealCursor() {
    final r = _cursorRect();
    if (r == null) return;
    var dy = 0.0, dx = 0.0;
    if (r.top < 8) dy = 8 - r.top + 40;
    if (r.bottom > _viewport.height - 8) dy = (_viewport.height - 8) - r.bottom - 40;
    if (r.left < 0) dx = -r.left + 40;
    if (r.right > _viewport.width) dx = _viewport.width - r.right - 40;
    if (dx != 0 || dy != 0) _set(_scale, _offset + Offset(dx, dy));
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (widget.onEditKey?.call(e) ?? false) return KeyEventResult.handled;
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final page = _viewport.height * 0.85;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.space && widget.player != null) {
      widget.player!.toggle();
    } else if (k == LogicalKeyboardKey.pageDown ||
        k == LogicalKeyboardKey.space ||
        k == LogicalKeyboardKey.arrowRight) {
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
        _pageW = pageW;
        _pageLeft = (box.maxWidth - pageW) / 2;
        final tops = <double>[];
        var y = _gap;
        for (final h in heights) {
          tops.add(y);
          y += h + _gap;
        }
        _pageTops = tops;
        // Nach einer Grössenänderung des Fensters wieder in die Grenzen holen.
        final w = box.maxWidth, h = box.maxHeight;
        _offset = Offset(
          _offset.dx.clamp(math.min(0.0, w - w * _scale), 0.0),
          _offset.dy.clamp(math.min(0.0, h - _contentHeight * _scale), 0.0),
        );
        final viewer = Focus(
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
              onTapUp: _onTapUp,
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
                              child: CustomPaint(
                                foregroundPainter: widget.player == null
                                    ? null
                                    : _CursorPainter(widget.player!, widget.pages[i]),
                                child: CustomPaint(
                                  foregroundPainter: widget.editor == null
                                      ? null
                                      : _EditCursorPainter(widget.editor!, widget.pages[i], widget.cursorTick!),
                                  child: ScorePageView(picture: widget.pictures[i], page: widget.pages[i]),
                                ),
                              ),
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
        final palette = widget.palette;
        if (palette == null) return viewer;
        // Werkzeugleiste beim Cursor: unter der Zeile, sonst darüber
        final r = _cursorRect();
        const maxW = 560.0;
        final left = r == null
            ? (box.maxWidth - maxW) / 2
            : (r.center.dx - 140).clamp(8.0, math.max(8.0, box.maxWidth - maxW - 8));
        final visible = r != null && r.bottom > 0 && r.top < box.maxHeight;
        final below = visible && r.bottom + 150 < box.maxHeight;
        return Stack(
          children: [
            Positioned.fill(child: viewer),
            Positioned(
              left: left.toDouble(),
              top: below ? r.bottom + 6 : null,
              bottom: below ? null : (visible ? math.max(8.0, box.maxHeight - r.top + 6) : 8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: maxW),
                child: palette,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Mitlaufende Markierung: ein farbiger Balken über die ganze Zeile.
class _CursorPainter extends CustomPainter {
  _CursorPainter(this.player, this.page) : super(repaint: Listenable.merge([player.position, player]));
  final ScorePlayer player;
  final core.PageDisplay page;

  @override
  void paint(Canvas canvas, Size size) {
    if (!player.playing && player.position.value <= 0) return;
    final (bar, pos) = player.location;
    final k = size.width / page.width;
    for (final sys in page.systems) {
      if (bar < sys.firstBar || bar > sys.lastBar) continue;
      final x = sys.xAt(bar, pos);
      if (x == null) continue;
      final r = Rect.fromLTRB((x - 0.45) * k, (sys.top - 1) * k, (x + 0.45) * k, (sys.bottom + 1) * k);
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, Radius.circular(0.3 * k)),
        Paint()..color = ScriviColors.selection.withAlpha(110),
      );
    }
  }

  @override
  bool shouldRepaint(_CursorPainter old) => old.player != player || old.page != page;
}

/// Cursor beim Bearbeiten: Balken über die Zeile, Markierung auf der Saite,
/// ausgewählte Schläge hinterlegt.
class _EditCursorPainter extends CustomPainter {
  _EditCursorPainter(this.editor, this.page, Listenable tick) : super(repaint: tick);
  final core.ScoreEditor editor;
  final core.PageDisplay page;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / page.width;
    final color = ScriviColors.selection;
    // Auswahl
    final sel = editor.selection;
    if (sel != null) {
      final (a, b) = sel;
      for (final sys in page.systems) {
        for (final span in sys.bars) {
          if (span.bar < a.bar || span.bar > b.bar) continue;
          final from = span.bar == a.bar ? editor.onsetOf(a.bar, a.beat).toDouble() : 0.0;
          final to = span.bar == b.bar
              ? (editor.onsetOf(b.bar, b.beat) + (editor.beatsOf(b.bar)[b.beat].duration.length)).toDouble()
              : span.length;
          final x0 = span.bar == a.bar ? span.xAt(from) - 0.8 : span.x0;
          final x1 = span.bar == b.bar ? math.min(span.xAt(to) - 0.8, span.x1) : span.x1;
          canvas.drawRect(
            Rect.fromLTRB(x0 * k, (sys.top - 0.5) * k, x1 * k, (sys.bottom + 0.5) * k),
            Paint()..color = color.withAlpha(40),
          );
        }
      }
    }
    final bar = editor.cursor.bar;
    final onset = editor.cursorOnset.toDouble();
    for (final sys in page.systems) {
      if (bar < sys.firstBar || bar > sys.lastBar) continue;
      final x = sys.xAt(bar, onset);
      if (x == null) continue;
      final col = Rect.fromLTRB((x - 1.1) * k, (sys.top - 0.5) * k, (x + 1.1) * k, (sys.bottom + 0.5) * k);
      canvas.drawRRect(RRect.fromRectAndRadius(col, Radius.circular(0.4 * k)), Paint()..color = color.withAlpha(45));
      final sy = sys.stringY(editor.cursor.string);
      if (sy != null && editor.stringed) {
        final r = Rect.fromCenter(center: Offset(x * k, sy * k), width: 2.2 * k, height: 1.3 * k);
        canvas.drawRRect(
          RRect.fromRectAndRadius(r, Radius.circular(0.3 * k)),
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.18 * k,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_EditCursorPainter old) => old.editor != editor || old.page != page;
}
