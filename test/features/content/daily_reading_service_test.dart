/// Чтение дня из паков: ротация, привязка к дате, фолбэк (блок B пакета 7.0).
///
/// Проверяется доменное поведение, а не отрисовка (урок 5): какой текст
/// выпадает на день, в каком порядке, что видит пользователь при отсутствии
/// контента и как выглядит атрибуция. Часы не подделываются вовсе — «сегодня»
/// приходит аргументом, поэтому результат детерминирован без fake-async.
///
/// Отдельно проверяется **честность**: неподтверждённый пак не выдаёт свои
/// тексты за проверенные, а фолбэк FR-CNT-3 не выдаёт себя за текст традиции.
library;

import 'package:dharma_toolkit/core/calendar/special_day.dart';
import 'package:dharma_toolkit/core/calendar/special_days_source.dart';
import 'package:dharma_toolkit/features/content/data/content_pack_loader.dart';
import 'package:dharma_toolkit/features/content/domain/content_fallbacks.dart';
import 'package:dharma_toolkit/features/content/domain/content_pack.dart';
import 'package:dharma_toolkit/core/content/daily_reading.dart';
import 'package:dharma_toolkit/features/content/domain/content_rotation.dart';
import 'package:dharma_toolkit/features/content/domain/daily_reading_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Источник-заглушка: отдаёт заданный ответ по правилу `tibetan` (в том числе
/// «не умею» — `null`).
class _StubSource implements SpecialDaysSource {
  _StubSource(this.traditionTag, {this.tibetanDates});

  @override
  final String traditionTag;

  final List<DateTime>? tibetanDates;

  /// Сколько раз спросили про правило tibetan (страх от «спросили и забыли»).
  int tibetanCalls = 0;

  @override
  List<SpecialDay> getSpecialDays(DateTime from, DateTime to) => const [];

  @override
  List<DateTime>? resolveTibetanMonthDay({
    required int month,
    required int day,
    required DateTime from,
    required DateTime to,
  }) {
    tibetanCalls++;
    return tibetanDates;
  }
}

ContentEntry entryOf({
  String id = 'c1',
  String title = 'Синтетическое чтение',
  String body = 'Синтетический текст фикстуры.',
  String source = 'синтетическая фикстура теста',
  ContentDateRule? rule,
}) =>
    ContentEntry(
      id: id,
      title: title,
      body: body,
      source: source,
      dateRule: rule,
    );

ContentPack packOf({
  String packId = 'p',
  String traditionTag = 'nyingma',
  bool verified = true,
  required List<ContentEntry> entries,
}) =>
    ContentPack(
      packId: packId,
      traditionTag: traditionTag,
      version: '1',
      verified: verified,
      entries: entries,
    );

/// Пул из [size] записей без правил даты.
List<ContentEntry> poolOf(int size) => [
      for (var i = 0; i < size; i++)
        entryOf(id: 'pool$i', title: 'Чтение пула $i', body: 'Текст $i.'),
    ];

final _today = DateTime(2026, 6, 1);

DailyReadingService serviceOf({
  String traditionTag = 'nyingma',
  List<ContentPack>? packs,
  SpecialDaysSource? source,
  List<ContentPackFailure> failures = const [],
}) =>
    DailyReadingService(
      traditionTag: traditionTag,
      packs: packs ?? [packOf(entries: poolOf(3))],
      source: source,
      packFailures: failures,
    );

