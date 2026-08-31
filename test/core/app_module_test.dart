import 'package:dharma_toolkit/core/module/app_module.dart';
import 'package:dharma_toolkit/core/module/module_registry.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stub implementation used to verify the [AppModule] contract.
class _StubModule implements AppModule {
  _StubModule({
    this.id = 'stub',
    this.name = 'Stub Module',
    this.version = '1.0.0',
  });

  int initCallCount = 0;
  int disposeCallCount = 0;

  @override
  final String id;

  @override
  final String name;

  @override
  final String version;

  @override
  Future<void> init() async {
    initCallCount++;
  }

  @override
  Future<void> dispose() async {
    disposeCallCount++;
  }
}

void main() {
  group('AppModule interface', () {
    test('has all 5 required members', () {
      final module = _StubModule();

      // Verify all 5 members exist and are accessible
      expect(module.id, isA<String>());
      expect(module.name, isA<String>());
      expect(module.version, isA<String>());
      expect(module.init, isA<Function>());
      expect(module.dispose, isA<Function>());
      expect(module, isA<AppModule>());
    });

    test('can be implemented by a concrete class', () {
      final module = _StubModule(
        id: 'test_module',
        name: 'Test Module',
        version: '2.3.1',
      );

      expect(module.id, 'test_module');
      expect(module.name, 'Test Module');
      expect(module.version, '2.3.1');
    });
  });

  group('ModuleRegistry', () {
    setUp(() async {
      // Reset singleton state between tests
      await ModuleRegistry.instance.disposeAll();
    });

    test('registers module and returns it by id', () {
      final registry = ModuleRegistry.instance;
      final module = _StubModule(id: 'calendar');

      registry.register(module);

      expect(registry.get('calendar'), same(module));
      expect(registry.get('nonexistent'), isNull);
    });

    test('throws ArgumentError on duplicate id registration', () {
      final registry = ModuleRegistry.instance;
      final module1 = _StubModule(id: 'tracker');
      final module2 = _StubModule(id: 'tracker');

      registry.register(module1);

      expect(
        () => registry.register(module2),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('initAll calls init on each module exactly once', () async {
      final registry = ModuleRegistry.instance;
      final module1 = _StubModule(id: 'a');
      final module2 = _StubModule(id: 'b');

      registry.register(module1);
      registry.register(module2);

      await registry.initAll();

      expect(module1.initCallCount, 1);
      expect(module2.initCallCount, 1);

      // Calling initAll again should be a no-op
      await registry.initAll();
      expect(module1.initCallCount, 1);
      expect(module2.initCallCount, 1);
    });

    test('disposeAll calls dispose in reverse registration order', () async {
      final registry = ModuleRegistry.instance;
      final disposeOrder = <String>[];

      final module1 = _OrderTrackingModule('first', disposeOrder);
      final module2 = _OrderTrackingModule('second', disposeOrder);
      final module3 = _OrderTrackingModule('third', disposeOrder);

      registry.register(module1);
      registry.register(module2);
      registry.register(module3);

      await registry.initAll();
      await registry.disposeAll();

      // Should be disposed in reverse: third, second, first
      expect(disposeOrder, ['third', 'second', 'first']);
    });

    test('disposeAll доводит очистку до конца, даже если dispose упал (6.2)',
        () async {
      final registry = ModuleRegistry.instance;
      final disposeOrder = <String>[];

      registry.register(_OrderTrackingModule('a', disposeOrder));
      registry.register(_DisposeFailingModule(disposeOrder));
      registry.register(_OrderTrackingModule('c', disposeOrder));
      await registry.initAll();

      // Первая ошибка переподнимается — отказ не должен тонуть молча.
      await expectLater(registry.disposeAll(), throwsStateError);

      // Но остальные модули диспожены, а реестр очищен: повторный bootstrap
      // (retry на экране восстановления) возможен.
      expect(disposeOrder, containsAllInOrder(['c', 'a']));
      expect(registry.all, isEmpty);
      // Реестр снова пригоден к регистрации.
      registry.register(_StubModule(id: 'after'));
      expect(registry.get('after'), isNotNull);
    });
  });
}

/// Модуль, у которого [dispose] всегда бросает (тест 6.2).
class _DisposeFailingModule implements AppModule {
  _DisposeFailingModule(this.disposeOrder);

  final List<String> disposeOrder;

  @override
  String get id => 'boom';

  @override
  String get name => 'Boom';

  @override
  String get version => '1.0.0';

  @override
  Future<void> init() async {}

  @override
  Future<void> dispose() async {
    disposeOrder.add(id);
    throw StateError('dispose упал');
  }
}

/// Helper module that tracks disposal order.
class _OrderTrackingModule implements AppModule {
  _OrderTrackingModule(this.id, this.disposeOrder);

  @override
  final String id;

  @override
  String get name => id;

  @override
  String get version => '1.0.0';

  final List<String> disposeOrder;

  @override
  Future<void> init() async {}

  @override
  Future<void> dispose() async {
    disposeOrder.add(id);
  }
}
