import 'package:flutter_test/flutter_test.dart';

void main() {
  test('probe', () {
    final t0 = DateTime.now();
    expect(1 + 1, 2);
    print('probe ok ${DateTime.now().difference(t0)}');
  });
}
