import 'dart:developer' as developer;

import 'package:mindtree_flutter/domain/lib/option_matching.dart';
import 'package:mindtree_flutter/domain/lib/short_ids.dart';

import '../../data/database/mindtree_repository.dart';
import '../../data/llm/client.dart';
import '../../data/llm/scheduler.dart';
import '../../data/prompts/prompts.dart';
import '../models/models.dart';

/// A single studied concept used as input for assessment generation.
class AssessmentItem {
  final String nodeId;
  final String label;
  final String oneLiner;
  final String details;

  const AssessmentItem({
    required this.nodeId,
    required this.label,
    required this.oneLiner,
    this.details = '',
  });

  Map<String, dynamic> toJson() => {
        'nodeId': nodeId,
        'label': label,
        'oneLiner': oneLiner,
        'details': details,
      };
}

/// Разбор `questions_json` от LLM в боевой контракт оценки.
///
/// Закрытый вопрос обязан получить разрешимый `correctAnswer` — по контракту это
/// строковый индекс правильного варианта (экраны сверяют ответ как
/// `selected.toString() == q.correctAnswer`), иначе вопрос нечем проверять, и он
/// отбрасывается. Открытый вопрос обязан нести рубрику в `explanation`: эталона
/// у него нет и не требуется, оценивает `gradeOpenEnded`, а с пустой рубрикой
/// такой вопрос засчитывался бы как верный на любой непустой ответ.
///
/// Резолв `correctAnswer` общий с ревью — `lib/domain/lib/option_matching.dart`.
List<AssessmentQuestion> _parseAssessmentResult(String raw) {
  final data = parseLLMJson<dynamic>(raw);
  if (data is! Map<String, dynamic>) return [];
  final questions = data['questions'];
  if (questions is! List) return [];
  final result = <AssessmentQuestion>[];
  for (final q in questions) {
    if (q is! Map<String, dynamic>) continue;
    final questionText = (q['question'] as String?)?.trim() ?? '';
    if (questionText.isEmpty) {
      developer.log('assessment_parse_dropped: reason=empty_question');
      continue;
    }
    final optionsRaw = q['options'];
    final options = optionsRaw is List ? optionsRaw.whereType<String>().toList() : <String>[];
    final correctAnswerRaw = (q['correctAnswer'] as String?)?.trim() ?? '';
    final explanationRaw = (q['explanation'] as String?)?.trim() ?? '';
    final typeStr = (q['type'] as String?)?.trim();
    final type = QuestionType.fromString(typeStr);

    if (options.isNotEmpty) {
      final resolved = resolveCorrectAnswerIndex(options, correctAnswerRaw);
      if (resolved.isEmpty) {
        developer.log('assessment_parse_dropped: reason=unresolved_correct_option, type=closed');
        continue;
      }
      result.add(AssessmentQuestion(
        id: q['id'] is String ? q['id'] as String : shortIdWith('a_'),
        type: type,
        nodeId: q['nodeId'] is String ? q['nodeId'] as String : '',
        question: questionText,
        options: options,
        correctAnswer: resolved,
        explanation: explanationRaw,
      ));
      continue;
    }

    if (explanationRaw.isEmpty) {
      developer.log('assessment_parse_dropped: reason=empty_rubric, type=open');
      continue;
    }
    result.add(AssessmentQuestion(
      id: q['id'] is String ? q['id'] as String : shortIdWith('a_'),
      type: type,
      nodeId: q['nodeId'] is String ? q['nodeId'] as String : '',
      question: questionText,
      options: const [],
      correctAnswer: '',
      explanation: explanationRaw,
    ));
  }
  return result;
}

/// Generates and grades diagnostic/quiz/final/mastery assessments.
class AssessmentEngine {
  final MindtreeRepository repo;
  final TreeScheduler scheduler;

  const AssessmentEngine({required this.repo, required this.scheduler});

  Future<Assessment> generate(
    String sessionId,
    String topicId,
    List<AssessmentItem> items, {
    AssessmentType type = AssessmentType.final_,
    int questionCount = 6,
    bool includeApplication = true,
  }) async {
    final topic = await repo.getTopic(topicId);

    final prompt = buildAssessmentPrompt(
      topic: topic?.name ?? '',
      goal: topic?.goal.name ?? '',
      sessionItems: items.map((s) => s.toJson()).toList(),
      includeApplication: includeApplication,
      questionCount: questionCount,
    );

    List<AssessmentQuestion> questions = const [];
    try {
      final res = await scheduler.execute<List<AssessmentQuestion>>(
        'assessment',
        () => prompt,
        _parseAssessmentResult,
      );
      if (res.result.isNotEmpty) {
        questions = res.result.take(questionCount).toList();
      }
    } catch (_) {
      // fall through
    }

    if (questions.isEmpty) {
      questions = _buildFallback(items, questionCount);
    }

    final id = shortIdWith('asmt_');
    final assessment = Assessment(
      id: id,
      sessionId: sessionId,
      type: type,
      questions: questions,
      startedAt: DateTime.now().toIso8601String(),
    );
    await repo.createAssessment(assessment);

    return assessment;
  }

  List<AssessmentQuestion> _buildFallback(List<AssessmentItem> items, int questionCount) {
    if (questionCount <= 0 || items.isEmpty) return const [];
    final result = <AssessmentQuestion>[];
    int idx = 0;
    for (final item in items) {
      if (result.length >= questionCount) break;
      final rubric = item.oneLiner.trim().isNotEmpty
          ? item.oneLiner.trim()
          : (item.details.trim().isNotEmpty ? item.details.trim() : '');
      final label = item.label.trim();
      final questionText = label.isNotEmpty
          ? 'Объясните своими словами, что такое «$label»'
          : 'Объясните своими словами изученный материал';
      if (rubric.isEmpty) {
        developer.log('assessment_fallback_dropped: reason=empty_rubric, item=${item.nodeId}');
        continue;
      }
      result.add(AssessmentQuestion(
        id: 'fa_${idx++}',
        type: QuestionType.recall,
        nodeId: item.nodeId,
        question: questionText,
        options: const [],
        correctAnswer: '',
        explanation: rubric,
      ));
    }
    if (result.isEmpty) return const [];
    return result.take(questionCount).toList();
  }

  Future<void> recordAttempt(
    String assessmentId,
    String questionId,
    String answer,
    bool correct,
    int timeMs, {
    String? feedback,
  }) async {
    final attempt = Attempt(
      id: shortIdWith('att_'),
      assessmentId: assessmentId,
      questionId: questionId,
      answer: answer,
      correct: correct,
      timeSpentMs: timeMs,
      feedback: feedback,
    );
    await repo.addAttempt(attempt);
  }

  Future<void> finalize(String assessmentId, double score) async {
    final existing = await repo.getAssessment(assessmentId);
    if (existing == null) return;
    await repo.updateAssessment(Assessment(
      id: existing.id,
      sessionId: existing.sessionId,
      type: existing.type,
      questions: existing.questions,
      startedAt: existing.startedAt,
      completedAt: DateTime.now().toIso8601String(),
      score: score,
    ));
  }

  Future<Assessment?> getById(String assessmentId) async {
    return repo.getAssessment(assessmentId);
  }
}