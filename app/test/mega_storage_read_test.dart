import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/data/repositories/dish_storage_repository.dart';

class BlindIO extends IOOverrides {
  @override
  File createFile(String path) => BlindFile(path);
}

class BlindFile implements File {
  @override
  final String path;
  BlindFile(this.path);
  @override
  Future<bool> exists() async => false;
  @override
  Future<Uint8List> readAsBytes() async => throw FileSystemException(
      'Injected inaccessible path', path, const OSError('Access denied', 5));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('PROBE inaccessible path must not look like empty user library',
      () async {
    final repo = DishStorageRepository(storageDirectory: Directory.systemTemp);
    await IOOverrides.runWithIOOverrides(() async {
      await expectLater(repo.loadAll(), throwsA(isA<FileSystemException>()));
    }, BlindIO());
  });
  test('PROBE directory occupying main storage path is an I/O error', () async {
    final dir = await Directory.systemTemp.createTemp('povar_type_');
    addTearDown(() => dir.delete(recursive: true));
    await Directory('${dir.path}/povarspravka_user_dishes.json').create();
    final repo = DishStorageRepository(storageDirectory: dir);
    await expectLater(repo.loadAll(), throwsA(isA<FileSystemException>()));
  });
}
