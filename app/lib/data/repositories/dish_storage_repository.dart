import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../core/calculation/models/blank_mode.dart';
import '../../core/calculation/models/dish.dart';
import '../../core/calculation/models/heat_process.dart';
import '../../core/calculation/models/ingredient.dart';
import '../../core/calculation/models/loss_group.dart';
import '../../core/calculation/models/product.dart';
import '../../core/calculation/calculation_validation.dart';

class DishStorageData {
  final Dish? activeDraft;
  final List<Dish> savedDishes;

  const DishStorageData({this.activeDraft, this.savedDishes = const []});
}

/// Кэш отпечатка библиотеки: элементы — по ссылке.
///
/// `Dish` иммутабелен, поэтому «те же самые объекты в том же порядке» и
/// означает «та же библиотека»: пересчитывать CRC незачем.
class _DigestCache {
  _DigestCache(this.snapshot, this.digest);

  final List<Dish> snapshot;
  final int digest;

  bool sameItems(List<Dish> other) {
    if (other.length != snapshot.length) return false;
    for (var i = 0; i < snapshot.length; i++) {
      if (!identical(snapshot[i], other[i])) return false;
    }
    return true;
  }
}

/// Прочитанный документ черновика (`draft.json` или его `.bak`).
class _DraftDocument {
  const _DraftDocument(this.draft, this.generation, this.schemaVersion);

  /// JSON черновика; `null` — повар очистил редактор.
  final Object? draft;

  /// Поколение записи (RA-01); `null` — документ старого формата.
  final int? generation;

  /// Версия схемы данных (`schemaVersion`), если задана явно.
  final int? schemaVersion;
}

class _IngredientExtras {
  final Map<String, dynamic> fields = <String, dynamic>{};
  String? unknownGroup;
  String? unknownProcess;
  int? productId;
  final Map<String, dynamic> productFields = <String, dynamic>{};
  final Map<int, Map<String, dynamic>> measureFields =
      <int, Map<String, dynamic>>{};

  bool get isEmpty =>
      fields.isEmpty &&
      unknownGroup == null &&
      unknownProcess == null &&
      productFields.isEmpty &&
      measureFields.isEmpty;
}

class _DishExtras {
  final Map<String, dynamic> fields = <String, dynamic>{};
  String? unknownProcess;
  String? unknownBlankMode;
  final Map<String, _IngredientExtras> ingredients =
      <String, _IngredientExtras>{};

  bool get isEmpty =>
      fields.isEmpty &&
      unknownProcess == null &&
      unknownBlankMode == null &&
      ingredients.isEmpty;
}

/// Состояние каталога хранения, общее для всех экземпляров репозитория на
/// одном нормализованном пути (RA-14).
class _DirectoryState {
  int? libraryFingerprint;
  int? draftFingerprint;
  int? generation;
  String? libraryStamp;
  bool diskLegacy = false;
  int? newerMainSchemaVersion;
  int? newerDraftSchemaVersion;
  int activeOps = 0;

  final Map<String, dynamic> extraDocumentKeys = <String, dynamic>{};
  final Map<String, _DishExtras> extraSavedDishes = <String, _DishExtras>{};
  final Map<String, _DishExtras> extraDraftDishes = <String, _DishExtras>{};

  void clearExtras() {
    extraDocumentKeys.clear();
    extraSavedDishes.clear();
    extraDraftDishes.clear();
  }
}

class DishStorageRepository {
  static const String _fileName = 'povarspravka_user_dishes.json';

  /// Текущая версия схемы данных рецептур и настроек (1 = без `LossTable`,
  /// 2 = актуальная модель `HeatProcess` / `LossGroup`).
  static const int currentSchemaVersion = 2;

  /// Максимальное число каталогов в общем LRU-кэше процесса (RA-14).
  static const int _maxCachedDirectories = 64;

  static const String _defaultQueueKey = '__default_documents__';

  final Directory? storageDirectory;
  Map<String, dynamic>? _memoryFallback;

  /// Экземплярное состояние для memory-only режима (`file == null`), чтобы
  /// тесты без `path_provider` не загрязняли общий `<default>` ключ (RA-14).
  final _DirectoryState _instanceState = _DirectoryState();

  /// Единый ограниченный LRU-кэш состояния каталогов (RA-14) вместо
  /// разрозненных статических карт: позволяет разным экранам и тестам делить
  /// отпечатки, поколения и неизвестные поля на одном пути без утечки памяти.
  static final Map<String, _DirectoryState> _dirStates =
      <String, _DirectoryState>{};

  /// Очередь записи, общая на КАТАЛОГ, а не на инстанс (IO-05).
  ///
  /// Раньше `_tail` жил в инстансе, и два репозитория на одном каталоге
  /// (домашний экран + экран бланка, либо два `ProviderContainer`) писали в
  /// ОДИН `.tmp`/`.bak.tmp` одновременно: на Windows `rename` падал с
  /// `FileSystemException(32)` и один из документов терялся.
  static final Map<String, Future<void>> _tails = <String, Future<void>>{};

  DishStorageRepository({this.storageDirectory});

