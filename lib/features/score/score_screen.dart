import 'dart:async';
import 'dart:io';
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
import '../../app/mic_listener.dart';
import '../../app/theme.dart';
import '../../app/window_buttons.dart';

import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/files/recent_files.dart';
import '../../core/files/score_files.dart';
import '../../widgets/visuals.dart';

import 'edit_tools.dart';
import 'export_dialog.dart';
import 'fretboard.dart';
import 'inspector.dart';
import 'note_preview.dart';
import 'pen_gestures.dart';
import 'quick_input.dart';
import 'score_painter.dart';
import 'score_player.dart';
import 'tools.dart';
import 'track_dialogs.dart';
import 'track_lanes.dart';
import 'transport_bar.dart';

/// Ein Stück schreiben und ansehen: Werkzeuge links, Noten in der Mitte,
/// Griffbrett unten, oben Anzeige und Abspielen. Es gibt keinen eigenen
/// Bearbeiten-Modus: Der Cursor ist immer da.
class ScoreScreen extends StatefulWidget {
  const ScoreScreen({
    super.key,
    required this.path,
    this.active = true,
    this.onClose,
    this.onTitle,
    this.tabBar,
    this.onOpenPiece,
    this.onOpenPath,
    this.onNextTab,
  });

  /// Die Datei (auch ein Entwurf im Ordner „Entwürfe“ von Scrivi).
  final String path;

  /// Reiter: Dieses Stück ist gerade zu sehen (sonst angehalten, Mikrofon aus).
  final bool active;

  /// Reiter: Stück geschlossen (sonst geht es zurück zur Startseite).
  final VoidCallback? onClose;

  /// Reiter: Titel für die Reiterleiste.
  final ValueChanged<String>? onTitle;

  /// Reiterleiste unter der oberen Leiste (nur bei mehreren offenen Stücken).
  final Widget? tabBar;

  /// Weiteres Stück in einem neuen Reiter öffnen; nächster Reiter (+1/−1).
  final VoidCallback? onOpenPiece;
  final ValueChanged<int>? onNextTab;

  /// Reiter: eine bestimmte Datei in einem neuen Reiter öffnen.
  final ValueChanged<String>? onOpenPath;

  @override
  State<ScoreScreen> createState() => _ScoreScreenState();
}

/// Ein offenes Stück in einem Reiter: lässt sich von aussen schliessen.
abstract interface class ScoreTab {
  Future<void> leave();
}

class _ScoreScreenState extends State<ScoreScreen> implements ToolHost, ScoreTab {
  core.Score? _score;

