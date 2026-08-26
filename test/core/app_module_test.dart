import 'package:dharma_toolkit/core/module/app_module.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stub implementation used only to verify the [AppModule] contract.
class _StubModule implements AppModule {
  @override
  String get id => 'stub';

  @override
  String get name => 'Stub Module';

  @override
  Future<void> init() async {}

  @override
  Future<void> dispose() async {}
}

void main() {
  group('AppModule interface', () {
    test('can be implemented by a concrete class', () {
      final module = _StubModule();

      expect(module.id, 'stub');
      expect(module.name, 'Stub Module');
      expect(module, isA<AppModule>());
    });

    test('init and dispose run without error', () async {
      final module = _StubModule();

      await module.init();
      await module.dispose();

      // No exceptions means the contract is satisfied.
      expect(true, isTrue);
    });
  });
}