  static String _normalizeDirPath(String path) {
    final normalized = p.normalize(path);
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  static _DirectoryState _sharedStateForKey(String key) {
    final existing = _dirStates.remove(key);
    if (existing != null) {
      _dirStates[key] = existing;
      return existing;
    }
    while (_dirStates.length >= _maxCachedDirectories) {
      String? evictKey;
      for (final entry in _dirStates.entries) {
        if (entry.value.activeOps == 0 && !_tails.containsKey(entry.key)) {
          evictKey = entry.key;
          break;
        }
      }
      if (evictKey == null) break;
      _dirStates.remove(evictKey);
    }
    final created = _DirectoryState();
    _dirStates[key] = created;
    return created;
  }

  _DirectoryState _stateForFile(File? file) {
    if (file == null) return _instanceState;
    return _sharedStateForKey(
        _normalizeDirPath(p.dirname(p.absolute(file.path))));
  }

  /// Забыть всё, что процесс знает о каталогах (RA-14).
  ///
  /// Статический кэш нужен приложению: два экрана и два `ProviderContainer`
  /// на одном каталоге обязаны делить одну очередь и одни отпечатки. Тестам
  /// же нужны изоляция и честная имитация «перезапуска приложения», когда о
  /// диске не известно ничего. Вызывать только при пустой очереди записи.
  @visibleForTesting
  static void resetForTesting() {
    _dirStates.clear();
    _tails.clear();
  }

  /// TRUE, если последний [loadAll] восстановил данные из `.bak`.
  ///
  /// IO-03: молчаливый откат на предыдущее поколение — это потеря работы без
  /// предупреждения. Флаг даёт UI возможность честно сказать: «документ был
  /// повреждён, библиотека восстановлена из резервной копии».
  bool didRecoverFromBackup = false;

  /// TRUE, если последний [loadAll] нашёл повреждённый `draft.json` и взял его
  /// резервную копию (`draft.json.bak`).
  bool didRecoverDraftFromBackup = false;

  String? _compatibilityNotice;

  /// Текст уведомления для повара после [loadAll] или `null`, если данные
  /// прочитаны без восстановления. Задача 2026-11-03: «при расхождении —
  /// восстановление с уведомлением».
  String? get recoveryNotice {
    if (didRecoverFromBackup) {
      return 'Файл с блюдами был повреждён — данные восстановлены из '
          'резервной копии. Проверьте последние изменения.';
    }
    if (didRecoverDraftFromBackup) {
      return 'Черновик был повреждён — открыта его резервная копия. '
          'Проверьте последние изменения в редакторе.';
    }
    return null;
  }

  /// Одноразовое неблокирующее предупреждение о совместимости (например, файл
  /// сохранён более новой версией формата `schemaVersion > currentSchemaVersion`).
  /// Не затрагивает [recoveryNotice].
  String? consumeCompatibilityNotice() {
    final notice = _compatibilityNotice;
    _compatibilityNotice = null;
    return notice;
  }

  /// Имя файла библиотеки в каталоге хранения (IO-07).
  String get storageFileName => _fileName;

  /// Небросающий read-only путь к каталогу хранения данных (IO-07).
  ///
  /// Возвращает `null`, если в текущем окружении недоступен плагин каталога
  /// документов (`MissingPluginException` / `UnsupportedError`).
  Future<String?> resolveStorageDirectoryPath() async {
    if (storageDirectory != null) {
      return storageDirectory!.path;
    }
    try {
      final dir = await getApplicationDocumentsDirectory();
      return dir.path;
    } on MissingPluginException {
      // Unsupported plugin hosts may use memory; real I/O failures must surface.
      return null;
    } on UnsupportedError {
      return null;
    }
  }

  String get _queueKey => storageDirectory != null
      ? _normalizeDirPath(p.absolute(storageDirectory!.path))
      : _defaultQueueKey;

  Future<T> _serialized<T>(Future<T> Function() operation) {
    final key = _queueKey;
    final previous = _tails[key] ?? Future<void>.value();
    final result = previous.then((_) => operation());
    // Хвост держит только успех/ошибку, но никогда не «залипает».
    final tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    _tails[key] = tail;
    tail.whenComplete(() {
      if (identical(_tails[key], tail)) _tails.remove(key);
    });
    return result;
  }

  Future<File?> _getStorageFile() async {
    final dirPath = await resolveStorageDirectoryPath();
    if (dirPath == null) return null;
    return File(p.join(dirPath, _fileName));
  }

  DishStorageData _decode(Map<String, dynamic> raw) {
    if (!raw.containsKey('activeDraft') ||
        raw['savedDishes'] is! List ||
        (raw['activeDraft'] != null &&
            raw['activeDraft'] is! Map<String, dynamic>)) {
      throw const FormatException('Invalid dishes document');
    }
    final saved = <Dish>[];
    final dishIds = <String>{};
    for (final item in raw['savedDishes'] as List) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException('Invalid saved dish');
      }
      final decoded = _decodeDish(item);
      if (dishIds.contains(decoded.id)) {
        throw const FormatException('Duplicate dish ID in saved dishes');
      }
      dishIds.add(decoded.id);
      saved.add(decoded);
    }
    return DishStorageData(
      activeDraft: raw['activeDraft'] == null
          ? null
          : _decodeDish(raw['activeDraft'] as Map<String, dynamic>),
      savedDishes: saved,
    );
  }

  Dish _decodeDish(Map<String, dynamic> raw) {
    if (raw['id'] is! String ||
        (raw['id'] as String).isEmpty ||
        raw['ingredients'] is! List) {
      throw const FormatException('Invalid dish structure');
    }
    for (final field in const <String>['createdAt', 'updatedAt']) {
      if (raw.containsKey(field) && raw[field] != null) {
        final ts = raw[field];
        if (ts is! String ||
            ts.trim().isEmpty ||
            DateTime.tryParse(ts) == null) {
          throw FormatException('Invalid dish $field timestamp');
        }
      }
    }
    for (final item in raw['ingredients'] as List) {
      if (item is! Map<String, dynamic> ||
          item['id'] is! String ||
          (item['id'] as String).isEmpty ||
          item['weightGrams'] is! num ||
          !(item['weightGrams'] as num).toDouble().isFinite ||
          (item['weightGrams'] as num).toDouble() < 0 ||
          item['product'] is! Map<String, dynamic>) {
        throw const FormatException('Invalid ingredient structure');
      }
      final product = item['product'] as Map<String, dynamic>;
      final measures = product['measures'];
      if (measures != null &&
          (measures is! List ||
              measures.any((m) => m is! Map<String, dynamic>))) {
        throw const FormatException('Invalid ingredient product measures');
      }
    }
    final dish = Dish.fromJson(raw);
    try {
      CalculationValidation.dish(dish);
    } on ArgumentError {
      throw const FormatException('Invalid calculation values in dish');
    }
    final ids = dish.ingredients.map((i) => i.id).toSet();
    if (ids.contains('') || ids.length != dish.ingredients.length) {
      throw const FormatException('Missing or duplicate ingredient ID');
    }
    return dish;
  }

  /// Проверить и прочитать опциональную `schemaVersion` документа.
  static int? _schemaVersionOf(Map<String, dynamic> raw) {
    if (!raw.containsKey('schemaVersion') || raw['schemaVersion'] == null) {
      return null;
    }
    final value = raw['schemaVersion'];
    if (value is! int || value < 1) {
      throw const FormatException('Invalid schemaVersion');
    }
    return value;
  }

  // CRC-32 detects accidental bit corruption; it is not authentication.
  static int _crc32(List<int> bytes) {
    var crc = 0xffffffff;
    for (final byte in bytes) {
      crc ^= byte;
      for (var bit = 0; bit < 8; bit++) {
        crc = (crc >> 1) ^ ((crc & 1) != 0 ? 0xedb88320 : 0);
      }
    }
    return (crc ^ 0xffffffff) & 0xffffffff;
  }

  String _encode(Map<String, dynamic> raw) {
    final payload = jsonEncode(raw);
    return jsonEncode({
      ...raw,
      'storageVersion': 1,
      'crc32': _crc32(utf8.encode(payload)),
    });
  }

  /// Номер поколения документа (RA-01); `null` — документ старого формата.
  static int? _generationOf(Map<String, dynamic> raw) {
    final value = raw['generation'];
    return value is int && value >= 0 ? value : null;
  }

  Future<Map<String, dynamic>?> _readValid(
    File file, {
    _DirectoryState? state,
    bool trackLegacy = false,
  }) async {
    try {
      // Decode explicitly: readAsString wraps malformed UTF-8 in an I/O error,
      // which must not be confused with an actual permission/disk failure.
      final text = utf8.decode(await file.readAsBytes());
      var raw = jsonDecode(text);
      if (raw is! Map<String, dynamic>) return null;
      final hasVersion = raw.containsKey('storageVersion');
      final hasCrc = raw.containsKey('crc32');
      if (hasVersion || hasCrc) {
        // IO-02 (D-IO01): документ, у которого ЕСТЬ один из служебных ключей,
        // но нет другого, — это не «старый формат», а подделка или порча.
        // Раньше удаление `crc32` переводило файл в legacy-ветку и он
        // принимался без проверки: злоумышленник мог подменить библиотеку.
        // Legacy — это документ БЕЗ ОБОИХ ключей.
        if (!hasVersion || !hasCrc) return null;
        final version = raw.remove('storageVersion');
        final checksum = raw.remove('crc32');
        if (version != 1) return null;
        // CRC по канонической сериализации уже доказывает целостность и то,
        // что документ записан этой версией приложения: любое изменение байтов
        // (порядок ключей, пробелы, значения) меняет сумму. Повторная сверка
        // всей строки была избыточной и удваивала стоимость чтения — на 512
        // восстановлениях это выходило за бюджет производительности.
        final payload = jsonEncode(raw);
        if (checksum != _crc32(utf8.encode(payload))) return null;
      }
      _schemaVersionOf(raw);
      // Legacy documents remain readable; new writes and recovered files carry CRC.
      _decode(raw); // Validate the complete payload, not just its JSON syntax.
      if (trackLegacy && !hasVersion && !hasCrc) {
        // Документ без служебных ключей — старый формат: читаем, но обязаны
        // переписать его при первом сохранении.
        state?.diskLegacy = true;
      }
      return raw;
    } on PathNotFoundException {
      // Only a genuinely absent path is an empty/missing document.
      // exists() also returns false for wrong types and some inaccessible paths.
      return null;
    } on JsonUnsupportedObjectError {
      // Valid JSON grammar may overflow a Dart double (e.g. 1e309).
      // Such data cannot be canonicalized for CRC and must use the backup.
      return null;
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  static Map<String, dynamic> _extraTopLevel(Map<String, dynamic> raw) {
    const known = {
      'activeDraft',
      'savedDishes',
      'schemaVersion',
      'generation',
      'storageVersion',
      'crc32',
    };
    return {
      for (final e in raw.entries)
        if (!known.contains(e.key)) e.key: e.value,
    };
  }

  Future<DishStorageData> loadAll() => _serialized(() async {
        didRecoverFromBackup = false;
        didRecoverDraftFromBackup = false;
        _compatibilityNotice = null;
        final file = await _getStorageFile();
        if (file == null) {
          return _memoryFallback == null
              ? const DishStorageData()
              : _decode(_memoryFallback!);
        }
        final state = _stateForFile(file);
        state.activeOps++;
        try {
          state.diskLegacy = false;
          var raw = await _readValid(file, state: state, trackLegacy: true);
          var mainMatchesMemory = true;
          if (raw == null) {
            final backup = File('${file.path}.bak');
            raw = await _readValid(backup);
            if (raw != null) {
              didRecoverFromBackup = true;
              // IO-03 (D-IO03 probe2): восстановление из `.bak` — это ПЕРВИЧНАЯ
              // задача, а перезапись повреждённого main — вспомогательная.
              // Раньше отказ rename (read-only файл, чужой антивирус, права)
              // выбрасывал уже прочитанные целые данные, и пользователь видел
              // «библиотека потеряна» при полностью сохранённой резервной копии.
              try {
                final temp = File('${file.path}.tmp');
                await temp.writeAsString(_encode(raw), flush: true);
                // Never replace the good backup with the damaged main document.
                await _renameWithRetry(temp, file.path);
              } catch (_) {
                // Best effort: данные всё равно возвращаются из памяти. На диске
                // остался повреждённый main, поэтому следующее сохранение обязано
                // переписать его, а не пойти быстрым путём.
                mainMatchesMemory = false;
              }
            } else if (await file.exists() || await backup.exists()) {
              throw const FormatException(
                  'Main dishes document and backup are invalid');
            }
          }
          if (raw == null) {
            state.clearExtras();
            state.newerMainSchemaVersion = null;
            state.newerDraftSchemaVersion = null;
            return const DishStorageData();
          }
          final librarySchema = _schemaVersionOf(raw);
          // FUZZ-13: черновик живёт в отдельном документе. Если он есть, валиден
          // и записан не раньше документа библиотеки (RA-01), он свежее её
          // `activeDraft` (снимка момента последнего сохранения библиотеки).
          // Порча `draft.json` не должна утягивать библиотеку: тогда берётся его
          // резервная копия, а без неё — снимок черновика из библиотеки.
          final libraryGeneration = _generationOf(raw);
          var newestGeneration = libraryGeneration ?? 0;
          int? draftSchema;
          var draftWon = false;
          final draftFile = File('${file.path}.draft.json');
          // Черновик читается отдельным валидатором: в его документе нет
          // `savedDishes`, и общий `_readValid` счёл бы файл повреждённым.
          //
          // Быстрый случай (черновика нет вовсе) стоит ровно один `exists()`:
          // именно он и происходит в подавляющем большинстве загрузок.
          final draftBackup = File('${draftFile.path}.bak');
          final hasDraftFile = await draftFile.exists();
          if (hasDraftFile || await draftBackup.exists()) {
            // `draft.json` существует → он и есть текущий черновик (в том числе
            // `null`: повар очистил редактор). Повреждённый документ черновика не
            // должен утягивать библиотеку — тогда берём его резервную копию.
            final primary =
                hasDraftFile ? await _readDraftDocument(draftFile) : null;
            final document = primary ?? await _readDraftDocument(draftBackup);
            // Задача 2026-11-03: повреждённый `draft.json` заменён резервной
            // копией — не молча, а с уведомлением (см. [recoveryNotice]).
            if (hasDraftFile && primary == null && document != null) {
              didRecoverDraftFromBackup = true;
            }
            if (document != null) {
              final generation = document.generation;
              if (generation != null && generation > newestGeneration) {
                newestGeneration = generation;
              }
              // Документ без номера поколения — старого формата: для него
              // действует прежнее правило «`draft.json` главнее библиотеки».
              // RA-01: если библиотека записана ПОЗЖЕ черновика (после правки в
              // редакторе сохранили блюдо или изменили список), её снимок
              // черновика и есть последнее состояние редактора: устаревший
              // `draft.json` его больше не перекрывает.
              if (generation == null ||
                  generation >= (libraryGeneration ?? 0)) {
                raw['activeDraft'] = document.draft;
                _decode(raw); // итоговый документ обязан проходить валидацию
                draftWon = true;
                draftSchema = document.schemaVersion;
              }
            }
          }
          _rememberUnknownKeys(
            state,
            raw,
            librarySchema: librarySchema,
            draftSchema: draftWon ? draftSchema : librarySchema,
          );
          state.newerMainSchemaVersion =
              (librarySchema != null && librarySchema > currentSchemaVersion)
                  ? librarySchema
                  : null;
          state.newerDraftSchemaVersion = (draftWon &&
                  draftSchema != null &&
                  draftSchema > currentSchemaVersion)
              ? draftSchema
              : null;
          final newerMain = state.newerMainSchemaVersion;
          final newerDraft = state.newerDraftSchemaVersion;
          if (newerMain != null || newerDraft != null) {
            final newest = (newerMain ?? 0) >= (newerDraft ?? 0)
                ? newerMain!
                : newerDraft!;
            _compatibilityNotice =
                'Данные созданы более новой версией приложения (схема v$newest, '
                'текущая — v$currentSchemaVersion). Неизвестные параметры '
                'сохраняются по возможности; перед перезаписью создаётся '
                'резервная копия.';
          }
          _memoryFallback = raw;
          final decoded = _decode(raw);
          state.libraryFingerprint = _libraryDigestOf(decoded.savedDishes);
          state.draftFingerprint = _draftKeyOf(raw['activeDraft']);
          state.generation = newestGeneration;
          state.libraryStamp = mainMatchesMemory ? await _stampOf(file) : null;
          return decoded;
        } finally {
          state.activeOps--;
        }
      });

  /// Прочитать документ ЧЕРНОВИКА.
  ///
  /// Документ черновика содержит только `activeDraft` (и номер поколения),
  /// поэтому общий [_readValid] (он требует `savedDishes` и валидирует целую
  /// библиотеку) для него не годится. Проверка целостности — та же: формат,
  /// версия, CRC. `null` — документа нет или он повреждён; черновик `null`
  /// («редактор очищен») возвращается как валидный документ.
  Future<_DraftDocument?> _readDraftDocument(File file) async {
    try {
      final text = utf8.decode(await file.readAsBytes());
      final raw = jsonDecode(text);
      if (raw is! Map<String, dynamic>) return null;
      final hasVersion = raw.containsKey('storageVersion');
      final hasCrc = raw.containsKey('crc32');
      if (hasVersion || hasCrc) {
        if (!hasVersion || !hasCrc) return null;
        final version = raw.remove('storageVersion');
        final checksum = raw.remove('crc32');
        if (version != 1) return null;
        if (checksum != _crc32(utf8.encode(jsonEncode(raw)))) return null;
      }
      if (!raw.containsKey('activeDraft')) return null;
      final draftSchema = _schemaVersionOf(raw);
      final draft = raw['activeDraft'];
      if (draft != null) {
        if (draft is! Map<String, dynamic>) return null;
        _decodeDish(draft); // черновик обязан быть корректной рецептурой
      }
      return _DraftDocument(draft, _generationOf(raw), draftSchema);
    } on PathNotFoundException {
      return null;
    } on JsonUnsupportedObjectError {
      return null;
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  static final _exemplarProduct = const Product(
    id: 0,
    code: '',
    name: '',
    groupId: 0,
    source: 'skurikhin',
    protein: 0,
    fat: 0,
    carbs: 0,
    kcal: 0,
    isDish: true,
  );

  static final Set<String> _knownDishKeys = <String>{
    ...Dish(
      id: '_',
      createdAt: DateTime.utc(2000),
      updatedAt: DateTime.utc(2000),
    ).toJson().keys,
    ...Dish(
      id: '_',
      process: HeatProcess.cold,
      createdAt: DateTime.utc(2000),
      updatedAt: DateTime.utc(2000),
    ).toJson().keys,
  };

  static final Set<String> _knownIngredientKeys = <String>{
    ...Ingredient(id: '_', product: _exemplarProduct, weightGrams: 1)
        .toJson()
        .keys,
    ...Ingredient(
      id: '_',
      product: _exemplarProduct,
      weightGrams: 1,
      groupOverride: LossGroup.meat,
      processOverride: HeatProcess.boil,
    ).toJson().keys,
  };

  static final Set<String> _knownProductKeys =
      _exemplarProduct.toJson().keys.toSet();

  static final Set<String> _knownMeasureKeys = const ProductMeasure(
    id: 0,
    productId: 0,
    name: '',
    grams: 1,
  ).toJson().keys.toSet();

  static final Set<String> _knownBlankModeNames = {
    for (final m in BlankMode.values) m.name,
  };

  static _DishExtras? _collectDishExtras(
    Map<String, dynamic> dishJson,
    int? schemaVersion,
  ) {
    final preserveUnknownEnums =
        schemaVersion != null && schemaVersion >= currentSchemaVersion;
    final extras = _DishExtras();
    for (final e in dishJson.entries) {
      if (!_knownDishKeys.contains(e.key)) extras.fields[e.key] = e.value;
    }
    if (preserveUnknownEnums) {
      final rawProcess = dishJson['process'];
      if (rawProcess is String &&
          rawProcess != HeatProcess.legacy.name &&
          HeatProcess.fromJsonName(rawProcess) == HeatProcess.legacy) {
        extras.unknownProcess = rawProcess;
      }
      final rawMode = dishJson['blankMode'];
      if (rawMode is String && !_knownBlankModeNames.contains(rawMode)) {
        extras.unknownBlankMode = rawMode;
      }
    }
    final rawIngredients = dishJson['ingredients'];
    if (rawIngredients is List) {
      for (final rawIng in rawIngredients) {
        if (rawIng is! Map<String, dynamic>) continue;
        final ingId = rawIng['id'];
        if (ingId is! String) continue;
        final ingExtras = _IngredientExtras();
        for (final e in rawIng.entries) {
          if (!_knownIngredientKeys.contains(e.key)) {
            ingExtras.fields[e.key] = e.value;
          }
        }
        if (preserveUnknownEnums) {
          final rawGroup = rawIng['group'];
          if (rawGroup is String && LossGroup.fromJsonName(rawGroup) == null) {
            ingExtras.unknownGroup = rawGroup;
          }
          final rawIngProcess = rawIng['process'];
          if (rawIngProcess is String &&
              rawIngProcess != HeatProcess.legacy.name &&
              HeatProcess.ingredientFromJsonName(rawIngProcess) == null) {
            ingExtras.unknownProcess = rawIngProcess;
          }
        }
        final prodJson = rawIng['product'];
        if (prodJson is Map<String, dynamic>) {
          ingExtras.productId = prodJson['id'] is int ? prodJson['id'] as int : 0;
          for (final e in prodJson.entries) {
            if (!_knownProductKeys.contains(e.key)) {
              ingExtras.productFields[e.key] = e.value;
            }
          }
          final measuresJson = prodJson['measures'];
          if (measuresJson is List) {
            for (final rawMeasure in measuresJson) {
              if (rawMeasure is! Map<String, dynamic>) continue;
              final mId = rawMeasure['id'];
              if (mId is! int) continue;
              Map<String, dynamic>? mExtras;
              for (final e in rawMeasure.entries) {
                if (!_knownMeasureKeys.contains(e.key)) {
                  (mExtras ??= <String, dynamic>{})[e.key] = e.value;
                }
              }
              if (mExtras != null) ingExtras.measureFields[mId] = mExtras;
            }
          }
        }
        if (!ingExtras.isEmpty) extras.ingredients[ingId] = ingExtras;
      }
    }
    return extras.isEmpty ? null : extras;
  }

  /// Запомнить незнакомые поля документа (включая `ingredients`, `product`,
  /// `measures` и неизвестные enum-значения новых схем), чтобы вернуть их
  /// при сохранении (IO-08 / A3-COMPAT-01).
  void _rememberUnknownKeys(
    _DirectoryState state,
    Map<String, dynamic> raw, {
    required int? librarySchema,
    required int? draftSchema,
  }) {
    state.clearExtras();
    state.extraDocumentKeys.addAll(_extraTopLevel(raw));

    final draft = raw['activeDraft'];
    if (draft is Map<String, dynamic>) {
      final id = draft['id'];
      if (id is String) {
        final collected = _collectDishExtras(draft, draftSchema);
        if (collected != null) state.extraDraftDishes[id] = collected;
      }
    }
    final saved = raw['savedDishes'];
    if (saved is List) {
      for (final item in saved) {
        if (item is! Map<String, dynamic>) continue;
        final id = item['id'];
        if (id is! String) continue;
        final collected = _collectDishExtras(item, librarySchema);
        if (collected != null) state.extraSavedDishes[id] = collected;
      }
    }
  }

  /// Дополнить JSON рецептуры неизвестными полями (и нераспознанными enum из
  /// более новой схемы), если пользователь их не перезаписал.
  Map<String, dynamic> _withExtras(
    Dish dish,
    _DirectoryState state, {
    Map<String, dynamic>? baseJson,
    required bool fromDraft,
  }) {
    final json = baseJson ?? dish.toJson();
    final extra = fromDraft
        ? (state.extraDraftDishes[dish.id] ?? state.extraSavedDishes[dish.id])
        : (state.extraSavedDishes[dish.id] ?? state.extraDraftDishes[dish.id]);
    if (extra == null) return json;
    for (final e in extra.fields.entries) {
      if (!json.containsKey(e.key)) json[e.key] = e.value;
    }
    if (extra.unknownProcess != null &&
        dish.process == HeatProcess.legacy &&
        !json.containsKey('process')) {
      json['process'] = extra.unknownProcess!;
    }
    if (extra.unknownBlankMode != null &&
        dish.blankMode == BlankMode.photoCross) {
      json['blankMode'] = extra.unknownBlankMode!;
    }
    if (extra.ingredients.isNotEmpty) {
      final rawIngredients = json['ingredients'] as List<dynamic>;
      for (var k = 0; k < dish.ingredients.length; k++) {
        final ing = dish.ingredients[k];
        final ingExtra = extra.ingredients[ing.id];
        if (ingExtra == null) continue;
        final ingJson = rawIngredients[k] as Map<String, dynamic>;
        for (final e in ingExtra.fields.entries) {
          if (!ingJson.containsKey(e.key)) ingJson[e.key] = e.value;
        }
        if (ingExtra.unknownGroup != null &&
            ing.groupOverride == null &&
            !ingJson.containsKey('group')) {
          ingJson['group'] = ingExtra.unknownGroup!;
        }
        if (ingExtra.unknownProcess != null &&
            ing.processOverride == null &&
            !ingJson.containsKey('process')) {
          ingJson['process'] = ingExtra.unknownProcess!;
        }
        if (ingExtra.productId == ing.product.id) {
          final prodJson = ingJson['product'] as Map<String, dynamic>;
          for (final e in ingExtra.productFields.entries) {
            if (!prodJson.containsKey(e.key)) prodJson[e.key] = e.value;
          }
          if (ingExtra.measureFields.isNotEmpty) {
            final measuresJson = prodJson['measures'] as List<dynamic>;
            for (var j = 0; j < ing.product.measures.length; j++) {
              final mExtra = ingExtra.measureFields[ing.product.measures[j].id];
              if (mExtra == null) continue;
              final mJson = measuresJson[j] as Map<String, dynamic>;
              for (final e in mExtra.entries) {
                if (!mJson.containsKey(e.key)) mJson[e.key] = e.value;
              }
            }
          }
        }
      }
    }
    return json;
  }


  /// Отпечаток списка блюд по идентичности и содержимому.
  ///
  /// Считается по `toJson()`-независимым полям, но отражает КАЖДОЕ
  /// сохранённое изменение: заголовок, состав, выход, сохранность, режим
  /// бланка и технологию. Дешёвая пара `id@updatedAt` здесь не годится:
  /// откат блюда к прежней версии (или правка без смены `updatedAt`) давал бы
  /// ложное «не изменилось», и запись молча терялась бы.
  int _libraryDigestOf(List<Dish> dishes) {
    // `Dish` иммутабелен, а библиотека передаётся как есть: если элементы —
    // ТЕ ЖЕ объекты в том же порядке, отпечаток уже известен. Без этого кэша
    // автосохранение черновика стоило O(библиотеки) ещё до сравнения с
    // диском — ровно то, что устраняет FUZZ-13.
    final cached = _digestCache;
    if (cached != null && cached.sameItems(dishes)) return cached.digest;
    final digest = _computeLibraryDigest(dishes);
    _digestCache = _DigestCache(List<Dish>.of(dishes), digest);
    return digest;
  }

  _DigestCache? _digestCache;

  int _computeLibraryDigest(List<Dish> dishes) {
    final buffer = StringBuffer('${dishes.length}');
    for (final d in dishes) {
      buffer
        ..write('|')
        ..write(d.id)
        ..write('\u0001')
        ..write(d.title)
        ..write('\u0001')
        ..write(d.updatedAt.microsecondsSinceEpoch)
        ..write('\u0001')
        ..write(d.customYieldGrams)
        ..write('\u0001')
        ..write('${d.retentionProtein}/${d.retentionFat}/${d.retentionCarbs}')
        ..write('\u0001')
        ..write(d.blankMode.name)
        ..write('\u0001')
        ..write(d.process.name)
        ..write('\u0001')
        ..write(d.showTitleInExport)
        ..write(d.showPer100gRowInExport)
        ..write('\u0001');
      for (final i in d.ingredients) {
        buffer
          ..write(i.id)
          ..write(':')
          ..write(i.weightGrams)
          ..write(':')
          ..write(i.isGross)
          ..write(':')
          ..write(i.product.name)
          ..write(':')
          ..write('${i.product.protein}/${i.product.fat}/'
              '${i.product.carbs}/${i.product.wastePct}')
          // Ручные группа/способ потерь — тоже сохраняемое изменение:
          // без них правка потерь считалась бы «не изменилось».
          ..write(':')
          ..write(i.groupOverride?.name)
          ..write(':')
          ..write(i.processOverride?.name)
          ..write(',');
      }
    }
    return _crc32(utf8.encode(buffer.toString()));
  }

  /// Отпечаток черновика по его сериализованному виду.
  ///
  /// Считается по снимку (а не по живому `Dish`), потому что именно снимок
  /// уходит на диск: отпечаток обязан описывать то же состояние.
  int? _draftKeyOf(Object? draftJson) => draftJson == null
      ? null
      : _crc32(utf8.encode(jsonEncode(draftJson)));

  /// Следующий номер поколения (RA-01). Номер «занимается» до записи: если
  /// запись не удалась, в последовательности просто остаётся пропуск.
  int _nextGeneration(_DirectoryState state) {
    final next = (state.generation ?? 0) + 1;
    state.generation = next;
    return next;
  }

  /// Наибольшее поколение документов на диске — для сохранения, которому не
  /// предшествовала загрузка этого каталога в текущем процессе. Без этого
  /// новая запись могла бы получить номер МЕНЬШЕ, чем у лежащего на диске
  /// `draft.json`, и он перекрыл бы её при следующей загрузке.
  Future<int> _newestGenerationOnDisk(File libraryFile) async {
    var newest = 0;
    for (final path in <String>[
      libraryFile.path,
      '${libraryFile.path}.bak',
      '${libraryFile.path}.draft.json',
      '${libraryFile.path}.draft.json.bak',
    ]) {
      try {
        final raw = jsonDecode(utf8.decode(await File(path).readAsBytes()));
        if (raw is Map<String, dynamic>) {
          final generation = _generationOf(raw);
          if (generation != null && generation > newest) newest = generation;
        }
      } on PathNotFoundException {
        // Нет документа — нет и поколения.
      } on FormatException {
        // Повреждённый документ поколения не задаёт.
      }
    }
    return newest;
  }

  /// Отпечаток файла библиотеки на диске: размер и последние 48 байт (RA-14).
  ///
  /// Документ всегда кончается полем `"crc32":…}` — контрольной суммой ВСЕГО
  /// содержимого, поэтому хвоста достаточно, чтобы отличить одно состояние
  /// файла от другого, не читая его целиком (быстрый путь FUZZ-13 остаётся
  /// O(1) по размеру библиотеки). Время изменения для этого не годится: на
  /// Windows `FileStat.modified` имеет разрешение в одну секунду.
  /// `null` — файла нет или его нельзя прочитать: тогда доверять памяти нельзя.
  static Future<String?> _stampOf(File file) async {
    try {
      final handle = await file.open();
      try {
        final length = await handle.length();
        final start = length > 48 ? length - 48 : 0;
        await handle.setPosition(start);
        final tail = await handle.read(length - start);
        return '$length:${base64.encode(tail)}';
      } finally {
        await handle.close();
      }
    } on FileSystemException {
      return null;
    }
  }

  /// Временная блокировка цели `rename` на Windows (RA-IO-01): открытый
  /// чужой хэндл (антивирус, индексатор, резервное копирование, второе окно
  /// приложения) не даёт заменить файл. `MoveFileEx` отвечает
  /// ERROR_ACCESS_DENIED (5), ERROR_SHARING_VIOLATION (32) или
  /// ERROR_LOCK_VIOLATION (33), Dart поднимает [PathAccessException].
  static bool _isTransientLock(FileSystemException error) {
    if (!Platform.isWindows || error is! PathAccessException) return false;
    final code = error.osError?.errorCode;
    return code == 5 || code == 32 || code == 33;
  }

  /// Суммарное время повторов одной замены файла.
  static const Duration _renameRetryBudget = Duration(milliseconds: 2500);

  /// `rename` с повторами при временной блокировке цели (A3-IO-01).
  ///
  /// Сначала выполняются короткие уступки цикла событий (`Duration.zero`),
  /// разрывающие синхронизацию с конкурирующим читателем на ~15.6 мс тике
  /// таймера Windows: читатель завершает чтение и уходит в ожидание, пока
  /// `rename` проходит в межтиковом окне. Если блокировка длительнее —
  /// короткий нечётный backoff с низким потолком (1..13 мс) в пределах
  /// [_renameRetryBudget].
  static Future<File> _renameWithRetry(File source, String target) async {
    final clock = Stopwatch()..start();
    var pauseMs = 1;
    var immediateYields = 4;
    while (true) {
      try {
        return await source.rename(target);
      } on FileSystemException catch (error) {
        if (!_isTransientLock(error) || clock.elapsed >= _renameRetryBudget) {
          rethrow;
        }
      }
      if (immediateYields > 0) {
        immediateYields--;
        await Future<void>.delayed(Duration.zero);
        continue;
      }
      await Future<void>.delayed(Duration(milliseconds: pauseMs));
      pauseMs = pauseMs >= 13 ? 13 : (pauseMs * 2 - (pauseMs > 2 ? 1 : 0));
      immediateYields = 2;
    }
  }

  /// Однократная резервная копия `.v<N>.bak` перед перезаписью документа с
  /// более новой версией схемы (`schemaVersion > currentSchemaVersion`).
  Future<void> _writePreDowngradeBackupIfNeeded(
    File targetFile,
    File sourceFile,
    int? schemaVersion,
  ) async {
    if (schemaVersion == null || schemaVersion <= currentSchemaVersion) return;
    final versionedBackup = File('${targetFile.path}.v$schemaVersion.bak');
    if (await versionedBackup.exists() || !await sourceFile.exists()) return;
    final backupTemp = File('${versionedBackup.path}.tmp');
    await backupTemp.writeAsBytes(await sourceFile.readAsBytes(), flush: true);
    await _renameWithRetry(backupTemp, versionedBackup.path);
  }

  /// Сохранить черновик, не переписывая библиотеку.
  ///
  /// [payloadDraft] — уже сериализованный черновик (с неизвестными полями),
  /// [generation] — номер поколения записи (RA-01).
  Future<void> _writeDraft(
    File libraryFile,
    Object? payloadDraft,
    int generation,
    _DirectoryState state,
  ) async {
    final draftFile = File('${libraryFile.path}.draft.json');
    final draftTemp = File('${draftFile.path}.tmp');
    await draftTemp.writeAsString(
        _encode(<String, dynamic>{
          'activeDraft': payloadDraft,
          'schemaVersion': currentSchemaVersion,
          'generation': generation,
        }),
        flush: true);
    if (await draftFile.exists()) {
      final newerDraftVersion = state.newerDraftSchemaVersion;
      if (newerDraftVersion != null) {
        final draftBackupFile = File('${draftFile.path}.bak');
        final existingDraft = await _readDraftDocument(draftFile);
        final source = existingDraft != null || !await draftBackupFile.exists()
            ? draftFile
            : draftBackupFile;
        await _writePreDowngradeBackupIfNeeded(
            draftFile, source, newerDraftVersion);
        state.newerDraftSchemaVersion = null;
      }
      // Черновик тоже переживает сбой записи: `.bak` хранит предыдущее
      // состояние редактора, а не теряет всё при порче нового.
      final backupTemp = File('${draftFile.path}.bak.tmp');
      await backupTemp.writeAsBytes(await draftFile.readAsBytes(), flush: true);
      await _renameWithRetry(backupTemp, '${draftFile.path}.bak');
    }
    await _renameWithRetry(draftTemp, draftFile.path);
  }

  Future<void> saveAll({
    required Dish? activeDraft,
    required List<Dish> savedDishes,
  }) {
    // FUZZ-13: автосохранение черновика не должно стоить O(библиотеки).
    //
    // Раньше каждое нажатие клавиши в редакторе заново сериализовало,
    // валидировало, кодировало, писало и перечитывало (ради `.bak`) ВСЮ
    // библиотеку: на 200 блюдах это 0,8–1,6 с на одно нажатие. Теперь
    // библиотека и черновик — разные документы: пока список сохранённых блюд
    // не изменился, пишем только `draft.json`.
    //
    // Снимок берётся СИНХРОННО, до постановки в очередь (IO-6/P1, P2, P5):
    // и список, и базовый JSON черновика фиксируются в момент вызова. Иначе
    // правка, сделанная пока запись ждёт очереди, могла бы попасть в уже
    // посчитанный отпечаток и потеряться.
    final librarySnapshot = List<Dish>.of(savedDishes, growable: false);
    final draftSnapshot = activeDraft;
    final baseDraftJson = draftSnapshot?.toJson();
    final libraryDigest = _libraryDigestOf(librarySnapshot);

    return _serialized(() async {
      final file = await _getStorageFile();
      final state = _stateForFile(file);
      state.activeOps++;
      try {
        final draftJson = draftSnapshot == null
            ? null
            : _withExtras(
                draftSnapshot,
                state,
                baseJson: baseDraftJson,
                fromDraft: true,
              );
        final draftDigest = _draftKeyOf(draftJson);

        Map<String, dynamic> buildPayload(int? generation) {
          final payload = <String, dynamic>{
            'activeDraft': draftJson,
            'savedDishes': librarySnapshot
                .map((d) => _withExtras(d, state, fromDraft: false))
                .toList(),
            'schemaVersion': currentSchemaVersion,
            if (generation != null) 'generation': generation,
          };
          // IO-08: вернуть неизвестные ключи верхнего уровня, чтобы откат на
          // старую версию не стирал данные более новой. Пишем их последними,
          // сохраняя канонический порядок известных ключей.
          for (final e in state.extraDocumentKeys.entries) {
            if (!payload.containsKey(e.key)) payload[e.key] = e.value;
          }
          _decode(payload);
          return payload;
        }

        // RA-14: «библиотека та же» проверяется не только по памяти, но и по
        // диску — если файл переписан извне (второе окно, синхронизация,
        // ручное восстановление), сохранение обязано записать документ заново.
        final knownStamp = state.libraryStamp;
        if (file != null &&
            state.libraryFingerprint == libraryDigest &&
            !state.diskLegacy &&
            state.generation != null &&
            knownStamp != null &&
            await _stampOf(file) == knownStamp) {
          // Библиотека на диске та же: её документ (и `.bak`) не трогаем.
          // Черновик пишем, только если он действительно изменился — иначе
          // нажатие, не изменившее ввод, не должно трогать диск вовсе.
          if (state.draftFingerprint != draftDigest) {
            await file.parent.create(recursive: true);
            await _writeDraft(file, draftJson, _nextGeneration(state), state);
            state.draftFingerprint = draftDigest;
          }
          // Копия в памяти нужна только для «нет каталога документов»; на
          // быстром пути достаточно обновить в ней один черновик, не собирая
          // документ библиотеки заново.
          final fallback = _memoryFallback;
          if (fallback != null) fallback['activeDraft'] = draftJson;
          return;
        }

        if (file == null) {
          _memoryFallback = buildPayload(null);
          state.libraryFingerprint = libraryDigest;
          state.draftFingerprint = draftDigest;
          return;
        }

        // Медленный путь: библиотека изменилась — документ собирается целиком,
        // и только здесь (не на быстром пути) платится его цена.
        await file.parent.create(recursive: true);
        state.generation ??= await _newestGenerationOnDisk(file);
        final generation = _nextGeneration(state);
        final payload = buildPayload(generation);
        final encoded = _encode(payload);

        final temp = File('${file.path}.tmp');
        await temp.writeAsString(encoded, flush: true);
        final previous = await _readValid(file);
        final prevSchema = previous != null ? _schemaVersionOf(previous) : null;
        final newerVer =
            (prevSchema != null && prevSchema > currentSchemaVersion)
                ? prevSchema
                : state.newerMainSchemaVersion;
        if (newerVer != null) {
          final backupFile = File('${file.path}.bak');
          final source =
              previous != null || !await backupFile.exists() ? file : backupFile;
          await _writePreDowngradeBackupIfNeeded(file, source, newerVer);
          state.newerMainSchemaVersion = null;
        }
        if (previous != null) {
          final backupTemp = File('${file.path}.bak.tmp');
          await backupTemp.writeAsBytes(await file.readAsBytes(), flush: true);
          await _renameWithRetry(backupTemp, '${file.path}.bak');
        } else if (!await File('${file.path}.bak').exists()) {
          // IO-02 (D-IO02): первое сохранение раньше оставляло ровно одну копию
          // на диске, и сбой при следующей записи уничтожал рецепт безвозвратно.
          // Журнальная копия того, что мы собираемся записать, даёт ту же
          // защиту, что и `.bak` для последующих поколений.
          final journalTemp = File('${file.path}.bak.tmp');
          await journalTemp.writeAsString(encoded, flush: true);
          await _renameWithRetry(journalTemp, '${file.path}.bak');
        }
        // Same-directory rename replaces the destination; no delete/write gap.
        // ТОЧКА ФИКСАЦИИ (RA-01): с этого момента библиотека и черновик этого
        // сохранения лежат на диске одним документом.
        await _renameWithRetry(temp, file.path);
        // Документ на диске теперь в текущем формате: миграция выполнена.
        state.diskLegacy = false;
        state.libraryFingerprint = libraryDigest;
        state.draftFingerprint = draftDigest;
        _memoryFallback = payload;
        state.libraryStamp = await _stampOf(file);
        // `draft.json` здесь НЕ переписывается: черновик этого сохранения уже
        // лежит в документе библиотеки, а оставшийся на диске `draft.json`
        // записан РАНЬШЕ (номер поколения меньше) и при загрузке уже не
        // победит (RA-01). Одно сохранение — одна замена файла: нет окна, в
        // котором сбой оставил бы два файла схемы в рассогласованном виде.
      } finally {
        state.activeOps--;
      }
    });
  }
}
