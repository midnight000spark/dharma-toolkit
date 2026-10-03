/// Матчер ошибки провайдера для Riverpod 3 (F-86, пакет `pre-stage-8`/Н1).
///
/// С версии 3.0 Riverpod оборачивает ошибку, возникшую при синхронном
/// `ref.read(...)`/`container.read(...)` отказавшего провайдера, в
/// `ProviderException` (migration guide 3.0). Гарды «непривязанный порт падает
/// громко» проверяют не тип обёртки, а **исходную** причину — она обязана
/// остаться `StateError`/`UnimplementedError` с тем же сообщением. Терять эту
/// проверку при апгрейде нельзя (урок 1/4): иначе «ошибка выходит наружу»
/// превратится в «что-то выходит».
library;

import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:flutter_test/flutter_test.dart';

/// Матчер: чтение провайдера бросает `ProviderException`, чья исходная ошибка
/// (с учётом вложенных оберток) удовлетворяет [causeMatcher].
Matcher throwsProviderError(Object causeMatcher) => throwsA(
      isA<ProviderException>().having(
        (e) => providerErrorCause(e),
        'исходная ошибка провайдера',
        causeMatcher,
      ),
    );

/// Достать исходную ошибку из [error], разворачивая вложенные `ProviderException`.
///
/// Обёртки вкладываются, когда отказавший провайдер читается из другого
/// провайдера: внешний `read` заворачивает уже завёрнутую ошибку внутреннего.
/// Нужен там, где проверка идёт через `predicate`/`having` по сообщению.
Object providerErrorCause(Object error) {
  var cause = error;
  while (cause is ProviderException) {
    cause = cause.exception;
  }
  return cause;
}
