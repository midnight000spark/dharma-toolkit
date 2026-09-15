/// План уведомлений: горизонт D-36, честные состояния и границы (блок D).
///
/// Проверяется домен планирования, а не плагин: план — платформо-независимое
/// описание, поэтому проверяется без уведомлений, таймзон и fake-async.
library;

import 'package:dharma_toolkit/core/calendar/special_day.dart';
import 'package:dharma_toolkit/core/calendar/special_days_source.dart';
import 'package:dharma_toolkit/features/events/domain/event_feed_service.dart';
import 'package:dharma_toolkit/features/events/domain/event_pack.dart';
import 'package:dharma_toolkit/features/events/domain/notification_plan.dart';
import 'package:dharma_toolkit/features/events/domain/notification_settings.dart';
import 'package:flutter_test/flutter_test.dart';

/// Источник дней: отдаёт заранее заданный список (окно соблюдает — как
/// требует контракт [SpecialDaysSource]).
class _StubSource implements SpecialDaysSource {
  _StubSource(this.traditionTag, this.days);

  @override
  final String traditionTag;
  final List<SpecialDay> days;

  @override
  List<SpecialDay> getSpecialDays(DateTime from, DateTime to) => [
        for (final d in days)
          if (!d.date.isBefore(from) && !d.date.isAfter(to)) d,
      ];

  @override
  List<DateTime>? resolveTibetanMonthDay({
    required int month,
    required int day,
    required DateTime from,
    required DateTime to,
  }) =>
      null;
}

/// Дни «каждый день» в окне [from]..[to] — для проверки границ горизонта.
List<SpecialDay> dailyDays(DateTime from, int count, {String name = 'День'}) => [
      for (var i = 0; i < count; i++)
        SpecialDay(
          date: DateTime(from.year, from.month, from.day + i),
          type: SpecialDayType.uposatha,
          name: '$name $i',
        ),
    ];

NotificationPlanBuilder builderFor(String tag, List<SpecialDay> days,
        {List<EventPack> packs = const []}) =>
    NotificationPlanBuilder(
      feedService: EventFeedService(
        traditionTag: tag,
        source: _StubSource(tag, days),
        packs: packs,
      ),
    );

/// Полдень 1 июня 2026 — «сейчас» во всех тестах блока.
final _now = DateTime(2026, 6, 1, 12);

