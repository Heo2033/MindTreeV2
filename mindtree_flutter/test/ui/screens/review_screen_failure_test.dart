import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mindtree_flutter/data/database/mindtree_db.dart';
import 'package:mindtree_flutter/data/database/mindtree_repository.dart';
import 'package:mindtree_flutter/domain/engines/review_scheduler.dart';
import 'package:mindtree_flutter/domain/models/models.dart';
import 'package:mindtree_flutter/providers/app_providers.dart';
import 'package:mindtree_flutter/providers/ui_stores.dart';
import 'package:mindtree_flutter/ui/screens/review_screen.dart';

const _topicId = 't1';
const _n1 = 'n1~ab01';

class FakeGraphNotifier extends GraphNotifier {
  FakeGraphNotifier(super.ref);

  @override
  Future<void> loadTopic(String id) async {}
}

/// Scheduler, у которого `onAnswered` всегда падает (LLM/БД недоступны) —
/// регрессия «ответ сгорает без сохранения в SRS».
class _FailingReviewScheduler extends ReviewScheduler {
  _FailingReviewScheduler(super.repo);

  @override
  Future<void> onAnswered(
    String topicId,
    String nodeId,
    String quality, {
    Map<String, double>? evidence,
    bool recordCareless = true,
  }) async {
    throw Exception('srs write failed');
  }

  @override
  Future<List<({String nodeId, String? dueAt})>> upcomingReviews(
    String topicId, {
    int limit = 10,
  }) async {
    return [(nodeId: _n1, dueAt: null)];
  }
}

/// Скип: фокус теста — потеря SRS-ответа, когда до scheduler дойти можно,
/// но запись падает. Провайдер репозитория не трогаем, scheduler подменяем.
void main() {
  testWidgets('падение onAnswered не «сжигает» карточку и показывает ошибку',
      (tester) async {
    final db = MindtreeDb(NativeDatabase.memory());
    final repo = MindtreeRepository(db);
    addTearDown(db.close);

    final container = ProviderContainer(overrides: [
      graphStoreProvider.overrideWith((ref) => FakeGraphNotifier(ref)),
      reviewSchedulerProvider.overrideWith(
        (ref) => _FailingReviewScheduler(repo),
      ),
    ]);
    addTearDown(container.dispose);

    container.read(graphStoreProvider.notifier).state = const GraphState(
      topicId: _topicId,
      topicName: 'Тема',
      nodes: [
        KnowledgeNode(
          id: _n1,
          topicId: _topicId,
          parentId: null,
          level: 1,
          label: 'Концепт',
          oneLiner: 'Определение',
          details: '',
          estimatedTimeMinutes: 5,
        ),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: ReviewScreen(topicId: _topicId)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Карточка показана — лицевая сторона.
    expect(find.text('Нажмите, чтобы увидеть ответ'), findsOneWidget);

    // Отвечаем «Знаю», но запись SRS падает.
    await tester.tap(find.text('Знаю'));
    await tester.pumpAndSettle();

    // Ошибка видна пользователю, повторение НЕ «сгорело» — карточка на месте,
    // и снова доступна оценка ответа.
    expect(find.textContaining('Не удалось сохранить ответ'), findsOneWidget);
    expect(find.text('Нажмите, чтобы увидеть ответ'), findsOneWidget);
    expect(find.text('Знаю'), findsOneWidget);
  });
}