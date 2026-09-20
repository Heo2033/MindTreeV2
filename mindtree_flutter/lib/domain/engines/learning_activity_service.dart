import 'dart:convert';
import 'dart:developer' as developer;

import '../models/models.dart';
import '../../data/database/mindtree_repository.dart';
import '../../data/llm/scheduler.dart';
import '../../data/llm/client.dart';
import 'learning_session_engine.dart';

class LearningActivityService {
  final LearningSessionEngine engine;
  final MindtreeRepository repo;
  final TreeScheduler scheduler;

  LearningActivityService({
    required this.engine,
    required this.repo,
    required this.scheduler,
  });

  Future<LearningActivity?> getActivity(String sessionId) async {
    final session = await engine.getSession(sessionId);
    if (session == null) return null;
    final blob = session.activityJson;
    if (blob == null || blob.isEmpty) return null;
    final parsed = parseActivityBlob(blob);
    final steps = parsed.steps;
    if (steps.isEmpty) return null;

    final current = await engine.getCurrentItem(sessionId);
    if (current == null) return null;

    if (parsed.itemId != null && parsed.itemId != current.item.id) return null;

    final node = await repo.getNode(current.item.nodeId);
    final nodeLabel = node?.label ?? '';
    final currentStep = nextPendingIndex(steps);
    return LearningActivity(
      sessionId: sessionId,
      itemId: current.item.id,
      nodeId: current.item.nodeId,
      nodeLabel: nodeLabel,
      goal: session.goal,
      steps: steps,
      currentStep: currentStep,
      isComplete: currentStep == -1,
    );
  }

  Future<LearningActivity> ensureActivity(String sessionId) async {
    final existing = await getActivity(sessionId);
    if (existing != null) return existing;

    final current = await engine.getCurrentItem(sessionId);
    if (current == null) throw Exception('No current curriculum step');
    final session = await engine.getSession(sessionId);
    if (session == null) throw Exception('Session not found');

    final node = await repo.getNode(current.item.nodeId);
    if (node == null) throw Exception('Node not found');

    // Prefetch: если фоном уже сгенерировали шаги для этого узла — берём их.
    var steps = await repo.getCachedActivitySteps(node.id, session.goal);
    steps ??= await _buildSteps(session, node, current.item.order);
    await repo.saveActivityCache(session.topicId, node.id, session.goal, steps);

    final blob = jsonEncode({'itemId': current.item.id, 'steps': steps});
    final updated = session.copyWith(
      activityJson: () => blob,
      currentActivityStep: 0,
    );
    await repo.updateSession(updated);

    await engine.eventBus.emit(
      sessionId: sessionId,
      topicId: session.topicId,
      kind: 'activity_started',
      nodeId: node.id,
      payload: {'itemId': current.item.id, 'steps': steps.map((s) => s.type).toList()},
    );

    return (await getActivity(sessionId))!;
  }

  /// Фоновая предгенерация шагов для узла (без изменения сессии).
  /// Результат кладётся в activity_cache — подхватится при переходе.
  Future<void> prefetchActivity(String sessionId, String nodeId, int order) async {
    final session = await engine.getSession(sessionId);
    if (session == null) return;
    final node = await repo.getNode(nodeId);
    if (node == null) return;

    try {
      final cached = await repo.getCachedActivitySteps(node.id, session.goal);
      if (cached != null) return;
      final built = await _buildSteps(session, node, order);
      await repo.saveActivityCache(session.topicId, node.id, session.goal, built);
    } catch (e, st) {
      developer.log('[activity] prefetch failed for $nodeId', error: e, stackTrace: st);
    }
  }

