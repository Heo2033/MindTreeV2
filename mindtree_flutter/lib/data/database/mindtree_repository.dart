import 'dart:convert';

import 'package:drift/drift.dart';

import '../../domain/models/models.dart';
import '../../domain/engines/scoped_ids.dart';
import 'mappers.dart';
import 'mindtree_db.dart';

/// High-level persistence operations for the domain engines.
class MindtreeRepository {
  final MindtreeDb db;

  MindtreeRepository(this.db);

  // ---------- Topics ----------

  Future<List<Topic>> listTopics() async {
    final rows = await db.select(db.topics).get();
    return rows.map(Mappers.topicFromRow).toList();
  }

  Future<Topic?> getTopic(String id) async {
    final row = await (db.select(db.topics)..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : Mappers.topicFromRow(row);
  }

  Future<Topic> createTopic(Topic topic) async {
    await db.into(db.topics).insert(Mappers.topicToRow(topic));
    return topic;
  }

  Future<void> updateTopic(Topic topic) async {
    await (db.update(db.topics)..where((t) => t.id.equals(topic.id))).write(Mappers.topicToRow(topic));
  }

  Future<void> deleteTopic(String id) async {
    await (db.delete(db.topics)..where((t) => t.id.equals(id))).go();
  }

  /// Тема вместе со всем деревом — сырьё для экспорта в файл.
  Future<TopicWithNodes?> getTopicWithNodes(String topicId) async {
    final topic = await getTopic(topicId);
    if (topic == null) return null;
    return TopicWithNodes(topic: topic, nodes: await listNodes(topicId));
  }

  /// Атомарная вставка темы со всем деревом: используется импортом файла.
  ///
  /// Транзакция обязательна — частично залитый импорт оставил бы тему без
  /// содержимого (или наоборот) и сломал бы инварианты дерева. При любой
  /// ошибке (в т.ч. конфликте id) всё откатывается.
  Future<Topic> insertTopicWithNodes(
    Topic topic,
    List<KnowledgeNode> nodes,
  ) async {
    await db.transaction(() async {
      await db.into(db.topics).insert(Mappers.topicToRow(topic));
      for (final n in nodes) {
        await db.into(db.knowledgeNodes).insert(Mappers.nodeToRow(n));
      }
    });
    return topic;
  }

  // ---------- Knowledge Nodes ----------

  Future<List<KnowledgeNode>> listNodes(String topicId) async {
    final rows = await (db.select(db.knowledgeNodes)
          ..where((n) => n.topicId.equals(topicId)))
        .get();
    return repairDanglingParentIds(rows.map(Mappers.nodeFromRow).toList());
  }

  Future<KnowledgeNode?> getNode(String id) async {
    final row = await (db.select(db.knowledgeNodes)..where((n) => n.id.equals(id))).getSingleOrNull();
    return row == null ? null : Mappers.nodeFromRow(row);
  }

  Future<List<KnowledgeNode>> getNodes(List<String> ids) async {
    if (ids.isEmpty) return const [];
    final rows = await (db.select(db.knowledgeNodes)..where((n) => n.id.isIn(ids))).get();
    return rows.map(Mappers.nodeFromRow).toList();
  }

  Future<List<KnowledgeNode>> getChildren(String parentId) async {
    final rows = await (db.select(db.knowledgeNodes)
          ..where((n) => n.parentId.equals(parentId)))
        .get();
    return rows.map(Mappers.nodeFromRow).toList();
  }

  Future<void> insertNodes(List<KnowledgeNode> nodes) async {
    await db.batch((b) {
      b.insertAll(db.knowledgeNodes, nodes.map(Mappers.nodeToRow).toList());
    });
  }

  Future<void> updateNode(KnowledgeNode node) async {
    await (db.update(db.knowledgeNodes)..where((n) => n.id.equals(node.id))).write(Mappers.nodeToRow(node));
  }

  Future<void> updateNodes(List<KnowledgeNode> nodes) async {
    await db.transaction(() async {
      for (final n in nodes) {
        await (db.update(db.knowledgeNodes)..where((x) => x.id.equals(n.id)))
            .write(Mappers.nodeToRow(n));
      }
    });
  }

  Future<void> insertOrReplaceNodes(List<KnowledgeNode> nodes) async {
    await db.batch((b) {
      b.insertAll(db.knowledgeNodes, nodes.map(Mappers.nodeToRow).toList(), mode: InsertMode.insertOrReplace);
    });
  }

  Future<int> countNodes(String topicId) async {
    final rows = await (db.select(db.knowledgeNodes)
          ..where((n) => n.topicId.equals(topicId)))
        .get();
    return rows.length;
  }

  /// Nodes without content generated (one_liner/details empty).
  Future<List<KnowledgeNode>> nodesNeedingContent(String topicId, {int? level, int? limit}) async {
    final query = db.select(db.knowledgeNodes)
      ..where((n) => n.topicId.equals(topicId) & n.contentLoaded.equals(false));
    if (level != null) {
      query.where((n) => n.level.equals(level));
    }
    if (limit != null) {
      query.limit(limit);
    }
    final rows = await query.get();
    return rows.map(Mappers.nodeFromRow).toList();
  }

  // ---------- Learning Journeys & Milestones ----------

  Future<LearningJourney?> getJourneyForTopic(String topicId) async {
    // Именно journey, у которого есть вехи: если в базе остались дубли
    // (старые сборки создавали journey на каждую сессию), показываем тот,
    // где реально лежит прогресс. `getSingleOrNull` на >1 строке бросает
    // «Bad state: Too many elements», поэтому берём список и выбираем сами.
    final rows = await (db.select(db.learningJourneys)
          ..where((j) => j.topicId.equals(topicId))
          ..orderBy([(j) => OrderingTerm.desc(j.createdAt)]))
        .get();
    if (rows.isEmpty) return null;

    LearningJourneyRowData? chosen;
    for (final row in rows) {
      // Приоритет у journey с вехами: в нём лежит реальный прогресс.
      if ((await listMilestones(row.id)).isNotEmpty) {
        chosen = row;
        break;
      }
      chosen ??= row;
    }
    if (chosen == null) return null;
    final milestones = await listMilestones(chosen.id);
    return Mappers.journeyFromRow(chosen, milestones);
  }

  Future<LearningJourney> createJourney(String id, String topicId) async {
    await db.into(db.learningJourneys).insert(LearningJourneysCompanion.insert(id: id, topicId: topicId));
    return LearningJourney(id: id, topicId: topicId, createdAt: DateTime.now().toIso8601String());
  }

  Future<List<LearningMilestone>> listMilestones(String journeyId) async {
    final rows = await (db.select(db.learningMilestones)
          ..where((m) => m.journeyId.equals(journeyId)))
        .get();
    return rows.map(Mappers.milestoneFromRow).toList();
  }

  Future<void> insertMilestones(List<LearningMilestone> milestones, {String journeyId = ''}) async {
    // `journeyId` обязателен для привязки: без него вехи не попадают
    // в `listMilestones(journeyId)` и journey остаётся без прогресса.
    // Зеркало: server/src/domain/MilestoneEngine.ts пишет journey_id в INSERT.
    await db.batch((b) {
      for (final m in milestones) {
        final companion = Mappers.milestoneToRow(m, journeyId: journeyId);
        b.insert(db.learningMilestones, LearningMilestonesCompanion(
          id: companion.id,
          journeyId: companion.journeyId,
          level: companion.level,
          title: companion.title,
          description: companion.description,
          capabilitiesJson: companion.capabilitiesJson,
          estimatedHours: companion.estimatedHours,
          status: companion.status,
          alternativePathsJson: companion.alternativePathsJson,
        ));
      }
    });
  }

  Future<LearningMilestone?> getMilestone(String id) async {
    final row = await (db.select(db.learningMilestones)..where((m) => m.id.equals(id))).getSingleOrNull();
    return row == null ? null : Mappers.milestoneFromRow(row);
  }

  Future<void> updateMilestone(LearningMilestone m) async {
    await (db.update(db.learningMilestones)..where((r) => r.id.equals(m.id))).write(Mappers.milestoneToRow(m));
  }

  // ---------- Learning Sessions ----------

  Future<List<LearningSession>> listSessions({int limit = 100}) async {
    final query = db.select(db.learningSessions)..orderBy([(s) => OrderingTerm.desc(s.startedAt)]);
    query.limit(limit);
    final rows = await query.get();
    return rows.map(Mappers.sessionFromRow).toList();
  }

  Future<List<LearningSession>> listSessionsForTopic(String topicId) async {
    final rows = await (db.select(db.learningSessions)..where((s) => s.topicId.equals(topicId))).get();
    return rows.map(Mappers.sessionFromRow).toList();
  }

  /// Незавершённые сессии темы, свежие первыми.
  ///
  /// «Незавершённая» = status != completed (completed/abandoned сейчас не
  /// пишутся, см. модель). Порядок детерминированный: startedAt desc, при
  /// равенстве — id asc, чтобы выбор не зависел от порядка строк в SQLite.
  Future<List<LearningSession>> listUnfinishedSessionsForTopic(
    String topicId, {
    int? limit,
  }) async {
    final query = db.select(db.learningSessions)
      ..where((s) =>
          s.topicId.equals(topicId) &
          s.status.isNotValue(SessionStatus.completed.raw))
      ..orderBy([
        (s) => OrderingTerm.desc(s.startedAt),
        (s) => OrderingTerm.asc(s.id),
      ]);
    if (limit != null) {
      query.limit(limit);
    }
    final rows = await query.get();
    return rows.map(Mappers.sessionFromRow).toList();
  }

  /// Последняя незавершённая сессия темы либо null.
  ///
  /// Продуктовое правило: показываем одну незавершённую сессию на тему, поэтому
  /// выбор делается в БД (`limit: 1`), а не вызывающим кодом.
  Future<LearningSession?> latestUnfinishedSessionForTopic(String topicId) async {
    final rows = await listUnfinishedSessionsForTopic(topicId, limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<LearningSession?> getSession(String id) async {
    final row = await (db.select(db.learningSessions)..where((s) => s.id.equals(id))).getSingleOrNull();
    return row == null ? null : Mappers.sessionFromRow(row);
  }

  Future<LearningSession> createSession(LearningSession session) async {
    await db.into(db.learningSessions).insert(Mappers.sessionToRow(session));
    return session;
  }

  Future<void> updateSession(LearningSession session) async {
    await (db.update(db.learningSessions)..where((s) => s.id.equals(session.id)))
        .write(Mappers.sessionToRow(session));
  }

  // ---------- Learning Events ----------

  Future<List<LearningEvent>> listEvents(String sessionId) async {
    final rows = await (db.select(db.learningEvents)..where((e) => e.sessionId.equals(sessionId))).get();
    return rows.map(Mappers.eventFromRow).toList();
  }

  Future<String> insertEvent(LearningEvent event) async {
    await db.into(db.learningEvents).insert(LearningEventsCompanion.insert(
          id: event.id,
          sessionId: event.sessionId,
          type: event.type.wire,
          nodeId: Value(event.nodeId),
          dataJson: Value(jsonEncode(event.data)),
          durationMs: Value(event.durationMs),
        ));
    return event.id;
  }

  // ---------- Learner Models ----------

  Future<LearnerModel?> getLearnerModel(String topicId, {String userId = 'default'}) async {
    final rows = await (db.select(db.learnerModels)
          ..where((m) => m.topicId.equals(topicId) & m.userId.equals(userId)))
        .get();
    // Модель по паре (topicId, userId) должна быть одна. `getSingleOrNull`
    // при дублях бросает «Bad state: Too many elements», поэтому при
    // нескольких строках берём последнюю — она и есть актуальная.
    if (rows.isEmpty) return null;
    return Mappers.learnerModelFromRow(rows.last);
  }

  Future<void> saveLearnerModel(LearnerModel model) async {
    final existing = await getLearnerModel(model.topicId, userId: model.userId);
    if (existing == null) {
      await db.into(db.learnerModels).insert(Mappers.learnerModelToRow(model));
    } else {
      await db.update(db.learnerModels).replace(Mappers.learnerModelToRow(model));
    }
  }

  // ---------- Assessments ----------

  Future<Assessment?> getAssessment(String id) async {
    final row = await (db.select(db.assessments)..where((a) => a.id.equals(id))).getSingleOrNull();
    return row == null ? null : Mappers.assessmentFromRow(row);
  }

  Future<Assessment> createAssessment(Assessment assessment, {List<Attempt>? attempts}) async {
    await db.into(db.assessments).insert(Mappers.assessmentToRow(assessment));
    if (attempts != null && attempts.isNotEmpty) {
      await db.batch((b) {
        b.insertAll(db.assessmentAttempts, attempts.map(Mappers.attemptToRow).toList());
      });
    }
    return assessment;
  }

  Future<void> updateAssessment(Assessment assessment) async {
    await (db.update(db.assessments)..where((a) => a.id.equals(assessment.id)))
        .write(Mappers.assessmentToRow(assessment));
  }

  Future<List<Attempt>> listAttempts(String assessmentId) async {
    final rows = await (db.select(db.assessmentAttempts)..where((a) => a.assessmentId.equals(assessmentId))).get();
    return rows.map(Mappers.attemptFromRow).toList();
  }

  Future<void> addAttempt(Attempt attempt) async {
    await db.into(db.assessmentAttempts).insert(Mappers.attemptToRow(attempt));
  }

  /// Find the most recent assessment of a given type for a session.
  Future<Assessment?> latestAssessmentForSession(String sessionId, String type) async {
    final rows = await (db.select(db.assessments)
          ..where((a) => a.sessionId.equals(sessionId) & a.type.equals(type))
          ..orderBy([(a) => OrderingTerm.desc(a.startedAt)]))
        .get();
    if (rows.isEmpty) return null;
    return Mappers.assessmentFromRow(rows.first);
  }

  // ---------- Activity Cache (prefetch) ----------

  /// Шаги активности для узла из кэша (по nodeId + goal), либо null.
  Future<List<ActivityStep>?> getCachedActivitySteps(String nodeId, String goal) async {
    final row = await (db.select(db.activityCache)
          ..where((c) => c.nodeId.equals(nodeId) & c.goal.equals(goal)))
        .getSingleOrNull();
    if (row == null) return null;
    try {
      final list = jsonDecode(row.stepsJson) as List<dynamic>;
      return list.map((e) => ActivityStep.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return null;
    }
  }

  /// Сохраняет сгенерированные шаги активности в кэш (upsert по nodeId+goal).
  Future<void> saveActivityCache(
    String topicId,
    String nodeId,
    String goal,
    List<ActivityStep> steps,
  ) async {
    await db.into(db.activityCache).insert(
          ActivityCacheCompanion(
            id: Value('ac_${nodeId}_$goal'),
            topicId: Value(topicId),
            nodeId: Value(nodeId),
            goal: Value(goal),
            stepsJson: Value(jsonEncode(steps.map((s) => s.toJson()).toList())),
          ),
          mode: InsertMode.insertOrReplace,
        );
  }
}
