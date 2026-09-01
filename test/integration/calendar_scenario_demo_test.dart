/// Демонстрируемый сценарий календаря на уровне данных (5b.6, SCR-11, урок 2).
///
/// Прогон через живую композицию приложения: shipping-пресеты из `presets/`
/// (ConfigModule + rootBundle), PresetManager на in-memory БД, единый
/// ProviderContainer с реактивной проводкой (R-21) и реестром выбора
/// реализации (D-32). Никаких ручных инстансов провайдеров — сценарий
/// показывает ровно тот путь, который пройдёт UI на Этапе 8.
///
/// Демонстрирует и ассертит:
///  1. Тхеравада → только упосатхи (перекрёстной подсветки нет);
///  2. Ньингма → 10-е/25-е дни и Лосар того же окна;
///  3. переключение пресета меняет набор БЕЗ перезапуска контейнера;
///  4. день вне верифицированного пака праздников → честный статус
///     «не проверено» (флаг festivalsPackComplete=false), а не «праздников нет».
///
/// Вывод шагов печатается в stdout — секции прогона идут в отчёт пакета
/// дословно (урок 2: критерий — предъявляемый прогон, а не зелёный факт).
/// Поэтому print здесь — продукт файла, а не отладочный шум.
// ignore_for_file: avoid_print
library;

import 'package:dharma_toolkit/core/config/config_module.dart';
import 'package:dharma_toolkit/core/config/preset_manager.dart';
import 'package:dharma_toolkit/core/db/app_database.dart';
import 'package:dharma_toolkit/core/storage/storage_module.dart';
import 'package:dharma_toolkit/features/calendar/data/tibetan/tibetan_calendar_provider.dart';
import 'package:dharma_toolkit/features/calendar/data/uposatha/uposatha_calendar_provider.dart';
import 'package:dharma_toolkit/features/calendar/domain/special_day.dart';
import 'package:dharma_toolkit/features/calendar/presentation/providers/calendar_providers.dart';
import 'package:dharma_toolkit/shared/providers/app_providers.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Читаемая подпись типа для табличного вывода «дата | тип | имя».
String _typeLabel(SpecialDayType t) => switch (t) {
      SpecialDayType.uposatha => 'упосатха',
      SpecialDayType.tibetan10 => '10-й день',
      SpecialDayType.tibetan25 => '25-й день',
      SpecialDayType.festival => 'праздник',
    };

String _fmt(DateTime d) => '${d.year}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

