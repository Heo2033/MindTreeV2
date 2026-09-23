import '../../data/database/mindtree_repository.dart';
import '../../data/llm/client.dart';
import '../../data/llm/scheduler.dart';
import '../models/models.dart';
import 'learner_model_service.dart';
import 'review_scheduler.dart';

/// Verdict quality of an answer.
typedef FeedbackQuality = String;

/// Feedback for a single answered activity step.
class AnswerFeedback {
  final bool correct;
  final FeedbackQuality quality;
  final double score;
  final String feedback;
  final String? misconception;

  const AnswerFeedback({
    required this.correct,
    required this.quality,
    required this.score,
    required this.feedback,
    this.misconception,
  });
}

/// Input of a recall (multiple choice) activity step.
class RecallStepInput {
  final List<String>? options;
  final int? correctIndex;

  const RecallStepInput({this.options, this.correctIndex});
}

const String _noMetaRule = '- В значениях полей пиши только готовый контент по теме. Запрещены служебные фразы о своих действиях и решениях («Узел помечен как…», «Переименовал узел…», «Этот узел не требует дочерних…», «Исправлено…»).';

const String _alphabetRule = '- Используй только кириллицу, латиницу, цифры и обычную пунктуацию. Запрещены иероглифы и знаки других письменностей (китайские, японские, корейские).\n- Все label, title, one_liner, details — только на русском языке.';

const String _promptActivityFeedback = '''# Роль
Ты — AI-репетитор. Оцениваешь свободный ответ ученика на задание по конкретному понятию.

# Контекст
Понятие: "{{node_label}}"
Определение: "{{node_one_liner}}"
Задание: "{{instruction}}"
Эталонный ответ: "{{reference_answer}}"
Ответ ученика: "{{user_answer}}"

# Задача
Оцени ответ ученика:
- correct — ответ верен по сути, демонстрирует понимание понятия
- partial — ответ частично верен: есть верная мысль, но есть ошибки или пропущена ключевая часть
- incorrect — ответ неверен или не относится к заданию

Для partial и incorrect укажи возможное заблуждение (misconception) одной фразой, если его можно определить (null, если не определяется).

Требования:
- feedback — 1–3 предложения, по-русски, доброжелательно, конкретно: что верно, чего не хватает.
- Не раскрывай эталонный ответ целиком в feedback (ученик должен перепроверить сам).
$_noMetaRule
$_alphabetRule

# Формат ответа
Строго JSON без markdown:
{
  "assessment": "correct",
  "feedback": "строка",
  "misconception": "строка или null"
}''';

String _buildActivityFeedbackPrompt({
  required String nodeLabel,
  required String nodeOneLiner,
  required String instruction,
  required String referenceAnswer,
  required String userAnswer,
}) {
  return _promptActivityFeedback
      .replaceAll('{{node_label}}', nodeLabel)
      .replaceAll(
          '{{node_one_liner}}', nodeOneLiner.length > 400 ? nodeOneLiner.substring(0, 400) : nodeOneLiner)
      .replaceAll('{{instruction}}', instruction.length > 600 ? instruction.substring(0, 600) : instruction)
      .replaceAll(
          '{{reference_answer}}', referenceAnswer.length > 800 ? referenceAnswer.substring(0, 800) : referenceAnswer)
      .replaceAll('{{user_answer}}', userAnswer.length > 1500 ? userAnswer.substring(0, 1500) : userAnswer);
}

String _sanitizeFeedbackText(Object? v) => (v?.toString() ?? '').trim();

String _sanitizeAssessment(Object? v) {
  final s = v?.toString();
  if (s == 'correct' || s == 'partial' || s == 'incorrect') return s!;
  return 'partial';
}

