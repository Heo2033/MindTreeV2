import 'dart:developer' as developer;

import '../../data/database/mindtree_repository.dart';
import '../../data/llm/client.dart';
import '../../data/llm/scheduler.dart';
import '../../data/prompts/prompts.dart';
import '../models/models.dart';
import 'learner_model_service.dart';
import 'review_scheduler.dart';

/// Verdict quality of an answer.
typedef FeedbackQuality = String;

/// Качество, когда ответ оценить НЕ удалось (LLM недоступен или ответил
/// неконтрактом).
///
/// Отдельное значение от 'incorrect': «не оценено» — это отказ инфраструктуры,
/// а не провал ученика. Раньше дефолт `partial` при падении LLM давал
/// `correct = false`, и `_record` уходил в `onAnswered(..., 'incorrect')`:
/// сброс SRS-интервала плюс ложная мисконцепция `careless` за отсутствие сети
/// или ключа. Теперь этот путь не трогает модель ученика вовсе.
const String kQualityUnevaluated = 'unevaluated';

/// Feedback for a single answered activity step.
class AnswerFeedback {
  final bool correct;
  final FeedbackQuality quality;
  final double score;
  final String feedback;
  final String? misconception;

  /// Удалось ли оценить ответ.
  ///
  /// `false` — LLM недоступен или ответил неконтрактом: mastery, SRS и
  /// мисконцепции по такому ответу НЕ трогаются, [score] не имеет смысла, а
  /// [feedback] содержит детерминированное объяснение по пересечению с
  /// эталоном (пустым он не бывает — UI-ревью ловит пустой фидбек как дефект).
  /// При `evaluated == false` ориентироваться надо на это поле, а не на
  /// [correct]: «не оценено» — это не «неверно».
  final bool evaluated;

  const AnswerFeedback({
    required this.correct,
    required this.quality,
    required this.score,
    required this.feedback,
    this.misconception,
    this.evaluated = true,
  });
}

/// Input of a recall (multiple choice) activity step.
class RecallStepInput {
  final List<String>? options;
  final int? correctIndex;

  const RecallStepInput({this.options, this.correctIndex});
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
///
/// Единственный владелец записи измерений по ответам на шаги активности:
/// [LearningActivityService] только зовёт [evaluateApply]/[evaluateRecall] и
/// показывает результат. Приватных копий этой логики в сервисе больше нет.
class FeedbackEngine {
  final MindtreeRepository repo;
  final TreeScheduler scheduler;
  final LearnerModelService _learnerModel;
  final ReviewScheduler _reviewScheduler;

  FeedbackEngine({required this.repo, required this.scheduler})
      : _learnerModel = LearnerModelService(repo),
        _reviewScheduler = ReviewScheduler(repo);

  /// Оценка свободного ответа шага «Применение».
  ///
  /// [nodeLabel]/[nodeOneLiner] — контекст понятия, [instruction] — задание,
  /// [referenceAnswer] — эталон, [userAnswer] — ответ ученика.
  ///
  /// Отказ LLM — НЕ вердикт: возвращается [AnswerFeedback] с
  /// `evaluated == false` и непустым [AnswerFeedback.feedback] от
  /// [heuristicApplyFeedback], а модель ученика остаётся нетронутой (никакого
  /// сброса SRS и никаких мисконцепций за сеть без ключа).
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
    final prompt = buildActivityFeedbackPrompt(
      nodeLabel: nodeLabel,
      nodeOneLiner: nodeOneLiner,
      instruction: instruction,
      referenceAnswer: referenceAnswer,
      userAnswer: userAnswer,
    );

    var assessment = '';
    var llmFeedback = '';
    String? misconception;
    var evaluated = false;
    try {
      final res = await scheduler.execute<Map<String, dynamic>>(
        'feedback',
        () => prompt,
        (raw) => parseLLMJson<Map<String, dynamic>>(raw),
        cacheKey: 'activity_fb:$nodeId:${_fnv1aHash(userAnswer)}',
      );
      // Санитизация обязательна: мусорный assessment («Верно», 'correct ')
      // иначе дал бы ложный вердикт «неверно», а верный JSON без `feedback` —
      // оценку вообще без объяснения.
      final clean = sanitizeFeedbackResult(res.result);
      assessment = clean['assessment'] as String;
      llmFeedback = (clean['feedback'] as String).trim();
      final misc = clean['misconception'];
      misconception =
          misc is String && misc.trim().isNotEmpty ? misc.trim() : null;
      evaluated = true;
    } catch (e, st) {
      // Сеть/ключ/лимиты/сломанный контракт — это отказ инфраструктуры.
      developer.log(
        '[feedback] LLM unavailable for node $nodeId',
        error: e,
        stackTrace: st,
      );
    }

    // Фидбек не бывает пустым (ревью ловит это как session_feedback_missing):
    // если модель его не дала, объясняем по пересечению с эталоном.
    final text = llmFeedback.isNotEmpty
        ? llmFeedback
        : heuristicApplyFeedback(referenceAnswer, userAnswer);

    if (!evaluated) {
      return AnswerFeedback(
        correct: false,
        quality: kQualityUnevaluated,
        score: 0.0,
        feedback: text,
        evaluated: false,
      );
    }

