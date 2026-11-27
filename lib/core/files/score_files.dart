import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:scrivi_core/scrivi_core.dart';

import '../../app/l10n.dart';

/// Lesen und Schreiben von Notendateien.
class ScoreFiles {
  ScoreFiles._();

  /// Endungen, die Scrivi öffnen kann (das Format wird trotzdem am Inhalt erkannt).
  static const readable = ['scrivi', 'gp', 'gpx', 'gp5', 'gp4', 'gp3', 'musicxml', 'mxl', 'xml', 'mid', 'midi'];

  static String ext(String path) => p.extension(path).toLowerCase().replaceFirst('.', '');
  static bool isReadable(String path) => readable.contains(ext(path));
  static bool isScrivi(String path) => ext(path) == 'scrivi';

  /// Das ganze Stück lesen (im Hintergrund).
  static Future<Score> load(String path) async {
    final bytes = await File(path).readAsBytes();
    return Isolate.run(() => GpReader.read(bytes));
  }

  /// Als `.scrivi` speichern: erst in eine Zwischendatei, dann umbenennen.
  /// So bleibt bei einem Absturz mitten im Schreiben die alte Datei heil.
  static Future<void> writeScrivi(String path, Score score) async {
    final bytes = ScriviFormat.encode(score);
    await writeAtomic(path, bytes);
  }

  static Future<void> writeAtomic(String path, Uint8List bytes) async {
    await Directory(p.dirname(path)).create(recursive: true);
    final tmp = File('$path.neu');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(path);
  }

  /// Dateiname aus einem Titel (ohne Zeichen, die Dateisysteme nicht mögen).
  static String safeName(String title, {String fallback = 'Neues Stück'}) {
    final s = title.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_').trim();
    if (s.isEmpty) return fallback;
    return s.length > 80 ? s.substring(0, 80) : s;
  }

  /// Freier Dateiname im Ordner [dir]: „Name.scrivi“, sonst „Name (2).scrivi“ …
  static Future<String> uniquePath(String dir, String name) async {
    final base = p.basenameWithoutExtension(name), e = p.extension(name);
    var candidate = p.join(dir, name);
    var n = 2;
    while (await File(candidate).exists()) {
      candidate = p.join(dir, '$base ($n)$e');
      n++;
    }
    return candidate;
  }
}

/// Verständliche Meldung, warum eine Datei nicht geht.
String problemText(Object e) {
  if (e is ScoreFileException) {
    return switch (e.problem) {
      ScoreFileProblem.olderGuitarPro => tr(
        'Dieses Guitar-Pro-Format kann Scrivi noch nicht öffnen.',
        'Scrivi can’t open this Guitar Pro format yet.',
      ),
      ScoreFileProblem.unknownFormat => tr('Diese Datei kennt Scrivi nicht.', 'Scrivi doesn’t know this kind of file.'),
      ScoreFileProblem.damaged => tr(
        'Die Datei ist beschädigt oder unvollständig.',
        'The file is damaged or incomplete.',
      ),
    };
  }
  if (e is FileSystemException) return tr('Die Datei lässt sich nicht lesen.', 'The file can’t be read.');
  return '$e';
}
