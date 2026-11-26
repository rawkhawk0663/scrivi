import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:scrivi_core/scrivi_core.dart';

import '../../app/error_log.dart';
import '../../app/l10n.dart';

/// Ein Stück in der Bibliothek.
class Piece {
  const Piece({
    required this.path,
    required this.title,
    required this.artist,
    required this.bars,
    required this.added,
    required this.size,
    required this.modified,
  });

  /// Ort der Datei in der Bibliothek.
  final String path;
  final String title;
  final String artist;
  final int bars;
  final DateTime added;
  final int size;
  final DateTime modified;

  String get fileName => p.basename(path);
  String get displayTitle => title.isNotEmpty ? title : p.basenameWithoutExtension(path);

  Map<String, dynamic> toJson() => {
    'title': title,
    'artist': artist,
    'bars': bars,
    'added': added.millisecondsSinceEpoch,
    'size': size,
    'modified': modified.millisecondsSinceEpoch,
  };

  static Piece fromJson(String path, Map<String, dynamic> j) => Piece(
    path: path,
    title: j['title'] as String? ?? '',
    artist: j['artist'] as String? ?? '',
    bars: j['bars'] as int? ?? 0,
    added: DateTime.fromMillisecondsSinceEpoch(j['added'] as int? ?? 0),
    size: j['size'] as int? ?? 0,
    modified: DateTime.fromMillisecondsSinceEpoch(j['modified'] as int? ?? 0),
  );
}

/// Ergebnis eines Imports, für die Meldung danach.
class ImportReport {
  int added = 0;
  int duplicates = 0;

  /// Ältere Formate, die erst später gelesen werden können.
  int later = 0;
  final failed = <(String, String)>[];
}

