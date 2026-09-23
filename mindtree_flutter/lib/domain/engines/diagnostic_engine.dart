import 'dart:convert';

import 'package:mindtree_flutter/domain/lib/short_ids.dart';

import '../../data/database/mindtree_repository.dart';
import '../../data/llm/client.dart';
import '../../data/llm/scheduler.dart';
import '../models/models.dart';
import 'learner_model_service.dart';

const String _noMetaRule = '- В значениях полей пиши только готовый контент по теме. Запрещены служебные фразы о своих действиях и решениях («Узел помечен как…», «Переименовал узел…», «Этот узел не требует дочерних…», «Исправлено…»).';

const String _alphabetRule = '- Используй только кириллицу, латиницу, цифры и обычную пунктуацию. Запрещены иероглифы и знаки других письменностей (китайские, японские, корейские).\n- Все label, title, one_liner, details — только на русском языке.';

const String _promptDiagnostic = '''# Роль
Ты — диагностирующий педагог. Оцени текущий уровень пользователя по теме.

# Контекст
Тема: "{{topic}}"
Цель пользователя: {{goal}}
Целевой уровень: {{target_level}}

# Ключевые понятия темы (ОБЯЗАТЕЛЬНО используй их для вопросов)
{{nodes_json}}

# Задача
Составь диагностику из 3–5 вопросов. КАЖДЫЙ вопрос должен:
1. Быть напрямую связан с конкретным понятием из списка "Ключевые понятия темы"
2. Использовать название понятия (label) в тексте вопроса или вариантах ответа
3. Проверять понимание именно этого понятия, а не общей темы

ЗАПРЕЩЕНО задавать общие вопросы вроде "Что вы знаете о теме?" или "Что обычно показывает базовое понимание?".
Каждый вопрос ДОЛЖЕН содержать имя конкретного понятия из списка (например, "Что такое Аркан?" или "Какова роль Старших Арканов?").

Отбери 3–5 понятий из списка выше (от базовых к продвинутым) и составь по одному вопросу на каждое.

# Формат ответа
Строгий JSON-объект:
{"questions":[{"id":"d1","nodeId":"<id из списка понятий>","question":"Вопрос с упоминанием конкретного понятия?","options":["Вариант A","Вариант B","Вариант C","Вариант D"],"correctIndex":0,"explanation":"..."}]}

# После обработки
На основе ответов диагностики определяется текущий уровень:
- Если большинство правильных — current_level близок к target
- Если большинство неправильных — current_level = awareness

$_noMetaRule
$_alphabetRule

# Язык
Отвечай СТРОГО на русском языке. Все текстовые поля — на русском.

Никакого текста вне JSON. Без ```json и без пояснений.''';

String _buildDiagnosticPrompt({
  required String topic,
  required String goal,
  required String targetLevel,
  required List<KnowledgeNode> nodes,
}) {
  final nodesJson = jsonEncode(nodes
      .map((n) => {
            'id': n.id,
            'label': n.label,
            'one_liner': n.oneLiner,
          })
      .toList());

  return _promptDiagnostic
      .replaceAll('{{topic}}', topic)
      .replaceAll('{{goal}}', goal)
      .replaceAll('{{target_level}}', targetLevel)
      .replaceAll('{{nodes_json}}', nodesJson);
}

/// A single diagnostic question.
class DiagnosticQuestion {
  final String id;
  final String nodeId;
  final String question;
  final List<String> options;
  final int correctIndex;
  final String explanation;

  const DiagnosticQuestion({
    required this.id,
    required this.nodeId,
    required this.question,
    this.options = const [],
    this.correctIndex = 0,
    this.explanation = '',
  });
}

/// One answered diagnostic question.
class DiagnosticAnswer {
  final String questionId;
  final String nodeId;
  final int selectedIndex;
  final int correctIndex;

  const DiagnosticAnswer({
    required this.questionId,
    required this.nodeId,
    required this.selectedIndex,
    required this.correctIndex,
  });
}

