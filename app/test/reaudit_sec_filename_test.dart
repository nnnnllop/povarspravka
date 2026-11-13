// RE-AUDIT (security-privacy-auditor): path traversal / filename safety.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:povarspravka/core/calculation/models/dish.dart';
import 'package:povarspravka/core/calculation/models/ingredient.dart';
import 'package:povarspravka/core/calculation/models/product.dart';
import 'package:povarspravka/core/export/export_service.dart';

final Directory outDir = () {
  final base = Platform.environment['TEMP'] ??
      Platform.environment['TMP'] ??
      Directory.systemTemp.path;
  final d = Directory('$base\\povar_reaudit\\sec');
  d.createSync(recursive: true);
  return d;
}();

Dish mkDish(String title) => Dish(
      id: 'sec',
      title: title,
      showTitleInExport: true,
      ingredients: [
        Ingredient(
          id: 'i0',
          product: const Product(
            id: 1,
            code: '1',
            name: 'Свекла',
            groupId: 1,
            source: 'skurikhin',
            protein: 1.5,
            fat: 0.1,
            carbs: 8.8,
            kcal: 42,
          ),
          weightGrams: 100,
          isGross: false,
        ),
      ],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final payloads = <String, String>{
    'dotdot_unix': '../../evil',
    'dotdot_win': r'..\..\evil',
    'abs_win': r'C:\Windows\evil',
    'abs_unix': '/etc/passwd',
    'unc': r'\\server\share\evil',
    'dotdot_deep': '../../../../../../../../../../tmp/pwn',
    'con': 'CON',
    'nul': 'NUL',
    'con_ext': 'CON.txt',
    'com1': 'COM1',
    'lpt9': 'LPT9',
    'mixed_case': 'con',
    'illegal': 'a<b>c:d"e|f?g*h',
    'trailing_dot': 'evil.',
    'trailing_space': 'evil ',
    'trailing_dot_space': 'evil. . ',
    'only_dots': '...',
    'only_slashes': '////',
    'long300': 'Ж' * 300,
    'emoji': '🍲 Борщ 🥘',
    'newline': 'evil\nname',
    'nul_byte': 'evil\u0000name',
    'space_eater': 'CON .txt',
    'ads': 'evil:stream',
  };

  group('fileBaseTitle sanitization', () {
    for (final e in payloads.entries) {
      test('"${e.key}"', () {
        final out = ExportService.fileBaseTitle(e.value);
        // ignore: avoid_print
        print('FILENAME[${e.key}] in=${e.value.replaceAll('\n', r'\n').replaceAll('\u0000', r'\u0000')}'
            ' -> out="$out"');
        // Invariants that MUST hold for any filesystem:
        expect(out, isNot(contains('/')), reason: 'path separator leaked');
        expect(out, isNot(contains(r'\')), reason: 'path separator leaked');
        expect(RegExp(r'[\x00-\x1f\x7f]').hasMatch(out), isFalse,
            reason: 'control char leaked');
        expect(RegExp(r'[<>:"|?*]').hasMatch(out), isFalse,
            reason: 'illegal Windows char leaked');
        expect(out.endsWith('.'), isFalse, reason: 'trailing dot');
        expect(out.endsWith(' '), isFalse, reason: 'trailing space');
        expect(out, isNotEmpty, reason: 'empty basename');
        expect(p.basename(out), out, reason: 'basename != itself');
        expect(p.isAbsolute(out), isFalse, reason: 'absolute path produced');
        expect(RegExp(r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\.|$)',
                caseSensitive: false)
            .hasMatch(out), isFalse, reason: 'reserved device name');
        // Byte-length bound (fs component limit is typically 255 bytes).
        expect(
            // utf8 length approximated by rune-safe check below
            out.runes
                .map((r) => Uri.encodeFull(String.fromCharCode(r)).length)
                .fold<int>(0, (a, b) => a + b),
            lessThanOrEqualTo(255));
      });
    }

    test('300-char title is truncated to <= 80 bytes', () {
      final out = ExportService.fileBaseTitle('Ж' * 300);
      final bytes = out.runes
          .map((r) => String.fromCharCode(r).codeUnits.length == 1 ? 2 : 4)
          .fold<int>(0, (a, b) => a + b);
      // ignore: avoid_print
      print('FILENAME[long300] out="$out" runes=${out.runes.length} '
          'approxUtf8Bytes=$bytes');
      expect(out.runes.length, lessThanOrEqualTo(40));
    });
  });

  group('real share_file path (mocked path_provider + share_plus)', () {
    test('traversal title never escapes the staging dir', () async {
      final tmp = await Directory.systemTemp.createTemp('povar_sec_share_');
      addTearDown(() async {
        try {
          await tmp.delete(recursive: true);
        } catch (_) {}
      });
      const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
      const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
      final handed = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathChannel, (call) async => tmp.path);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(shareChannel, (call) async {
        final args = call.arguments as Map;
        handed.addAll((args['paths'] as List).cast<String>());
        return null;
      });

      for (final e in payloads.entries) {
        handed.clear();
        await ExportService.shareFile(mkDish(e.value), ExportType.xlsx);
        for (final path in handed) {
          // ignore: avoid_print
          print('SHARE[${e.key}] produced="$path"');
          final resolved = p.normalize(p.absolute(path));
          final tmpNorm = p.normalize(p.absolute(tmp.path));
          expect(p.isWithin(tmpNorm, resolved), isTrue,
              reason: 'PATH ESCAPED staging dir for ${e.key}: $resolved');
          expect(p.basename(path), isNot(equals('.')), reason: 'collapsed');
        }
      }
      // Anything from the payload must not have been created outside.
      final evil1 = File(p.join(Directory.current.path, 'evil.xlsx'));
      final evil2 = File(p.join(tmp.path, '..', '..', 'evil.xlsx'));
      expect(await evil1.exists(), isFalse);
      expect(await evil2.exists(), isFalse);
    });
  });
}
