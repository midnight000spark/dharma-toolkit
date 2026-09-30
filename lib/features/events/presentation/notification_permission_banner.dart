/// Честный статус разрешения на уведомления на экране (W1).
///
/// Показывается, когда запрос при первом входе не дал права показывать:
/// «напоминания не придут» — видимое состояние, а не тишина, из-за которой
/// пользователь ждал бы напоминание, которого не будет (UX-A-4, R-26).
/// Запрос запускается самим фактом первого чтения
/// [notificationPermissionProvider] из этого виджета: дерево виджетов и есть
/// UI-контекст, нужный платформенному диалогу (Activity).
///
/// Место — слой composition root (`main.dart`): фича знает о своём порте, а
/// корень — единственный, кому можно связать её с оболочкой. На Этапе 8
/// баннер уступит место штатному состоянию SCR-12/SCR-14.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/notification_scheduler.dart';
import 'providers/event_providers.dart';

/// Полоса состояния разрешения; при действующем разрешении не занимает места.
class NotificationPermissionBanner extends ConsumerWidget {
  const NotificationPermissionBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permission = ref.watch(notificationPermissionProvider);
    final message = permission.when(
      data: _messageFor,
      // Запрос в процессе или отказ запроса (не платформы): молчим — но это
      // не «всё хорошо», а «ещё не знаем»; провайдер перезапросится только
      // явной инвалидацией (Этап 8, SCR-14).
      loading: () => null,
      error: (error, stack) => null,
    );
    if (message == null) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Material(
        color: scheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text(
            message,
            style: TextStyle(color: scheme.onErrorContainer),
          ),
        ),
      ),
    );
  }

  static String? _messageFor(NotificationPermission permission) {
    switch (permission) {
      case NotificationPermission.granted:
        return null;
      case NotificationPermission.denied:
        return 'Напоминания не придут: разрешение на уведомления не выдано.';
      case NotificationPermission.unavailable:
        return 'Напоминания не придут: уведомления на этом устройстве '
            'недоступны.';
    }
  }
}
