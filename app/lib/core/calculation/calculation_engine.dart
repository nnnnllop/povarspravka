import 'calculation_math.dart';
import 'calculation_validation.dart';
import 'loss_table.dart';
import 'models/blank_mode.dart';
import 'models/calculation_result.dart';
import 'models/dish.dart';
import 'models/heat_process.dart';
import 'models/ingredient.dart';

/// Расчёт пищевой ценности блюда.
///
/// Задача 2026-11-03 «только нутриенты после тепловой обработки»:
///
///     Б_готов = Σ Б_i × (100 − потериБ(группа_i, способ_i)) / 100
///
/// так же для Ж и У; ккал = 4Б + 9Ж + 4У. Потери — [LossTable]
/// (источники — `docs/COEFFICIENT_SOURCES.md`). Брутто → нетто — отходы
/// продукта, как раньше. Вес готового блюда вводит повар: приложение
/// не моделирует уварку, развариваемость и экстракцию.
class CalculationEngine {
  static double _round1(double v) => CalculationMath.round1(v);
  static double _round2(double v) => CalculationMath.round2(v);

  /// Не бросающая версия [calculate] для виджетов (STATE-01).
  ///
  /// Возвращает `null`, если данные блюда невычислимы. Нужна там, где
  /// исключение из `build()` превратилось бы в красный экран — на домашнем
  /// экране в карточках черновика и сохранённого блюда.
  ///
  /// RA-22: перехватываются только ошибки данных ([isDataError]);
  /// ошибка программы (`TypeError`, `StackOverflowError`, …) не маскируется.
  static CalculationResult? tryCalculate(Dish dish) {
    try {
      return calculate(dish);
    } catch (e) {
      if (isDataError(e)) return null;
      rethrow;
    }
  }

  /// Ошибка входных данных, которую бросает [calculate]: недопустимое
  /// значение ([ArgumentError] валидатора), невозможное состояние
  /// ([StateError]) или битый документ ([FormatException]). Остальное —
  /// дефект программы, его нельзя показывать как «ошибку данных».
  static bool isDataError(Object error) =>
      error is ArgumentError ||
      error is StateError ||
      error is FormatException;

  /// Потери одного ингредиента в блюде со способом [dishProcess].
  ///
  /// Группа — выбор повара или классификатор ([Ingredient.lossGroup]);
  /// способ — способ ингредиента или блюда ([Ingredient.processIn]).
  /// `готовое = сырьё × (100 − потери) / 100` точно в десятичной арифметике,
  /// HALF-UP до 0,01 г — как сырьё в строке бланка.
  static IngredientLossLine lossLine(Ingredient ing, HeatProcess dishProcess) {
    final group = ing.lossGroup;
    final process = ing.processIn(dishProcess);
    final loss = LossTable.lossFor(group, process);
    final protein = ing.proteinInDish;
    final fat = ing.fatInDish;
    final carbs = ing.carbsInDish;
    return IngredientLossLine(
      ingredientId: ing.id,
      productName: ing.product.name,
      group: group,
      groupIsManual: ing.groupOverride != null,
      process: process,
      processIsManual: ing.processOverride != null,
      loss: loss,
      rawProtein: protein,
      rawFat: fat,
      rawCarbs: carbs,
      cookedProtein: CalculationMath.wasteAdjusted(protein, loss.protein, 2),
      cookedFat: CalculationMath.wasteAdjusted(fat, loss.fat, 2),
      cookedCarbs: CalculationMath.wasteAdjusted(carbs, loss.carbs, 2),
    );
  }

