// АУДИТ ГОСТ 31987-2012 / Сборник рецептур — файл 2 из 3.
//
// Здесь проверяется модель данных приложения:
//   A. вес готового блюда — только введённый поваром. Гидратация круп,
//      уварка и экстракция (`yield_physics.dart`) удалены задачей
//      2026-11-03 — приложение вес не угадывает;
//   B. сохранность — не одна глобальная тройка 0.94/0.88/0.91, а потери
//      ПО ГРУППЕ ПРОДУКТА и способу обработки (`LossTable`, МР 2.3.0419-26;
//      холодный салат — ничего);
//   D. полуфабрикаты: блюдо как ингредиент другого блюда.
//
// ПЕРЕПИСАНО дважды: сначала группы A и B закрепляли ОТСУТСТВИЕ физики,
// затем — модель выхода ГОСТ-01/02/03. Задача 2026-11-03 удалила модель
// выхода, и те же сценарии теперь проверяют упрощённый расчёт (перечень —
// docs/FIX_REPORT_2026-11-03.md). Сверка 10 эталонных карт — в
// `audit_gost_physics_test.dart`.
import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/calculation_engine.dart';
import 'package:povarspravka/core/calculation/loss_table.dart';
import 'package:povarspravka/core/calculation/models/dish.dart';
import 'package:povarspravka/core/calculation/models/heat_process.dart';
import 'package:povarspravka/core/calculation/models/ingredient.dart';
import 'package:povarspravka/core/calculation/models/loss_group.dart';
import 'package:povarspravka/core/calculation/models/product.dart';
import 'package:povarspravka/presentation/providers/dish_provider.dart';

import 'audit_gost_benchmark_test.dart' as bench;

Product mk(String name, double p, double f, double c,
        {double waste = 0, bool? isDish}) =>
    Product(
      id: name.hashCode & 0x7fffffff,
      code: name,
      name: name,
      groupId: 0, // группа потерь — по названию (FoodClassifier)
      source: 'skurikhin',
      wastePct: waste,
      protein: p,
      fat: f,
      carbs: c,
      kcal: 0,
      hasExplicitProtein: true,
      hasExplicitFat: true,
      hasExplicitCarbs: true,
      isDish: isDish,
    );

