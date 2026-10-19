import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/data/repositories/dish_storage_repository.dart';
import 'culinary_logic_test.dart' show fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final number in ['1e309', '-1e309', 'extension']) {
    test('DEEP CRC recovery handles numeric overflow $number', () async {
      final dir = await Directory.systemTemp.createTemp('povar_crc_num_');
      addTearDown(() => dir.delete(recursive: true));
      final repo = DishStorageRepository(storageDirectory: dir);
      final old = fixture(100).copyWith(title: 'backup');
      await repo.saveAll(activeDraft: old, savedDishes: [old]);
      await repo.saveAll(
          activeDraft: old.copyWith(title: 'current'), savedDishes: [old]);
      final file = File('${dir.path}/povarspravka_user_dishes.json');
      final raw = await file.readAsString();
      final regex = RegExp(r'("weightGrams":)[0-9.eE+-]+');
      expect(regex.hasMatch(raw), isTrue);
      final bad = number == 'extension'
          ? '${raw.substring(0, raw.length - 1)},"extra":1e309}'
          : raw.replaceFirstMapped(regex, (m) => '${m[1]}$number');
      await file.writeAsString(bad, flush: true);
      final result =
          await DishStorageRepository(storageDirectory: dir).loadAll();
      expect(result.activeDraft!.toJson(), old.toJson());
      expect(result.savedDishes.single.toJson(), old.toJson());
    });
  }
}
