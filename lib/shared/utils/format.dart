/// Форматирование счётных значений (общие утилиты UI).
library;

/// «123 повторений» / «123», если единица не задана.
///
/// Гарантирует отсутствие висячего пробела (мелочь аудита D-24/6.1):
/// пустая или пробельная `unit` не добавляет хвост.
String formatCount(int count, String? unit) {
  final trimmed = unit?.trim() ?? '';
  if (trimmed.isEmpty) return '$count';
  return '$count $trimmed';
}

/// Разбор целого с группировкой разрядов — единые правила валидации числовых
/// полей (урок 3, слой причины): форма создания цели (B-9, 5.0.4) и диалог
/// произвольного инкремента (FR-TRK-9, 5.0.5) проверяют ввод здесь.
///
/// Пробелы — группировка разрядов («1 500» → 1500), а не данные;
/// пустой ввод → null; нецелое или ≤ 0 → [FormatException] с текстом [error]
/// для показа под полем.
int? parseGroupedPositiveInt(String raw, {required String error}) {
  final normalized = raw.trim().replaceAll(RegExp(r'\s+'), '');
  if (normalized.isEmpty) return null;
  final parsed = int.tryParse(normalized);
  if (parsed == null || parsed <= 0) {
    throw FormatException(error);
  }
  return parsed;
}
