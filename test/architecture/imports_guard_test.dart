import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Архитектурные guard-тесты (D-5, D-20; починка R-10 в 5.0.5).
///
/// Прежняя версия ловила только абсолютные `package:dharma_toolkit/features/...`
/// и вообще не проверяла направление core → features — из-за чего R-9 прошёл
/// незамеченным, а второй тест был заглушкой `expect(true, isTrue)`.
///
/// Теперь оба вида директив (`package:` и относительные) резолвятся в
/// нормализованный путь внутри `lib/`, и правила проверяются по факту импорта:
///  1. feature → feature запрещён (изоляция фич, D-5);
///  2. core → features запрещён, КРОМЕ `lib/core/db/` — единственного
///     ослабления принципа №1, агрегации схемы Drift (D-20);
///  3. конкретный список нарушений падает с текстом, по которому видно файл,
///     строку и нарушенное правило.
///
/// Самодостаточность сторожа доказана мутацией 3.2 (нарушения вносились руками
/// и тест краснел), а регрессию резолвинга дополнительно страхуют синтетические
/// кейсы ниже: они падают, если сломается разбор относительных или package-путей.
void main() {
  group('синтетика: резолвинг обоих видов импортов ловит нарушения', () {
    test('package-импорт feature → feature нарушает', () {
      final violations = findViolations({
        'lib/features/tracker/x.dart':
            "import 'package:dharma_toolkit/features/calendar/y.dart';",
      });
      expect(violations, hasLength(1));
      expect(violations.single.rule, 'feature→feature');
    });

    test('относительный импорт feature → feature нарушает', () {
      final violations = findViolations({
        'lib/features/tracker/presentation/x.dart':
            "import '../../calendar/y.dart';",
      });
      expect(violations, hasLength(1));
      expect(violations.single.rule, 'feature→feature');
      expect(violations.single.edge.target,
          'lib/features/calendar/y.dart'); // нормализованный путь
    });

    test('core → features нарушает (кроме core/db)', () {
      final violations = findViolations({
        'lib/core/config/x.dart': "import '../../features/tracker/y.dart';",
      });
      expect(violations, hasLength(1));
      expect(violations.single.rule, 'core→features');
    });

    test('core/db → features разрешено (D-20)', () {
      final violations = findViolations({
        'lib/core/db/app_database.dart':
            "import '../../features/tracker/data/t.dart';",
      });
      expect(violations, isEmpty);
    });

    test('разрешённые связи молчат: feature→shared, feature→core, '
        'core→core, внешние пакеты', () {
      final violations = findViolations({
        'lib/features/tracker/x.dart': [
          "import 'package:flutter/material.dart';",
          "import '../../shared/utils/format.dart';",
          "import '../../core/db/app_database.dart';",
          "import 'sibling.dart';",
        ].join('\n'),
        'lib/features/tracker/sibling.dart':
            "import 'package:dharma_toolkit/features/tracker/x.dart';",
      });
      expect(violations, isEmpty);
    });

    test('экспорт — тоже связь: re-export чужой фичи нарушает', () {
      final violations = findViolations({
        'lib/features/tracker/x.dart':
            "export 'package:dharma_toolkit/features/content/y.dart';",
      });
      expect(violations, hasLength(1));
    });

    test('закомментированный импорт не нарушение', () {
      final violations = findViolations({
        'lib/core/module/x.dart':
            "// import '../../features/tracker/y.dart'; (контракт)",
      });
      expect(violations, isEmpty);
    });
  });

  group('реальный код lib/', () {
    test('ни одна фича не импортирует другую фичу (D-5)', () {
      final violations = findViolations(readProjectFiles())
          .where((v) => v.rule == 'feature→feature')
          .toList();
      expect(
        violations,
        isEmpty,
        reason: 'прямые импорты между фичами запрещены:\n'
            '${violations.map((v) => v.describe()).join('\n')}',
      );
    });

    test('ядро не импортирует фичи, кроме core/db (принцип №1 + D-20)', () {
      final violations = findViolations(readProjectFiles())
          .where((v) => v.rule == 'core→features')
          .toList();
      expect(
        violations,
        isEmpty,
        reason: 'ядро знает о фичах только через точку агрегации схемы БД '
            'lib/core/db/ (D-20):\n'
            '${violations.map((v) => v.describe()).join('\n')}',
      );
    });

    test('слабление D-20 зафиксировано: точка агрегации — только core/db', () {
      // Единственный разрешённый путь ядро→фичи — lib/core/db/. Если кто-то
      // вынесет агрегацию в новый файл (core/database.dart и т.п.) или, что
      // хуже, добавит импорт фичи в core/config — красный тест выше.
      // Здесь — самостраховка: сам scanner обязан видеть файлы, иначе два
      // предыдущих теста проходили бы вакуумно.
      final files = readProjectFiles();
      expect(files, isNotEmpty);
      expect(files.keys.any((path) => path.startsWith('lib/core/db/')), isTrue);
    });
  });
}

