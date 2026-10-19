// pdf 3.11.3 serializes non-BMP ToUnicode entries as scalar hex instead of
// UTF-16BE. Keep this narrow adapter until the upstream implementation is fixed.
// ignore_for_file: implementation_imports
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/src/pdf/obj/unicode_cmap.dart';
import 'package:pdf/widgets.dart' as pw;

class UnicodePdfFont extends pw.TtfFont {
  UnicodePdfFont(ByteData data) : super(data);

  @override
  PdfFont buildFont(PdfDocument pdfDocument) {
    final font = super.buildFont(pdfDocument) as PdfTtfFont;
    final map = _Utf16Cmap(pdfDocument);
    map.cmap
      ..clear()
      ..addAll(font.unicodeCMap.cmap);
    font.unicodeCMap = map;
    return font;
  }
}

class _Utf16Cmap extends PdfUnicodeCmap {
  _Utf16Cmap(PdfDocument document) : super(document, false);

  @override
  void prepare() {
    final original = List<int>.of(cmap);
    try {
      for (var i = 0; i < cmap.length; i++) {
        final scalar = cmap[i];
        if (scalar > 0xffff && scalar <= 0x10ffff) {
          final offset = scalar - 0x10000;
          final high = 0xd800 + (offset >> 10);
          final low = 0xdc00 + (offset & 0x3ff);
          // The base serializer writes hexadecimal; pack two UTF-16 code units.
          cmap[i] = (high << 16) | low;
        }
      }
      super.prepare();
    } finally {
      // Font subsetting and widths must continue to see Unicode scalars.
      cmap
        ..clear()
        ..addAll(original);
    }
  }
}
