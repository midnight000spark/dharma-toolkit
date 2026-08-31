import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/onboarding/presentation/screens/tradition_pick_screen.dart';
import 'features/tracker/presentation/screens/create_practice_screen.dart';
import 'features/tracker/presentation/screens/practice_count_screen.dart';
import 'features/tracker/presentation/screens/practice_list_screen.dart';
import 'shared/providers/app_providers.dart';

/// Маршрут одной практики: `/practice/<число>`.
final _practicePath = RegExp(r'^/practice/([^/]+)$');

/// Роутер приложения — точка сборки (корень lib/, вне features: композиционный
/// слой знает о фичах, сами фичи — друг о друге нет).
///
/// Правила (B-4):
/// - `/pick` — выбор традиции;
/// - `/` — список практик **активного пресета** (тег из провайдера, не литерал);
/// - если активного пресета нет — редирект на `/pick`.
///
/// Правила (B-7):
/// - нечисловой id на `/practice/<id>` — редирект на список, не `int.parse`;
/// - любой несуществующий маршрут — `_NotFoundScreen` с кнопкой «Назад»
///   через `errorBuilder`, а не падение.
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final hasActivePreset =
          ref.read(presetManagerProvider).activePreset != null;
      final picking = state.matchedLocation == '/pick';
      if (!hasActivePreset && !picking) return '/pick';
      if (hasActivePreset && picking) return '/';
      final match = _practicePath.firstMatch(state.matchedLocation);
      if (match != null && int.tryParse(match.group(1)!) == null) {
        return '/'; // B-7: deep link с мусорным id — на список.
      }
      return null;
    },
    errorBuilder: (context, state) =>
        _NotFoundScreen(location: state.uri.toString()),
    routes: [
      GoRoute(
        path: '/pick',
        builder: (context, state) => const TraditionPickScreen(),
      ),
      GoRoute(
        path: '/',
        builder: (context, state) => Consumer(
          builder: (context, ref, _) => PracticeListScreen(
            traditionTag: ref.watch(activeTraditionTagProvider),
          ),
        ),
      ),
      GoRoute(
        path: '/create',
        builder: (context, state) => Consumer(
          builder: (context, ref, _) => CreatePracticeScreen(
            traditionTag: ref.watch(activeTraditionTagProvider),
          ),
        ),
      ),
      GoRoute(
        path: '/practice/:id',
        builder: (context, state) {
          final id = int.tryParse(state.pathParameters['id'] ?? '');
          if (id == null) {
            // До сюда редирект обычно не пропускает; защита второго слоя.
            return _NotFoundScreen(location: state.uri.toString());
          }
          return PracticeCountScreen(practiceId: id);
        },
      ),
    ],
  );
});

/// Экран неизвестного маршрута (B-7): вместо падения — внятное сообщение
/// и кнопка «Назад», уводящая на список (редирект сам решит, `/` или `/pick`).
class _NotFoundScreen extends StatelessWidget {
  final String location;

  const _NotFoundScreen({required this.location});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Не найдено')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Страница не найдена'),
              Text(location,
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => context.go('/'),
                child: const Text('Назад'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
