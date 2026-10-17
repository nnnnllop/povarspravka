import '../calculation_math.dart';

class ProductMeasure {
  final int id;
  final int productId;
  final String name;
  final double grams;

  const ProductMeasure({
    required this.id,
    required this.productId,
    required this.name,
    required this.grams,
  });

  factory ProductMeasure.fromMap(Map<String, dynamic> map) {
    return ProductMeasure(
      id: map['id'] as int? ?? 0,
      productId: map['product_id'] as int? ?? 0,
      name: map['name'] as String? ?? 'порция',
      grams: (map['grams'] as num?)?.toDouble() ?? 100.0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'product_id': productId,
        'name': name,
        'grams': grams,
      };

  factory ProductMeasure.fromJson(Map<String, dynamic> json) =>
      ProductMeasure.fromMap(json);
}

class ProductNutrient {
  final String code;
  final String name;
  final String unit;
  final double value;
  final String category; // 'mineral', 'vitamin', 'other'

  const ProductNutrient({
    required this.code,
    required this.name,
    required this.unit,
    required this.value,
    required this.category,
  });

  bool get isMineral => category == 'mineral';
  bool get isVitamin => category == 'vitamin';

  static const Map<String, ({String name, String unit, String category})>
      _nutrientMeta = {
    // Минералы
    'NA': (name: 'Натрий (Na)', unit: 'мг', category: 'mineral'),
    'K': (name: 'Калий (K)', unit: 'мг', category: 'mineral'),
    'CA': (name: 'Кальций (Ca)', unit: 'мг', category: 'mineral'),
    'MG': (name: 'Магний (Mg)', unit: 'мг', category: 'mineral'),
    'P': (name: 'Фосфор (P)', unit: 'мг', category: 'mineral'),
    'FE': (name: 'Железо (Fe)', unit: 'мг', category: 'mineral'),
    'ZN': (name: 'Цинк (Zn)', unit: 'мг', category: 'mineral'),
    'CU': (name: 'Медь (Cu)', unit: 'мг', category: 'mineral'),
    'SE': (name: 'Селен (Se)', unit: 'мкг', category: 'mineral'),
    // Витамины
    'VITA_RAE': (name: 'Витамин A (РЭ)', unit: 'мкг', category: 'vitamin'),
    'RETOL': (name: 'Ретинол', unit: 'мкг', category: 'vitamin'),
    'CARTB': (name: 'Бета-каротин', unit: 'мкг', category: 'vitamin'),
    'TOCPHA': (name: 'Витамин E (ТЭ)', unit: 'мг', category: 'vitamin'),
    'VITD': (name: 'Витамин D', unit: 'мкг', category: 'vitamin'),
    'VITC': (name: 'Витамин C', unit: 'мг', category: 'vitamin'),
    'THIA': (name: 'Витамин B1 (тиамин)', unit: 'мг', category: 'vitamin'),
    'RIBF': (name: 'Витамин B2 (рибофлавин)', unit: 'мг', category: 'vitamin'),
    'NIA': (name: 'Витамин PP (ниацин)', unit: 'мг', category: 'vitamin'),
    'NIAEQ': (name: 'Ниациновый эквивалент', unit: 'мг', category: 'vitamin'),
    'VITB6A': (name: 'Витамин B6', unit: 'мг', category: 'vitamin'),
    'FOL': (name: 'Фолаты (B9)', unit: 'мкг', category: 'vitamin'),
    'VITB12': (name: 'Витамин B12', unit: 'мкг', category: 'vitamin'),
    'CHOLN': (name: 'Холин (B4)', unit: 'мг', category: 'vitamin'),
    'VITK1': (name: 'Витамин K', unit: 'мкг', category: 'vitamin'),
  };

  static ProductNutrient? fromMap(Map<String, dynamic> map) {
    final rawCode = (map['nutrient_code'] as String? ?? '').toUpperCase();
    final val = (map['value'] as num?)?.toDouble() ?? 0.0;
    if (rawCode.isEmpty || val <= 0) return null;

    final meta = _nutrientMeta[rawCode];
    if (meta == null) return null;

    return ProductNutrient(
      code: rawCode,
      name: meta.name,
      unit: meta.unit,
      value: val,
      category: meta.category,
    );
  }
}

class Product {
  final int id;
  final String code;
  final String name;
  final String? nameNorm;
  final int groupId;
  final String source; // 'skurikhin' or 'usda'
  final int? pageNum;
  final double wastePct; // процент отходов при холодной обработке
  final double protein; // белки на 100г
  final double fat; // жиры на 100г
  final double carbs; // углеводы на 100г
  final double kcal; // калорийность на 100г
  final double water;
  final double fiber;
  final double ash;
  final double organicAcids;
  final double sugars;
  final double starch;
  final double sfa;
  final double pufa;
  final double chol;
  final double alcohol;
  final List<ProductMeasure> measures;
  final bool hasExplicitProtein;
  final bool hasExplicitFat;
  final bool hasExplicitCarbs;
  final bool hasExplicitKcal;

