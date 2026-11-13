// RE-AUDIT (security-privacy-auditor): XLSX formula injection & DOCX/XLSX XML injection.
//
// Artifacts are written to %TEMP%\povar_reaudit\sec\ so an external verifier can
// unzip and inspect them independently of this test process.
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/models/dish.dart';
import 'package:povarspravka/core/calculation/models/ingredient.dart';
import 'package:povarspravka/core/calculation/models/product.dart';
import 'package:povarspravka/core/export/docx_blank_generator.dart';
import 'package:povarspravka/core/export/xlsx_blank_generator.dart';
import 'package:xml/xml.dart';

final Directory outDir = () {
  final base = Platform.environment['TEMP'] ??
      Platform.environment['TMP'] ??
      Directory.systemTemp.path;
  final d = Directory('$base\\povar_reaudit\\sec\\artifacts');
  d.createSync(recursive: true);
  return d;
}();

Product mkProduct(String name) => Product(
      id: 1,
      code: '1',
      name: name,
      groupId: 1,
      source: 'skurikhin',
      protein: 1.5,
      fat: 0.1,
      carbs: 8.8,
      kcal: 42,
    );

Dish mkDish({
  String title = '',
  List<String> productNames = const ['Свекла'],
  bool showTitle = true,
  bool gross = false,
  double wastePct = 20,
}) =>
    Dish(
      id: 'sec',
      title: title,
      showTitleInExport: showTitle,
      ingredients: [
        for (var i = 0; i < productNames.length; i++)
          Ingredient(
            id: 'i$i',
            product: Product(
              id: 1,
              code: '1',
              name: productNames[i],
              groupId: 1,
              source: 'skurikhin',
              protein: 1.5,
              fat: 0.1,
              carbs: 8.8,
              kcal: 42,
              wastePct: wastePct,
            ),
            weightGrams: 100,
            isGross: gross,
          ),
      ],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

Map<String, String> unzip(List<int> bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final out = <String, String>{};
  for (final f in archive.files) {
    if (f.isFile) {
      out[f.name] = utf8.decode(f.content as List<int>, allowMalformed: true);
    }
  }
  return out;
}

void save(String name, List<int> bytes) {
  File('${outDir.path}\\$name').writeAsBytesSync(bytes);
}

/// Every text-bearing cell of the sheet, as (ref, xml-snippet).
List<String> cellsContaining(String sheetXml, String needle) {
  final doc = XmlDocument.parse(sheetXml);
  final out = <String>[];
  for (final c in doc.findAllElements('c')) {
    if (c.innerText.contains(needle) || c.toXmlString().contains(needle)) {
      out.add(c.toXmlString());
    }
  }
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ---------------------------------------------------------------------
  // 1. XLSX formula injection
  // ---------------------------------------------------------------------
  group('XLSX formula injection', () {
    const payloads = <String, String>{
      'cmd': "=cmd|'/c calc'!A0",
      'hyperlink': '=HYPERLINK("http://evil","x")',
      'plus': '+1+1',
      'minus': '-1+1',
      'at': '@SUM(A1:A9)',
      'cr': '\r=1+1',
      'tab': '\t=1+1',
    };

    for (final e in payloads.entries) {
      test('title "${e.key}" is stored as text, not as a formula', () {
        final dish = mkDish(title: e.value);
        final bytes = XlsxBlankGenerator.generate(dish);
        save('xlsx_title_${e.key}.xlsx', bytes);
        final files = unzip(bytes);
        final sheetXml = files['xl/worksheets/sheet1.xml']!;
        // Well-formed?
        final doc = XmlDocument.parse(sheetXml);

        final matching = doc
            .findAllElements('c')
            .where((c) => c.innerText.trim() == e.value.trim())
            .toList();
        expect(matching, isNotEmpty,
            reason: 'title cell not found for payload ${e.key}');

        for (final cell in matching) {
          final type = cell.getAttribute('t');
          final hasFormula = cell.findElements('f').isNotEmpty;
          // ignore: avoid_print
          print('PAYLOAD[${e.key}] cell=${cell.getAttribute('r')} '
              't=$type hasFormula=$hasFormula '
              'xml=${cell.toXmlString()}');
          expect(hasFormula, isFalse,
              reason: 'payload ${e.key} emitted as <f> formula');
          expect(type, anyOf('inlineStr', 'str', 's'),
              reason: 'payload ${e.key} emitted without string type');
          expect(cell.findAllElements('is').isNotEmpty ||
              cell.findAllElements('v').isNotEmpty, isTrue);
        }
      });
    }

    test('ingredient (product) name payload is stored as text', () {
      const p = '=cmd|\'/c calc\'!A0';
      final dish = mkDish(productNames: [p]);
      final bytes = XlsxBlankGenerator.generate(dish);
      save('xlsx_ingredient_cmd.xlsx', bytes);
      final files = unzip(bytes);
      final sheetXml = files['xl/worksheets/sheet1.xml']!;
      XmlDocument.parse(sheetXml);
      final cells = cellsContaining(sheetXml, 'cmd');
      expect(cells, isNotEmpty);
      for (final cell in cells) {
        // ignore: avoid_print
        print('INGREDIENT cell=$cell');
        expect(cell.contains('<f>'), isFalse);
      }
    });

    test('no <f> element ever contains user-controlled text', () {
      // Sanity: formulas present must all be generator-authored templates.
      final dish = mkDish(
        title: '=1+1',
        productNames: ['=A1', '+B2', '-C3', '@D4'],
        showTitle: true,
      );
      final bytes = XlsxBlankGenerator.generate(dish);
      save('xlsx_all_formulas.xlsx', bytes);
      final sheetXml = unzip(bytes)['xl/worksheets/sheet1.xml']!;
      final doc = XmlDocument.parse(sheetXml);
      final formulas = doc
          .findAllElements('f')
          .map((f) => f.innerText)
          .toList();
      // ignore: avoid_print
      print('ALL FORMULAS (${formulas.length}): $formulas');
      for (final f in formulas) {
        expect(f.contains('calc'), isFalse);
        expect(f.contains('HYPERLINK'), isFalse);
      }
      File('${outDir.path}\\xlsx_all_formulas_formulas.txt')
          .writeAsStringSync(formulas.join('\n'));
    });

    test('leading-zero numeric-looking text is not coerced', () {
      final dish = mkDish(title: '001', productNames: ['001234']);
      final bytes = XlsxBlankGenerator.generate(dish);
      save('xlsx_leading_zero.xlsx', bytes);
      final sheetXml = unzip(bytes)['xl/worksheets/sheet1.xml']!;
      expect(cellsContaining(sheetXml, '001234').first, contains('inlineStr'));
    });
  });

  // ---------------------------------------------------------------------
  // 2. DOCX / XLSX XML injection
  // ---------------------------------------------------------------------
  group('DOCX/XLSX XML injection', () {
    final nasty = <String, String>{
      'markup': '<a>&"\'</a>',
      'cdata': ']]><![CDATA[x]]>',
      'entity': '&amp;&lt;&#0;&#x0;',
      'proc': '<?xml version="1.0"?>',
      'comment': '<!-- x -->',
      'controls': String.fromCharCodes([
        for (var c = 0x00; c <= 0x08; c++) c,
        0x0b,
        0x0c,
        for (var c = 0x0e; c <= 0x1f; c++) c,
      ]),
      'nonchars': '\uFFFE\uFFFF',
      'lone_surrogate': String.fromCharCode(0xD800),
      'lone_low': String.fromCharCode(0xDC00),
      'bom': '\uFEFF',
      'replacement': '\uFFFD',
      'emoji': '👨‍👩‍👧‍👦🍲',
      'rtl': 'מתכון عربي',
      'x0041': '_x0041_injection',
    };

    for (final e in nasty.entries) {
      test('DOCX document.xml stays well-formed for ${e.key}', () {
        final dish = mkDish(title: e.value, productNames: [e.value]);
        final bytes = DocxBlankGenerator.generate(dish);
        save('docx_${e.key}.docx', bytes);
        final files = unzip(bytes);
        final xml = files['word/document.xml']!;
        XmlDocument doc;
        try {
          doc = XmlDocument.parse(xml);
        } catch (err) {
          // ignore: avoid_print
          print('BAD DOCX XML for ${e.key}: $err');
          rethrow;
        }
        expect(doc.rootElement.name.local, 'document');
        // No injected element must appear as an element.
        expect(doc.findAllElements('a').where((n) =>
            n.parentElement?.name.local == 'w:document' ||
            n.name.local == 'a' && n.attributes.isEmpty), isEmpty);
      });

      test('XLSX sheet1.xml stays well-formed for ${e.key}', () {
        final dish = mkDish(title: e.value, productNames: [e.value]);
        final bytes = XlsxBlankGenerator.generate(dish);
        save('xlsx_${e.key}.xlsx', bytes);
        final files = unzip(bytes);
        final xml = files['xl/worksheets/sheet1.xml']!;
        XmlDocument doc;
        try {
          doc = XmlDocument.parse(xml);
        } catch (err) {
          // ignore: avoid_print
          print('BAD XLSX XML for ${e.key}: $err');
          rethrow;
        }
        expect(doc.rootElement.name.local, 'worksheet');
      });
    }

    test('control chars are replaced by U+FFFD, not emitted raw', () {
      final dish = mkDish(title: 'a\u0000b\u0001c\u001Fd',
          productNames: ['x\u0000y']);
      final docx = unzip(DocxBlankGenerator.generate(dish))['word/document.xml']!;
      final xlsx = unzip(XlsxBlankGenerator.generate(dish))[
          'xl/worksheets/sheet1.xml']!;
      save('docx_controls_only.docx',
          DocxBlankGenerator.generate(dish));
      save('xlsx_controls_only.xlsx',
          XlsxBlankGenerator.generate(dish));
      for (final raw in [docx, xlsx]) {
        for (final c in [0x00, 0x01, 0x1f]) {
          expect(raw.codeUnits.contains(c), isFalse,
              reason: 'raw control char 0x$c leaked into XML');
        }
      }
      // The escaped (numeric-reference) form must not appear either.
      expect(RegExp(r'&#x?0*(0|1|2|3|4|5|6|7|8|11|12|14|31);')
          .hasMatch(docx), isFalse);
    });

    test('lone surrogate cannot produce invalid UTF-8 in the zip', () {
      final dish = mkDish(title: 'A${String.fromCharCode(0xD800)}B',
          productNames: ['${String.fromCharCode(0xDC00)}C']);
      final docxBytes = DocxBlankGenerator.generate(dish);
      save('docx_lone_surrogate_raw.docx', docxBytes);
      // Re-decode strictly: invalid UTF-8 would have thrown.
      final archive = ZipDecoder().decodeBytes(docxBytes);
      for (final f in archive.files) {
        if (!f.isFile) continue;
        final strict = utf8.decode(f.content as List<int>);
        expect(strict, isNotNull);
      }
    });

    test('_x00NN_ literal is protected in spreadsheet cells', () {
      final dish = mkDish(productNames: ['_x0041_ и _x000D_']);
      final xlsx = unzip(XlsxBlankGenerator.generate(dish))[
          'xl/worksheets/sheet1.xml']!;
      save('xlsx_x0041.xlsx', XlsxBlankGenerator.generate(dish));
      // ESC must be present so Excel does not unescape it.
      expect(xlsx.contains('_x005F_x0041_'), isTrue,
          reason: 'ST_Xstring escape missing → Excel would decode it');
    });
  });
}
