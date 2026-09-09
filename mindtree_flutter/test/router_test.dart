import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:mindtree_flutter/router.dart';

/// Regression test: go_router forbids parameterized default locations on
/// StatefulShellBranch. `appRouter` construction used to throw
/// "The default location of a StatefulShellBranch cannot be a parameterized
/// route" because all branch routes were `/topic/:topicId/...`.
void main() {
  test('appRouter construction does not assert', () {
    expect(() => appRouter, returnsNormally);
  });

  group('topic routes', () {
    test('every branch default location is parameter-free', () {
      String? check(RouteBase route) {
        if (route is GoRoute) {
          if (route.path.contains(':')) {
            return route.path;
          }
          for (final child in route.routes) {
            final bad = check(child);
            if (bad != null) return bad;
          }
        }
        if (route is StatefulShellRoute) {
          for (final branch in route.branches) {
            for (final child in branch.routes) {
              final bad = check(child);
              if (bad != null) return bad;
            }
          }
        }
        return null;
      }

      for (final route in appRouter.configuration.routes) {
        expect(check(route), isNull,
            reason: 'go_router forbids parameterized branch default locations');
      }
    });
  });
}