  const Product({
    required this.id,
    required this.code,
    required this.name,
    this.nameNorm,
    required this.groupId,
    required this.source,
    this.pageNum,
    this.wastePct = 0.0,
    required this.protein,
    required this.fat,
    required this.carbs,
    required this.kcal,
    this.water = 0.0,
    this.fiber = 0.0,
    this.ash = 0.0,
    this.organicAcids = 0.0,
    this.sugars = 0.0,
    this.starch = 0.0,
    this.sfa = 0.0,
    this.pufa = 0.0,
    this.chol = 0.0,
    this.alcohol = 0.0,
    this.measures = const [],
    this.hasExplicitProtein = true,
    this.hasExplicitFat = true,
    this.hasExplicitCarbs = true,
    this.hasExplicitKcal = true,
  });

  /// Only manually checked Skurikhin measures are exposed: the legacy OCR
  /// table has merged digits and substring-based assignments to unrelated dishes.
  /// Page 207: cups 250/200 ml, spoons filled as specified in the book.
  /// Page 210: edible egg mass; category is explicit, not a universal egg weight.
  List<ProductMeasure> get calculationMeasures {
    if (!isSkurikhin) {
      return measures.where((m) {
        if (!m.grams.isFinite || m.grams <= 0 || m.grams > 5000) return false;
        final mLower = m.name.toLowerCase();
        final pLower = name.toLowerCase();
        if (mLower.contains('egg') ||
            pLower.contains('яйц') ||
            mLower.contains('яйц')) {
          final isQuail =
              mLower.contains('quail') || pLower.contains('перепел');
          if (isQuail) {
            if (m.grams < 6.0 || m.grams > 25.0) return false;
          } else {
            if (m.grams < 25.0 || m.grams > 120.0) return false;
          }
        }
        if (mLower.contains('cup') || mLower.contains('стакан')) {
          if (m.grams < 50.0 || m.grams > 450.0) return false;
        }
        if (mLower.contains('tbsp') || mLower.contains('столовая лож')) {
          if (m.grams < 3.0 || m.grams > 50.0) return false;
        }
        if (mLower.contains('tsp') || mLower.contains('чайная лож')) {
          if (m.grams < 0.5 || m.grams > 25.0) return false;
        }
        return true;
      }).toList();
    }
    final values = switch (name) {
      'Яйцо куриное' => {'1 шт. (1 категория, нетто)': 47.0},
      'Яйцо перепелиное' => {'1 шт. (нетто)': 9.0},
      'Сметана 10,0% жирности' => {
          'стакан (чайный 250 мл)': 250.0,
          'стакан (граненый 200 мл)': 200.0,
          'столовая ложка': 20.0,
          'чайная ложка': 9.0
        },
      'Сметана 30,0% жирности' => {
          'стакан (чайный 250 мл)': 250.0,
          'стакан (граненый 200 мл)': 200.0,
          'столовая ложка': 25.0,
          'чайная ложка': 11.0
        },
      _ => <String, double>{},
    };
    return values.entries
        .toList()
        .asMap()
        .entries
        .map((entry) => ProductMeasure(
            id: -(entry.key + 1),
            productId: id,
            name: entry.value.key,
            grams: entry.value.value))
        .toList();
  }

  bool get isSkurikhin => source.toLowerCase() == 'skurikhin';
  bool get isUsda => source.toLowerCase() == 'usda';

  String get sourceLabel => isSkurikhin ? 'Скурихин' : 'USDA';

  double get proteinRounded => CalculationMath.round2(protein);
  double get fatRounded => CalculationMath.round2(fat);
  double get carbsRounded => CalculationMath.round2(carbs);
  double get kcalRounded => CalculationMath.round1(kcal);

