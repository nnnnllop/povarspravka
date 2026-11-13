// Задача 2026-11-03: таблица потерь Б/Ж/У при тепловой обработке.
//
// Роли оракулов разделены:
// 1. Сверяются все 84 ячейки `LossTable` с машиночитаемым блоком
//    docs/COEFFICIENT_SOURCES.md (синхронизация таблица <-> спецификация).
// 2. Независимый захардкоженный оракул 18 подтверждённых троек МР 2.3.0419-26
//    (прил. 4, с. 24) и частичной ячейки fry/fatOil (Ж=50%, S3) проверяет
//    `LossTable.lossFor` напрямую без чтения `COEFFICIENT_SOURCES.md`
//    (закрытие A3-TEST-01).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/loss_table.dart';
import 'package:povarspravka/core/calculation/models/heat_process.dart';
import 'package:povarspravka/core/calculation/models/loss_group.dart';

const _doc = '../docs/COEFFICIENT_SOURCES.md';

Map<String, dynamic> _block() {
  final text = File(_doc).readAsStringSync();
  final m = RegExp(r'<!-- LOSS_TABLE_JSON_BEGIN -->\s*```json\s*([\s\S]*?)```\s*<!-- LOSS_TABLE_JSON_END -->')
      .firstMatch(text);
  expect(m, isNotNull, reason: 'в $_doc нет блока LOSS_TABLE_JSON');
  return jsonDecode(m!.group(1)!) as Map<String, dynamic>;
}

const _lossProcesses = [
  HeatProcess.boil,
  HeatProcess.stew,
  HeatProcess.fry,
  HeatProcess.bake,
  HeatProcess.steam,
  HeatProcess.stock,
];

