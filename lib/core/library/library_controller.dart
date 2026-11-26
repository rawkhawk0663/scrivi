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

  /// Formate, die erst später gelesen werden können (heute keine mehr).
  int later = 0;
  final failed = <(String, String)>[];
}

/// Verständlicher Grund, warum sich eine Datei nicht öffnen lässt.
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

  /// Dateiendungen, die Scrivi öffnet: Guitar Pro, MusicXML, MIDI.
  static const readable = ['scrivi', 'gp', 'gpx', 'gp5', 'gp4', 'gp3', 'musicxml', 'mxl', 'xml', 'mid', 'midi'];

  /// Ordner für die Originale bearbeiteter Stücke (nie gelöscht, nicht in der Liste).
  String get originalsDir => p.join(root, 'Originale');

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

  static String _ext(String path) => p.extension(path).toLowerCase().replaceFirst('.', '');
  bool _isReadable(String path) => readable.contains(_ext(path));

  /// Endung für die Kopie in der Bibliothek: die bisherige, sonst nach Inhalt.
  static String _targetExtension(String path, Uint8List b) {
    final ext = _ext(path);
    if (readable.contains(ext)) return ext;
    bool starts(String s) => b.length >= s.length && String.fromCharCodes(b.sublist(0, s.length)) == s;
    if (starts('PK')) {
      return String.fromCharCodes(b.take(4096)).contains('Content/score.gpif') ? 'gp' : 'mxl';
    }
    if (starts('BCF')) return 'gpx';
    if (ScriviFormat.looksLike(b)) return 'scrivi';
    if (starts('MThd')) return 'mid';
    if (b.length > 20 && String.fromCharCodes(b.sublist(1, 20)).startsWith('FICHIER GUITAR PRO')) {
      final v = String.fromCharCodes(b.sublist(1, 30));
      return v.contains('v3') ? 'gp3' : (v.contains('v4') ? 'gp4' : 'gp5');
    }
    return 'musicxml';
  }

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
          if (e is File && _isReadable(e.path)) files.add(e.path);
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
        final target = await _uniqueName(
          piecesDir,
          '${p.basenameWithoutExtension(name)}.${_targetExtension(path, bytes)}',
        );
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
        // Beim Ordner-Import sind andere XML-Dateien normal: still überspringen.
        if (e.problem == ScoreFileProblem.unknownFormat && _ext(path) == 'xml' && !paths.contains(path)) continue;
        report.failed.add((name, problemText(e)));
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

  /// Neues Stück als `.scrivi` in der Bibliothek anlegen.
  Future<Piece> create(Score score) async {
    final title = score.info.title.trim().isEmpty ? 'Neues Stück' : score.info.title.trim();
    final target = await _uniqueName(piecesDir, '${_safeName(title)}.scrivi');
    await _writeAtomic(target, ScriviFormat.encode(score));
    final piece = await _pieceFor(target, score, added: DateTime.now());
    _pieces.add(piece);
    _sort();
    await _writeIndex();
    notifyListeners();
    return piece;
  }

  /// Bearbeitetes Stück speichern (erst in eine Zwischendatei, dann umbenennen).
  ///
  /// Ist es noch keine `.scrivi`-Datei (z. B. eine importierte Guitar-Pro-Datei),
  /// entsteht daneben eine `.scrivi`-Datei; das Original wandert in den Ordner
  /// „Originale“ und bleibt dort erhalten. Gibt das (evtl. neue) Stück zurück.
  Future<Piece> save(Piece piece, Score score) async {
    var path = piece.path;
    if (_ext(path) != 'scrivi') {
      final target = await _uniqueName(piecesDir, '${p.basenameWithoutExtension(path)}.scrivi');
      await _writeAtomic(target, ScriviFormat.encode(score));
      await Directory(originalsDir).create(recursive: true);
      final keep = await _uniqueName(originalsDir, p.basename(path));
      try {
        await File(path).rename(keep);
      } catch (_) {
        await File(path).copy(keep);
        await File(path).delete();
      }
      path = target;
    } else {
      await _writeAtomic(path, ScriviFormat.encode(score));
    }
    final updated = await _pieceFor(path, score, added: piece.added);
    final i = _pieces.indexWhere((x) => x.path == piece.path);
    if (i >= 0) {
      _pieces[i] = updated;
    } else {
      _pieces.add(updated);
    }
    _sort();
    await _writeIndex();
    notifyListeners();
    return updated;
  }

  Future<Piece> _pieceFor(String path, Score score, {required DateTime added}) async {
    final stat = await File(path).stat();
    return Piece(
      path: path,
      title: score.info.title,
      artist: score.info.artist,
      bars: score.masterBars.length,
      added: added,
      size: stat.size,
      modified: stat.modified,
    );
  }

  static Future<void> _writeAtomic(String path, List<int> bytes) async {
    final tmp = File('$path.neu');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(path);
  }

  /// Dateiname aus einem Titel (ohne Zeichen, die Dateisysteme nicht mögen).
  static String _safeName(String title) {
    final s = title.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_').trim();
    return s.isEmpty ? 'Neues Stück' : (s.length > 80 ? s.substring(0, 80) : s);
  }

  /// Das ganze Stück lesen (im Hintergrund).
  static Future<Score> load(String path) async {
    final bytes = await File(path).readAsBytes();
    return Isolate.run(() => GpReader.read(bytes));
  }
}
