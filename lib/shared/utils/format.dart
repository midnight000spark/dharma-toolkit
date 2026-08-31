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
