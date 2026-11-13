// Главный инженер аудита — независимые кросс-проверки, не дублирующие работу
// субагентов. Каждый тест доказывает ровно одно утверждение и печатает числа,
// чтобы вердикт в отчёте опирался на исполняемую улику, а не на чтение кода.
//
// НИЧЕГО в app/lib не меняется: тесты только фиксируют текущее поведение.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/calculation_engine.dart';
import 'package:povarspravka/core/calculation/calculation_math.dart';
import 'package:povarspravka/core/calculation/models/dish.dart';
import 'package:povarspravka/core/calculation/models/ingredient.dart';
import 'package:povarspravka/core/calculation/models/product.dart';
import 'package:povarspravka/core/calculation/yield_explanation.dart';
import 'package:povarspravka/core/calculation/calculation_validation.dart';
import 'package:povarspravka/data/repositories/dish_storage_repository.dart';
import 'package:povarspravka/presentation/providers/dish_provider.dart';
import 'package:povarspravka/presentation/screens/recipe_editor_screen.dart';
import 'package:povarspravka/presentation/widgets/calc_error_banner.dart';
import 'package:povarspravka/core/theme/app_theme.dart';

Product _p({
  double protein = 18.6,
  double fat = 16.0,
  double carbs = 0.0,
  double kcal = 218.0,
  double wastePct = 0.0,
  String name = 'Говядина 1 кат.',
}) =>
    Product(
      id: 1,
      code: '1',
      name: name,
      groupId: 1,
      source: 'skurikhin',
      protein: protein,
      fat: fat,
      carbs: carbs,
      kcal: kcal,
      wastePct: wastePct,
    );

Dish _dish(
  List<Ingredient> ings, {
  double? yieldGrams,
  double rp = 0.94,
  double rf = 0.88,
  double rc = 0.91,
}) {
  final now = DateTime.utc(2026, 1, 1);
  return Dish(
    id: 'lead',
    ingredients: ings,
    customYieldGrams: yieldGrams,
    retentionProtein: rp,
    retentionFat: rf,
    retentionCarbs: rc,
    createdAt: now,
    updatedAt: now,
  );
}

