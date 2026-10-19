import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:share_plus_platform_interface/platform_interface/share_plus_platform.dart';
import 'package:share_plus/share_plus.dart' show XFile;
import 'package:povarspravka/core/export/export_service.dart';
import 'package:povarspravka/presentation/providers/dish_provider.dart';
import 'package:povarspravka/core/calculation/models/ingredient.dart';
import 'final360_readiness_test.dart' show sample;

class TempPaths extends PathProviderPlatform {
  final String path;
  TempPaths(this.path);
  @override
  Future<String?> getTemporaryPath() async => path;
}

class AndroidCopyShare extends SharePlatform {
  final Directory root;
  bool fail = false;
  int calls = 0;
  AndroidCopyShare(this.root);
  @override
  Future<ShareResult> shareXFiles(List<XFile> files,
      {String? subject, String? text, Rect? sharePositionOrigin}) async {
    calls++;
    if (fail) {
      throw const FileSystemException('Injected share failure');
    }
    final copy = Directory('${root.path}/share_plus')..createSync();
    for (final f in files) {
      expect(File(f.path).lengthSync(), greaterThan(0));
      File(f.path).copySync('${copy.path}/${f.name}');
    }
    return const ShareResult('qa.receiver', ShareResultStatus.success);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('360 cache reaps abandoned owned dirs but preserves fresh and unrelated',
      () async {
    final root = await Directory.systemTemp.createTemp('povar_360_gc_');
    try {
      final owned = Directory('${root.path}/blank_old')..createSync();
      File('${owned.path}/file.pdf').writeAsStringSync('qa');
      final unrelated = Directory('${root.path}/user_documents')..createSync();
      await ExportService.pruneAbandonedExports(root);
      expect(owned.existsSync(), true);
      await ExportService.pruneAbandonedExports(root,
          now: DateTime.now().add(const Duration(days: 2)));
      expect(owned.existsSync(), false);
      expect(unrelated.existsSync(), true);
    } finally {
      await root.delete(recursive: true);
    }
  });
  test(
      '360 Android staging cleanup after 30 mocked handoffs and failed share, recipient copy survives',
      () async {
    final root = await Directory.systemTemp.createTemp('povar_360_share_');
    final paths = PathProviderPlatform.instance;
    final platform = SharePlatform.instance;
    final oldTarget = debugDefaultTargetPlatformOverride;
    final mock = AndroidCopyShare(root);
    try {
      PathProviderPlatform.instance = TempPaths(root.path);
      SharePlatform.instance = mock;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final n = DishNotifier();
      n.addIngredient(sample, 100);
      for (var i = 0; i < 30; i++) {
        await ExportService.shareFile(n.state, ExportType.values[i % 3]);
      }
      expect(Directory('${root.path}/exports').listSync(), isEmpty);
      expect(Directory('${root.path}/share_plus').listSync().length, 3);
      mock.fail = true;
      await expectLater(ExportService.shareFile(n.state, ExportType.docx),
          throwsA(isA<FileSystemException>()));
      expect(Directory('${root.path}/exports').listSync(), isEmpty);
      expect(mock.calls, 31);
      n.dispose();
    } finally {
      PathProviderPlatform.instance = paths;
      SharePlatform.instance = platform;
      debugDefaultTargetPlatformOverride = oldTarget;
      await root.delete(recursive: true);
    }
  });
  test('360 restoreIngredient cannot bypass nutrient validation', () {
    final n = DishNotifier();
    final invalid = sample.copyWith(protein: 100, fat: 1);
    expect(
        () => n.restoreIngredient(
            Ingredient(id: 'bad', product: invalid, weightGrams: 100), 0),
        throwsArgumentError);
    expect(n.state.ingredients, isEmpty);
    n.dispose();
  });
}
