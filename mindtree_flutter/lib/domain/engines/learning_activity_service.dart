import 'dart:convert';
import 'dart:developer' as developer;

import '../models/models.dart';
import '../../data/database/mindtree_repository.dart';
import '../../data/llm/scheduler.dart';
import '../../data/llm/client.dart';
import '../../data/prompts/prompts.dart';
import 'package:mindtree_flutter/domain/lib/activity_blob.dart';
import 'feedback_engine.dart';
import 'learning_session_engine.dart';

class LearningActivityService {
  final LearningSessionEngine engine;
  final MindtreeRepository repo;
  final TreeScheduler scheduler;

  /// Оценка ответов и запись модели ученика живут здесь, а не в приватных
  /// копиях сервиса: `FeedbackEngine` владеет единственной формулой накопления
  /// измерений, SRS и типологией мисконцепций.
  final FeedbackEngine feedback;

  LearningActivityService({
    required this.engine,
    required this.repo,
    required this.scheduler,
    required this.feedback,
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

    // Открываем границу времени на работу с текущим узлом.
    engine.eventBus.markUnitStart(sessionId);
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
    final topic = await repo.getTopic(session.topicId);
    final topicName = topic?.name ?? '';

    if (step.type == 'recall') {
      final chosenIndex = _clamp(0, int.tryParse(answer) ?? 0, (step.options?.length ?? 1) - 1);
      final result = await feedback.evaluateRecall(
        session.topicId,
        topicName,
        activity.nodeId,
        nodeLabel,
        RecallStepInput(options: step.options, correctIndex: step.correctIndex),
        chosenIndex,
      );
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
        correct: result.evaluated ? result.correct : null,
        feedback: result.feedback,
      );
      await _persistSteps(sessionId, activity.itemId, updatedSteps);
      // Шаг закрыт: длительность времени на него уходит в событие,
      // следующий шаг стартует с новой границы.
      final spentMs = engine.eventBus.closeUnit(sessionId);
      await engine.eventBus.emit(
        sessionId: sessionId,
        topicId: session.topicId,
        kind: 'activity_answer',
        nodeId: activity.nodeId,
        payload: _answerPayload('recall', result),
        durationMs: spentMs,
      );
      engine.eventBus.markUnitStart(sessionId);
    } else if (step.type == 'apply') {
      final res = await feedback.evaluateApply(session.topicId, topicName, activity.nodeId,
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
        correct: res.evaluated ? res.correct : null,
        feedback: res.feedback,
      );
      await _persistSteps(sessionId, activity.itemId, updatedSteps);
      final spentMs = engine.eventBus.closeUnit(sessionId);
      await engine.eventBus.emit(
        sessionId: sessionId,
        topicId: session.topicId,
        kind: 'activity_answer',
        nodeId: activity.nodeId,
        payload: _answerPayload('apply', res),
        durationMs: spentMs,
      );
      engine.eventBus.markUnitStart(sessionId);
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
      final spentMs = engine.eventBus.closeUnit(sessionId);
      await engine.eventBus.emit(
        sessionId: sessionId,
        topicId: session.topicId,
        kind: 'activity_step_done',
        nodeId: activity.nodeId,
        payload: {'step': step.type},
        durationMs: spentMs,
      );
      engine.eventBus.markUnitStart(sessionId);
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
        () => buildActivityPrompt(
          topic: topicLabel,
          goal: session.goal,
          targetLevel: targetLevel,
          label: nodeData.label,
          oneLiner: nodeData.oneLiner,
          details: nodeData.details,
          conceptType: nodeData.conceptType,
          difficulty: nodeData.difficulty,
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
    final explainText = explainBody(node);
    final rawExample = generated.example.trim().isNotEmpty
        ? generated.example
        : fallbackExample(node);
    final exampleBody = sanitizeExample(node, explainText, rawExample);
    final recall = _buildRecall(node, generated, order, relatedLabels);
    final apply = _buildApply(node, generated);

    final steps = [
      ActivityStep(
        type: 'explain',
        title: '\u0418\u0437\u0443\u0447\u0430\u0435\u043c \u043f\u043e\u043d\u044f\u0442\u0438\u0435',
        body: explainBody(node),
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

  /// Полезная нагрузка события `activity_answer`.
  ///
  /// `score` и `correct` попадают в лог только когда ответ удалось оценить:
  /// при отказе LLM (`evaluated == false`) выдумывать «0.5 за неоценённый
  /// ответ» нельзя — иначе аналитика и ревью считают мусор за данные.
  static Map<String, dynamic> _answerPayload(String step, AnswerFeedback result) => {
        'step': step,
        'evaluated': result.evaluated,
        'correct': result.evaluated ? result.correct : null,
        if (result.evaluated) 'score': result.score,
      };

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
/// one_liner + связи — но не голый one_liner. Аналогия НЕ включается:
/// она отдаётся шагу «пример» (fallbackExample), иначе оба шага дублируются.
String explainBody(KnowledgeNode node) {
  if (node.details.isNotEmpty) return node.details;
  final parts = <String>[node.oneLiner];
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
        options: (j['options'] as List<dynamic>? ?? [])
            .whereType<String>()
            .toList(),
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
    final ref = gen.referenceAnswer.trim();
    // Задание спрашивает про применение, поэтому «образец» обязан отвечать
    // про применение. Пересказ определения тут врёт: ученика просят назвать
    // применение, а сверяют с определением — и он получает «Есть ошибки».
    if (isUsableReferenceAnswer(ref, node)) {
      return (instruction: gen.instruction.trim(), referenceAnswer: ref);
    }
  }
  return _fallbackApply(node);
}

/// Защита от дубля «пример повторяет объяснение»: если LLM/fallback вернул
/// для примера тот же текст, что в шаге «объяснение», подменяем его на
/// fallback-пример (аналогия либо нейтральная иллюстрация) — иначе
/// пользователь видит одинаковые шаги подряд.
String ensureDistinctExample(KnowledgeNode node, String explainBody, String example) {
  final a = example.trim();
  final b = explainBody.trim();
  if (a.isEmpty) return fallbackExample(node);
  if (b.isNotEmpty && (a == b || a.contains(b) || b.contains(a))) {
    return fallbackExample(node);
  }
  return a;
}

/// Шаг «Разбираем пример» обязан содержать пример, а не задание ученику.
///
/// Модель регулярно кладёт в `example` императив («Приведите пример…»,
/// «Рассмотрите, как…»), и тогда ученик на шаге «пример» не получает
/// примера вовсе. Такие тексты заменяем на fallback.
String sanitizeExample(KnowledgeNode node, String explainBody, String example) {
  final distinct = ensureDistinctExample(node, explainBody, example);
  if (looksLikeLearnerTask(distinct)) return fallbackExample(node);
  return distinct;
}

/// Маркеры задания, адресованного ученику (2-е лицо, императив).
const _taskMarkers = <String>[
  'приведите', 'приведи', 'рассмотрите', 'рассмотри', 'представь', 'представьте',
  'опишите', 'введите', 'разберите', 'разбери', 'объясните', 'перечислите',
  'сравните', 'проанализируйте', 'придумайте', 'назовите', 'укажите', 'выберите',
  'подумайте', 'попробуйте', 'сформулируйте', 'ответьте', 'задайте вопрос',
];

/// True, если текст — это задание ученику, а не готовый пример.
bool looksLikeLearnerTask(String text) {
  final t = text.trim().toLowerCase();
  if (t.isEmpty) return true;
  if (t.endsWith('?')) return true;
  for (final marker in _taskMarkers) {
    if (t.startsWith(marker)) return true;
  }
  return false;
}

/// Эталонный ответ пригоден, если это развёрнутый ответ по существу и он
/// не является пересказом определения.
bool isUsableReferenceAnswer(String reference, KnowledgeNode node) {
  final r = reference.trim();
  if (r.length < 40) return false;
  return !repeatsDefinition(r, node);
}

/// Определение, на которое опирается понятие; пустая строка — если нет.
String _definitionOf(KnowledgeNode node) =>
    node.oneLiner.trim().isNotEmpty ? node.oneLiner.trim() : node.details.trim();

bool repeatsDefinition(String text, KnowledgeNode node) {
  final t = text.toLowerCase();
  for (final candidate in [node.oneLiner, node.details]) {
    final d = candidate.trim();
    if (d.length < 20) continue;
    if (t.contains(d.toLowerCase())) return true;
    final first = _firstSentence(d);
    if (first.length >= 40 && t.contains(first.toLowerCase())) return true;
  }
  return false;
}

String _firstSentence(String text) {
  for (final terminator in ['. ', '! ', '? ']) {
    final i = text.indexOf(terminator);
    if (i > 0) return text.substring(0, i + 1);
  }
  return text;
}

String _shorten(String text, int max) =>
    text.length <= max ? text : '${text.substring(0, max).trimRight()}…';

/// Fallback «пример». Принципиально НЕ задание ученику: шаг называется
/// «Разбираем пример», и раньше здесь возвращалась инструкция
/// «Приведите один простой пример…» — ученик вместо примера получал задачу.
/// Определение тоже не дублируем (иначе шаг повторяет «объяснение»).
String fallbackExample(KnowledgeNode node) {
  final analogy = node.analogy?.trim() ?? '';
  if (analogy.isNotEmpty) return 'Аналогия: $analogy';
  // Выдуманный «реальный случай» был бы враньём: показываем, где понятие
  // стоит в теме, и честно отправляем за разбором в шаг «Применение».
  final anchors = <String>[];
  for (final r in node.relations) {
    final label = r.label?.trim() ?? '';
    if (label.isNotEmpty && !anchors.contains(label)) anchors.add(label);
    if (anchors.length >= 2) break;
  }
  if (anchors.isEmpty) {
    return 'Для «${node.label}» отдельного разбора в теме нет: это опорное '
        'понятие, от которого отталкиваются остальные. Свой пример вы '
        'разберёте в шаге «Применение».';
  }
  return '«${node.label}» связывает понятия: ${anchors.join(', ')}. '
      'Разбор конкретного примера — в шаге «Применение».';
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

/// Fallback-задание «Применение». Задание и эталон обязаны быть согласованы.
/// Раньше ученика просили только назвать применение, а сверяли с определением —
/// любой честный ответ получал «Есть ошибки». Поэтому fallback спрашивает и о
/// смысле понятия, и о применении, а эталон отвечает на оба пункта.
({String instruction, String referenceAnswer}) _fallbackApply(KnowledgeNode node) {
  final definition = _shorten(_definitionOf(node), 180);
  final analogy = node.analogy?.trim() ?? '';
  final applied = analogy.isNotEmpty
      ? 'Понять это проще всего через аналогию: $analogy'
      : '«${node.label}» нужно там, где без него не обойтись, и именно оно '
          'объясняет, почему задача решается так: $definition';
  return (
    instruction:
        'Своими словами объясните, что такое «${node.label}» и зачем это понятие '
        'нужно в вашей теме. Назовите одну задачу, где оно пригодится.',
    referenceAnswer: '$definition $applied',
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
