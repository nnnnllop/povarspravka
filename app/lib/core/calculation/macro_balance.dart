import 'calculation_engine.dart';

/// Доли калорийности (Б / Ж / У в %) и массовое соотношение Б : Ж : У.
class MacroBalance {
  final double protein;
  final double fat;
  final double carbs;
  final double proteinKcal;
  final double fatKcal;
  final double carbsKcal;
  final double totalKcal;
  final int proteinPct;
  final int fatPct;
  final int carbsPct;
  final double? fatToProteinRatio;
  final double? carbsToProteinRatio;

  const MacroBalance({
    required this.protein,
    required this.fat,
    required this.carbs,
    required this.proteinKcal,
    required this.fatKcal,
    required this.carbsKcal,
    required this.totalKcal,
    required this.proteinPct,
    required this.fatPct,
    required this.carbsPct,
    this.fatToProteinRatio,
    this.carbsToProteinRatio,
  });

  bool get hasEnergy => totalKcal > 0;

  factory MacroBalance.fromMacros({
    required double protein,
    required double fat,
    required double carbs,
  }) {
    final safeP = (protein.isFinite && protein > 0) ? protein : 0.0;
    final safeF = (fat.isFinite && fat > 0) ? fat : 0.0;
    final safeC = (carbs.isFinite && carbs > 0) ? carbs : 0.0;

    final pKcal = safeP * 4.0;
    final fKcal = safeF * 9.0;
    final cKcal = safeC * 4.0;
    final total = pKcal + fKcal + cKcal;

    var pPct = 0;
    var fPct = 0;
    var cPct = 0;

    if (total > 0) {
      final raw = [
        pKcal * 100.0 / total,
        fKcal * 100.0 / total,
        cKcal * 100.0 / total,
      ];
      final floors = [for (final v in raw) v.floor()];
      var remainder = 100 - (floors[0] + floors[1] + floors[2]);
      final order = [0, 1, 2]
        ..sort((a, b) => (raw[b] - floors[b]).compareTo(raw[a] - floors[a]));
      for (var i = 0; i < remainder; i++) {
        floors[order[i % 3]]++;
      }
      pPct = floors[0];
      fPct = floors[1];
      cPct = floors[2];
    }

    return MacroBalance(
      protein: safeP,
      fat: safeF,
      carbs: safeC,
      proteinKcal: pKcal,
      fatKcal: fKcal,
      carbsKcal: cKcal,
      totalKcal: total,
      proteinPct: pPct,
      fatPct: fPct,
      carbsPct: cPct,
      fatToProteinRatio: safeP > 0 ? safeF / safeP : null,
      carbsToProteinRatio: safeP > 0 ? safeC / safeP : null,
    );
  }

  /// Соотношение Б : Ж : У при нормировке белка к 1 (например, «1 : 1,2 : 3,4»).
  String? get ratioLabel {
    final fp = fatToProteinRatio;
    final cp = carbsToProteinRatio;
    if (fp == null || cp == null) return null;
    return '1 : ${CalculationEngine.formatGrams(fp)} : '
        '${CalculationEngine.formatGrams(cp)}';
  }
}