  Future<LearningActivity> answer(
    String sessionId,
    int stepIndex,
    String answer,
  ) async {
    final session = await engine.getSession(sessionId);
    if (session == null) throw Exception('Session not found');
    final activity = await getActivity(sessionId);
    if (activity == null) throw Exception('Activity not found. Call ensureActivity first.');
    if (stepIndex < 0 || stepIndex >= activity.steps.length) throw Exception('Invalid step index');
    final step = activity.steps[stepIndex];
    if (step.isAnswered) throw Exception('Step already answered');

    final node = await repo.getNode(activity.nodeId);
    final nodeLabel = node?.label ?? activity.nodeLabel;
    final nodeOneLiner = node?.oneLiner ?? '';

    if (step.type == 'recall') {
      final chosenIndex = _clamp(0, int.tryParse(answer) ?? 0, (step.options?.length ?? 1) - 1);
      final result = _evaluateRecall(chosenIndex, step);
      final updatedSteps = List<ActivityStep>.from(activity.steps);
      updatedSteps[stepIndex] = ActivityStep(
        type: step.type,
        title: step.title,
        body: step.body,
        instruction: step.instruction,
        options: step.options,
        correctIndex: step.correctIndex,
        bestAnswer: step.bestAnswer,
        placeholder: step.placeholder,
        status: 'answered',
        userAnswer: answer,
        correct: result.correct,
        feedback: result.feedback,
      );
      await _persistSteps(sessionId, activity.itemId, updatedSteps);
      await engine.eventBus.emit(
        sessionId: sessionId,
        topicId: session.topicId,
        kind: 'activity_answer',
        nodeId: activity.nodeId,
        payload: {'step': 'recall', 'correct': result.correct, 'score': result.score},
      );
    } else if (step.type == 'apply') {
      final topic = await repo.getTopic(session.topicId);
      final topicName = topic?.name ?? '';
      final res = await _evaluateApply(session.topicId, topicName, activity.nodeId,
          nodeLabel, nodeOneLiner, step.instruction ?? '', step.bestAnswer ?? '', answer);
      final updatedSteps = List<ActivityStep>.from(activity.steps);
      updatedSteps[stepIndex] = ActivityStep(
        type: step.type,
        title: step.title,
        body: step.body,
        instruction: step.instruction,
        options: step.options,
        correctIndex: step.correctIndex,
        bestAnswer: step.bestAnswer,
        placeholder: step.placeholder,
        status: 'answered',
        userAnswer: answer,
        correct: res.correct,
        feedback: res.feedback,
      );
      await _persistSteps(sessionId, activity.itemId, updatedSteps);
      await engine.eventBus.emit(
        sessionId: sessionId,
        topicId: session.topicId,
        kind: 'activity_answer',
        nodeId: activity.nodeId,
        payload: {'step': 'apply', 'correct': res.correct, 'score': res.score},
      );
    } else {
      final updatedSteps = List<ActivityStep>.from(activity.steps);
      updatedSteps[stepIndex] = ActivityStep(
        type: step.type,
        title: step.title,
        body: step.body,
        instruction: step.instruction,
        options: step.options,
        correctIndex: step.correctIndex,
        bestAnswer: step.bestAnswer,
        placeholder: step.placeholder,
        status: 'answered',
        userAnswer: answer.isEmpty ? '' : answer,
      );
      await _persistSteps(sessionId, activity.itemId, updatedSteps);
      await engine.eventBus.emit(
        sessionId: sessionId,
        topicId: session.topicId,
        kind: 'activity_step_done',
        nodeId: activity.nodeId,
        payload: {'step': step.type},
      );
    }

    return (await getActivity(sessionId))!;
  }