  /// Готовые Б/Ж/У блюда после тепловой обработки.
  ///
  ///  * [HeatProcess.legacy] — прежний расчёт без изменений: тройка `Dish`
  ///    (по умолчанию 0,94 / 0,88 / 0,91) применяется к суммам сырья. Так
  ///    считаются документы, созданные до задачи 2026-11-03, и они обязаны
  ///    давать прежние числа. Ручные группа/способ ингредиентов здесь
  ///    не действуют.
  ///  * любой другой способ — по ингредиенту ([lossLine]), итог — сумма
  ///    строк. Тройка `Dish` НЕ используется.
  static ({
    double protein,
    double fat,
    double carbs,
    List<IngredientLossLine> lines,
  }) _cooked(
    Dish dish, {
    required double rawTotalProtein,
    required double rawTotalFat,
    required double rawTotalCarbs,
  }) {
    if (dish.process.isLegacy) {
      final pPct =
          CalculationMath.productRounded(dish.retentionProtein, 100, 10);
      final fPct = CalculationMath.productRounded(dish.retentionFat, 100, 10);
      final cPct = CalculationMath.productRounded(dish.retentionCarbs, 100, 10);
      return (
        protein: CalculationMath.productRounded(rawTotalProtein, pPct, 2,
            divideBy100: true),
        fat: CalculationMath.productRounded(rawTotalFat, fPct, 2,
            divideBy100: true),
        carbs: CalculationMath.productRounded(rawTotalCarbs, cPct, 2,
            divideBy100: true),
        lines: const <IngredientLossLine>[],
      );
    }

    final lines = List<IngredientLossLine>.unmodifiable([
      for (final ing in dish.ingredients) lossLine(ing, dish.process),
    ]);
    return (
      protein: CalculationMath.sumRounded(lines.map((l) => l.cookedProtein), 2),
      fat: CalculationMath.sumRounded(lines.map((l) => l.cookedFat), 2),
      carbs: CalculationMath.sumRounded(lines.map((l) => l.cookedCarbs), 2),
      lines: lines,
    );
  }

  /// Итоговая сохранность `готовое / сырьё` до 0,0001 — только для
  /// отображения (в расчёте не участвует). Нет нутриента — нет потерь.
  static double _effectiveRetention(double cooked, double raw) => raw > 0
      ? CalculationMath.ratioRounded(cooked, raw, 4, multiplier: 1)
      : 1.0;

