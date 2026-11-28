import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:scrivi_core/scrivi_core.dart' as core;

import '../../app/error_log.dart';
import '../../app/l10n.dart';
import '../../app/open_url.dart';
import '../../app/sounds.dart';
import '../../core/files/pdf_export.dart';
import '../../core/files/score_files.dart';
import 'score_painter.dart';

/// Wohin ein Stück ausgegeben wird.
enum ExportKind {
  pdf('pdf', Icons.picture_as_pdf_outlined),
  png('png', Icons.image_outlined),
  musicXml('musicxml', Icons.library_music_outlined),
  midi('mid', Icons.piano_outlined),
  wav('wav', Icons.graphic_eq_rounded);

  /// Seiten (mit Wahl: diese Spur, alle Stimmen, Partitur).
  bool get paged => this == pdf || this == png;

  const ExportKind(this.extension, this.icon);
  final String extension;
  final IconData icon;

  String get label => switch (this) {
    pdf => tr('PDF (zum Drucken und Weitergeben)', 'PDF (to print and share)'),
    png => tr('Bild (PNG, eine Datei pro Seite)', 'Image (PNG, one file per page)'),
    musicXml => tr('MusicXML (für andere Notenprogramme)', 'MusicXML (for other notation programs)'),
    midi => tr('MIDI (Töne, so wie sie klingen)', 'MIDI (the notes as they sound)'),
    wav => tr('Tonspur (WAV, zum Mitspielen)', 'Audio (WAV, to play along)'),
  };

  String get hint => switch (this) {
    pdf => tr('Seiten wie in der Ansicht, Notenzeichen gestochen scharf.', 'Pages as shown, sharp at any size.'),
    png => tr(
      'Für Arbeitsblätter, Mails und Präsentationen (200 dpi).',
      'For worksheets, e-mails and presentations (200 dpi).',
    ),
    wav => tr(
      'Alle Spuren gemischt wie im Mischpult, Wiederholungen ausgespielt.',
      'All tracks mixed as in the mixer, repeats played out.',
    ),
    musicXml => tr(
      'Alle Spuren mit Noten, Saite und Bund, Akkorden und Liedtext.',
      'All tracks with notes, string and fret, chords and lyrics.',
    ),
    midi => tr(
      'Alle Spuren mit Klang und Tempo, Wiederholungen ausgeschrieben.',
      'All tracks with sound and tempo, repeats written out.',
    ),
  };
}

/// Was ins PDF kommt: die gewählte Spur, alle Spuren einzeln (Stimmen) oder die Partitur.
enum PdfScope { track, parts, score }

/// Ausgeben: Fenster mit Format (und beim PDF: diese Spur oder alle), dann
/// Ort wählen (Android: Ordner „Scrivi“ in den Dokumenten).
class ScoreExport {
  ScoreExport({
    required this.score,
    required this.track,
    required this.options,
    required this.sourcePath,
    this.fullScore = false,
  });

  /// Am Bildschirm ist die Partitur zu sehen: Drucken und PDF nehmen sie zuerst.
  final bool fullScore;

  PdfScope get initialScope => fullScore && score.tracks.length > 1 ? PdfScope.score : PdfScope.track;

  final core.Score score;
  final int track;

  /// Ansicht wie am Bildschirm (Noten/Tab, transponiert); Seiten immer A4.
  final core.LayoutOptions options;
  final String sourcePath;

  String get _baseName => score.info.title.trim().isNotEmpty
      ? ScoreFiles.safeName(score.info.title)
      : p.basenameWithoutExtension(sourcePath);

  /// Seiten für das PDF: die gewählte Spur, alle hintereinander oder die Partitur.
  List<core.PageDisplay> _pages(PdfScope scope) {
    final opts = core.LayoutOptions(
      showTab: options.showTab,
      showNotation: options.showNotation,
      germanNoteNames: options.germanNoteNames,
      transposed: options.transposed,
    );
    if (scope == PdfScope.score) {
      return core.ScoreEngraver(score, options: opts, measurer: FlutterTextMeasurer()).layout().pages;
    }
    return [
      for (var i = 0; i < score.tracks.length; i++)
        if (scope == PdfScope.parts || i == track)
          ...core.Engraver(score, trackIndex: i, options: opts, measurer: FlutterTextMeasurer()).layout().pages,
    ];
  }

