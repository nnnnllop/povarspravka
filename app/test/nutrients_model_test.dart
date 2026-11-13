// Модель «только нутриенты после тепловой обработки» (задача 2026-11-03):
// сохранение ручных группы/способа ингредиента, старые документы (legacy)
// с прежними числами, подпись потерь в карточке, пометка kNotGostNotice
// и прочерк вместо «в 100 г», когда вес готового блюда не указан.
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/calculation_engine.dart';
import 'package:povarspravka/core/calculation/loss_table.dart';
import 'package:povarspravka/core/calculation/models/dish.dart';
import 'package:povarspravka/core/calculation/models/heat_process.dart';
import 'package:povarspravka/core/calculation/models/ingredient.dart';
import 'package:povarspravka/core/calculation/models/loss_group.dart';
import 'package:povarspravka/core/calculation/models/product.dart';
import 'package:povarspravka/core/export/docx_blank_generator.dart';
import 'package:povarspravka/core/export/pdf_blank_generator.dart';
import 'package:povarspravka/core/export/xlsx_blank_generator.dart';
import 'package:povarspravka/presentation/providers/dish_provider.dart';
import 'package:povarspravka/presentation/widgets/ingredient_card.dart';

const _beef = Product(
  id: 1,
  code: '3.1.1',
  name: 'Говядина 1 категории',
  groupId: 3,
  source: 'skurikhin',
  protein: 18.6,
  fat: 16.0,
  carbs: 0.0,
  kcal: 218.0,
);

const _potato = Product(
  id: 2,
  code: '8.1.6.1',
  name: 'Картофель',
  groupId: 8,
  source: 'skurikhin',
  protein: 2.0,
  fat: 0.4,
  carbs: 16.3,
  kcal: 77.0,
  wastePct: 20.0,
);

final _t = DateTime.utc(2026, 11, 3, 12);

Dish _dish(HeatProcess process, {double? yieldGrams, bool per100 = true}) =>
    Dish(
      id: 'nm',
      title: 'Проверка',
      showPer100gRowInExport: per100,
      ingredients: const [
        Ingredient(
            id: 'b',
            product: _beef,
            weightGrams: 200,
            groupOverride: LossGroup.meat),
        Ingredient(
            id: 'p',
            product: _potato,
            weightGrams: 250,
            isGross: true,
            groupOverride: LossGroup.rootTuber),
      ],
      customYieldGrams: yieldGrams,
      process: process,
      createdAt: _t,
      updatedAt: _t,
    );

String _docxText(Dish d) {
  final archive = ZipDecoder().decodeBytes(DocxBlankGenerator.generate(d));
  return utf8.decode(archive.findFile('word/document.xml')!.content as List<int>);
}

