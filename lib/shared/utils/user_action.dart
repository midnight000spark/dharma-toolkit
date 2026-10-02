import 'package:flutter/material.dart';

import 'error_text.dart';

/// Выполнить действие пользователя с видимым сообщением об отказе (W18).
///
/// Раньше отказ репозитория в обработчике кнопки уходил в необработанную
/// асинхронную ошибку: действие не выполнялось, а пользователь видел
/// «ничего не произошло» — самая дорогая форма молчания. Здесь исключение
/// перехватывается, причина уходит в лог, а на экран — snackbar.
///
/// Возвращает `true`, если действие завершилось успешно; `false` — если упало
/// (сообщение показано). Наружу исключение не выпускается: обработчик кнопки
/// не должен уронить экран.
Future<bool> runUserAction(
  BuildContext context,
  Future<void> Function() action, {
  String message = 'Не удалось выполнить действие',
}) async {
  try {
    await action();
    return true;
  } catch (error, stack) {
    debugPrint('Действие не выполнено: $error\n$stack');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userFacingErrorText(message, details: error))),
      );
    }
    return false;
  }
}