  Future<List<ActivityStep>> _buildSteps(
    LearningSession session,
    KnowledgeNode node,
    int order,
  ) async {
    final topic = await repo.getTopic(session.topicId);
    final topicLabel = topic?.name ?? '';
    final targetLevel = topic?.targetLevel.raw ?? 'basic_understanding';

    final nodeData = _NodeContext(
      id: node.id,
      label: node.label,
      oneLiner: node.oneLiner,
      details: node.details,
      conceptType: node.conceptType?.raw,
      difficulty: node.difficulty,
    );

    _ActivityGenResult generated = _ActivityGenResult();
    try {
      final res = await scheduler.execute<Map<String, dynamic>>(
        'activity',
        () => _buildActivityPrompt(
          topic: topicLabel,
          goal: session.goal,
          targetLevel: targetLevel,
          node: nodeData,
        ),
        (raw) => parseLLMJson<Map<String, dynamic>>(raw),
        cacheKey: 'activity:${node.id}:${session.goal}:$targetLevel',
      );
      generated = _ActivityGenResult.fromJson(res.result);
    } catch (e, st) {
      developer.log(
        '[activity] LLM generation failed for ${node.id}',
        error: e,
        stackTrace: st,
      );
    }

    final relatedLabels = await _relatedLabels(session.topicId, node);
    final exampleBody = generated.example.trim().isNotEmpty
        ? generated.example
        : _fallbackExample(node);
    final recall = _buildRecall(node, generated, order, relatedLabels);
    final apply = _buildApply(node, generated);

    final steps = [
      ActivityStep(
        type: 'explain',
        title: '\u0418\u0437\u0443\u0447\u0430\u0435\u043c \u043f\u043e\u043d\u044f\u0442\u0438\u0435',
        body: _explainBody(node),
        status: 'current',
      ),
      ActivityStep(
        type: 'example',
        title: '\u0420\u0430\u0437\u0431\u0438\u0440\u0430\u0435\u043c \u043f\u0440\u0438\u043c\u0435\u0440',
        body: exampleBody,
        status: 'pending',
      ),
      ActivityStep(
        type: 'recall',
        title: '\u041f\u0440\u043e\u0432\u0435\u0440\u044f\u0435\u043c \u0437\u0430\u043f\u043e\u043c\u0438\u043d\u0430\u043d\u0438\u0435',
        instruction: recall.question,
        options: recall.options,
        correctIndex: recall.correctIndex,
        placeholder: '\u0412\u044b\u0431\u0435\u0440\u0438\u0442\u0435 \u0432\u0430\u0440\u0438\u0430\u043d\u0442 \u043e\u0442\u0432\u0435\u0442\u0430',
        status: 'pending',
      ),
      ActivityStep(
        type: 'apply',
        title: '\u041f\u0440\u0438\u043c\u0435\u043d\u044f\u0435\u043c \u043d\u0430 \u043f\u0440\u0430\u043a\u0442\u0438\u043a\u0435',
        instruction: apply.instruction,
        bestAnswer: apply.referenceAnswer,
        placeholder: '\u0412\u0432\u0435\u0434\u0438\u0442\u0435 \u043e\u0442\u0432\u0435\u0442 \u0441\u0432\u043e\u0438\u043c\u0438 \u0441\u043b\u043e\u0432\u0430\u043c\u0438\u2026',
        status: 'pending',
      ),
    ];
    return steps;
  }

  Future<void> _persistSteps(String sessionId, String itemId, List<ActivityStep> steps) async {
    final session = await engine.getSession(sessionId);
    if (session == null) return;
    final blob = jsonEncode({'itemId': itemId, 'steps': steps});
    final updated = session.copyWith(
      activityJson: () => blob,
      currentActivityStep: nextPendingIndex(steps),
    );
    await repo.updateSession(updated);
  }

  ({bool correct, String feedback, double score}) _evaluateRecall(
    int chosenIndex,
    ActivityStep step,
  ) {
    final options = step.options;
    final correctIdx = step.correctIndex ?? 0;
    if (options == null || options.isEmpty) {
      // Без вариантов ответов считаем ответ верным — fallback без данных.
      return (correct: true, feedback: 'Варианты не сгенерированы; переходим дальше.', score: 1.0);
    }
    final clamped = _clamp(0, chosenIndex, options.length - 1);
    final correct = clamped == correctIdx;
    return (
      correct: correct,
      feedback: correct
          ? 'Правильно!'
          : 'Неверно. Правильный ответ: ${options[correctIdx]}',
      score: correct ? 1.0 : 0.0,
    );
  }

  Future<({bool correct, String feedback, double score})> _evaluateApply(
    String topicId,
    String topicName,
    String nodeId,
    String nodeLabel,
    String nodeOneLiner,
    String instruction,
    String referenceAnswer,
    String userAnswer,
  ) async {
    try {
      final res = await scheduler.execute<Map<String, dynamic>>(
        'activity',
        () => _buildActivityFeedbackPrompt(
          nodeLabel: nodeLabel,
          nodeOneLiner: nodeOneLiner,
          instruction: instruction,
          referenceAnswer: referenceAnswer,
          userAnswer: userAnswer,
        ),
        (raw) => parseLLMJson<Map<String, dynamic>>(raw),
      );
      final assessment = (res.result['assessment'] as String?) ?? 'partial';
      final feedback = (res.result['feedback'] as String?) ?? '';
      final isCorrect = assessment == 'correct';
      return (
        correct: isCorrect,
        feedback: feedback,
        score: isCorrect ? 1.0 : (assessment == 'partial' ? 0.5 : 0.0),
      );
    } catch (_) {
      return (correct: false, feedback: '', score: 0.0);
    }
  }

  static int _clamp(int min, int value, int max) =>
      value < min ? min : (value > max ? max : value);

