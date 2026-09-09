import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mindtree_flutter/providers/current_topic.dart';
import 'ui/screens/analytics_screen.dart';
import 'ui/screens/diagnostic_screen.dart';
import 'ui/screens/final_assessment_screen.dart';
import 'ui/screens/focus_screen.dart';
import 'ui/screens/graph_screen.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/learner_model_screen.dart';
import 'ui/screens/milestones_screen.dart';
import 'ui/screens/new_topic_screen.dart';
import 'ui/screens/provider_config_screen.dart';
import 'ui/screens/quiz_screen.dart';
import 'ui/screens/review_screen.dart';
import 'ui/screens/session_screen.dart';
import 'ui/screens/topic_shell.dart';
import 'ui/screens/tutor_screen.dart';

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
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) => _topicTab(
        (topicId) => TopicShell(
          navigationShell: navigationShell,
          topicId: topicId,
        ),
      ),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/topic/graph',
              builder: (context, state) =>
                  _topicTab((topicId) => GraphScreen(topicId: topicId)),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/topic/focus',
              builder: (context, state) =>
                  _topicTab((topicId) => FocusScreen(topicId: topicId)),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/topic/session',
              builder: (context, state) =>
                  _topicTab((topicId) => SessionScreen(topicId: topicId)),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/topic/quiz',
              builder: (context, state) =>
                  _topicTab((topicId) => QuizScreen(topicId: topicId)),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/topic/tutor',
              builder: (context, state) =>
                  _topicTab((topicId) => TutorScreen(topicId: topicId)),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/topic/learner',
              builder: (context, state) =>
                  _topicTab((topicId) => LearnerModelScreen(topicId: topicId)),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/topic/diagnostic',
              builder: (context, state) =>
                  _topicTab((topicId) => DiagnosticScreen(topicId: topicId)),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/topic/milestones',
              builder: (context, state) =>
                  _topicTab((topicId) => MilestonesScreen(topicId: topicId)),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/topic/review',
              builder: (context, state) =>
                  _topicTab((topicId) => ReviewScreen(topicId: topicId)),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/topic/analytics',
              builder: (context, state) =>
                  _topicTab((topicId) => AnalyticsScreen(topicId: topicId)),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/topic/final',
              builder: (context, state) =>
                  _topicTab((topicId) => FinalAssessmentScreen(topicId: topicId)),
            ),
          ],
        ),
      ],
    ),
  ],
);