/// Verständlicher Grund, warum sich eine Datei nicht öffnen lässt.
String problemText(Object e) {
  if (e is ScoreFileException) {
    return switch (e.problem) {
      ScoreFileProblem.olderGuitarPro => tr(
        'Ältere Guitar-Pro-Dateien (.gpx, .gp5, .gp4, .gp3) kann Scrivi noch nicht öffnen. Das kommt bald.',
        'Scrivi can’t open older Guitar Pro files (.gpx, .gp5, .gp4, .gp3) yet. Coming soon.',
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

/// Die Bibliothek: Scrivi verwaltet seine Stücke selbst, als Kopie in
/// `<Datenordner>/Bibliothek/Stücke/`. Die Originale bleiben unangetastet.
/// Gelöschtes kommt in `Bibliothek/Papierkorb/`.
class LibraryController extends ChangeNotifier {
  LibraryController(this.root)
    : piecesDir = p.join(root, 'Stücke'),
      trashDir = p.join(root, 'Papierkorb'),
      metaDir = p.join(root, '.scrivi');

  final String root;
  final String piecesDir;
  final String trashDir;
  final String metaDir;

  /// Dateiendungen, die Scrivi heute öffnet.
  static const readable = ['gp'];

  /// Ältere Formate, die später dazukommen.
  static const later = ['gpx', 'gp5', 'gp4', 'gp3'];

  final List<Piece> _pieces = [];
  bool loading = true;

  List<Piece> get pieces => List.unmodifiable(_pieces);

  String get _indexPath => p.join(metaDir, 'index.json');

  Future<void> init() async {
    try {
      await Directory(piecesDir).create(recursive: true);
      await Directory(metaDir).create(recursive: true);
      final index = await _readIndex();
      final found = <Piece>[];
      var changed = false;
      await for (final e in Directory(piecesDir).list(followLinks: false)) {
        if (e is! File || !_isReadable(e.path)) continue;
        final stat = await e.stat();
        final known = index[p.basename(e.path)];
        if (known != null &&
            known.size == stat.size &&
            known.modified.millisecondsSinceEpoch == stat.modified.millisecondsSinceEpoch) {
          found.add(Piece.fromJson(e.path, known.toJson()));
          continue;
        }
        try {
          final meta = await _readMeta(await e.readAsBytes());
          found.add(
            Piece(
              path: e.path,
              title: meta.$1,
              artist: meta.$2,
              bars: meta.$3,
              added: known?.added ?? stat.modified,
              size: stat.size,
              modified: stat.modified,
            ),
          );
        } catch (err, st) {
          ErrorLog.record(err, st, where: 'Bibliothek einlesen: ${p.basename(e.path)}');
          found.add(
            Piece(
              path: e.path,
              title: '',
              artist: '',
              bars: 0,
              added: stat.modified,
              size: stat.size,
              modified: stat.modified,
            ),
          );
        }
        changed = true;
      }
      if (found.length != index.length) changed = true;
      _pieces
        ..clear()
        ..addAll(found);
      _sort();
      if (changed) await _writeIndex();
    } catch (e, st) {
      ErrorLog.record(e, st, where: 'Bibliothek öffnen');
    }
    loading = false;
    notifyListeners();
  }

  bool _isReadable(String path) => readable.contains(p.extension(path).toLowerCase().replaceFirst('.', ''));
  bool _isLater(String path) => later.contains(p.extension(path).toLowerCase().replaceFirst('.', ''));

  void _sort() => _pieces.sort((a, b) => a.displayTitle.toLowerCase().compareTo(b.displayTitle.toLowerCase()));

  Future<Map<String, Piece>> _readIndex() async {
    try {
      final f = File(_indexPath);
      if (!await f.exists()) return {};
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      final list = j['pieces'] as Map<String, dynamic>? ?? {};
      return {
        for (final e in list.entries) e.key: Piece.fromJson(p.join(piecesDir, e.key), e.value as Map<String, dynamic>),
      };
    } catch (e, st) {
      ErrorLog.record(e, st, where: 'Bibliothek: Verzeichnis lesen');
      return {};
    }
  }

  Future<void> _writeIndex() async {
    final data = {
      'format': 'scrivi-library',
      'version': 1,
      'pieces': {for (final x in _pieces) x.fileName: x.toJson()},
    };
    final f = File(_indexPath);
    final tmp = File('$_indexPath.neu');
    await tmp.writeAsString(const JsonEncoder.withIndent(' ').convert(data));
    await tmp.rename(f.path);
  }

  /// Titel, Interpret und Taktzahl lesen (im Hintergrund).
  static Future<(String, String, int)> _readMeta(Uint8List bytes) => Isolate.run(() {
    final s = GpReader.read(bytes);
    return (s.info.title, s.info.artist, s.masterBars.length);
  });

  /// Dateien und Ordner importieren (Ordner werden durchsucht).
  Future<ImportReport> importPaths(List<String> paths) async {
    final report = ImportReport();
    final files = <String>[];
    for (final path in paths) {
      if (await FileSystemEntity.isDirectory(path)) {
        await for (final e in Directory(path).list(recursive: true, followLinks: false)) {
          if (e is File && (_isReadable(e.path) || _isLater(e.path))) files.add(e.path);
        }
      } else {
        files.add(path);
      }
    }
    for (final path in files) {
      final name = p.basename(path);
      try {
        final bytes = await File(path).readAsBytes();
        if (await _isDuplicate(bytes)) {
          report.duplicates++;
          continue;
        }
        final meta = await _readMeta(bytes);
        // Neuere Guitar-Pro-Dateien kommen immer als .gp in die Bibliothek.
        final target = await _uniqueName(piecesDir, '${p.basenameWithoutExtension(name)}.gp');
        final tmp = File('$target.neu');
        await tmp.writeAsBytes(bytes, flush: true);
        await tmp.rename(target);
        final stat = await File(target).stat();
        _pieces.add(
          Piece(
            path: target,
            title: meta.$1,
            artist: meta.$2,
            bars: meta.$3,
            added: DateTime.now(),
            size: stat.size,
            modified: stat.modified,
          ),
        );
        report.added++;
      } on ScoreFileException catch (e) {
        if (e.problem == ScoreFileProblem.olderGuitarPro || _isLater(path)) {
          report.later++;
        } else {
          report.failed.add((name, problemText(e)));
        }
      } catch (e, st) {
        ErrorLog.record(e, st, where: 'Import: $name');
        report.failed.add((name, problemText(e)));
      }
    }
    if (report.added > 0) {
      _sort();
      await _writeIndex();
      notifyListeners();
    }
    return report;
  }

  Future<bool> _isDuplicate(Uint8List bytes) async {
    for (final x in _pieces) {
      if (x.size != bytes.length) continue;
      try {
        final other = await File(x.path).readAsBytes();
        if (listEquals(other, bytes)) return true;
      } catch (_) {}
    }
    return false;
  }

  static Future<String> _uniqueName(String dir, String name) async {
    final base = p.basenameWithoutExtension(name), ext = p.extension(name);
    var candidate = p.join(dir, name);
    var n = 2;
    while (await File(candidate).exists()) {
      candidate = p.join(dir, '$base ($n)$ext');
      n++;
    }
    return candidate;
  }

  /// In den Papierkorb legen (nie endgültig löschen).
  Future<void> delete(Piece piece) async {
    await Directory(trashDir).create(recursive: true);
    final target = await _uniqueName(trashDir, piece.fileName);
    try {
      await File(piece.path).rename(target);
    } catch (_) {
      await File(piece.path).copy(target);
      await File(piece.path).delete();
    }
    _pieces.removeWhere((x) => x.path == piece.path);
    await _writeIndex();
    notifyListeners();
  }

  /// Das ganze Stück lesen (im Hintergrund).
  static Future<Score> load(String path) async {
    final bytes = await File(path).readAsBytes();
    return Isolate.run(() => GpReader.read(bytes));
  }
}
