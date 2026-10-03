import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../events/event_bus.dart';
import '../events/preset_events.dart';
import '../module/app_module.dart';
import '../module/module_registry.dart';
import '../storage/storage_module.dart';
import 'preset_schema.dart';

/// Preset manager. Manages the user's active tradition.
///
/// Семантика (D-26, закреплена в пакете 5.0.2):
/// - применение пресета **материализует** его практики в таблицу practices
///   идемпотентно — upsert по паре (traditionTag, presetPracticeId) (B-3);
/// - смена и сброс пресета **никогда не удаляют** данные практик (FR-ONB-4
///   «без потери данных»); изоляция — через traditionTag;
/// - повторное применение того же пресета восстанавливает те же строки
///   с сохранёнными счётчиками;
/// - удаление — только явное действие пользователя (с каскадом истории, B-11).
class PresetManager implements AppModule, ReportsOwnFailures {
  @override
  String get id => 'preset_manager';

  @override
  String get name => 'Менеджер пресетов';

  @override
  String get version => '1.0.0';

  final AppDatabase Function() _databaseGetter;
  final StorageModule _storage;
  PresetSchema? _activePreset;
  final List<ModuleInitFailure> _ownFailures = [];

  @override
  List<ModuleInitFailure> get ownFailures => List.unmodifiable(_ownFailures);

  /// Шина для события [PresetChanged] (D-21/D-36).
  ///
  /// Необязательна: менеджер пресетов работает и без неё (тесты, утилитарные
  /// сценарии), но тогда о смене традиции узнаёт только поток
  /// [activePresetStream] — перепланирование уведомлений его не слушает
  /// (гонка смены пресета), поэтому в приложении шина передаётся
  /// composition root'ом.
  final EventBus? eventBus;

  /// Broadcast-шина изменений активного пресета для UI (реактивность без
  /// EventBus — D-21). Намеренно не закрывается в [dispose]: синглтон-подобные
  /// тестовые пересоздания не должны превращать publish в тишину (урок R-12).
  final StreamController<PresetSchema?> _activePresetController =
      StreamController<PresetSchema?>.broadcast();

  PresetManager(this._databaseGetter, this._storage, {this.eventBus});

  AppDatabase get _database => _databaseGetter();

  @override
  Future<void> init() async {
    _ownFailures.clear();
    // Load active preset from storage
    final activePresetId = _storage.getString('active_preset_id');
    if (activePresetId == null) return;
    try {
      _activePreset = await _loadPresetFromDb(activePresetId);
    } catch (error, stack) {
      // C1(1): «в колонке presets.data лежит JSON, который не проходит текущую
      // схему» — штатное состояние (blob не версионирован: тесты держат там и
      // `data: '{"id":"nyingma"}'`), и лечится оно БЕЗ потери данных. Раньше
      // такой отказ был фатальным, а единственный механизм на экране
      // восстановления — снести файл БД вместе с историей простираний (B-5).
      //
      // Теперь: активная традиция снимается (только ключ в настройках — строки
      // пресета и счётчики не трогаются, D-26), старт продолжается в состоянии
      // «активной традиции нет», и отказ докладывается наверх через
      // [ReportsOwnFailures] — молчать он не вправе (класс R-11/R-13/R-20).
      _ownFailures.add(ModuleInitFailure(
        id,
        error,
        stack,
        kind: FailureKind.activePresetUnreadable,
        subject: activePresetId,
      ));
      _activePreset = null;
      try {
        await _storage.remove('active_preset_id');
      } catch (removeError, removeStack) {
        // Снятие ключа не удалось — при следующем старте отказ повторится;
        // это отдельная строка отчёта, а не тишина.
        _ownFailures.add(ModuleInitFailure(
          id,
          removeError,
          removeStack,
          kind: FailureKind.activePresetUnreadable,
          subject: 'ключ active_preset_id не снят',
        ));
      }
    }
  }

  @override
  Future<void> dispose() async {
    _activePreset = null;
    _ownFailures.clear();
  }

  /// Apply a preset: save to DB, materialize its practices, set as active.
  ///
  /// Идемпотентна: повторный вызов с тем же пресетом не создаёт дублей и
  /// не трогает счётчики (upsert по (traditionTag, presetPracticeId)).
  /// Кастомные практики (presetPracticeId == null) не затрагиваются вовсе.
  ///
  /// W14: три записи — строка пресета (таблица `presets`), материализация
  /// практик и указатель `active_preset_id` — выполняются в ОДНОЙ транзакции
  /// БД. До этого отказ на записи указателя оставлял пресет и практики
  /// закоммиченными: следующий старт видел материализацию пресета, который так
  /// и не стал активным. Теперь отказ любого шага откатывает всё; указатель
  /// (SharedPreferences) не участник SQL-транзакции, но пишется внутри её
  /// границ до COMMIT, поэтому при отказе ключ не остаётся. Единственная
  /// теоретическая точка рассогласования — сбой самого COMMIT: ключ указывает
  /// на отсутствующий пресет, а init деградирует безопасно («активной традиции
  /// нет», данные не теряются).
  ///
  /// Безопасна при конкурентных вызовах (R-22): Drift сериализует транзакции,
  /// поэтому второй параллельный вызов видит строки первого, а не падает
  /// `ConstraintException` по уникальному индексу.
  Future<void> applyPreset(PresetSchema preset) async {
    final db = _database;
    await db.transaction(() async {
      // 1) Строка пресета в таблице presets.
      await db.into(db.presets).insertOnConflictUpdate(
            PresetsCompanion.insert(
              id: preset.id,
              name: preset.name,
              version: preset.version,
              tradition: preset.tradition,
              data: jsonEncode(preset.toJson()),
            ),
          );

      // 2) Материализация практик — вложенной транзакцией (savepoint).
      await _materializePractices(preset);

      // 3) Указатель активного пресета — до COMMIT, чтобы отказ откатил его.
      await _storage.setString('active_preset_id', preset.id);
    });

    _activePreset = preset;
    _activePresetController.add(preset);
    // Событие публикуется ПОСЛЕ commit и ПОСЛЕ присвоения активного пресета:
    // подписчик (перепланировщик, D-36) обязан увидеть уже переключённую
    // традицию, а не «переключение в процессе»; при откате транзакции шина
    // молчит — события нет.
    eventBus?.publish(PresetChanged(traditionTag: preset.id));
  }