  /// Собирает осмысленные термины-дистракторы: определения соседних узлов
  /// (siblings по тому же родителю) и подписи relation-рёбер.
  Future<List<String>> _relatedLabels(String topicId, KnowledgeNode node) async {
    final result = <String>[];
    final siblings = await repo.listNodes(topicId);
    for (final n in siblings) {
      if (result.length >= 3) break;
      if (n.parentId == node.parentId &&
          n.id != node.id &&
          n.oneLiner.isNotEmpty &&
          !result.contains(n.oneLiner)) {
        result.add(n.oneLiner);
      }
    }
    for (final rel in node.relations) {
      if (result.length >= 3) break;
      final label = rel.label;
      if (label != null && label.trim().isNotEmpty && !result.contains(label.trim())) {
        result.add(label.trim());
      }
    }
    return result;
  }
}

/// Текст шага «объяснение»: подробный details, либо связка
/// one_liner + аналогия + связи — но не голый one_liner.
String _explainBody(KnowledgeNode node) {
  if (node.details.isNotEmpty) return node.details;
  final parts = <String>[node.oneLiner];
  if (node.analogy != null && node.analogy!.isNotEmpty) {
    parts.add('\u0410\u043d\u0430\u043b\u043e\u0433\u0438\u044f: ${node.analogy}');
  }
  final related = node.relations
      .map((r) => r.label?.trim() ?? '')
      .where((l) => l.isNotEmpty)
      .toSet()
      .toList();
  if (related.isNotEmpty) {
    parts.add('\u0421\u0432\u044f\u0437\u0430\u043d\u043e \u0441: ${related.join(', ')}.');
  }
  return parts.join('\n\n');
}

// ─── Activity generation helpers ──────────────────────────────────────────────

class _NodeContext {
  final String id;
  final String label;
  final String oneLiner;
  final String details;
  final String? conceptType;
  final double difficulty;
  _NodeContext({
    required this.id,
    required this.label,
    required this.oneLiner,
    required this.details,
    this.conceptType,
    this.difficulty = 0.5,
  });
}

class _ActivityGenResult {
  final String example;
  final _RecallGen? recall;
  final _ApplyGen? apply;
  _ActivityGenResult({this.example = '', this.recall, this.apply});

  factory _ActivityGenResult.fromJson(Map<String, dynamic> j) {
    final recallRaw = j['recall'] as Map<String, dynamic>?;
    final applyRaw = j['apply'] as Map<String, dynamic>?;
    return _ActivityGenResult(
      example: (j['example'] as String?) ?? '',
      recall: recallRaw != null ? _RecallGen.fromJson(recallRaw) : null,
      apply: applyRaw != null ? _ApplyGen.fromJson(applyRaw) : null,
    );
  }
}

class _RecallGen {
  final String question;
  final List<String> options;
  final int correctIndex;
  _RecallGen({this.question = '', this.options = const [], this.correctIndex = 0});

  factory _RecallGen.fromJson(Map<String, dynamic> j) => _RecallGen(
        question: (j['question'] as String?) ?? '',
        options: (j['options'] as List<dynamic>? ?? []).cast<String>(),
        correctIndex: (j['correct_index'] as num?)?.toInt() ?? 0,
      );
}

class _ApplyGen {
  final String instruction;
  final String referenceAnswer;
  _ApplyGen({this.instruction = '', this.referenceAnswer = ''});

  factory _ApplyGen.fromJson(Map<String, dynamic> j) => _ApplyGen(
        instruction: (j['instruction'] as String?) ?? '',
        referenceAnswer: (j['reference_answer'] as String?) ?? '',
      );
}

({String question, List<String> options, int correctIndex}) _buildRecall(
  KnowledgeNode node,
  _ActivityGenResult generated,
  int order, [
  List<String> relatedLabels = const [],
]) {
  final gen = generated.recall;
  if (gen != null && gen.options.length >= 2) {
    final rotation = order % gen.options.length;
    final rotated = rotateOptions(gen.options, rotation);
    final correctIndex = rotateIndex(gen.correctIndex, rotation, gen.options.length);
    return (question: gen.question, options: rotated, correctIndex: correctIndex);
  }
  return _fallbackRecall(node, order, relatedLabels);
}

({String instruction, String referenceAnswer}) _buildApply(
  KnowledgeNode node,
  _ActivityGenResult generated,
) {
  final gen = generated.apply;
  if (gen != null && gen.instruction.trim().isNotEmpty) {
    return (instruction: gen.instruction, referenceAnswer: gen.referenceAnswer);
  }
  return _fallbackApply(node);
}