  Future<Uint8List> _bytes(ExportKind kind, {PdfScope scope = PdfScope.track}) async => switch (kind) {
    ExportKind.pdf => PdfExport.build(_pages(scope), title: score.info.title),
    ExportKind.png => _png(_pages(scope).first),
    ExportKind.musicXml => core.MusicXmlWriter.write(score),
    ExportKind.midi => core.MidiWriter.write(score),
    ExportKind.wav => _wav(),
  };

  /// Eine Seite als PNG (200 dpi, nach der Notengrösse der Seite).
  static Future<Uint8List> _png(core.PageDisplay page) async {
    final k = page.spaceMm / 25.4 * 200; // Bildpunkte pro Linienabstand
    final w = (page.width * k).round(), h = (page.height * k).round();
    final rec = ui.PictureRecorder();
    final canvas = ui.Canvas(rec, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
    canvas.scale(k);
    PagePictures.paint(canvas, page);
    final image = await rec.endRecording().toImage(w, h);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  }

  /// Ganzes Stück als Tonspur (im Hintergrund gerechnet, mit der mitgelieferten Klangsammlung).
  Future<Uint8List> _wav() async {
    final sounds = await Sounds.bytes();
    final s = score;
    return Isolate.run(() {
      core.SoundFont? sf;
      try {
        sf = sounds == null ? null : core.SoundFont.parse(sounds);
      } catch (_) {}
      return core.Synth.mixdown(s, sounds: sf);
    });
  }

  /// Fenster zeigen und ausgeben.
  Future<void> show(BuildContext context) async {
    final choice = await showDialog<(ExportKind, PdfScope)>(
      context: context,
      builder: (context) => _ExportDialog(trackCount: score.tracks.length, initial: initialScope),
    );
    if (choice == null || !context.mounted) return;
    final (kind, scope) = choice;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final suffix = !kind.paged || score.tracks.length < 2
          ? ''
          : switch (scope) {
              PdfScope.track => ' – ${_trackName(track)}',
              PdfScope.parts => tr(' – Stimmen', ' – parts'),
              PdfScope.score => tr(' – Partitur', ' – score'),
            };
      final name = '$_baseName$suffix.${kind.extension}';
      final target = await _target(name, kind);
      if (target == null) return;
      if (kind == ExportKind.wav) {
        messenger.showSnackBar(SnackBar(content: Text(tr('Die Tonspur wird gerechnet …', 'Rendering the audio …'))));
      }
      if (kind == ExportKind.png) {
        // Mehrere Seiten: eine Datei pro Seite (Name-1.png, Name-2.png …)
        final pages = _pages(scope);
        final base = target.substring(0, target.length - 4);
        for (var i = 0; i < pages.length; i++) {
          final path = pages.length == 1 ? target : '$base-${i + 1}.png';
          await ScoreFiles.writeAtomic(path, await _png(pages[i]));
        }
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              pages.length == 1
                  ? tr('Gespeichert: $target', 'Saved: $target')
                  : tr(
                      '${pages.length} Bilder gespeichert: $base-1.png …',
                      '${pages.length} images saved: $base-1.png …',
                    ),
            ),
          ),
        );
        return;
      }
      final bytes = await _bytes(kind, scope: scope);
      await ScoreFiles.writeAtomic(target, bytes);
      messenger.showSnackBar(SnackBar(content: Text(tr('Gespeichert: $target', 'Saved: $target'))));
    } catch (err, st) {
      ErrorLog.record(err, st, where: 'Exportieren (${kind.name})');
      messenger.showSnackBar(SnackBar(content: Text(tr('Exportieren ist fehlgeschlagen.', 'Export failed.'))));
    }
  }

  /// Drucken: PDF der gewählten Spur bauen und im PDF-Programm des Systems
  /// öffnen (dort drucken). Android: als PDF in den Dokumenten ablegen.
  Future<void> print(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await _bytes(ExportKind.pdf, scope: initialScope);
      final name = '$_baseName.pdf';
      if (Platform.isAndroid || Platform.isIOS) {
        final dir = p.join(await _documentsDir() ?? Directory.systemTemp.path, 'Scrivi');
        final target = await ScoreFiles.uniquePath(dir, name);
        await ScoreFiles.writeAtomic(target, bytes);
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              tr('PDF gespeichert: $target – von dort aus drucken.', 'PDF saved: $target – print it from there.'),
            ),
          ),
        );
        return;
      }
      final dir = Directory(p.join(Directory.systemTemp.path, 'Scrivi'));
      await dir.create(recursive: true);
      final target = p.join(dir.path, name);
      await ScoreFiles.writeAtomic(target, bytes);
      await openUrl(Uri.file(target));
    } catch (err, st) {
      ErrorLog.record(err, st, where: 'Drucken');
      messenger.showSnackBar(SnackBar(content: Text(tr('Drucken ist fehlgeschlagen.', 'Printing failed.'))));
    }
  }

  String _trackName(int i) {
    final n = score.tracks[i].name.trim();
    return n.isEmpty ? tr('Spur ${i + 1}', 'Track ${i + 1}') : ScoreFiles.safeName(n);
  }

  Future<String?> _target(String name, ExportKind kind) async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final loc = await getSaveLocation(
        suggestedName: name,
        initialDirectory: ScoreFiles.isScrivi(sourcePath) ? p.dirname(sourcePath) : await _documentsDir(),
        acceptedTypeGroups: [
          XTypeGroup(
            label: switch (kind) {
              ExportKind.pdf => 'PDF',
              ExportKind.png => 'PNG',
              ExportKind.musicXml => 'MusicXML',
              ExportKind.midi => 'MIDI',
              ExportKind.wav => 'WAV',
            },
            extensions: [kind.extension],
          ),
        ],
        confirmButtonText: tr('Speichern', 'Save'),
      );
      if (loc == null) return null;
      final ext = '.${kind.extension}';
      return loc.path.toLowerCase().endsWith(ext) ? loc.path : '${loc.path}$ext';
    }
    final dir = p.join(await _documentsDir() ?? Directory.systemTemp.path, 'Scrivi');
    return ScoreFiles.uniquePath(dir, name);
  }

  static Future<String?> _documentsDir() async {
    try {
      return (await getApplicationDocumentsDirectory()).path;
    } catch (_) {
      return Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
    }
  }
}

