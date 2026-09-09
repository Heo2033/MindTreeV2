import '../models/models.dart';
import '../../data/database/mindtree_repository.dart';
import '../../data/llm/scheduler.dart';
import '../../data/llm/client.dart';
import 'learner_model_service.dart';
import 'review_scheduler.dart';
import 'event_bus.dart';

class CreateSessionInput {
  final String? journeyId;
  final String topicId;
  final String goal;
  final int timeBudgetMinutes;
  final String? milestoneId;

  const CreateSessionInput({
    this.journeyId,
    required this.topicId,
    required this.goal,
    required this.timeBudgetMinutes,
    this.milestoneId,
  });
}

class LearningSessionEngine {
  final MindtreeRepository repo;
  final TreeScheduler scheduler;
  final LearnerModelService learnerModel;
  final ReviewScheduler reviewScheduler;
  final EventBus eventBus;

  LearningSessionEngine({
    required this.repo,
    required this.scheduler,
    required this.learnerModel,
    required this.reviewScheduler,
    required this.eventBus,
  });

  Future<LearningSession> create(CreateSessionInput input) async {
    var journeyId = input.journeyId;
    if (journeyId == null) {
      journeyId = 'journey_${_shortId()}';
      await repo.createJourney(journeyId, input.topicId);
    }

    final nodes = await repo.listNodes(input.topicId);
    final ordered = _readingOrder(nodes);
    final targetLevel = await _getTargetLevel(input.topicId);
    final topic = await repo.getTopic(input.topicId);
    final topicName = topic?.name ?? '';
    final currentLevel = await learnerModel.getCurrentLevel(input.topicId);

    final curriculum = await _generateCurriculum(
      topicId: input.topicId,
      topicName: topicName,
      goal: input.goal,
      targetLevel: targetLevel,
      currentLevel: currentLevel,
      timeBudgetMinutes: input.timeBudgetMinutes,
      nodes: ordered,
    );

    final sessionId = 'session_${_shortId()}';
    final session = LearningSession(
      id: sessionId,
      journeyId: journeyId,
      milestoneId: input.milestoneId,
      topicId: input.topicId,
      goal: input.goal,
      timeBudgetMinutes: input.timeBudgetMinutes,
      startedAt: DateTime.now().toIso8601String(),
      status: SessionStatus.active,
      curriculum: Curriculum(
        sessionId: sessionId,
        items: curriculum.items,
        totalEstimatedMinutes: curriculum.totalEstimatedMinutes,
      ),
      currentIndex: 0,
    );

    await repo.createSession(session);
    await eventBus.emit(
      sessionId: sessionId,
      topicId: input.topicId,
      kind: 'session_started',
      payload: {'goal': input.goal},
    );

    return session;
  }

  Future<LearningSession?> getSession(String sessionId) async =>
      repo.getSession(sessionId);

  Future<({CurriculumItem item, int index, Curriculum curriculum})?>
      getCurrentItem(String sessionId) async {
    final session = await getSession(sessionId);
    if (session == null) return null;
    if (session.currentIndex >= session.curriculum.items.length) return null;
    final item = session.curriculum.items[session.currentIndex];
    return (item: item, index: session.currentIndex, curriculum: session.curriculum);
  }

