import 'dart:async';
import 'dart:math' as math;

import '../models/models.dart';
import '../../data/database/mindtree_repository.dart';
import '../../data/llm/scheduler.dart';
import '../../data/prompts/prompts.dart';
import 'learner_model_service.dart';

class TutorReply {
  final String text;
  final bool usedFallback;
  final int? timeRemainingMinutes;

  const TutorReply({
    required this.text,
    this.usedFallback = false,
    this.timeRemainingMinutes,
  });
}

class _TutorContext {
  final String? topicName;
  final String? topicGoal;
  final String targetLevel;
  final String currentLevel;
  final String? currentNodeLabel;
  final List<String>? nodePath;
  final String? currentMastery;
  final List<String> misconceptions;
  final List<String> recentAttempts;
  final int? timeRemainingMinutes;

  const _TutorContext({
    this.topicName,
    this.topicGoal,
    required this.targetLevel,
    required this.currentLevel,
    this.currentNodeLabel,
    this.nodePath,
    this.currentMastery,
    this.misconceptions = const [],
    this.recentAttempts = const [],
    this.timeRemainingMinutes,
  });
}

class AITutorService {
  final MindtreeRepository repo;
  final LearnerModelService learnerModel;
  final TreeScheduler scheduler;

  AITutorService({
    required this.repo,
    required this.learnerModel,
    required this.scheduler,
  });

  Future<TutorReply> reply(
    String topicId,
    String message, {
    String? sessionId,
    String? nodeId,
  }) async {
    final ctx = await _buildContext(topicId, sessionId: sessionId, nodeId: nodeId);
    final prompt = buildTutorPrompt(
      topic: ctx.topicName ?? '',
      goal: ctx.topicGoal ?? '',
      targetLevel: ctx.targetLevel,
      currentLevel: ctx.currentLevel,
      currentNode: ctx.currentNodeLabel,
      nodePath: ctx.nodePath,
      currentMastery: ctx.currentMastery,
      misconceptions: ctx.misconceptions.isNotEmpty ? ctx.misconceptions : null,
      timeRemainingMinutes: ctx.timeRemainingMinutes,
      recentAttempts: ctx.recentAttempts.isNotEmpty ? ctx.recentAttempts : null,
      message: message,
    );

    try {
      final res = await scheduler.execute<String>(
        'tutor',
        () => prompt,
        (raw) => raw,
      );
      return TutorReply(
        text: res.result,
        usedFallback: false,
        timeRemainingMinutes: ctx.timeRemainingMinutes,
      );
    } catch (err) {
      return TutorReply(
        text: _fallbackText(ctx, message, err),
        usedFallback: true,
        timeRemainingMinutes: ctx.timeRemainingMinutes,
      );
    }
  }

  Stream<dynamic> streamReply(
    String topicId,
    String message, {
    String? sessionId,
    String? nodeId,
  }) async* {
    late final _TutorContext ctx;
    late final String prompt;
    try {
      ctx = await _buildContext(topicId, sessionId: sessionId, nodeId: nodeId);
      prompt = buildTutorPrompt(
        topic: ctx.topicName ?? '',
        goal: ctx.topicGoal ?? '',
        targetLevel: ctx.targetLevel,
        currentLevel: ctx.currentLevel,
        currentNode: ctx.currentNodeLabel,
        nodePath: ctx.nodePath,
        currentMastery: ctx.currentMastery,
        misconceptions: ctx.misconceptions.isNotEmpty ? ctx.misconceptions : null,
        timeRemainingMinutes: ctx.timeRemainingMinutes,
        recentAttempts: ctx.recentAttempts.isNotEmpty ? ctx.recentAttempts : null,
        message: message,
      );
    } catch (err) {
      // Контекст не собрался (ошибка БД/модели) — не роняем стрим, отдаём fallback.
      final text = _fallbackText(
        const _TutorContext(
          targetLevel: 'basic_understanding',
          currentLevel: 'awareness',
        ),
        message,
        err,
      );
      const chunk = 64;
      for (var i = 0; i < text.length; i += chunk) {
        yield {'kind': 'token', 'text': text.substring(i, math.min(i + chunk, text.length))};
      }
      yield {'kind': 'done', 'usedFallback': true, 'timeRemainingMinutes': null};
      return;
    }

    try {
      final stream = scheduler.executeStream('tutor', () => prompt);
      var any = false;
      await for (final token in stream) {
        if (token.isNotEmpty) {
          any = true;
          yield {'kind': 'token', 'text': token};
        }
      }
      if (!any) throw Exception('LLM API вернул пустой ответ');
    } catch (err) {
      final text = _fallbackText(ctx, message, err);
      const chunk = 64;
      for (var i = 0; i < text.length; i += chunk) {
        yield {'kind': 'token', 'text': text.substring(i, math.min(i + chunk, text.length))};
      }
      yield {
        'kind': 'done',
        'usedFallback': true,
        'timeRemainingMinutes': ctx.timeRemainingMinutes,
      };
      return;
    }

    yield {
      'kind': 'done',
      'usedFallback': false,
      'timeRemainingMinutes': ctx.timeRemainingMinutes,
    };
  }