  /// Выполняет расчет показателей бланка для переданного блюда.
  /// Суммы по столбцам рассчитываются по округленным значениям ячеек (до 0,01 г / 0,1 ккал),
  /// чтобы ручная проверка калькулятором по напечатанному бланку сходилась копейка в копейку.
  static CalculationResult calculate(Dish dish) {
    CalculationValidation.dish(dish);
    final rawTotalWeight = CalculationMath.sumRounded(
        dish.ingredients.map((i) => i.netGramsRounded), 1);
    final rawTotalProtein = CalculationMath.sumRounded(
        dish.ingredients.map((i) => i.proteinInDish), 2);
    final rawTotalFat = CalculationMath.sumRounded(
        dish.ingredients.map((i) => i.fatInDish), 2);
    final rawTotalCarbs = CalculationMath.sumRounded(
        dish.ingredients.map((i) => i.carbsInDish), 2);
    // MATH-02 «sum-then-round» против «round-then-sum».
    //
    // Две величины с разным смыслом, и обе обязаны быть верными:
    //
    //  * `rawTotalKcal` — СТОЛБЕЦ бланка «сырьё». Это бухгалтерская строка:
    //    повар сверяет бланк калькулятором, поэтому она печатается как СУММА
    //    напечатанных построчных ккал (инвариант «итог = сумма строк»).
    //    На воздухе видно, что сумма строк систематически завышает точную
    //    энергию (на 65 строках — +0,7 ккал), но именно эту величину видит
    //    человек в бланке, и расхождение с итогом было бы хуже.
    //  * `cookedKcal` — энергетическая ценность готового блюда, считается
    //    ТОЧНО от сумм Б/Ж/У: 4·ΣP + 9·ΣF + 4·ΣC с единственным HALF-UP на
    //    выходе (MATH-02).
    final rawTotalKcal = CalculationMath.sumRounded(
        dish.ingredients.map((i) => i.blankKcalInDish), 1);

    final cooked = _cooked(
      dish,
      rawTotalProtein: rawTotalProtein,
      rawTotalFat: rawTotalFat,
      rawTotalCarbs: rawTotalCarbs,
    );
    final cookedProtein = cooked.protein;
    final cookedFat = cooked.fat;
    final cookedCarbs = cooked.carbs;

    // Формула ЭЦ: Б × 4 + Ж × 9 + У × 4.
    //
    // Энергия считается от ПЕЧАТНЫХ (округлённых до 0,01 г) значений Б/Ж/У:
    // так «ккал готового блюда» тождественно равно 4·P + 9·F + 4·C по тем
    // числам, которые человек видит в бланке, и ручная проверка сходится.
    final cookedKcal =
        CalculationMath.energy(cookedProtein, cookedFat, cookedCarbs);

    // Вес готового блюда — только ввод повара (для legacy без ввода — сумма
    // нетто, как раньше). `0` — вес не указан: итог на всё блюдо, «на 100 г»
    // не считается (пустое блюдо — тоже не ошибка: «0 г» и «— на 100 г»).
    final yieldGrams = dish.effectiveYieldGrams;

    // LOGIC-01: масса Б/Ж/У — КОМПОНЕНТ массы блюда, а не её верхняя граница
    // (предупреждение в UI, не ошибка). Отрицательный или нефинитный
    // выход — ошибка входа.
    if (!yieldGrams.isFinite || yieldGrams < 0) {
      throw ArgumentError('Dish yield must be non-negative (got $yieldGrams g)');
    }

    // В 100 г готового блюда
    final per100gProtein = yieldGrams > 0
        ? CalculationMath.ratioRounded(cookedProtein, yieldGrams, 2)
        : 0.0;
    final per100gFat = yieldGrams > 0
        ? CalculationMath.ratioRounded(cookedFat, yieldGrams, 2)
        : 0.0;
    final per100gCarbs = yieldGrams > 0
        ? CalculationMath.ratioRounded(cookedCarbs, yieldGrams, 2)
        : 0.0;
    final per100gKcal = yieldGrams > 0
        ? CalculationMath.ratioRounded(cookedKcal, yieldGrams, 1)
        : 0.0;

    final legacy = dish.process.isLegacy;
    return CalculationResult(
      blankMode: dish.blankMode,
      yieldGrams: yieldGrams,
      rawTotalWeight: rawTotalWeight,
      rawTotalProtein: rawTotalProtein,
      rawTotalFat: rawTotalFat,
      rawTotalCarbs: rawTotalCarbs,
      rawTotalKcal: dish.blankMode == BlankMode.detailed ? rawTotalKcal : null,
      process: dish.process,
      retentionProtein: legacy
          ? dish.retentionProtein
          : _effectiveRetention(cookedProtein, rawTotalProtein),
      retentionFat: legacy
          ? dish.retentionFat
          : _effectiveRetention(cookedFat, rawTotalFat),
      retentionCarbs: legacy
          ? dish.retentionCarbs
          : _effectiveRetention(cookedCarbs, rawTotalCarbs),
      lines: cooked.lines,
      cookedProtein: cookedProtein,
      cookedFat: cookedFat,
      cookedCarbs: cookedCarbs,
      cookedKcal: cookedKcal,
      per100gProtein: per100gProtein,
      per100gFat: per100gFat,
      per100gCarbs: per100gCarbs,
      per100gKcal: per100gKcal,
    );
  }

  /// Форматирование массы нетто в бланке с защитой от потери точности.
  ///
  /// MATH-04: при отходах ≥ 90 % печать нетто до 0,1 г теряет столько
  /// информации, что обратный пересчёт брутто уезжает на десятки граммов
  /// (245 074 г при 99,8 % → «490,1 г» → обратно 245 050 г). Поэтому при
  /// больших отходах печатается столько знаков после запятой, чтобы брутто
  /// восстанавливалось с точностью до 0,5 г.
  static String formatNetGrams(double net, double wastePct) {
    if (!net.isFinite) return '—';
    if (wastePct < 90.0) return formatGrams(net);
    // 1 % съедобной части → 0,1 г нетто = 10 г брутто: нужно 2 знака,
    // чтобы шаг брутто был ≤ 0,5 г на каждые 0,1 г нетто.
    final decimals = wastePct >= 99.0 ? 3 : 2;
    final rounded = CalculationMath.productRounded(
        net, 1.0, decimals);
    if (rounded == rounded.truncateToDouble()) {
      final (n, s) = CalculationMath.decimal(rounded);
      final scaled = s > 0
          ? n ~/ BigInt.from(10).pow(s)
          : n * BigInt.from(10).pow(-s);
      return scaled.toString();
    }
    return rounded.toStringAsFixed(decimals).replaceAll('.', ',');
  }