void main() {
  test('6 способов × 14 групп = 84 ячейки, все значения 0…100 %', () {
    expect(LossTable.table.keys.toSet(), _lossProcesses.toSet());
    var cells = 0;
    for (final p in _lossProcesses) {
      expect(LossTable.table[p]!.keys.toSet(), LossGroup.values.toSet(),
          reason: p.name);
      for (final g in LossGroup.values) {
        final l = LossTable.lossFor(g, p);
        for (final v in [l.protein, l.fat, l.carbs]) {
          expect(v, inInclusiveRange(0, 100), reason: '${p.name}/${g.name}');
        }
        cells++;
      }
    }
    expect(cells, 84);
  });

  test('каждая ячейка = docs/COEFFICIENT_SOURCES.md (значения, источник, UNVERIFIED)', () {
    final table = _block()['table'] as Map<String, dynamic>;
    expect(table.keys.toSet(), _lossProcesses.map((p) => p.name).toSet());
    for (final p in _lossProcesses) {
      final row = table[p.name] as Map<String, dynamic>;
      expect(row.keys.toSet(), LossGroup.values.map((g) => g.name).toSet());
      for (final g in LossGroup.values) {
        final doc = row[g.name] as Map<String, dynamic>;
        final l = LossTable.lossFor(g, p);
        final where = '${p.name}/${g.name}';
        expect(l.protein, (doc['p'] as num).toDouble(), reason: '$where Б');
        expect(l.fat, (doc['f'] as num).toDouble(), reason: '$where Ж');
        expect(l.carbs, (doc['c'] as num).toDouble(), reason: '$where У');
        expect(l.source.id, doc['source'], reason: '$where источник');
        expect(l.unverified.map((n) => n.name).toSet(),
            (doc['unverified'] as List).cast<String>().toSet(),
            reason: '$where UNVERIFIED');
        expect(l.note, isNotEmpty, reason: '$where: строка источника');
      }
    }
  });

  test('каждый источник — Id S1…S5, название и https-URL, упомянутый в документе', () {
    final doc = File(_doc).readAsStringSync();
    final sources = {
      for (final p in _lossProcesses)
        for (final g in LossGroup.values) LossTable.lossFor(g, p).source,
      NutrientLoss.none.source,
      NutrientLoss.legacyAverage.source,
      LossSource.skurikhin1985,
    };
    for (final s in sources) {
      expect(s.id, matches(RegExp(r'^S[1-5]$')));
      expect(s.title, isNotEmpty);
      expect(Uri.parse(s.url).scheme, 'https', reason: s.id);
      expect(doc, contains(s.url), reason: '${s.id}: URL есть в документе');
      expect(doc, contains('| ${s.id} |'), reason: s.id);
    }
  });

  test('cold — потерь нет; legacy — 6/12/9 = тройка 0,94/0,88/0,91', () {
    final block = _block();
    for (final g in LossGroup.values) {
      final c = LossTable.lossFor(g, HeatProcess.cold);
      expect([c.protein, c.fat, c.carbs], [0, 0, 0]);
      final l = LossTable.lossFor(g, HeatProcess.legacy);
      expect([l.protein, l.fat, l.carbs], [6, 12, 9]);
    }
    expect(block['cold'], containsPair('p', 0));
    expect(block['legacy'], allOf(containsPair('p', 6), containsPair('f', 12),
        containsPair('c', 9)));
    expect(kLegacyRetentionProtein, closeTo(1 - 6 / 100, 1e-12));
    expect(kLegacyRetentionFat, closeTo(1 - 12 / 100, 1e-12));
    expect(kLegacyRetentionCarbs, closeTo(1 - 9 / 100, 1e-12));
  });

  test('список UNVERIFIED: подтверждены ровно строки прил. 4 и жир при жарке', () {
    final verified = <String>{};
    var partial = 0;
    for (final p in _lossProcesses) {
      for (final g in LossGroup.values) {
        final l = LossTable.lossFor(g, p);
        if (l.isVerified) verified.add('${p.name}/${g.name}');
        if (!l.isVerified && l.unverified.length < 3) partial++;
      }
    }
    const plantStarch = ['grainPasta', 'legumes', 'rootTuber', 'flourBread'];
    const plantSugar = ['vegetable', 'fruitBerry'];
    expect(verified, {
      'boil/meat', 'boil/fish',
      for (final g in [...plantStarch, ...plantSugar]) 'boil/$g',
      'stew/meat',
      'fry/meat', 'fry/fish',
      for (final g in [...plantStarch, ...plantSugar]) 'fry/$g',
      'bake/dairy',
    });
    expect(partial, 1, reason: 'жарка жиров: Ж — S3, Б и У — UNVERIFIED');
    final fat = LossTable.lossFor(LossGroup.fatOil, HeatProcess.fry);
    expect(fat.unverified, {LossNutrient.protein, LossNutrient.carbs});
    expect(fat.source, LossSource.mrFryingFat);
    expect(fat.fat, 50);
  });

  test('независимый оракул первоисточника МР 2.3.0419-26 (18 троек прил. 4 + fry/fatOil)', () {
    // Захардкоженные значения из первоисточника МР 2.3.0419-26, прил. 4, с. 24;
    // тест НЕ читает docs/COEFFICIENT_SOURCES.md (A3-TEST-01).
    const mrAppendix4Verified = <(HeatProcess, LossGroup), (double, double, double)>{
      (HeatProcess.boil, LossGroup.meat): (10.0, 25.0, 0.0),
      (HeatProcess.boil, LossGroup.fish): (10.0, 10.0, 0.0),
      (HeatProcess.boil, LossGroup.grainPasta): (2.0, 2.0, 5.0),
      (HeatProcess.boil, LossGroup.legumes): (2.0, 2.0, 5.0),
      (HeatProcess.boil, LossGroup.rootTuber): (2.0, 2.0, 5.0),
      (HeatProcess.boil, LossGroup.vegetable): (2.0, 2.0, 2.0),
      (HeatProcess.boil, LossGroup.fruitBerry): (2.0, 2.0, 2.0),
      (HeatProcess.boil, LossGroup.flourBread): (2.0, 2.0, 5.0),
      (HeatProcess.stew, LossGroup.meat): (5.0, 5.0, 0.0),
      (HeatProcess.fry, LossGroup.meat): (10.0, 30.0, 0.0),
      (HeatProcess.fry, LossGroup.fish): (10.0, 20.0, 0.0),
      (HeatProcess.fry, LossGroup.grainPasta): (5.0, 10.0, 10.0),
      (HeatProcess.fry, LossGroup.legumes): (5.0, 10.0, 10.0),
      (HeatProcess.fry, LossGroup.rootTuber): (5.0, 10.0, 10.0),
      (HeatProcess.fry, LossGroup.vegetable): (5.0, 10.0, 20.0),
      (HeatProcess.fry, LossGroup.fruitBerry): (5.0, 10.0, 20.0),
      (HeatProcess.fry, LossGroup.flourBread): (5.0, 10.0, 10.0),
      (HeatProcess.bake, LossGroup.dairy): (5.0, 5.0, 5.0),
    };
    expect(mrAppendix4Verified, hasLength(18));

    final verifiedInCode = <(HeatProcess, LossGroup)>{};
    for (final p in _lossProcesses) {
      for (final g in LossGroup.values) {
        final actual = LossTable.lossFor(g, p);
        if (actual.isVerified) verifiedInCode.add((p, g));
      }
    }
    expect(verifiedInCode, mrAppendix4Verified.keys.toSet());

    for (final entry in mrAppendix4Verified.entries) {
      final (process, group) = entry.key;
      final (expP, expF, expC) = entry.value;
      final actual = LossTable.lossFor(group, process);
      expect([actual.protein, actual.fat, actual.carbs], [expP, expF, expC],
          reason: '${process.name}/${group.name}');
      expect(actual.source, LossSource.mrAppendix4,
          reason: '${process.name}/${group.name}');
      expect(actual.unverified, isEmpty,
          reason: '${process.name}/${group.name}');
    }

    // Частично подтверждённая ячейка (S3): при жарке к расчёту принимается 50 % жира.
    final fryFat = LossTable.lossFor(LossGroup.fatOil, HeatProcess.fry);
    expect(fryFat.fat, 50.0);
    expect(fryFat.source, LossSource.mrFryingFat);
    expect(fryFat.unverified, {LossNutrient.protein, LossNutrient.carbs});
  });

  test('пометка «не по ГОСТ»', () {
    expect(kNotGostNotice,
        'Пищевая ценность рассчитана по открытым справочным коэффициентам потерь, не по ГОСТ.');
    expect(File(_doc).readAsStringSync(), contains(kNotGostNotice));
  });
}
