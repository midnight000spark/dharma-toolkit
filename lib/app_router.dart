import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/onboarding/presentation/screens/tradition_pick_screen.dart';
import 'features/tracker/presentation/screens/create_practice_screen.dart';
import 'features/tracker/presentation/screens/practice_count_screen.dart';
import 'features/tracker/presentation/screens/practice_list_screen.dart';
import 'shared/providers/app_providers.dart';

/// Роутер приложения — точка сборки (corень lib/, вне features: композиционный
/// слой знает о фичах, сами фичи — друг о друге нет).
///
/// Правила (B-4):
/// - `/pick` — выбор традиции;
/// - `/` — список практик **активного пресета** (тег из провайдера, не литерал);
/// - если активного пресета нет — редирект на `/pick`.
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final hasActivePreset =
          ref.read(presetManagerProvider).activePreset != null;
      final picking = state.matchedLocation == '/pick';
      if (!hasActivePreset && !picking) return '/pick';
      if (hasActivePreset && picking) return '/';
      return null;
    },
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
          final id = int.parse(state.pathParameters['id']!);
          return PracticeCountScreen(practiceId: id);
        },
      ),
    ],
  );
});