Dish mkDish(String title, List<Ingredient> ings,
        {double? yieldGrams, double rp = .94, double rf = .88, double rc = .91}) =>
    Dish(
      id: title.hashCode.toRadixString(16),
      title: title,
      ingredients: ings,
      customYieldGrams: yieldGrams,
      retentionProtein: rp,
      retentionFat: rf,
      retentionCarbs: rc,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

String f2(double v) => v.toStringAsFixed(2);
String f1(double v) => v.toStringAsFixed(1);
String rel(double app, double norm) =>
    '${((app - norm) / norm * 100).toStringAsFixed(2)}%';

/// Все 10 рецептур стенда в терминах приложения: нетто-массы + нормативный
/// выход.  Повторяется здесь независимо, чтобы файл 2 не зависел от файла 1.
({String id, String title, double normYield, List<Ingredient> ings, double rp,
    double rf, double rc}) borsch() => (
      id: 'I1',
      title: 'Борщ сибирский',
      normYield: 1000,
      rp: 0.935,
      rf: 0.917,
      rc: 0.918,
      ings: [
        Ingredient(id: 'b1', product: mk('Говядина 1 кат.', 18.6, 16.0, 0), weightGrams: 54),
        Ingredient(id: 'b2', product: mk('Капуста белокочанная', 1.8, .1, 4.7), weightGrams: 120),
        Ingredient(id: 'b3', product: mk('Картофель', 2.0, .4, 16.3), weightGrams: 80),
        Ingredient(id: 'b4', product: mk('Свекла', 1.5, .1, 8.8), weightGrams: 106),
        Ingredient(id: 'b5', product: mk('Морковь', 1.3, .1, 6.9), weightGrams: 20),
        Ingredient(id: 'b6', product: mk('Лук репчатый', 1.4, .2, 8.2), weightGrams: 30),
        Ingredient(id: 'b7', product: mk('Томатная паста', 4.8, 0, 19.0), weightGrams: 20),
        Ingredient(id: 'b8', product: mk('Масло сливочное', .8, 72.5, 1.3), weightGrams: 16),
        Ingredient(id: 'b9', product: mk('Сахар-песок', 0, 0, 99.8), weightGrams: 10),
        Ingredient(id: 'b10', product: mk('Вода питьевая', 0, 0, 0), weightGrams: 544),
      ],
    );

({String id, String title, double normYield, List<Ingredient> ings, double rp,
    double rf, double rc}) cutlets() => (
      id: 'I2',
      title: 'Котлеты домашние',
      normYield: 108,
      rp: 0.80,
      rf: 0.85,
      rc: 0.84,
      ings: [
        Ingredient(id: 'c1', product: mk('Говядина котлетная', 18.6, 28.0, 0), weightGrams: 66),
        Ingredient(id: 'c2', product: mk('Свинина мясная', 14.3, 33.3, 0), weightGrams: 26),
        Ingredient(id: 'c3', product: mk('Хлеб пшеничный', 7.6, .8, 49.2), weightGrams: 18),
        Ingredient(id: 'c4', product: mk('Лук репчатый', 1.4, .2, 8.2), weightGrams: 4),
        Ingredient(id: 'c5', product: mk('Яйцо куриное', 12.7, 11.5, .7), weightGrams: 4.7),
        Ingredient(id: 'c6', product: mk('Вода питьевая', 0, 0, 0), weightGrams: 24),
      ],
    );

({String id, String title, double normYield, List<Ingredient> ings, double rp,
    double rf, double rc}) buckwheat() => (
      id: 'I3',
      title: 'Каша гречневая рассыпчатая',
      normYield: 210,
      rp: 0.965,
      rf: 0.965,
      rc: 0.88,
      ings: [
        Ingredient(id: 'k1', product: mk('Крупа гречневая', 12.6, 3.3, 57.1), weightGrams: 100),
        Ingredient(id: 'k2', product: mk('Вода питьевая', 0, 0, 0), weightGrams: 150),
      ],
    );

({String id, String title, double normYield, List<Ingredient> ings, double rp,
    double rf, double rc}) puree() => (
      id: 'I4',
      title: 'Пюре картофельное',
      normYield: 250,
      rp: 0.97,
      rf: 0.97,
      rc: 0.97,
      ings: [
        Ingredient(id: 'p1', product: mk('Картофель', 2.0, .4, 16.3), weightGrams: 245),
        Ingredient(id: 'p2', product: mk('Молоко 3,2%', 2.9, 3.2, 4.7), weightGrams: 100),
        Ingredient(id: 'p3', product: mk('Масло сливочное', .8, 72.5, 1.3), weightGrams: 20),
      ],
    );

({String id, String title, double normYield, List<Ingredient> ings, double rp,
    double rf, double rc}) olivier() => (
      id: 'I5',
      title: 'Салат «Оливье»',
      normYield: 250,
      rp: 1.0,
      rf: 1.0,
      rc: 1.0,
      ings: [
        Ingredient(id: 'o1', product: mk('Картофель отварной', 2.0, .4, 16.3), weightGrams: 50),
        Ingredient(id: 'o2', product: mk('Морковь отварная', 1.3, .1, 6.9), weightGrams: 25),
        Ingredient(id: 'o3', product: mk('Огурцы консервированные', .8, .1, 1.6), weightGrams: 25),
        Ingredient(id: 'o4', product: mk('Горошек зелёный', 3.1, .2, 8.0), weightGrams: 30),
        Ingredient(id: 'o5', product: mk('Курица отварная', 18.2, 18.4, .7), weightGrams: 50),
        Ingredient(id: 'o6', product: mk('Яйцо куриное', 12.7, 11.5, .7), weightGrams: 40),
        Ingredient(id: 'o7', product: mk('Майонез', 2.8, 67.0, 2.6), weightGrams: 30),
      ],
    );

({String id, String title, double normYield, List<Ingredient> ings, double rp,
    double rf, double rc}) omelette() => (
      id: 'I6',
      title: 'Омлет натуральный паровой',
      normYield: 133.5,
      rp: 0.985,
      rf: 0.99,
      rc: 0.99,
      ings: [
        Ingredient(id: 'm1', product: mk('Яйцо куриное', 12.7, 11.5, .7), weightGrams: 75),
        Ingredient(id: 'm2', product: mk('Молоко 3,2%', 2.9, 3.2, 4.7), weightGrams: 45),
        Ingredient(id: 'm3', product: mk('Масло сливочное', .8, 72.5, 1.3), weightGrams: 10),
      ],
    );

({String id, String title, double normYield, List<Ingredient> ings, double rp,
    double rf, double rc}) broth() => (
      id: 'I7',
      title: 'Бульон куриный прозрачный',
      normYield: 300,
      rp: 0.12,
      rf: 0.08,
      rc: 0.20,
      ings: [
        Ingredient(id: 's1', product: mk('Курица 1 кат.', 18.2, 18.4, .7), weightGrams: 40),
        Ingredient(id: 's2', product: mk('Морковь', 1.3, .1, 6.9), weightGrams: 8),
        Ingredient(id: 's3', product: mk('Лук репчатый', 1.4, .2, 8.2), weightGrams: 8),
        Ingredient(id: 's4', product: mk('Вода питьевая', 0, 0, 0), weightGrams: 280),
      ],
    );

({String id, String title, double normYield, List<Ingredient> ings, double rp,
    double rf, double rc}) syrniki() => (
      id: 'I8',
      title: 'Сырники из творога',
      normYield: 140,
      rp: 0.88,
      rf: 0.90,
      rc: 0.88,
      ings: [
        Ingredient(id: 'y1', product: mk('Творог 9%', 18.0, 9.0, 3.0), weightGrams: 100),
        Ingredient(id: 'y2', product: mk('Мука в/с', 10.3, 1.1, 70.6), weightGrams: 16),
        Ingredient(id: 'y3', product: mk('Яйцо куриное', 12.7, 11.5, .7), weightGrams: 8),
        Ingredient(id: 'y4', product: mk('Сахар-песок', 0, 0, 99.8), weightGrams: 10),
        Ingredient(id: 'y5', product: mk('Масло сливочное', .8, 72.5, 1.3), weightGrams: 6),
      ],
    );

({String id, String title, double normYield, List<Ingredient> ings, double rp,
    double rf, double rc}) bechamel() => (
      id: 'I9',
      title: 'Соус Бешамель',
      normYield: 1000,
      rp: 0.979,
      rf: 0.971,
      rc: 0.981,
      ings: [
        Ingredient(id: 'z1', product: mk('Молоко 3,2%', 2.9, 3.2, 4.7), weightGrams: 900),
        Ingredient(id: 'z2', product: mk('Мука пшеничная', 10.3, 1.1, 70.6), weightGrams: 50),
        Ingredient(id: 'z3', product: mk('Масло сливочное', .8, 72.5, 1.3), weightGrams: 50),
      ],
    );

({String id, String title, double normYield, List<Ingredient> ings, double rp,
    double rf, double rc}) mors() => (
      id: 'I10',
      title: 'Морс клюквенный',
      normYield: 1000,
      rp: 1.0,
      rf: 1.0,
      rc: 1.0,
      ings: [
        Ingredient(id: 'r1', product: mk('Клюква', .5, 0, 3.8), weightGrams: 20),
        Ingredient(id: 'r2', product: mk('Сахар-песок', 0, 0, 99.8), weightGrams: 120),
        Ingredient(id: 'r3', product: mk('Вода питьевая', 0, 0, 0), weightGrams: 860),
      ],
    );

final cards = <({String id, String title, double normYield, List<Ingredient> ings, double rp, double rf, double rc})>[
  borsch(),
  cutlets(),
  buckwheat(),
  puree(),
  olivier(),
  omelette(),
  broth(),
  syrniki(),
  bechamel(),
  mors(),
];

void main() {
  // ═════════════════════════════════════════ A. ВЕС ГОТОВОГО БЛЮДА
  //
  // ПЕРЕПИСАНО (задача 2026-11-03): группа закрепляла модель выхода —
  // развариваемость круп (×2,1), уварку заливки и экстракцию в бульон.
  // Модель удалена: вес готового блюда вводит повар, приложение его не
  // угадывает. Те же сценарии проверяют новое поведение.
  group('A. Вес готового блюда вводит повар (бывш. «гидратация и уварка»)', () {
    test('A1 каша: вес не угадывается, «на 100 г» — по введённому весу', () {
      // Карта I3 этого файла: 100 г крупы + 150 г воды. Раньше выход
      // считался «развариваемостью» (крупа × 2,1), теперь — только
      // введённый вес.
      final d = Dish.withProcess(
        id: 'kasha',
        process: HeatProcess.boil,
        ingredients: buckwheat().ings,
      );
      expect(d.totalRawNetGrams, 250, reason: 'крупа 100 + вода 150');
      final none = CalculationEngine.calculate(d);
      expect(none.yieldGrams, 0, reason: 'вес не введён — не угадываем');
      expect(none.hasYield, isFalse);
      expect(none.per100gKcal, 0);
      expect(none.cookedKcal, greaterThan(0),
          reason: 'итог на всё блюдо считается и без веса');

      // Повар взвесил кашу: 210 г.
      final r = CalculationEngine.calculate(d.copyWith(customYieldGrams: 210));
      expect(r.yieldGrams, 210);
      expect(r.cookedKcal, none.cookedKcal,
          reason: 'вес меняет только «на 100 г», не нутриенты блюда');
      expect(r.per100gKcal, closeTo(r.cookedKcal / 210 * 100, 0.1));
    });

    test('A2 крупа без строки воды: вес 0, а не масса сухой крупы', () {
      final d = Dish.withProcess(
        id: 'kasha2',
        process: HeatProcess.boil,
        ingredients: buckwheat()
            .ings
            .where((i) => !i.product.name.toLowerCase().contains('вода'))
            .toList(),
      );
      expect(d.totalRawNetGrams, 100);
      final r = CalculationEngine.calculate(d);
      expect(r.yieldGrams, 0, reason: 'масса сухой крупы — не вес готовой каши');
    });

    test('A4 бульон: приложение не испаряет воду — вес вводит повар', () {
      // Карта I7 этого файла: курица + овощи + 280 г заливки (336 г сырья).
      final d = Dish.withProcess(
        id: 'broth',
        process: HeatProcess.stock,
        ingredients: broth().ings,
      );
      expect(d.totalRawNetGrams, 336);
      expect(d.effectiveYieldGrams, 0, reason: 'уварку «по модели» не считаем');
      expect(d.copyWith(customYieldGrams: 300).effectiveYieldGrams, 300);
      // Без веса и холодный цех не складывает сырьё в «выход».
      expect(d.copyWith(process: HeatProcess.cold).effectiveYieldGrams, 0);
      // Старый документ — сумма нетто, как раньше.
      expect(d.copyWith(process: HeatProcess.legacy).effectiveYieldGrams, 336);
    });

    test('A5 поля модели: способ обработки и его имя в документе', () {
      final d = Dish.withProcess(
          id: 'x', process: HeatProcess.boil, ingredients: const []);
      final json = d.toJson();
      expect(json['process'], 'boil');
      expect(
          HeatProcess.values.map((p) => p.name),
          containsAll(<String>[
            'legacy', 'cold', 'boil', 'stew', 'fry', 'bake', 'steam', 'stock'
          ]));
      // Имена удалённой модели читаются как новые способы.
      expect(Dish.fromJson({...json, 'process': 'soup'}).process, HeatProcess.boil);
      expect(Dish.fromJson({...json, 'process': 'grain'}).process, HeatProcess.boil);
      expect(Dish.fromJson({...json, 'process': 'fryMain'}).process, HeatProcess.fry);
    });

    test('A6 жарка отражается на Б/Ж/У через таблицу потерь', () {
      final fried = Dish.withProcess(
        id: 'cut',
        process: HeatProcess.fry,
        customYieldGrams: 108,
        ingredients: cutlets().ings,
      );
      final raw = fried.copyWith(process: HeatProcess.cold);
      final f = CalculationEngine.calculate(fried);
      final r = CalculationEngine.calculate(raw);
      expect(f.cookedProtein, lessThan(r.cookedProtein),
          reason: 'жарка теряет белок (мясо 10 %), а не только массу');
      expect(f.cookedFat, lessThan(r.cookedFat));
    });
  });

  group('B. Сохранность: справочник по продукту вместо одной тройки', () {
    test('B1 legacy-дефолт сохранён для старых документов', () {
      final d = Dish(
          id: 'x', createdAt: DateTime(2026), updatedAt: DateTime(2026));
      expect(d.process, HeatProcess.legacy);
      expect(d.retentionProtein, .94);
      expect(d.retentionFat, .88);
      expect(d.retentionCarbs, .91);
    });

    test('B2 холодный салат НЕ теряет нутриентов', () {
      final cold = Dish.withProcess(
        id: 'olivier',
        process: HeatProcess.cold,
        customYieldGrams: 250,
        ingredients: bench.toAppDish(bench.benchmark[4]).ingredients,
      );
      final r = CalculationEngine.calculate(cold);
      expect(r.cookedProtein, closeTo(r.rawTotalProtein, 0.01));
      expect(r.cookedFat, closeTo(r.rawTotalFat, 0.01));
      expect(r.cookedCarbs, closeTo(r.rawTotalCarbs, 0.01));
    });

    test('B3 морс — холодная технология: углеводы не «испаряются»', () {
      final d = Dish.withProcess(
        id: 'mors',
        process: HeatProcess.cold,
        customYieldGrams: 1000,
        ingredients: bench.toAppDish(bench.benchmark[9]).ingredients,
      );
      final r = CalculationEngine.calculate(d);
      expect(r.cookedCarbs, closeTo(r.rawTotalCarbs, 0.01));
    });

    test('B4 таблица потерь покрывает весь диапазон способов и групп', () {
      // Одна тройка на всё блюдо физически невозможна: потери жира мяса —
      // от 0 % (без обработки) до 30 % (жарка), а в бульон переходит лишь
      // четверть жира мяса (потери 75 %).
      expect(LossTable.lossFor(LossGroup.meat, HeatProcess.cold).fat, 0);
      expect(LossTable.lossFor(LossGroup.meat, HeatProcess.fry).fat, 30);
      expect(LossTable.lossFor(LossGroup.meat, HeatProcess.stock).fat, 75);
      // Каждая ячейка «способ × группа» задана (у legacy и cold потери
      // общие для всех групп).
      for (final p in HeatProcess.values) {
        if (p.isLegacy || p == HeatProcess.cold) continue;
        for (final g in LossGroup.values) {
          expect(LossTable.table[p]?[g], isNotNull, reason: '${p.name}/${g.name}');
        }
      }
      final names = HeatProcess.values.map((p) => p.name).toSet();
      expect(names.length, HeatProcess.values.length);
    });

    test('B5 потери берутся ПО ПРОДУКТУ: котлеты жарятся, но не «варятся»', () {
      final fried = Dish.withProcess(
        id: 'cut',
        process: HeatProcess.fry,
        customYieldGrams: 108,
        ingredients: cutlets().ings,
      );
      final boiled = fried.copyWith(process: HeatProcess.boil);
      final f = CalculationEngine.calculate(fried);
      final b = CalculationEngine.calculate(boiled);
      // Мясо: жарка Ж 30 % против 25 % при варке (МР 2.3.0419-26, прил. 4).
      expect(f.cookedFat, lessThan(b.cookedFat),
          reason: 'жарка мяса теряет больше жира, чем варка');
      final meat = f.lines.firstWhere((l) => l.productName == 'Свинина мясная');
      expect(meat.group, LossGroup.meat);
      expect(meat.loss.fat, 30);
      final bread = f.lines.firstWhere((l) => l.productName == 'Хлеб пшеничный');
      expect(bread.group, LossGroup.flourBread,
          reason: 'у каждой строки своя группа, а не одна тройка на блюдо');
      expect(bread.loss.fat, isNot(meat.loss.fat));
    });
  });

  // ══════════════════════════════════════════════ D. ПОЛУФАБРИКАТЫ
  group('D. Полуфабрикаты: блюдо как ингредиент блюда', () {
    test('D1 есть только флаг isDish, вычислений «блюдо → нутриенты» нет', () {
      final p = mk('Котлетная масса', 16.0, 20.0, 3.0, isDish: true);
      expect(p.isDishOnly, isTrue);
      // isDish — только метка каталога, на расчёт не влияет.
      final a = CalculationEngine.calculate(mkDish('x',
          [Ingredient(id: '1', product: p, weightGrams: 100)]));
      final b = CalculationEngine.calculate(mkDish('x', [
        Ingredient(
            id: '1', product: mk('Котлетная масса', 16.0, 20.0, 3.0), weightGrams: 100)
      ]));
      expect(a.cookedKcal, b.cookedKcal);
      expect(a.per100gKcal, b.per100gKcal);
    });

    test('D2 рецепт «Полуфабрикат + жарка» даёт ВЕРНЫЕ нутриенты, если '
        'считать правильно (ручное доказательство совместимости)', () {
      // Реальная PЦ: котлетная масса 142,7 г → 108 г жареных.  Сборник:
      // нутриенты П/Ф минус потери 20/15/16 % → 108 г приложения.
      // Это работает с пересчётом «на 100 г» вручную (см. ниже), НО требует:
      //   1) вычислить, что 108 г готовых = 142,7 г П/Ф (усадка 24,3 %);
      //   2) вручную вписать нутриенты в карточку «П/Ф как продукт».
      final semifab = CalculationEngine.calculate(
          mkDish('ПФ', cutlets().ings, yieldGrams: 142.7, rp: 1, rf: 1, rc: 1));
      final p100 = semifab.per100gProtein;
      final f100 = semifab.per100gFat;
      final c100 = semifab.per100gCarbs;
      // Пересборка «ПФ как продукты» — масса берётся в НЕТТО готового п/ф.
      final composed = CalculationEngine.calculate(mkDish(
        'Котлеты из ПФ',
        [
          Ingredient(
              id: 'pf',
              product: mk('Полуфабрикат котлетный', p100, f100, c100),
              weightGrams: 142.7),
        ],
        yieldGrams: 108,
        rp: 0.80,
        rf: 0.85,
        rc: 0.84,
      ));
      final direct = CalculationEngine.calculate(mkDish('Котлеты',
          cutlets().ings, yieldGrams: 108, rp: 0.80, rf: 0.85, rc: 0.84));
      // Должно совпасть до сотых — и совпадает.
      expect(composed.cookedProtein, closeTo(direct.cookedProtein, 0.05));
      expect(composed.cookedFat, closeTo(direct.cookedFat, 0.05));
      expect(composed.cookedCarbs, closeTo(direct.cookedCarbs, 0.05));
      // ignore: avoid_print
      print('D2 ПФ→котлеты: Б ${f2(composed.cookedProtein)} / ${f2(direct.cookedProtein)}, '
          'Ж ${f2(composed.cookedFat)} / ${f2(direct.cookedFat)}, '
          'У ${f2(composed.cookedCarbs)} / ${f2(direct.cookedCarbs)}');
    });

    test('D3 НО: приложение НЕ умеет пересчёт «блюдо с выходом → продукт». '
        'Если взять нутриенты ПФ «на выход», нутриенты теряются молча', () {
      // Распространённая ошибка пользователя: в карточке продукта
      // «Котлетная масса» сохраняются НА 100 Г П/Ф, но масса ставится
      // РАВНОЙ сумме сырья (142,7), а выход ПФ = 142,7 (усадка не задана).
      // Тогда «108 г готовых» — это ПФ 108 г, а не 142,7.
      final semifab = CalculationEngine.calculate(
          mkDish('ПФ', cutlets().ings, yieldGrams: 142.7, rp: 1, rf: 1, rc: 1));
      final wrong = CalculationEngine.calculate(mkDish(
        'Котлеты из ПФ (ошибка)',
        [
          Ingredient(
              id: 'pf',
              product: mk(
                  'ПФ', semifab.per100gProtein, semifab.per100gFat, semifab.per100gCarbs),
              weightGrams: 108),
        ],
        yieldGrams: 108,
        rp: 0.80,
        rf: 0.85,
        rc: 0.84,
      ));
      final direct = CalculationEngine.calculate(mkDish('Котлеты',
          cutlets().ings, yieldGrams: 108, rp: 0.80, rf: 0.85, rc: 0.84));
      final dK = (wrong.cookedKcal - direct.cookedKcal) / direct.cookedKcal * 100;
      // ignore: avoid_print
      print('D3: ккал ${f1(wrong.cookedKcal)} vs ${f1(direct.cookedKcal)} '
          '(${dK.toStringAsFixed(2)} %) — тихая ошибка -24,3 % сырья');
      expect(dK.abs(), greaterThan(5));
    });

    test('D4 вложенность: выход ПФ нигде не связан с выходом блюда', () {
      // Dish не ссылается на другой Dish.  Проверяем сериализацию: id
      // ингредиента — строка, продукт — плоский Product, без id рецепта.
      final d = mkDish('x', cutlets().ings, yieldGrams: 108);
      final json = d.toJson();
      final ing0 = (json['ingredients'] as List).first as Map<String, dynamic>;
      expect(ing0.containsKey('dishId'), isFalse);
      expect(ing0.containsKey('recipeId'), isFalse);
      expect(ing0.containsKey('link'), isFalse);
      // ignore: avoid_print
      print('D4: ключи ингредиента = ${ing0.keys.toList()}');
    });

    test('D5 DishNotifier: полуфабрикат можно только копировать как продукт', () async {
      final n = DishNotifier();
      addTearDown(n.dispose);
      n.addIngredient(mk('Котлетная масса', 16.0, 20.0, 3.0, isDish: true), 142.7);
      expect(n.state.ingredients.single.product.isDishOnly, isTrue);
      // Новое блюдо (cold): вес готового блюда не угадывается (раньше —
      // 142,7 г суммой нетто), его вводит повар.
      expect(n.state.process, HeatProcess.cold);
      expect(n.state.effectiveYieldGrams, 0);
      // Старый расчёт (legacy) по-прежнему берёт сумму нетто.
      n.setHeatProcess(HeatProcess.legacy);
      expect(n.state.effectiveYieldGrams, 142.7);
      // Приложение не пересчитывает нутриенты при добавлении «блюда как
      // ингредиента» и не требует указания его выхода.
      expect(n.state.customYieldGrams, isNull);
      await n.flushPendingSaves();
    });
  });
}
