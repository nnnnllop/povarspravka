// Классификатор продуктов по группам таблицы потерь (задача 2026-11-03, п. 5).
//
// Данные — все продукты `assets/db/reference.db` (база открывается только
// для чтения, см. `support/reference_db.dart`). Проверяется:
//  1. распределение по группам совпадает со снимком
//     `fixtures/classifier_distribution.json` — любая правка словарей
//     классификатора видна в ревью как правка снимка;
//  2. две ручные выборки по 200 продуктов
//     (`fixtures/classifier_manual_sample.json`) — не более 2 % ошибок в каждой;
//  3. дефект аудита 2026-10-30: поиск подстроки («сыр» в «сырой», «жир»
//     в «Инжир» и «Свинина жирная») больше не меняет группу.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/food_classifier.dart';
import 'package:povarspravka/core/calculation/models/loss_group.dart';
import 'package:povarspravka/core/calculation/models/product.dart';

import 'support/reference_db.dart';

Map<String, dynamic> _fixture(String name) =>
    jsonDecode(File('test/fixtures/$name').readAsStringSync())
        as Map<String, dynamic>;

/// Слово целиком: слева и справа — не буква (независимо от токенайзера
/// классификатора).
RegExp _word(String pattern) => RegExp(
      '(?:^|[^а-яёa-z])(?:$pattern)(?=[^а-яёa-z]|\$)',
      caseSensitive: false,
      unicode: true,
    );

String _describe(Product p) =>
    '${p.id} «${p.name}» (group_id ${p.groupId}): '
    '${FoodClassifier.classify(p).name}';