Ingredient _i(Product p, double g, {String id = 'i1', bool isGross = false}) =>
    Ingredient(id: id, product: p, weightGrams: g, isGross: isGross);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ───────────────────────────────────────────────────────────────────────
  // LEAD-01. Ядро не может посчитать физически корректное жирное блюдо.
  //
  // Инвариант «масса БЖУ выхода ≤ масса выхода» физически неверен для
  // продуктов с высоким содержанием жира/воды, потому что жир с коэф.
  // сохранности 0.88 «почти не теряет массу», а вода при жарке/выпечке
  // испаряется. Пример реальный: сливочное масло 90 % жира, потери при
  // тушении масла ~12 % → 100 г масла дают 79.2 г жира. Выпарить из
  // 100 г масла 21 г возможно, а «выйти» должно быть ≥ 79.2 г — для
  // масла «на сковороде» повар честно указывает выход 60 г (гарнир
  // впитал 40 г), и приложение отказывается считать.
  // ───────────────────────────────────────────────────────────────────────
  test('LEAD-01 a legitimate butter-heavy dish CALCULATES (spec)', () {
    final butter = _p(
        name: 'Масло сливочное «Крестьянское»',
        protein: 0.8,
        fat: 72.5,
        carbs: 1.3,
        kcal: 661);
    final dish = _dish([_i(butter, 100)], yieldGrams: 60);
    // SPEC (LOGIC-01): cooked macronutrients are a COMPONENT of the dish mass,
    // not an upper bound on it. 100 g of butter holds ~64 g of fat, and a chef
    // genuinely sets 60 g yield when a garnish absorbs the rest — this must
    // calculate, not throw.
    expect(() => CalculationEngine.calculate(dish), returnsNormally);
    final res = CalculationEngine.calculate(dish);
    expect(res.yieldGrams, 60);
    expect(res.cookedFat, greaterThan(0));
    // The density is real: more fat than yield is legal and reported, not fatal.
    final macroMass = CalculationMath.sumRounded(
        [res.cookedProtein, res.cookedFat, res.cookedCarbs], 2);
    expect(macroMass, greaterThan(60.0),
        reason: 'the scenario is the one LOGIC-01 legalises');
    expect(res.per100gKcal.isFinite, isTrue);
    expect(res.per100gKcal, greaterThan(0));
  });

  // ───────────────────────────────────────────────────────────────────────
  // LEAD-02. SPEC: opening a dish the engine rejects shows a `CalcErrorBanner`
  // instead of taking the UI down. The home screen no longer calls the engine
  // unguarded (it uses `CalculationEngine.tryCalculate`) and the provider
  // yields `null` rather than throwing.
  // ───────────────────────────────────────────────────────────────────────
  testWidgets(
      'LEAD-02 a dish the engine rejects renders a banner, never a Red Screen',
      (tester) async {
    // A yield the validator refuses (MATH-05: below the 1 g floor) — the
    // dish loads fine, only the calculation fails.
    final butter = _p(
        name: 'Масло', protein: 0.8, fat: 72.5, carbs: 1.3, kcal: 661);
    final dish = _dish([_i(butter, 100)], yieldGrams: 0.1);
    final container = ProviderContainer(overrides: [
      dishProvider.overrideWith((ref) => DishNotifier()..loadDish(dish)),
    ]);
    addTearDown(container.dispose);

    // The provider yields null instead of throwing.
    expect(container.read(calculationResultProvider), isNull);
    expect(container.read(calculationErrorProvider), isNotNull);

    final uiContainer = ProviderContainer(overrides: [
      dishProvider.overrideWith((ref) => DishNotifier()..loadDish(dish)),
    ]);
    addTearDown(uiContainer.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: uiContainer,
      child: MaterialApp(
        theme: AppTheme.light,
        home: const RecipeEditorScreen(),
      ),
    ));
    await tester.pump();

    expect(tester.takeException(), isNull,
        reason: 'редактор обязан показать баннер, а не Red Screen');
    expect(find.byType(ErrorWidget), findsNothing);
    expect(find.byType(CalcErrorBanner), findsOneWidget);
  });

  // ───────────────────────────────────────────────────────────────────────
  // LEAD-03. Ввод запятой в поле фактического выхода НАВСЕГДА блокирует
  // дальнейший ввод: saved=750.5 → formatGrams→"750,5" → TextField.onChanged
  // видит "750,5" → parse 750.5 == saved → поле не переписывается, но
  // пользователь дописал ещё цифру "7", итог "750,57" — и это ловится.
  // А вот обратное: сохранённый выход с сотыми 0.945 → formatGrams даёт
  // "0,9" — и повторное открытие показывает УМЕНЬШЕННЫЙ выход.
  // Здесь проверяем тот же класс дефекта в другом месте: 1 десятичная
  // цифра — только это и переживает переоткрытие карточки.
  // ───────────────────────────────────────────────────────────────────────
  test('LEAD-03 custom yield is silently coarsened to 0.1 g on every build path',
      () {
    final beef = _p();
    final d0 = _dish([_i(beef, 600)], yieldGrams: 412.37);
    // effectiveYieldGrams округляет входное значение до 0.1.
    final effective = d0.effectiveYieldGrams;
    final shown = CalculationEngine.formatGrams(412.37);
    // ignore: avoid_print
    print('LEAD-03 stored=412.37 effective=$effective shown="$shown"');
    expect(effective, 412.4);
    // Информационная потеря 0.03 г на каждое переоткрытие — не аддитивна,
    // но 412.37 никогда не вернуть через UI.
    final afterReopen = CalculationEngine.parseInputDouble(shown);
    expect(afterReopen, isNot(412.37));
  });

  // ───────────────────────────────────────────────────────────────────────
  // LEAD-04. Подложенное значение вручную введённого выхода выживает
  // автопересчёт при добавлении ингредиента: новый вес сырья не
  // переносит выход → блюдо «сжимается» и падает в LEAD-01.
  // ───────────────────────────────────────────────────────────────────────
  test('LEAD-04 adding an ingredient keeps the stale custom yield', () {
    final beef = _p();
    final n = DishNotifier();
    n.addIngredient(beef, 600);
    n.setCustomYield(750);
    n.addIngredient(beef, 600, isGross: false);
    final d = n.state;
    // ignore: avoid_print
    print('LEAD-04 raw=${d.totalRawNetGrams} yield=${d.effectiveYieldGrams}');
    expect(d.totalRawNetGrams, 1200.0);
    expect(d.effectiveYieldGrams, 750.0,
        reason: 'выход не вырос вслед за сырьём — молчаливое сжатие блюда');
    // Сырья стало вдвое больше, а выход остался прежним — блюдо «сжалось».
    // Печатаем, вычислимо ли оно ещё (при 1200 г говядины БЖУ после т.о.
    // ≈ 470 г, то есть пока вычислимо; следующий шаг роста — нет).
    Object? err;
    try {
      CalculationEngine.calculate(d);
    } catch (e) {
      err = e;
    }
    // ignore: avoid_print
    print('LEAD-04 calculate after growth threw: ${err.runtimeType}');
    expect(err, isNull,
        reason: 'рост сырья не должен делать блюдо невычислимым');
    // Доводим до отказа честным путём: ещё три порции сырья.
    n.addIngredient(beef, 600);
    n.addIngredient(beef, 600);
    Object? err2;
    try {
      CalculationEngine.calculate(n.state);
    } catch (e) {
      err2 = e;
    }
    // ignore: avoid_print
    print('LEAD-04 raw=${n.state.totalRawNetGrams} '
        'yield=${n.state.effectiveYieldGrams} threw=${err2.runtimeType}');
    expect(err2, isNull,
        reason: 'простое добавление сырья не должно делать блюдо невычислимым');
  });

  // ───────────────────────────────────────────────────────────────────────
  // LEAD-05. «Уварка −X %» в подписи показывает ДЕЛЬТУ, а не процент.
  // yield_explanation.dart:22: formatGrams(-delta / raw * 100) ставит «%»
  // и НЕ делит на 100 в обратную сторону… проверим фактический текст.
  // ───────────────────────────────────────────────────────────────────────
  test('LEAD-05 уварка percentage text is the raw percentage, not a fraction',
      () {
    final e = YieldExplanation(1000, 750);
    // ignore: avoid_print
    print('LEAD-05 badge="${e.badge}"');
    // −(250/1000*100) = −25 % — корректно. Фиксируем как PASSED-поведение.
    expect(e.badge, contains('25'));
    // Но при малых изменениях подпись округляет до 0.1 и даёт «−0%».
    final tiny = YieldExplanation(1000, 999.6);
    // ignore: avoid_print
    print('LEAD-05 tiny badge="${tiny.badge}" changed=${tiny.changed}');
  });

  // ───────────────────────────────────────────────────────────────────────
  // LEAD-06. Валидация продукта: kcal/water/fiber/sfa не проверяются на
  // конечность. Infinity в kcal проходит `CalculationValidation.product`
  // и попадает в прод-путь (карточка продукта показывает тарифы).
  // ───────────────────────────────────────────────────────────────────────
  test('LEAD-06 non-finite kcal passes product validation', () {
    final bad = Product(
      id: 9,
      code: 'x',
      name: 'Битый продукт',
      groupId: 1,
      source: 'bls',
      protein: 1,
      fat: 1,
      carbs: 1,
      kcal: double.infinity,
    );
    Object? err;
    try {
      CalculationValidation.product(bad);
    } catch (e) {
      err = e;
    }
    // ignore: avoid_print
    print('LEAD-06 validate(inf kcal) threw: ${err.runtimeType}');
    expect(err, isNotNull,
        reason: 'бесконечная калорийность обязана отвергаться');

    // А что будет, если такой продукт дойдёт до бланка в подробном режиме —
    // kcalInDish участвует в строке бланка.
    final ing = _i(bad, 100);
    // ignore: avoid_print
    print('LEAD-06 ing.kcalInDish=${ing.kcalInDish} '
        'blankKcal=${ing.blankKcalInDish}');
  });

  // ───────────────────────────────────────────────────────────────────────
  // LEAD-07. Непечатаемое в названии: ZWSP/эмодзи переживают JSON,
  // но «Итого» превращается в копеечную кашу при названии-пустышке —
  // проверяем, что сохранение не теряет невидимые символы (это и есть
  // требование по Unicode-добросовестности слоя хранения).
  // ───────────────────────────────────────────────────────────────────────
  test('LEAD-07 storage keeps ZWSP, emoji and «ёлочки» byte-exactly', () async {
    final dir = await Directory.systemTemp.createTemp('lead07');
    addTearDown(() => dir.delete(recursive: true));
    final repo = DishStorageRepository(storageDirectory: dir);
    const title = 'Борщ\u200B «Особый» 🍲\u00A0с\u2028пометкой';
    final d = _dish([_i(_p(), 100)], yieldGrams: 100)
        .copyWith(title: title);
    await repo.saveAll(activeDraft: d, savedDishes: [d]);
    final back = await repo.loadAll();
    expect(back.activeDraft!.title, title);
    expect(back.savedDishes.single.title, title);
  });

  // ───────────────────────────────────────────────────────────────────────
  // LEAD-08. Детерминизм: identical double output бит-в-бит.
  // ───────────────────────────────────────────────────────────────────────
  test('LEAD-08 engine is bit-for-bit deterministic over 500 runs', () {
    final dish = _dish([
      _i(_p(protein: 12.6, fat: 3.3, carbs: 57.1, kcal: 308), 123.4, id: 'a'),
      _i(_p(protein: 2.9, fat: 3.2, carbs: 4.7, kcal: 60), 38.7, id: 'b'),
      _i(_p(protein: 0.8, fat: 72.5, carbs: 1.3, kcal: 661), 15.3, id: 'c'),
    ], yieldGrams: 177.4);
    final first = CalculationEngine.calculate(dish);
    final fp = first.cookedKcal.toString();
    for (var i = 0; i < 500; i++) {
      final r = CalculationEngine.calculate(dish);
      expect(r.cookedKcal.toString(), fp);
      expect(r.per100gProtein.toString(), first.per100gProtein.toString());
    }
  });

  // ───────────────────────────────────────────────────────────────────────
  // LEAD-09. Финансовая округляемость калькуляционной карты: итог «1С
  // Общепит» считается до 0.01 ₽. Показываем, что копеечная сверка
  // «итог = сумма строк» держится только для Б, Ж, У, но НЕ для ккал
  // (ккал на 0.1 и пересчитывается из БЖУ — 4-9-4).
  // ───────────────────────────────────────────────────────────────────────
  test('LEAD-09 printed rows sum exactly to printed totals (money-grade)', () {
    final dish = _dish([
      _i(_p(protein: 12.6, fat: 3.3, carbs: 57.1, kcal: 308), 100.0, id: 'a'),
      _i(_p(protein: 2.9, fat: 3.2, carbs: 4.7, kcal: 60), 38.0, id: 'b'),
      _i(_p(protein: 0.8, fat: 72.5, carbs: 1.3, kcal: 661), 15.0, id: 'c'),
      _i(_p(protein: 10.3, fat: 1.1, carbs: 70.6, kcal: 334), 22.0, id: 'd'),
    ], yieldGrams: 175);
    final r = CalculationEngine.calculate(dish);
    final rowsP = dish.ingredients
        .map((i) => CalculationEngine.parseInputDouble(
            CalculationEngine.formatMacro(i.proteinInDish))!)
        .toList();
    final sumP = rowsP.fold<double>(0, (a, b) => a + b);
    final printed = CalculationEngine.parseInputDouble(
        CalculationEngine.formatMacro(r.rawTotalProtein))!;
    // ignore: avoid_print
    print('LEAD-09 rows=$sumP total=$printed');
    expect(sumP.toStringAsFixed(2), printed.toStringAsFixed(2));
  });

  // ───────────────────────────────────────────────────────────────────────
  // LEAD-10. Провайдер → UI lookup: savedDishesProvider НЕ читает БД,
  // рецепт самодостаточен (критерий 8 «snapshot-независимость»).
  // ───────────────────────────────────────────────────────────────────────
  test('LEAD-10 saved recipe recalculates without any product repository', () {
    final d = _dish([_i(_p(), 300)], yieldGrams: 220);
    final json = jsonEncode(d.toJson());
    final restored = Dish.fromJson(jsonDecode(json) as Map<String, dynamic>);
    final a = CalculationEngine.calculate(d);
    final b = CalculationEngine.calculate(restored);
    expect(b.cookedKcal, a.cookedKcal);
    expect(restored.ingredients.single.product.name, 'Говядина 1 кат.');
  });
}
