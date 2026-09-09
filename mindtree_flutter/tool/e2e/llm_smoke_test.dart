// Live end-to-end smoke test against a real LLM provider.
//
// Reads a hardcoded provider config from `provider-config.json` (generated
// from `server/.env` via `tool/gen_config.ps1`), opens an in-memory Drift DB,
// and drives the real KnowledgeGraphEngine + prompt builders + TreeScheduler +
// LLM client pipeline. Asserts a valid knowledge tree is produced and
// persisted to the repository.
//
// Run:
//   flutter test tool/e2e/llm_smoke_test.dart
//
// Skips (passes trivially) when provider-config.json or its API key is missing
// so the suite stays green without secrets.

import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mindtree_flutter/data/database/mindtree_db.dart';
import 'package:mindtree_flutter/data/database/mindtree_repository.dart';
import 'package:mindtree_flutter/data/llm/client.dart' as llm_client;
import 'package:mindtree_flutter/data/llm/scheduler.dart';
import 'package:mindtree_flutter/data/prompts/prompts.dart';
import 'package:mindtree_flutter/domain/engines/knowledge_graph_engine.dart';
import 'package:mindtree_flutter/domain/engines/scoped_ids.dart';
import 'package:mindtree_flutter/domain/models/models.dart';

const _configPath = 'provider-config.json';
const _query = 'Понятие переменной в программировании';
const _topicId = 'e2e_topic_1';