void main() {
  late List<Product> products;
  late Map<int, Product> byId;

  setUpAll(() async {
    products = await loadAllReferenceProducts();
    byId = {for (final p in products) p.id: p};
  });

  group('все продукты reference.db', () {
    test('каждая группа справочника сопоставлена группе таблицы потерь', () {
      final ids = {for (final p in products) p.groupId};
      expect(ids, hasLength(32), reason: '12 групп Скурихина + 20 групп BLS');
      expect(
        ids.where((g) => !FoodClassifier.baseGroupById.containsKey(g)),
        isEmpty,
      );
    });

    test('распределение по группам совпадает со снимком', () {
      final snapshot = _fixture('classifier_distribution.json');
      final byGroup = <String, Map<String, int>>{};
      final totals = <String, int>{};
      for (final p in products) {
        final g = FoodClassifier.classify(p).name;
        final row = byGroup['${p.groupId}'] ??= <String, int>{};
        row[g] = (row[g] ?? 0) + 1;
        totals[g] = (totals[g] ?? 0) + 1;
      }
      final expectedByGroup = {
        for (final e in (snapshot['by_group_id'] as Map<String, dynamic>)
            .entries)
          e.key: (e.value as Map<String, dynamic>).cast<String, int>(),
      };
      final expectedTotals = {
        for (final e
            in (snapshot['totals'] as Map<String, dynamic>).cast<String, int>()
                .entries)
          if (e.value > 0) e.key: e.value,
      };
      final actualJson = const JsonEncoder.withIndent('  ')
          .convert({'totals': totals, 'by_group_id': byGroup});
      expect(products, hasLength(snapshot['total'] as int));
      expect(byGroup, equals(expectedByGroup),
          reason: 'Фактическое распределение:\n$actualJson');
      expect(totals, equals(expectedTotals));
      expect(totals.values.fold<int>(0, (a, b) => a + b), products.length);
    });
  });

  group('ручная выборка (2 × 200 продуктов, допуск 2 %)', () {
    final sample = _fixture('classifier_manual_sample.json');
    final names = {for (final g in LossGroup.values) g.name};

    List<Map<String, dynamic>> itemsOf(String part) =>
        ((sample[part] as Map<String, dynamic>)['items'] as List)
            .cast<Map<String, dynamic>>();

    for (final part in const ['development', 'holdout']) {
      test('$part: не более 4 ошибок из 200', () {
        final items = itemsOf(part);
        expect(items, hasLength(200));
        final errors = <String>[];
        for (final item in items) {
          final id = item['id'] as int;
          final product = byId[id];
          expect(product, isNotNull, reason: 'id $id нет в reference.db');
          expect(product!.name, item['name'],
              reason: 'id $id: название в базе изменилось');
          expect(product.groupId, item['group_id']);
          final expected = (item['expected'] as List).cast<String>();
          expect(expected, isNotEmpty);
          expect(names.containsAll(expected), isTrue,
              reason: 'id $id: неизвестная группа в $expected');
          final actual = FoodClassifier.classify(product).name;
          if (!expected.contains(actual)) {
            errors.add('$id «${product.name}»: $actual, ожидалось $expected');
          }
        }
        // ignore: avoid_print
        print('$part: ошибок ${errors.length} из ${items.length}'
            '${errors.isEmpty ? '' : '\n  ${errors.join('\n  ')}'}');
        expect(errors.length, lessThanOrEqualTo(4), reason: errors.join('\n'));
      });
    }

    test('выборки не пересекаются и без повторов', () {
      final dev = {for (final i in itemsOf('development')) i['id'] as int};
      final hold = {for (final i in itemsOf('holdout')) i['id'] as int};
      expect(dev, hasLength(200));
      expect(hold, hasLength(200));
      expect(dev.intersection(hold), isEmpty);
    });
  });

  group('слова сравниваются целиком (дефект подстроки)', () {
    test('«сырой/сырая/сырец…» вне молочных групп справочника не молочные',
        () {
      final raw = _word('сыр(?:ой|ая|ое|ые|ых|ого|ую|ом|ому|ым|ыми|ец)');
      final hits = products.where((p) => raw.hasMatch(p.name)).toList();
      // В базе таких продуктов более 500 (сырая рыба, сырое мясо…).
      expect(hits.length, greaterThan(500));
      const dairyGroups = {1, 109, 114}; // молочные, мороженое
      final wrong = [
        for (final p in hits)
          if (!dairyGroups.contains(p.groupId) &&
              FoodClassifier.classify(p) == LossGroup.dairy)
            _describe(p),
      ];
      expect(wrong, isEmpty);
    });

    test('«нежирный» и «… без жира» не делают продукт жиром', () {
      final lean = _word('нежирн[а-яё]*');
      final leanHits = products.where((p) => lean.hasMatch(p.name)).toList();
      expect(leanHits.length, greaterThan(50));
      final noFat = products
          .where((p) => p.name.toLowerCase().contains('без жира'))
          .toList();
      expect(noFat.length, greaterThan(500));
      final wrong = [
        for (final p in [...leanHits, ...noFat])
          if (FoodClassifier.classify(p) == LossGroup.fatOil) _describe(p),
      ];
      expect(wrong, isEmpty);
    });

    test('сыры и сырки — молочные', () {
      final cheese = RegExp('^сыр(?:ы|ок|ки)?(?=[^а-яё]|\$)',
          caseSensitive: false, unicode: true);
      final hits = products.where((p) => cheese.hasMatch(p.name)).toList();
      expect(hits.length, greaterThanOrEqualTo(40));
      final wrong = [
        for (final p in hits)
          if (FoodClassifier.classify(p) != LossGroup.dairy) _describe(p),
      ];
      expect(wrong, isEmpty);
    });

    test('спорные названия из аудита', () {
      const cases = <(int, String, LossGroup)>[
        (182, 'Свинина жирная', LossGroup.meat),
        (220, 'Свинина жирная', LossGroup.meat),
        (879, 'Инжир', LossGroup.fruitBerry),
        (880, 'Инжир', LossGroup.fruitBerry),
        (11171, 'Инжир', LossGroup.fruitBerry),
        (11172, 'Инжир', LossGroup.fruitBerry),
        (11173, 'Инжир', LossGroup.fruitBerry),
        (514, 'Жир говяжий', LossGroup.fatOil),
        (22, 'Сыр домашний нежирный', LossGroup.dairy),
        (12133, 'Молоко сырое', LossGroup.dairy),
      ];
      for (final (id, prefix, group) in cases) {
        final p = byId[id];
        expect(p, isNotNull, reason: 'id $id');
        expect(p!.name, startsWith(prefix));
        expect(FoodClassifier.classify(p), group, reason: _describe(p));
      }
    });
  });

  group('продукт без группы справочника — по названию', () {
    const cases = <String, LossGroup>{
      'Филе куриное': LossGroup.poultry,
      'Рис отварной': LossGroup.grainPasta,
      'Морской язык в муке, жареный': LossGroup.fish,
      'Салат из сельдерея': LossGroup.vegetable,
      'Сыр российский': LossGroup.dairy,
      'Свинина жирная': LossGroup.meat,
      'Инжир': LossGroup.fruitBerry,
      'Масло сливочное': LossGroup.fatOil,
      'Творог нежирный': LossGroup.dairy,
      'Морковь сырая': LossGroup.rootTuber,
      'Картофель отварной': LossGroup.rootTuber,
      'Говядина тушёная': LossGroup.meat,
      'Яйцо куриное': LossGroup.egg,
      'Фасоль': LossGroup.legumes,
      'Капуста белокочанная': LossGroup.vegetable,
      'Яблоко': LossGroup.fruitBerry,
      'Мука пшеничная': LossGroup.flourBread,
      'Хлеб ржаной': LossGroup.flourBread,
      'Сахар': LossGroup.sugarHoney,
      'Мёд': LossGroup.sugarHoney,
      'Борщ': LossGroup.other,
      'Куриный суп с лапшой': LossGroup.other,
    };
    for (final e in cases.entries) {
      test('«${e.key}» → ${e.value.name}', () {
        expect(FoodClassifier.classifyRaw(0, e.key), e.value);
        // Неизвестный group_id ведёт себя так же, как отсутствующий.
        expect(FoodClassifier.classifyRaw(9999, e.key), e.value);
      });
    }
  });
}
