import '../calculation_math.dart';
import '../calculation_validation.dart';
import '../food_classifier.dart';
import 'heat_process.dart';
import 'loss_group.dart';
import 'product.dart';

class Ingredient {
  final String id;
  final Product product;
  final double weightGrams; // Введенная масса
  final bool isGross; // Масса брутто (с учетом отходов) или нетто

  /// Группа таблицы потерь, выбранная поваром вручную.
  ///
  /// `null` — группа по классификатору ([FoodClassifier.classify]). В JSON —
  /// ключ `group` (только если задана).
  final LossGroup? groupOverride;

  /// Способ обработки именно этого ингредиента (например, лук
  /// обжарен для супа).
  ///
  /// `null` — способ блюда (`Dish.process`). [HeatProcess.legacy] здесь
  /// не допускается: старый расчёт — свойство всего документа. В JSON —
  /// ключ `process` (только если задан).
  final HeatProcess? processOverride;

  const Ingredient({
    required this.id,
    required this.product,
    required this.weightGrams,
    this.isGross = false,
    this.groupOverride,
    this.processOverride,
  }) : assert(processOverride != HeatProcess.legacy,
            'legacy задаётся только для всего блюда');

  /// Группа таблицы потерь, по которой считается ингредиент: выбор
  /// повара или, если его нет, классификатор.
  LossGroup get lossGroup => groupOverride ?? FoodClassifier.classify(product);

  /// Способ обработки ингредиента в блюде со способом [dishProcess].
  ///
  /// Готовое блюдо справочника (`is_dish = 1`) уже прошло обработку —
  /// его нутриенты приведены для готового продукта, повторных потерь нет
  /// ([HeatProcess.cold]), если повар не задал способ явно.
  HeatProcess processIn(HeatProcess dishProcess) {
    final own = processOverride;
    if (own != null && !own.isLegacy) return own;
    return product.isDishOnly ? HeatProcess.cold : dishProcess;
  }

  /// Фактическая масса нетто (съедобная часть).
  ///
  /// MATH-03: `wastePct >= 100` — продукт без съедобной части, ошибка
  /// валидации (единый инвариант с [CalculationValidation.maxWastePct]),
  /// а не молчаливый «0 г».
  static double netFromGross(double gross, double wastePct) {
    CalculationValidation.range(gross, 0, 9999999, 'gross');
    CalculationValidation.range(
        wastePct, 0, CalculationValidation.maxWastePct, 'wastePct');
    if (wastePct <= 0.0) return gross;
    return CalculationMath.wasteAdjusted(gross, wastePct, 12);
  }

  /// No finite gross weight exists for positive net at 100% waste.
  ///
  /// MATH-04: обратный пересчёт НЕ округляет результат — иначе нарушается
  /// точная идемпотентность брутто→нетто→брутто. Полная точность (12 знаков
  /// после запятой) сохраняется в модели; округление — только при печати.
  static double? grossFromNet(double net, double wastePct) {
    CalculationValidation.range(net, 0, 9999999, 'net');
    CalculationValidation.range(
        wastePct, 0, CalculationValidation.maxWastePct, 'wastePct');
    if (wastePct <= 0.0) return net;
    return CalculationMath.wasteAdjusted(net, wastePct, 12, inverse: true);
  }

  double get netGrams {
    CalculationValidation.range(weightGrams, 0, 9999999, 'weightGrams');
    CalculationValidation.range(
        product.wastePct, 0, CalculationValidation.maxWastePct, 'wastePct');
    if (!isGross || product.wastePct <= 0.0) {
      return weightGrams;
    }
    return CalculationMath.wasteAdjusted(weightGrams, product.wastePct, 12);
  }

  /// Округленная масса нетто (г), отображаемая в столбце «Количество, г» бланка
  double get netGramsRounded {
    CalculationValidation.range(weightGrams, 0, 9999999, 'weightGrams');
    CalculationValidation.range(
        product.wastePct, 0, CalculationValidation.maxWastePct, 'wastePct');
    return isGross
        ? CalculationMath.wasteAdjusted(weightGrams, product.wastePct, 1)
        : CalculationMath.round1(weightGrams);
  }

  /// Белки в блюде (г) — рассчитываются от отображаемой массы нетто и белка на 100 г с округлением до 0,01 г
  double get proteinInDish =>
      CalculationMath.productRounded(netGramsRounded, product.proteinRounded, 2,
          divideBy100: true);

  /// Жиры в блюде (г) — рассчитываются от отображаемой массы нетто и жиров на 100 г с округлением до 0,01 г
  double get fatInDish =>
      CalculationMath.productRounded(netGramsRounded, product.fatRounded, 2,
          divideBy100: true);

  /// Углеводы в блюде (г) — рассчитываются от отображаемой массы нетто и углеводов на 100 г с округлением до 0,01 г
  double get carbsInDish =>
      CalculationMath.productRounded(netGramsRounded, product.carbsRounded, 2,
          divideBy100: true);

  /// Энергетическая ценность сырья по справочнику (ккал)
  double get kcalInDish => (netGramsRounded * product.kcal) / 100.0;

  /// Энергетическая ценность сырья по формуле бланка (4*Б + 9*Ж + 4*У)
  double get blankKcalInDish =>
      CalculationMath.energy(proteinInDish, fatInDish, carbsInDish);

  Map<String, dynamic> toJson() => {
        'id': id,
        'product': product.toJson(),
        'weightGrams': weightGrams,
        'isGross': isGross,
        if (groupOverride != null) 'group': groupOverride!.name,
        if (processOverride != null) 'process': processOverride!.name,
      };

  factory Ingredient.fromJson(Map<String, dynamic> json) {
    final weight = json['weightGrams'];
    if (weight is! num || !weight.toDouble().isFinite || weight < 0) {
      throw const FormatException('Missing or invalid weightGrams');
    }
    final id = json['id'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('Missing or invalid ingredient id');
    }
    final productJson = json['product'];
    if (productJson is! Map<String, dynamic>) {
      throw const FormatException('Missing or invalid ingredient product');
    }
    return Ingredient(
      id: id,
      product: Product.fromJson(productJson),
      weightGrams: weight.toDouble(),
      isGross: json['isGross'] as bool? ?? false,
      // Нет ключа / неизвестное имя → null (группа классификатора, способ
      // блюда): старые документы читаются без изменений.
      groupOverride: LossGroup.fromJsonName(json['group']),
      processOverride: HeatProcess.ingredientFromJsonName(json['process']),
    );
  }

  /// Копия с изменениями. Сброс ручного выбора — [clearGroupOverride] /
  /// [clearProcessOverride] (иначе `null` означает «не менять»).
  Ingredient copyWith({
    String? id,
    Product? product,
    double? weightGrams,
    bool? isGross,
    LossGroup? groupOverride,
    bool clearGroupOverride = false,
    HeatProcess? processOverride,
    bool clearProcessOverride = false,
  }) {
    if (processOverride == HeatProcess.legacy) {
      throw ArgumentError.value(processOverride, 'processOverride',
          'legacy задаётся только для всего блюда');
    }
    return Ingredient(
      id: id ?? this.id,
      product: product ?? this.product,
      weightGrams: weightGrams ?? this.weightGrams,
      isGross: isGross ?? this.isGross,
      groupOverride:
          clearGroupOverride ? null : (groupOverride ?? this.groupOverride),
      processOverride: clearProcessOverride
          ? null
          : (processOverride ?? this.processOverride),
    );
  }
}