void main() {
  group('ContentRotation — детерминизм и границы', () {
    test('раскладка дня проходит через прод-формулу сида (эталон, W28)', () {
      // W28: прежний тест крепил значение `stableHash` для строки дня, которой
      // прод не хэширует (прод берёт `block:$block`), поэтому расхождение с
      // прод-формулой сида не ловилось — смена ключа раскладки оставляла тест
      // зелёным. Здесь закреплён результат `indexForDay`: он доходит до
      // продового `stableHash('block:$block')` в `_orderOfBlock`, поэтому
      // смена ключа/алгоритма меняет последовательность и краснит тест.
      final indices = [
        for (var i = 0; i < 9; i++)
          ContentRotation.indexForDay(
              DateTime(2026, 6, 1).add(Duration(days: i)), 3),
      ];
      expect(indices, [2, 1, 0, 1, 2, 0, 2, 1, 2]);
    });

    test('пустой пул — честная ошибка вызова, а не тихий ноль', () {
      expect(() => ContentRotation.indexForDay(_today, 0), throwsArgumentError);
    });

    test('пул из одной записи всегда даёт индекс 0 (повтор не с чем путать)', () {
      expect(ContentRotation.indexForDay(_today, 1), 0);
      expect(ContentRotation.indexForDay(DateTime(2027, 1, 1), 1), 0);
    });
  });

  group('DailyReadingService — ротация и привязка к дате', () {
    test('запись без dateRule приходит ротацией с атрибуцией пака', () {
      final day = serviceOf().readingsFor(_today);

      final reading = day.readings.single;
      expect(reading.source, ContentReadingSource.pack);
      expect(reading.isDateBound, isFalse);
      expect(reading.packId, 'p');
      expect(reading.attribution, 'пак «p» · синтетическая фикстура теста');
      expect(reading.date, _today);
      expect(reading.isVerified, isTrue);
    });

    test('григорианское правило: чтение приходит в свой день, не в чужой', () {
      final service = serviceOf(packs: [
        packOf(entries: [
          entryOf(rule: const GregorianYearlyContentDateRule(month: 6, day: 2)),
        ]),
      ]);

      expect(service.readingsFor(_today).readings.single.isDateBound, isFalse,
          reason: 'в сегодняшний день правило 2 июня не выпадает — работает '
              'ротация из пула');
      expect(service.readingsFor(DateTime(2026, 6, 2)).readings.single.title,
          'Синтетическое чтение');
      expect(
          service.readingsFor(DateTime(2026, 6, 2)).readings.single.isDateBound,
          isTrue);
    });

    test('привязанное чтение идёт первым, ротация — второй', () {
      final day = serviceOf(packs: [
        packOf(entries: [
          entryOf(
            id: 'pooled',
            title: 'Чтение пула',
            rule: null,
          ),
          entryOf(
            id: 'bound',
            title: 'Чтение на второе июня',
            rule: const GregorianYearlyContentDateRule(month: 6, day: 2),
          ),
        ]),
      ]).readingsFor(DateTime(2026, 6, 2));

      expect(day.readings, hasLength(2));
      expect(day.readings.first.title, 'Чтение на второе июня');
      expect(day.readings.first.isDateBound, isTrue);
      expect(day.readings.last.title, 'Чтение пула');
      expect(day.readings.last.isDateBound, isFalse);
    });

    test('правило tibetan разрешается через порт календаря', () {
      final source = _StubSource('nyingma', tibetanDates: [DateTime(2026, 6, 1)]);
      final day = serviceOf(
        packs: [
          packOf(entries: [
            entryOf(
              id: 'tib',
              title: 'Тибетское чтение',
              rule: const TibetanContentDateRule(month: 10, day: 25),
            ),
          ]),
        ],
        source: source,
      ).readingsFor(_today);

      expect(source.tibetanCalls, 1);
      expect(day.readings.single.title, 'Тибетское чтение');
      expect(day.readings.single.isDateBound, isTrue);
    });

    test('правило tibetan без календаря — пропуск с причиной, не тихий пропуск',
        () {
      final day = serviceOf(packs: [
        packOf(entries: [
          entryOf(rule: const TibetanContentDateRule(month: 10, day: 25)),
        ]),
      ]).readingsFor(_today);

      expect(day.notes.any((n) => n.contains('требует календаря')), isTrue,
          reason: 'пользователь обязан узнать, почему текст пропущен');
      // C8г (ревью): user-канал без названия чтения и packId; конкретика — в
      // диагностике.
      expect(day.notes.any((n) => n.contains('Синтетическое чтение')), isFalse);
      expect(day.notes.any((n) => n.contains('«p»')), isFalse);
      expect(day.debugNotes.any((n) => n.contains('Синтетическое чтение')), isTrue);
      expect(day.debugNotes.any((n) => n.contains('«p»')), isTrue);
    });

    test('календарь тибетских дат не знает — честный отказ, отличный от '
        '«дата не встречается»', () {
      final source = _StubSource('theravada', tibetanDates: null);
      final day = serviceOf(
        traditionTag: 'theravada',
        packs: [
          packOf(
            traditionTag: 'theravada',
            entries: [
              entryOf(rule: const TibetanContentDateRule(month: 10, day: 25)),
            ],
          ),
        ],
        source: source,
      ).readingsFor(_today);

      expect(day.notes.any((n) => n.contains('тибетских дат не знает')), isTrue);
      // C8г (ревью): тег традиции и названия не уходят в user-канал.
      expect(day.notes.any((n) => n.contains('theravada')), isFalse);
      expect(day.notes.any((n) => n.contains('Синтетическое чтение')), isFalse);
      expect(day.debugNotes.any((n) => n.contains('theravada')), isTrue);
      expect(day.debugNotes.any((n) => n.contains('Синтетическое чтение')), isTrue);
    });

    test('ротация: соседние дни не повторяют один и тот же текст (годовой свип)',
        () {
      final service = serviceOf(packs: [packOf(entries: poolOf(3))]);
      String? previous;
      for (var i = 0; i < 365; i++) {
        final reading =
            service.readingsFor(DateTime(2026, 1, 1 + i)).readings.first;
        expect(reading.title, isNot(previous),
            reason: 'два дня подряд один текст — это не ротация '
                '(день ${i + 1})');
        previous = reading.title;
      }
    });

    test('ротация детерминирована: тот же день — тот же текст', () {
      final service = serviceOf(packs: [packOf(entries: poolOf(4))]);

      final first = service.readingsFor(_today).readings.single.title;
      final second =
          service.readingsFor(DateTime(2026, 6, 1, 23, 59)).readings.single.title;

      expect(second, first, reason: 'время суток не влияет на выбор текста дня');
    });

    test('ротация обходит весь пул: за 10 дней видны оба текста пула из двух',
        () {
      final service = serviceOf(packs: [packOf(entries: poolOf(2))]);
      final seen = <String>{};
      for (var i = 0; i < 10; i++) {
        seen.add(service.readingsFor(DateTime(2026, 6, 1 + i))
            .readings
            .single
            .title);
      }

      expect(seen, hasLength(2));
    });

    test('неподтверждённый пак не выдаёт свои тексты за проверенные', () {
      final day = serviceOf(packs: [
        packOf(verified: false, entries: poolOf(2)),
      ]).readingsFor(_today);

      expect(day.readings.single.isVerified, isFalse);
      expect(day.notes.any((n) => n.contains('не подтверждён')), isTrue);
      // C8г (ревью): id пака виден только диагностике.
      expect(day.notes.any((n) => n.contains('«p»')), isFalse);
      expect(day.debugNotes.single, contains('«p»'));
    });

    test('пак чужой традиции не берётся (изоляция данных, принцип №3)', () {
      final day = serviceOf(packs: [
        packOf(packId: 'foreign', traditionTag: 'theravada', entries: poolOf(2)),
      ]).readingsFor(_today);

      expect(day.isFallback, isTrue,
          reason: 'чужой пак не даёт контента — работает фолбэк');
      expect(day.notes.any((n) => n.contains('изоляция данных')), isTrue);
      // C8г (ревью): имя и тег чужого пака — только в диагностике.
      expect(day.notes.any((n) => n.contains('foreign')), isFalse);
      expect(day.notes.any((n) => n.contains('theravada')), isFalse);
      expect(day.debugNotes.any((n) => n.contains('foreign')), isTrue);
      expect(day.debugNotes.any((n) => n.contains('theravada')), isTrue);
    });

    test('пул собирается только из записей без правила даты', () {
      final service = serviceOf(packs: [
        packOf(entries: [
          entryOf(
            id: 'bound',
            title: 'Привязанное',
            rule: const GregorianYearlyContentDateRule(month: 12, day: 31),
          ),
          entryOf(id: 'pooled', title: 'Пуловое'),
        ]),
      ]);

      for (var i = 0; i < 30; i++) {
        final reading =
            service.readingsFor(DateTime(2026, 6, 1 + i)).readings.single;
        expect(reading.title, 'Пуловое',
            reason: 'привязанная запись не участвует в ротации пула');
      }
    });
  });

  group('DailyReadingService — сбои паков в чтении дня (C8б)', () {
    test('битый пак: тип отказа в notes, путь поля и ассет — в debugNotes', () {
      final day = serviceOf(packs: const [], failures: const [
        ContentPackFailure(
          'assets/content_packs/broken.json',
          'запись отвергнута — поле "entries[2].title": '
              'обязательное поле отсутствует',
        ),
      ]).readingsFor(_today);

      expect(day.isFallback, isTrue,
          reason: 'живых паков нет — показана собственная формулировка');
      expect(
        day.notes.any((n) => n.contains('часть записей пака повреждена')),
        isTrue,
        reason: 'пользователь видит тип отказа, а не только «источника нет»; '
            'общее «источник недоступен» без причины недопустимо',
      );
      expect(day.notes.any((n) => n.contains('entries[')), isFalse,
          reason: 'путь поля — внутренняя деталь, ему место в диагностике');
      expect(day.notes.any((n) => n.contains('assets/')), isFalse);
      expect(day.debugNotes.any((n) => n.contains('entries[2].title')), isTrue);
      expect(
          day.debugNotes.any(
              (n) => n.contains('assets/content_packs/broken.json')),
          isTrue);
    });

    test('битый JSON: user-строка без сырой причины и пути', () {
      final day = serviceOf(packs: const [], failures: const [
        ContentPackFailure('assets/content_packs/b.json', 'битый JSON: ...'),
      ]).readingsFor(_today);

      expect(day.notes.any((n) => n.contains('пак повреждён: не читается')),
          isTrue);
      expect(day.notes.any((n) => n.contains('битый JSON')), isFalse);
      expect(day.debugNotes.any((n) => n.contains('битый JSON')), isTrue);
    });

    test('без сбоев в диагностике — только запись фолбэка', () {
      final day = serviceOf(packs: const []).readingsFor(_today);

      expect(day.notes, contains(ContentFallbacks.note));
      expect(day.debugNotes, [ContentFallbacks.debugNote]);
    });
  });

  group('DailyReadingService — фолбэк FR-CNT-3', () {
    test('паков нет → собственная формулировка, а не пустой экран', () {
      final day = serviceOf(packs: const []).readingsFor(_today);

      final reading = day.readings.single;
      expect(reading.source, ContentReadingSource.fallback);
      expect(reading.title, ContentFallbacks.title);
      expect(reading.body, ContentFallbacks.forDay(_today));
      expect(reading.packId, isNull);
      expect(day.notes, contains(ContentFallbacks.note));
    });

    test('фолбэк не выдаёт себя за текст традиции', () {
      final reading =
          serviceOf(packs: const []).readingsFor(_today).readings.single;

      expect(reading.isVerified, isFalse);
      expect(reading.attribution, contains('приложения'));
      expect(reading.attribution, isNot(contains('пак «')),
          reason: 'фолбэк не имеет права выглядеть как текст пака');
    });

    test('пак-заготовка без записей — тоже фолбэк (пустой пак ничего не обещал)',
        () {
      final day =
          serviceOf(packs: [packOf(entries: const [])]).readingsFor(_today);

      expect(day.isFallback, isTrue);
    });

    test('фолбэк ротируется день ото дня (без повторов подряд)', () {
      final service = serviceOf(packs: const []);
      String? previous;
      for (var i = 0; i < 60; i++) {
        final reading =
            service.readingsFor(DateTime(2026, 6, 1 + i)).readings.single;
        expect(reading.body, isNot(previous));
        expect(reading.body, isNotEmpty);
        previous = reading.body;
      }
    });

    test('формулировки нейтральны: ни одного упоминания традиции в тексте', () {
      for (final text in ContentFallbacks.formulations) {
        expect(text.trim(), isNotEmpty);
        expect(text.length, lessThan(160),
            reason: 'фолбэк обязан оставаться кратким (FR-CNT-3)');
      }
    });

    test('S5: в UI только локализуемый текст — id и пути уходят в диагностику',
        () {
      final day = serviceOf(packs: const []).readingsFor(_today);
      final reading = day.readings.single;

      // Весь текст, который видит пользователь: пояснение дня, поля чтения и
      // UI-константы фолбэка. Внутренние id требований и пути ассетов здесь
      // недопустимы — их место в диагностике (то же разделение, что C8г).
      final uiTexts = <String>[
        ...day.notes,
        reading.title,
        reading.body,
        reading.attribution,
        ContentFallbacks.title,
        ContentFallbacks.attribution,
        ContentFallbacks.note,
        ...ContentFallbacks.formulations,
      ];
      for (final text in uiTexts) {
        expect(RegExp(r'FR-[A-Z]+-\d').hasMatch(text), isFalse,
            reason: 'внутренний id требования не место в UI-строке: «$text»');
        expect(text.contains('assets/'), isFalse,
            reason: 'путь ассета — диагностике: «$text»');
        expect(text.contains('.json'), isFalse,
            reason: 'ключ ассета — диагностике: «$text»');
      }
      expect(day.notes, contains(ContentFallbacks.note));
      expect(day.debugNotes, contains(ContentFallbacks.debugNote));
      expect(day.debugNotes.any((n) => n.contains('FR-CNT-3')), isTrue,
          reason: 'id требования уходит в диагностику, а не теряется');
    });
  });
}