String _fallbackExample(KnowledgeNode node) {
  if (node.analogy != null && node.analogy!.isNotEmpty) {
    return '\u0410\u043d\u0430\u043b\u043e\u0433\u0438\u044f: ${node.analogy}';
  }
  return '\u041f\u0440\u0438\u043c\u0435\u0440 \u043f\u043e\u043d\u044f\u0442\u0438\u044f \u00ab${node.label}\u00bb: ${node.oneLiner} \u2014 \u0440\u0430\u0441\u0441\u043c\u043e\u0442\u0440\u0438\u0442\u0435 \u044d\u0442\u043e \u043d\u0430 \u043e\u0434\u043d\u043e\u043c \u043f\u0440\u043e\u0441\u0442\u043e\u043c \u0441\u043b\u0443\u0447\u0430\u0435 \u0438\u0437 \u0442\u0435\u043c\u044b.';
}

({String question, List<String> options, int correctIndex}) _fallbackRecall(
  KnowledgeNode node,
  int order, [
  List<String> relatedLabels = const [],
]) {
  // Дистракторы — осмысленные определения соседних понятий (siblings/relations).
  final distractors = <String>[];
  for (final label in relatedLabels) {
    if (label.isEmpty || label == node.oneLiner || distractors.contains(label)) continue;
    distractors.add(label);
    if (distractors.length >= 3) break;
  }
  const generic = [
    '\u041f\u043e\u043d\u044f\u0442\u0438\u0435, \u043e\u0431\u0440\u0430\u0442\u043d\u043e\u0435 \u0438\u0437\u0443\u0447\u0430\u0435\u043c\u043e\u043c\u0443',
    '\u0422\u0435\u0440\u043c\u0438\u043d \u0438\u0437 \u0434\u0440\u0443\u0433\u043e\u0433\u043e \u0440\u0430\u0437\u0434\u0435\u043b\u0430 \u0442\u0435\u043c\u044b',
    '\u0421\u043b\u0443\u0447\u0430\u0439\u043d\u0430\u044f \u043a\u043e\u043c\u0431\u0438\u043d\u0430\u0446\u0438\u044f \u0442\u0435\u0437\u0438\u0441\u043e\u0432',
  ];
  for (final label in generic) {
    if (distractors.contains(label)) continue;
    distractors.add(label);
    if (distractors.length >= 3) break;
  }
  final options = [
    node.oneLiner.isNotEmpty ? node.oneLiner : '\u0412\u0435\u0440\u043d\u044b\u0439 \u043e\u0442\u0432\u0435\u0442 \u2014 \u0432 \u043e\u043f\u0440\u0435\u0434\u0435\u043b\u0435\u043d\u0438\u0438 \u043f\u043e\u043d\u044f\u0442\u0438\u044f',
    ...distractors.take(3),
  ];
  final rotation = order % options.length;
  final rotated = rotateOptions(options, rotation);
  final correctIndex = rotateIndex(0, rotation, options.length);
  return (
    question: '\u0427\u0442\u043e \u043e\u0437\u043d\u0430\u0447\u0430\u0435\u0442 \u043f\u043e\u043d\u044f\u0442\u0438\u0435 \u00ab${node.label}\u00bb?',
    options: rotated,
    correctIndex: correctIndex,
  );
}

({String instruction, String referenceAnswer}) _fallbackApply(KnowledgeNode node) {
  return (
    instruction:
        '\u041e\u0431\u044a\u044f\u0441\u043d\u0438\u0442\u0435 \u0441\u0432\u043e\u0438\u043c\u0438 \u0441\u043b\u043e\u0432\u0430\u043c\u0438, \u043a\u0430\u043a \u043f\u043e\u043d\u044f\u0442\u0438\u0435 \u00ab${node.label}\u00bb \u043f\u0440\u0438\u043c\u0435\u043d\u044f\u0435\u0442\u0441\u044f \u043d\u0430 \u043f\u0440\u0430\u043a\u0442\u0438\u043a\u0435. \u041f\u0440\u0438\u0432\u0435\u0434\u0438\u0442\u0435 \u043e\u0434\u0438\u043d \u0441\u043e\u0431\u0441\u0442\u0432\u0435\u043d\u043d\u044b\u0439 \u043f\u0440\u0438\u043c\u0435\u0440 \u0438\u0437 \u0440\u0435\u0430\u043b\u044c\u043d\u043e\u0439 \u0436\u0438\u0437\u043d\u0438 \u0438\u043b\u0438 \u0437\u0430\u0434\u0430\u0447\u0438.',
    referenceAnswer: node.oneLiner.isNotEmpty ? node.oneLiner : node.details,
  );
}

