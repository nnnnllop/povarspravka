import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/data/repositories/dish_storage_repository.dart';
import '../test/culinary_logic_test.dart' show fixture;
import '../test/support/chaos_io.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('DEEP isolated process checkpoint worker', () async {
    final env = Platform.environment;
    final root = Directory(env['MEGA_KILL_ROOT']!);
    if (env['MEGA_KILL_MODE'] == 'verify') {
      final cases =
          jsonDecode(File('${root.path}/cases.json').readAsStringSync())
              as List;
      for (final item in cases) {
        final dir = Directory('${root.path}/${item['name']}');
        final repo = DishStorageRepository(storageDirectory: dir);
        final result = await repo.loadAll();
        final expected = item['mode'] == 'recovery'
            ? 'v1'
            : item['point'] == 'main.afterRename'
                ? 'new'
                : 'committed';
        expect(result.activeDraft!.title, expected, reason: item['name']);
        expect(result.savedDishes.length, 10, reason: item['name']);
        for (var i = 0; i < 10; i++) {
          expect(result.savedDishes[i].id, 'id$i');
          expect(result.savedDishes[i].title, '${expected}_$i');
          expect(result.savedDishes[i].ingredients.single.weightGrams, 100);
        }
      }
      File('${root.path}/verified.json').writeAsStringSync(
          jsonEncode({'cases': cases.length, 'verified': cases.length}),
          flush: true);
      return;
    }
    final dir = Directory('${root.path}/${env['MEGA_KILL_CASE']}')
      ..createSync(recursive: true);
    final repo = DishStorageRepository(storageDirectory: dir);
    final base = fixture(100);
    Future<void> save(String name) => repo.saveAll(
        activeDraft: base.copyWith(title: name),
        savedDishes: List.generate(
            10, (i) => base.copyWith(id: 'id$i', title: '${name}_$i')));
    await save('v1');
    await save('committed');
    if (env['MEGA_KILL_MODE'] == 'recovery') {
      await File('${dir.path}/povarspravka_user_dishes.json')
          .writeAsString('{broken');
    }
    final ack = File('${dir.path}/checkpoint.ready');
    final ackTemp = File('${dir.path}/checkpoint.ready.tmp');
    final blocked = Completer<void>();
    final chaos = ChaosIO((point, file) async {
      if (point == env['MEGA_KILL_POINT']) {
        await ackTemp.writeAsString(jsonEncode({'point': point, 'pid': pid}),
            flush: true);
        await ackTemp.rename(ack.path);
        await blocked
            .future; // Parent terminates only this worker process tree.
      }
    });
    await IOOverrides.runWithIOOverrides(() async {
      if (env['MEGA_KILL_MODE'] == 'recovery') {
        await repo.loadAll();
      } else {
        await save('new');
      }
    }, chaos);
    fail('Expected checkpoint was not reached');
  }, timeout: const Timeout(Duration(minutes: 4)));
}