  Future<({
    Map<String, dynamic> content,
    KnowledgeNode node,
  })> studyNode(String sessionId, String nodeId) async {
    final session = await getSession(sessionId);
    if (session == null) throw Exception('Session not found');

    final node = await repo.getNode(nodeId);
    if (node == null || node.topicId != session.topicId) throw Exception('Node not found');

    if (!node.contentLoaded) {
      final path = await _nodePath(session.topicId, nodeId);
      final siblingNodes = await _siblings(session.topicId, node.parentId ?? '');
      final topic = await repo.getTopic(session.topicId);
      final topicName = topic?.name ?? '';
      final level = await learnerModel.getCurrentLevel(session.topicId);
      final knowledgeLevel = _masteryLevelToKnowledgeLevel(level);

      final ontologyContext = StringBuffer();
      if (node.oneLiner.isNotEmpty) {
        ontologyContext.writeln('Каноническое определение: ${node.oneLiner}');
      }
      if (node.conceptType != null) {
        ontologyContext.writeln('Ось классификации: ${node.conceptType!.raw}');
      }

      final prompt = _buildContentPrompt(
        rootTopic: topicName,
        nodePath: path,
        siblings: siblingNodes,
        knowledgeLevel: knowledgeLevel,
        goal: session.goal,
        nodeLevel: node.level,
        isRoot: node.level <= 1 && node.parentId == null,
        isCriticalDomain: _isCriticalDomain(topicName, path),
        ontologyContext: ontologyContext.toString(),
        nodeId: node.id,
        nodeTitle: node.label,
      );

      Map<String, dynamic> content;
      try {
        final res = await scheduler.execute<Map<String, dynamic>>(
          'content',
          () => prompt,
          (raw) => parseLLMJson<Map<String, dynamic>>(raw),
        );
        content = {
          'one_liner': (res.result['one_liner'] as String?) ?? node.oneLiner,
          'details': (res.result['details'] as String?) ?? node.details,
          'analogy': res.result['analogy'] != null &&
                  (res.result['analogy'] as String).isNotEmpty
              ? res.result['analogy']
              : null,
          'relations': res.result['relations'] is List ? res.result['relations'] : <dynamic>[],
          'sources': res.result['sources'] is List
              ? (res.result['sources'] as List).map((e) => e.toString()).toList()
              : <String>[],
        };
      } catch (_) {
        content = {
          'one_liner': node.oneLiner,
          'details': node.details,
          'relations': <dynamic>[],
          'sources': <String>[],
        };
      }

      final updatedNode = node.copyWith(
        oneLiner: content['one_liner'] as String,
        details: content['details'] as String,
        analogy: () => content['analogy'] as String?,
        sources: content['sources'] as List<String>,
        contentLoaded: true,
        state: NodeState.contentGenerated,
      );
      await repo.updateNode(updatedNode);

      await eventBus.emit(
        sessionId: sessionId,
        topicId: session.topicId,
        kind: 'explain',
        nodeId: nodeId,
        payload: {'label': node.label},
      );

      final fetched = await repo.getNode(nodeId) ?? updatedNode;
      return (content: content, node: fetched);
    } else {
      await eventBus.emit(
        sessionId: sessionId,
        topicId: session.topicId,
        kind: 'explain',
        nodeId: nodeId,
        payload: {'label': node.label},
      );
      return (
        content: {
          'one_liner': node.oneLiner,
          'details': node.details,
          'analogy': node.analogy,
          'sources': node.sources,
        },
        node: node,
      );
    }
  }

  Future<void> markItemCompleted(
    String sessionId,
    String itemId, {
    String? nodeId,
    String quality = 'correct',
  }) async {
    final session = await getSession(sessionId);
    if (session == null) return;

    final items = [
      for (final it in session.curriculum.items)
        it.id == itemId ? it.copyWith(status: CurriculumItemStatus.completed) : it,
    ];
    final maxIdx = (items.length - 1).clamp(0, items.length - 1);
    final nextIdx = (session.currentIndex + 1).clamp(0, maxIdx);

    final updated = session.copyWith(
      curriculum: Curriculum(
        sessionId: sessionId,
        items: items,
        totalEstimatedMinutes: session.curriculum.totalEstimatedMinutes,
      ),
      currentIndex: nextIdx,
      activityJson: () => null,
      currentActivityStep: 0,
    );
    await repo.updateSession(updated);

    if (nodeId != null) {
      await reviewScheduler.onAnswered(session.topicId, nodeId, quality);
    }

    final completedCount = items.where((i) => i.status == CurriculumItemStatus.completed).length;
    final progress = items.isNotEmpty ? completedCount / items.length : 0.0;
    await eventBus.emit(
      sessionId: sessionId,
      topicId: session.topicId,
      kind: 'item_completed',
      nodeId: nodeId,
      payload: {'itemId': itemId, 'progress': progress},
    );
  }

  Future<String> generateFinalAssessment(String sessionId) async {
    final session = await getSession(sessionId);
    if (session == null) throw Exception('Session not found');

    final studiedNodeIds = session.curriculum.items
        .where((i) => i.status == CurriculumItemStatus.completed && i.nodeId.isNotEmpty)
        .map((i) => i.nodeId)
        .toList();

    final items = studiedNodeIds.isNotEmpty
        ? [for (final nid in studiedNodeIds) await _nodeBrief(session.topicId, nid)]
        : await _allNodeBriefs(session.topicId);

    final assessmentId = 'assess_${_shortId()}';
    final assessment = Assessment(
      id: assessmentId,
      sessionId: sessionId,
      type: AssessmentType.final_,
      startedAt: DateTime.now().toIso8601String(),
      questions: await _generateAssessmentQuestions(session.topicId, items),
    );
    await repo.createAssessment(assessment);

    await eventBus.emit(
      sessionId: sessionId,
      topicId: session.topicId,
      kind: 'assessment',
      payload: {'assessmentId': assessmentId},
    );

    return assessmentId;
  }

