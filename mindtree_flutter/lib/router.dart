import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mindtree_flutter/providers/current_topic.dart';
import 'package:mindtree_flutter/ui/nav/topic_nav.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/more_screen.dart';
import 'ui/screens/new_topic_screen.dart';
import 'ui/screens/provider_config_screen.dart';
import 'ui/screens/topic_shell.dart';

/// Builds a screen widget passing the currently-open topic id from
/// [currentTopicIdProvider] into its `topicId` constructor parameter.
Widget _topicTab(Widget Function(String topicId) builder) {
  return Consumer(
    builder: (context, ref, _) => builder(ref.watch(currentTopicIdProvider)),
  );
}

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: '/new',
      builder: (context, state) => const NewTopicScreen(),
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const ProviderConfigScreen(),
    ),

    // Пути предыдущей версии навигации: оставляем рабочими редиректами,
    // чтобы не сломать deep links и сохранённые закладки.
    for (final entry in kLegacyTopicRedirects.entries)
      GoRoute(
        path: entry.key,
        redirect: (context, state) => entry.value,
      ),

    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) => _topicTab(
        (topicId) => TopicShell(
          navigationShell: navigationShell,
          topicId: topicId,
          location: state.uri.path,
        ),
      ),
      branches: [
        // Разделы темы: по одной ветке на раздел, пункты — вложенные маршруты.
        for (final section in kTopicSections)
          StatefulShellBranch(
            routes: [
              for (final item in section.items)
                GoRoute(
                  path: item.path,
                  builder: (context, state) =>
                      _topicTab((topicId) => item.builder(topicId)),
                ),
            ],
          ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: kMorePath,
              builder: (context, state) => const MoreScreen(),
            ),
          ],
        ),
      ],
    ),
  ],
);
