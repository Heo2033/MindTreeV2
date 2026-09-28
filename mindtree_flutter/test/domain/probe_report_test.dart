// Регрессии детерминированного отчёта probe.
//
// Закрывает реальные баги, найденные на первом end-to-end прогоне:
//   1. `MasteryLevel` попадал в JSON как enum → `Converting object to an
//      encodable object failed` (analyzer это не ловит в `Map<String, dynamic>`).
//   2. Случайные продакшн-id (`session_*`, `asmt_*`, `ms_*`) и wall-clock
//      `completedAt` попадали в отчёт → два прогона давали разные байты.
//   3. `MilestoneEngine.generate` уже сохраняет milestones сам, а pipeline
//      вставлял их повторно → `UNIQUE constraint failed`.
//
// Тесты гоняют НАСТОЯЩИЙ pipeline на fake LLM и сравнивают вывод побайтово.

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindtree_flutter/data/database/mindtree_db.dart';
import 'package:mindtree_flutter/data/database/mindtree_repository.dart';
import 'package:mindtree_flutter/data/llm/client.dart';
import 'package:mindtree_flutter/data/llm/scheduler.dart';
import 'package:mindtree_flutter/domain/engines/engine_factory.dart';

import '../../tool/probe/fake_llm.dart';
import '../../tool/probe/pipeline.dart';
import '../../tool/probe/probe_result.dart';
import '../../tool/probe/report.dart';

const _q1 = 'доказательство теоремы остановки';

/// Гоняет полный pipeline на детерминированном fake LLM и in-memory БД.
Future<ProbeResult> runMockProbe({
  List<String> queries = const [_q1],
  bool skipSession = false,
}) async {
  final db = MindtreeDb(NativeDatabase.memory());
  final fake = FakeLlm();
  final config = const LLMConfig(isMock: true, temperature: 0, numCtx: 16384);
  final engines = buildEngines(
    repo: MindtreeRepository(db),
    configProvider: () => config,
    schedulerConfig: const SchedulerConfig(
      maxRPM: 100000,
      maxRPD: 100000,
      maxConcurrency: 1,
    ),
    llmCall: (cfg, prompt, {model, temperature, seed}) async =>
        fake.invoke(cfg, prompt, model: model, temperature: temperature),
  );
  try {
    return await runPipeline(
      engines,
      PipelineOptions(
        queries: queries,
        goal: 'overview',
        level: 1,
        minutes: 30,
        skipSession: skipSession,
        mock: true,
      ),
    );
  } finally {
    await db.close();
  }
}

