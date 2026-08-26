import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Architectural guard tests enforcing module isolation (D-5).
///
/// These tests scan the source tree and fail the build if any feature module
/// imports another feature module directly. Features must communicate only
/// through core (event bus, shared interfaces).
void main() {
  test('features do not import each other', () async {
    final featuresDir = Directory('lib/features');
    if (!await featuresDir.exists()) return; // no features yet — skip

    final violations = <String>[];

    for (final feature in await featuresDir.list().toList()) {
      if (feature is! Directory) continue;
      final featureName = feature.uri.pathSegments
          .where((s) => s.isNotEmpty)
          .last;

      await for (final entity in feature.list(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final content = await entity.readAsString();

        // Look for imports like 'package:dharma_toolkit/features/<other>/'
        final importRegex = RegExp(
          r'''import\s+['"]package:dharma_toolkit/features/(\w+)/''',
        );
        for (final match in importRegex.allMatches(content)) {
          final imported = match.group(1);
          if (imported != featureName) {
            violations.add(
              '${entity.path}: imports features/$imported '
              'but lives in features/$featureName',
            );
          }
        }
      }
    }

    expect(violations, isEmpty,
        reason: 'Found module isolation violations:\n${violations.join("\n")}');
  });

  test('features are free to import core and shared', () {
    // Placeholder — passes now while features are empty.
    // Will be expanded when feature modules are implemented.
    expect(true, isTrue);
  });
}
