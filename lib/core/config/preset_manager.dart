import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../module/app_module.dart';
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
class PresetManager implements AppModule {
  @override
  String get id => 'preset_manager';

  @override
  String get name => 'Менеджер пресетов';

  @override
  String get version => '1.0.0';

  final AppDatabase Function() _databaseGetter;
  final StorageModule _storage;
  PresetSchema? _activePreset;

  /// Broadcast-шина изменений активного пресета для UI (реактивность без
  /// EventBus — D-21). Намеренно не закрывается в [dispose]: синглтон-подобные
  /// тестовые пересоздания не должны превращать publish в тишину (урок R-12).
  final StreamController<PresetSchema?> _activePresetController =
      StreamController<PresetSchema?>.broadcast();

  PresetManager(this._databaseGetter, this._storage);

  AppDatabase get _database => _databaseGetter();

  @override
  Future<void> init() async {
    // Load active preset from storage
    final activePresetId = _storage.getString('active_preset_id');
    if (activePresetId != null) {
      _activePreset = await _loadPresetFromDb(activePresetId);
    }
  }

  @override
  Future<void> dispose() async {
    _activePreset = null;
  }

  /// Apply a preset: save to DB, materialize its practices, set as active.
  ///
  /// Идемпотентна: повторный вызов с тем же пресетом не создаёт дублей и
  /// не трогает счётчики (upsert по (traditionTag, presetPracticeId)).
  /// Кастомные практики (presetPracticeId == null) не затрагиваются вовсе.
  Future<void> applyPreset(PresetSchema preset) async {
    // Save preset to DB (presets table)
    await _database.into(_database.presets).insertOnConflictUpdate(
          PresetsCompanion.insert(
            id: preset.id,
            name: preset.name,
            version: preset.version,
            tradition: preset.tradition,
            data: jsonEncode(preset.toJson()),
          ),
        );

    await _materializePractices(preset);

    // Set as active
    await _storage.setString('active_preset_id', preset.id);
    _activePreset = preset;
    _activePresetController.add(preset);
  }

  /// Switch preset: apply new. Data of the old tradition is NOT deleted (D-26):
  /// строки остаются под своим traditionTag и переживут возврат к пресету.
  Future<void> switchPreset(PresetSchema newPreset) async {
    await applyPreset(newPreset);
  }

  /// Reset preset: снять активный пресет. Данные практик НЕ удаляются (D-26);
  /// повторное применение того же пресета восстановит строки со счётчиками.
  Future<void> resetPreset() async {
    await _storage.remove('active_preset_id');
    _activePreset = null;
    _activePresetController.add(null);
  }

  /// Get the active preset.
  PresetSchema? get activePreset => _activePreset;

  /// Поток изменений активного пресета: первому слушателю сразу отдаётся
  /// текущее значение, далее — применения/сбросы.
  Stream<PresetSchema?> get activePresetStream async* {
    yield _activePreset;
    yield* _activePresetController.stream;
  }

  Future<void> _materializePractices(PresetSchema preset) async {
    final db = _database;
    for (var i = 0; i < preset.practices.length; i++) {
      final practice = preset.practices[i];

      final existing = await (db.select(db.practices)
            ..where(
              (t) =>
                  t.traditionTag.equals(preset.id) &
                  t.presetPracticeId.equals(practice.id),
            ))
          .getSingleOrNull();

      // Смещение на секунду за порядок в пресете: Drift хранит DateTime с
      // точностью до секунды, а список сортируется по createdAt — массовая
      // вставка одним DateTime.now() дала бы недетерминированный порядок
      // (существо B-10). Шаг в миллисекунду молча схлопнулся бы в равенство.
      final now = DateTime.now().add(Duration(seconds: i));

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
                createdAt: Value(now),
                updatedAt: Value(now),
              ),
            );
      } else {
        // Обновляем только описательные поля из пресета: currentCount,
        // createdAt и id не трогаем — счёт практикующего священен (D-26).
        await (db.update(db.practices)
              ..where((t) => t.id.equals(existing.id)))
            .write(
          PracticesCompanion(
            presetId: Value(preset.id),
            name: Value(practice.name),
            type: Value(practice.type),
            target: Value(practice.target),
            unit: Value(practice.unit),
            updatedAt: Value(now),
          ),
        );
      }
    }
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
