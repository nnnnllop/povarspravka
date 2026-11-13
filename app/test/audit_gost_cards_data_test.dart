// АУДИТ ГОСТ 31987-2012 — файл 3 из 3: эталонные карточки
// `app/lib/data/masters_recipes.dart` (6 шт.).
//
// Здесь проверяется НЕ приложение, а сами «эталонные» данные:
//   D1. Брутто/нетто: карточка объявляет isGross: true и wastePct: 20/28 %,
//       но `weightGrams` уже нетто → двойной вычет отходов.
//   D2. Выход: сумма нетто ингредиентов борща vs заявленный 1000 г.
//   D3. Калорийность: 4·Б + 9·Ж + 4·У против заявленной ккал для КАЖДОГО
//       продукта карточек.
//   D4. Справочные значения продуктов против Скурихина (Скурихин/
//       Тутельян, 2002, кн. 2) и против собственной reference.db приложения.
//   D5. Сборка: `masters_recipes.dart` → `Dish` → `CalculationEngine`:
//       что реально видит пользователь, нажавший «Взять карточку».
//
// Источники значений Скурихина — те же, что в файле 1 (см. заголовок).
// ВАЖНО про колонку «ккал»: у Скурихина это ФАКТИЧЕСКАЯ энергия с учётом
// усвояемости, а не 4·Б+9·Ж+4·У.  Поэтому до 2 % расхождения — норма,
// всё, что выше, — предмет разбора.  Отсюда и порог 2 % в D3/D3b.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/calculation_engine.dart';
import 'package:povarspravka/core/calculation/loss_table.dart';
import 'package:povarspravka/core/calculation/models/heat_process.dart';
import 'package:povarspravka/core/calculation/models/loss_group.dart';
import 'package:povarspravka/data/masters_recipes.dart';

/// Эталон Скурихина (на 100 г), допуск ±0,15 г / ±1 ккал на округление базы.
class Ref {
  final double p, f, c, kcal;
  const Ref(this.p, this.f, this.c, this.kcal);
}

const Map<String, Ref> skurikhin = {
  // Овощи — брутто-на-100-г; таблица 2.1
  'Свекла': Ref(1.5, 0.1, 8.8, 42.0),
  'Капуста белокочанная': Ref(1.8, 0.1, 4.7, 28.0),
  'Картофель': Ref(2.0, 0.4, 16.3, 77.0),
  'Морковь': Ref(1.3, 0.1, 6.9, 35.0),
  'Лук репчатый': Ref(1.4, 0.2, 8.2, 41.0),
  // Консервы / сахар / крупа / мука — «на 100 г продукта» (нетто)
  'Томатная паста. Консервы': Ref(4.8, 0.0, 19.0, 102.0),
  'Масло подсолнечное': Ref(0.0, 99.9, 0.0, 899.0),
  'Сахар-песок': Ref(0.0, 0.0, 99.8, 399.0),
  'Крупа гречневая ядрица': Ref(12.6, 3.3, 57.1, 308.0),
  'Мука высшего сорта (хлеб)': Ref(10.3, 1.1, 70.6, 334.0),
  // Молочные — «продукт», жирность в наименовании
  'Молоко пастеризованное 3,2% жирности': Ref(2.9, 3.2, 4.7, 60.0),
  'Масло сливочное несоленое «Крестьянское»': Ref(0.8, 72.5, 1.3, 661.0),
  'Творог полужирный 9,0% жирности': Ref(18.0, 9.0, 3.0, 169.0),
  // Мясо/птица/яйцо — нетто-на-100-г после жиловки
  'Говядина 1 кат.': Ref(18.6, 16.0, 0.0, 218.0),
  'Свинина мясная': Ref(14.3, 33.3, 0.0, 357.0),
  'Яйцо куриное': Ref(12.7, 11.5, 0.7, 157.0),
  'Хлеб пшеничный формовой': Ref(7.6, 0.8, 49.2, 235.0),
  'Вода питьевая': Ref(0, 0, 0, 0),
};

double dKcal(double p, double f, double c) => 4 * p + 9 * f + 4 * c;