  /// Datei, in die gespeichert wird. Bei Entwürfen und bei Dateien anderer
  /// Formate (z. B. Guitar Pro) braucht es erst „Speichern unter“.
  late String _path = widget.path;
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
  RecentFiles? _recent;

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
    _recent = RecentScope.maybeOf(context);
  }

  bool get _fullScore => _settings?.fullScore.value ?? false;

  /// Endlos-Zeile (nicht zusammen mit der Partitur).
  bool get _endless => !_fullScore && (_settings?.endless.value ?? false);
  bool get _transposed => _settings?.transposed.value ?? false;

  void _setTransposed(bool v) {
    _settings?.setTransposed(v);
    _engrave();
  }

  /// Seiten, Endlos-Zeile oder Partitur.
  void _setLayout(String v) {
    _settings?.setEndless(v == 'endless');
    _settings?.setFullScore(v == 'score');
    _engrave();
    WidgetsBinding.instance.addPostFrameCallback((_) => _viewer.currentState?.revealCursor());
  }

  bool get _stringed => _score != null && _score!.tracks.isNotEmpty && _score!.tracks[_track].staff.isStringed;

  void _setView(ScoreView v) {
    _view = v;
    _settings?.setScoreView(v);
    _engrave();
  }

  Future<void> _load() async {
    try {
      final score = await ScoreFiles.load(widget.path);
      if (!mounted) return;
      unawaited(_recent?.touch(widget.path, score));
      _score = score;
      _player = ScorePlayer(score)..onMixChanged = _onMix;
      _scheduleWarmUp(const Duration(seconds: 1));
      _editor = core.ScoreEditor(score, track: _track);
      _engrave();
    } catch (e, st) {
      ErrorLog.record(e, st, where: 'Stück öffnen: ${p.basename(widget.path)}');
      if (mounted) setState(() => _error = e);
    }
  }

  /// Die gewählte Spur setzen und als Bilder aufnehmen.
  void _engrave() {
    final score = _editor?.score ?? _score;
    if (score == null) return;
    try {
      final options = _layoutOptions;
      // Eingaben in der Ansicht „transponiert“ zurückrechnen
      _editor?.viewShift = _transposed ? score.tracks[_track].instrumentKey : 0;
      final layout = _fullScore && score.tracks.length > 1
          ? core.ScoreEngraver(score, options: options, measurer: FlutterTextMeasurer()).layout()
          : core.Engraver(score, trackIndex: _track, options: options, measurer: FlutterTextMeasurer()).layout();
      final pictures = layout.pages.map(PagePictures.record).toList();
      final old = _pictures;
      setState(() {
        _pages = layout.pages;
        _pictures = pictures;
      });
      _reportTitle();
      // Alte Bilder erst nach dem nächsten Bild freigeben.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final p in old ?? const <ui.Picture>[]) {
          p.dispose();
        }
      });
    } catch (e, st) {
      ErrorLog.record(e, st, where: 'Stück öffnen: ${p.basename(widget.path)}');
      if (mounted) setState(() => _error = e);
    }
  }

  core.LayoutOptions get _layoutOptions => core.LayoutOptions(
    showTab: _view != ScoreView.notation,
    showNotation: _view != ScoreView.tab,
    germanNoteNames: !L10n.isEnglish,
    endless: _endless,
    transposed: _transposed,
  );

  ScoreExport? get _export {
    final score = _editor?.score ?? _score;
    if (score == null) return null;
    return ScoreExport(score: score, track: _track, options: _layoutOptions, sourcePath: _path, fullScore: _fullScore);
  }

  @override
  Future<void> openPiece() async => widget.onOpenPiece?.call();

  /// Exportieren als PDF, MusicXML oder MIDI.
  @override
  Future<void> exportPiece() async => _export?.show(context);

  /// Drucken über das PDF-Programm des Systems.
  @override
  Future<void> printPiece() async => _export?.print(context);

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

  // ───────────────────────── Mikrofon ─────────────────────────

  MicListener? _mic;
  StreamSubscription<core.PitchReading>? _micSub;
  final _noteListener = core.NoteListener();

  /// Gerade gehörter Ton (für die Anzeige oben).
  final _heard = ValueNotifier<int?>(null);

  @override
  bool get micOn => _mic != null;

  @override
  Future<void> toggleMic() async {
    if (_mic != null) return _stopMic();
    final score = _score;
    if (score == null) return;
    // Tiefster Ton der Spur bestimmt, wie tief das Mikrofon hinhört (Bass: E1 = 41 Hz)
    final t = score.tracks[_track];
    final lowest = t.staff.isStringed ? t.staff.tuning.reduce(math.min) : 40;
    final minHz = (440.0 * math.pow(2, (lowest - 69) / 12) * 0.9).clamp(35.0, 70.0);
    final mic = MicListener(minFrequency: minHz);
    setState(() => _mic = mic);
    final err = await mic.start();
    if (!mounted) return;
    if (err != null) {
      setState(() => _mic = null);
      await mic.dispose();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            err == 'permission'
                ? tr(
                    'Scrivi darf das Mikrofon nicht benutzen (Einstellungen des Geräts).',
                    'Scrivi may not use the microphone (device settings).',
                  )
                : tr('Das Mikrofon lässt sich nicht einschalten.', 'The microphone cannot be switched on.'),
          ),
        ),
      );
      return;
    }
    _noteListener.reset();
    _micSub = mic.readings.listen(_onReading);
  }

  void _onReading(core.PitchReading r) {
    final midi = _noteListener.add(r);
    _heard.value = r.hasPitch && r.clarity > 0.85 ? r.midi : (r.level < 0.01 ? null : _heard.value);
    // Beim Abspielen nicht mitschreiben: das Mikrofon hört sonst Scrivi selbst
    if (midi == null || (_player?.playing ?? false)) return;
    apply((e) => e.inputHeard(midi));
  }

  Future<void> _stopMic() async {
    final mic = _mic;
    await _micSub?.cancel();
    _micSub = null;
    _heard.value = null;
    if (mounted) setState(() => _mic = null);
    await mic?.dispose();
  }

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
    // Das Mischpult gehört nicht zum Rückgängigmachen: die aktuellen Werte bleiben im Stück
    final p = _player;
    if (p != null && p.volume.length == e.score.tracks.length) {
      for (var i = 0; i < p.volume.length; i++) {
        e.setMix(i, p.mixOf(i));
      }
      e.setReverb(p.reverb);
    }
    _score = e.score;
    _engrave();
    unawaited(_player?.updateScore(e.score).then((_) => _scheduleWarmUp()));
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), _flushSave);
  }

  Timer? _warmTimer;

  /// Klang im Hintergrund vorbereiten, wenn eine Weile nichts geändert wurde:
  /// dann startet das Abspielen sofort.
  void _scheduleWarmUp([Duration after = const Duration(milliseconds: 1500)]) {
    _warmTimer?.cancel();
    _warmTimer = Timer(after, () {
      if (mounted) _player?.warmUp();
    });
  }

  /// Mischpult geändert: ins Stück übernehmen und sichern (ohne neu zu setzen).
  void _onMix(int track) {
    final e = _editor, p = _player;
    if (e == null || p == null) return;
    if (track < 0) {
      e.setReverb(p.reverb);
    } else {
      e.setMix(track, p.mixOf(track));
    }
    _score = e.score;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), _flushSave);
  }

  /// Noch nicht an einem selbst gewählten Ort gespeichert (Entwurf oder fremdes Format).
  bool get _unsaved => !ScoreFiles.isScrivi(_path) || (_recent?.isDraft(_path) ?? false);

  /// Ungespeicherte Änderungen jetzt sichern: in die Datei bzw. in den Entwurf.
  /// Eine Datei in fremdem Format wird nie überschrieben; beim ersten Ändern
  /// entsteht ein Entwurf, das Original bleibt unberührt.
  void _flushSave() {
    _saveTimer?.cancel();
    final e = _editor;
    final score = _score;
    if (score == null || e == null || e.revision == _savedRevision) return;
    final rev = e.revision;
    final prev = _saving ?? Future.value();
    _saving = prev.then((_) async {
      try {
        if (!ScoreFiles.isScrivi(_path)) {
          final recent = _recent;
          if (recent == null) return;
          _path = await recent.newDraft(score);
        } else {
          await ScoreFiles.writeScrivi(_path, score);
          await _recent?.touch(_path, score);
        }
        _savedRevision = rev;
        if (mounted) setState(() {});
      } catch (err, st) {
        ErrorLog.record(err, st, where: 'Speichern: ${p.basename(_path)}');
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(tr('Speichern ist fehlgeschlagen.', 'Saving failed.'))));
        }
      }
    });
  }

  /// Speichern: Ist das Stück schon eine eigene Datei, wird nur gesichert;
  /// sonst „Speichern unter“.
  @override
  Future<void> save() async {
    if (_unsaved) return saveAs();
    _flushSave();
    await _saving;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Gespeichert', 'Saved'))));
    }
  }

  /// Speichern unter: Ort und Name wählen (Android: Ordner „Scrivi“ in den Dokumenten).
  @override
  Future<void> saveAs() async {
    final score = _editor?.score ?? _score;
    final recent = _recent;
    if (score == null) return;
    _flushSave();
    await _saving;
    final wasDraft = recent?.isDraft(_path) ?? false;
    final base = score.info.title.trim().isNotEmpty
        ? ScoreFiles.safeName(score.info.title)
        : p.basenameWithoutExtension(widget.path);
    final name = '$base.scrivi';
    String target;
    try {
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        final dir = wasDraft ? await _documentsDir() : p.dirname(_path);
        final loc = await getSaveLocation(
          suggestedName: name,
          initialDirectory: dir,
          acceptedTypeGroups: [
            const XTypeGroup(label: 'Scrivi', extensions: ['scrivi']),
          ],
          confirmButtonText: tr('Speichern', 'Save'),
        );
        if (loc == null) return;
        target = loc.path.toLowerCase().endsWith('.scrivi') ? loc.path : '${loc.path}.scrivi';
      } else {
        final dir = p.join(await _documentsDir() ?? Directory.systemTemp.path, 'Scrivi');
        target = await ScoreFiles.uniquePath(dir, name);
      }
      await ScoreFiles.writeScrivi(target, score);
      final old = _path;
      _path = target;
      _reportTitle();
      _savedRevision = _editor?.revision ?? _savedRevision;
      await recent?.touch(target, score);
      if (wasDraft) await recent?.remove(old);
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(tr('Gespeichert: $target', 'Saved: $target'))));
      }
    } catch (err, st) {
      ErrorLog.record(err, st, where: 'Speichern unter');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(tr('Speichern ist fehlgeschlagen.', 'Saving failed.'))));
      }
    }
  }

  /// Dokumente-Ordner; fehlt er, der Benutzerordner (oder null: der Dialog entscheidet).
  Future<String?> _documentsDir() async {
    try {
      return (await getApplicationDocumentsDirectory()).path;
    } catch (_) {
      return Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
    }
  }

  /// Beim Verlassen eines nie gespeicherten Stücks nachfragen. Der Entwurf
  /// bleibt bei „Später“ unter „Zuletzt geöffnet“ erhalten.
  Future<void> _leave() async {
    _flushSave();
    await _saving;
    final recent = _recent;
    if (mounted && recent != null && recent.isDraft(_path)) {
      final foreign = !ScoreFiles.isScrivi(widget.path);
      final choice = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(tr('Noch nicht gespeichert', 'Not saved yet')),
          content: Text(
            foreign
                ? tr(
                    'Deine Änderungen liegen in einem Entwurf, das Original bleibt unverändert. Jetzt als Scrivi-Datei speichern?',
                    'Your changes are kept in a draft; the original stays unchanged. Save as a Scrivi file now?',
                  )
                : tr(
                    'Das Stück ist als Entwurf gesichert und bleibt unter „Zuletzt geöffnet“. Jetzt an einem Ort deiner Wahl speichern?',
                    'The piece is kept as a draft under “Recently opened”. Save it somewhere of your choice now?',
                  ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, 'later'), child: Text(tr('Später', 'Later'))),
            FilledButton(onPressed: () => Navigator.pop(context, 'save'), child: Text(tr('Speichern …', 'Save …'))),
          ],
        ),
      );
      if (choice == null) return;
      if (choice == 'save') await saveAs();
    }
    if (!mounted) return;
    final close = widget.onClose;
    if (close != null) {
      await _player?.pause();
      close();
    } else {
      Navigator.of(context).pop();
    }
  }

  /// Reiter wird geschlossen (Kreuz oder Strg+W): wie Zurück.
  @override
  Future<void> leave() => _leave();

  String? _reportedTitle;

  /// Titel für den Reiter melden, wenn er sich geändert hat.
  void _reportTitle() {
    final cb = widget.onTitle;
    if (cb == null) return;
    final score = _editor?.score ?? _score;
    final title = score != null && score.info.title.trim().isNotEmpty
        ? score.info.title.trim()
        : p.basenameWithoutExtension(_path);
    if (title == _reportedTitle) return;
    _reportedTitle = title;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) cb(title);
    });
  }

  @override
  void didUpdateWidget(ScoreScreen old) {
    super.didUpdateWidget(old);
    if (old.active && !widget.active) {
      // In einen anderen Reiter gewechselt: nichts spielt oder hört im Verborgenen weiter
      unawaited(_player?.pause());
      if (_mic != null) unawaited(_stopMic());
      _flushSave();
    }
  }

  /// Datei öffnen (Dateidialog) und in einem neuen Reiter zeigen.
  Future<void> _openFile() async {
    final file = await openFile(
      acceptedTypeGroups: [XTypeGroup(label: tr('Notendateien', 'Music files'), extensions: ScoreFiles.readable)],
      confirmButtonText: tr('Öffnen', 'Open'),
    );
    if (file == null || !mounted) return;
    final open = widget.onOpenPath;
    if (open != null) {
      open(file.path);
    } else {
      unawaited(Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ScoreScreen(path: file.path))));
    }
  }

  /// Menü „Datei“ oben links: Neu, Öffnen, Zuletzt geöffnet, Speichern, Exportieren, Drucken …
  Widget _fileMenu(BuildContext context) {
    final c = context.scrivi;
    final recent = (_recent?.entries ?? const <RecentEntry>[]).where((e) => !p.equals(e.path, _path)).take(10).toList();
    Widget item(String label, IconData icon, String? keys, VoidCallback? onPressed) => MenuItemButton(
      leadingIcon: Icon(icon, size: 18),
      trailingIcon: keys == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(left: 28),
              child: Text(keys, style: TextStyle(fontSize: 12, color: c.muted)),
            ),
      onPressed: onPressed,
      child: Text(label),
    );
    return MenuAnchor(
      alignmentOffset: const Offset(0, 4),
      menuChildren: [
        item(tr('Neues Stück …', 'New piece …'), Icons.note_add_outlined, tr('Strg+N', 'Ctrl+N'), widget.onOpenPiece),
        item(tr('Öffnen …', 'Open …'), Icons.folder_open_outlined, tr('Strg+O', 'Ctrl+O'), _openFile),
        SubmenuButton(
          leadingIcon: const Icon(Icons.history_rounded, size: 18),
          menuChildren: [
            if (recent.isEmpty)
              MenuItemButton(onPressed: null, child: Text(tr('Noch nichts', 'Nothing yet')))
            else
              for (final r in recent)
                MenuItemButton(
                  onPressed: widget.onOpenPath == null ? null : () => widget.onOpenPath!(r.path),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: Text(r.displayTitle, overflow: TextOverflow.ellipsis),
                  ),
                ),
          ],
          child: Text(tr('Zuletzt geöffnet', 'Open recent')),
        ),
        const Divider(height: 1),
        item(tr('Speichern', 'Save'), Icons.save_outlined, tr('Strg+S', 'Ctrl+S'), save),
        item(
          tr('Speichern unter …', 'Save as …'),
          Icons.save_as_outlined,
          tr('Strg+Umschalt+S', 'Ctrl+Shift+S'),
          saveAs,
        ),
        const Divider(height: 1),
        item(
          tr('Exportieren (PDF, MusicXML, MIDI) …', 'Export (PDF, MusicXML, MIDI) …'),
          Icons.ios_share_rounded,
          tr('Strg+E', 'Ctrl+E'),
          exportPiece,
        ),
        item(tr('Drucken …', 'Print …'), Icons.print_outlined, tr('Strg+P', 'Ctrl+P'), printPiece),
        const Divider(height: 1),
        item(tr('Angaben zum Stück …', 'Piece information …'), Icons.info_outline_rounded, null, editTitle),
        const Divider(height: 1),
        item(tr('Schliessen', 'Close'), Icons.close_rounded, tr('Strg+W', 'Ctrl+W'), _leave),
      ],
      builder: (context, controller, _) => TextButton(
        onPressed: () => controller.isOpen ? controller.close() : controller.open(),
        style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.onSurface),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [Text(tr('Datei', 'File')), const Icon(Icons.arrow_drop_down_rounded, size: 20)],
        ),
      ),
    );
  }

  /// Titel und Speicherstand oben links.
  Widget _titleBlock(BuildContext context, bool compact) {
    final c = context.scrivi;
    final score = _editor?.score ?? _score;
    final title = score != null && score.info.title.isNotEmpty ? score.info.title : p.basenameWithoutExtension(_path);
    final state = _unsaved ? tr('nicht gespeichert', 'not saved') : p.basename(_path);
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: compact ? 130 : 210),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            Text(
              state,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: _unsaved ? Theme.of(context).colorScheme.primary : c.muted),
            ),
          ],
        ),
      ),
    );
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
    final r = await askScoreInfo(context, editor.score.info);
    if (r != null) apply((e) => e.setScoreInfo(r));
  }

  @override
  Future<void> editTranspose() async {
    final v = await askTranspose(context);
    if (v != null && v != 0) apply((e) => e.transposeAll(v));
  }

  // ───────────────────────── Spuren ─────────────────────────

  /// Andere Spur zeigen und darin schreiben.
  void _selectTrack(int i) {
    if (i == _track || _score == null || i >= _score!.tracks.length) return;
    _track = i;
    _editor?.track = i;
    // In der Partitur bleibt das Bild, nur der Cursor wechselt die Zeile
    if (_fullScore && _score!.tracks.length > 1) {
      _editor?.viewShift = _transposed ? _score!.tracks[i].instrumentKey : 0;
      setState(() {});
    } else {
      _engrave();
    }
    _cursorTick.value++;
  }

  /// In den Spur-Bahnen angetippt: Spur wählen, Cursor dorthin.
  void _onLaneSelect(int track, int bar, double position) {
    _selectTrack(track);
    apply((e) => e.setCursor(bar, position));
  }

  @override
  Future<void> editTrackName(int track) async {
    final t = editor.score.tracks[track];
    final r = await askText(context, title: tr('Name der Spur', 'Track name'), initial: t.name);
    if (r != null && r.$1.trim().isNotEmpty) apply((e) => e.setTrackInfo(track, name: r.$1));
  }

  @override
  Future<void> editTrackSound(int track) async {
    final v = await askSound(context, editor.score.tracks[track].program);
    if (v != null) apply((e) => e.setTrackInfo(track, program: v));
  }

  @override
  Future<void> editTuning() async {
    final t = editor.score.tracks[editor.track];
    if (!t.staff.isStringed) return;
    final r = await askTuning(context, t.staff);
    if (r != null) apply((e) => e.setTuning(r.tuning, capo: r.capo, keepFrets: r.keepFrets));
  }

  @override
  Future<void> editInstrumentKey(int track) async {
    final t = editor.score.tracks[track];
    final octave = t.bars.isNotEmpty && t.bars.first.clef == core.Clef.treble8vb ? t.transposeSemitones : 0;
    final v = await askInstrumentKey(context, t.instrumentKey, octaveInClef: octave);
    if (v == null) return;
    apply((e) => e.setTrackInfo(track, instrumentKey: v));
    if (v != 0 && !_transposed && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              'Gespeichert. Sichtbar wird es unter Ansicht → Transponiert.',
              'Saved. It shows under View → Transposed.',
            ),
          ),
          action: SnackBarAction(label: tr('Einschalten', 'Turn on'), onPressed: () => _setTransposed(true)),
        ),
      );
    }
  }

  @override
  Future<void> addTrack() => _addTrack();

  Future<void> _addTrack({Offset? at}) async {
    final kinds = core.NewPieceKind.values;
    core.NewPieceKind? kind;
    if (at != null) {
      kind = await showMenu<core.NewPieceKind>(
        context: context,
        position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx + 1, at.dy + 1),
        items: [for (final k in kinds) PopupMenuItem(value: k, child: Text(newTrackName(k)))],
      );
    } else {
      kind = await showDialog<core.NewPieceKind>(
        context: context,
        builder: (context) => SimpleDialog(
          title: Text(tr('Spur hinzufügen', 'Add track')),
          children: [
            for (final k in kinds)
              SimpleDialogOption(onPressed: () => Navigator.pop(context, k), child: Text(newTrackName(k))),
          ],
        ),
      );
    }
    if (kind == null) return;
    apply((e) => e.addTrack(kind!));
    _track = editor.track;
    _engrave();
  }

  Future<void> _removeTrack(int i) async {
    final t = editor.score.tracks[i];
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Spur löschen?', 'Delete track?')),
        content: Text(
          tr(
            '„${t.name}“ wird mit allen Noten gelöscht. Rückgängig geht mit Strg+Z.',
            '“${t.name}” is deleted with all its notes. Undo with Ctrl+Z.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Abbrechen', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('Löschen', 'Delete'))),
        ],
      ),
    );
    if (ok != true) return;
    _player?.trackRemoved(i);
    apply((e) => e.removeTrack(i));
    _track = editor.track;
    _engrave();
  }

  Future<void> _trackMenu(int i, Offset at) async {
    final t = editor.score.tracks[i];
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx + 1, at.dy + 1),
      items: [
        PopupMenuItem(value: 'name', child: Text(tr('Umbenennen …', 'Rename …'))),
        PopupMenuItem(value: 'sound', child: Text(tr('Klang …', 'Sound …'))),
        if (t.staff.isStringed)
          PopupMenuItem(value: 'tuning', child: Text(tr('Stimmung und Kapo …', 'Tuning and capo …'))),
        if (editor.score.tracks.length > 1)
          PopupMenuItem(value: 'delete', child: Text(tr('Spur löschen …', 'Delete track …'))),
      ],
    );
    switch (choice) {
      case 'name':
        await editTrackName(i);
      case 'sound':
        await editTrackSound(i);
      case 'tuning':
        _selectTrack(i);
        await editTuning();
      case 'delete':
        await _removeTrack(i);
    }
  }

  // ───────────────────────── Schnell-Eingaben ─────────────────────────

  List<core.StrumPattern> get _patterns =>
      editor.stringed ? core.StrumPattern.forTime(_bar.time) : const <core.StrumPattern>[];

  void _info(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Future<void> quickChords() async {
    final r = await askChordLine(context, fromBar: editor.cursor.bar, patterns: _patterns);
    if (r == null) return;
    (int, int)? range;
    apply((e) => range = e.setChordLine(r.text));
    final p = r.pattern, rg = range;
    if (p != null && rg != null) apply((e) => e.applyPattern(p, rg.$1, rg.$2), sound: true);
  }

  @override
  Future<void> quickPattern() async {
    final e = editor;
    if (!e.stringed) return;
    final sel = e.selection;
    var from = sel?.$1.bar ?? e.cursor.bar, to = sel?.$2.bar ?? e.cursor.bar;
    if (sel == null) {
      // Ohne Auswahl: bis zum Ende des Formteils am Cursor
      for (final (_, a, b) in e.sections) {
        if (from >= a && from <= b) to = b;
      }
      if (to == from && e.sections.isEmpty) to = e.score.masterBars.length - 1;
    }
    final r = await askPattern(context, patterns: _patterns, from: from, to: to, bars: e.score.masterBars.length);
    if (r == null) return;
    final missing = [
      for (var b = r.$2; b <= r.$3; b++)
        if (e.chordAt(b, e.barLength(b)) == null) b,
    ];
    apply((e) => e.applyPattern(r.$1, r.$2, r.$3), sound: true);
    if (missing.isNotEmpty) {
      _info(
        tr(
          'Takte ohne Akkord blieben, wie sie sind. Zuerst Akkorde setzen (Akkordzeile).',
          'Bars without a chord were left as they are. Set chords first (chord line).',
        ),
      );
    }
  }

  @override
  Future<void> quickLyrics() async {
    final r = await askLyricsText(context, fromBar: editor.cursor.bar);
    if (r == null) return;
    var n = 0;
    apply((e) => n = e.setLyricsText(r.$1, line: r.$2));
    final total = core.ScoreEditor.parseLyrics(r.$1).length;
    _info(
      n < total
          ? tr(
              '$n von $total Silben verteilt: Es hat nicht mehr Noten.',
              '$n of $total syllables placed: there are no more notes.',
            )
          : tr('$n Silben verteilt.', '$n syllables placed.'),
    );
  }

  @override
  Future<void> quickSection() async {
    final sections = editor.sections;
    if (sections.isEmpty) {
      _info(
        tr(
          'Noch keine Formteile. Zuerst einen setzen (Takt → Formteil).',
          'No sections yet. Set one first (Bar → Section).',
        ),
      );
      return;
    }
    final r = await askSectionCopy(
      context,
      sections: sections,
      cursorBar: editor.cursor.bar,
      bars: editor.score.masterBars.length,
    );
    if (r != null) apply((e) => e.copyBars(r.$1, r.$2, r.$3));
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
      } else if (k == LogicalKeyboardKey.keyS) {
        shift ? saveAs() : save();
      } else if (k == LogicalKeyboardKey.keyO) {
        _openFile();
      } else if (k == LogicalKeyboardKey.keyN && widget.onOpenPiece != null) {
        widget.onOpenPiece!();
      } else if (k == LogicalKeyboardKey.keyW && widget.onClose != null) {
        _leave();
      } else if (k == LogicalKeyboardKey.tab && widget.onNextTab != null) {
        widget.onNextTab!(shift ? -1 : 1);
      } else if (k == LogicalKeyboardKey.keyE) {
        exportPiece();
      } else if (k == LogicalKeyboardKey.keyP) {
        printPiece();
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
    } else if (ch == 'M') {
      toggleMic();
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

  /// Angetippt: Cursor dorthin; schreiben Maus und Finger wie der Stift, auch eine Note.
  void _onEditTap(_PageHit hit) {
    if (hit.track != null) _selectTrack(hit.track!);
    if (_penNotes && hit.diatonic != null && hit.string == null) return _onPen(PenStroke.tap, hit, null);
    apply(
      (e) => e.setCursor(hit.bar, hit.position, string: hit.string, select: HardwareKeyboard.instance.isShiftPressed),
    );
  }

  /// Stift: antippen setzt eine Note (auf einer Note: Akkordton dazu), waagrechter
  /// Strich wählt aus, Durchkritzeln oder Radierer löscht, Strich nach oben/unten
  /// verschiebt um einen Halbton.
  void _onPen(PenStroke kind, _PageHit from, _PageHit? to) {
    if (from.track != null) _selectTrack(from.track!);
    final b = to ?? from;
    final (x, y) = from.bar < b.bar || (from.bar == b.bar && from.position <= b.position) ? (from, b) : (b, from);
    void range(core.ScoreEditor e) {
      e.setCursor(x.bar, x.position, string: x.string);
      e.setCursor(y.bar, y.position, string: y.string, select: true);
    }

    switch (kind) {
      case PenStroke.tap:
        final d = from.diatonic;
        apply((e) {
          e.setCursor(from.bar, from.position, string: from.string);
          if (d != null) e.penNote(d);
        }, sound: d != null);
      case PenStroke.line:
        apply(range);
      case PenStroke.scribble:
        apply((e) {
          range(e);
          // Einzelner Ton in der Tabulatur: nur die Saite, sonst der ganze Schlag
          if (to == null && from.string != null) e.anchor = null;
          e.toRest();
          e.anchor = null;
        });
      case PenStroke.flickUp || PenStroke.flickDown:
        apply((e) {
          e.setCursor(from.bar, from.position, string: from.string);
          e.transposeSelection(kind == PenStroke.flickUp ? 1 : -1);
        }, sound: true);
      case PenStroke.none:
        break;
    }
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
    _warmTimer?.cancel();
    _micSub?.cancel();
    _mic?.dispose();
    _heard.dispose();
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
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && widget.active) _leave();
      },
      child: Scaffold(
        backgroundColor: ScriviColors.pageSurround,
        body: SafeArea(
          child: Column(
            children: [
              _topBar(context),
              ?widget.tabBar,
              Expanded(child: _body()),
            ],
          ),
        ),
      ),
    ).withListen([
      ?settings?.showTools,
      ?settings?.showFretboard,
      ?settings?.openToolGroups,
      ?settings?.showTracks,
      ?settings?.showInspector,
    ]);
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
        if ((s?.openToolGroups.value ?? const {'duration', 'guitar', 'quick'}).contains(g.name)) g,
    };
    final showTracks = s?.showTracks.value ?? true;
    final showInspector = s?.showInspector.value ?? true;
    final c = context.scrivi;
    final main = Row(
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
                  endless: _endless,
                  pages: pages,
                  pictures: pictures,
                  player: _player,
                  editor: e,
                  cursorTick: _cursorTick,
                  onEditTap: _onEditTap,
                  onEditKey: _onEditKey,
                  onPen: _onPen,
                  penWrites: _penNotes,
                ),
              ),
              if (showFretboard) ...[
                Divider(height: 1, thickness: 1, color: c.line),
                Fretboard(editor: e, onTap: _onFret),
              ],
            ],
          ),
        ),
        if (showInspector) ...[
          VerticalDivider(width: 1, thickness: 1, color: c.line),
          Container(
            width: Inspector.width,
            color: c.card,
            child: Inspector(host: this, player: _player, cursorTick: _cursorTick),
          ),
        ],
      ],
    );
    if (!showTracks) return main;
    return Column(
      children: [
        Expanded(child: main),
        Divider(height: 1, thickness: 1, color: c.line),
        TrackLanes(
          maxLanes: MediaQuery.sizeOf(context).height < 800 ? 3 : 4,
          editor: e,
          player: _player,
          cursorTick: _cursorTick,
          onSelect: _onLaneSelect,
          onTrackMenu: _trackMenu,
          onAddTrack: (at) => _addTrack(at: at),
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
            final compact = box.maxWidth < 1280;
            final left = <Widget>[
              IconButton(
                tooltip: tr('Zur Startseite', 'Back to start'),
                icon: const Icon(Icons.arrow_back),
                onPressed: _leave,
              ),
              _fileMenu(context),
              _titleBlock(context, compact),
              IconButton(
                tooltip: _unsaved
                    ? tr('Speichern unter …  (Strg+S)', 'Save as …  (Ctrl+S)')
                    : tr('Speichern  (Strg+S)', 'Save  (Ctrl+S)'),
                isSelected: _unsaved,
                style: IconButton.styleFrom(backgroundColor: _unsaved ? scheme.primaryContainer : null),
                icon: Icon(Icons.save_outlined, color: _unsaved ? scheme.onPrimaryContainer : null),
                onPressed: save,
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
                toggle(
                  Icons.table_rows_outlined,
                  tr('Spuren ein/aus', 'Show/hide tracks'),
                  s.showTracks.value,
                  () => s.setShowTracks(!s.showTracks.value),
                ),
                toggle(
                  Icons.view_sidebar_outlined,
                  tr('Eigenschaften ein/aus', 'Show/hide properties'),
                  s.showInspector.value,
                  () => s.setShowInspector(!s.showInspector.value),
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
              if (e != null && p != null) Flexible(child: _display(context, e, p, compact)),
            ];
            final right = <Widget>[
              if (_mic != null)
                ValueListenableBuilder<int?>(
                  valueListenable: _heard,
                  builder: (context, m, _) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ActionChip(
                      avatar: Icon(Icons.mic_rounded, size: 18, color: Theme.of(context).colorScheme.error),
                      label: Text(
                        m == null ? tr('Ich höre zu …', 'Listening …') : '${stringNoteName(m)}${m ~/ 12 - 1}',
                      ),
                      tooltip: tr('Mikrofon ausschalten  (M)', 'Switch the microphone off  (M)'),
                      onPressed: toggleMic,
                    ),
                  ),
                ),
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
              if (_pages != null)
                PopupMenuButton<Object>(
                  tooltip: tr('Ansicht', 'View'),
                  icon: Icon(_endless ? Icons.view_column_outlined : Icons.view_agenda_outlined, size: 20),
                  onSelected: (v) => v is ScoreView
                      ? _setView(v)
                      : (v == 'transposed' ? _setTransposed(!_transposed) : _setLayout(v as String)),
                  itemBuilder: (context) => [
                    CheckedPopupMenuItem(
                      value: 'pages',
                      checked: !_endless && !_fullScore,
                      child: Text(tr('Seiten (eine Spur)', 'Pages (one track)')),
                    ),
                    CheckedPopupMenuItem(
                      value: 'score',
                      checked: _fullScore,
                      child: Text(tr('Partitur (alle Spuren)', 'Full score (all tracks)')),
                    ),
                    CheckedPopupMenuItem(
                      value: 'endless',
                      checked: _endless,
                      child: Text(tr('Endlos (eine lange Zeile)', 'Endless (one long line)')),
                    ),
                    const PopupMenuDivider(),
                    CheckedPopupMenuItem(
                      value: 'transposed',
                      checked: _transposed,
                      child: Text(tr('Transponiert (wie die Musiker lesen)', 'Transposed (as the players read)')),
                    ),
                    if (_stringed) ...[
                      const PopupMenuDivider(),
                      for (final v in ScoreView.values)
                        CheckedPopupMenuItem(value: v, checked: v == _view, child: Text(_viewName(v))),
                    ],
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
          constraints: BoxConstraints(maxWidth: compact ? 240 : 380),
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
                            onSelected: _selectTrack,
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

extension on Widget {
  /// Neu aufbauen, wenn sich eine der Einstellungen ändert.
  Widget withListen(List<Listenable> ls) =>
      ls.isEmpty ? this : ListenableBuilder(listenable: Listenable.merge(ls), builder: (_, _) => this);
}

/// Angetippte Stelle: Takt, Stelle im Takt (ganze Noten), Saite bzw. Stammton.
class _PageHit {
  const _PageHit(this.bar, this.position, this.string, this.diatonic, [this.track]);
  final int bar;
  final double position;
  final int? string;
  final int? diatonic;

  /// Spur der Zeile (nur in der Partitur).
  final int? track;
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
    this.onPen,
    this.penWrites = false,
    this.endless = false,
  });
  final List<core.PageDisplay> pages;

  /// Eine einzige lange Zeile: waagrecht blättern.
  final bool endless;
  final List<ui.Picture> pictures;
  final ScorePlayer? player;

  /// Bearbeiten: Cursor, Antippen, Tasten, Werkzeugleiste.
  final core.ScoreEditor? editor;
  final ValueNotifier<int>? cursorTick;
  final ValueChanged<_PageHit>? onEditTap;
  final bool Function(KeyEvent)? onEditKey;

  /// Strich mit dem Stift (Radierer = Durchkritzeln); [to] beim Bereich.
  final void Function(PenStroke kind, _PageHit from, _PageHit? to)? onPen;

  /// Die Maus schreibt wie der Stift (statt die Seiten zu verschieben).
  final bool penWrites;

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
  double _contentWidth = 0;

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

  /// In der Endlos-Zeile lässt sich auch verkleinern (mehr Takte auf einmal).
  double get _minScale => widget.endless ? 0.5 : 1.0;
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
    _inkTick.dispose();
    super.dispose();
  }

  /// Beim Abspielen mitblättern: Kommt die Markierung in eine Zeile, die nicht
  /// ganz zu sehen ist, wird sie oben ins Bild gerückt.
  void _follow() {
    final player = widget.player;
    if (player == null || !player.playing || _pageTops.isEmpty) return;
    final (bar, pos) = player.location;
    if (widget.endless) {
      // Waagrecht mitlaufen: die Stelle bleibt im linken Drittel
      final page = widget.pages.first;
      final sys = page.systems.isEmpty ? null : page.systems.first;
      final x = sys?.xAt(bar, pos);
      if (x == null) return;
      final k = _pageW / page.width;
      final vx = (_pageLeft + x * k) * _scale + _offset.dx;
      if (vx < _viewport.width * 0.1 || vx > _viewport.width * 0.8) {
        _fling.stop();
        _set(_scale, Offset(_offset.dx - vx + _viewport.width * 0.2, _offset.dy));
      }
      return;
    }
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

  // ───────────────────────── Stift ─────────────────────────

  int? _penPointer;
  bool _eraser = false;
  final _ink = <Offset>[];
  final _inkTick = ValueNotifier(0);

  bool _isPen(PointerDownEvent e) {
    if (widget.editor == null || widget.onPen == null) return false;
    return switch (e.kind) {
      PointerDeviceKind.stylus || PointerDeviceKind.invertedStylus => true,
      PointerDeviceKind.mouse => widget.penWrites && e.buttons & kPrimaryMouseButton != 0,
      _ => false,
    };
  }

  void _onPointerDown(PointerDownEvent e) {
    if (_penPointer != null || !_isPen(e)) return;
    _fling.stop();
    _focus.requestFocus();
    _penPointer = e.pointer;
    _eraser = e.kind == PointerDeviceKind.invertedStylus || e.buttons & kSecondaryStylusButton != 0;
    _ink
      ..clear()
      ..add(e.localPosition);
    _inkTick.value++;
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (e.pointer != _penPointer) return;
    if (e.buttons & kSecondaryStylusButton != 0) _eraser = true;
    _ink.add(e.localPosition);
    _inkTick.value++;
  }

  void _onPointerUp(PointerUpEvent e) {
    if (e.pointer != _penPointer) return;
    _penPointer = null;
    final pts = List.of(_ink);
    _ink.clear();
    _inkTick.value++;
    var kind = classifyStroke(pts);
    if (_eraser) kind = kind == PenStroke.tap ? PenStroke.tap : PenStroke.scribble;
    final onPen = widget.onPen;
    if (kind == PenStroke.none || onPen == null || pts.isEmpty) return;
    if (kind == PenStroke.scribble) {
      // Von ganz links bis ganz rechts
      var l = pts.first, r = pts.first;
      for (final p in pts) {
        if (p.dx < l.dx) l = p;
        if (p.dx > r.dx) r = p;
      }
      final a = _hitAt(l, snap: 1), b = _hitAt(r, snap: -1);
      if (a != null) onPen(kind, a, b);
      return;
    }
    if (kind == PenStroke.line) {
      final (l, r) = pts.first.dx <= pts.last.dx ? (pts.first, pts.last) : (pts.last, pts.first);
      final a = _hitAt(l, snap: 1);
      if (a != null) onPen(kind, a, _hitAt(r, snap: -1));
      return;
    }
    final a = _hitAt(pts.first);
    if (a == null) return;
    if (_eraser) {
      onPen(PenStroke.scribble, a, null);
    } else {
      onPen(kind, a, null);
    }
  }

  void _onPointerCancel(PointerCancelEvent e) {
    if (e.pointer != _penPointer) return;
    _penPointer = null;
    _ink.clear();
    _inkTick.value++;
  }

  /// Angetippter Takt: Fensterpunkt → Seite → Zeile → Takt.
  void _onTapUp(TapUpDetails d) {
    _focus.requestFocus();
    final hit = _hitAt(d.localPosition);
    if (hit != null) widget.onEditTap?.call(hit);
  }

  void _set(double scale, Offset offset) {
    final w = _viewport.width, h = _viewport.height;
    final contentW = _contentWidth * scale, contentH = _contentHeight * scale;
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

  void reset() => _set(1, Offset(widget.endless ? _offset.dx / _scale : 0, _offset.dy / _scale));

  void _onSignal(PointerSignalEvent e) {
    if (e is PointerScrollEvent) {
      GestureBinding.instance.pointerSignalResolver.register(e, (event) {
        final s = event as PointerScrollEvent;
        if (HardwareKeyboard.instance.isControlPressed) {
          zoomBy(s.scrollDelta.dy < 0 ? 1.1 : 1 / 1.1, s.localPosition);
        } else if (HardwareKeyboard.instance.isShiftPressed || widget.endless) {
          scrollBy(0, s.scrollDelta.dy + s.scrollDelta.dx);
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

  /// Fensterpunkt → Takt, Stelle, Saite bzw. Stammton. [snap] für Bereiche:
  /// 1 = der erste Schlag ab dieser Stelle (linkes Ende), -1 = der letzte bis
  /// hierher (rechtes Ende), 0 = der nächste.
  _PageHit? _hitAt(Offset local, {int snap = 0}) {
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
        // Nächster Schlag nach x (bei Bereichen nur Schläge innerhalb)
        var pos = 0.0, d = double.infinity;
        for (final (onset, bx) in b.beats) {
          if (snap > 0 && bx < x - 1.2 || snap < 0 && bx > x + 1.2) continue;
          if ((bx - x).abs() < d) {
            d = (bx - x).abs();
            pos = onset;
          }
        }
        var bar = b.bar;
        if (d == double.infinity) {
          // Kein Schlag auf dieser Seite der Stelle: ab dem nächsten bzw. bis zum vorigen Takt
          if (snap > 0 && bar + 1 < widget.editor!.score.masterBars.length) {
            bar++;
            pos = 0;
          } else if (snap < 0 && bar > 0) {
            bar--;
            pos = 1e6;
          }
        }
        final tabTop = best.tabTop;
        final inTab = tabTop != null && y > tabTop - best.tabSpacing && y < tabTop + best.strings * best.tabSpacing;
        return _PageHit(bar, pos, inTab ? best.stringAt(y) : null, inTab ? null : best.diatonicAt(y), best.track);
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
        if (sys.track != null && sys.track != e.track) continue;
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
        var pageW = math.min(box.maxWidth - 2 * _gap, 1100.0);
        if (widget.endless && widget.pages.isNotEmpty) {
          // Gleicher Massstab wie eine A4-Seite, nur viel breiter
          pageW = widget.pages.first.width * pageW / const core.LayoutOptions().pageWidth;
        }
        final heights = widget.pages.map((p) => pageW * p.height / p.width).toList();
        _contentHeight = math.max(heights.fold(_gap, (s, h) => s + h + _gap), box.maxHeight);
        _contentWidth = math.max(box.maxWidth, pageW + 2 * _gap);
        _pageW = pageW;
        _pageLeft = (_contentWidth - pageW) / 2;
        final tops = <double>[];
        // Die Endlos-Zeile steht in der Mitte
        var y = widget.endless && heights.isNotEmpty ? math.max(_gap, (box.maxHeight - heights.first) / 2) : _gap;
        for (final h in heights) {
          tops.add(y);
          y += h + _gap;
        }
        _pageTops = tops;
        // Nach einer Grössenänderung des Fensters wieder in die Grenzen holen.
        final w = box.maxWidth, h = box.maxHeight;
        _offset = Offset(
          _offset.dx.clamp(math.min(0.0, w - _contentWidth * _scale), 0.0),
          _offset.dy.clamp(math.min(0.0, h - _contentHeight * _scale), 0.0),
        );
        final viewer = Focus(
          focusNode: _focus,
          autofocus: true,
          onKeyEvent: _onKey,
          child: Listener(
            onPointerSignal: _onSignal,
            onPointerDown: _onPointerDown,
            onPointerMove: _onPointerMove,
            onPointerUp: _onPointerUp,
            onPointerCancel: _onPointerCancel,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              // Der Stift (und beim Schreiben mit der Maus auch sie) zeichnet Gesten statt zu verschieben
              supportedDevices: widget.onPen == null
                  ? null
                  : {
                      PointerDeviceKind.touch,
                      PointerDeviceKind.trackpad,
                      PointerDeviceKind.unknown,
                      if (!widget.penWrites) PointerDeviceKind.mouse,
                    },
              onScaleStart: _onScaleStart,
              onScaleUpdate: _onScaleUpdate,
              onScaleEnd: _onScaleEnd,
              onTapUp: _onTapUp,
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.topLeft,
                  minWidth: _contentWidth,
                  maxWidth: _contentWidth,
                  minHeight: _contentHeight,
                  maxHeight: _contentHeight,
                  child: Transform(
                    transform: Matrix4.identity()
                      ..translateByDouble(_offset.dx, _offset.dy, 0, 1)
                      ..scaleByDouble(_scale, _scale, 1, 1),
                    child: Column(
                      children: [
                        SizedBox(height: tops.isEmpty ? _gap : tops.first),
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
        return Stack(
          children: [
            Positioned.fill(child: viewer),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _InkPainter(_ink, _inkTick, () => _eraser, Theme.of(context).colorScheme)),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Spur des Stifts, solange er zeichnet (Radierer rot).
class _InkPainter extends CustomPainter {
  _InkPainter(this.points, this.tick, this.eraser, this.scheme) : super(repaint: tick);
  final List<Offset> points;
  final ValueNotifier<int> tick;
  final bool Function() eraser;
  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final paint = Paint()
      ..color = (eraser() ? scheme.error : scheme.primary).withValues(alpha: 0.75)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_InkPainter old) => true;
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
        if (sys.track != null && sys.track != editor.track) continue;
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
      if (sys.track != null && sys.track != editor.track) continue;
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