void main() {

  final Map<String, dynamic>? cfgJson = _readProviderConfig();
  final apiKey =
      cfgJson?['LLM_API_KEY'] as String? ?? '';

  test(
    'генерация дерева знаний через реальный LLM (odirouter)',
    () async {
      if (cfgJson == null || apiKey.isEmpty || cfgJson['LLM_BASE_URL'] == null) {
        markTestSkipped(
          'Нет provider-config.json (или ключа) — пропуск живого E2E. '
          'Сгенерируйте его: & tool\\gen_config.ps1',
        );
        return;
      }

      final llmCfg = llm_client.LLMConfig(
        apiKey: apiKey,
        baseUrl: cfgJson['LLM_BASE_URL'] as String,
        model: cfgJson['LLM_MODEL'] as String? ?? 'gpt-4o',
        modelStrong: cfgJson['LLM_MODEL_STRONG'] as String? ?? '',
        modelStrongFallback:
            cfgJson['LLM_MODEL_STRONG_FALLBACK'] as String? ?? '',
        modelFast: cfgJson['LLM_MODEL_FAST'] as String? ?? '',
        temperature: 0.4,
        numCtx: 8192,
        timeoutMs: 180000,
      );

      final scheduler = TreeScheduler(
        configProvider: () => llmCfg,
        config: const SchedulerConfig(
          maxRPM: 10,
          maxConcurrency: 2,
          maxRetries: 2,
          opDeadlineMs: 300000,
        ),
      );

      final db = MindtreeDb(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = MindtreeRepository(db);

      await repo.createTopic(Topic(
        id: _topicId,
        name: 'E2E: $_query',
        goal: LearningGoal.overview,
        targetLevel: MasteryLevel.basicUnderstanding,
        timeBudgetMinutes: 30,
      ));

      final engine = KnowledgeGraphEngine(
        repo: repo,
        scheduler: scheduler,
        generateStructure: (ctx) => buildL1Prompt(
          ctx.query,
          goal: ctx.options.goal,
          level: ctx.options.level,
        ),
        generateL2: (ctx) => buildL2Prompt(
          userQuery: ctx.userQuery,
          rootId: ctx.root.id,
          rootTitle: ctx.root.title,
          rootCanonicalDefinition: ctx.root.canonicalDefinition,
          goal: ctx.options?.goal,
          level: ctx.options?.level,
          timeBudgetMinutes: ctx.options?.timeBudgetMinutes,
        ),
        generateL3: (ctx) => buildL3Prompt(
          userQuery: ctx.userQuery,
          rootTitle: ctx.rootTitle,
          parentId: ctx.parent.id,
          parentTitle: ctx.parent.title,
          parentCanonicalDefinition: ctx.parent.canonicalDefinition,
          siblings: [
            for (final s in ctx.siblings)
              {
                'id': s.id,
                'title': s.title,
                'canonical_definition': s.canonicalDefinition,
              },
          ],
          goal: ctx.options?.goal,
          level: ctx.options?.level,
        ),
        generateExpand: (ctx) => buildExpandPrompt(
          rootTopic: ctx.rootTopic,
          contextPaths: ctx.contextPaths,
          nodesToExpand: [
            for (final n in ctx.nodesToExpand)
              {'id': n.id, 'title': n.title, 'path': n.path},
          ],
          existingTree: [
            for (final n in ctx.existingTree)
              {'id': n.id, 'title': n.title, 'parentId': n.parentId, 'level': n.level},
          ],
          goal: ctx.options?.goal,
          level: ctx.options?.level,
        ),
        generateValidate: (ctx) => buildValidatePrompt(
          [
            for (final n in ctx.nodes)
              {
                'id': n.id,
                'parentId': n.parentId,
                'level': n.level,
                'label': n.label,
                'one_liner': n.oneLiner,
                'details': n.details,
                'conceptType': n.conceptType,
                'semantic_axis': n.semanticAxis,
                'canonical_definition': n.canonicalDefinition,
                'forbidden_interpretations': n.forbiddenInterpretations,
              },
          ],
          focusIds: ctx.focusIds,
        ),
        generateRepair: (ctx) => buildRepairPrompt(
          problemNodes: [
            for (final n in ctx.problemNodes)
              {
                'id': n.id,
                'parentId': n.parentId,
                'level': n.level,
                'label': n.label,
                'one_liner': n.oneLiner,
                'details': n.details,
                'conceptType': n.conceptType,
                'semantic_axis': n.semanticAxis,
                'canonical_definition': n.canonicalDefinition,
                'forbidden_interpretations': n.forbiddenInterpretations,
              },
          ],
          issues: [
            for (final i in ctx.issues)
              {'type': i.type, 'node_id': i.nodeId, 'reason': i.reason},
          ],
          level: ctx.level,
        ),
        generateContent: (ctx) => buildContentPrompt(
          rootTopic: ctx.rootTopic,
          nodePath: ctx.nodePath,
          nodeId: ctx.node.id,
          nodeLabel: ctx.node.label,
          siblings: ctx.siblings,
          knowledgeLevel: ctx.knowledgeLevel,
          goal: ctx.goal,
          nodeLevel: ctx.nodeLevel,
          isRoot: ctx.isRoot,
          isCriticalDomain: ctx.isCriticalDomain,
          ontologyContext: {
            'canonical_definition': ctx.ontologyContext.canonicalDefinition,
            'semantic_axis': ctx.ontologyContext.semanticAxis,
            'forbidden_interpretations':
                ctx.ontologyContext.forbiddenInterpretations,
          },
        ),
      );

      final phases = <String>{};
      final result = await engine.generate(
        _query,
        goal: 'overview',
        level: 'basic_understanding',
        timeBudgetMinutes: 30,
        onProgress: (phase, message, [stats]) {
          phases.add(phase);
          // ignore: avoid_print
          print('  [e2e] $phase: $message');
          if (stats != null) {
            // ignore: avoid_print
            print('  [e2e]   stats: ${stats.total} узлов, глубина ${stats.depth}');
          }
        },
      );

      // ignore: avoid_print
      print('  [e2e] warnings: ${result.warnings}');

      final offline =
          result.warnings.any((w) => w.contains('Офлайн') || w.contains('демо'));
      expect(offline, isFalse,
          reason: 'Живой LLM работал — дерево не должно быть демо/офлайн.');

      expect(phases, containsAll(['structure', 'done']));
      expect(result.nodes, isNotEmpty, reason: 'Дерево должно содержать узлы.');
      expect(
        result.nodes.where((n) => n.level == 1 && n.parentId == null),
        isNotEmpty,
        reason: 'Должен быть уровень 1 (корень).',
      );
      expect(
        result.nodes.where((n) => n.level == 2),
        isNotEmpty,
        reason: 'Должны быть разделы уровня 2.',
      );

      // Persist via the same path the app uses, then re-read from the DB.
      final scoped = scopeNodeIds(result.nodes, _topicId);
      final knowledgeNodes = scoped
          .map((d) => KnowledgeNode(
                id: d.id,
                topicId: _topicId,
                parentId: d.parentId,
                level: d.level,
                label: d.title.trim(),
                oneLiner: d.canonicalDefinition ?? '',
                details: '',
              ))
          .toList();
      await repo.insertOrReplaceNodes(knowledgeNodes);

      final persisted = await repo.listNodes(_topicId);
      expect(persisted.length, result.nodes.length,
          reason: 'Все сгенерированные узлы записаны в БД.');
      expect(persisted, isNotEmpty);
      expect(persisted.every((n) => n.label.trim().isNotEmpty), isTrue,
          reason: 'У всех узлов есть метка.');
      await repo.deleteTopic(_topicId);
    },
    timeout: const Timeout(Duration(minutes: 25)),
  );
}

Map<String, dynamic>? _readProviderConfig() {
  final f = File(_configPath);
  if (!f.existsSync()) return null;
  try {
    return jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
}