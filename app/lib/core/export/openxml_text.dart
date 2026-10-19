/// XML 1.0 serialization shared by Word and Excel exporters.
class OpenXmlText {
  static bool _allowed(int c) =>
      c == 9 ||
      c == 10 ||
      c == 13 ||
      (c >= 0x20 && c <= 0xd7ff) ||
      (c >= 0xe000 && c <= 0xfffd) ||
      (c >= 0x10000 && c <= 0x10ffff);
  static String escape(String text, {bool spreadsheet = false}) {
    // Invalid controls and isolated UTF-16 surrogates cannot occur in XML 1.0.
    var safe =
        String.fromCharCodes(text.runes.map((c) => _allowed(c) ? c : 0xfffd));
    if (spreadsheet) {
      // Protect literal ST_Xstring sequences, e.g. _x0041_ must not become A.
      safe = safe.replaceAllMapped(
          RegExp(r'_(?=x[0-9a-f]{4}_)', caseSensitive: false),
          (_) => '_x005F_');
    }
    return safe
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}