void _printSection(String title, List<SpecialDay> days) {
  print('--- $title (${days.length} отм.) ---');
  for (final d in days) {
    print('${_fmt(d.date)} | ${_typeLabel(d.type)} | ${d.name}');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Единое окно сценария: сентябрь 2026 плюс февраль 2027, чтобы в одном
  // прогоне были и 10/25 сентября, и Лосар-2027 (вектор F-45: 2027-02-07).
  final wFrom = DateTime(2026, 9, 1);
  final wTo = DateTime(2027, 2, 28);

  late AppDatabase database;
  late StorageModule storage;
  late ConfigModule config;
  late PresetManager manager;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    database = AppDatabase.forTesting(
      NativeDatabase.memory(setup: enableForeignKeys),
    );
    storage = StorageModule();
    await storage.init();
    config = ConfigModule();
    await config.init(); // реальные shipping-пресеты из presets/*.json
    manager = PresetManager(() => database, storage);
    await manager.init();
    container = ProviderContainer(
      overrides: [presetManagerProvider.overrideWithValue(manager)],
    );
    // Держим подписку: потоковые провайдеры живут между read-вызовами
    // (паттерн provider_selection_test).
    container.listen(activeTraditionTagProvider, (_, _) {});
  });

  tearDown(() async {
    container.dispose();
    await database.close();
    try {
      await storage.dispose();
    } catch (_) {}
  });

  Future<void> settleTag(String expected) async {
    for (var i = 0; i < 50; i++) {
      if (container.read(activeTraditionTagProvider).value == expected) return;
      await Future<void>.delayed(Duration.zero);
    }
    fail('тег так и не стал "$expected"');
  }

  test('SCR-11: Тхеравада → Ньингма → обратно в одном живом контейнере',
      () async {
    // ─ Шаг 1. Применяю Тхераваду.
    await manager.applyPreset(config.getPreset('theravada_default')!);
    await settleTag('theravada_default');
    final cal1 = container.read(activeCalendarProviderProvider);
    expect(cal1, isA<UposathaCalendarProvider>(),
        reason: 'Тхеравада обязана получить лунный календарь, а не тибетский');
    final days1 = cal1!.getSpecialDays(wFrom, wTo);
    _printSection('Шаг 1 · Тхеравада (tag=${cal1.traditionTag})', days1);

    // Только упосатхи: перекрёстная подсветка чужих типов — стоп-гейт.
    expect(days1.any((d) => d.type == SpecialDayType.uposatha), isTrue);
    expect(days1.where((d) => d.type != SpecialDayType.uposatha), isEmpty,
        reason: 'в календаре Тхеравады не должно быть тибетских дней и Лосара');
    // Сентябрьское ядро окна совпадает со снапшотом 5b.2 (9-4/9-11/9-18/9-26).
    expect(
        days1
            .where((d) =>
                d.type == SpecialDayType.uposatha && d.date.month == 9)
            .map((d) => int.parse(_fmt(d.date).substring(8)))
            .toList(),
        [4, 11, 18, 26]);

    // ─ Шаг 2. Переключаю на Ньингму (контейнер не пересоздавался).
    await manager.switchPreset(config.getPreset('nyingma')!);
    await settleTag('nyingma');
    final cal2 = container.read(activeCalendarProviderProvider);
    expect(cal2, isA<TibetanCalendarProvider>(),
        reason: 'смена пресета без перезапуска обязана сменить календарь (R-21)');
    final days2 = cal2!.getSpecialDays(wFrom, wTo);
    _printSection('Шаг 2 · Ньингма после switchPreset, тот же контейнер'
        ' (tag=${cal2.traditionTag})', days2);

    // 10/25 сентября на месте; Лосар-2027 = 07.02 (вектор F-45).
    expect(days2.where((d) =>
        d.date.month == 9 && d.type == SpecialDayType.tibetan10), isNotEmpty,
        reason: '10-е дни сентября должны быть размечены');
    expect(days2.where((d) =>
        d.date.month == 9 && d.type == SpecialDayType.tibetan25), isNotEmpty,
        reason: '25-е дни сентября должны быть размечены');
    expect(
        days2
            .where((d) => d.type == SpecialDayType.festival)
            .map((d) => _fmt(d.date))
            .toList(),
        ['2027-02-07'],
        reason: 'в окне Лосар ровно один и это вектор F-45 (2027-02-07)');
    // Обратная перекрёстная защита: упосатх в тибетском календаре нет.
    expect(days2.where((d) => d.type == SpecialDayType.uposatha), isEmpty,
        reason: 'Ньингма не должна подсвечивать упосатхи');
    // Набор изменился относительно шага 1 — это и есть «переключение меняет».
    expect(days2.map((d) => (d.date, d.type)).toSet(),
        isNot(days1.map((d) => (d.date, d.type)).toSet()));

    // ─ Шаг 3. Возврат на Тхераваду — тоже без перезапуска.
    await manager.switchPreset(config.getPreset('theravada_default')!);
    await settleTag('theravada_default');
    final cal3 = container.read(activeCalendarProviderProvider);
    expect(cal3, isA<UposathaCalendarProvider>(),
        reason: 'обратное переключение возвращает лунный календарь');
    final days3 = cal3!.getSpecialDays(wFrom, wTo);
    print('--- Шаг 3 · возврат на Тхераваду: набор равен шагу 1 '
        '(${days3.length} отм., без пересоздания контейнера) ---');
    expect(days3, equals(days1),
        reason: 'чистота (контракт 5b.1): повтор пути даёт тот же набор');
  });

  test('SCR-11: день вне верифицированного пака — «не проверено», не «нет»',
      () async {
    await manager.applyPreset(config.getPreset('nyingma')!);
    await settleTag('nyingma');
    final cal = container.read(activeCalendarProviderProvider)!;
    final sep = cal.getSpecialDays(DateTime(2026, 9, 1), DateTime(2026, 9, 30));
    final marked = sep.map((d) => d.date).toSet();
    final unmarkedDay = DateTime(2026, 9, 14); // не 10-й, не 25-й, не Лосар
    expect(marked.contains(unmarkedDay), isFalse,
        reason: 'препосылка: день не размечен вычислимым паком');

    // Ровно та ветка статусной функции, которую обязан использовать UI
    // (UX-A-4): при festivalsPackComplete=false неразмеченный день —
    // «не проверено», а не «праздников нет».
    expect(TibetanCalendarProvider.festivalsPackComplete, isFalse,
        reason: 'флаг честности обязан быть false, пока таблица не верифицирована');
    final status = marked.contains(unmarkedDay)
        ? 'отмечен'
        : (TibetanCalendarProvider.festivalsPackComplete
            ? 'праздников нет'
            : 'не проверено (пак праздников не верифицирован)');
    _printSection('Ньингма, сентябрь 2026 (статусная ветка UX-A-4)', sep);
    print('${_fmt(unmarkedDay)} | — | $status');

    expect(status, 'не проверено (пак праздников не верифицирован)',
        reason: 'стоп-гейт: «праздников нет» вместо «не проверено» недопустим');
    // Заодно: в сентябре festival-отметин нет — tripwire 5b.3 на месте.
    expect(sep.where((d) => d.type == SpecialDayType.festival), isEmpty);
  });
}
