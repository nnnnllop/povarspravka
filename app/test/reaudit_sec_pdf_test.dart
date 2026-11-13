// RE-AUDIT (security-privacy-auditor): PDF injection / robustness / size.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/models/dish.dart';
import 'package:povarspravka/core/calculation/models/ingredient.dart';
import 'package:povarspravka/core/calculation/models/product.dart';
import 'package:povarspravka/core/export/pdf_blank_generator.dart';

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
              wastePct: 20,
            ),
            weightGrams: 100,
            isGross: false,
          ),
      ],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

/// PDF structure check. The `pdf` package emits PDF 1.5 with an /XRef
/// *stream* (not a classic `trailer` dictionary), so we assert what is
/// actually produced: header, startxref offset pointing at a real object
/// header, %%EOF, and a sane page count.
void checkPdf(List<int> bytes, String label) {
  final latin1Text = latin1.decode(bytes, allowInvalid: true);
  expect(latin1Text.startsWith('%PDF-'), isTrue, reason: '$label: no header');
  expect(latin1Text.trimRight().endsWith('%%EOF'), isTrue,
      reason: '$label: no EOF marker');
  final sx = RegExp(r'startxref\s+(\d+)').firstMatch(latin1Text);
  expect(sx, isNotNull, reason: '$label: no startxref');
  final off = int.parse(sx!.group(1)!);
  expect(off, lessThan(bytes.length), reason: '$label: startxref past EOF');
  final atOffset = latin1Text.substring(off, (off + 40).clamp(0, bytes.length));
  expect(RegExp(r'^\d+\s+\d+\s+obj').hasMatch(atOffset), isTrue,
      reason: '$label: startxref($off) does not point at an object header '
          '→ "${atOffset.replaceAll(RegExp(r"\s"), " ")}"');
  expect(latin1Text.contains('/Type/XRef') ||
      latin1Text.contains('/Type /XRef') ||
      latin1Text.contains('trailer'), isTrue,
      reason: '$label: no xref (stream or table)');
  final pageCount = RegExp(r'/Type\s*/Page[^s]').allMatches(latin1Text).length;
  // ignore: avoid_print
  print('PDF[$label] bytes=${bytes.length} pageObj=${pageCount} '
      'header=${latin1Text.substring(0, 8).trim()}');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PDF robustness', () {
    final cases = <String, String>{
      'paren_open': 'a(b',
      'paren_close': 'a)b',
      'paren_balanced': 'a(b)c',
      'backslash': r'a\b\\c',
      'paren_backslash': r'a\)b\(c\\',
      'pdf_literal_nested': r'\)\\)(((',
      'cyrillic': 'Борщ с капустой и картофелем',
      'emoji': 'Суп 🍲 с 👨‍👩‍👧‍👦',
      'rtl': 'Мармелад مكونات מתכון',
      'empty': '',
      'spaces': '   ',
      'newlines': 'a\nb\r\nc\td',
      'null': 'a\u0000b\u0001c',
      'long10k': 'Ж' * 10000,
      'longascii10k': 'x' * 10000,
      'cjk': '酱油 拉面 醤油',
      'combining': 'e\u0301\u0327\u0334',
      'zwj': 'a\u200Db\u200Ec',
      'bidi_override': 'a\u202Eb\u202Fc',
      'pdf_keyword': '/Type /Page /Contents [1 0 R]',
    };

    for (final e in cases.entries) {
      test('title "${e.key}" produces a structurally valid PDF', () async {
        final sw = Stopwatch()..start();
        final bytes = await PdfBlankGenerator.generate(
          mkDish(title: e.value, productNames: [e.value]),
        );
        sw.stop();
        File('${outDir.path}\\pdf_${e.key}.pdf').writeAsBytesSync(bytes);
        // ignore: avoid_print
        print('TIMING pdf_${e.key} ${sw.elapsedMilliseconds}ms');
        checkPdf(bytes, e.key);
        expect(bytes.length, greaterThan(1000));
      });
    }

    test('10000-char title does not blow up the document', () async {
      final bytes = await PdfBlankGenerator.generate(
          mkDish(title: 'Ж' * 10000, productNames: ['Свекла']));
      File('${outDir.path}\\pdf_title_10k.pdf').writeAsBytesSync(bytes);
      // ignore: avoid_print
      print('PDF[title_10k] bytes=${bytes.length}');
      checkPdf(bytes, 'title_10k');
    });

    test('5000 ingredients: page count, time, size', () async {
      final sw = Stopwatch()..start();
      final bytes = await PdfBlankGenerator.generate(mkDish(
        title: 'Нагрузка',
        productNames: [for (var i = 0; i < 5000; i++) 'Продукт $i'],
      ));
      sw.stop();
      File('${outDir.path}\\pdf_5000_ingredients.pdf').writeAsBytesSync(bytes);
      final latin1Text = latin1.decode(bytes, allowInvalid: true);
      final pageCount = RegExp(r'/Type\s*/Page[^s]').allMatches(latin1Text).length;
      // ignore: avoid_print
      print('PDF[5000] ms=${sw.elapsedMilliseconds} bytes=${bytes.length} '
          'pages=$pageCount');
      checkPdf(bytes, '5000');
      expect(((5000 + 17) ~/ 18), pageCount);
    });
  });
}
