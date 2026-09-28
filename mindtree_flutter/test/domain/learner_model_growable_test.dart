import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mindtree_flutter/data/database/mindtree_db.dart';
import 'package:mindtree_flutter/data/database/mindtree_repository.dart';
import 'package:mindtree_flutter/domain/engines/learner_model_service.dart';
import 'package:mindtree_flutter/domain/models/models.dart';

/// Регрессия: `_masteriesOf` отдавал `const []`, когда строки learner_model
/// ещё нет. Он немодифицируемый, поэтому `_findOrCreate` → `list.add` падал
/// с «Cannot add to an unmodifiable list» на первом же обновлении мастери
/// по теме, у которой модель ещё не создана.
void main() {
  late MindtreeDb db;
  late MindtreeRepository repo;
  late LearnerModelService service;

  setUp(() async {
    db = MindtreeDb(NativeDatabase.memory());
    repo = MindtreeRepository(db);
    service = LearnerModelService(repo);
    await repo.createTopic(const Topic(id: 't1', name: 'Тема'));
    // Сознательно НЕ создаём learner_model — именно этот случай ронял код.
  });

  tearDown(() async {
    await db.close();
  });

  group('обновление мастери без существующей learner_model', () {
    test('updateMasteryDimensions не падает и создаёт мастери', () async {
      await service.updateMasteryDimensions('t1', 'n1~abcdef01', {
        'understanding': 0.6,
        'recall': 0.5,
      });

      final saved = await repo.getLearnerModel('t1');
      expect(saved, isNotNull);
      expect(
        saved!.conceptMasteries.map((m) => m.nodeId),
        contains('n1~abcdef01'),
      );
    });

    test('updateMasteryDimensions вызывается повторно без ошибок', () async {
      await service.updateMasteryDimensions('t1', 'n1~abcdef01', {
        'understanding': 0.3,
      });
      await service.updateMasteryDimensions('t1', 'n1~abcdef01', {
        'understanding': 0.8,
      });
      await service.updateMasteryDimensions('t1', 'n2~abcdef02', {
        'recall': 0.4,
      });

      final saved = await repo.getLearnerModel('t1');
      expect(saved!.conceptMasteries.length, 2);
    });

    test(
      'getConceptProfile по узлу без мастери возвращает null, а не падает',
      () async {
        expect(await service.getConceptProfile('t1', 'n1~abcdef01'), isNull);
      },
    );
  });
}
