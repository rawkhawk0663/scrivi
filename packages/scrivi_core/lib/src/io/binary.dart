import 'dart:convert';
import 'dart:typed_data';

/// Liest Zahlen und Texte aus Binärdaten (Little Endian, wie in den
/// älteren Guitar-Pro-Dateien).
class BinaryReader {
  BinaryReader(this.bytes) : _data = ByteData.sublistView(bytes);

  final Uint8List bytes;
  final ByteData _data;
  int pos = 0;

  bool get atEnd => pos >= bytes.length;

  void _need(int n) {
    if (pos + n > bytes.length) throw const FormatException('Datei endet zu früh');
  }

  int u8() {
    _need(1);
    return bytes[pos++];
  }

  int i8() {
    _need(1);
    return _data.getInt8(pos++);
  }

  bool boolean() => u8() != 0;

  int i16() {
    _need(2);
    final v = _data.getInt16(pos, Endian.little);
    pos += 2;
    return v;
  }

  int i32() {
    _need(4);
    final v = _data.getInt32(pos, Endian.little);
    pos += 4;
    return v;
  }

  int u32() {
    _need(4);
    final v = _data.getUint32(pos, Endian.little);
    pos += 4;
    return v;
  }

  double f64() {
    _need(8);
    final v = _data.getFloat64(pos, Endian.little);
    pos += 8;
    return v;
  }

  void skip(int n) {
    _need(n);
    pos += n;
  }

  /// Länge (1 Byte), danach immer [count] Zeichen; gilt nur der vordere Teil.
  String byteSizeString(int count) {
    final size = u8();
    _need(count);
    final s = decodeCp1252(bytes.sublist(pos, pos + (size < count ? size : count)));
    pos += count;
    return s;
  }

  /// Länge (4 Bytes), danach die Zeichen.
  String intSizeString() {
    final n = i32();
    if (n <= 0) return '';
    _need(n);
    final s = decodeCp1252(bytes.sublist(pos, pos + n));
    pos += n;
    return s;
  }

  /// Gesamtlänge (4 Bytes), dann Länge (1 Byte) und Zeichen.
  String intByteSizeString() {
    final n = i32();
    if (n <= 0) return '';
    return byteSizeString(n - 1);
  }
}

/// Texte in älteren Dateien sind in Windows-1252 gespeichert. Ist der Text
/// gültiges UTF-8 (neuere Programme), wird er so gelesen.
String decodeCp1252(List<int> b) {
  if (b.any((c) => c >= 0x80)) {
    try {
      return utf8.decode(b);
    } catch (_) {}
  }
  const high = [
    0x20AC,
    0x81,
    0x201A,
    0x0192,
    0x201E,
    0x2026,
    0x2020,
    0x2021,
    0x02C6,
    0x2030,
    0x0160,
    0x2039,
    0x0152,
    0x8D,
    0x017D,
    0x8F, //
    0x90,
    0x2018,
    0x2019,
    0x201C,
    0x201D,
    0x2022,
    0x2013,
    0x2014,
    0x02DC,
    0x2122,
    0x0161,
    0x203A,
    0x0153,
    0x9D,
    0x017E,
    0x0178,
  ];
  final out = StringBuffer();
  for (final c in b) {
    if (c == 0) break;
    out.writeCharCode(c >= 0x80 && c < 0xA0 ? high[c - 0x80] : c);
  }
  return out.toString().trim();
}
