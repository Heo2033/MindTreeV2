// Загрузчик учебной сессии из drift/SQLite-базы приложения.
//
// Зачем он нужен: экспорт темы (`mindtree-*.json`) содержит только дерево, а
// качество обучения видно по сессии — что реально спросили, как ученик ответил,
// что замерили и что решили двигаться дальше. Инструмент ревью открывает БД
// ТОЛЬКО НА ЧТЕНИЕ и превращает сессию в плоский `SessionView`.
//
// ─── Почему копия файла, а не открытие оригинала ───────────────────────────────
// Приложение держит `mindtree.db` открытым в WAL-режиме. Чтение оригинала на
// Windows блокируется, а «горячая» копия без `-wal`/`-shm` может дать
// неконсистентный снимок. Поэтому файл и его спутники копируются во временный
// каталог, и уже копия открывается обычным drift. Оригинал не трогаем.
//
// ─── Чего в БД нет ───────────────────────────────────────────────────────────
// * Тайминга по шагам активности: `ActivityStep` не хранит длительность,
//   события — хранят. Поэтому `SessionStepView.durationMs` остаётся 0, а
//   проверка `session_step_duration` честно ругается на отсутствие замера.
// * Снапшота mastery «до»: `learner_models` хранит только текущее состояние.
//   `masteryBefore` пуст, `masteryAfter` заполнен; об этом есть warning.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:mindtree_flutter/data/database/mindtree_db.dart';
import 'package:mindtree_flutter/domain/models/models.dart';

import 'session_checks.dart';

/// Не удалось прочитать БД или сессию. Сообщение — для пользователя CLI.
class SessionLoadException implements Exception {
  final String message;
  const SessionLoadException(this.message);
  @override
  String toString() => message;
}

/// Узел дерева в плоском виде — контекст для отчёта (не для проверок).
class NodeSummary {
  final String id;
  final String label;
  final String oneLiner;
  final int level;
  final bool leaf;
  final String state;
  final double difficulty;
  final int estimatedTimeMinutes;

  const NodeSummary({
    required this.id,
    required this.label,
    this.oneLiner = '',
    this.level = 1,
    this.leaf = false,
    this.state = '',
    this.difficulty = 0.5,
    this.estimatedTimeMinutes = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'oneLiner': oneLiner,
        'level': level,
        'leaf': leaf,
        'state': state,
        'difficulty': difficulty,
        'estimatedTimeMinutes': estimatedTimeMinutes,
      };
}

/// Milestone темы в плоском виде.
class MilestoneSummary {
  final String id;
  final String level;
  final String title;
  final String status;
  final double estimatedHours;

  const MilestoneSummary({
    required this.id,
    required this.level,
    required this.title,
    this.status = '',
    this.estimatedHours = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'level': level,
        'title': title,
        'status': status,
        'estimatedHours': estimatedHours,
      };
}

/// Сессия + контекст, готовые к проверкам и к отчёту.
class LoadedSession {
  /// Плоское представление для проверок (`session_checks.dart`).
  final SessionView view;

  final String sessionId;
  final String topicId;
  final String topicName;

  /// Узлы дерева темы — контекст отчёта и основание для сверки id активностей.
  final List<NodeSummary> nodes;

  final List<MilestoneSummary> milestones;

  /// Проблемы разбора данных: битый JSON, неизвестные поля и т.п.
  final List<String> warnings;

  const LoadedSession({
    required this.view,
    required this.sessionId,
    required this.topicId,
    this.topicName = '',
    this.nodes = const [],
    this.milestones = const [],
    this.warnings = const [],
  });

  Map<String, String> get nodeLabels => {
        for (final n in nodes) n.id: n.label,
      };

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'topicId': topicId,
        'topicName': topicName,
        'view': _viewToJson(),
        'nodes': [for (final n in nodes) n.toJson()],
        'milestones': [for (final m in milestones) m.toJson()],
        'warnings': warnings,
      };

