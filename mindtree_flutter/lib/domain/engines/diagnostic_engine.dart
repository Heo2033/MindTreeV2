import 'dart:developer' as developer;

import 'package:mindtree_flutter/domain/lib/short_ids.dart';

import '../../data/database/mindtree_repository.dart';
import '../../data/llm/client.dart';
import '../../data/llm/scheduler.dart';
import '../../data/prompts/prompts.dart';
import '../models/models.dart';
import 'learner_model_service.dart';
// Устойчивый сдвиг вариантов/индекса — общие детерминированные хелперы
// (без RNG), переиспользуем их, а не дублируем ротацию.
import 'learning_activity_service.dart' show rotateIndex, rotateOptions;

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

    final prompt = buildDiagnosticPrompt(
      topic: topic?.name ?? '',
      goal: topic?.goal.name ?? 'выяснить текущий уровень понимания',
      targetLevel: topic?.targetLevel.raw ?? 'basic_understanding',
      nodes: nodes.map((n) => {
        'id': n.id,
        'label': n.label,
        'one_liner': n.oneLiner,
      }).toList(),
    );

    List<DiagnosticQuestion> questions;
    try {
      final res = await scheduler.execute<List<DiagnosticQuestion>>(
        'diagnostic',
        () => prompt,
        _parseDiagnosticResult,
      );
      questions = res.result;
    } catch (e, st) {
      // LLM недоступен (сеть/ключ/лимиты) — отдаём детерминированный набор
      // вопросов из уже загруженного дерева: экран диагностики не должен падать.
      developer.log(
        '[diagnostic] LLM generation failed for $topicId',
        error: e,
        stackTrace: st,
      );
      questions = _fallbackQuestions(topic?.name ?? '', nodes);
    }

    return questions.take(6).toList();
  }

  /// Детерминированный fallback-диагностики без LLM: вопрос на каждый узел
  /// («что означает понятие X»), варианты — подписи узлов. Без Random и без
  /// DateTime: и порядок узлов, и сдвиг вариантов задаются индексом узла,
  /// поэтому один и тот же вход всегда даёт один и тот же набор вопросов.
  List<DiagnosticQuestion> _fallbackQuestions(
    String topicName,
    List<KnowledgeNode> nodes,
  ) {
    // Один узел — вопрос в одном варианте бессмыслен, без узлов — тоже.
    if (nodes.length < 2) return const [];

    // Подпись узла — и вопрос, и варианты; без label берём one_liner.
    final labels = [
      for (final n in nodes)
        n.label.trim().isNotEmpty ? n.label.trim() : n.oneLiner.trim(),
    ];

    final questions = <DiagnosticQuestion>[];
    for (var i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      final correct = labels[i];
      if (correct.isEmpty) continue;

      // Дистракторы — подписи следующих по обходу узлов (циклически), без
      // пустых строк и повторов правильного варианта.
      final distractors = <String>[];
      for (var k = 1; distractors.length < 3 && k < nodes.length; k++) {
        final candidate = labels[(i + k) % nodes.length];
        if (candidate.isEmpty || candidate == correct) continue;
        if (distractors.contains(candidate)) continue;
        distractors.add(candidate);
      }

      final options = [correct, ...distractors];
      // Меньше двух вариантов — вопрос без выбора, пропускаем узел.
      if (options.length < 2) continue;

      // Сдвиг по индексу узла: правильный вариант не всегда первый, но для
      // одного и того же узла его позиция всегда одна и та же.
      final shift = i % options.length;
      final oneLiner = node.oneLiner.trim();
      questions.add(
        DiagnosticQuestion(
          id: shortIdWith('d_'),
          nodeId: node.id,
          question: 'Что означает понятие «$correct»?',
          options: rotateOptions(options, shift),
          correctIndex: rotateIndex(0, shift, options.length),
          explanation: oneLiner.isNotEmpty
              ? oneLiner
              : 'Понятие «$correct» — часть темы «$topicName».',
        ),
      );
    }
    return questions;
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

    // Уровень из ответов диагностики — стартовая точка, а не приговор: он не
    // опускает уже достигнутый уровень (`raiseOverallLevel`) и попадает в
    // `initial_overall_level`, из которого `analytics` считает Learning Gain.
    await _learnerModel.raiseOverallLevel(
      topicId,
      MasteryLevel.fromString(currentLevel),
      asInitial: true,
    );

    // Свидетельство по КАЖДОМУ ответу, а не константы всем «известным»:
    // раньше здесь писалось {understanding: 0.6, recall: 0.6, application: 0.4,
    // transfer: 0.3} для всех верно отвеченных концептов, и в реальной БД
    // восемь узлов получали одинаковый профиль независимо от ответов. Теперь
    // верный ответ — это одно свидетельство для `recall`/`understanding` с
    // весом [kEvidenceWeight], неверный — то же свидетельство со score 0.
    for (final answer in answers) {
      if (answer.nodeId.isEmpty) continue;
      final score = answer.selectedIndex == answer.correctIndex ? 1.0 : 0.0;
      await _learnerModel.recordEvidence(topicId, answer.nodeId, {
        dimRecall: score,
        dimUnderstanding: score,
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
