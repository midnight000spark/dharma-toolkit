import 'package:go_router/go_router.dart';

import 'screens/practice_list_screen.dart';
import 'screens/practice_count_screen.dart';
import 'screens/create_practice_screen.dart';

/// Маршруты для модуля tracker
final trackerRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const PracticeListScreen(traditionTag: 'sample'),
    ),
    GoRoute(
      path: '/create',
      builder: (context, state) => const CreatePracticeScreen(traditionTag: 'sample'),
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
