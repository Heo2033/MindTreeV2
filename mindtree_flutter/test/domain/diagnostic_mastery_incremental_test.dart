import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindtree_flutter/data/database/mindtree_db.dart';
import 'package:mindtree_flutter/data/database/mindtree_repository.dart';
import 'package:mindtree_flutter/data/llm/client.dart' as llm_client;
import 'package:mindtree_flutter/data/llm/scheduler.dart';
import 'package:mindtree_flutter/domain/engines/diagnostic_engine.dart';
import 'package:mindtree_flutter/domain/engines/engine_factory.dart';
import 'package:mindtree_flutter/domain/engines/learner_model_service.dart';
import 'package:mindtree_flutter/domain/engines/mastery_engine.dart';
import 'package:mindtree_flutter/domain/models/models.dart';

import '../../tool/probe/fake_llm.dart';

const _topicId = 't1';
const _nodeId = 'n1~abc12345';
const _node2Id = 'n2~deadbeef';

/// Детерминированный fake-транспорт: mastery-ответ можно подменить целиком.
class _MasteryLlm {
  final FakeLlm fake = FakeLlm();
  Map<String, dynamic>? masteryResult;

  /// Маркер mastery-промпта — общий с `PromptKind.mastery`.
  static const _masteryMarker =
      'Оцени по ответам пользователя, достиг ли он целевого уровня';

  Future<llm_client.LLMResult> invoke(
    llm_client.LLMConfig cfg,
    String prompt, {
    String? model,
    double? temperature,
    int? seed,
  }) async {
    if (prompt.contains(_masteryMarker)) {
      final result = masteryResult ??
          {
            'concepts': <Map<String, dynamic>>[],
            'enough': false,
            'overall_level': 'awareness',
            'gaps': <String>[],
          };
      return llm_client.LLMResult(
        text: jsonEncode(result),
        usage: const llm_client.LLMUsage(inputTokens: 1, outputTokens: 1),
      );
    }
    return fake.invoke(
      cfg,
      prompt,
      model: model,
      temperature: temperature,
      seed: seed,
    );
  }
}