// ─── Rotation helpers ─────────────────────────────────────────────────────────

List<T> rotateOptions<T>(List<T> options, int shift) {
  if (options.isEmpty || shift == 0) return options;
  final n = options.length;
  final shiftMod = ((shift % n) + n) % n;
  return [for (var i = 0; i < n; i++) options[(i + shiftMod) % n]];
}

int rotateIndex(int index, int shift, int length) {
  if (length == 0) return 0;
  return ((index - ((shift % length) + length) % length) + length) % length;
}

int nextPendingIndex(List<ActivityStep> steps) {
  for (var i = 0; i < steps.length; i++) {
    if (steps[i].status == 'pending' || steps[i].status == 'current') return i;
  }
  return -1;
}

({String? itemId, List<ActivityStep> steps}) parseActivityBlob(String raw) {
  try {
    final parsed = jsonDecode(raw.isEmpty ? '{}' : raw);
    if (parsed is List) {
      return (
        itemId: null,
        steps: parsed
            .whereType<Map<String, dynamic>>()
            .map(ActivityStep.fromJson)
            .toList(),
      );
    }
    if (parsed is Map<String, dynamic>) {
      final stepsRaw = parsed['steps'];
      if (stepsRaw is List) {
        return (
          itemId: parsed['itemId'] as String?,
          steps: stepsRaw
              .whereType<Map<String, dynamic>>()
              .map(ActivityStep.fromJson)
              .toList(),
        );
      }
    }
    return (itemId: null, steps: <ActivityStep>[]);
  } catch (_) {
    return (itemId: null, steps: <ActivityStep>[]);
  }
}

// ─── Prompt building (inline) ────────────────────────────────────────────────

const _noMetaRule = 'Не отвечайте на вопрос внутри формулировок.';
const _alphabetRule = 'Все тексты на русском языке.';

String _buildActivityPrompt({
  required String topic,
  required String goal,
  required String targetLevel,
  required _NodeContext node,
}) {
  return '''# Роль
Ты — AI-репетитор. Готовишь учебный материал для одного понятия внутри структурированной сессии изучения темы.

# Контекст
Тема: "$topic"
Цель сессии: "$goal"
Целевой уровень усвоения: "$targetLevel"
Понятие: "${node.label}"
Определение: "${node.oneLiner.length > 400 ? node.oneLiner.substring(0, 400) : node.oneLiner}"
Подробное объяснение: "${node.details.length > 1200 ? node.details.substring(0, 1200) : node.details}"
Тип понятия: "${node.conceptType ?? 'концепция'}"
Сложность: ${node.difficulty.toStringAsFixed(2)}

# Задача
Для этого понятия подготовь три элемента учебного цикла:
1. example — конкретный, узнаваемый пример применения данного понятия (2–4 предложения, простым языком).
2. recall — вопрос на припоминание (multiple choice) из 4 вариантов. Вопрос проверяет понимание понятия, а не заучивание формулировок.
3. apply — открытое задание на применение понятия в новой ситуации + эталонный ответ (reference_answer), которым репетитор сверит ответ ученика.

Требования:
- Все тексты на русском языке, простым языком, по уровню цели ученика.
- example должен быть конкретным и новым (не из определения).
- Один из 4 вариантов recall — правильный, остальные правдоподобные, но неверные (типичные ошибки).
- apply формулируется как практическое микрозадание, решаемое за 1–3 минуты.
- Не отвечайте на вопрос внутри формулировок.
$_noMetaRule
$_alphabetRule

# Формат ответа
Строго JSON без markdown:
{
  "example": "строка",
  "recall": { "question": "строка", "options": ["а", "б", "в", "г"], "correct_index": 0 },
  "apply": { "instruction": "строка", "reference_answer": "строка" }
}''';
}

String _buildActivityFeedbackPrompt({
  required String nodeLabel,
  required String nodeOneLiner,
  required String instruction,
  required String referenceAnswer,
  required String userAnswer,
}) {
  String truncate(String s, int max) => s.length > max ? s.substring(0, max) : s;
  return '''# Роль
Ты — AI-репетитор. Оцениваешь свободный ответ ученика на задание по конкретному понятию.

# Контекст
Понятие: "$nodeLabel"
Определение: "${truncate(nodeOneLiner, 400)}"
Задание: "${truncate(instruction, 600)}"
Эталонный ответ: "${truncate(referenceAnswer, 800)}"
Ответ ученика: "${truncate(userAnswer, 1500)}"

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
}