  Map<String, dynamic> _viewToJson() => {
        'goal': view.goal,
        'targetLevel': view.targetLevel,
        'timeBudgetMinutes': view.timeBudgetMinutes,
        'startedAt': view.startedAt,
        'completedAt': view.completedAt,
        'status': view.status,
        'plannedNodeIds': view.plannedNodeIds,
        'activities': [
          for (final a in view.activities)
            {
              'nodeId': a.nodeId,
              'nodeLabel': a.nodeLabel,
              'isComplete': a.isComplete,
              'steps': [
                for (final s in a.steps)
                  {
                    'type': s.type,
                    'title': s.title,
                    if (s.body != null) 'body': s.body,
                    if (s.instruction != null) 'instruction': s.instruction,
                    if (s.options != null) 'options': s.options,
                    if (s.correctIndex != null) 'correctIndex': s.correctIndex,
                    if (s.bestAnswer != null) 'bestAnswer': s.bestAnswer,
                    if (s.userAnswer != null) 'userAnswer': s.userAnswer,
                    if (s.correct != null) 'correct': s.correct,
                    if (s.feedback != null) 'feedback': s.feedback,
                    'durationMs': s.durationMs,
                  },
              ],
            },
        ],
        'questions': [
          for (final q in view.questions)
            {
              'nodeId': q.nodeId,
              'type': q.effectiveType,
              'question': q.question,
              if (q.options != null) 'options': q.options,
              if (q.correctAnswer != null) 'correctAnswer': q.correctAnswer,
              if (q.correctIndex != null) 'correctIndex': q.correctIndex,
              if (q.userAnswer != null) 'userAnswer': q.userAnswer,
              if (q.correct != null) 'correct': q.correct,
              if (q.feedback != null) 'feedback': q.feedback,
              'timeSpentMs': q.timeSpentMs,
            },
        ],
        'events': [
          for (final e in view.events) {'type': e.type, 'durationMs': e.durationMs},
        ],
        'masteryAfter': view.masteryAfter,
        'masteryBefore': view.masteryBefore,
        'misconceptions': view.misconceptions,
      };
}

/// Последние сессии из базы. `sessionId == null` → самая свежая.
Future<List<LoadedSession>> loadSessions({
  required String dbPath,
  String? sessionId,
  String? topicId,
  int limit = 20,
}) async {
  final copy = await _copyDatabase(dbPath);
  final MindtreeDb db;
  try {
    db = MindtreeDb(NativeDatabase(copy));
    // Проверяем, что файл вообще SQLite: иначе drift отдаст сырое
    // `SqliteException: file is not a database`, и пользователь получит
    // стектрейс вместо подсказки.
    await db.customSelect('SELECT 1').get();
  } on Object catch (e) {
    _deleteTempDir(copy);
    throw SessionLoadException(
      'Файл не читается как база MindTree: $e\n'
      'Укажи --db <путь к mindtree.db> (файл создаётся приложением).',
    );
  }
  try {
    final rows = <LearningSessionRowData>[];
    if (sessionId != null && sessionId.isNotEmpty) {
      final row = await (db.select(db.learningSessions)
            ..where((t) => t.id.equals(sessionId)))
          .getSingleOrNull();
      if (row == null) {
        throw SessionLoadException('Сессия «$sessionId» не найдена в базе');
      }
      rows.add(row);
    } else {
      final query = db.select(db.learningSessions)
        ..orderBy([(t) => OrderingTerm.desc(t.startedAt)])
        ..limit(limit);
      if (topicId != null && topicId.isNotEmpty) {
        query.where((t) => t.topicId.equals(topicId));
      }
      rows.addAll(await query.get());
    }
    final out = <LoadedSession>[];
    for (final row in rows) {
      out.add(await _loadOne(db, row));
    }
    return out;
  } finally {
    await db.close();
    _deleteTempDir(copy);
  }
}

/// Одна сессия по id.
Future<LoadedSession> loadSession({
  required String dbPath,
  required String sessionId,
}) async {
  final all = await loadSessions(dbPath: dbPath, sessionId: sessionId);
  return all.first;
}

/// Копирует `mindtree.db` (+`-wal`, `-shm`) во временный каталог и возвращает
/// путь к копии. Оригинал остаётся нетронутым.
Future<File> _copyDatabase(String dbPath) async {
  final source = File(dbPath);
  if (!source.existsSync()) {
    throw SessionLoadException(
      'Файл базы не найден: $dbPath\n'
      'Укажи путь явно: --db <путь к mindtree.db>\n'
      'Обычно он лежит в профиле приложения (см. README инструмента).',
    );
  }
  final dir = Directory.systemTemp.createTempSync('mindtree_review_');
  final target = File('${dir.path}${Platform.pathSeparator}mindtree.db');
  try {
    await source.copy(target.path);
    // WAL и SHM обязательны: без них снимок может быть неконсистентным.
    for (final suffix in const ['-wal', '-shm']) {
      final extra = File('$dbPath$suffix');
      if (extra.existsSync()) {
        await extra.copy('${target.path}$suffix');
      }
    }
  } on FileSystemException catch (e) {
    _deleteTempDir(target);
    throw SessionLoadException('Не удалось скопировать базу для чтения: $e');
  }
  return target;
}

void _deleteTempDir(File copiedDb) {
  final dir = copiedDb.parent;
  if (dir.existsSync()) {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // Временный мусор не должен ломать отчёт.
    }
  }
}