void main() {
  group('NotificationPlanBuilder — честные состояния', () {
    test('уведомления выключены → пустой план с пояснением (FR-EVT-3)', () {
      final plan = builderFor('theravada_default', dailyDays(_now, 5))
          .build(
        now: _now,
        settings: NotificationSettings.defaults.copyWith(enabled: false),
      );

      expect(plan.items, isEmpty);
      expect(plan.notes.single, contains('выключены'));
    });

    test('пустой вход без деградаций → пустой план без пояснений', () {
      // Календарь привязан, но в окне нет особых дней, паков нет: молчать
      // здесь честно — деградации не случилось, пустое состояние рисует UI
      // (SCR-12), а не домен.
      final plan = builderFor('theravada_default', const [])
          .build(now: _now, settings: NotificationSettings.defaults);

      expect(plan.items, isEmpty);
      expect(plan.notes, isEmpty);
    });

    test('ни одного «своего» пункта: только события ленты (FR-EVT-4/UX-A-2)',
        () {
      // Начинаем с завтрашнего дня: сегодняшние 08:00 уже прошли в 12:00.
      final days = dailyDays(_now.add(const Duration(days: 1)), 3);
      final plan = builderFor('theravada_default', days)
          .build(now: _now, settings: NotificationSettings.defaults);

      expect(plan.items, hasLength(3));
      expect(plan.items.map((i) => i.title).toList(),
          days.map((d) => d.name).toList());
      expect(
        plan.items.every((i) => i.scheduledAt.hour == 8 &&
            i.scheduledAt.minute == 0),
        isTrue,
        reason: 'время — из настроек (D-36: дефолт 08:00)',
      );
    });

    test('время из настроек, а не дефолтное', () {
      final plan = builderFor(
              'theravada_default', dailyDays(_now.add(const Duration(days: 1)), 1))
          .build(
        now: _now,
        settings: NotificationSettings(enabled: true, hour: 21, minute: 5),
      );

      expect(plan.items.single.scheduledAt.hour, 21);
      expect(plan.items.single.scheduledAt.minute, 5);
    });
  });

  group('NotificationPlanBuilder — время и дедупликация', () {
    test('прошедшие моменты не планируются', () {
      // Сегодняшнее событие в 08:00, «сейчас» — 12:00.
      final today = DateTime(2026, 6, 1);
      final plan = builderFor('theravada_default', [
        SpecialDay(
            date: today,
            type: SpecialDayType.uposatha,
            name: 'Сегодня утром'),
        SpecialDay(
            date: DateTime(2026, 6, 2),
            type: SpecialDayType.uposatha,
            name: 'Завтра утром'),
      ]).build(now: _now, settings: NotificationSettings.defaults);

      expect(plan.items.map((i) => i.title), ['Завтра утром']);
      expect(plan.notes.join('\n'), contains('прошедших'));
    });

    test('одно и то же уведомление в одну минуту не дублируется', () {
      final day = DateTime(2026, 6, 3);
      final source = _StubSource('nyingma', [
        SpecialDay(date: day, type: SpecialDayType.festival, name: 'Один день'),
      ]);
      final pack = EventPack(
        packId: 'synthetic',
        traditionTag: 'nyingma',
        version: '1',
        verified: true,
        entries: [
          EventPackEntry(
            id: 'e1',
            type: 'festival',
            name: 'Один день',
            dateRule: const GregorianYearlyDateRule(month: 6, day: 3),
            source: 'синтетическая фикстура теста',
          ),
        ],
      );
      final plan = NotificationPlanBuilder(
        feedService: EventFeedService(
          traditionTag: 'nyingma',
          source: source,
          packs: [pack],
        ),
      ).build(now: _now, settings: NotificationSettings.defaults);

      expect(plan.items, hasLength(1),
          reason: 'две записи ленты с тем же названием и временем — один показ');
    });
  });

  group('NotificationPlanBuilder — горизонт и лимит pending', () {
    test('горизонт D-36 = 60 дней: 61-й день не планируется', () {
      final plan = builderFor('theravada_default', dailyDays(_now, 90)).build(
        now: _now,
        settings: NotificationSettings.defaults,
      );

      final last = plan.items.last.scheduledAt;
      expect(last.difference(_now).inDays, lessThanOrEqualTo(60));
      expect(
        plan.items.any((i) => i.title == 'День 61'),
        isFalse,
        reason: 'за пределом горизонта планирования нет пунктов',
      );
      expect(plan.items, hasLength(60),
          reason: 'день 0 — сегодня, моменты уже прошедшие не планируются');
    });

    test('pending не превышает iOS-лимит 64 (F-57) и это видно', () {
      final plan = builderFor('theravada_default', dailyDays(_now, 90)).build(
        now: _now,
        settings: NotificationSettings.defaults,
      );

      expect(plan.items.length, lessThanOrEqualTo(NotificationPlan.maxPending));
    });

    test('превышение лимита 64 не теряется молча, а поясняется', () {
      final builder = builderFor('theravada_default', dailyDays(_now, 200));
      final plan = builder.build(
        now: _now,
        settings: NotificationSettings.defaults,
        horizon: const Duration(days: 200),
      );

      expect(plan.items, hasLength(NotificationPlan.maxPending));
      expect(plan.notes.join('\n'), contains('лимит'));
    });

    test('идентификаторы — в полосе приложения D-36', () {
      final plan = builderFor('theravada_default', dailyDays(_now, 90)).build(
        now: _now,
        settings: NotificationSettings.defaults,
      );

      expect(plan.items.first.id, NotificationPlan.idRangeStart);
      expect(plan.items.map((i) => i.id).toSet(), hasLength(plan.items.length),
          reason: 'идентификаторы уникальны');
      expect(
        plan.items.every((i) => i.id >= NotificationPlan.idRangeStart &&
            i.id <= NotificationPlan.idRangeEnd),
        isTrue,
      );
    });
  });

  group('NotificationPlanBuilder — атрибуция в уведомлении', () {
    test('непроверенная дата помечена в тексте (UX-A-4)', () {
      final pack = EventPack(
        packId: 'synthetic_unverified',
        traditionTag: 'nyingma',
        version: '1',
        verified: false,
        entries: [
          EventPackEntry(
            id: 'e1',
            type: 'festival',
            name: 'Непроверенный день',
            dateRule: const GregorianYearlyDateRule(month: 6, day: 4),
            source: 'синтетическая фикстура теста',
          ),
        ],
      );
      final plan = builderFor('nyingma', const [], packs: [pack])
          .build(now: _now, settings: NotificationSettings.defaults);

      expect(plan.items.single.title, 'Непроверенный день');
      expect(plan.items.single.body, contains('не подтверждена'));
    });

    test('payload несёт дату и источник — адаптер 6.2 откроет нужный экран',
        () {
      final plan = builderFor(
              'theravada_default', dailyDays(_now.add(const Duration(days: 1)), 1))
          .build(now: _now, settings: NotificationSettings.defaults);

      expect(plan.items.single.payload, contains('2026-06-02'));
      expect(plan.items.single.payload, contains('calendar'));
      expect(plan.items.single.payload, isNot(contains('packId')));
    });
  });
}
