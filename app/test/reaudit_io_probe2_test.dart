// ПОВТОРНЫЙ АУДИТ — диагностика (2): семантика rename при удержании хэндла и
// сколько попыток нужно, чтобы rename прошёл после закрытия.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'reaudit_io_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Q1 хэндл закрыт -> rename сразу ок?', () async {
    final s = await newStore('pr4');
    final log = <String>[];
    for (var trial = 0; trial < 10; trial++) {
      await s.lib.writeAsString('A$trial', flush: true);
      final raf = await s.lib.open();
      await raf.close();
      final t = s.f('x$trial.tmp');
      await t.writeAsString('B$trial', flush: true);
      try {
        await t.rename(s.lib.path);
        log.add('ok@1');
      } on FileSystemException catch (e) {
        log.add('fail(${e.osError?.errorCode})');
      }
    }
    // ignore: avoid_print
    print('Q1 $log');
    expect(log, isNotEmpty);
  });

  test('Q2 хэндл открыт (не читался) -> rename; после close — за сколько '
      'попыток', () async {
    final s = await newStore('pr5');
    await s.lib.writeAsString('A' * 1000, flush: true);
    final out = <String>[];
    for (var trial = 0; trial < 5; trial++) {
      final raf = await s.lib.open();
      final t = s.f('y$trial.tmp');
      await t.writeAsString('B' * 1000, flush: true);
      var okWhileOpen = true;
      try {
        await t.rename(s.lib.path);
      } on FileSystemException {
        okWhileOpen = false;
      }
      if (!okWhileOpen) {
        await raf.close();
        var attempts = 0;
        var ok = false;
        while (attempts < 10 && !ok) {
          attempts++;
          try {
            await t.rename(s.lib.path);
            ok = true;
          } on FileSystemException {
            await Future<void>.delayed(const Duration(milliseconds: 5));
          }
        }
        out.add('afterClose ok=$ok attempts=$attempts');
      } else {
        await raf.close();
        out.add('whileOpen ok');
      }
    }
    // ignore: avoid_print
    print('Q2 $out');
    expect(out, isNotEmpty);
  });

  test('Q3 две одновременные записи через RAFile в один файл', () async {
    final s = await newStore('pr6');
    await s.lib.writeAsString('A' * 4000, flush: true);
    final out = <String>[];
    final raf = await s.lib.open();
    await raf.length();
    await raf.setPosition(0);
    final buf = await raf.read(4000);
    out.add('raf read=${buf.length}');
    try {
      await s.lib.writeAsString('Z' * 4000, flush: true);
      out.add('second opener write OK');
    } on FileSystemException catch (e) {
      out.add('second opener write FAILED ${e.osError?.errorCode}');
    }
    await raf.close();
    try {
      await s.lib.writeAsString('Y' * 4000, flush: true);
      out.add('after close write OK');
    } on FileSystemException catch (e) {
      out.add('after close write FAILED ${e.osError?.errorCode}');
    }
    // ignore: avoid_print
    print('Q3 $out');
    expect(out, isNotEmpty);
  });

  test('Q4 одновременно open на чтение (как readAsBytes) + rename', () async {
    final s = await newStore('pr7');
    await s.lib.writeAsString('A' * 100000, flush: true);
    final res = <String>[];
    for (var trial = 0; trial < 10; trial++) {
      final raf = await s.lib.open();
      final t = s.f('z$trial.tmp');
      await t.writeAsString('B' * 100000, flush: true);
      try {
        await t.rename(s.lib.path);
        res.add('whileOpen ok');
      } on FileSystemException catch (e) {
        res.add('whileOpen fail(${e.osError?.errorCode})');
      }
      await raf.close();
    }
    // ignore: avoid_print
    print('Q4 $res');
    expect(res, isNotEmpty);
  });
}