/// Импорт-связь: файл-источник, нормализованный путь цели, директива.
class ImportEdge {
  final String source;
  final String target;
  final int line;
  final String directive;
  const ImportEdge(this.source, this.target, this.line, this.directive);
}

/// Нарушение архитектурного правила.
class Violation {
  final ImportEdge edge;
  final String rule;
  const Violation(this.edge, this.rule);

  String describe() =>
      '${edge.source}:${edge.line} — ${edge.directive} → ${edge.target} [$rule]';
}

/// Правила над снимком «путь → содержимое»: резолвит директивы и проверяет,
/// что связи между слоями нет. Используется и на синтетических наборах
/// (доказательство, что сторож ловит оба вида импортов), и на реальном lib/.
List<Violation> findViolations(Map<String, String> files) {
  final violations = <Violation>[];
  for (final entry in files.entries) {
    final edges = importEdges(entry.key, entry.value);
    for (final edge in edges) {
      final sourceFeature = featureOf(edge.source);
      final targetFeature = featureOf(edge.target);
      if (sourceFeature != null &&
          targetFeature != null &&
          sourceFeature != targetFeature) {
        violations.add(Violation(edge, 'feature→feature'));
        continue;
      }
      if (isCore(edge.source) && !isCoreDb(edge.source) && targetFeature != null) {
        violations.add(Violation(edge, 'core→features'));
      }
    }
  }
  return violations;
}

String? featureOf(String path) {
  const prefix = 'lib/features/';
  if (!path.startsWith(prefix)) return null;
  final rest = path.substring(prefix.length);
  final slash = rest.indexOf('/');
  return slash == -1 ? rest : rest.substring(0, slash);
}

bool isCore(String path) => path.startsWith('lib/core/');

bool isCoreDb(String path) => path.startsWith('lib/core/db/');

/// Снимок всех .dart файлов lib/: путь → содержимое.
Map<String, String> readProjectFiles() {
  final files = <String, String>{};
  final entities = Directory('lib')
      .listSync(recursive: true)
      .where((e) => e.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final entity in entities) {
    files[normalizePath(entity.path)] = File(entity.path).readAsStringSync();
  }
  return files;
}

/// Импорт-связи одного файла: import/export-директивы, резолвнутые в
/// нормализованные пути проекта. package:dharma_toolkit/… → lib/…;
/// относительные — от dirname источника с сворачиванием ../.
/// Внешние пакетные импорты игнорируются.
List<ImportEdge> importEdges(String path, String contents) {
  final edges = <ImportEdge>[];
  final lines = contents.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final directive = parseImportDirective(lines[i]);
    if (directive == null) continue;
    final target = resolveImport(directive, sourcePath: path);
    if (target != null) {
      edges.add(ImportEdge(path, target, i + 1, directive));
    }
  }
  return edges;
}

/// Директивы import/export (part не рассматриваем: part не создаёт связей
/// между модулями). Комментарий внутри строки не импортирует:
/// `// import ...` отфильтрован по ведущим `//`.
String? parseImportDirective(String line) {
  final trimmed = line.trimLeft();
  if (trimmed.startsWith('//')) return null;
  final match =
      RegExp('''^(?:import|export)\\s+["']([^"']+)["']''').firstMatch(trimmed);
  return match?.group(1);
}

/// Разрешение spec → путь проекта; null — вне проекта или не .dart.
String? resolveImport(String spec, {required String sourcePath}) {
  if (spec.startsWith('dart:')) return null;
  if (!spec.endsWith('.dart')) return null;
  if (spec.startsWith('package:')) {
    if (!spec.startsWith('package:dharma_toolkit/')) return null;
    return normalizePath(
        'lib/${spec.substring('package:dharma_toolkit/'.length)}');
  }
  // Относительный: от папки источника.
  final segments = <String>[
    ...sourcePath.split('/')..removeLast(),
    ...spec.split('/'),
  ];
  final stacked = <String>[];
  for (final segment in segments) {
    if (segment == '.' || segment.isEmpty) continue;
    if (segment == '..') {
      if (stacked.isEmpty) return null; // над lib/ — вне проекта
      stacked.removeLast();
    } else {
      stacked.add(segment);
    }
  }
  final joined = stacked.join('/');
  if (!joined.startsWith('lib/')) return null;
  return normalizePath(joined);
}

String normalizePath(String path) => path.replaceAll(r'\', '/');