void main() {
  // Полный прогон дорогой, поэтому считаем его один раз на группу.
  late ProbeResult result;
  setUpAll(() async {
    result = await runMockProbe();
  });

  group('JSON-сериализация', () {
    test('рендерится без исключений (enum → строка, без сырых DateTime)', () {
      expect(() => renderJson(result), returnsNormally);
    });

    test('все значения — JSON-совместимые (регрессия MasteryLevel enum)', () {
      // jsonEncode — строгий контракт: любой enum/DateTime/объект упадёт.
      expect(() => jsonEncode(resultToJson(result)), returnsNormally);
    });

    test('milestone level сериализован строкой, а не enum', () {
      final json = jsonDecode(renderJson(result)) as Map<String, dynamic>;
      final queries = json['queries'] as List<dynamic>;
      final milestones = (queries.first as Map<String, dynamic>)['milestones']
          as List<dynamic>;
      expect(milestones, isNotEmpty);
      for (final m in milestones.cast<Map<String, dynamic>>()) {
        expect(m['level'], isA<String>());
      }
    });
  });

  group('детерминизм', () {
    test('два независимых прогона дают побайтово одинаковый report.json', () async {
      final second = await runMockProbe();
      expect(renderJson(second), renderJson(result));
    });

    test('два независимых прогона дают побайтово одинаковый report.md', () async {
      final second = await runMockProbe();
      expect(renderMarkdown(second), renderMarkdown(result));
    });

    test('рендер чистый: повторный рендер того же результата идентичен', () {
      expect(renderJson(result), renderJson(result));
      expect(renderMarkdown(result), renderMarkdown(result));
    });

    test('в отчёте нет случайных продакшн-id', () {
      final json = renderJson(result);
      // Префиксы `shortIdWith`, которые генерируются случайно.
      expect(json, isNot(contains('session_')));
      expect(json, isNot(contains('asmt_')));
      expect(json, isNot(contains('ms_')));
    });

    test('случайные id заменены стабильными алиасами', () {
      final queries = (jsonDecode(renderJson(result)) as Map<String, dynamic>)['queries']
          as List<dynamic>;
      final q = queries.first as Map<String, dynamic>;
      expect((q['session'] as Map<String, dynamic>)['idAlias'], 'a0');
      // curriculum.sessionId и session.id — один и тот же объект сессии,
      // поэтому алиас обязан совпасть.
      final curriculumAlias = (q['curriculum'] as Map<String, dynamic>)['sessionAlias'];
      expect(curriculumAlias, (q['session'] as Map<String, dynamic>)['idAlias']);
    });
  });

  group('конфиденциальность', () {
    test('в отчёте нет apiKey/baseUrl', () {
      final json = renderJson(result).toLowerCase();
      expect(json, isNot(contains('apikey')));
      expect(json, isNot(contains('api_key')));
      expect(json, isNot(contains('baseurl')));
      expect(json, isNot(contains('base_url')));
    });
  });

  group('структура отчёта', () {
    test('верхний уровень: schema, params, llm, checks, queries', () {
      final json = jsonDecode(renderJson(result)) as Map<String, dynamic>;
      expect(
        json.keys,
        containsAll(<String>['schema', 'params', 'llm', 'checks', 'queries']),
      );
      expect(json['schema'], 'mindtree.probe/v1');
    });

    test('params помечает прогон как mock', () {
      final json = jsonDecode(renderJson(result)) as Map<String, dynamic>;
      final params = json['params'] as Map<String, dynamic>;
      expect(params['mock'], isTrue);
      expect(params['queries'], [_q1]);
      expect(params['level'], 1);
    });

    test('checks отсортированы по code (стабильный порядок)', () {
      final json = jsonDecode(renderJson(result)) as Map<String, dynamic>;
      final codes = ((json['checks'] as Map<String, dynamic>)['results'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map((c) => c['code'] as String)
          .toList();
      final sorted = List<String>.of(codes)..sort();
      expect(codes, sorted);
    });

    test('llm-статистика содержит вызовы по видам промптов', () {
      final json = jsonDecode(renderJson(result)) as Map<String, dynamic>;
      final llm = json['llm'] as Map<String, dynamic>;
      expect(llm['calls'], greaterThan(0));
      final byKind = llm['callsByKind'] as Map<String, dynamic>;
      expect(byKind['structure'], greaterThan(0));
      expect(byKind['content'], greaterThan(0));
    });

    test('markdown содержит основные секции', () {
      final md = renderMarkdown(result);
      expect(md, contains('MindTree probe report'));
      expect(md, contains('## Quality checks'));
    });
  });

  group('��������� ��������', () {
    // ���������: �������� ������ �������� ����� ��������� ���, � `single_root`
    // ����� 2 ����� �� ���� ����������� �������� > ������ `fail`.
    test('��� ������� �� ���� ������� single_root fail', () async {
      final multi = await runMockProbe(queries: const [_q1, '��������']);
      expect(multi.outcomes, hasLength(2));
      final singleRootFails = multi.checks
          .where((c) => c.code == 'single_root' && c.severity.name == 'fail')
          .toList();
      expect(
        singleRootFails.map((c) => c.message).join('\n'),
        isEmpty,
        reason: '� ������ ���� ���� ������ � ��� ����� ��� �����.',
      );
      expect(
        multi.summary.hasFailures,
        isFalse,
        reason: 'Mock-������ �� ������ ������ fail.\n'
            '${multi.checks.map((c) => '${c.severity.name} ${c.code} '
                '${c.nodeId ?? ''}: ${c.message}').join('\n')}',
      );
    });

    test('� ������� ������� ���� topicId � ���� ������', () async {
      final multi = await runMockProbe(queries: const [_q1, '��������']);
      final topicIds = multi.outcomes.map((o) => o.topicId).toSet();
      expect(topicIds, hasLength(2), reason: 'Topic ID �����������.');
      for (final o in multi.outcomes) {
        final roots = o.nodes.where((n) => n.parentId == null).toList();
        expect(roots, hasLength(1), reason: '����� ���� ������ �� ����.');
        expect(roots.single.id, o.rootId);
      }
    });

    test('������-��������� ������ ���� ��������������', () async {
      final a = await runMockProbe(queries: const [_q1, '��������']);
      final b = await runMockProbe(queries: const [_q1, '��������']);
      expect(renderJson(b), renderJson(a));
    });
  });

  group('--skip-session', () {
    test('������� ������ �� ��� fail', () async {
      final r = await runMockProbe(skipSession: true);
      expect(r.params.sessionSkipped, isTrue);
      expect(r.outcomes.single.session, isNull);
      expect(
        r.summary.hasFailures,
        isFalse,
        reason: '������� ������ � ������� �����, � �� ���������.\n'
            '${r.checks.map((c) => '${c.severity.name} ${c.code} '
                '${c.nodeId ?? ''}: ${c.message}').join('\n')}',
      );
    });
  });
}