  // ─── Private helpers ──────────────────────────────────────────────────────

  Future<Curriculum> _generateCurriculum({
    required String topicId,
    required String topicName,
    required String goal,
    required String targetLevel,
    required MasteryLevel currentLevel,
    required int timeBudgetMinutes,
    required List<KnowledgeNode> nodes,
  }) async {
    final nodesJson = nodes
        .take(40)
        .map((n) => '{"id":"${n.id}","label":"${n.label}","level":${n.level},"difficulty":${n.difficulty}}')
        .join(',');

    final prompt = '''# Роль
Ты — AI-методист. Составь учебный план (curriculum) для сессии изучения темы.

# Контекст
Тема: "$topicName"
Цель: "$goal"
Целевой уровень: "$targetLevel"
Текущий уровень: "${currentLevel.raw}"
Время (мин): $timeBudgetMinutes

# Узлы темы (в порядке изучения):
[$nodesJson]

# Задача
Сгенерируй JSON учебного плана — отсортированный список концептов для изучения.
Каждый элемент:
- id: уникальный идентификатор (itemId_N)
- nodeId: id узла из дерева
- label: краткое название
- order: порядковый номер (с 1)
- type: "explain"
- estimatedMinutes: оценка времени в минутах (целое)
- priority: приоритет 0.0–1.0
- status: "pending"
- reason: краткое объяснение почему этот концепт включён

Покрой все叶子 узлы. Суммарное estimatedMinutes ≤ $timeBudgetMinutes.

# Формат
Строго JSON:
{"sessionId":"","items":[...],"totalEstimatedMinutes":N}''';

    try {
      final res = await scheduler.execute<Map<String, dynamic>>(
        'curriculum',
        () => prompt,
        (raw) => parseLLMJson<Map<String, dynamic>>(raw),
      );
      final itemsRaw = res.result['items'] as List<dynamic>? ?? [];
      final items = itemsRaw
          .whereType<Map<String, dynamic>>()
          .map(CurriculumItem.fromJson)
          .toList();
      return Curriculum(
        sessionId: '',
        items: items,
        totalEstimatedMinutes: (res.result['totalEstimatedMinutes'] as num?)?.toInt() ??
            items.fold<int>(0, (s, i) => s + i.estimatedMinutes),
      );
    } catch (_) {
      final items = nodes.take(12).toList().asMap().entries.map((e) {
        final i = e.key;
        final n = e.value;
        return CurriculumItem(
          id: 'itemId_${i + 1}',
          nodeId: n.id,
          label: n.label,
          order: i + 1,
          type: CurriculumItemType.explain,
          estimatedMinutes: n.estimatedTimeMinutes,
          priority: n.importance,
          status: CurriculumItemStatus.pending,
        );
      }).toList();
      return Curriculum(
        sessionId: '',
        items: items,
        totalEstimatedMinutes: items.fold<int>(0, (s, i) => s + i.estimatedMinutes),
      );
    }
  }

  Future<({String nodeId, String label, String oneLiner, String details})>
      _nodeBrief(String topicId, String nodeId) async {
    final node = await repo.getNode(nodeId);
    if (node == null || node.topicId != topicId) {
      return (nodeId: nodeId, label: '', oneLiner: '', details: '');
    }
    return (
      nodeId: node.id,
      label: node.label,
      oneLiner: node.oneLiner,
      details: node.details,
    );
  }

  Future<List<({String nodeId, String label, String oneLiner, String details})>>
      _allNodeBriefs(String topicId) async {
    final nodes = await repo.listNodes(topicId);
    return nodes.where((n) => n.leaf).take(12).map((n) => (
          nodeId: n.id,
          label: n.label,
          oneLiner: n.oneLiner,
          details: n.details,
        )).toList();
  }

  Future<List<String>> _nodePath(String topicId, String nodeId) async {
    final nodes = await repo.listNodes(topicId);
    final byId = {for (final n in nodes) n.id: n};
    final path = <String>[];
    KnowledgeNode? current = byId[nodeId];
    var guard = 0;
    while (current != null && guard < 50) {
      path.insert(0, current.label);
      current = current.parentId != null ? byId[current.parentId] : null;
      guard++;
    }
    return path;
  }

