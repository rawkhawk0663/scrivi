import 'dart:io';
import 'dart:ui' as ui;

import 'package:path/path.dart' as p;
import 'package:scrivi_core/scrivi_core.dart';

import '../../app/error_log.dart';
import '../../features/score/score_painter.dart';
import 'recent_files.dart';
import 'score_files.dart';

/// Vorschaubilder für „Zuletzt geöffnet“: der obere Teil der ersten Seite als
/// PNG im Ordner [dir]. Werden einzeln nacheinander erzeugt, damit die
/// Startseite flüssig bleibt.
class Thumbnails {
  Thumbnails(this.dir);

  final String dir;

  /// Anteil der ersten Seite, der gezeigt wird (Titel und erste Zeilen).
  static const crop = 0.5;
  static const width = 420;

  /// Stand des Notensatzes: erhöhen, wenn die Noten anders aussehen, damit die
  /// Vorschaubilder neu entstehen.
  static const style = 6;

  final _jobs = <String, Future<File?>>{};
  Future<void> _queue = Future.value();

  String _keyFor(RecentEntry piece) {
    final safe = '${piece.path.hashCode.toRadixString(16)}-${piece.fileName}'.replaceAll(RegExp(r'[^\w\-. ]'), '_');
    return '$safe-${piece.size}-${piece.modified.millisecondsSinceEpoch}-v$style.png';
  }

  Future<File?> forPiece(RecentEntry piece) {
    final key = _keyFor(piece);
    return _jobs.putIfAbsent(key, () {
      final done = _queue.then((_) => _make(piece, key));
      _queue = done.then((_) {}, onError: (_) {});
      return done;
    });
  }

  Future<File?> _make(RecentEntry piece, String key) async {
    final file = File(p.join(dir, key));
    try {
      if (await file.exists()) return file;
      await Directory(dir).create(recursive: true);
      final score = await ScoreFiles.load(piece.path);
      final layout = Engraver(score, measurer: FlutterTextMeasurer()).layout();
      final page = layout.pages.first;
      final picture = PagePictures.record(page);
      final s = width / page.width;
      final h = (page.height * crop * s).round();
      final rec = ui.PictureRecorder();
      final canvas = ui.Canvas(rec);
      canvas.scale(s);
      canvas.drawPicture(picture);
      final image = await rec.endRecording().toImage(width, h);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      picture.dispose();
      if (data == null) return null;
      final tmp = File('${file.path}.neu');
      await tmp.writeAsBytes(data.buffer.asUint8List(), flush: true);
      await tmp.rename(file.path);
      return file;
    } catch (e, st) {
      ErrorLog.record(e, st, where: 'Vorschaubild: ${piece.fileName}');
      return null;
    }
  }
}