  factory Product.fromMap(
    Map<String, dynamic> map, [
    List<ProductMeasure> measures = const [],
  ]) {
    return Product(
      id: map['id'] as int? ?? 0,
      code: map['code'] as String? ?? '',
      name: map['name'] as String? ?? '',
      nameNorm: map['name_norm'] as String?,
      groupId: map['group_id'] as int? ?? 0,
      source: map['source'] as String? ?? 'skurikhin',
      pageNum: map['page_num'] as int?,
      wastePct: (map['waste_pct'] as num?)?.toDouble() ?? 0.0,
      protein: (map['protein'] as num?)?.toDouble() ?? 0.0,
      fat: (map['fat'] as num?)?.toDouble() ?? 0.0,
      carbs: (map['carbs'] as num?)?.toDouble() ?? 0.0,
      kcal: (map['kcal'] as num?)?.toDouble() ?? 0.0,
      water: (map['water'] as num?)?.toDouble() ?? 0.0,
      fiber: (map['fiber'] as num?)?.toDouble() ?? 0.0,
      ash: (map['ash'] as num?)?.toDouble() ?? 0.0,
      organicAcids: (map['organic_acids'] as num?)?.toDouble() ?? 0.0,
      sugars: (map['sugars'] as num?)?.toDouble() ?? 0.0,
      starch: (map['starch'] as num?)?.toDouble() ?? 0.0,
      sfa: (map['sfa'] as num?)?.toDouble() ?? 0.0,
      pufa: (map['pufa'] as num?)?.toDouble() ?? 0.0,
      chol: (map['chol'] as num?)?.toDouble() ?? 0.0,
      alcohol: (map['alcohol'] as num?)?.toDouble() ?? 0.0,
      measures: measures,
      hasExplicitProtein: map.containsKey('protein') && map['protein'] != null,
      hasExplicitFat: map.containsKey('fat') && map['fat'] != null,
      hasExplicitCarbs: map.containsKey('carbs') && map['carbs'] != null,
      hasExplicitKcal: map.containsKey('kcal') && map['kcal'] != null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'code': code,
        'name': name,
        'name_norm': nameNorm,
        'group_id': groupId,
        'source': source,
        'page_num': pageNum,
        'waste_pct': wastePct,
        if (hasExplicitProtein) 'protein': protein,
        if (hasExplicitFat) 'fat': fat,
        if (hasExplicitCarbs) 'carbs': carbs,
        if (hasExplicitKcal) 'kcal': kcal,
        'water': water,
        'fiber': fiber,
        'ash': ash,
        'organic_acids': organicAcids,
        'sugars': sugars,
        'starch': starch,
        'sfa': sfa,
        'pufa': pufa,
        'chol': chol,
        'alcohol': alcohol,
        'measures': measures.map((m) => m.toJson()).toList(),
      };

  factory Product.fromJson(Map<String, dynamic> json) {
    final rawMeasures = json['measures'] as List<dynamic>? ?? const [];
    final measures = rawMeasures
        .whereType<Map<String, dynamic>>()
        .map(ProductMeasure.fromJson)
        .toList();
    return Product.fromMap(json, measures);
  }

  Product copyWith({
    int? id,
    String? code,
    String? name,
    String? nameNorm,
    int? groupId,
    String? source,
    int? pageNum,
    double? wastePct,
    double? protein,
    double? fat,
    double? carbs,
    double? kcal,
    double? water,
    double? fiber,
    double? ash,
    double? organicAcids,
    double? sugars,
    double? starch,
    double? sfa,
    double? pufa,
    double? chol,
    double? alcohol,
    List<ProductMeasure>? measures,
    bool? hasExplicitProtein,
    bool? hasExplicitFat,
    bool? hasExplicitCarbs,
    bool? hasExplicitKcal,
  }) {
    return Product(
      id: id ?? this.id,
      code: code ?? this.code,
      name: name ?? this.name,
      nameNorm: nameNorm ?? this.nameNorm,
      groupId: groupId ?? this.groupId,
      source: source ?? this.source,
      pageNum: pageNum ?? this.pageNum,
      wastePct: wastePct ?? this.wastePct,
      protein: protein ?? this.protein,
      fat: fat ?? this.fat,
      carbs: carbs ?? this.carbs,
      kcal: kcal ?? this.kcal,
      water: water ?? this.water,
      fiber: fiber ?? this.fiber,
      ash: ash ?? this.ash,
      organicAcids: organicAcids ?? this.organicAcids,
      sugars: sugars ?? this.sugars,
      starch: starch ?? this.starch,
      sfa: sfa ?? this.sfa,
      pufa: pufa ?? this.pufa,
      chol: chol ?? this.chol,
      alcohol: alcohol ?? this.alcohol,
      measures: measures ?? this.measures,
      hasExplicitProtein: hasExplicitProtein ?? this.hasExplicitProtein,
      hasExplicitFat: hasExplicitFat ?? this.hasExplicitFat,
      hasExplicitCarbs: hasExplicitCarbs ?? this.hasExplicitCarbs,
      hasExplicitKcal: hasExplicitKcal ?? this.hasExplicitKcal,
    );
  }
}
