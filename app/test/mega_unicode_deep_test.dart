import 'dart:math';
import 'package:xml/xml.dart';
import 'package:povarspravka/core/export/openxml_text.dart';
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/export/docx_blank_generator.dart';
import 'package:povarspravka/core/export/xlsx_blank_generator.dart';
import 'culinary_logic_test.dart' show fixture;

bool xmlScalar(int c) =>
    c == 9 ||
    c == 10 ||
    c == 13 ||
    (c >= 0x20 && c <= 0xd7ff) ||
    (c >= 0xe000 && c <= 0xfffd) ||
    (c >= 0x10000 && c <= 0x10ffff);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('DEEP ST_Xstring 10000 roundtrips cover overlapping literal escapes',
      () {
    String decode(String encoded) => XmlDocument.parse('<t>$encoded</t>')
        .rootElement
        .innerText
        .replaceAllMapped(RegExp(r'_x([0-9a-fA-F]{4})_'),
            (m) => String.fromCharCode(int.parse(m[1]!, radix: 16)));
    const cases = [
      '_x0041_x0042_',
      '_x005F_x0041_',
      '_x0041__x0042_',
      '_X0041_'
    ];
    for (final raw in cases) {
      expect(decode(OpenXmlText.escape(raw, spreadsheet: true)), raw);
    }
    final rng = Random(20261020);
    const tokens = [
      'A',
      '_',
      'x',
      '_x0041_',
      '_x005F_',
      '_x0000_',
      '_xFFFE_',
      '_X0041_',
      '🍲',
      '&<>',
      '\n'
    ];
    for (var i = 0; i < 10000; i++) {
      final raw = List.generate(
          rng.nextInt(17), (_) => tokens[rng.nextInt(tokens.length)]).join();
      final actual = decode(OpenXmlText.escape(raw, spreadsheet: true));
      if (actual != raw) {
        fail('ST_Xstring roundtrip mismatch at seed case $i: $raw -> $actual');
      }
    }
  });

  test('DEEP XML serializer exhausts all 1114112 codepoint values', () {
    final escaped = {
      38: '&amp;',
      60: '&lt;',
      62: '&gt;',
      34: '&quot;',
      39: '&apos;'
    };
    for (var c = 0; c <= 0x10ffff; c++) {
      final source = String.fromCharCode(c);
      final actual = OpenXmlText.escape(source);
      final expected = xmlScalar(c) ? (escaped[c] ?? source) : '\ufffd';
      if (actual != expected) {
        fail('XML serialization mismatch U+${c.toRadixString(16)}');
      }
    }
  });
  for (final format in ['docx', 'xlsx']) {
    test('DEEP $format rejects XML-illegal scalars but preserves emoji', () {
      const hostile =
          'Суп\u0000\u0001\u000b\u000c\u001f\ufffe\uffff\ud800X\udfff &<> 🍲🥩';
      final base = fixture(100);
      final dish =
          base.copyWith(title: hostile, showTitleInExport: true, ingredients: [
        base.ingredients.single.copyWith(
            product: base.ingredients.single.product.copyWith(name: hostile))
      ]);
      final bytes = format == 'docx'
          ? DocxBlankGenerator.generate(dish)
          : XlsxBlankGenerator.generate(dish);
      final archive = ZipDecoder().decodeBytes(bytes);
      final all = <String>[];
      for (final file in archive.files.where((f) => f.name.endsWith('.xml'))) {
        final xml = utf8.decode(file.content as List<int>);
        expect(xml.runes.where((c) => !xmlScalar(c)), isEmpty,
            reason: file.name);
        all.add(xml);
      }
      expect(all.join(), contains('🍲🥩'));
      expect(all.join(), contains('&amp;&lt;&gt;'));
      final out = Directory('../audit_artifacts/mega/deep_unicode')
        ..createSync(recursive: true);
      File('${out.path}/controls.$format').writeAsBytesSync(bytes);
    });
  }
  test('DEEP XLSX literal OOXML escape sequences stay literal', () {
    final base = fixture(100);
    final d = base.copyWith(
        title: '_x0041_ _x000A_ _x005F_',
        showTitleInExport: true,
        ingredients: [
          base.ingredients.single.copyWith(
              product: base.ingredients.single.product
                  .copyWith(name: '_x0041_ literal'))
        ]);
    final bytes = XlsxBlankGenerator.generate(d);
    final archive = ZipDecoder().decodeBytes(bytes);
    final xml = utf8.decode(
        archive.findFile('xl/worksheets/sheet1.xml')!.content as List<int>);
    final out = Directory('../audit_artifacts/mega/deep_unicode')
      ..createSync(recursive: true);
    File('${out.path}/literal.xlsx').writeAsBytesSync(bytes);
    expect(xml, contains('_x005F_x0041_'));
    expect(xml, contains('_x005F_x000A_'));
    expect(xml, contains('_x005F_x005F_'));
  });
}
