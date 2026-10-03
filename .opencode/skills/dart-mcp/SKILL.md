---
name: dart-mcp
description: >
  Use the `dart` MCP server for Dart/Flutter tooling against the local project:
  analyze files, hot reload/restart a running app, inspect the widget tree,
  drive a Flutter app, read dependencies, and query packages. Unlike jev-mcp,
  this server DOES touch the local repository and a running app.
license: MIT
compatibility: opencode
metadata:
  audience: developer
  workflow: dart-flutter-loop
---

## Что я делаю

Тонкая обёртка над тулчейном Dart/Flutter (`dart mcp-server`): анализ, hot
reload/restart, инспекция виджетов, `flutter_driver`-команды, чтение
зависимостей, поиск по пакетам. Сервер **работает с реальным деревом проекта**
(в отличие от `jev-mcp`, который repo-blind) и может подключаться к запущенному
приложению через DTD/VM-service.

## Когда меня вызывает агент

- После правок Dart/Flutter-кода — **hot reload или hot restart** (см. ниже).
- Нужен `flutter analyze` по конкретным путям, а не весь проект.
- Нужно понять зависимость/пакет: `dart_read_package_uris` (чтение файлов
  `package:` / `package-root:`), `dart_rip_grep_packages` (ripgrep по
  зависимостям), `dart_pub_dev_search` (поиск на pub.dev).
- Нужно посмотреть виджет-дерево/выбранный виджет, прогнать driver-команду,
  прочитать bundle/ошибки рантайма, поуправлять VM-service.

## Порядок для live-приложения (важно)

1. Если приложение ещё не подключено — **сначала `dtd` → `listDtdUris`**, затем
   `connect` к нужному URI; `listConnectedApps` покажет подключённые приложения.
   Если рабочий каталог URI похож на домашний каталог — это, вероятно, IDE, и
   подключаться надо к нему, чтобы найти app из IDE.
2. **После завершения правок кода всегда** выполняй `hot_reload` (или
   `hot_restart`, если менялись глобальные `const`/состояние). Это часть
   дисциплины, а не опция.
3. Для взаимодействия с виджетом сначала получи дерево через
   `widget_inspector` (`get_widget_tree`), выбери реальный текст/tooltip/тип
   виджета — **не угадывай селекторы**.

## Инструменты (кратко)

| Тул | Назначение |
|---|---|
| `dart_analyze_files` | анализ путей/проекта; `applyFixes` — автофиксы (осторожно) |
| `dart_get_runtime_errors` | последние ошибки рантайма активного приложения |
| `dart_hot_reload` / `dart_hot_restart` | применить правки к запущенному приложению |
| `dart_widget_inspector` | дерево виджетов, выбранный виджет, режим выбора |
| `dart_flutter_driver_command` | команды `flutter_driver` (tap/scroll/text/…); селекторы — из дерева |
| `dart_dtd` | discover/connect/list/disconnect DTD |
| `dart_vm_service` | connect/disconnect/callMethod по VM-service URI |
| `dart_lsp` | hover, signatureHelp, resolveWorkspaceSymbol |
| `dart_pub` | `get`/`deps`/`upgrade`/`outdated`/`add`/`remove` |
| `dart_pub_dev_search` | поиск пакетов на pub.dev |
| `dart_read_package_uris` | чтение файлов зависимостей (`package:`/`package-root:`) |
| `dart_rip_grep_packages` | ripgrep по исходникам зависимостей |
| `dart_roots` | add/remove корней проекта |

## Правила проекта

- `dart_pub add`/`remove` и `dart_pub upgrade` — **новые/меняющиеся зависимости
  owner-gated** (AGENT: новые зависимости — только с одобрения владельца).
  Предлагай, не выполняй.
- `dart_analyze_files --applyFixes` меняет файлы — не применять к `lib/`
  без явной необходимости; `dart format` к `lib/` не применять (D-дисциплина).
- Server — read/write к локальному дереву: не запускай destructive-операции
  вне пакета.

## Если подключения нет

Hot reload/restart недоступны без активного DTD/VM-service — это не ошибка
пакета: собери и прогони обычными командами (`flutter analyze`, `flutter test`,
`flutter run`), а MCP-цикл используй, когда приложение действительно запущено.
