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

List<AssessmentQuestion> _parseAssessmentResult(String raw) {
  final data = parseLLMJson<dynamic>(raw);
  if (data is! Map<String, dynamic>) return [];
  final questions = data['questions'];
  if (questions is! List) return [];
  return questions.whereType<Map<String, dynamic>>().map((q) {
    final options = q['options'];
    return AssessmentQuestion(
      id: q['id'] is String
          ? q['id'] as String
          : shortIdWith('a_'),
      type: QuestionType.fromString(q['type'] as String? ?? 'recall'),
      nodeId: q['nodeId'] is String ? q['nodeId'] as String : '',
      question: q['question'] is String ? q['question'] as String : '',
      options: options is List ? options.whereType<String>().toList() : null,
      correctAnswer: q['correctAnswer'] is String ? q['correctAnswer'] as String : '',
      explanation: q['explanation'] is String ? q['explanation'] as String : '',
    );
  }).toList();
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

    List<AssessmentQuestion> questions;
    try {
      final res = await scheduler.execute<List<AssessmentQuestion>>(
        'assessment',
        () => prompt,
        _parseAssessmentResult,
      );
      questions = res.result.take(questionCount).toList();
    } catch (_) {
      questions = items.take(questionCount).toList().asMap().entries.map((e) {
        final i = e.key;
        final item = e.value;
        return AssessmentQuestion(
          id: 'fa_$i',
          type: QuestionType.recall,
          nodeId: item.nodeId,
          question: 'Что такое "${item.label}"?',
          options: const [],
          correctAnswer: '',
          explanation: item.oneLiner,
        );
      }).toList();
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
