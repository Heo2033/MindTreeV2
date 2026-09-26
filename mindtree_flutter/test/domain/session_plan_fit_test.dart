import 'package:flutter_test/flutter_test.dart';

import 'package:mindtree_flutter/domain/engines/curriculum_engine.dart';
import 'package:mindtree_flutter/domain/models/models.dart';

CurriculumItem _item({
  required String id,
  required int order,
  required int minutes,
}) =>
    CurriculumItem(
      id: id,
      nodeId: 'node_$id',
      label: 'Раздел $id',
      order: order,
      type: CurriculumItemType.explain,
      estimatedMinutes: minutes,
    );

void main() {
  group('fitPlanToBudget', () {
    test('пустой план остаётся пустым', () {
      expect(fitPlanToBudget(const [], 30), isEmpty);
    });

    test('план укладывается в бюджет: сумма ≤ бюджета', () {
      final items = [
        _item(id: 'a', order: 0, minutes: 10),
        _item(id: 'b', order: 1, minutes: 15),
        _item(id: 'c', order: 2, minutes: 20),
        _item(id: 'd', order: 3, minutes: 5),
      ];
      final fitted = fitPlanToBudget(items, 30);

      // 10+15=25 <= 30; следующий (20) уже не влезает → break, хвост отбрасывается.
      expect(fitted, hasLength(2));
      expect([for (final it in fitted) it.id], ['a', 'b']);
      final total =
          fitted.fold<int>(0, (acc, it) => acc + it.estimatedMinutes);
      expect(total, lessThanOrEqualTo(30));
    });

    test('первые пункты идут по порядку (order), а не по входному списку', () {
      final items = [
        _item(id: 'z', order: 3, minutes: 5),
        _item(id: 'a', order: 0, minutes: 5),
        _item(id: 'm', order: 1, minutes: 5),
        _item(id: 'n', order: 2, minutes: 5),
      ];
      final fitted = fitPlanToBudget(items, 15);

      expect([for (final it in fitted) it.id], ['a', 'm', 'n']);
    });

    test('первый пункт сохраняется, даже если сам длиннее бюджета', () {
      final items = [_item(id: 'big', order: 0, minutes: 120)];
      final fitted = fitPlanToBudget(items, 30);

      expect(fitted, hasLength(1));
      expect(fitted.single.id, 'big');
    });

    test('длинный первый пункт разрешён, остальные уже не влезают', () {
      final items = [
        _item(id: 'big', order: 0, minutes: 40),
        _item(id: 'small', order: 1, minutes: 5),
      ];
      final fitted = fitPlanToBudget(items, 30);

      expect(fitted, hasLength(1));
      expect(fitted.single.id, 'big');
    });

    test('не модифицирует переданный список', () {
      final items = [
        _item(id: 'a', order: 1, minutes: 5),
        _item(id: 'b', order: 0, minutes: 5),
      ];
      fitPlanToBudget(items, 30);

      expect([for (final it in items) it.id], ['a', 'b']);
    });
  });
}