  // S10: алиас `switchPreset` снят — он был чистым дублем [applyPreset] без
  // собственной семантики. Смена пресета не удаляет данные старой традиции
  // (D-26): строки остаются под своим traditionTag и переживут возврат.

  /// Reset preset: снять активный пресет. Данные практик НЕ удаляются (D-26);
  /// повторное применение того же пресета восстановит строки со счётчиками.
  Future<void> resetPreset() async {
    await _storage.remove('active_preset_id');
    _activePreset = null;
    _activePresetController.add(null);
    // Пустой тег — «активной традиции нет»: напоминания снимаются.
    eventBus?.publish(PresetChanged(traditionTag: ''));
  }

  /// Get the active preset.
  PresetSchema? get activePreset => _activePreset;

  /// Поток изменений активного пресета: первому слушателю сразу отдаётся
  /// текущее значение, далее — применения/сбросы.
  Stream<PresetSchema?> get activePresetStream async* {
    yield _activePreset;
    yield* _activePresetController.stream;
  }

  /// Материализовать практики пресета идемпотентным upsert'ом.
  ///
  /// Вызывается из [applyPreset] внутри его транзакции; drift 2.x
  /// поддерживает вложенные транзакции (savepoint), поэтому и отдельный
  /// вызов остаётся атомарным.
  ///
  /// R-22: вся последовательность select → insert/update выполняется в одной
  /// транзакции. Без неё два конкурентных [applyPreset] (двойной тап по
  /// карточке пресета) оба не видят незакоммиченную строку: второй insert
  /// падает `ConstraintException` по уникальному индексу
  /// (traditionTag, presetPracticeId), исключение из async `onTap`
  /// проглатывается зоной — падение молчаливое и недетерминированное.
  /// Drift сериализует транзакции, поэтому второй вызов после ожидания
  /// видит результат первого и идёт по ветке update.
  Future<void> _materializePractices(PresetSchema preset) async {
    final db = _database;
    await db.transaction(() async {
      for (var i = 0; i < preset.practices.length; i++) {
        final practice = preset.practices[i];

        final existing = await (db.select(db.practices)
              ..where(
                (t) =>
                    t.traditionTag.equals(preset.id) &
                    t.presetPracticeId.equals(practice.id),
              ))
            .getSingleOrNull();

        // W8: порядок из JSON пишется явным индексом `sort_order`, а не
        // смещением `createdAt` на i секунд. Прежняя подделка даты (i секунд
        // «в будущее») искажала момент создания и не позволяла перестановке
        // практик в пресете дойти до списка: при повторном применении
        // `createdAt` не перезаписывается (D-26), поэтому позиция оставалась
        // старой. `createdAt` теперь — честный момент материализации; точности
        // до секунды (F-33/F-68) для этого достаточно, порядок несёт
        // `sort_order`.
        final now = DateTime.now();

        if (existing == null) {
          await db.into(db.practices).insert(
                PracticesCompanion.insert(
                  presetId: Value(preset.id),
                  presetPracticeId: Value(practice.id),
                  name: practice.name,
                  type: practice.type,
                  target: Value(practice.target),
                  unit: Value(practice.unit),
                  traditionTag: preset.id,
                  sortOrder: Value(i),
                  createdAt: Value(now),
                  updatedAt: Value(now),
                ),
              );
        } else {
          // Обновляем только описательные поля из пресета: currentCount,
          // createdAt и id не трогаем — счёт практикующего священен (D-26).
          // `sortOrder` — часть описания пресета (не пользовательских
          // данных), поэтому он переназначается и при повторном применении:
          // перестановка в JSON обязана менять порядок списка (W8).
          await (db.update(db.practices)
                ..where((t) => t.id.equals(existing.id)))
              .write(
            PracticesCompanion(
              presetId: Value(preset.id),
              name: Value(practice.name),
              type: Value(practice.type),
              target: Value(practice.target),
              unit: Value(practice.unit),
              sortOrder: Value(i),
              updatedAt: Value(now),
            ),
          );
        }
      }
    });
  }

  Future<PresetSchema?> _loadPresetFromDb(String presetId) async {
    final query = _database.select(_database.presets)
      ..where((t) => t.id.equals(presetId));
    final result = await query.getSingleOrNull();
    if (result == null) return null;

    final json = jsonDecode(result.data) as Map<String, dynamic>;
    return PresetSchema.fromJson(json);
  }
}
