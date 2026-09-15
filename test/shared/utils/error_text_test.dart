import 'package:dharma_toolkit/shared/utils/error_text.dart';
import 'package:flutter_test/flutter_test.dart';

/// B-19: пользователю — человекочитаемое сообщение, не сырое исключение.
void main() {
  group('userFacingErrorText (B-19)', () {
    test('с деталями возвращает ровно сообщение, без текста исключения', () {
      final text = userFacingErrorText(
        'Не удалось загрузить практики',
        details: StateError('SQLITE_ERROR: no such table: practices'),
      );

      expect(text, 'Не удалось загрузить практики');
      expect(text.contains('SQLITE_ERROR'), isFalse,
          reason: 'детали исключения не должны попадать в UI');
      expect(text.contains('StateError'), isFalse);
    });

    test('без деталей ведёт себя так же', () {
      expect(
        userFacingErrorText('Ошибка восстановления'),
        'Ошибка восстановления',
      );
    });

    test('детали любого типа (не String) тоже не протекают в текст', () {
      final text = userFacingErrorText(
        'Ошибка восстановления',
        details: Exception('PathNotFoundException: db.sqlite'),
      );

      expect(text, 'Ошибка восстановления');
      expect(text.contains('db.sqlite'), isFalse);
      expect(text.contains('Exception'), isFalse);
    });
  });
}
