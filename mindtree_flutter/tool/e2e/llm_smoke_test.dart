// Live end-to-end smoke test against a real LLM provider.
//
// Drives the FULL learning loop through the same factory the app uses
// (`buildEngines`) and the same pipeline the headless probe uses
// (`runPipeline`): tree → content → curriculum → diagnostic → session →
// assessment → mastery → milestones, plus the pure quality checks.
//
// This replaces the older version of this file, which hand-wired every
// prompt builder into a private `KnowledgeGraphEngine`. That duplication
// meant the smoke test validated a graph the app never runs; now it validates
// the real wiring, so a broken engine dependency cannot pass here and fail in
// the app (and vice versa).
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
import 'package:mindtree_flutter/domain/engines/engine_factory.dart';
import 'package:mindtree_flutter/domain/engines/scoped_ids.dart';

import '../probe/pipeline.dart';

const _configPath = 'provider-config.json';
const _query = 'Понятие переменной в программировании';

void main() {
  final Map<String, dynamic>? cfgJson = _readProviderConfig();
  final apiKey = cfgJson?['LLM_API_KEY'] as String? ?? '';

  test(
    'полный цикл обучения через реальный LLM (buildEngines + probe pipeline)',
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

      final db = MindtreeDb(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = MindtreeRepository(db);

      // Ровно та же сборка движков, что в приложении.
      final engines = buildEngines(
        repo: repo,
        configProvider: () => llmCfg,
        schedulerConfig: const SchedulerConfig(
          maxRPM: 10,
          maxRPD: 500,
          maxConcurrency: 2,
          maxRetries: 2,
          opDeadlineMs: 300000,
        ),
      );

      final result = await runPipeline(
        engines,
        PipelineOptions(
          queries: const [_query],
          goal: 'overview',
          level: 1,
          minutes: 30,
          // ignore: avoid_print
          onProgress: (m) => print('  [e2e] $m'),
        ),
      );

      // Именно живой LLM, а не офлайн-фолбэк движков.
      final outcome = result.outcomes.single;
      final notes = outcome.notes.join(' | ');
      expect(
        notes.contains('Офлайн') || notes.contains('демо'),
        isFalse,
        reason: 'Живой LLM работал — отчёт не должен содержать офлайн/демо.\n'
            'notes: $notes',
      );

      expect(outcome.nodes, isNotEmpty, reason: 'Дерево должно содержать узлы.');
      expect(
        outcome.nodes.where((n) => n.level == 1 && n.parentId == null).length,
        1,
        reason: 'Ровно один корень на тему.',
      );
      expect(
        outcome.nodes.where((n) => n.level == 2),
        isNotEmpty,
        reason: 'Должны быть разделы уровня 2.',
      );

      // scoped-иды: `~`+8hex от topicId, без «голых» id.
      expect(
        outcome.nodes.every((n) => n.id.contains('~')),
        isTrue,
        reason: 'Все узлы должны быть проскоуплены: ${outcome.nodes.first.id}',
      );
      expect(
        outcome.nodes.every((n) => scopedSuffix(outcome.topicId).isNotEmpty),
        isTrue,
      );

      // Дерево реально сохранено в БД и читается обратно.
      final persisted = await repo.listNodes(outcome.topicId);
      expect(persisted.length, outcome.nodes.length,
          reason: 'Все сгенерированные узлы записаны в БД.');
      expect(persisted.every((n) => n.label.trim().isNotEmpty), isTrue,
          reason: 'У всех узлов есть метка.');
      expect(persisted.every((n) => n.oneLiner.trim().isNotEmpty), isTrue,
          reason: 'У всех узлов есть one_liner.');

      // Контент, curriculum, диагностика, сессия, оценка, mastery, milestones.
      expect(outcome.curriculum, isNotNull, reason: 'Curriculum построен.');
      expect(outcome.curriculum!.items, isNotEmpty);
      expect(outcome.diagnosticQuestions, isNotEmpty,
          reason: 'Диагностика вернула вопросы.');
      expect(outcome.session, isNotNull, reason: 'Учебная сессия создана.');
      expect(outcome.answers, isNotEmpty, reason: 'Шаги активности отвечены.');
      expect(outcome.assessment, isNotNull, reason: 'Assessment проведён.');
      expect(outcome.assessment!.score, isNotNull);
      expect(outcome.masteryAfter, isNotNull, reason: 'Mastery рассчитан.');
      expect(outcome.milestones, isNotEmpty, reason: 'Milestones построены.');

      // Ни одного quality-нарушения уровня fail.
      final fails = result.checks.where((c) => c.severity.name == 'fail').toList();
      expect(
        fails.map((c) => '${c.code} ${c.nodeId ?? ''}: ${c.message}').join('\n'),
        isEmpty,
        reason: 'Quality-проверки уровня fail не должны срабатывать на живом LLM.',
      );

      await repo.deleteTopic(outcome.topicId);
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