    final correct = assessment == 'correct';
    final partial = assessment == 'partial';
    final score = correct ? 1.0 : (partial ? 0.5 : 0.0);
    final miscType = correct
        ? null
        : (partial
            ? MisconceptionType.incomplete
            : MisconceptionType.applicationFailure);
    await _record(
      topicId: topicId,
      nodeId: nodeId,
      // Свободный ответ — свидетельство про применение, и по совместимости
      // про понимание понятия. Каждое измерение движется ровно один раз.
      evidence: {dimApplication: score, dimUnderstanding: score},
      // Частично верный ответ повторением не считается: SRS не двигаем ни в
      // плюс, ни в минус — «не совсем верно» не повод обнулять интервал.
      srsQuality: correct ? 'correct' : (partial ? null : 'again'),
      misconceptionType: miscType,
      description: miscType == null
          ? null
          : (misconception ?? miscType.defaultDescription),
    );

    return AnswerFeedback(
      correct: correct,
      quality: correct ? 'correct' : 'incorrect',
      score: score,
      feedback: text,
      misconception: misconception,
    );
  }

  /// Оценка шага «Проверяем запоминание» (выбор варианта).
  ///
  /// LLM здесь не нужен: правильный индекс известен детерминированно.
  /// Ответ — свидетельство и про память (`recall`), и про понимание; оба
  /// измерения пишутся одним и тем же смешиванием [kEvidenceWeight], а не
  /// «recall дважды, application один раз».
  Future<AnswerFeedback> evaluateRecall(
    String topicId,
    String topicName,
    String nodeId,
    String nodeLabel,
    RecallStepInput step,
    int chosenIndex,
  ) async {
    final options = step.options;
    if (options == null || options.isEmpty) {
      // Вариантов нет — измерять нечего. Модель ученика не трогаем: вопрос без
      // вариантов не «верный» и не «неверный».
      return AnswerFeedback(
        correct: false,
        quality: kQualityUnevaluated,
        score: 0.0,
        feedback: 'Варианты не сгенерированы; переходим дальше.',
        evaluated: false,
      );
    }

    final correctIndex = step.correctIndex ?? 0;
    final indexValid = correctIndex >= 0 && correctIndex < options.length;
    final correct = indexValid && chosenIndex == correctIndex;
    final chosen =
        chosenIndex >= 0 && chosenIndex < options.length ? options[chosenIndex] : '';
    final correctOption = indexValid ? options[correctIndex] : '';
    final score = correct ? 1.0 : 0.0;

    final String feedback;
    final String? description;
    if (correct) {
      feedback = 'Верно! Вы правильно припомнили понятие.';
      description = null;
    } else {
      feedback =
          'Не совсем. Правильный ответ: «$correctOption». Перечитайте объяснение понятия и попробуйте ещё раз.';
      description = _confusionText(chosen, correctOption, nodeLabel);
    }

    await _record(
      topicId: topicId,
      nodeId: nodeId,
      evidence: {dimRecall: score, dimUnderstanding: score},
      srsQuality: correct ? 'correct' : 'again',
      misconceptionType: correct ? null : MisconceptionType.confused,
      description: description,
    );

    return AnswerFeedback(
      correct: correct,
      quality: correct ? 'correct' : 'incorrect',
      score: score,
      feedback: feedback,
      misconception: description,
    );
  }

  /// Единственная точка записи по ответу шага активности.
  ///
  /// [evidence] — измерения, по которым ответ даёт свидетельство; пишутся
  /// инкрементально через [LearnerModelService.recordEvidence], ровно один раз
  /// на измерение. [srsQuality] — качество для SM-2; `null` означает «ответ не
  /// повторение», и тогда SRS не трогается вовсе.
  ///
  /// `recordCareless: false` — тип ошибки записывается здесь и точнее, чем
  /// безликое `careless` («небрежный ответ при повторении»), которого в шаге
  /// активности нет в природе.
  Future<void> _record({
    required String topicId,
    required String nodeId,
    required Map<String, double> evidence,
    required String? srsQuality,
    MisconceptionType? misconceptionType,
    String? description,
  }) async {
    if (srsQuality != null) {
      await _reviewScheduler.onAnswered(
        topicId,
        nodeId,
        srsQuality,
        evidence: evidence,
        recordCareless: false,
      );
    } else {
      await _learnerModel.recordEvidence(topicId, nodeId, evidence);
    }
    final text = description?.trim() ?? '';
    if (misconceptionType != null && text.isNotEmpty) {
      await _learnerModel.addMisconception(
        topicId,
        nodeId,
        misconceptionType,
        text,
      );
    }
  }

  /// Текст мисконцепции «перепутал варианты».
  ///
  /// Если вариантов нет (упавший генератор шагов или пустой индекс) — осмысленный
  /// текст по подписи понятия. Пустая строка не пишется никогда: записи с
  /// `description = ''` и есть тот мусор, который загрязняет модель ученика.
  static String _confusionText(
    String chosen,
    String correctOption,
    String nodeLabel,
  ) {
    if (chosen.trim().isEmpty || correctOption.trim().isEmpty) {
      final label = nodeLabel.trim();
      return label.isEmpty
          ? MisconceptionType.confused.defaultDescription
          : 'Ответ на проверку запоминания «$label» неверный: выбран вариант, '
              'не соответствующий определению понятия';
    }
    return 'Выбрано «${_truncate(chosen, 80)}», правильным было «${_truncate(correctOption, 80)}»';
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
