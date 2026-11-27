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
import '../../app/window_buttons.dart';
import '../../core/library/library_controller.dart';
import '../../widgets/visuals.dart';
import '../library/library_screen.dart' show LibraryScope;
import 'edit_tools.dart';
import 'fretboard.dart';
import 'note_preview.dart';
import 'score_painter.dart';
import 'score_player.dart';
import 'tools.dart';
import 'transport_bar.dart';

/// Ein Stück schreiben und ansehen: Werkzeuge links, Noten in der Mitte,
/// Griffbrett unten, oben Anzeige und Abspielen. Es gibt keinen eigenen
/// Bearbeiten-Modus: Der Cursor ist immer da.
class ScoreScreen extends StatefulWidget {
  const ScoreScreen({super.key, required this.piece, this.startEditing = false});
  final Piece piece;

  /// Früher: gleich im Bearbeiten-Modus öffnen. Heute wird immer geschrieben.
  final bool startEditing;

  @override
  State<ScoreScreen> createState() => _ScoreScreenState();
}

class _ScoreScreenState extends State<ScoreScreen> implements ToolHost {
  core.Score? _score;
  late Piece _piece = widget.piece;
  List<core.PageDisplay>? _pages;
  List<ui.Picture>? _pictures;
  Object? _error;
  int _track = 0;
  ScoreView _view = ScoreView.both;
  ScorePlayer? _player;
  final _viewer = GlobalKey<_PagesViewerState>();
  final _preview = NotePreview();

  // Schreiben
  core.ScoreEditor? _editor;
  bool _penNotes = false;
  int _savedRevision = 0;
  Timer? _saveTimer;
  Future<void>? _saving;
  String _fretDigits = '';
  DateTime _fretTime = DateTime(0);
  core.EditCursor? _fretCursor;
  static List<core.Beat> _clipboard = const [];
  LibraryController? _library;

  /// Zählt Cursor-Bewegungen (die Markierung zeichnet sich dann neu).
  final _cursorTick = ValueNotifier<int>(0);

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
      _editor = core.ScoreEditor(score, track: _track);
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

  // ───────────────────────── Schreiben ─────────────────────────

  @override
  core.ScoreEditor get editor => _editor!;

  @override
  bool get penNotes => _penNotes;
  @override
  set penNotes(bool v) => setState(() => _penNotes = v);

