import 'package:dharma_toolkit/shared/utils/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatCount (6.1)', () {
    test('без единицы — просто число, без висячего пробела', () {
      expect(formatCount(123, null), '123');
      expect(formatCount(123, ''), '123');
      expect(formatCount(123, '   '), '123');
      // Отдельно страховка от регрессии хвоста:
      expect(formatCount(123, null).endsWith(' '), isFalse);
    });

    test('с единицей — «N единица»', () {
      expect(formatCount(123, 'повторений'), '123 повторений');
      expect(formatCount(0, 'минут'), '0 минут');
    });

    test('единица trim-ится', () {
      expect(formatCount(5, '  простираний '), '5 простираний');
    });
  });
}
