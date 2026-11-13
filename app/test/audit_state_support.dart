// A controllable in-memory `DishStorageRepository` used by the state audit.
//
// It records every `saveAll` payload (with the gating that was in force at
// CALL time, before the global write queue), so an audit test can prove
// exactly what was written to disk in which order.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:povarspravka/core/calculation/models/dish.dart';
import 'package:povarspravka/data/repositories/dish_storage_repository.dart';

class RecordedWrite {
  final Dish? draft;
  final List<Dish> saved;
  final String draftGating;
  final String savedGating;
  RecordedWrite(this.draft, this.saved, this.draftGating, this.savedGating);

  String get titleOfDraft => draft?.title ?? '<no draft>';
  List<String> get savedTitles => saved.map((d) => d.title).toList();

  @override
  String toString() =>
      'write(draft="${titleOfDraft}" $draftGating, saved=$savedTitles $savedGating)';
}

/// Gates are per-slot ("draft" / "saved"). A gated write blocks AFTER its
/// payload was captured — exactly where the real repository is serialized —
/// so the audit can force any interleaving of the two writers.
class GatedStorage extends DishStorageRepository {
  GatedStorage({this.initial});

  final DishStorageData? initial;
  final writes = <RecordedWrite>[];
  Dish? currentDraft;
  List<Dish> currentSaved = const [];

  Completer<void>? draftGate;
  Completer<void>? savedGate;
  bool _draftGating = false;
  bool _savedGating = false;
  Future<void> _tail = Future<void>.value();

  /// Number of `saveAll` calls that reached the (recorded) write point.
  int get writeCount => writes.length;

  void gateDraft() {
    _draftGating = true;
    draftGate = Completer<void>();
  }

  void gateSaved() {
    _savedGating = true;
    savedGate = Completer<void>();
  }

  void releaseDraft() {
    _draftGating = false;
    draftGate?.complete();
    draftGate = null;
  }

  void releaseSaved() {
    _savedGating = false;
    savedGate?.complete();
    savedGate = null;
  }

  @override
  Future<DishStorageData> loadAll() async {
    if (initial == null) return const DishStorageData();
    currentDraft = initial!.activeDraft;
    currentSaved = initial!.savedDishes;
    return initial!;
  }

  @override
  Future<void> saveAll(
      {required Dish? activeDraft, required List<Dish> savedDishes}) {
    final write = RecordedWrite(
        activeDraft,
        List<Dish>.unmodifiable(savedDishes),
        _draftGating ? 'draft:BLOCKED' : 'draft:free',
        _savedGating ? 'saved:BLOCKED' : 'saved:free');
    writes.add(write);
    // The repository payload is captured synchronously in the real
    // implementation; the write reaches "disk" only after the release.
    final fut = _tail.then((_) async {
      if (_draftGating) {
        await draftGate!.future;
      }
      if (_savedGating) {
        await savedGate!.future;
      }
      currentDraft = activeDraft;
      currentSaved = List<Dish>.from(savedDishes);
    });
    _tail = fut.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return fut;
  }

  /// Re-read exactly what is on "disk".
  DishStorageData snapshot() =>
      DishStorageData(activeDraft: currentDraft, savedDishes: currentSaved);

  /// Human-readable dump of every payload handed to the repository.
  String describeWrites() =>
      writes.map((w) => w.toString()).join(' -> ');
}

/// Sloppy fake used to prove the state-provider logic does not depend on
/// the exact repository implementation.
class CountingStorage extends DishStorageRepository {
  int saves = 0;
  Dish? lastDraft;
  List<Dish> lastSaved = const [];

  @override
  Future<DishStorageData> loadAll() async => const DishStorageData();

  @override
  Future<void> saveAll(
      {required Dish? activeDraft, required List<Dish> savedDishes}) async {
    saves++;
    lastDraft = activeDraft;
    lastSaved = savedDishes;
  }
}

/// Persistent-directory storage that survives "restarts" (same directory).
DishStorageRepository dirStorage(Directory dir) =>
    DishStorageRepository(storageDirectory: dir);

String jsonDump(Object? o) => const JsonEncoder.withIndent('  ').convert(o);

/// Runs `body` and returns the error (or null) without letting it escape.
Future<Object?> captureError(Future<void> Function() body) async {
  try {
    await body();
    return null;
  } catch (e) {
    return e;
  }
}