  @override
  void apply(void Function(core.ScoreEditor e) op, {bool sound = false}) {
    final e = _editor;
    if (e == null) return;
    final rev = e.revision;
    try {
      op(e);
    } catch (err, st) {
      ErrorLog.record(err, st, where: 'Bearbeiten');
    }
    if (e.revision != rev) _afterEdit();
    if (sound) _playBeat();
    _cursorTick.value++;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => _viewer.currentState?.revealCursor());
  }

  /// Die Töne am Cursor kurz anspielen.
  void _playBeat() {
    final e = _editor!;
    final b = e.currentBeat;
    if (b == null || b.isRest) return;
    final t = e.score.tracks[e.track];
    final midis = [
      for (final n in b.notes)
        if (!n.dead) n.pitch.midi,
    ]..sort();
    unawaited(_preview.play(midis, core.PlayTrack(e.track, t, const [])));
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
    if (score == null || e == null || e.revision == _savedRevision) return;
    final rev = e.revision;
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

  core.MasterBar get _bar => editor.score.masterBars[editor.cursor.bar];

  @override
  Future<void> editTimeSignature() async {
    final t = await askTimeSignature(context, _bar.time);
    if (t != null) apply((e) => e.setTimeSignature(t));
  }

  @override
  Future<void> editKey() async {
    final k = await askKey(context, _bar.key);
    if (k != null) apply((e) => e.setKey(k));
  }

  @override
  Future<void> editTempo() async {
    final v = await askNumber(
      context,
      title: tr('Tempo (Viertel pro Minute)', 'Tempo (quarters per minute)'),
      initial: editor.tempoAtCursor.round(),
      min: 20,
      max: 400,
    );
    if (v != null) apply((e) => e.setTempo(v.toDouble()));
  }

  @override
  Future<void> editSection() async {
    final r = await askText(
      context,
      title: tr('Formteil', 'Section'),
      initial: _bar.section?.label ?? '',
      suggestions: sectionSuggestions(),
    );
    if (r != null) apply((e) => e.setSection(r.$1));
  }

  @override
  Future<void> editRepeatEnd() async {
    final v = await askNumber(
      context,
      title: tr('Wie oft spielen? (0 = keine Wiederholung)', 'How many times? (0 = no repeat)'),
      initial: _bar.hasRepeatEnd ? _bar.repeatEnd : 2,
      min: 0,
      max: 9,
    );
    if (v != null) apply((e) => e.setRepeatEnd(v));
  }

  @override
  Future<void> editTitle() async {
    final r = await askTitle(context, editor.score.info.title, editor.score.info.artist);
    if (r != null) apply((e) => e.setInfo(title: r.$1.trim(), artist: r.$2.trim()));
  }

  @override
  Future<void> editTranspose() async {
    final v = await askTranspose(context);
    if (v != null && v != 0) apply((e) => e.transposeAll(v));
  }

  @override
  void copy() {
    _clipboard = editor.copy();
    setState(() {});
  }

  @override
  void cut() => apply((e) => _clipboard = e.cut());

  @override
  void paste() {
    if (_clipboard.isNotEmpty) apply((e) => e.paste(_clipboard));
  }

  @override
  bool get canPaste => _clipboard.isNotEmpty;

  /// Abspielen ab dem Cursor; beim Anhalten steht der Cursor dort, wo die Musik war.
  Future<void> _togglePlay() async {
    final p = _player, e = _editor;
    if (p == null || e == null) return;
    if (p.playing) {
      await p.pause();
      final (bar, pos) = p.location;
      apply((e) => e.setCursor(bar, pos));
    } else {
      p.seekTo(e.cursor.bar, e.cursorOnset.toDouble());
      await p.play();
    }
    setState(() {});
  }

  /// Tastatur. Gibt true zurück, wenn die Taste verwendet wurde.
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
        copy();
      } else if (k == LogicalKeyboardKey.keyX) {
        cut();
      } else if (k == LogicalKeyboardKey.keyV) {
        paste();
      } else if (k == LogicalKeyboardKey.keyA) {
        apply((e) => e.selectAll());
      } else if (k == LogicalKeyboardKey.keyK || k == LogicalKeyboardKey.keyF) {
        showToolSearch(context, this);
      } else if (k == LogicalKeyboardKey.arrowLeft) {
        apply((e) => e.moveBar(-1, select: shift));
      } else if (k == LogicalKeyboardKey.arrowRight) {
        apply((e) => e.moveBar(1, select: shift));
      } else {
        return false;
      }
      return true;
    }
    if (k == LogicalKeyboardKey.space) {
      _togglePlay();
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
      apply((e) => e.inputFret(f), sound: true);
      _fretCursor = e.cursor;
      return true;
    }
    final ch = (ev.character ?? '').toUpperCase();
    const steps = {'C': 0, 'D': 1, 'E': 2, 'F': 3, 'G': 4, 'A': 5, 'B': 6, 'H': 6};
    if (steps.containsKey(ch) && !hw.isAltPressed) {
      apply((e) => e.inputStep(steps[ch]!, addToChord: shift), sound: true);
      return true;
    }
    if (k == LogicalKeyboardKey.arrowLeft) {
      apply((e) => e.moveBeat(-1, select: shift));
    } else if (k == LogicalKeyboardKey.arrowRight) {
      apply((e) => e.moveBeat(1, select: shift));
    } else if (k == LogicalKeyboardKey.arrowUp) {
      apply((e) => shift ? e.transposeSelection(1) : e.moveString(1), sound: shift);
    } else if (k == LogicalKeyboardKey.arrowDown) {
      apply((e) => shift ? e.transposeSelection(-1) : e.moveString(-1), sound: shift);
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
      apply((e) => e.toggleTie(), sound: true);
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

  /// Angetippt: Cursor dorthin, mit „Stift setzt Noten“ auch eine Note.
  void _onEditTap(_PageHit hit) {
    final pen = _penNotes && hit.diatonic != null && hit.string == null;
    apply((e) {
      e.setCursor(hit.bar, hit.position, string: hit.string, select: HardwareKeyboard.instance.isShiftPressed);
      if (pen) e.inputDiatonic(hit.diatonic!);
    }, sound: pen);
  }

  /// Griffbrett angetippt: Ton auf den Cursor (weitere Saiten = Akkord).
  void _onFret(int string, int fret) {
    apply((e) {
      e.cursor = e.cursor.copyWith(string: string);
      e.inputFret(fret);
    }, sound: true);
  }

  @override
  void dispose() {
    _flushSave();
    _cursorTick.dispose();
    _player?.dispose();
    _preview.dispose();
    for (final p in _pictures ?? const <ui.Picture>[]) {
      p.dispose();
    }
    super.dispose();
  }

  // ───────────────────────── Aufbau ─────────────────────────

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    return Scaffold(
      backgroundColor: ScriviColors.pageSurround,
      body: SafeArea(
        child: Column(
          children: [
            _topBar(context),
            Expanded(child: _body()),
          ],
        ),
      ),
    ).withListen([?settings?.showTools, ?settings?.showFretboard, ?settings?.openToolGroups]);
  }

  Widget _body() {
    if (_error != null) {
      return EmptyState(
        icon: Icons.error_outline,
        title: tr('Das Stück lässt sich nicht öffnen', 'The piece can’t be opened'),
        text: problemText(_error!),
      );
    }
    final pages = _pages, pictures = _pictures, e = _editor;
    if (pages == null || pictures == null || e == null) return const Center(child: CircularProgressIndicator());
    final s = _settings;
    final showTools = s?.showTools.value ?? true;
    final showFretboard = (s?.showFretboard.value ?? true) && e.stringed;
    final open = {
      for (final g in ToolGroup.values)
        if ((s?.openToolGroups.value ?? const {'duration', 'guitar'}).contains(g.name)) g,
    };
    final c = context.scrivi;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showTools) ...[
          SizedBox(
            width: 4 * ToolButton.size + 3 * 4 + 20 + 2 * ToolButton.size + 8,
            child: ToolPanel(
              host: this,
              open: open,
              onToggleGroup: (g) {
                final names = {for (final x in open) x.name};
                names.contains(g.name) ? names.remove(g.name) : names.add(g.name);
                s?.setOpenToolGroups(names);
                setState(() {});
              },
            ),
          ),
          VerticalDivider(width: 1, thickness: 1, color: c.line),
        ],
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: _PagesViewer(
                  key: _viewer,
                  pages: pages,
                  pictures: pictures,
                  player: _player,
                  editor: e,
                  cursorTick: _cursorTick,
                  onEditTap: _onEditTap,
                  onEditKey: _onEditKey,
                ),
              ),
              if (showFretboard) ...[
                Divider(height: 1, thickness: 1, color: c.line),
                Fretboard(editor: e, onTap: _onFret),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Obere Leiste: zurück, Bereiche ein/aus, Rückgängig, Zoom; in der Mitte
  /// Abspielen und Anzeige; rechts Tempo, Schleife, Metronom, Einzähler,
  /// Mischpult, Ansicht, Suche.
  Widget _topBar(BuildContext context) {
    final c = context.scrivi;
    final e = _editor;
    final p = _player;
    final s = _settings;
    final scheme = Theme.of(context).colorScheme;
    Widget toggle(IconData icon, String tip, bool on, VoidCallback onTap) => IconButton(
      tooltip: tip,
      isSelected: on,
      style: IconButton.styleFrom(backgroundColor: on ? scheme.primaryContainer : null),
      icon: Icon(icon, size: 20, color: on ? scheme.onPrimaryContainer : null),
      onPressed: onTap,
    );
    // Rechts Platz für die Fensterknöpfe; an freien Stellen lässt sich das Fenster ziehen.
    return WindowDragArea(
      mouseOnly: true,
      doubleTapMaximizes: false,
      child: Container(
        height: 60,
        color: c.background,
        padding: EdgeInsets.only(left: 6, right: hasWindowButtons ? windowButtonsWidth : 6),
        child: LayoutBuilder(
          builder: (context, box) {
            final compact = box.maxWidth < 1100;
            final left = <Widget>[
              IconButton(
                tooltip: tr('Zur Bibliothek', 'Back to library'),
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              if (s != null) ...[
                toggle(
                  Icons.handyman_outlined,
                  tr('Werkzeuge ein/aus', 'Show/hide tools'),
                  s.showTools.value,
                  () => s.setShowTools(!s.showTools.value),
                ),
                if (_stringed)
                  toggle(
                    Icons.view_week_outlined,
                    tr('Griffbrett ein/aus', 'Show/hide fretboard'),
                    s.showFretboard.value,
                    () => s.setShowFretboard(!s.showFretboard.value),
                  ),
              ],
              const SizedBox(width: 4),
              IconButton(
                tooltip: tr('Rückgängig  (Strg+Z)', 'Undo  (Ctrl+Z)'),
                icon: const Icon(Icons.undo_rounded),
                onPressed: e != null && e.canUndo ? () => apply((e) => e.undo()) : null,
              ),
              IconButton(
                tooltip: tr('Wiederholen  (Strg+Y)', 'Redo  (Ctrl+Y)'),
                icon: const Icon(Icons.redo_rounded),
                onPressed: e != null && e.canRedo ? () => apply((e) => e.redo()) : null,
              ),
              if (!compact) ...[
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
            ];
            final center = <Widget>[
              IconButton(
                tooltip: tr('Zum Anfang', 'To the start'),
                icon: const Icon(Icons.skip_previous_rounded),
                onPressed: p == null
                    ? null
                    : () {
                        p.rewind();
                        apply((e) => e.setCursor(0, 0));
                      },
              ),
              if (p != null)
                ListenableBuilder(
                  listenable: p,
                  builder: (context, _) => SizedBox(
                    width: 44,
                    height: 44,
                    child: p.preparing
                        ? const Padding(padding: EdgeInsets.all(11), child: CircularProgressIndicator(strokeWidth: 3))
                        : IconButton.filled(
                            tooltip: p.playing
                                ? tr('Anhalten  (Leertaste)', 'Pause  (Space)')
                                : tr('Abspielen ab Cursor  (Leertaste)', 'Play from cursor  (Space)'),
                            icon: Icon(p.playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 28),
                            onPressed: _togglePlay,
                          ),
                  ),
                ),
              const SizedBox(width: 8),
              if (e != null && p != null) _display(context, e, p, compact),
            ];
            final right = <Widget>[
              if (p != null)
                ListenableBuilder(
                  listenable: p,
                  builder: (context, _) {
                    final t = TransportBar(player: p);
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _chip(
                          context,
                          '${(p.tempo * 100).round()} %',
                          tr('Tempo beim Abspielen', 'Playback tempo'),
                          p.tempo != 1,
                          () => t.tempoDialog(context),
                        ),
                        _chip(
                          context,
                          p.loop == null ? '⟲' : '⟲ ${p.loop!.$1 + 1}–${p.loop!.$2 + 1}',
                          tr('Schleife', 'Loop'),
                          p.loop != null,
                          () => t.loopDialog(context),
                        ),
                        toggle(
                          Icons.av_timer_rounded,
                          tr('Metronom', 'Metronome'),
                          p.metronome,
                          () => p.setMetronome(!p.metronome),
                        ),
                        _chip(context, '1·2', tr('Einzähler', 'Count-in'), p.countIn, () => p.setCountIn(!p.countIn)),
                        IconButton(
                          tooltip: tr('Mischpult', 'Mixer'),
                          icon: const Icon(Icons.tune_rounded, size: 20),
                          onPressed: () => t.mixer(context),
                        ),
                      ],
                    );
                  },
                ),
              if (_pages != null && _stringed)
                PopupMenuButton<ScoreView>(
                  tooltip: tr('Ansicht', 'View'),
                  initialValue: _view,
                  icon: const Icon(Icons.view_agenda_outlined, size: 20),
                  onSelected: _setView,
                  itemBuilder: (context) => [
                    for (final v in ScoreView.values)
                      CheckedPopupMenuItem(value: v, checked: v == _view, child: Text(_viewName(v))),
                  ],
                ),
              if (e != null)
                IconButton(
                  tooltip: tr('Werkzeug suchen  (Strg+K)', 'Find a tool  (Ctrl+K)'),
                  icon: const Icon(Icons.search_rounded),
                  onPressed: () => showToolSearch(context, this),
                ),
            ];
            return Row(
              children: [
                ...left,
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Row(mainAxisSize: MainAxisSize.min, children: center),
                      ),
                    ],
                  ),
                ),
                ...right,
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _chip(BuildContext context, String label, String tip, bool on, VoidCallback onTap) {
    final scheme = Theme.of(context).colorScheme;
    final c = context.scrivi;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Tooltip(
        message: tip,
        waitDuration: const Duration(milliseconds: 300),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? scheme.primaryContainer : c.cardHigh,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: on ? scheme.onPrimaryContainer : null,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Anzeige: Spur (zum Wechseln antippen), Takt, Zeit, Tempo, Taktart, Tonart.
  Widget _display(BuildContext context, core.ScoreEditor e, ScorePlayer p, bool compact) {
    final c = context.scrivi;
    final score = e.score;
    return ListenableBuilder(
      listenable: Listenable.merge([p, p.position, _cursorTick]),
      builder: (context, _) {
        final bar = p.playing ? p.location.$1 : e.cursor.bar;
        final mb = score.masterBars[bar.clamp(0, score.masterBars.length - 1)];
        double bpm = 120;
        for (final t in score.tempos) {
          if (t.bar <= bar) bpm = t.bpm;
        }
        final muted = TextStyle(fontSize: 12, color: c.muted, fontFeatures: const [FontFeature.tabularFigures()]);
        final strong = const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          fontFeatures: [FontFeature.tabularFigures()],
        );
        final trackLabel = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text('${_track + 1}. ${_trackName(_track)}', style: strong, overflow: TextOverflow.ellipsis),
            ),
            if (score.tracks.length > 1) Icon(Icons.arrow_drop_down, size: 18, color: c.muted),
          ],
        );
        return Container(
          constraints: BoxConstraints(minWidth: compact ? 160 : 300, maxWidth: compact ? 220 : 380),
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: c.line),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    score.tracks.length > 1
                        ? PopupMenuButton<int>(
                            tooltip: tr('Spur wählen', 'Choose track'),
                            initialValue: _track,
                            onSelected: (i) {
                              _track = i;
                              _editor?.track = i;
                              _engrave();
                              _cursorTick.value++;
                            },
                            itemBuilder: (context) => [
                              for (var i = 0; i < score.tracks.length; i++)
                                PopupMenuItem(value: i, child: Text('${i + 1}. ${_trackName(i)}')),
                            ],
                            child: trackLabel,
                          )
                        : trackLabel,
                    Text('${tr('Takt', 'Bar')} ${bar + 1} / ${score.masterBars.length}', style: muted),
                  ],
                ),
              ),
              if (!compact)
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${formatTime(p.position.value)} / ${formatTime(p.plan.duration)}', style: strong),
                    Text(
                      '♩ = ${bpm.round()} · ${mb.time.beats}/${mb.time.beatType} · ${keyName(mb.key)}',
                      style: muted,
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Tonart als Name, z. B. „G-Dur“ bzw. „G major“.
String keyName(core.KeySignature k) {
  const de = ['Ces', 'Ges', 'Des', 'As', 'Es', 'B', 'F', 'C', 'G', 'D', 'A', 'E', 'H', 'Fis', 'Cis'];
  const en = ['C♭', 'G♭', 'D♭', 'A♭', 'E♭', 'B♭', 'F', 'C', 'G', 'D', 'A', 'E', 'B', 'F♯', 'C♯'];
  final i = (k.fifths + 7).clamp(0, 14);
  return L10n.isEnglish ? '${en[i]} major' : '${de[i]}-Dur';
}

extension on Widget {
  /// Neu aufbauen, wenn sich eine der Einstellungen ändert.
  Widget withListen(List<Listenable> ls) =>
      ls.isEmpty ? this : ListenableBuilder(listenable: Listenable.merge(ls), builder: (_, _) => this);
}

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
    this.editor,
    this.cursorTick,
    this.onEditTap,
    this.onEditKey,
  });
  final List<core.PageDisplay> pages;
  final List<ui.Picture> pictures;
  final ScorePlayer? player;

  /// Bearbeiten: Cursor, Antippen, Tasten, Werkzeugleiste.
  final core.ScoreEditor? editor;
  final ValueNotifier<int>? cursorTick;
  final ValueChanged<_PageHit>? onEditTap;
  final bool Function(KeyEvent)? onEditKey;

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
    final hit = _hitAt(d.localPosition);
    if (hit != null) widget.onEditTap?.call(hit);
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
        return viewer;
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
    // Nur während des Abspielens; danach zeigt der Cursor die Stelle.
    if (!player.playing) return;
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
