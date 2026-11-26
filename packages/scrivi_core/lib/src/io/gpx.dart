import 'dart:convert';
import 'dart:typed_data';

import 'gp_reader.dart';

/// Guitar Pro 6 (`.gpx`): Ein kleines Dateisystem („BCFS“), meist gepackt
/// („BCFZ“). Darin liegt `score.gpif` im selben XML-Format wie bei `.gp`.
class GpxContainer {
  GpxContainer._();

  static bool looksLike(Uint8List b) =>
      b.length >= 4 && b[0] == 0x42 && b[1] == 0x43 && b[2] == 0x46 && (b[3] == 0x5A || b[3] == 0x53); // BCFZ / BCFS

  /// Gibt den Inhalt von `score.gpif` zurück.
  static String scoreXml(Uint8List bytes) {
    Uint8List fs;
    if (bytes[3] == 0x5A) {
      fs = _decompress(bytes);
    } else {
      fs = bytes;
    }
    if (fs.length < 4 || String.fromCharCodes(fs.sublist(0, 4)) != 'BCFS') {
      throw const ScoreFileException(ScoreFileProblem.damaged, 'kein BCFS');
    }
    final files = _readFileSystem(Uint8List.sublistView(fs, 4));
    final gpif = files['score.gpif'];
    if (gpif == null) throw const ScoreFileException(ScoreFileProblem.damaged, 'score.gpif fehlt');
    return utf8.decode(gpif, allowMalformed: true);
  }

  /// Entpacken: Bitstrom mit Rückverweisen auf bereits Ausgepacktes.
  static Uint8List _decompress(Uint8List src) {
    final expected = ByteData.sublistView(src, 4, 8).getInt32(0, Endian.little);
    if (expected <= 0 || expected > 200 * 1024 * 1024) {
      throw const ScoreFileException(ScoreFileProblem.damaged, 'Grösse');
    }
    final out = Uint8List(expected);
    var len = 0;
    var bytePos = 8;
    var bitPos = 0;
    int bit() {
      if (bytePos >= src.length) throw const _EndOfData();
      final v = (src[bytePos] >> (7 - bitPos)) & 1;
      bitPos++;
      if (bitPos == 8) {
        bitPos = 0;
        bytePos++;
      }
      return v;
    }

    // Höchstes Bit zuerst
    int bits(int n) {
      var v = 0;
      for (var i = 0; i < n; i++) {
        v = (v << 1) | bit();
      }
      return v;
    }

    // Niedrigstes Bit zuerst
    int bitsReversed(int n) {
      var v = 0;
      for (var i = 0; i < n; i++) {
        v |= bit() << i;
      }
      return v;
    }

    // Der Strom darf vor der angekündigten Länge enden.
    try {
      _loop(() => len < expected, () {
        if (bit() == 1) {
          final wordSize = bits(4);
          final offset = bitsReversed(wordSize);
          final size = bitsReversed(wordSize);
          final from = len - offset;
          if (from < 0 || offset == 0) throw const ScoreFileException(ScoreFileProblem.damaged, 'Verweis');
          final n = size < offset ? size : offset;
          for (var i = 0; i < n && len < expected; i++) {
            out[len++] = out[from + i];
          }
        } else {
          final size = bitsReversed(2);
          for (var i = 0; i < size && len < expected; i++) {
            out[len++] = bits(8);
          }
        }
      });
    } on _EndOfData {
      // fertig
    }
    return Uint8List.sublistView(out, 0, len);
  }

  static void _loop(bool Function() condition, void Function() body) {
    while (condition()) {
      body();
    }
  }

  /// Dateien im BCFS: Blöcke zu 4096 Bytes; ein Eintrag (Typ 2) nennt Name,
  /// Grösse und die Blöcke mit dem Inhalt.
  static Map<String, Uint8List> _readFileSystem(Uint8List data) {
    const sector = 0x1000;
    final view = ByteData.sublistView(data);
    int i32(int at) => at + 4 <= data.length ? view.getInt32(at, Endian.little) : 0;
    final files = <String, Uint8List>{};
    var offset = sector;
    while (offset + 3 < data.length) {
      if (i32(offset) == 2) {
        final nameBytes = <int>[];
        for (var k = offset + 4; k < offset + 4 + 127 && k < data.length && data[k] != 0; k++) {
          nameBytes.add(data[k]);
        }
        final name = String.fromCharCodes(nameBytes);
        final size = i32(offset + 0x8C);
        final content = BytesBuilder(copy: false);
        var p = offset + 0x94;
        while (true) {
          final block = i32(p);
          if (block == 0) break;
          final start = block * sector;
          if (start >= data.length) break;
          final end = start + sector > data.length ? data.length : start + sector;
          content.add(Uint8List.sublistView(data, start, end));
          p += 4;
        }
        final all = content.takeBytes();
        if (size >= 0 && size <= all.length) files[name] = Uint8List.sublistView(all, 0, size);
      }
      offset += sector;
    }
    return files;
  }
}

class _EndOfData implements Exception {
  const _EndOfData();
}
