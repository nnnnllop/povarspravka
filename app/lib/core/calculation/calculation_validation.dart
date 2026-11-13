import 'calculation_math.dart';
import 'models/calculation_result.dart';
import 'models/dish.dart';
import 'models/product.dart';

/// Reject corrupt inputs rather than manufacturing zero nutrients.
class CalculationValidation {
  static bool inRange(double value, double min, double max) =>
      value.isFinite && value >= min && value <= max;

  static void range(double value, double min, double max, String name) {
    if (!inRange(value, min, max)) {
      throw ArgumentError.value(value, name, 'Expected finite $min..$max');
    }
  }

  /// Не бросающая проверка продукта (FUZZ-01) для пользовательских путей:
  /// добавление в раскладку и загрузка из хранилища.
  static bool isValidProduct(Product p) {
    try {
      product(p);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Допустимый диапазон тройки сохранности Б/Ж/У (только режим legacy).
  ///
  /// Верхняя граница — 1.0 (потерь нет, так считаются холодные блюда).
  /// Нижняя — 0.01 (1 %): `retention = 0` даёт правдоподобно отформатированное
  /// «0,0 ккал» для килограмма мяса (MATH-08) — это ошибка ввода, а не
  /// коэффициент. Фактическая экстракция в отвар моделируется отдельным
  /// [HeatProcess.stock] на уровне блюда, а не нулевой сохранностью.
  static const double minRetention = 0.01;
  static const double maxRetention = 1.0;

  /// Минимальный осмысленный выход готового блюда (MATH-05).
  ///
  /// При выходе 0,1 г блюдо на 1 кг даёт коэффициент ×1000 и десятки
  /// миллионов ккал на 100 г. Ограничение ставится там, где оно реально
  /// защищает: в знаменателе «на 100 г» ([Dish.effectiveYieldGrams] и
  /// [CalculationResult.portion]), а не в сыром поле модели — чтобы
  /// пользователь не получал исключение при вводе, валидатор всё равно
  /// отвергает такие значения до расчёта.
  static const double minCustomYieldGrams = 1.0;
  static const double maxCustomYieldGrams = 9999999.0;

  /// Верхняя граница отходов — строго меньше 100 % (MATH-03).
  ///
  /// Продукт без съедобной части не может входить в раскладку: раньше
  /// `wastePct = 100` молча превращался в «0 г нетто», и 200 г свёклы
  /// печатались как «0» — повар не видел, что строка исчезла. Единый
  /// инвариант для валидатора, модели и UI — отказ на этапе проверки.
  static const double maxWastePct = 99.999;

  static void product(Product p) {
    if (!p.hasExplicitProtein || p.protein.isNaN) {
      throw ArgumentError('Product missing protein');
    }
    if (!p.hasExplicitFat || p.fat.isNaN) {
      throw ArgumentError('Product missing fat');
    }
    if (!p.hasExplicitCarbs || p.carbs.isNaN) {
      throw ArgumentError('Product missing carbs');
    }
    // MATH-03: отходы ≥ 100 % — продукт без съедобной части.
    range(p.wastePct, 0, maxWastePct, 'wastePct');
    range(p.protein, 0, 100, 'protein');
    range(p.fat, 0, 100, 'fat');
    range(p.carbs, 0, 100, 'carbs');
    if (CalculationMath.sumExceeds([p.protein, p.fat, p.carbs], 100)) {
      throw ArgumentError(
        'Product nutrients sum (${p.protein} + ${p.fat} + ${p.carbs}) exceeds 100g',
      );
    }
    // FUZZ-01 / FUZZ-04: NaN, ±Infinity и отрицательные значения энергии и
    // микронутриентов раньше проходили дальше и роняли сохранение сырым
    // `JsonUnsupportedObjectError: ... Infinity`.
    //
    // `kcal` проверяется, только если он реально был задан: у продукта без
    // явной калорийности поле остаётся дефолтным нулём и не участвует в
    // расчёте (энергия всегда пересчитывается по 4/9/4).
    if (p.hasExplicitKcal) range(p.kcal, 0, 100000, 'kcal');
    range(p.water, 0, 1000, 'water');
    range(p.fiber, 0, 100, 'fiber');
    range(p.ash, 0, 100, 'ash');
    range(p.organicAcids, 0, 100, 'organicAcids');
    range(p.sugars, 0, 100, 'sugars');
    range(p.starch, 0, 100, 'starch');
    range(p.sfa, 0, 100, 'sfa');
    range(p.pufa, 0, 100, 'pufa');
    range(p.chol, 0, 100000, 'chol');
    range(p.alcohol, 0, 100, 'alcohol');
  }

  static void dish(Dish dish) {
    // Тройка сохранности участвует в расчёте только в legacy; для остальных
    // способов потери берутся из таблицы, а сохранённая тройка ни на что
    // не влияет и не должна блокировать расчёт.
    if (dish.process.isLegacy) {
      for (final r in [
        dish.retentionProtein,
        dish.retentionFat,
        dish.retentionCarbs
      ]) {
        range(r, minRetention, maxRetention, 'retention');
      }
    }
    if (dish.customYieldGrams != null) {
      // MATH-05: выход ниже 1 г — не «мелкое блюдо», а ошибка порядка
      // величины (опечатка «0,1» вместо «100»). Именно это значение попадает
      // в знаменатель «на 100 г», поэтому оно отвергается до расчёта.
      range(dish.customYieldGrams!, minCustomYieldGrams, maxCustomYieldGrams,
          'customYieldGrams');
    }
    for (final ing in dish.ingredients) {
      range(ing.weightGrams, 0, 9999999, 'weightGrams');
      product(ing.product);
    }
  }

  /// MATH-08: блюдо с ненулевой массой сырья, у которого сохранность Б/Ж/У
  /// равна нулю по всем трём нутриентам, даёт правдоподобно отформатированное
  /// «0,0 ккал» для килограмма мяса. Это не ошибка расчёта (нулевая
  /// сохранность — валидный ввод), но почти всегда — забытое поле, поэтому
  /// UI показывает предупреждение.
  static bool warnsZeroRetention(Dish dish) {
    if (!dish.process.isLegacy) return false;
    final hasMass = dish.ingredients.any((i) => i.weightGrams > 0);
    return hasMass &&
        dish.retentionProtein == 0.0 &&
        dish.retentionFat == 0.0 &&
        dish.retentionCarbs == 0.0;
  }

  /// A3-INPUT-01: мягкое неблокирующее предупреждение, когда указанный поваром
  /// выход меньше суммарной массы Б/Ж/У после тепловой обработки (или хотя бы
  /// один макронутриент на 100 г превысил 100 г).
  ///
  /// В отличие от валидации при ручном вводе выхода, такая ситуация
  /// возникает, если сначала указан малый выход, а ингредиенты добавлены
  /// позже, либо загружена старая рецептура. Вес блюда принудительно не
  /// меняется; UI показывает мягкое предупреждение.
  static bool warnsImpossiblePer100g(CalculationResult result) {
    if (!result.hasYield) return false;
    return CalculationMath.sumExceeds(
          [result.cookedProtein, result.cookedFat, result.cookedCarbs],
          result.yieldGrams,
        ) ||
        result.per100gProtein > 100 ||
        result.per100gFat > 100 ||
        result.per100gCarbs > 100;
  }
}