Future<LoadedSession> _loadOne(MindtreeDb db, LearningSessionRowData row) async {
  final warnings = <String>[];

  final topic = await (db.select(db.topics)..where((t) => t.id.equals(row.topicId)))
      .getSingleOrNull();

  final nodeRows = await (db.select(db.knowledgeNodes)
        ..where((t) => t.topicId.equals(row.topicId))
        ..orderBy([(t) => OrderingTerm.asc(t.level)]))
      .get();
  final nodes = [
    for (final n in nodeRows)
      NodeSummary(
        id: n.id,
        label: n.label,
        oneLiner: n.oneLiner,
        level: n.level,
        leaf: n.leaf,
        state: n.state,
        difficulty: n.difficulty,
        estimatedTimeMinutes: n.estimatedTimeMinutes,
      ),
  ];
  final labels = {for (final n in nodes) n.id: n.label};

  // ─── План (curriculum) ─────────────────────────────────────────────────────
  var plannedNodeIds = <String>[];
  if (row.curriculumJson.isNotEmpty) {
    try {
      final curriculum =
          Curriculum.fromJson(jsonDecode(row.curriculumJson) as Map<String, dynamic>);
      plannedNodeIds = [
        for (final item in curriculum.items)
          if (item.nodeId.isNotEmpty) item.nodeId,
      ];
    } on Object catch (e) {
      warnings.add('curriculum_json не разобран: $e');
    }
  }

  // ─── Активности ────────────────────────────────────────────────────────────
  final activities = <SessionActivityView>[];
  if (row.activityJson.isNotEmpty) {
    final decoded = _decodeOrNull(row.activityJson, 'activity_json', warnings);
    if (decoded != null && decoded is! List) {
      // Валидный JSON, но не массив: без предупреждения активности молча
      // выглядели бы как «сессия без заданий».
      warnings.add(
        'activity_json — ${decoded.runtimeType}, а не массив: активности не разобраны',
      );
    }
    if (decoded is List) {
      for (final item in decoded) {
        if (item is! Map<String, dynamic>) continue;
        final steps = <SessionStepView>[];
        final rawSteps = item['steps'];
        if (rawSteps is List) {
          for (final raw in rawSteps) {
            if (raw is! Map<String, dynamic>) continue;
            steps.add(SessionStepView(
              type: '${raw['type'] ?? ''}',
              title: '${raw['title'] ?? ''}',
              body: raw['body'] as String?,
              instruction: raw['instruction'] as String?,
              options: (raw['options'] as List?)?.cast<String>(),
              correctIndex: (raw['correctIndex'] as num?)?.toInt(),
              bestAnswer: raw['bestAnswer'] as String?,
              userAnswer: raw['userAnswer'] as String?,
              correct: raw['correct'] as bool?,
              feedback: raw['feedback'] as String?,
              // Тайминга по шагам в БД нет — см. шапку файла.
              durationMs: 0,
            ));
          }
        }
        final nodeId = '${item['nodeId'] ?? ''}';
        final label = '${item['nodeLabel'] ?? ''}'.trim();
        activities.add(SessionActivityView(
          nodeId: nodeId,
          nodeLabel: label.isNotEmpty ? label : (labels[nodeId] ?? ''),
          steps: steps,
          isComplete: item['isComplete'] as bool? ?? false,
        ));
      }
    }
  }

  // ─── Оценки: вопросы + попытки ──────────────────────────────────────────────
  final questions = <SessionQuestionView>[];
  final assessmentViews = <AssessmentScoreView>[];
  final assessments = await (db.select(db.assessments)
        ..where((t) => t.sessionId.equals(row.id)))
      .get();
  for (final assessment in assessments) {
    final attempts = await (db.select(db.assessmentAttempts)
          ..where((t) => t.assessmentId.equals(assessment.id)))
        .get();
    final attemptByQuestion = <String, AssessmentAttemptRowData>{};
    for (final a in attempts) {
      // Последняя попытка по вопросу побеждает: именно она описывает итог.
      attemptByQuestion[a.questionId] = a;
    }
    // Балл из БД рядом с фактическими попытками: без сверки расхождение
    // («верно, но correct=false, score=0») осталось бы невидимым.
    assessmentViews.add(AssessmentScoreView(
      type: assessment.type,
      recordedScore: assessment.score,
      attempts: attempts.length,
      correctAttempts: attempts.where((a) => a.correct).length,
    ));
    final decoded =
        _decodeOrNull(assessment.questionsJson, 'assessment.questions_json', warnings);
    if (decoded is! List) continue;
    for (final raw in decoded) {
      if (raw is! Map<String, dynamic>) continue;
      final AssessmentQuestion q;
      try {
        q = AssessmentQuestion.fromJson(raw);
      } on Object catch (e) {
        // Вопрос без `id`/`type` и подобное — скипаем вопрос, а не сессию.
        warnings.add('Вопрос пропущен: не разобран (${e.runtimeType})');
        continue;
      }
      if (q.id.isEmpty) {
        warnings.add('Вопрос без id пропущен: попытку не сопоставить');
        continue;
      }
      final attempt = attemptByQuestion[q.id];
      questions.add(SessionQuestionView(
        nodeId: q.nodeId,
        question: q.question,
        type: q.type.wire,
        options: q.options,
        correctAnswer: q.correctAnswer,
        correctIndex: _correctIndexOf(q),
        userAnswer: attempt?.answer,
        correct: attempt?.correct,
        feedback: attempt?.feedback ?? q.explanation,
        timeSpentMs: attempt?.timeSpentMs ?? 0,
      ));
    }
  }

  // ─── События ───────────────────────────────────────────────────────────────
  final eventRows = await (db.select(db.learningEvents)
        ..where((t) => t.sessionId.equals(row.id))
        ..orderBy([(t) => OrderingTerm.asc(t.timestamp)]))
      .get();
  final events = [
    for (final e in eventRows)
      SessionEventView(type: e.type, durationMs: e.durationMs),
  ];

  // ─── Mastery и мисконцепции ────────────────────────────────────────────────
  var masteryAfter = <String, double>{};
  final misconceptions = <String>[];
  final misconceptionsByNode = <String, String>{};
  final model = _latestLearnerModel(
    await (db.select(db.learnerModels)..where((t) => t.topicId.equals(row.topicId))).get(),
    warnings,
  );
  if (model != null && model.conceptMasteriesJson.isNotEmpty) {
    final decoded =
        _decodeOrNull(model.conceptMasteriesJson, 'learner_model.concept_masteries', warnings);
    if (decoded is List) {
      for (final raw in decoded) {
        if (raw is! Map<String, dynamic>) continue;
        final ConceptMastery cm;
        try {
          cm = ConceptMastery.fromJson(raw);
        } on Object catch (e) {
          // Одна битая запись не должна ронять разбор всей сессии.
          warnings.add('Запись concept_mastery пропущена: $e');
          continue;
        }
        if (cm.nodeId.isEmpty) {
          warnings.add('Запись concept_mastery без nodeId пропущена');
          continue;
        }
        masteryAfter[cm.nodeId] = _masteryScore(cm);
        for (final m in cm.errors) {
          final text = m.description.trim();
          if (text.isEmpty) continue;
          misconceptions.add(text);
          if (m.nodeId.isNotEmpty) {
            misconceptionsByNode[m.nodeId] = text;
          }
        }
      }
    }
    // Снапшота «до» в БД нет — дельту mastery посчитать нечем.
    warnings.add(
      'История mastery не хранится: learner_models содержит только текущее '
      'состояние, поэтому проверки дельты mastery неполны.',
    );
  }

  // ─── Milestones темы ────────────────────────────────────────────────────────
  final journey = _latestJourney(
    await (db.select(db.learningJourneys)..where((t) => t.topicId.equals(row.topicId))).get(),
    warnings,
  );
  final milestones = <MilestoneSummary>[];
  if (journey != null) {
    final milestoneRows = await (db.select(db.learningMilestones)
          ..where((t) => t.journeyId.equals(journey.id)))
        .get();
    for (final m in milestoneRows) {
      milestones.add(MilestoneSummary(
        id: m.id,
        level: m.level,
        title: m.title,
        status: m.status,
        estimatedHours: m.estimatedHours,
      ));
    }
  }

  // Узлы плана, которых нет в дереве, — повод проверить согласованность.
  final missing = [
    for (final id in plannedNodeIds)
      if (!labels.containsKey(id)) id,
  ];
  if (missing.isNotEmpty) {
    warnings.add(
      'В плане ${missing.length} узл(ев), которых нет в дереве темы: '
      '${missing.take(5).join(', ')}',
    );
  }

  final view = SessionView(
    topicName: topic?.name ?? '',
    goal: topic?.goal ?? row.goal,
    targetLevel: topic?.targetLevel ?? MasteryLevel.basicUnderstanding.raw,
    timeBudgetMinutes: topic?.timeBudgetMinutes ?? row.timeBudgetMinutes,
    startedAt: row.startedAt.toIso8601String(),
    completedAt: row.completedAt?.toIso8601String() ?? '',
    status: row.status,
    activities: activities,
    questions: questions,
    events: events,
    masteryAfter: masteryAfter,
    misconceptions: misconceptions,
    plannedNodeIds: plannedNodeIds,
    misconceptionsByNode: misconceptionsByNode,
    assessments: assessmentViews,
  );

  return LoadedSession(
    view: view,
    sessionId: row.id,
    topicId: row.topicId,
    topicName: topic?.name ?? '',
    nodes: nodes,
    milestones: [...milestones]..sort((a, b) => a.id.compareTo(b.id)),
    warnings: warnings,
  );
}

