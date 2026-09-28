import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:mindtree_flutter/router.dart';
import 'package:mindtree_flutter/ui/nav/topic_nav.dart';
import 'package:mindtree_flutter/ui/screens/more_screen.dart';

/// Регрессия: до редизайна было 11 вкладок верхнего уровня. Сейчас их 4
/// (Учить / Проверить / Прогресс / Ещё), но ни один экран не должен
/// стать недостижимым, а старые deep links — обязаны работать.
void main() {
  /// Собирает все объявленные пути реальной таблицы маршрутов.
  Map<String, GoRoute> declaredRoutes() {
    final out = <String, GoRoute>{};

    void walk(RouteBase route) {
      if (route is GoRoute) {
        out[route.path] = route;
        for (final child in route.routes) {
          walk(child);
        }
      } else if (route is StatefulShellRoute) {
        for (final branch in route.branches) {
          for (final child in branch.routes) {
            walk(child);
          }
        }
      } else if (route is ShellRoute) {
        for (final child in route.routes) {
          walk(child);
        }
      }
    }

    for (final route in appRouter.configuration.routes) {
      walk(route);
    }
    return out;
  }

  StatefulShellRoute topicShell() =>
      appRouter.configuration.routes.whereType<StatefulShellRoute>().single;

  group('структура навигации', () {
    test('в боковой навигации ровно 4 раздела', () {
      expect(
        kTopicSectionsWithMore.map((s) => s.label).toList(),
        ['Учить', 'Проверить', 'Прогресс', 'Ещё'],
      );
    });

    test('все 11 экранов темы остались достижимы', () {
      // 4 (Учить) + 3 (Проверить) + 4 (Прогресс)
      expect(kAllTopicItems.length, 11);
      expect(
        kAllTopicItems.map((i) => i.path).toSet().length,
        11,
        reason: 'пути пунктов должны быть уникальны',
      );
    });

    test('каждый пункт принадлежит ровно одному разделу', () {
      for (final item in kAllTopicItems) {
        expect(sectionForPath(item.path), isNotNull,
            reason: 'пункт ${item.path} не привязан к разделу');
      }
      // Путь «Ещё» не должен считаться пунктом раздела.
      expect(sectionForPath(kMorePath), isNull);
    });

    test('у каждого раздела с несколькими пунктами есть переключатель', () {
      for (final section in kTopicSections) {
        expect(section.hasSubNav, section.items.length > 1);
        expect(section.items, isNotEmpty);
      }
    });
  });

  group('таблица маршрутов', () {
    test('в shell ровно 4 ветки', () {
      expect(topicShell().branches.length, 4);
    });

    test('все новые пути объявлены в appRouter', () {
      final routes = declaredRoutes();
      for (final item in kAllTopicItems) {
        expect(routes.containsKey(item.path), isTrue,
            reason: 'путь ${item.path} не объявлен в роутере');
      }
      expect(routes.containsKey(kMorePath), isTrue);
      expect(routes[kMorePath]!.builder, isNotNull);
    });

    test('объявленный путь не содержит параметров', () {
      for (final path in declaredRoutes().keys) {
        expect(path.contains(':'), isFalse,
            reason: 'go_router не допускает параметры в ветках shell');
      }
    });

    test('старые пути остались и ведут на редирект', () {
      final routes = declaredRoutes();
      for (final entry in kLegacyTopicRedirects.entries) {
        final route = routes[entry.key];
        expect(route, isNotNull,
            reason: 'старый путь ${entry.key} исчез из роутера');
        expect(route!.redirect, isNotNull,
            reason: 'старый путь ${entry.key} не перенаправляет в '
                '${entry.value}');
      }
    });
  });

  group('целостность редиректов', () {
    test('цели редиректов существуют в реестре', () {
      final known = {
        ...kAllTopicItems.map((i) => i.path),
        kMorePath,
      };
      for (final target in kLegacyTopicRedirects.values) {
        expect(known, contains(target),
            reason: 'редирект ведёт в неизвестный путь $target');
      }
    });

    test('все 11 старых путей покрыты редиректами', () {
      expect(kLegacyTopicRedirects.length, 11);
    });
  });

  group('экран «Ещё»', () {
    testWidgets('перечисляет все пункты разделов и ведёт в них',
        (tester) async {
      // Высокая поверхность, чтобы ленивый ListView построил весь список.
      tester.view.physicalSize = const Size(1000, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final router = GoRouter(routes: [
        GoRoute(path: '/', builder: (_, _) => const MoreScreen()),
        GoRoute(path: '/settings', builder: (_, _) => const SizedBox()),
        GoRoute(path: kMorePath, builder: (_, _) => const MoreScreen()),
        for (final item in kAllTopicItems)
          GoRoute(path: item.path, builder: (_, _) => const MoreScreen()),
      ]);

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      for (final item in kAllTopicItems) {
        expect(find.text(item.label), findsOneWidget,
            reason: 'пункт ${item.label} не виден в «Ещё»');
      }
      expect(find.text('Настройки провайдера'), findsOneWidget);
      expect(find.text('К списку тем'), findsOneWidget);

      // Переход из каталога работает.
      await tester.tap(find.text('Граф'));
      await tester.pumpAndSettle();
      expect(router.routerDelegate.currentConfiguration.uri.path,
          '/topic/learn/graph');
    });
  });
}