  /// Форматирование чисел для бланка с русской десятичной запятой.
  ///
  /// MATH-06: `1,5e21` раньше превращалось в `9223372036854775807` —
  /// `roundToDouble()` у бесконечности равен ей самой, после чего `toInt()`
  /// насыщал Int64. Теперь целые величины печатаются через `BigInt`, поэтому
  /// число выводится полностью и без клампа на любой разумной величине.
  static String formatGrams(double value) {
    if (!value.isFinite) return '—';
    final rounded = _round1(value);
    // MATH-07: 1e-7 раньше печаталось как «0» и строка ингредиента молча
    // обнулялась. Всё, что меньше половины шага печати, но больше нуля,
    // печатается как «<0,1» — повар видит, что масса есть.
    if (rounded == 0.0 && value > 0) return '<0,1';
    if (rounded == 0.0 && value < 0) return '>-0,1';
    // Целое — печатаем точно, через десятичную запись double в BigInt:
    // это не теряет точность и не насыщает Int64. `decimal()` возвращает
    // (мантисса, число_знаков_дроби − экспонента):
    //   150.0   → (1500, 1)   → 1500 / 10¹      = 150
    //   1.5e21  → (15, −20)   → 15 · 10²⁰      = 1500000000000000000000
    if (rounded == rounded.truncateToDouble()) {
      final (n, s) = CalculationMath.decimal(rounded);
      final scaled = s > 0
          ? n ~/ BigInt.from(10).pow(s)
          : n * BigInt.from(10).pow(-s);
      return scaled.toString();
    }
    return rounded.toStringAsFixed(1).replaceAll('.', ',');
  }

  /// Верхняя граница, до которой граммы вообще имеет смысл печатать.
  static const double maxPrintableGrams = 1e15;

  static String formatMacro(double value) {
    if (!value.isFinite) return '—';
    return _round2(value).toStringAsFixed(2).replaceAll('.', ',');
  }

  static String formatKcal(double value) {
    if (!value.isFinite) return '—';
    return _round1(value).toStringAsFixed(1).replaceAll('.', ',');
  }

  /// Shared exact percentage text for UI and all exports.
  static String formatPercent(double retention) =>
      CalculationMath.productRounded(retention, 100, 10)
          .toStringAsFixed(10)
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '')
          .replaceAll('.', ',');

  /// Exact format for waste percentage (e.g. 1.5 -> "1,5", 25 -> "25")
  static String formatWastePercent(double wastePct) => wastePct
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '')
      .replaceAll('.', ',');

  /// Разбор пользовательского ввода с поддержкой запятой и точки.
  ///
  /// * FUZZ-07: пробел — разделитель тысяч («1 000» → 1000), а не мусор;
  /// * FUZZ-08: отрицательные числа отклоняются (`-3` → `null`);
  /// * MATH-07: экспоненциальная запись принимается только если число
  ///   положительно и конечно — «1e-7» остаётся валидным входом, но UI
  ///   печатает его как «<0,1», а не как «0».
  static double? parseInputDouble(String input) {
    // Пробелы (в т.ч. неразрывные и тонкие) допускаются только как
    // групповые разделители между цифрами.
    final raw = input.trim();
    if (raw.isEmpty) return null;
    final thousands = RegExp(r'^(\d{1,3})(?:[ \u00A0\u202F]\d{3})+$');
    var cleaned = raw;
    if (thousands.hasMatch(raw)) {
      cleaned = raw.replaceAll(RegExp(r'[ \u00A0\u202F]'), '');
    } else if (RegExp(r'[ \u00A0\u202F\t\n]').hasMatch(raw)) {
      return null;
    }
    cleaned = cleaned.replaceAll(',', '.');
    // Отклоняем знак: масса не бывает отрицательной (FUZZ-08).
    if (cleaned.startsWith('-') || cleaned.startsWith('+')) return null;
    final parsed = double.tryParse(cleaned);
    if (parsed == null || !parsed.isFinite || parsed < 0) return null;
    return parsed;
  }
}
