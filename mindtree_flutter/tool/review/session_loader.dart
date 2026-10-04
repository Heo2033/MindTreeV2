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
// ─── Контракт вопросов оценки ─────────────────────────────────────────────────
// Приложение в базе хранит уже приведённый к боевому контракту `questions_json`
// (`AssessmentEngine._parseAssessmentResult`):
// * закрытый вопрос — `correctAnswer` это строковый ИНДЕКС правильного варианта
//   («"0".."3"»), ученик отвечает тем же индексом, и экран считает ответ верным
//   как `selected.toString() == q.correctAnswer` (`quiz_screen.dart`,
//   `final_assessment_screen.dart`); «правильный вариант» ищется общим резолвом
//   `lib/domain/lib/option_matching.dart`, а не текстовым сравнением;
// * открытый вопрос — `options` пуст, `correctAnswer` пуст ПО ПОСТРОЕНИЮ: эталона
//   не требуется и не существует, оценивает `gradeOpenEnded` по рубрике из
//   `explanation`, поэтому рубрика попадает в `SessionQuestionView.rubric`.
//
// ─── Чего в БД нет ───────────────────────────────────────────────────────────
// * Тайминга по шагам активности: `ActivityStep` не хранит длительность,
//   события — хранят. Поэтому `SessionStepView.durationMs` остаётся 0, а
//   проверка `session_step_duration` честно ругается на отсутствие замера.
// * `nodeId` и `isComplete` в `activity_json`: приложение пишет объект
//   `{"itemId": ..., "steps": [...]}` (`learning_activity_service.dart`).
//   Узел восстанавливается по `itemId` через план, а завершение — по
//   отвеченности шагов (`ActivityStep.status` в blob есть).
// * Снапшота mastery «до»: `learner_models` хранит только текущее состояние.
//   `masteryBefore` пуст, `masteryAfter` заполнен; об этом есть warning и
//   info-находка `session_mastery_delta`.
// * Привязки мисконцепции к сессии в БД нет: `learner_models` уникален по
//   `(userId, topicId)`, строка одна на тему, поэтому все мисконцепции темы
//   достаются каждой её сессии. Инструмент выводит принадлежность из окна
//   `[startedAt, completedAt ?? старт следующей сессии темы)`. Приложение
//   сессии не закрывает (`completed_at` всегда NULL, `status` всегда `active`),
//   поэтому верхняя граница выводится из старта следующей сессии темы; если её
//   нет, границы нет. Соседи берутся по ВСЕМ сессиям темы, а не по попавшим в
//   выборку (`--limit`, `--topic-id`, `--session`), иначе усечение тихо ломало
//   бы окно. Ограничение: `Misconception.detectedAt` — локальное время ISO без
//   смещения, поэтому при смене часового пояса или DST возможен сдвиг на часы.
//   Мисконцепции вне окна и без `detectedAt` в отчёт не идут, но считаются в
//   warnings.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:mindtree_flutter/data/database/mindtree_db.dart';
import 'package:mindtree_flutter/domain/lib/option_matching.dart';
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
              if (q.rubric != null) 'rubric': q.rubric,
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
    // Старты сессий по темам — верхняя граница окна атрибуции мисконцепций.
    // Берём ВСЕ сессии запрошенных тем, а не только попавшие в выборку: при
    // усечении по `--limit` самая ранняя выбранная сессия темы иначе не увидит
    // старт следующей, её окно останется без верхней границы, и мисконцепции
    // более поздних сессий молча вернутся в её отчёт. Один запрос на темы
    // `rows`, соседей по БД `_loadOne` не добирает никогда.
    final startsByTopic = <String, List<DateTime>>{};
    final topicIds = {for (final row in rows) row.topicId};
    if (topicIds.isNotEmpty) {
      // Сортировка по возрастанию — списки внутри карты тоже по возрастанию,
      // на этом держится выборка соседа в `_nextSessionStart`.
      final siblings = await (db.select(db.learningSessions)
            ..where((t) => t.topicId.isIn(topicIds))
            ..orderBy([(t) => OrderingTerm.asc(t.startedAt)]))
          .get();
      for (final s in siblings) {
        (startsByTopic[s.topicId] ??= <DateTime>[]).add(s.startedAt);
      }
    }
    final out = <LoadedSession>[];
    for (final row in rows) {
      final nextStart = _nextSessionStart(startsByTopic[row.topicId], row.startedAt);
      out.add(await _loadOne(db, row, nextStart));
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

/// [nextSessionStart] — старт ближайшей сессии той же темы строго позже
/// [LearningSessionRowData.startedAt]; `null`, если такой сессии нет. Нужен как
/// верхняя граница окна атрибуции мисконцепций, потому что приложение сессии не
/// закрывает (см. шапку файла).
Future<LoadedSession> _loadOne(
  MindtreeDb db,
  LearningSessionRowData row,
  DateTime? nextSessionStart,
) async {
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
  // `item.id` → `nodeId`. Боевой `activity_json` пишет только `itemId`, поэтому
  // без этого соответствия узел активности не восстановить. Строим целиком,
  // но по тем же непустым `nodeId`, что и `plannedNodeIds`.
  var nodeByCurriculumItemId = <String, String>{};
  if (row.curriculumJson.isNotEmpty) {
    try {
      final curriculum =
          Curriculum.fromJson(jsonDecode(row.curriculumJson) as Map<String, dynamic>);
      plannedNodeIds = [
        for (final item in curriculum.items)
          if (item.nodeId.isNotEmpty) item.nodeId,
      ];
      nodeByCurriculumItemId = {
        for (final item in curriculum.items)
          if (item.id.isNotEmpty && item.nodeId.isNotEmpty) item.id: item.nodeId,
      };
    } on Object catch (e) {
      warnings.add('curriculum_json не разобран: $e');
    }
  }

  // ─── Активности ────────────────────────────────────────────────────────────
  final activities = <SessionActivityView>[];
  if (row.activityJson.isNotEmpty) {
    final decoded = _decodeOrNull(row.activityJson, 'activity_json', warnings);
    // Разбор шагов и узла у форматов общий, различается только обёртка.
    final List<Object?> rawActivities;
    if (decoded is Map<String, dynamic>) {
      // Боевой формат — объект одной активности `{"itemId", "steps"}`.
      rawActivities = [decoded];
    } else if (decoded is List) {
      // Список — legacy/выгрузка.
      rawActivities = decoded;
    } else {
      rawActivities = const [];
    }
    for (final raw in rawActivities) {
      if (raw is! Map<String, dynamic>) continue;
      final parsed = _parseActivitySteps(raw['steps']);
      final nodeId = _activityNodeId(raw, nodeByCurriculumItemId);
      final itemId = '${raw['itemId'] ?? ''}'.trim();
      final where = itemId.isEmpty ? '' : ' (itemId «$itemId»)';

      // Активность без узла или без шагов проверкам только мешает: почти все
      // они ключуются по `nodeId`. Лучше честно выпасть из отчёта с warning'ом,
      // чем превратить потерю данных в каскад ложных находок.
      if (nodeId.isEmpty) {
        warnings.add('activity_json: у активности не нашёлся узел$where — нет ни '
            'nodeId, ни itemId, разрешимого через план; активность пропущена');
      }
      if (parsed.isEmpty) {
        warnings.add('activity_json: у активности нет шагов$where — активность '
            'пропущена, судить о прохождении не по чему');
      }
      if (nodeId.isEmpty || parsed.isEmpty) continue;

      final label = '${raw['nodeLabel'] ?? ''}'.trim();
      activities.add(SessionActivityView(
        nodeId: nodeId,
        nodeLabel: label.isNotEmpty ? label : (labels[nodeId] ?? ''),
        steps: [for (final step in parsed) step.view],
        isComplete: _activityIsComplete(raw, parsed),
      ));
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
      // Рубрика открытого вопроса лежит в `explanation`; у закрытого она же
      // служит пояснением к правильному варианту, поэтому в DTO это отдельное
      // поле, а не вычисление из `feedback`.
      final rubric = (q.explanation ?? '').trim();
      questions.add(SessionQuestionView(
        nodeId: q.nodeId,
        question: q.question,
        type: q.type.wire,
        options: q.options,
        correctAnswer: q.correctAnswer,
        correctIndex: _correctIndexOf(q),
        rubric: rubric.isEmpty ? null : rubric,
        userAnswer: attempt?.answer,
        correct: attempt?.correct,
        feedback: (attempt?.feedback ?? '').isNotEmpty
            ? attempt?.feedback
            : q.explanation,

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
  // `learner_models` — одна строка на тему, поэтому мисконцепции достаются все.
  // Владеет ими только та сессия, чьё окно их накрывает; остальные сессии темы
  // их не видят. `masteryAfter` остаётся текущим состоянием темы целиком: дельту
  // mastery разбирает `checkMasteryDelta`.
  var masteryAfter = <String, double>{};
  final misconceptions = <String>[];
  final misconceptionsByNode = <String, String>{};
  final windowFrom = row.startedAt;
  final windowTo = row.completedAt ?? nextSessionStart;
  var outsideWindow = 0;
  var withoutDetectedAt = 0;
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
          final detectedAt = _parseLocal(m.detectedAt);
          if (detectedAt == null) {
            withoutDetectedAt++;
          } else if (!_inWindow(detectedAt, windowFrom, windowTo)) {
            outsideWindow++;
          } else {
            misconceptions.add(text);
            if (m.nodeId.isNotEmpty) {
              misconceptionsByNode[m.nodeId] = text;
            }
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
  // Агрегаты без списков id: сколько мисконцепций темы этой сессии не досталось.
  if (outsideWindow > 0) {
    warnings.add(
      'Мисконцепции темы вне окна сессии: $outsideWindow '
      '(окно ${_fmtDate(windowFrom)} — '
      '${windowTo == null ? '∞' : _fmtDate(windowTo)}) — '
      'отнесены к другим сессиям',
    );
  }
  if (withoutDetectedAt > 0) {
    warnings.add(
      'Мисконцепции без detectedAt: $withoutDetectedAt — отнести к сессии '
      'нельзя',
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

/// Шаг активности вместе с признаком «отвечен», выведенным из сырого JSON.
///
/// Отвеченность нужна для `isComplete`: боевой blob флага завершения не пишет,
/// а `SessionStepView` статус шага не хранит (см. `ActivityStep.status`).
class _ParsedStep {
  final SessionStepView view;
  final bool answered;
  const _ParsedStep(this.view, this.answered);
}

/// Разбор `steps` активности. Пустой результат — шагов нет или они не объекты.
List<_ParsedStep> _parseActivitySteps(Object? rawSteps) {
  if (rawSteps is! List) return const [];
  final out = <_ParsedStep>[];
  for (final raw in rawSteps) {
    if (raw is! Map<String, dynamic>) continue;
    out.add(_ParsedStep(
      SessionStepView(
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
      ),
      _rawStepAnswered(raw),
    ));
  }
  return out;
}

/// Отвечен ли шаг по сырому JSON.
///
/// `ActivityStep.status` ∈ pending|current|answered и сериализуется в blob,
/// поэтому явный статус — источник истины. Если его нет (legacy-выгрузка),
/// отвеченным считаем шаг с непустым ответом или с выставленным вердиктом.
bool _rawStepAnswered(Map<String, dynamic> raw) {
  final status = '${raw['status'] ?? ''}'.trim();
  if (status.isNotEmpty) return status == 'answered';
  if ('${raw['userAnswer'] ?? ''}'.trim().isNotEmpty) return true;
  return raw['correct'] != null;
}

/// Узел активности: явный `nodeId`, иначе — `itemId` через план.
///
/// Приложение пишет в `activity_json` только `{"itemId", "steps"}`
/// (`learning_activity_service.dart`), поэтому боевой путь — второй. Ничего не
/// нашлось — возвращаем пустую строку, вызывающий код с warning'ом выкинет
/// такую активность из отчёта.
String _activityNodeId(
  Map<String, dynamic> raw,
  Map<String, String> nodeByCurriculumItemId,
) {
  final direct = '${raw['nodeId'] ?? ''}'.trim();
  if (direct.isNotEmpty) return direct;
  final itemId = '${raw['itemId'] ?? ''}'.trim();
  if (itemId.isEmpty) return '';
  return nodeByCurriculumItemId[itemId] ?? '';
}

/// Флаг завершения активности.
///
/// Явный `isComplete` в blob — приоритет, его не переопределяем. В боевом
/// формате его нет, иначе на реальных данных каждая сессия выглядела бы
/// «ни одна активность не завершена»; тогда завершена = все шаги отвечены.
bool _activityIsComplete(Map<String, dynamic> raw, List<_ParsedStep> steps) {
  final explicit = raw['isComplete'];
  if (explicit is bool) return explicit;
  if (steps.isEmpty) return false;
  return steps.every((s) => s.answered);
}

/// Ближайший старт сессии той же темы строго позже [startedAt].
///
/// [starts] — отсортированный по возрастанию список стартов. Совпадающие с
/// [startedAt] значения пропускаются, поэтому соседи с одинаковым временем
/// старта друг друга не ограничивают. `null` — следующей сессии нет.
DateTime? _nextSessionStart(List<DateTime>? starts, DateTime startedAt) {
  if (starts == null) return null;
  for (final start in starts) {
    if (start.isAfter(startedAt)) return start;
  }
  return null;
}

/// Разбор `Misconception.detectedAt` — локальное ISO-время без смещения.
///
/// `null` — поле пустое или не разбирается: без времени отнести мисконцепцию к
/// сессии нельзя, и она не достаётся ни одной.
DateTime? _parseLocal(String iso) {
  final raw = iso.trim();
  if (raw.isEmpty) return null;
  return DateTime.tryParse(raw);
}

/// Окно сессии `[from, to)`. `to == null` — верхней границы нет.
bool _inWindow(DateTime detectedAt, DateTime from, DateTime? to) {
  if (detectedAt.isBefore(from)) return false;
  if (to != null && !detectedAt.isBefore(to)) return false;
  return true;
}

/// Дата в формате `dd.MM.yyyy HH:mm` по локальному времени.
String _fmtDate(DateTime d) {
  String p(int v) => v.toString().padLeft(2, '0');
  return '${p(d.day)}.${p(d.month)}.${p(d.year)} ${p(d.hour)}:${p(d.minute)}';
}

/// Индекс правильного варианта закрытого вопроса.
///
/// Резолв общий с движком (`lib/domain/lib/option_matching.dart`), потому что
/// `correctAnswer` в базе — это строковый ИНДЕКС правильного варианта
/// («"0".."3"»), а не текст варианта: приложение сверяет ответ как
/// `selected.toString() == q.correctAnswer` (`quiz_screen.dart`,
/// `final_assessment_screen.dart`). Поиск только по тексту давал на боевых
/// данных ложное «правильный ответ неизвестен».
///
/// `null` — открытый вопрос (`options` пуст, эталон не требуется) либо
/// несопоставимый `correctAnswer`.
int? _correctIndexOf(AssessmentQuestion q) =>
    resolveCorrectOptionIndex(q.options ?? const <String>[], q.correctAnswer);

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