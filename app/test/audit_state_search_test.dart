// STATE-02 / STATE-03: debounce, stale results and Timer leak of `SearchNotifier`.
//
// PASS-tests assert that the CURRENT implementation keeps its promise.
// FAIL-tests name a real, reproducible defect and are left red on purpose.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/models/product.dart';
import 'package:povarspravka/data/repositories/product_repository.dart';
import 'package:povarspravka/presentation/providers/search_provider.dart';

Product prod(String name) => Product(
    id: name.hashCode,
    code: name,
    name: name,
    groupId: 1,
    source: 'skurikhin',
    protein: 1,
    fat: 1,
    carbs: 1,
    kcal: 17);

class QueryEchoRepo extends ProductRepository {
  final calls = <String>[];
  final delays = <String, Duration>{};
  @override
  Future<List<Product>> searchProducts(
      {required String query,
      int? groupId,
      String? source,
      bool? isDish,
      int limit = 50}) async {
    calls.add(query);
    if (query == 'slow') await Future<void>.delayed(delays['slow'] ?? Duration.zero);
    if (query == 'яблоко') {
      await Future<void>.delayed(delays['яблоко'] ?? Duration.zero);
    }
    return [prod(query.isEmpty ? '<empty>' : query)];
  }
}



void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('STATE-02 debounce / stale results', () {
    testWidgets('(a) 20 rapid keystrokes -> exactly ONE final state for the '
        'last query, no stale overwrite', (tester) async {
      final repo = QueryEchoRepo();
      final container = ProviderContainer(
          overrides: [productRepositoryProvider.overrideWithValue(repo)]);
      addTearDown(container.dispose);
      final n = container.read(searchProvider.notifier);
      // Drain the constructor's immediate search('').
      await tester.pump();
      await tester.pump();
      final baselineCalls = repo.calls.length;

      const word = 'картофель обжареный ';
      for (var i = 1; i <= 20; i++) {
        n.search(word.substring(0, i));
        await tester.pump(const Duration(milliseconds: 10));
      }
      // Debounce window (150 ms) elapses.
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();

      final state = container.read(searchProvider);
      final executed = repo.calls.skip(baselineCalls).toList();
      // ignore: avoid_print
      print('STATE-02(a): repo calls after typing = $executed; '
          'final query="${state.query}", results=${state.results.map((p) => p.name).toList()}, '
          'isLoading=${state.isLoading}');
      expect(executed, [word.substring(0, 20)],
          reason: 'debounce must collapse 20 keystrokes into one call');
      expect(state.query, word.substring(0, 20));
      expect(state.results.single.name, word.substring(0, 20));
      expect(state.isLoading, isFalse);
    });

    testWidgets('(b) a slow repo must not clobber a newer query',
        (tester) async {
      final repo = QueryEchoRepo()
        ..delays['slow'] = const Duration(milliseconds: 400);
      final container = ProviderContainer(
          overrides: [productRepositoryProvider.overrideWithValue(repo)]);
      addTearDown(container.dispose);
      final n = container.read(searchProvider.notifier);
      await tester.pump();
      await tester.pump();
      expect(container.read(searchProvider).results.single.name, '<empty>');

      // "slow" is issued immediately (immediate:true bypasses debounce).
      n.search('slow', immediate: true);
      await tester.pump(const Duration(milliseconds: 10));
      n.search('fresh', immediate: true);
      await tester.pump(const Duration(milliseconds: 50));
      expect(container.read(searchProvider).results.single.name, 'fresh');
      // The slow call resolves AFTER the fresh one already applied.
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();

      final state = container.read(searchProvider);
      // ignore: avoid_print
      print('STATE-02(b): final query="${state.query}", '
          'results=${state.results.map((p) => p.name).toList()}, '
          'isLoading=${state.isLoading}, repo calls=${repo.calls}');
      expect(state.query, 'fresh');
      expect(state.results.single.name, 'fresh',
          reason: 'the stale "slow" answer must be dropped by _requestId');
    });

    testWidgets('(c) setIsDishFilter during an in-flight search does not '
        'produce a list for the OLD filter', (tester) async {
      final repo = QueryEchoRepo()
        ..delays['яблоко'] = const Duration(milliseconds: 300);
      final container = ProviderContainer(
          overrides: [productRepositoryProvider.overrideWithValue(repo)]);
      addTearDown(container.dispose);
      final n = container.read(searchProvider.notifier);
      await tester.pump();
      await tester.pump();
      expect(container.read(searchProvider).selectedIsDish, isNull);

      final pending = n.search('яблоко', immediate: true);
      await tester.pump(const Duration(milliseconds: 20));
      n.setIsDishFilter(true); // bumps _requestId via search(immediate:true)
      expect(container.read(searchProvider).selectedIsDish, isTrue);
      await tester.pump(const Duration(milliseconds: 400));
      await pending;
      await tester.pump();

      final state = container.read(searchProvider);
      // ignore: avoid_print
      print('STATE-02(c): selectedIsDish=${state.selectedIsDish}, '
          'query="${state.query}", results='
          '${state.results.map((p) => p.name).toList()}, '
          'repo calls=${repo.calls}');
      expect(state.selectedIsDish, isTrue);
      expect(state.results.single.name, 'яблоко');
    });

    test('(d) query-only changes DO bump the request id (control)', () async {
      final repo = QueryEchoRepo();
      final n = SearchNotifier(repo);
      addTearDown(n.dispose);
      await n.search('a', immediate: true);
      await n.search('ab', immediate: true);
      expect(repo.calls, containsAllInOrder(['', 'a', 'ab']));
    });
  });

  group('STATE-03 search Timer hygiene', () {
    test('constructor issues an immediate search("") and dispose() leaves no '
        'pending timer', () async {
      final repo = QueryEchoRepo();
      final n = SearchNotifier(repo);
      expect(repo.calls, ['']);
      // Schedule a debounced search, then dispose while it is pending.
      final pending = n.search('abc');
      n.dispose();
      await pending.timeout(const Duration(seconds: 1),
          onTimeout: () => fail('debounce Future did not complete on dispose'));
      await Future<void>.delayed(const Duration(milliseconds: 250));
      // ignore: avoid_print
      print('STATE-03: repo calls = ${repo.calls} (debounced "abc" must not run)');
      expect(repo.calls, [''],
          reason: 'dispose() cancels the debounce timer before it fires');
    });

    testWidgets('ProviderContainer.dispose() cancels the search timer '
        '(a leaked 150 ms Timer fails the framework invariant)', (tester) async {
      final repo = QueryEchoRepo();
      final container = ProviderContainer(
          overrides: [productRepositoryProvider.overrideWithValue(repo)]);
      container.read(searchProvider.notifier).search('x');
      await tester.pump(const Duration(milliseconds: 20));
      container.dispose();
      await tester.pump();

      // `AutomatedTestWidgetsFlutterBinding._verifyInvariants` asserts
      // "A Timer is still pending even after the widget tree was disposed"
      // when a timer is alive at the END of a testWidgets body:
      //   if (periodicTimerCount != 0 || nonPeriodicTimerCount != 0) ...
      // So finishing this body without pulling the pump to 200 ms means the
      // framework itself checks the timer for us.
      // ignore: avoid_print
      print('STATE-03 widget: repo calls = ${repo.calls}');
      expect(repo.calls, [''],
          reason: 'the debounced timer must not survive disposal');
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('REGRESSION GUARD: if dispose() did not cancel, the 150 ms '
        'Timer would still be pending and the framework would fail', (tester) async {
      final repo = QueryEchoRepo();
      final n = SearchNotifier(repo)..search('leak');
      await tester.pump();
      // Dispose WITHOUT pumping past the debounce window. A missing
      // `_debounceTimer?.cancel()` inside SearchNotifier.dispose() makes the
      // binding throw "A Timer is still pending..." at the end of this body.
      n.dispose();
      await tester.pump(const Duration(milliseconds: 1));
      expect(repo.calls, ['']);
    });

    testWidgets('a search in flight when the notifier is disposed does not '
        'touch state afterwards', (tester) async {
      final repo = QueryEchoRepo()
        ..delays['z'] = const Duration(milliseconds: 100);
      final container = ProviderContainer(
          overrides: [productRepositoryProvider.overrideWithValue(repo)]);
      final n = container.read(searchProvider.notifier);
      await tester.pump();
      unawaited(n.search('z', immediate: true));
      container.dispose();
      await tester.pump(const Duration(milliseconds: 250));
      expect(tester.takeException(), isNull);
    });
  });
}
