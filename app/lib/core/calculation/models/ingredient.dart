import '../calculation_math.dart';
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
  double get netGrams {
    if (!isGross || product.wastePct <= 0) {
      return weightGrams;
    }
    final edibleRatio = (100.0 - product.wastePct) / 100.0;
    return weightGrams * edibleRatio;
  }

  /// Округленная масса нетто (г), отображаемая в столбце «Количество, г» бланка
  double get netGramsRounded => CalculationMath.round1(netGrams);

  /// Белки в блюде (г) — рассчитываются от отображаемой массы нетто и белка на 100 г с округлением до 0,01 г
  double get proteinInDish => CalculationMath.productRounded(
      netGramsRounded, product.proteinRounded, 2,
      divideBy100: true);

  /// Жиры в блюде (г) — рассчитываются от отображаемой массы нетто и жиров на 100 г с округлением до 0,01 г
  double get fatInDish => CalculationMath.productRounded(
      netGramsRounded, product.fatRounded, 2,
      divideBy100: true);

  /// Углеводы в блюде (г) — рассчитываются от отображаемой массы нетто и углеводов на 100 г с округлением до 0,01 г
  double get carbsInDish => CalculationMath.productRounded(
      netGramsRounded, product.carbsRounded, 2,
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
    return Ingredient(
      id: json['id'] as String? ?? '',
      product: Product.fromJson(
        (json['product'] as Map<String, dynamic>?) ?? const {},
      ),
      weightGrams: (json['weightGrams'] as num?)?.toDouble() ?? 100.0,
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