void main() {
  late MindtreeDb db;
  late MindtreeRepository repo;
  late MindtreeEngines engines;
  late _MasteryLlm llm;

  setUp(() async {
    db = MindtreeDb(NativeDatabase.memory());
    repo = MindtreeRepository(db);
    llm = _MasteryLlm();
    engines = buildEngines(
      repo: repo,
      configProvider: () => const llm_client.LLMConfig(
        isMock: true,
        temperature: 0,
        numCtx: 16384,
      ),
      schedulerConfig: const SchedulerConfig(
        maxRPM: 100000,
        maxRPD: 100000,
        maxConcurrency: 1,
        maxRetries: 0,
      ),
      llmCall: (cfg, prompt, {model, temperature, seed}) =>
          llm.invoke(cfg, prompt, model: model, temperature: temperature, seed: seed),
    );
    await repo.createTopic(const Topic(id: _topicId, name: 'Теорема остановки'));
    await repo.insertNodes([
      KnowledgeNode(
        id: _nodeId,
        topicId: _topicId,
        parentId: null,
        level: 1,
        label: 'Теорема остановки',
        oneLiner: 'Одно утверждение об итеративных вычислениях.',
        details: 'Подробности корня.',
      ),
      KnowledgeNode(
        id: _node2Id,
        topicId: _topicId,
        parentId: _nodeId,
        level: 2,
        label: 'Вычислимая функция',
        oneLiner: 'Функция, для которой существует алгоритм вычисления.',
        details: 'Подробности понятия.',
      ),
    ]);
  });

  tearDown(() async {
    await db.close();
  });

  Future<ConceptProfile?> profile(String nodeId) =>
      engines.learnerModel.getConceptProfile(nodeId, _topicId);

  /// Единый набор `MasteryItem` для двух концептов.
  List<MasteryItem> items() => [
        MasteryItem(
          nodeId: _nodeId,
          label: 'Теорема остановки',
          type: 'recall',
          userAnswer: 'утверждение о свойствах вычислений',
        ),
        MasteryItem(
          nodeId: _node2Id,
          label: 'Вычислимая функция',
          type: 'recall',
          userAnswer: 'функция с алгоритмом',
        ),
      ];

  Map<String, dynamic> concept(
    String nodeId, {
    double understanding = 0.8,
    double recall = 0.6,
    double application = 0.4,
    double transfer = 0.2,
    double confidence = 0.8,
    Map<String, dynamic>? misconception,
  }) =>
      {
        'nodeId': nodeId,
        'understanding': understanding,
        'recall': recall,
        'application': application,
        'transfer': transfer,
        'confidence': confidence,
        'misconception': misconception,
      };

  group('diagnostic.evaluate: инкрементальная запись', () {
    test('блендит с накопленным, а не пишет константы 0.6/0.6/0.4/0.3',
        () async {
      await engines.learnerModel.updateMasteryDimensions(
        _topicId,
        _nodeId,
        {dimRecall: 0.9, dimUnderstanding: 0.9},
      );

      final result = await engines.diagnostic.evaluate(_topicId, [
        DiagnosticAnswer(
          questionId: 'q1',
          nodeId: _nodeId,
          selectedIndex: 1,
          correctIndex: 1,
        ),
      ]);

      expect(result.knownConcepts, [_nodeId]);
      final p = (await profile(_nodeId))!;
      // Все измеренные dimensions сдвигаются ровно наполовину к свидетельству.
      expect(p.recall, closeTo(0.95, 1e-9));
      expect(p.understanding, closeTo(0.95, 1e-9));
      // Не измеренные диагностикой dimensions не придуманы.
      expect(p.application, 0);
      expect(p.transfer, 0);
    });

    test('один низкий балл не опускает уже достигнутый уровень', () async {
      await engines.learnerModel.raiseOverallLevel(
        _topicId,
        MasteryLevel.solidUnderstanding,
        asInitial: true,
      );

      final result = await engines.diagnostic.evaluate(_topicId, [
        DiagnosticAnswer(
          questionId: 'q1',
          nodeId: _nodeId,
          selectedIndex: 0,
          correctIndex: 1,
        ),
      ]);

      expect(result.currentLevel, 'awareness');
      expect(
        await engines.learnerModel.getCurrentLevel(_topicId),
        MasteryLevel.solidUnderstanding,
        reason: 'диагностика не имеет права стирать ранее показанный уровень',
      );
      expect(
        await engines.learnerModel.getInitialLevel(_topicId),
        MasteryLevel.solidUnderstanding,
        reason: 'стартовая точка зафиксирована один раз',
      );
    });
  });

  group('mastery.evaluate: инкрементальная запись и мисконцепции', () {
    test('LLM-оценки блендятся с историей концепта, а не перезаписывают её',
        () async {
      await engines.learnerModel.updateMasteryDimensions(
        _topicId,
        _nodeId,
        {
          dimUnderstanding: 0.9,
          dimRecall: 0.9,
          dimApplication: 0.9,
          dimTransfer: 0.9,
        },
      );
      llm.masteryResult = {
        'concepts': [
          concept(
            _nodeId,
            understanding: 0.8,
            recall: 0.6,
            application: 0.4,
            transfer: 0.2,
          ),
        ],
        'enough': true,
        'overall_level': 'solid_understanding',
        'gaps': <String>[],
      };

      await engines.mastery.evaluate(
        _topicId,
        items().take(1).toList(),
        'solid_understanding',
      );

      final p = (await profile(_nodeId))!;
      expect(p.understanding, closeTo(0.85, 1e-9));
      expect(p.recall, closeTo(0.75, 1e-9));
      expect(p.application, closeTo(0.65, 1e-9));
      expect(p.transfer, closeTo(0.55, 1e-9),
          reason: 'не перезапись константами LLM, а полусмесь с историей');
    });

    test('пустое описание мисконцепции заменяется текстом по типу', () async {
      llm.masteryResult = {
        'concepts': [
          concept(_nodeId, misconception: {
            'type': 'incomplete',
            'description': '',
          }),
          concept(_node2Id),
        ],
        'enough': false,
        'overall_level': 'basic_understanding',
        'gaps': <String>[],
      };

      await engines.mastery.evaluate(
        _topicId,
        items(),
        'solid_understanding',
      );

      final p = (await profile(_nodeId))!;
      expect(p.errors, hasLength(1));
      expect(p.errors.single.nodeId, _nodeId);
      expect(p.errors.single.type, MisconceptionType.incomplete);
      expect(
        p.errors.single.description,
        MisconceptionType.incomplete.defaultDescription,
        reason: 'в БД не бывает пустого description',
      );
      expect(p.errors.single.description, isNotEmpty);
    });

    test('неизвестный тип мисконцепции не пишется вовсе', () async {
      llm.masteryResult = {
        'concepts': [
          concept(_nodeId, misconception: {
            'type': 'nonsense_type',
            'description': 'непонятная ошибка',
          }),
          concept(_node2Id),
        ],
        'enough': false,
        'overall_level': 'basic_understanding',
        'gaps': <String>[],
      };

      await engines.mastery.evaluate(
        _topicId,
        items(),
        'solid_understanding',
      );

      expect((await profile(_nodeId))!.errors, isEmpty,
          reason: 'тип не распознан — ошибаться нечем помогать');
    });

    test('низкие оценки не опускают уровень темы', () async {
      await engines.learnerModel.raiseOverallLevel(
        _topicId,
        MasteryLevel.practicalApplication,
      );
      llm.masteryResult = {
        'concepts': [
          concept(_nodeId, understanding: 0.1, recall: 0.1, application: 0.1,
              transfer: 0.1, confidence: 0.1),
        ],
        'enough': false,
        'overall_level': 'awareness',
        'gaps': <String>[],
      };

      await engines.mastery.evaluate(
        _topicId,
        items().take(1).toList(),
        'solid_understanding',
      );

      expect(
        await engines.learnerModel.getCurrentLevel(_topicId),
        MasteryLevel.practicalApplication,
      );
    });
  });
}