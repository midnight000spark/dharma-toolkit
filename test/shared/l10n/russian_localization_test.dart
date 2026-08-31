import 'package:dharma_toolkit/core/config/config_module.dart';
import 'package:dharma_toolkit/core/config/preset_manager.dart';
import 'package:dharma_toolkit/core/db/app_database.dart';
import 'package:dharma_toolkit/core/storage/storage_module.dart';
import 'package:dharma_toolkit/features/tracker/data/practice_repository.dart';
import 'package:dharma_toolkit/features/tracker/presentation/providers/practice_provider.dart';
import 'package:dharma_toolkit/main.dart';
import 'package:dharma_toolkit/shared/providers/app_providers.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// R-15/D-28: русская локаль приложения.
///
/// Тест проверяет ПРОВЕДКУ РЕАЛЬНОГО корня ([DharmaToolkitApp]), а не
/// поддельного MaterialApp: если делегаты/локаль уберут из main.dart, он
/// покраснеет. Ассерты на конкретные русские строки Material
/// ([MaterialLocalizations]) доказывают, что это не просто тег 'ru', а
/// подключённые Global*-локализации (урок 4: поведение, а не отрисовка).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late StorageModule storage;
  late ConfigModule config;
  late PresetManager presetManager;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(
      NativeDatabase.memory(setup: enableForeignKeys),
    );
    storage = StorageModule();
    await storage.init();
    presetManager = PresetManager(() => db, storage);
    await presetManager.init();
    config = ConfigModule();
    await config.init(); // реальные ассеты (F-11)
  });

  tearDown(() async {
    try {
      await db.close();
    } catch (_) {}
  });

  Future<BuildContext> pumpRealApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          configModuleProvider.overrideWithValue(config),
          presetManagerProvider.overrideWithValue(presetManager),
          practiceRepositoryProvider.overrideWithValue(
            PracticeRepository(db),
          ),
        ],
        child: const DharmaToolkitApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    // Без активного пресета редирект на /pick — точка отсчёта живого корня.
    return tester.element(find.text('Выберите традицию'));
  }

  testWidgets('корень приложения работает с локалью ru', (tester) async {
    final context = await pumpRealApp(tester);

    // Фиксированный locale: ru даже при системном английском (проверка ниже
    // опирается на то, что localeOf возвращает ровно ru).
    expect(Localizations.localeOf(context), const Locale('ru'));
  });

  testWidgets('системные строки Material — русские (делегаты подключены)',
      (tester) async {
    final context = await pumpRealApp(tester);
    final material = MaterialLocalizations.of(context);

    // Именно значения из GlobalMaterialLocalizations(ru), а не заглушки:
    // без делегатов здесь были бы английские 'Cancel'/'Copy'/'Paste'
    // (меню выделения — ручной сценарий (в) приёмки).
    expect(material.cancelButtonLabel, 'Отмена');
    expect(material.copyButtonLabel, 'Копировать');
    expect(material.pasteButtonLabel, 'Вставить');
  });
}