  Future<List<String>> _siblings(String topicId, String parentId) async {
    final nodes = await repo.listNodes(topicId);
    return nodes
        .where((n) => n.parentId == parentId && n.id != parentId)
        .map((n) => n.label)
        .take(8)
        .toList();
  }

  Future<String> _getTargetLevel(String topicId) async {
    final topic = await repo.getTopic(topicId);
    return topic?.targetLevel.raw ?? 'basic_understanding';
  }

  Future<List<AssessmentQuestion>> _generateAssessmentQuestions(
    String topicId,
    List<({String nodeId, String label, String oneLiner, String details})> items,
  ) async {
    final itemsJson = items
        .map((i) => '{"nodeId":"${i.nodeId}","label":"${i.label}","oneLiner":"${i.oneLiner}"}')
        .join(',');
    final prompt = '''# Роль
Ты — AI-тестолог. Сгенерируй финальную проверку для сессии.

# Узлы:
[$itemsJson]

# Задача
Сгенерируй 6 вопросов разного типа (recognition, recall, explanation, application, diagnosis, transfer).
Каждый вопрос:
- id: question_N
- nodeId: id узла
- type: тип вопроса
- question: текст вопроса
- options: 4 варианта ответа
- correctAnswer: правильный ответ
- explanation: объяснение

# Формат
Строго JSON:
{"questions":[...]}''';

    try {
      final res = await scheduler.execute<Map<String, dynamic>>(
        'assessment',
        () => prompt,
        (raw) => parseLLMJson<Map<String, dynamic>>(raw),
      );
      final questionsRaw = res.result['questions'] as List<dynamic>? ?? [];
      return questionsRaw
          .whereType<Map<String, dynamic>>()
          .map(AssessmentQuestion.fromJson)
          .toList();
    } catch (_) {
      return items.take(3).map((i) => AssessmentQuestion(
            id: 'q_${i.nodeId}',
            type: QuestionType.recognition,
            nodeId: i.nodeId,
            question: 'Что означает понятие «${i.label}»?',
            options: [
              i.oneLiner.isNotEmpty ? i.oneLiner : 'Верный ответ',
              'Понятие, обратное изучаемому',
              'Термин из другого раздела',
              'Нерелевантный ответ',
            ],
            correctAnswer: i.oneLiner.isNotEmpty ? i.oneLiner : 'Верный ответ',
          )).toList();
    }
  }

  static String _shortId() {
    final hex = DateTime.now().millisecondsSinceEpoch.toRadixString(16);
    return hex.substring(hex.length - 8);
  }

  static List<KnowledgeNode> _readingOrder(List<KnowledgeNode> nodes) {
    final sorted = List<KnowledgeNode>.from(nodes)
      ..sort((a, b) {
        if (a.level != b.level) return a.level.compareTo(b.level);
        return b.importance.compareTo(a.importance);
      });
    return sorted;
  }
}

// ─── MasteryLevel → KnowledgeLevel mapping ────────────────────────────────────

const _noMetaRule = 'Не отвечайте на вопрос внутри формулировок.';
const _alphabetRule = 'Все тексты на русском языке.';

String _masteryLevelToKnowledgeLevel(MasteryLevel level) {
  switch (level) {
    case MasteryLevel.awareness:
    case MasteryLevel.basicUnderstanding:
      return 'beginner';
    case MasteryLevel.solidUnderstanding:
    case MasteryLevel.practicalApplication:
      return 'intermediate';
    case MasteryLevel.advanced:
    case MasteryLevel.expert:
      return 'expert';
  }
}

// ─── Critical domain detection (§64) ─────────────────────────────────────────

const _criticalDomainKeywords = [
  'медицина', 'медицин', 'фармаколог', 'фармац', 'терапи', 'хирург',
  'патолог', 'анатом', 'физиолог', 'клини', 'диагност',
  'law', 'право', 'юрис', 'уголовн', 'гражданск',
  'finance', 'финанс', 'экономик', 'бухгалт', 'налог',
  'medicine', 'medical', 'pharmacolog', 'clinical', 'surgery',
  'legal', 'jurisprud',
  'exam', 'экзамен', 'сертиф', ' licens',
  'наук', 'scientific', 'исследован',
];