String _xlsxText(Dish d) {
  final archive = ZipDecoder().decodeBytes(XlsxBlankGenerator.generate(d));
  return utf8.decode(
      archive.findFile('xl/worksheets/sheet1.xml')!.content as List<int>);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('JSON: способ блюда и ручные группа/способ ингредиента', () {
    test('ручные группа и способ переживают toJson → fromJson', () {
      const ing = Ingredient(
        id: 'x',
        product: _beef,
        weightGrams: 100,
        groupOverride: LossGroup.fatOil,
        processOverride: HeatProcess.fry,
      );
      final json = ing.toJson();
      expect(json['group'], 'fatOil');
      expect(json['process'], 'fry');
      final back = Ingredient.fromJson(
          jsonDecode(jsonEncode(json)) as Map<String, dynamic>);
      expect(back.groupOverride, LossGroup.fatOil);
      expect(back.processOverride, HeatProcess.fry);
      expect(back.lossGroup, LossGroup.fatOil);
      expect(back.processIn(HeatProcess.boil), HeatProcess.fry);
    });

    test('без ручных значений ключей group/process у ингредиента нет', () {
      const ing = Ingredient(id: 'x', product: _beef, weightGrams: 100);
      final json = ing.toJson();
      expect(json.containsKey('group'), isFalse);
      expect(json.containsKey('process'), isFalse);
      expect(ing.processIn(HeatProcess.stew), HeatProcess.stew,
          reason: 'без ручного способа действует способ блюда');
    });

    test('неизвестные или legacy-значения у ингредиента игнорируются', () {
      final base = const Ingredient(id: 'x', product: _beef, weightGrams: 100)
          .toJson();
      for (final bad in ['legacy', 'nope', 42]) {
        final back = Ingredient.fromJson(
            {...base, 'group': bad, 'process': bad});
        expect(back.groupOverride, isNull, reason: '$bad');
        expect(back.processOverride, isNull, reason: '$bad');
      }
    });

    test('способ блюда: legacy без ключа, остальные — по имени, алиасы', () {
      final legacy = _dish(HeatProcess.legacy).toJson();
      expect(legacy.containsKey('process'), isFalse,
          reason: 'старый формат документа не меняется');
      expect(Dish.fromJson(legacy).process, HeatProcess.legacy);
      for (final p in HeatProcess.values.where((p) => !p.isLegacy)) {
        final json = _dish(p).toJson();
        expect(json['process'], p.name);
        expect(Dish.fromJson(json).process, p);
      }
      const aliases = {
        'soup': HeatProcess.boil,
        'grain': HeatProcess.boil,
        'fryMain': HeatProcess.fry,
        'unknown': HeatProcess.legacy,
      };
      for (final e in aliases.entries) {
        final json = {...legacy, 'process': e.key};
        expect(Dish.fromJson(json).process, e.value, reason: e.key);
      }
    });

    test('старый документ (без process) считается прежними числами', () {
      // Документ в формате до задачи 2026-11-03: тройка 0,94/0,88/0,91,
      // выход — сумма нетто, если вес не введён.
      final old = <String, dynamic>{
        'id': 'old',
        'title': 'Старое блюдо',
        'ingredients': [
          {
            'id': 'b',
            'product': _beef.toJson(),
            'weightGrams': 200.0,
            'isGross': false,
          },
          {
            'id': 'p',
            'product': _potato.toJson(),
            'weightGrams': 250.0,
            'isGross': true,
          },
        ],
        'customYieldGrams': null,
        'retentionProtein': 0.94,
        'retentionFat': 0.88,
        'retentionCarbs': 0.91,
        'blankMode': 'photoCross',
        'createdAt': _t.toIso8601String(),
        'updatedAt': _t.toIso8601String(),
      };
      final dish = Dish.fromJson(old);
      expect(dish.process, HeatProcess.legacy);
      final r = CalculationEngine.calculate(dish);
      expect(r.usesLossTable, isFalse);
      expect(r.lines, isEmpty);
      expect(r.yieldGrams, 400.0, reason: '200 + 250×0,8 нетто');
      expect(r.cookedProtein, closeTo(r.rawTotalProtein * 0.94, 0.005),
          reason: 'legacy: итог округлён до 0,01, как в бланке');
      expect(r.cookedFat, closeTo(r.rawTotalFat * 0.88, 0.005),
          reason: 'legacy: итог округлён до 0,01, как в бланке');
      expect(r.cookedCarbs, closeTo(r.rawTotalCarbs * 0.91, 0.005),
          reason: 'legacy: итог округлён до 0,01, как в бланке');
      // Повторное сохранение не добавляет ключ process.
      expect(dish.toJson().containsKey('process'), isFalse);
    });
  });

  group('DishNotifier: ручная группа и способ ингредиента', () {
    test('setIngredientGroup / setIngredientProcess и сброс null', () {
      final n = DishNotifier();
      n.setHeatProcess(HeatProcess.boil);
      n.addIngredient(_beef, 200);
      final id = n.state.ingredients.single.id;
      final auto = n.state.ingredients.single.lossGroup;

      n.setIngredientGroup(id, LossGroup.fish);
      expect(n.state.ingredients.single.groupOverride, LossGroup.fish);
      n.setIngredientProcess(id, HeatProcess.fry);
      expect(n.state.ingredients.single.processOverride, HeatProcess.fry);
      final line = CalculationEngine.calculate(n.state).lines.single;
      expect(line.group, LossGroup.fish);
      expect(line.process, HeatProcess.fry);
      expect(line.groupIsManual, isTrue);
      expect(line.processIsManual, isTrue);
      final fishFry = LossTable.lossFor(LossGroup.fish, HeatProcess.fry);
      expect(line.cookedProtein,
          closeTo(line.rawProtein * (100 - fishFry.protein) / 100, 1e-9));

      n.setIngredientGroup(id, null);
      n.setIngredientProcess(id, null);
      final ing = n.state.ingredients.single;
      expect(ing.groupOverride, isNull);
      expect(ing.processOverride, isNull);
      expect(ing.lossGroup, auto);
      final line2 = CalculationEngine.calculate(n.state).lines.single;
      expect(line2.process, HeatProcess.boil);
      expect(line2.groupIsManual, isFalse);
      expect(line2.processIsManual, isFalse);
    });

    test('legacy у ингредиента отклоняется, чужой id не меняет состояние', () {
      final n = DishNotifier();
      n.addIngredient(_beef, 200);
      final id = n.state.ingredients.single.id;
      n.setIngredientProcess(id, HeatProcess.legacy);
      expect(n.state.ingredients.single.processOverride, isNull);
      final before = n.state;
      n.setIngredientGroup('нет-такого', LossGroup.fish);
      n.setIngredientProcess('нет-такого', HeatProcess.fry);
      expect(identical(n.state, before), isTrue);
    });

    test('новое блюдо — без обработки, потерь нет', () {
      final n = DishNotifier();
      expect(n.state.process, HeatProcess.cold);
      n.addIngredient(_potato, 250, isGross: true);
      final r = CalculationEngine.calculate(n.state);
      expect(r.usesLossTable, isTrue);
      expect(r.cookedProtein, r.rawTotalProtein);
      expect(r.cookedFat, r.rawTotalFat);
      expect(r.cookedCarbs, r.rawTotalCarbs);
    });
  });

  group('Подпись потерь в карточке ингредиента', () {
    test('мясо · варка — числа источника без «оценки»', () {
      const ing = Ingredient(
          id: 'b', product: _beef, weightGrams: 100, groupOverride: LossGroup.meat);
      expect(
        lossLabelFor(ing, HeatProcess.boil),
        'Потери: ${LossGroup.meat.label} (вручную) · ${HeatProcess.boil.label}'
        ' — Б 10 %, Ж 25 %, У 0 %',
      );
    });

    test('UNVERIFIED-ячейка помечена «(оценка)», ручной способ — «(вручную)»',
        () {
      const ing = Ingredient(
        id: 'c',
        product: _beef,
        weightGrams: 100,
        groupOverride: LossGroup.poultry,
        processOverride: HeatProcess.boil,
      );
      final label = lossLabelFor(ing, HeatProcess.cold);
      expect(label, startsWith('Потери: ${LossGroup.poultry.label} (вручную) · '
          '${HeatProcess.boil.label} (вручную) — '));
      expect(LossTable.lossFor(LossGroup.poultry, HeatProcess.boil).isVerified,
          isFalse);
      expect(label, endsWith(' (оценка)'));
    });

    test('без обработки — «нет»', () {
      const ing = Ingredient(id: 'p', product: _potato, weightGrams: 100);
      expect(lossLabelFor(ing, HeatProcess.cold),
          endsWith('· ${HeatProcess.cold.label} — нет'));
    });
  });

  group('Бланки: пометка «не по ГОСТ» и вес готового блюда', () {
    test('новый расчёт с весом: пометка есть, «в 100 г» посчитано', () async {
      final d = _dish(HeatProcess.boil, yieldGrams: 380);
      final r = CalculationEngine.calculate(d);
      expect(r.hasYield, isTrue);
      final docx = _docxText(d);
      expect(docx, contains(kNotGostNotice));
      expect(docx, contains('Потери при тепловой обработке — по группам'));
      expect(docx, contains(CalculationEngine.formatMacro(r.per100gProtein)));
      final xlsx = _xlsxText(d);
      expect(xlsx, contains(kNotGostNotice));
      final pdf = await PdfBlankGenerator.generate(d);
      expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
    });

    test('новый расчёт без веса: итог на всё блюдо, «в 100 г» — прочерк',
        () async {
      final d = _dish(HeatProcess.stew);
      final r = CalculationEngine.calculate(d);
      expect(r.hasYield, isFalse);
      expect(r.per100gProtein, 0);
      expect(r.cookedProtein, greaterThan(0));
      final docx = _docxText(d);
      expect(docx, contains(kNotGostNotice));
      // Прочерки: выход и 4 ячейки строки «В 100 г блюда».
      // Тот же документ с весом — прочерков на 5 меньше.
      final withYield = _dish(HeatProcess.stew, yieldGrams: 380);
      int docxDashes(String s) =>
          '<w:t xml:space="preserve">—</w:t>'.allMatches(s).length;
      expect(docxDashes(docx), docxDashes(_docxText(withYield)) + 5);
      int xlsxDashes(String s) => '<t>—</t>'.allMatches(s).length;
      expect(xlsxDashes(_xlsxText(d)), xlsxDashes(_xlsxText(withYield)) + 5);
      final pdf = await PdfBlankGenerator.generate(d);
      expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
    });

    test('legacy-документ: пометки нет, прежняя формула 94/88/91', () {
      final d = _dish(HeatProcess.legacy);
      final docx = _docxText(d);
      expect(docx, isNot(contains(kNotGostNotice)));
      expect(docx, contains('Сохранность после тепловой обработки:'));
      expect(docx, contains('= Сумма белков *94 /100'));
      expect(_xlsxText(d), isNot(contains(kNotGostNotice)));
    });
  });
}