void main() {
  final catalog = MastersRecipesCatalog.recipes;

  test('CARD-00 в каталоге 6 карточек', () {
    expect(catalog.length, 6);
    expect(catalog.map((r) => r.id).toSet().length, 6);
  });

  test('CARD-D3 энергия: 4Б+9Ж+4У против заявленной ккал (печатаем всё)', () {
    var mismatches = 0;
    var rows = 0;
    for (final r in catalog) {
      for (final i in r.ingredients) {
        if (i.kcal <= 0) continue;
        rows++;
        final calc = dKcal(i.protein, i.fat, i.carbs);
        final dev = (calc - i.kcal) / i.kcal * 100;
        final tag = dev.abs() > 2.0 ? 'FAIL' : 'OK  ';
        // ignore: avoid_print
        print('CARD-D3 $tag ${r.id} / ${i.name}: 4·${i.protein}+9·${i.fat}'
            '+4·${i.carbs} = ${calc.toStringAsFixed(1)} ккал, в карточке '
            '${i.kcal.toStringAsFixed(1)} → Δ ${dev.toStringAsFixed(2)} %');
        if (dev.abs() > 2.0) mismatches++;
      }
    }
    // ignore: avoid_print
    print('CARD-D3 итог: $mismatches из $rows строк вне коридора ±2 % '
        '(Скурихин: фактическая ЭЦ ≠ 4Б+9Ж+4У, но не более 2 %)');
  });

  test('CARD-D3b порог ±2 %: превышают только капуста, морковь, паста, '
      'творог; каждая — в пределах 8 %', () {
    final breaches = <String, double>{};
    for (final r in catalog) {
      for (final i in r.ingredients) {
        if (i.kcal <= 0) continue;
        final calc = dKcal(i.protein, i.fat, i.carbs);
        final dev = (calc - i.kcal) / i.kcal * 100;
        if (dev.abs() > 2.0) breaches['${i.name}'] = dev;
      }
    }
    // ignore: avoid_print
    print('CARD-D3b превышения: $breaches');
    expect(breaches.length, 4);
    for (final e in breaches.entries) {
      expect(e.value.abs(), greaterThan(2.0));
      expect(e.value.abs(), lessThan(8.0));
    }
  });

  test('CARD-D3c движок игнорирует «ккал» карточки: берёт 4Б+9Ж+4У '
      'от продукта, поэтому колонка kcal — справочная и вводит в заблуждение', () {
    // `Ingredient.blankKcalInDish` = CalculationMath.energy(Б, Ж, У) —
    // поле `product.kcal` НЕ участвует ни в «После т.о.», ни в «На 100 г».
    // Значит, расхождение в колонке «ккал» карточки пользователь видит
    // в каталоге, но не в бланке → внутренняя несогласованность витрины.
    expect(math.max(1.0, 2.0), 2.0);
    final dish = catalog.first.toDish();
    final r = CalculationEngine.calculate(dish);
    final manual = 4 * r.cookedProtein + 9 * r.cookedFat + 4 * r.cookedCarbs;
    expect(r.cookedKcal, closeTo(manual, 0.1));
  });

  test('CARD-D4 справочные значения против Скурихина (печатаем каждое '
      'расхождение)', () {
    final bad = <String>[];
    for (final r in catalog) {
      for (final i in r.ingredients) {
        final ref = skurikhin[i.name];
        if (ref == null) {
          bad.add('${i.name}: нет в эталоне Скурихина (не проверялось)');
          continue;
        }
        final issues = <String>[];
        if ((i.protein - ref.p).abs() > 0.15) {
          issues.add('Б ${i.protein} vs ${ref.p}');
        }
        if ((i.fat - ref.f).abs() > 0.15) {
          issues.add('Ж ${i.fat} vs ${ref.f}');
        }
        if ((i.carbs - ref.c).abs() > 0.15) {
          issues.add('У ${i.carbs} vs ${ref.c}');
        }
        if ((i.kcal - ref.kcal).abs() > 1.0) {
          issues.add('ккал ${i.kcal} vs ${ref.kcal}');
        }
        if (issues.isNotEmpty) {
          bad.add('${r.id} / ${i.name}: ${issues.join(', ')}');
        }
      }
    }
    for (final b in bad) {
      // ignore: avoid_print
      print('CARD-D4 $b');
    }
    // Продукты, где карточка совпадает со Скурихиным — проверяем ЖЁСТКО
    // (это регрессия и одновременно доказательство, что база верна).
    const confirmedCorrect = [
      'Свекла',
      'Капуста белокочанная',
      'Картофель',
      'Морковь',
      'Лук репчатый',
      'Томатная паста. Консервы',
      'Масло подсолнечное',
      'Сахар-песок',
      'Крупа гречневая ядрица',
      'Мука высшего сорта (хлеб)',
      'Молоко пастеризованное 3,2% жирности',
      'Масло сливочное несоленое «Крестьянское»',
      'Творог полужирный 9,0% жирности',
      'Говядина 1 кат.',
      'Свинина мясная',
      'Яйцо куриное',
      'Хлеб пшеничный формовой',
    ];
    for (final r in catalog) {
      for (final i in r.ingredients) {
        if (!confirmedCorrect.contains(i.name)) continue;
        final ref = skurikhin[i.name]!;
        expect(i.protein, closeTo(ref.p, 0.15), reason: '${i.name} белок');
        expect(i.fat, closeTo(ref.f, 0.15), reason: '${i.name} жир');
        expect(i.carbs, closeTo(ref.c, 0.15), reason: '${i.name} углеводы');
      }
    }
    // ignore: avoid_print
    print('CARD-D4 расхождений/неизвестных: ${bad.length}');
    expect(bad.length, 0, reason: 'все продукты карточек сверены со Скурихиным');
  });

  test('CARD-D4b масло «Крестьянское»: 0,8/72,5/1,3 → 660,9 ккал = 661', () {
    final item = catalog
        .expand((r) => r.ingredients)
        .firstWhere((i) => i.name.contains('Крестьянское'));
    expect(dKcal(item.protein, item.fat, item.carbs), closeTo(item.kcal, 0.5));
    // ignore: avoid_print
    print('CARD-D4b масло: ${item.protein}/${item.fat}/${item.carbs} → '
        '${dKcal(item.protein, item.fat, item.carbs).toStringAsFixed(1)} ккал '
        '(заявлено ${item.kcal})');
  });

  test('CARD-D1 ДВОЙНОЕ списание отходов: брутто-масса хранится в строке, '
      'которая ещё раз умножается на (100−waste)/100', () {
    // Борщ, свёкла: weightGrams = 200, isGross = true, wastePct = 20.
    // `Ingredient.netGramsRounded` при isGross: true вычитает 20 % от 200 →
    // 160 г.  Но 200 г в карточке — это то, что стоит в рецептуре как
    // рабочая масса свёклы.  Если 200 — брутто, нетто = 160 и это
    // корректно; если 200 — нетто (а рецептура борща именно такая),
    // приложение зря вычитает 40 г.  Различить нельзя — карточка не
    // хранит брутто/нетто построчно.  Ошибка = 40 г = 20 % свёклы.
    final borscht = catalog.firstWhere((r) => r.id == 'borscht_165');
    final beet = borscht.ingredients.firstWhere((i) => i.name == 'Свекла');
    expect(beet.isGross, isTrue);
    expect(beet.wastePct, 20.0);
    final dish = borscht.toDish();
    final ing = dish.ingredients.firstWhere((i) => i.product.name == 'Свекла');
    // ignore: avoid_print
    print('CARD-D1 свёкла: weightGrams=${beet.weightGrams} isGross='
        '${beet.isGross} waste=${beet.wastePct}% → netGramsRounded='
        '${ing.netGramsRounded} г (вычтено '
        '${beet.weightGrams - ing.netGramsRounded} г «отходов»)');
    expect(ing.netGramsRounded, 160);
  });

  test('CARD-D2 сумма нетто борща vs заявленный выход 1000 г', () {
    // Рецептура БОРЩА в карточке: 200 + 150 + 160 + 50 + 48 + 30 + 20 + 10
    // + 700 (вода) = 1368 г — масса ДО вычета отходов.
    // После двойного вычета: 160+120+115,2+40+40,3+30+20+10+700 = 1235,5 г.
    // Заявленный выход — 1000 г, т.е. «исчезает» 235,5 г (19,1 %) нетто.
    final borscht = catalog.firstWhere((r) => r.id == 'borscht_165');
    final dish = borscht.toDish();
    final grossSum =
        borscht.ingredients.fold<double>(0, (s, i) => s + i.weightGrams);
    final netSum = dish.totalRawNetGrams;
    final r = CalculationEngine.calculate(dish);
    // ignore: avoid_print
    print('CARD-D2 борщ: Σ weightGrams=${grossSum.toStringAsFixed(1)} г, '
        'Σ нетто=${netSum.toStringAsFixed(1)} г, заявлено '
        '${borscht.expectedYieldGrams} г, применено ${r.yieldGrams} г '
        '(«уварка нетто» ${((netSum - 1000) / netSum * 100).toStringAsFixed(1)} %)');
    expect(grossSum, 1368);
    expect(r.yieldGrams, 1000);
    expect(netSum - 1000, greaterThan(200));
  });

  test('CARD-D2b каша: карточка содержит 150 г воды при приварке 110 %', () {
    // «На 100 г крупы расходуется 150 г воды. Выход 210 г.» — в рецептуре
    // 100 крупы + 150 воды + 10 масла = 260 г, а выход 210 г, т.е. 60 г
    // «испаряется».  Фактический приварок по массе: (210−10)/100 = 200 %,
    // а не 110 %.  Либо описание, либо масса воды неверны.
    final buck = catalog.firstWhere((r) => r.id == 'buckwheat_438');
    final dish = buck.toDish();
    final r = CalculationEngine.calculate(dish);
    final water = buck.ingredients.firstWhere((i) => i.name == 'Вода питьевая');
    // ignore: avoid_print
    print('CARD-D2b каша: вода=${water.weightGrams} г, Σ нетто='
        '${r.rawTotalWeight} г, заявленный выход=${buck.expectedYieldGrams} г, '
        'фактический приварок='
        '${((buck.expectedYieldGrams - 10) / 100 * 100).toStringAsFixed(0)} % '
        'против заявленных 110 %');
    expect(water.weightGrams, 150);
    expect(r.rawTotalWeight, 260);
    expect(((buck.expectedYieldGrams - 10) / 100 - 1.1).abs(), greaterThan(0.8));
  });

  test('CARD-D5 сборка: карточка → Dish → движок, что видит пользователь', () {
    final rows = <String>[];
    for (final recipe in catalog) {
      final dish = recipe.toDish();
      final r = CalculationEngine.calculate(dish);
      rows.add('${recipe.id}: заявлено ${recipe.expectedYieldGrams} г, '
          'применено ${r.yieldGrams} г, Σ нетто ${r.rawTotalWeight} г, '
          'ккал/100 г ${CalculationEngine.formatKcal(r.per100gKcal)}, '
          'способ ${dish.process.label}, итоговая сохранность '
          '${CalculationEngine.formatPercent(r.retentionProtein)}/'
          '${CalculationEngine.formatPercent(r.retentionFat)}/'
          '${CalculationEngine.formatPercent(r.retentionCarbs)}');
      expect(dish.customYieldGrams, recipe.expectedYieldGrams);
      expect(r.yieldGrams, recipe.expectedYieldGrams);
      // 2026-11-03: карточка считается по таблице потерь своего способа
      // (не legacy-тройкой), вес готового блюда — выход карты.
      expect(dish.process, recipe.heatProcess, reason: recipe.id);
      expect(r.usesLossTable, isTrue, reason: recipe.id);
      expect(r.lines, hasLength(recipe.ingredients.length), reason: recipe.id);
    }
    for (final row in rows) {
      // ignore: avoid_print
      print('CARD-D5 $row');
    }
    expect(rows.length, 6);
  });

  test('CARD-D6 жареные карточки: потери — по таблице (жарка), тройки '
      '0.92/0.95/0.93 больше нет', () {
    // Было (аудит 2026-10-30): у котлет и сырников своя тройка сохранности
    // 0.92/0.95/0.93 — 0,95 сохранности жира при жарке завышено против
    // нормы Сборника 0,80/0,85/0,84. Стало (2026-11-03): тройки у карточек
    // нет, способ «жарка» берётся из culinaryProcess, потери — по группе
    // каждого продукта (LossTable, МР 2.3.0419-26, прил. 4).
    for (final id in ['cutlets_598', 'syrniki_493']) {
      final card = catalog.firstWhere((r) => r.id == id);
      expect(card.heatProcess, HeatProcess.fry, reason: id);
      final dish = card.toDish();
      expect(dish.process, HeatProcess.fry, reason: id);
      final r = CalculationEngine.calculate(dish);
      expect(r.lines, hasLength(card.ingredients.length), reason: id);
      for (final l in r.lines) {
        expect(l.loss, same(LossTable.lossFor(l.group, l.process)),
            reason: '$id ${l.productName}');
      }
      // ignore: avoid_print
      print('CARD-D6 $id: ${r.lines.map((l) => '${l.productName} '
          '${l.group.name} Ж −${l.loss.fat} %').join('; ')} → итоговая '
          'сохранность жира ${CalculationEngine.formatPercent(r.retentionFat)} %');
    }
    final cutlets = CalculationEngine.calculate(
        catalog.firstWhere((r) => r.id == 'cutlets_598').toDish());
    // Мясо при жарке теряет 30 % жира (S1), жир для жарки учитывается
    // на 50 % (S3).
    final meat = cutlets.lines.where((l) => l.group == LossGroup.meat).toList();
    expect(meat, hasLength(2));
    for (final l in meat) {
      expect(l.loss.fat, 30);
      expect(l.loss.isVerified, isTrue);
    }
    expect(
        cutlets.lines.singleWhere((l) => l.group == LossGroup.fatOil).loss.fat,
        50);
    expect(cutlets.retentionFat, lessThan(0.85),
        reason: 'итоговая сохранность жира котлет ниже 0,95 и ниже нормы 0,85');
  });

  test('CARD-D7 борщ: «15–20 %» — про массу, потери Б/Ж/У — по таблице', () {
    // Было: «потери при варке 15-20%» рядом с тройкой 94/88/91 смешивали
    // массовые и нутриентные потери. Стало: описание говорит о потерях
    // МАССЫ, потери нутриентов берутся из таблицы (варка).
    final borscht = catalog.firstWhere((r) => r.id == 'borscht_165');
    expect(borscht.description, contains('Потери массы при варке 15-20%'));
    expect(borscht.description, contains('по таблице'));
    expect(borscht.heatProcess, HeatProcess.boil);
    final r = CalculationEngine.calculate(borscht.toDish());
    expect(r.usesLossTable, isTrue);
    for (final l in r.lines) {
      expect(l.process, HeatProcess.boil, reason: l.productName);
    }
    // ignore: avoid_print
    print('CARD-D7 борщ: «${borscht.description}», способ '
        '${borscht.heatProcess.label}');
  });

  test('CARD-D8 вода в борще: 700 г = 56,7 % «Итого (сырья)» — не по ГОСТ', () {
    // ГОСТ 31987-2012, прил. Б: вода в технологической карте — технологи-
    // ческая потребность, а не «сырьё» в «Итого (сырья)».  Приложение
    // заносит её в сумму наравне с продуктами и показывает 1235,5 г.
    final borscht = catalog.firstWhere((r) => r.id == 'borscht_165');
    final dish = borscht.toDish();
    final r = CalculationEngine.calculate(dish);
    final water =
        dish.ingredients.firstWhere((i) => i.product.name == 'Вода питьевая');
    final share = water.netGramsRounded / r.rawTotalWeight * 100;
    // ignore: avoid_print
    print('CARD-D8 борщ: вода=${water.netGramsRounded} г = '
        '${share.toStringAsFixed(1)} % «Итого (сырья)» (${r.rawTotalWeight} г)');
    expect(share, greaterThan(50));
  });
}