bool _isCriticalDomain(String topicName, List<String> nodePath) {
  final text = ([topicName] + nodePath).join(' ').toLowerCase();
  return _criticalDomainKeywords.any((kw) => text.contains(kw));
}

// ─── Content prompt builder (§64: sources for critical domains) ──────────────

const _contentLevelTones = <String, String>{
  'beginner':
      'Пиши максимально доступно для новичка, без профессионального жаргона. Каждый специальный термин объясняй сразу простыми словами.',
  'intermediate':
      'Пиши для знакомого с основами читателя. Термины раскрывай через интуицию: сначала «как работает», затем термин.',
  'expert':
      'Пиши для специалиста, используй точную терминологию. Можно опускать базовые объяснения.',
};

const _contentGoalHints = <String, String>{
  'overview': 'Цель — общий обзор: опиши суть и место понятия в теме, без глубоких деталей.',
  'exam': 'Цель — подготовка к экзамену: делай акцент на ключевых фактах, определениях и формулировках.',
  'deep':
      'Цель — глубокое изучение: кроме сути кратко обозначь механизм/устройство и подтемы, которые стоит разобрать.',
};

const _rootGuidance = '''
# Корневой узел (обзор темы)
Это корневой/обзорный узел. СТРОГО соблюдай:
- ТОЛЬКО интуиция «как это работает» + краткий перечень подтем (roadmap «что разберём дальше»).
- НЕ углубляйся в механику, математику и формулы на корневом узле — это задача дочерних узлов.
- Для цели deep особенно: покажи «зачем» и «что дальше», а не сжатую сводку.
- Не противоречь дочерним узлам — не опережай их content.''';

const _antiJargonRule = '''
# Антижаргон (обязательное правило)
- КАЖДЫЙ специальный термин (например «градиент лог-плотности», «score», «марковская цепь», «максимизация правдоподобия») объясни простыми словами в ТОМ ЖЕ предложении.
- ЗАПРЕЩЕНО использовать термин, который ты не можешь объяснить простыми словами без жаргона.
- ЗАПРЕЩЕНО давать плотную энциклопедическую выжимку: обучай читателя, а не перечисляй термины.
- Если термин не влияет на понимание сути — опусти его.''';

const _detailsInstruction =
    '1–2 предложения (макс. 500 символов). Факты, цифры, ключевые свойства. Если понятие включает формулу или математическое выражение, записывай его в LaTeX: инлайн — \$формула\$, блочная — \$\$формула\$\$.';

const _twoPartDetailsBlock = '''
# Структура подробностей
Для этой аудитории и цели (intermediate/beginner + deep) оформи details в ДВА абзаца, разделённых пустой строкой (\n\n), начинающихся со следующих заголовков:
1. «Интуиция:» — 1–2 предложения простыми словами, БЕЗ терминов: как это работает.
2. «Механика:» — ключевые термины/механизм, но КАЖДЫЙ термин сопровождай однострочным пояснением сразу после него.
Не вылезай за лимит символов.''';

const _rootFormulaBan = '''
# Формулы на корневом узле
Это корневой узел. НЕ пиши голые математические формулы. Опиши смысл словами (например: «сеть по более зашумленному кадру восстанавливает чуть менее зашумлённый»). Формулы и математика — на дочерние узлы.''';

