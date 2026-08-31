import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// Проводка локализации (R-15, D-28): приложение только на русском (D-23).
///
/// Единственный источник списков делегатов/локалей — чтобы `MaterialApp.router`
/// в `main.dart` и `MaterialApp` экрана восстановления не расходились
/// (урок 3: не дублировать точечно). Фиксированный [appLocale] означает, что
/// языковые настройки устройства не перебивают русский: поддержка только `ru`,
/// ничего другого предложить не можем.
///
/// Глобальные делегаты дают русские системные строки Material: кнопки диалогов
/// («Отмена»/«ОК»), date/time pickers (будут в Этапе 6), меню выделения
/// текста («Копировать»/«Вставить») для TalkBack.
const List<LocalizationsDelegate<Object?>> appLocalizationsDelegates = [
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

const List<Locale> appSupportedLocales = [Locale('ru')];

const Locale appLocale = Locale('ru');