class _ExportDialog extends StatefulWidget {
  const _ExportDialog({required this.trackCount, required this.initial});
  final int trackCount;
  final PdfScope initial;

  @override
  State<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<_ExportDialog> {
  ExportKind _kind = ExportKind.pdf;
  late PdfScope _scope = widget.initial;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(tr('Exportieren', 'Export')),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final k in ExportKind.values)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  selected: k == _kind,
                  selectedTileColor: scheme.primaryContainer.withValues(alpha: 0.5),
                  leading: Icon(k.icon),
                  title: Text(k.label),
                  subtitle: Text(k.hint),
                  onTap: () => setState(() => _kind = k),
                ),
              if (_kind.paged && widget.trackCount > 1) ...[
                const SizedBox(height: 12),
                SegmentedButton<PdfScope>(
                  segments: [
                    ButtonSegment(value: PdfScope.track, label: Text(tr('Diese Spur', 'This track'))),
                    ButtonSegment(value: PdfScope.parts, label: Text(tr('Alle Stimmen', 'All parts'))),
                    ButtonSegment(value: PdfScope.score, label: Text(tr('Partitur', 'Full score'))),
                  ],
                  selected: {_scope},
                  onSelectionChanged: (s) => setState(() => _scope = s.first),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Abbrechen', 'Cancel'))),
        FilledButton(
          onPressed: () => Navigator.pop(context, (_kind, _scope)),
          child: Text(tr('Speichern …', 'Save …')),
        ),
      ],
    );
  }
}