String _buildContentPrompt({
  required String rootTopic,
  required List<String> nodePath,
  required List<String> siblings,
  String? knowledgeLevel,
  String? goal,
  int nodeLevel = 1,
  bool isRoot = false,
  bool isCriticalDomain = false,
  String ontologyContext = '',
  required String nodeId,
  required String nodeTitle,
}) {
  final sanitizedTopic = rootTopic
      .replaceAll('\r', '')
      .replaceAll(RegExp(r'^#+\s', multiLine: true), '')
      .replaceAll(RegExp(r'^[-*]\s', multiLine: true), '')
      .trim();

  final tone = knowledgeLevel != null && _contentLevelTones.containsKey(knowledgeLevel)
      ? '\n# Аудитория\n${_contentLevelTones[knowledgeLevel]}\n'
      : '';

  final goalBlock = goal != null && _contentGoalHints.containsKey(goal)
      ? '\n# Цель\n${_contentGoalHints[goal]}\n'
      : '';

  final rootBlock = isRoot || nodeLevel == 1 ? _rootGuidance : '';
  final antiJargon = knowledgeLevel != null && knowledgeLevel != 'expert' ? _antiJargonRule : '';
  final twoPartDetails = knowledgeLevel != null && knowledgeLevel != 'expert' && goal == 'deep'
      ? _twoPartDetailsBlock
      : '';
  final rootFormulaBan = isRoot || nodeLevel == 1 ? _rootFormulaBan : '';

  final sourcesBlock = isCriticalDomain
      ? '# Источники (§64: factual reliability)\nЭта тема относится к критически важной области (медицина, право, финансы, наука, экзамен).\nВключи в JSON поле sources — массив из 2–4 наиболее авторитетных источников.\nНе придумывай источники — указывай только реальные, общепризнанные.\nЕсли достоверных источников нет — верни "sources": [].\n'
      : '';
  final sourcesFormatNote = isCriticalDomain
      ? 'Если sources запрошены: "sources": ["источник1", "источник2"].\nЕсли sources нет: "sources": [].'
      : 'Если sources нет: "sources": [].';

  return '''# Роль
Ты — эксперт-энциклопедист. Дай точное, краткое описание понятия.

# Контекст
Тема: "$sanitizedTopic"
Путь: ${nodePath.join(' → ')}
Соседи: ${siblings.join(', ')}
$tone$goalBlock
$rootBlock
$rootFormulaBan
$ontologyContext
# Задача
Опиши узел «$nodeTitle»:

- one_liner — СУТЬ в одном предложении (макс. 120 символов). Без воды, без вводных фраз. Прямо к делу.
- details — КРАТКАЯ справка. $_detailsInstruction
- analogy — НЕОБЯЗАТЕЛЬНО: бытовая метафора, 1 предложение (макс. 120 символов). Если метафора не приходит в голову — верни "".
- relations — СВЯЗИ с другими понятиями (см. формат ниже). Генерируй 2–4 связи, если они есть.

$twoPartDetails
- analogy — НЕОБЯЗАТЕЛЬНО: бытовая метафора, 1 предложение (макс. 120 символов). Если метафора не приходит в голову — верни "".
- relations — СВЯЗИ с другими понятиями (см. формат ниже). Генерируй 2–4 связи, если они есть.

# Типы связей
- related — общая связь
- depends_on — зависит от
- requires — требует знания
- example_of — является примером
- similar_to — похоже на
- contrasts_with — противоположно
- causes — вызывает
- enables — позволяет/делает возможным
- used_for — используется для
- alternative_to — альтернатива
- derives_from — вытекает из
- parameterizes — параметризует
- approximates — аппроксимирует
- generalizes — обобщает
- implements — реализует
- explains_why — объясняет почему (цепочка «зачем?»)

# Антипаттерны (НЕ пиши)
- "Данное понятие означает..."
- "В системе Таро это..."
- "Является важной частью..."
- "Описывает сферу..."
- Повторение родителя или детей
- Общие фразы без конкретики

# Правила
- Факты > рассуждений.
- Конкретика > абстракции.
- Если у понятия есть компоненты — перечисли их.
- Если понятие — конкретный объект (карта, термин) — опиши его функцию, не общую теорию.
- В relations указывай id узлов из дерева. Если подходящего id нет — не генерируй связь.
- Используй canonical_definition как основу для details. Не противоречь ему.
- Не нарушай forbidden_interpretations — не утверждай то, что запрещено.
- Не смешивай semantic_axis — не описывай архитектуру как процесс и наоборот.
- Не противоречь parent, ancestors и siblings.
$_noMetaRule
$antiJargon
$_alphabetRule
$sourcesBlock
# Язык
Отвечай СТРОГО на русском языке.
Все термины в one_liner и details — на русском. Исключение: устоявшиеся аббревиатуры
(U-Net, DDPM, VAE, CLIP, Stable Diffusion, ControlNet, DiT, NeRF, DDIM и т.д.).
Всё остальное переводи.

# Формат
Только JSON:
{"one_liner":"...","details":"...","analogy":"...","relations":[{"from":"id_этого_узла","to":"id_другого_узла","type":"requires","label":"опционально"}],"claims":[{"subject":"название_узла","predicate":"is_a","object":"категория"}],"sources":["URL_or_название_источника"]}

Claims — список утверждений. Predicates: is_a, has_a, part_of, alternative_to, implements, requires, enables, contradicts, depends_on, related_to.
$sourcesFormatNote

Если analogy не нужна: "analogy": "".
Если relations нет: "relations": [].
Если claims нет: "claims": [].
В поле from используй id текущего узла: "$nodeId".

Никакого текста вне JSON.''';
}