/// Result of evaluating a diagnostic.
class DiagnosticResult {
  final List<DiagnosticQuestion> questions;
  final String currentLevel;
  final List<String> knownConcepts;
  final List<String> unknownConcepts;
  final double score;

  const DiagnosticResult({
    this.questions = const [],
    required this.currentLevel,
    required this.knownConcepts,
    required this.unknownConcepts,
    required this.score,
  });
}

List<DiagnosticQuestion> _parseDiagnosticResult(String raw) {
  final data = parseLLMJson<dynamic>(raw);
  if (data is! Map<String, dynamic>) return [];
  final questions = data['questions'];
  if (questions is! List) return [];
  return questions.whereType<Map<String, dynamic>>().map((q) {
    final options = q['options'];
    return DiagnosticQuestion(
      id: q['id'] is String
          ? q['id'] as String
          : shortIdWith('d_'),
      nodeId: q['nodeId'] is String ? q['nodeId'] as String : '',
      question: q['question'] is String ? q['question'] as String : '',
      options: options is List ? options.whereType<String>().toList() : const [],
      correctIndex: q['correctIndex'] is num ? (q['correctIndex'] as num).toInt() : 0,
      explanation: q['explanation'] is String ? q['explanation'] as String : '',
    );
  }).toList();
}

/// Runs an initial diagnostic to estimate starting mastery.
class DiagnosticEngine {
  final MindtreeRepository repo;
  final TreeScheduler scheduler;
  final LearnerModelService _learnerModel;

  DiagnosticEngine({required this.repo, required this.scheduler})
      : _learnerModel = LearnerModelService(repo);

  Future<List<DiagnosticQuestion>> generate(String topicId) async {
    final topic = await repo.getTopic(topicId);
    final nodes = (await repo.listNodes(topicId))
        .where((n) => n.level >= 1)
        .take(8)
        .toList();

    final prompt = _buildDiagnosticPrompt(
      topic: topic?.name ?? '',
      goal: topic?.goal.name ?? 'выяснить текущий уровень понимания',
      targetLevel: topic?.targetLevel.raw ?? 'basic_understanding',
      nodes: nodes,
    );

    final res = await scheduler.execute<List<DiagnosticQuestion>>(
      'diagnostic',
      () => prompt,
      _parseDiagnosticResult,
    );

    return res.result.take(6).toList();
  }

  Future<DiagnosticResult> evaluate(
    String topicId,
    List<DiagnosticAnswer> answers,
  ) async {
    final correctCount =
        answers.where((a) => a.selectedIndex == a.correctIndex).length;
    final score = answers.isNotEmpty ? correctCount / answers.length : 0.0;

    final knownConcepts = answers
        .where((a) => a.selectedIndex == a.correctIndex)
        .map((a) => a.nodeId)
        .toList();
    final unknownConcepts = answers
        .where((a) => a.selectedIndex != a.correctIndex)
        .map((a) => a.nodeId)
        .toList();

    final String currentLevel;
    if (score >= 0.8) {
      currentLevel = 'practical_application';
    } else if (score >= 0.6) {
      currentLevel = 'solid_understanding';
    } else if (score >= 0.4) {
      currentLevel = 'basic_understanding';
    } else {
      currentLevel = 'awareness';
    }

    await _learnerModel.setOverallLevel(
      topicId,
      MasteryLevel.fromString(currentLevel),
    );

    for (final nodeId in knownConcepts) {
      await _learnerModel.updateMasteryDimensions(topicId, nodeId, {
        'understanding': 0.6,
        'recall': 0.6,
        'application': 0.4,
        'transfer': 0.3,
      });
    }

    return DiagnosticResult(
      questions: const [],
      currentLevel: currentLevel,
      knownConcepts: knownConcepts,
      unknownConcepts: unknownConcepts,
      score: score,
    );
  }
}