  // ─── Private helpers ────────────────────────────────────────────────────────

  Future<_TutorContext> _buildContext(
    String topicId, {
    String? sessionId,
    String? nodeId,
  }) async {
    final topic = await repo.getTopic(topicId);
    final currentLevel = await learnerModel.getCurrentLevel(topicId);
    final targetLevel = topic?.targetLevel ?? MasteryLevel.basicUnderstanding;

    final currentNode = sessionId != null
        ? await _currentNodeOfSession(sessionId)
        : nodeId != null
            ? await _nodeOfId(nodeId)
            : null;

    final misconceptions = await _recentMisconceptions(topicId);
    final timeLeft = sessionId != null
        ? await _remainingMinutes(sessionId)
        : null;

    String? currentMastery;
    if (currentNode != null) {
      final profile =
          await learnerModel.getConceptProfile(currentNode['id']!, topicId);
      if (profile != null) {
        currentMastery =
            'освоение ${(profile.masteryScore * 100).round()}%';
      }
    }

    final recentAttempts = await _recentAttempts(topicId);

    return _TutorContext(
      topicName: topic?.name,
      topicGoal: topic?.goal.raw,
      targetLevel: targetLevel.raw,
      currentLevel: currentLevel.raw,
      currentNodeLabel: currentNode?['label'],
      nodePath: currentNode?['path']?.cast<String>(),
      currentMastery: currentMastery,
      misconceptions: misconceptions,
      recentAttempts: recentAttempts,
      timeRemainingMinutes: timeLeft,
    );
  }

  String _fallbackText(_TutorContext ctx, String message, Object err) {
    final errorMessage = err is Exception ? err.toString() : err.toString();
    return 'Не удалось получить ответ от модели. '
        'Тема: ${ctx.topicName ?? ''}. Ваш вопрос: $message. '
        '(Ошибка: $errorMessage)';
  }

  Future<Map<String, dynamic>?> _nodeOfId(String nodeId) async {
    final node = await repo.getNode(nodeId);
    if (node == null) return null;

    final allNodes = await repo.listNodes(node.topicId);
    final byId = <String, KnowledgeNode>{};
    for (final n in allNodes) {
      byId[n.id] = n;
    }

    final path = <String>[];
    var current = nodeId;
    var guard = 0;
    while (byId.containsKey(current) && guard < 50) {
      final row = byId[current]!;
      path.insert(0, row.label);
      final parentId = row.parentId;
      if (parentId == null || parentId.isEmpty) break;
      current = parentId;
      guard++;
    }

    return {'id': node.id, 'label': node.label, 'path': path};
  }

  Future<Map<String, dynamic>?> _currentNodeOfSession(String sessionId) async {
    final session = await repo.getSession(sessionId);
    if (session == null) return null;

    final curriculum = session.curriculum;
    final idx = session.currentIndex;
    if (idx < 0 || idx >= curriculum.items.length) return null;

    final item = curriculum.items[idx];
    final node = await repo.getNode(item.nodeId);
    if (node == null) return null;

    final withPath = await _nodeOfId(node.id);
    return withPath ?? {'id': node.id, 'label': node.label, 'path': <String>[]};
  }

  Future<List<String>> _recentMisconceptions(String topicId,
      {int limit = 3}) async {
    return await learnerModel.getWeakConcepts(topicId, limit: limit);
  }

  Future<List<String>> _recentAttempts(String topicId,
      {int limit = 4}) async {
    final profiles = await learnerModel.getConceptProfiles(topicId);
    final withErrors = profiles.where((p) => p.errors.isNotEmpty);
    final items = <String>[];

    for (final p in withErrors) {
      for (final err in p.errors) {
        items.add('${p.nodeId}: ${err.description.isNotEmpty ? err.description : err.type.wire}');
        if (items.length >= limit) break;
      }
      if (items.length >= limit) break;
    }

    if (items.length < limit) {
      for (final p in profiles) {
        if (items.length >= limit) break;
        if (p.masteryScore < 0.6) {
          items.add(
              '${p.nodeId}: слабое освоение (${(p.masteryScore * 100).round()}%)');
        }
      }
    }

    return items.take(limit).toList();
  }

  Future<int?> _remainingMinutes(String sessionId) async {
    final session = await repo.getSession(sessionId);
    if (session == null) return null;
    final budget = session.timeBudgetMinutes;
    final startedAt = DateTime.tryParse(session.startedAt);
    if (startedAt == null) return null;
    final elapsed =
        DateTime.now().difference(startedAt).inMilliseconds / 60000;
    return math.max(0, (budget - elapsed).round());
  }
}
