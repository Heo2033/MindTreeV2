// Регресс защиты времени ответа в `AssessmentEngine.recordAttempt`.
//
// `timeMs` приходил из UI-таймера и раньше писался в БД как есть: зависший
// таймер (или экстраполяция через `elapsedBetween` после сворачивания экрана)
// давал ответы «длиной» в дни и искажал любую статистику времени-на-вопрос.
// Теперь значение нормализуется чистой функцией [sanitizeAttemptTimeMs]:
// ≤0 и неправдоподобно большие значения заменяются на 0.
//
// Порог — общий доменный `kImplausibleDurationMs`
// (`lib/domain/lib/time_plausibility.dart`), он же порог фильтра аналитики
// и пара `kImplausibleAnswerMs` из `tool/review/session_checks.dart`.
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mindtree_flutter/data/database/mindtree_db.dart';
import 'package:mindtree_flutter/data/database/mindtree_repository.dart';
import 'package:mindtree_flutter/data/llm/client.dart';
import 'package:mindtree_flutter/data/llm/scheduler.dart';
import 'package:mindtree_flutter/domain/engines/assessment_engine.dart';
import 'package:mindtree_flutter/domain/engines/engine_factory.dart';
import 'package:mindtree_flutter/domain/lib/time_plausibility.dart';
import 'package:mindtree_flutter/domain/models/models.dart';

import '../../tool/probe/fake_llm.dart';

void main() {
  group('sanitizeAttemptTimeMs: чистая функция', () {
    test('потолок — общий доменный порог правдоподобности (2 часа)', () {
      expect(kImplausibleDurationMs, 2 * 60 * 60 * 1000);
      expect(kMaxPlausibleAttemptMs, kImplausibleDurationMs,
          reason: 'attempt не может быть правдоподобнее, чем порог аналитики');
    });

    test('обычное время ответа не меняется', () {
      expect(sanitizeAttemptTimeMs(0), 0);
      expect(sanitizeAttemptTimeMs(1), 1);
      expect(sanitizeAttemptTimeMs(45 * 1000), 45 * 1000);
      expect(sanitizeAttemptTimeMs(15 * 60 * 1000), 15 * 60 * 1000);
    });

    test('граница: ровно порог допустим, на 1 мс больше — нет', () {
      expect(sanitizeAttemptTimeMs(kMaxPlausibleAttemptMs),
          kMaxPlausibleAttemptMs);
      expect(sanitizeAttemptTimeMs(kMaxPlausibleAttemptMs + 1), 0);
      expect(sanitizeAttemptTimeMs(3 * 60 * 60 * 1000), 0,
          reason: '3 часа ответа — это уже зависший таймер');
    });

    test('неположительные значения → 0', () {
      expect(sanitizeAttemptTimeMs(-1), 0);
      expect(sanitizeAttemptTimeMs(-9 * 60 * 60 * 1000), 0);
    });

    test('epoch-подобные значения (мс вместо длительности) → 0', () {
      expect(sanitizeAttemptTimeMs(1760000000000), 0);
      expect(sanitizeAttemptTimeMs(2 * 60 * 60 * 1000 * 24 * 365), 0);
    });
  });

  group('recordAttempt: санитизация перед записью', () {
    late MindtreeDb db;
    late MindtreeRepository repo;
    late MindtreeEngines engines;

    setUp(() async {
      db = MindtreeDb(NativeDatabase.memory());
      repo = MindtreeRepository(db);
      final fake = FakeLlm();
      engines = buildEngines(
        repo: repo,
        configProvider: () =>
            const LLMConfig(isMock: true, temperature: 0, numCtx: 16384),
        schedulerConfig: const SchedulerConfig(
          maxRPM: 100000,
          maxRPD: 100000,
          maxConcurrency: 1,
          maxRetries: 0,
        ),
        llmCall: (cfg, prompt, {model, temperature, seed}) async =>
            fake.invoke(cfg, prompt, model: model, temperature: temperature),
      );
      await repo.createAssessment(const Assessment(
        id: 'asmt_1',
        sessionId: 's1',
        type: AssessmentType.quiz,
        startedAt: '2026-01-01T00:00:00',
      ));
    });

    tearDown(() async {
      await db.close();
    });

    test('неправдоподобно большое время записывается как 0', () async {
      await engines.assessment
          .recordAttempt('asmt_1', 'q1', 'ответ', true, kMaxPlausibleAttemptMs + 1);

      final attempts = await repo.listAttempts('asmt_1');
      expect(attempts, hasLength(1));
      expect(attempts.single.timeSpentMs, 0);
      expect(attempts.single.correct, isTrue,
          reason: 'санитизация не трогает сам ответ');
      expect(attempts.single.answer, 'ответ');
    });

    test('ровно порог сохраняется как есть', () async {
      await engines.assessment.recordAttempt(
          'asmt_1', 'q2', 'ответ', false, kMaxPlausibleAttemptMs);

      final attempts = await repo.listAttempts('asmt_1');
      expect(attempts.single.timeSpentMs, kMaxPlausibleAttemptMs);
    });

    test('нормальное время и фидбек сохраняются без изменений', () async {
      await engines.assessment
          .recordAttempt('asmt_1', 'q3', 'ответ', true, 42 * 1000, feedback: 'ок');

      final attempts = await repo.listAttempts('asmt_1');
      expect(attempts.single.timeSpentMs, 42 * 1000);
      expect(attempts.single.feedback, 'ок');
    });

    test('отрицательное время записывается как 0', () async {
      await engines.assessment.recordAttempt('asmt_1', 'q4', '', false, -500);

      final attempts = await repo.listAttempts('asmt_1');
      expect(attempts.single.timeSpentMs, 0);
    });
  });
}