int _fnv1aHash(String s) {
  var h = 0x811c9dc5;
  for (var i = 0; i < s.length; i++) {
    h ^= s.codeUnitAt(i);
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h & 0xffffffff;
}

/// Generates adaptive feedback for learning activities.
class FeedbackEngine {
  final MindtreeRepository repo;
  final TreeScheduler scheduler;
  final LearnerModelService _learnerModel;
  final ReviewScheduler _reviewScheduler;

  FeedbackEngine({required this.repo, required this.scheduler})
      : _learnerModel = LearnerModelService(repo),
        _reviewScheduler = ReviewScheduler(repo);

  Future<AnswerFeedback> evaluateApply(
    String topicId,
    String topicName,
    String nodeId,
    String nodeLabel,
    String nodeOneLiner,
    String instruction,
    String referenceAnswer,
    String userAnswer,
  ) async {
    final prompt = _buildActivityFeedbackPrompt(
      nodeLabel: nodeLabel,
      nodeOneLiner: nodeOneLiner,
      instruction: instruction,
      referenceAnswer: referenceAnswer,
      userAnswer: userAnswer,
    );

    var assessment = 'partial';
    var feedback = '';
    String? misconception;
    try {
      final res = await scheduler.execute<dynamic>(
        'feedback',
        () => prompt,
        (raw) => parseLLMJson<dynamic>(raw),
        cacheKey: 'activity_fb:$nodeId:${_fnv1aHash(userAnswer)}',
      );
      final parsed = res.result;
      if (parsed is Map<String, dynamic>) {
        assessment = _sanitizeAssessment(parsed['assessment']);
        feedback = _sanitizeFeedbackText(parsed['feedback']);
        final misc = parsed['misconception'];
        misconception = misc is String && misc.trim().isNotEmpty ? misc.trim() : null;
      }
    } catch (_) {
      feedback = '';
    }

    var base = feedback;
    if (base.isEmpty) {
      base = heuristicApplyFeedback(referenceAnswer, userAnswer);
    }
    final score = assessment == 'correct' ? 1.0 : (assessment == 'partial' ? 0.5 : 0.0);
    final correct = assessment == 'correct';
    final MisconceptionType? miscType;
    if (correct) {
      miscType = null;
    } else {
      miscType = score == 0 ? MisconceptionType.applicationFailure : MisconceptionType.incomplete;
    }

    await _record(
      topicId,
      nodeId,
      'application',
      score,
      correct,
      miscType,
      misconception,
    );

    return AnswerFeedback(
      correct: correct,
      quality: assessment == 'correct' ? 'correct' : 'incorrect',
      score: score,
      feedback: base,
      misconception: misconception,
    );
  }

  Future<AnswerFeedback> evaluateRecall(
    String topicId,
    String topicName,
    String nodeId,
    String nodeLabel,
    RecallStepInput step,
    int chosenIndex,
  ) async {
    final correct = chosenIndex == step.correctIndex;
    final chosen = (step.options != null && chosenIndex < step.options!.length)
        ? step.options![chosenIndex]
        : '';
    final correctOption = (step.options != null && (step.correctIndex ?? 0) < step.options!.length)
        ? step.options![step.correctIndex ?? 0]
        : '';

    final score = correct ? 1.0 : 0.0;
    final String feedback;
    if (correct) {
      feedback = 'Верно! Вы правильно припомнили понятие.';
    } else {
      feedback = 'Не совсем. Правильный ответ: «$correctOption». Перечитайте объяснение понятия и попробуйте ещё раз.';
    }

    final String? misconception;
    if (correct) {
      misconception = null;
    } else {
      misconception =
          'Выбрано «${_truncate(chosen, 80)}», правильным было «${_truncate(correctOption, 80)}»';
    }

    await _record(
      topicId,
      nodeId,
      'recall',
      score,
      correct,
      correct ? null : MisconceptionType.confused,
      misconception,
    );

    return AnswerFeedback(
      correct: correct,
      quality: correct ? 'correct' : 'incorrect',
      score: score,
      feedback: feedback,
      misconception: misconception,
    );
  }

  Future<void> _record(
    String topicId,
    String nodeId,
    SkillDimension dim,
    double score,
    bool correct,
    MisconceptionType? misconceptionType,
    String? description,
  ) async {
    final prev = await _learnerModel.getConceptProfile(nodeId, topicId);
    final blended = prev != null ? _dimValue(prev, dim) * 0.5 + score * 0.5 : score;
    await _learnerModel.updateMasteryDimensions(topicId, nodeId, {dim: blended});
    if (!correct && misconceptionType != null && description != null) {
      await _learnerModel.addMisconception(topicId, nodeId, misconceptionType, description);
    }
    await _reviewScheduler.onAnswered(topicId, nodeId, correct ? 'correct' : 'incorrect');
  }

  static double _dimValue(ConceptProfile p, String dim) {
    switch (dim) {
      case dimUnderstanding:
        return p.understanding;
      case dimRecall:
        return p.recall;
      case dimApplication:
        return p.application;
      case dimTransfer:
        return p.transfer;
      default:
        return p.understanding;
    }
  }

  static String _truncate(String s, int max) => s.length > max ? s.substring(0, max) : s;
}

/// Fallback feedback computed from token overlap with the reference answer.
String heuristicApplyFeedback(String referenceAnswer, String userAnswer) {
  final refTokens = _tokenize(referenceAnswer);
  final userTokens = _tokenize(userAnswer);
  if (userTokens.isEmpty) {
    return 'Ответ пустой или слишком короткий. Сформулируйте мысль своими словами.';
  }
  if (refTokens.isEmpty) {
    return 'Проверьте ответ по эталонному решению ниже.';
  }
  var hits = 0;
  for (final t in userTokens) {
    if (refTokens.contains(t)) hits++;
  }
  final ratio = hits / refTokens.length;
  if (ratio >= 0.4) {
    return 'Ответ частично совпадает с эталоном. Сверьтесь с вариантом ниже и дополните недостающее.';
  }
  return 'Ответ пока не совпадает с эталоном. Сверьтесь с вариантом ниже и попробуйте переформулировать.';
}

Set<String> _tokenize(String text) {
  final cleaned = text
      .toLowerCase()
      .replaceAll(RegExp(r'[«»"(),.;:!?—–\-]'), ' ');
  return cleaned
      .split(RegExp(r'\s+'))
      .where((w) => w.length > 3)
      .toSet();
}
