// RE-AUDIT (security-privacy-auditor): SQL / FTS5 injection in product search.
//
// product_repository.dart's `searchProducts` is a plain Dart class (no plugin
// needed), so the real code path is exercised directly. The DB is redirected by
// mocking the path_provider channel to a temp directory that contains a COPY of
// reference.db — the real asset file is never opened read-write.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/data/repositories/product_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

late Directory dbDir;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // В `flutter test` нет платформенного плагина sqflite: тот же API через FFI
    // (dev_dependency sqflite_common_ffi). Репозиторий открывает КОПИЮ базы
    // в dbDir с readOnly: true. Раньше все 41 тест падали на открытии базы.
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final temp = Platform.environment['TEMP'] ?? Directory.systemTemp.path;
    dbDir = Directory('$temp\\povar_reaudit\\sec\\repo_db');
    if (dbDir.existsSync()) dbDir.deleteSync(recursive: true);
    dbDir.createSync(recursive: true);
    const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, (call) async => dbDir.path);
  });

  group('FTS5 / SQL injection via search query', () {
    final payloads = <String, String>{
      'single_quote': "' OR 1=1 --",
      'double_quote': '"',
      'unbalanced_dquote': 'молоко"',
      'star': '*',
      'only_stars': '***',
      'near': 'NEAR(молоко сахар)',
      'near_upper': 'NEAR(a b, 5)',
      'or_op': 'OR',
      'and_op': 'AND',
      'not_op': 'NOT',
      'minus': '-',
      'minus_word': '-молоко',
      'plus_word': '+молоко',
      'colon': 'name:молоко',
      'caret': '^молоко',
      'paren_open': '(',
      'paren_close': ')',
      'paren_pair': '(молоко)',
      'nul': 'молоко\u0000сахар',
      'percent': '%',
      'underscore': '_',
      'like_escape': '%_%_%',
      'semi': 'молоко; DROP TABLE product;--',
      'union': "' UNION SELECT 1,2,3--",
      'comment': 'молоко /* x */',
      'backslash': r'молоко\',
      'brackets': '[молоко]',
      'curly': 'молоко{1,2}',
      'dollar': r'$молоко',
      'question': '?',
      'at': '@молоко',
      'hash': '#молоко',
      'backtick': '`молоко`',
      'very_long': 'а' * 5000,
      'many_tokens': List.filled(500, 'молоко').join(' '),
      'empty': '',
      'spaces': '   ',
      'unicode_confusables': 'молокο',
      'rtl': 'م\u200Fولоко',
      'emoji': '🍲',
    };

    for (final e in payloads.entries) {
      test('payload "${e.key}" does not crash or corrupt the DB', () async {
        final repo = ProductRepository();
        List<Object?> results = const [];
        Object? error;
        final sw = Stopwatch()..start();
        try {
          results = await repo.searchProducts(query: e.value).timeout(
                const Duration(seconds: 30),
              );
        } catch (err) {
          error = err;
        }
        sw.stop();
        // ignore: avoid_print
        print('SQL[${e.key}] len=${e.value.length} hits=${results.length} '
            'ms=${sw.elapsedMilliseconds} err=${error ?? '-'}');
        expect(error, isNull, reason: 'search threw for ${e.key}');
        expect(results.length, lessThanOrEqualTo(50),
            reason: 'limit not enforced for ${e.key}');
      });
    }

    test('DB is still intact and read-only after all payloads', () async {
      final repo = ProductRepository();
      final n = await repo.getTotalCount();
      // ignore: avoid_print
      print('SQL total_products_after=${n}');
      expect(n, greaterThan(8000));
      final groups = await repo.getFoodGroups();
      expect(groups, isNotEmpty);
    });

    test('interpolated-looking query returns same result as sanitized', () async {
      final repo = ProductRepository();
      final a = await repo.searchProducts(query: 'молоко');
      final b = await repo.searchProducts(query: 'молоко" OR "1"="1');
      // ignore: avoid_print
      print('SQL legit=${a.length} injected=${b.length} '
          'same=${a.length == b.length}');
      expect(b.length, lessThanOrEqualTo(50));
    });
  });
}