/// Индекс правильного варианта: если `correctAnswer` — это текст одного из
/// вариантов, находим его; иначе `null` (открытый вопрос).
int? _correctIndexOf(AssessmentQuestion q) {
  final options = q.options;
  final answer = q.correctAnswer?.trim();
  if (options == null || options.isEmpty || answer == null || answer.isEmpty) {
    return null;
  }
  for (var i = 0; i < options.length; i++) {
    if (options[i].trim() == answer) return i;
  }
  return null;
}

/// Средний балл мастерства по четырём измерениям — тот же смысл, что у
/// `learner_model_service`.
double _masteryScore(ConceptMastery cm) {
  final sum = cm.understanding + cm.recall + cm.application + cm.transfer;
  return double.parse((sum / 4).toStringAsFixed(4));
}

/// Последняя модель по `updatedAt`.
///
/// Уникального ключа на тему нет, если в базе завёлись дубли (импорт, гонка
/// фонового обновления). Раньше это давало `StateError: Too many elements` и
/// терялся весь отчёт по теме; теперь берём актуальную и предупреждаем.
LearnerModelRowData? _latestLearnerModel(
  List<LearnerModelRowData> rows,
  List<String> warnings,
) {
  if (rows.length <= 1) return rows.isEmpty ? null : rows.first;
  warnings.add(
    'В базе ${rows.length} learner_models на одну тему — берём последний по updatedAt',
  );
  final sorted = [...rows]..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
  return sorted.last;
}

/// То же для journey: при дублях берём последний по `createdAt`.
LearningJourneyRowData? _latestJourney(
  List<LearningJourneyRowData> rows,
  List<String> warnings,
) {
  if (rows.length <= 1) return rows.isEmpty ? null : rows.first;
  warnings.add(
    'В базе ${rows.length} learning_journeys на одну тему — берём последний по createdAt',
  );
  final sorted = [...rows]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  return sorted.last;
}

/// JSON-разбор с понятным warning вместо падения: битые данные в архиве сессии
/// не должны ронять ревью.
Object? _decodeOrNull(String raw, String what, List<String> warnings) {
  if (raw.trim().isEmpty) return null;
  try {
    return jsonDecode(raw);
  } on FormatException catch (e) {
    warnings.add('$what: битый JSON (${e.message})');
    return null;
  }
}
