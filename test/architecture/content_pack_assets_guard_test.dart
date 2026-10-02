/// W32/T5 (S2, H-08): каталоги паков объявлены в `pubspec.yaml`, ключи
/// пресетов указывают на существующие файлы, а файлы в каталогах объявлены
/// пресетами.
///
/// Почему сторож: каталоги ассетов Flutter **не рекурсивны**, а
/// незадекларированный каталог в release-сборку не попадает — первый реальный
/// контент-пак молча оказался бы вне bundle, а загрузчик отрапортовал бы
/// «файл пака недоступен». Обратная сторона: файл-сирота в каталоге паков или
/// ключ с опечаткой/вне namespace (H-08) — ассет, который никто не прочитает.
///
/// T5 (tests-quality-1) исполнен здесь вместе с публикацией W32 — пакету
/// tests-quality-1 дублировать не нужно.
///
/// Аттестован мутациями (warning-3c, блок 11): снятая декларация каталога,
/// фальшивый ключ пресета, файл-сирота, вложенный каталог — все красные.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _pubspecPath = 'pubspec.yaml';
const _manifestPath = 'presets/index.json';

/// Каталоги паков: (поле пресета, префикс ключа).
const _packSources = <({String presetField, String prefix})>[
  (presetField: 'contentPacks', prefix: 'assets/content_packs/'),
  (presetField: 'eventPacks', prefix: 'assets/events/'),
];

/// Минимум, который обязан быть объявлен: без этого паки не доедут.
const _expectedDirs = <String>[
  'presets/',
  'assets/content_packs/',
  'assets/events/',
];

/// Скан секции `assets:` из `pubspec.yaml`: строки вида `    - <путь>`.
Set<String> _declaredAssetDirs(String source) {
  final declared = <String>{};
  var inAssets = false;
  for (final line in const LineSplitter().convert(source)) {
    if (RegExp(r'^  assets:\s*$').hasMatch(line)) {
      inAssets = true;
      continue;
    }
    if (!inAssets) continue;
    final entry = RegExp(r'^    - (.+)$').firstMatch(line);
    if (entry != null) {
      declared.add(entry.group(1)!.trim());
      continue;
    }
    if (line.trim().isEmpty) continue;
    if (!line.startsWith('    ')) inAssets = false;
  }
  return declared;
}

void main() {
  test('W32/T5: каталоги паков объявлены и покрыты ключами пресетов', () {
    final declared = _declaredAssetDirs(File(_pubspecPath).readAsStringSync());
    // Самостраховка: ослепший скан не имеет права молча «проходить».
    expect(declared, isNotEmpty, reason: 'скан секции assets: пуст — сторож ослеп');
    expect(
      declared,
      containsAll(_expectedDirs),
      reason: 'W32: каталог пака не объявлен в pubspec.yaml — '
          'release-сборка его не увидит',
    );

    // (1) Объявленный каталог обязан существовать: из несуществующего
    // каталога Flutter ассеты не собирает.
    for (final dir in _expectedDirs) {
      expect(Directory(dir).existsSync(), isTrue,
          reason: 'каталог $dir объявлен, но его нет на диске');
    }

    // (2) Пресеты: каждый ключ — прямой ребёнок своего каталога, файл есть.
    final manifest = jsonDecode(File(_manifestPath).readAsStringSync())
        as Map<String, dynamic>;
    final presetIds = (manifest['presets'] as List).cast<String>();
    expect(presetIds, isNotEmpty, reason: 'манифест пуст — сторож ослеп');

    final referenced = <String, Set<String>>{
      for (final source in _packSources) source.prefix: <String>{},
    };
    for (final id in presetIds) {
      final preset = jsonDecode(File('presets/$id.json').readAsStringSync())
          as Map<String, dynamic>;
      for (final source in _packSources) {
        final keys = (preset[source.presetField] as List).cast<String>();
        for (final key in keys) {
          expect(
            key.startsWith(source.prefix),
            isTrue,
            reason: 'W32: ключ "$key" вне namespace ${source.prefix} (H-08)',
          );
          final relative = key.substring(source.prefix.length);
          expect(relative.contains('/'), isFalse,
              reason: 'W32: $key — вложенный путь; каталоги ассетов Flutter '
                  'не рекурсивны');
          expect(
            File(key).existsSync(),
            isTrue,
            reason: 'W32: пресет $id объявляет "$key" — файла нет, '
                'в bundle попадёт пустота',
          );
          referenced[source.prefix]!.add(key);
        }
      }
    }

    // (3) Обратная сторона: каждый json-файл каталога объявлен пресетом,
    // а вложенных каталогов быть не должно (они не попадут в bundle).
    for (final source in _packSources) {
      final entries = Directory(source.prefix).listSync();
      final nested = entries.whereType<Directory>().toList();
      expect(
        nested,
        isEmpty,
        reason: 'W32: вложенный каталог ${nested.map((d) => d.path)} не '
            'попадёт в bundle — каталоги ассетов не рекурсивны',
      );
      final files = entries
          .whereType<File>()
          .where((f) => !f.uri.pathSegments.last.startsWith('.'))
          .where((f) => f.path.endsWith('.json'));
      for (final file in files) {
        expect(
          referenced[source.prefix],
          contains(file.path),
          reason: 'W32: ${file.path} есть в каталоге, но ни одним пресетом '
              'не объявлен — мёртвый ассет',
        );
      }
    }
  });
}
