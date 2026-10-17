import '../calculation_math.dart';
import '../calculation_validation.dart';
import 'product.dart';

class Ingredient {
  final String id;
  final Product product;
  final double weightGrams; // Введенная масса
  final bool isGross; // Масса брутто (с учетом отходов) или нетто

  const Ingredient({
    required this.id,
    required this.product,
    required this.weightGrams,
    this.isGross = false,
  });

  /// Фактическая масса нетто (съедобная часть)
  static double netFromGross(double gross, double wastePct) {
    CalculationValidation.range(gross, 0, 9999999, 'gross');
    CalculationValidation.range(wastePct, 0, 100, 'wastePct');
    if (wastePct >= 100.0) return 0.0;
    if (wastePct <= 0.0) return gross;
    return CalculationMath.wasteAdjusted(gross, wastePct, 12);
  }

  /// No finite gross weight exists for positive net at 100% waste.
  static double? grossFromNet(double net, double wastePct) {
    CalculationValidation.range(net, 0, 9999999, 'net');
    CalculationValidation.range(wastePct, 0, 100, 'wastePct');
    if (wastePct >= 100.0) return net == 0 ? 0 : null;
    if (wastePct <= 0.0) return net;
    return CalculationMath.wasteAdjusted(net, wastePct, 12, inverse: true);
  }

  double get netGrams {
    CalculationValidation.range(weightGrams, 0, 9999999, 'weightGrams');
    CalculationValidation.range(product.wastePct, 0, 100, 'wastePct');
    if (!isGross || product.wastePct <= 0.0) {
      return weightGrams;
    }
    if (product.wastePct >= 100.0) return 0.0;
    return CalculationMath.wasteAdjusted(weightGrams, product.wastePct, 12);
  }

  /// Округленная масса нетто (г), отображаемая в столбце «Количество, г» бланка
  double get netGramsRounded {
    CalculationValidation.range(weightGrams, 0, 9999999, 'weightGrams');
    CalculationValidation.range(product.wastePct, 0, 100, 'wastePct');
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
    );
  }

  Ingredient copyWith({
    String? id,
    Product? product,
    double? weightGrams,
    bool? isGross,
  }) {
    return Ingredient(
      id: id ?? this.id,
      product: product ?? this.product,
      weightGrams: weightGrams ?? this.weightGrams,
      isGross: isGross ?? this.isGross,
    );
  }
}
