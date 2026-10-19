import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

typedef ChaosHook = Future<void> Function(String point, File nativeFile);

// Test-only filesystem boundary hooks. No production code or real user paths.
class ChaosIO extends IOOverrides {
  final ChaosHook hook;
  ChaosIO(this.hook);
  @override
  File createFile(String path) => _ChaosFile(super.createFile(path), hook);
}

class _ChaosFile implements File {
  final File native;
  final ChaosHook hook;
  _ChaosFile(this.native, this.hook);
  String get role => path.endsWith('.bak.tmp')
      ? 'backup'
      : path.endsWith('.tmp')
          ? 'temp'
          : 'main';
  @override
  String get path => native.path;
  @override
  Directory get parent => native.parent;
  @override
  Future<bool> exists() => native.exists();
  @override
  Future<Uint8List> readAsBytes() async {
    await hook('$role.beforeRead', native);
    return native.readAsBytes();
  }

  @override
  Future<File> writeAsString(String contents,
      {FileMode mode = FileMode.write,
      Encoding encoding = utf8,
      bool flush = false}) async {
    await hook('$role.beforeWrite', native);
    await native.writeAsString(contents,
        mode: mode, encoding: encoding, flush: flush);
    await hook('$role.afterWrite', native);
    return this;
  }

  @override
  Future<File> writeAsBytes(List<int> bytes,
      {FileMode mode = FileMode.write, bool flush = false}) async {
    await hook('$role.beforeWrite', native);
    await native.writeAsBytes(bytes, mode: mode, flush: flush);
    await hook('$role.afterWrite', native);
    return this;
  }

  @override
  Future<File> rename(String newPath) async {
    final target = role == 'backup' ? 'backup' : 'main';
    await hook('$target.beforeRename', native);
    final renamed = await native.rename(newPath);
    await hook('$target.afterRename', renamed);
    return _ChaosFile(renamed, hook);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
