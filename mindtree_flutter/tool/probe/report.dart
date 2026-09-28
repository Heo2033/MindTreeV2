// Рендеринг отчётов probe.
//
// ДВА ВИДА ОТЧЁТА:
// - `report.json` / `report.md` — ДЕТЕРМИНИРОВАННЫЕ. Собираются только из
//   `ProbeResult`, где нет ни времени, ни случайных id. Два прогона с
//   одинаковым входом дают побайтово одинаковые файлы.
// - `run-stats.json` — НЕдетерминированный (latency, wall-clock). Лежит
//   отдельно, чтобы случайно не сломать побайтовое сравнение.
//
// Детерминизм обеспечивают три правила, и все они соблюдаются ниже:
// 1. Ключи maps вставляются в фиксированном порядке (Dart `Map` сохраняет
//    порядок вставки, `jsonEncode` выводит именно его).
// 2. Все списки сортируются по стабильному ключу ДО рендера.
// 3. Дробные числа округляются до [_precision] знаков: одинаковые вычисления
//    на разных платформах не должны отличаться в последнем бите.

import 'dart:convert';

import 'probe_result.dart';
import 'quality_checks.dart';
import 'tree_mapper.dart';

/// Знаков после запятой в отчёте.
const int _precision = 4;

/// Округляет число для стабильного вывода.
num _num(num v) {
  if (v is int) return v;
  if (v.isNaN || v.isInfinite) return 0;
  final factor = _pow10(_precision);
  return (v * factor).round() / factor;
}

int _pow10(int n) {
  var r = 1;
  for (var i = 0; i < n; i++) {
    r *= 10;
  }
  return r;
}

/// `double` как строка с фиксированной точностью — для Markdown.
String _fmt(num v, {int digits = 2}) {
  final n = _num(v);
  if (n is int) return n.toString();
  final s = n.toStringAsFixed(digits);
  // Убираем хвостовые нули: `0.50` → `0.5`, но `0.00` → `0`.
  var out = s;
  if (out.contains('.')) {
    out = out.replaceFirst(RegExp(r'0+$'), '');
    if (out.endsWith('.')) out = out.substring(0, out.length - 1);
  }
  return out;
}

/// Экранирует текст для таблицы Markdown.
String _md(String s) => s
    .replaceAll('|', r'\|')
    .replaceAll('\r', ' ')
    .replaceAll('\n', ' ')
    .trim();

/// Обрезает текст до [max] символов с многоточием.
String _clip(String s, int max) {
  final flat = _md(s);
  return flat.length <= max ? flat : '${flat.substring(0, max - 1)}…';
}

/// JSON-отчёт: детерминированный, с отступами и завершающим переводом строки.
String renderJson(ProbeResult result) {
  final data = resultToJson(result);
  return '${const JsonEncoder.withIndent('  ').convert(data)}\n';
}

/// Собирает полный JSON-отчёт как данные.
///
/// Вынесено отдельно, чтобы тесты могли проверить структуру, не парся текст.
Map<String, dynamic> resultToJson(ProbeResult result) => {
      'schema': 'mindtree.probe/v1',
      'params': result.params.toJson(),
      'llm': result.llm.toJson(),
      'checks': {
        'summary': result.summary.toJson(),
        'results': [
          for (final c in result.checks)
            {
              'code': c.code,
              'severity': c.severity.name,
              if (c.nodeId != null) 'nodeId': c.nodeId,
              'message': c.message,
            },
        ],
      },
      'queries': [
        for (final o in result.outcomes) _outcomeToJson(o, _IdAliases()),
      ],
    };

/// Стабильные алиасы для продакшн-id, которые генерируются случайно
/// (`shortIdWith`: `session_*`, `asmt_*`).
///
/// Порядок присвоения — по первому появлению, поэтому для одного и того же
/// входа отчёт побайтово одинаков. Сырые id остаются в `run-stats.json`.
class _IdAliases {
  final Map<String, String> _byId = {};

  String alias(String? id) {
    if (id == null || id.isEmpty) return 'none';
    return _byId.putIfAbsent(id, () => 'a${_byId.length}');
  }
}

Map<String, dynamic> _outcomeToJson(QueryOutcome o, _IdAliases ids) => {
      'topicId': o.topicId,
      'query': o.query,
      'rootId': o.rootId,
      'notes': o.notes,
      'tree': {
        'nodeCount': o.nodes.length,
        'contentLoaded': [for (final n in o.nodes) if (n.contentLoaded) n.id].length,
        'nodes': [
          for (final n in sortNodesForReport(o.nodes))
            {
              'id': n.id,
              'parentId': n.parentId,
              'level': n.level,
              'label': n.label,
              'oneLiner': n.oneLiner,
              'details': n.details,
              if (n.analogy != null) 'analogy': n.analogy,
              'state': n.state.wire,
              'contentLoaded': n.contentLoaded,
              'leaf': n.leaf,
              'importance': _num(n.importance),
              'difficulty': _num(n.difficulty),
              'estimatedTimeMinutes': n.estimatedTimeMinutes,
              if (n.relations.isNotEmpty)
                'relations': [
                  for (final r in n.relations)
                    {
                      'from': r.from,
                      'to': r.to,
                      'type': r.type.raw,
                      if (r.label != null) 'label': r.label,
                    },
                ],
            },
        ],
      },
      'curriculum': o.curriculum == null
          ? null
          : {
              // Продакшн-id сессии генерируется случайно (`shortIdWith`), поэтому
              // в детерминированный отчёт попадает только стабильный алиас.
              'sessionAlias': ids.alias(o.curriculum!.sessionId),
              'totalEstimatedMinutes': o.curriculum!.totalEstimatedMinutes,
              'items': [
                for (final i in o.curriculum!.items)
                  {
                    'order': i.order,
                    'nodeId': i.nodeId,
                    'label': i.label,
                    'type': i.type.name,
                    'status': i.status.name,
                    'estimatedMinutes': i.estimatedMinutes,
                    'priority': _num(i.priority),
                    if (i.reason != null) 'reason': i.reason,
                  },
              ],
            },
      'alreadyKnown': o.alreadyKnown,
      'diagnostic': {
        'questions': [
          for (final q in o.diagnosticQuestions)
            {
              'id': q.id,
              'nodeId': q.nodeId,
              'question': q.question,
              'options': q.options,
              'correctIndex': q.correctIndex,
            },
        ],
        'answers': [
          for (final a in o.diagnosticAnswers)
            {
              'questionId': a.questionId,
              'nodeId': a.nodeId,
              'selectedIndex': a.selectedIndex,
              'correctIndex': a.correctIndex,
              'correct': a.selectedIndex == a.correctIndex,
            },
        ],
        if (o.diagnosticResult != null) ...{
          'currentLevel': o.diagnosticResult!.currentLevel,
          'score': _num(o.diagnosticResult!.score),
          'knownConcepts': o.diagnosticResult!.knownConcepts,
          'unknownConcepts': o.diagnosticResult!.unknownConcepts,
        },
      },
      'session': o.session == null
          ? null
          : {
              'idAlias': ids.alias(o.session!.id),
              'topicId': o.session!.topicId,
              'status': o.session!.status.name,
              'goal': o.session!.goal,
              'timeBudgetMinutes': o.session!.timeBudgetMinutes,
              'currentIndex': o.session!.currentIndex,
              'currentActivityStep': o.session!.currentActivityStep,
              'totalItems': o.session!.curriculum.items.length,
            },
      'activity': o.activity == null
          ? null
          : {
              'nodeId': o.activity!.nodeId,
              'nodeLabel': o.activity!.nodeLabel,
              'goal': o.activity!.goal,
              'isComplete': o.activity!.isComplete,
              'steps': [
                for (final s in o.activity!.steps)
                  {
                    'type': s.type,
                    'title': s.title,
                    'status': s.status,
                    if (s.instruction != null) 'instruction': s.instruction,
                    if (s.options != null) 'options': s.options,
                    if (s.correctIndex != null) 'correctIndex': s.correctIndex,
                    if (s.bestAnswer != null) 'bestAnswer': s.bestAnswer,
                    if (s.userAnswer != null) 'userAnswer': s.userAnswer,
                    if (s.correct != null) 'correct': s.correct,
                    if (s.feedback != null) 'feedback': s.feedback,
                  },
              ],
            },
      'answers': [for (final a in o.answers) a.toJson()],
      'misconceptions': [
        for (final a in o.answers)
          if (a.misconception.isNotEmpty)
            {
              'nodeId': a.nodeId,
              'nodeLabel': a.nodeLabel,
              'misconception': a.misconception,
            },
      ],
      'assessment': {
        'questions': [
          for (final q in o.assessmentQuestions)
            {
              'id': q.id,
              'type': q.type.wire,
              'nodeId': q.nodeId,
              'question': q.question,
              if (q.options != null) 'options': q.options,
              if (q.correctAnswer != null) 'correctAnswer': q.correctAnswer,
            },
        ],
        if (o.assessment != null) ...{
          'idAlias': ids.alias(o.assessment!.id),
          'type': o.assessment!.type.name,
          if (o.assessment!.score != null) 'score': _num(o.assessment!.score!),
          // `completedAt` — wall-clock, поэтому в run-stats, а не в отчёт.
          'completed': true,
        },
      },
      'mastery': {
        'before': o.masteryBefore == null
            ? null
            : {
                'level': o.masteryBefore!.newLevel.name,
                'score': _num(o.masteryBefore!.score),
                'reachedTarget': o.masteryBefore!.reachedTarget,
                'gaps': o.masteryBefore!.gaps,
              },
        'after': o.masteryAfter == null
            ? null
            : {
                'level': o.masteryAfter!.newLevel.name,
                'score': _num(o.masteryAfter!.score),
                'reachedTarget': o.masteryAfter!.reachedTarget,
                'gaps': o.masteryAfter!.gaps,
              },
        'concepts': o.masteryConcepts == null
            ? null
            : [
                for (final c in o.masteryConcepts!.concepts)
                  {
                    'nodeId': c.nodeId,
                    'understanding': _num(c.understanding),
                    'recall': _num(c.recall),
                    'application': _num(c.application),
                    'transfer': _num(c.transfer),
                    'confidence': _num(c.confidence),
                    if (c.misconception != null) 'misconception': c.misconception,
                  },
              ],
      },
      'milestones': [
        for (final m in o.milestones)
          {
            'idAlias': ids.alias(m.id),
            'level': m.level.raw,
            'title': m.title,
            'description': m.description,
            'status': m.status.name,
            'estimatedHours': _num(m.estimatedHours),
            'capabilities': m.capabilities,
            'alternativePaths': [
              for (final a in m.alternativePaths)
                {
                  'id': a.id,
                  'title': a.title,
                  'estimatedHours': _num(a.estimatedHours),
                },
            ],
          },
      ],
    };

/// Markdown-отчёт: детерминированный, читаемый человеком.
String renderMarkdown(ProbeResult result) {
  final b = StringBuffer();
  final p = result.params;

  b.writeln('# MindTree probe report');
  b.writeln();
  b.writeln('## Параметры');
  b.writeln();
  b.writeln('| Параметр | Значение |');
  b.writeln('| --- | --- |');
  b.writeln('| Режим | ${p.mock ? 'mock (детерминированный)' : 'реальный LLM'} |');
  b.writeln('| Цель | ${_md(p.goal)} |');
  b.writeln('| Уровень | ${p.level} |');
  b.writeln('| Время, мин | ${p.minutes} |');
  b.writeln('| Контент | ${p.contentSkipped ? 'пропущен' : 'сгенерирован'} |');
  b.writeln('| Сессия | ${p.sessionSkipped ? 'пропущена' : 'пройдена'} |');
  b.writeln('| Запросов | ${p.queries.length} |');
  b.writeln();
  for (final q in p.queries) {
    b.writeln('- Запрос: ${_md(q)}');
  }
  b.writeln();

  b.writeln('## LLM');
  b.writeln();
  b.writeln('- Вызовов: ${result.llm.calls}');
  b.writeln('- Входных токенов: ${result.llm.inputTokens}');
  b.writeln('- Выходных токенов: ${result.llm.outputTokens}');
  b.writeln();
  if (result.llm.callsByKind.isNotEmpty) {
    b.writeln('| Вид промпта | Вызовов |');
    b.writeln('| --- | --- |');
    for (final key in result.llm.callsByKind.keys.toList()..sort()) {
      b.writeln('| $key | ${result.llm.callsByKind[key]} |');
    }
    b.writeln();
  }

  b.writeln('## Quality checks');
  b.writeln();
  final s = result.summary;
  b.writeln('- Всего: ${s.total} (fail=${s.fail}, warn=${s.warn}, info=${s.info})');
  b.writeln();
  if (result.checks.isEmpty) {
    b.writeln('Нарушений нет.');
    b.writeln();
  } else {
    b.writeln('| Severity | Код | Узел | Сообщение |');
    b.writeln('| --- | --- | --- | --- |');
    for (final c in result.checks) {
      b.writeln('| ${c.severity.name} | ${c.code} | '
          '${c.nodeId ?? '—'} | ${_clip(c.message, 160)} |');
    }
    b.writeln();
  }

  for (final o in result.outcomes) {
    b.writeln('## Запрос: ${_md(o.query)}');
    b.writeln();
    b.writeln('Тема `${o.topicId}`, корень `${o.rootId}`.');
    b.writeln();
    if (o.notes.isNotEmpty) {
      b.writeln('Замечания по прогону:');
      b.writeln();
      for (final n in o.notes) {
        b.writeln('- $n');
      }
      b.writeln();
    }

    b.writeln('### Дерево знаний (${o.nodes.length} узлов)');
    b.writeln();
    b.writeln('| Уровень | Узел | Подпись | one_liner | Контент |');
    b.writeln('| --- | --- | --- | --- | --- |');
    for (final n in sortNodesForReport(o.nodes)) {
      b.writeln('| ${n.level} | `${_clip(n.id, 28)}` | ${_md(n.label)} | '
          '${_clip(n.oneLiner, 90)} | ${n.contentLoaded ? 'да' : 'нет'} |');
    }
    b.writeln();

    final detailed = [
      for (final n in sortNodesForReport(o.nodes))
        if (n.contentLoaded) n,
    ];
    if (detailed.isNotEmpty) {
      b.writeln('#### Контент узлов');
      b.writeln();
      for (final n in detailed) {
        b.writeln('- **${_md(n.label)}** (`${_clip(n.id, 28)}`, уровень ${n.level})');
        b.writeln('  - one_liner: ${_clip(n.oneLiner, 200)}');
        if (n.details.isNotEmpty) {
          b.writeln('  - details: ${_clip(n.details, 400)}');
        }
        if (n.analogy != null && n.analogy!.isNotEmpty) {
          b.writeln('  - аналогия: ${_clip(n.analogy!, 200)}');
        }
        if (n.relations.isNotEmpty) {
          b.writeln('  - связи: ${n.relations.map((r) => '${r.from} -${r.type.raw}-> ${r.to}').join('; ')}');
        }
      }
      b.writeln();
    }

    final cur = o.curriculum;
    if (cur != null) {
      b.writeln('### Учебный план (${cur.items.length} пунктов, '
          '${cur.totalEstimatedMinutes} мин)');
      b.writeln();
      b.writeln('| # | Узел | Тип | Статус | Мин | Приоритет | Причина |');
      b.writeln('| --- | --- | --- | --- | --- | --- | --- |');
      for (final i in cur.items) {
        b.writeln('| ${i.order} | `${_clip(i.nodeId, 28)}` | ${i.type.name} | '
            '${i.status.name} | ${i.estimatedMinutes} | ${_fmt(i.priority)} | '
            '${_clip(i.reason ?? '—', 60)} |');
      }
      b.writeln();
      if (o.alreadyKnown.isNotEmpty) {
        b.writeln('Уже известно: ${o.alreadyKnown.map(_clipWith28).join(', ')}');
        b.writeln();
      }
    }

    if (o.diagnosticQuestions.isNotEmpty) {
      b.writeln('### Диагностика (${o.diagnosticQuestions.length} вопросов)');
      b.writeln();
      for (final q in o.diagnosticQuestions) {
        b.writeln('- **${q.id}** (${_clip(q.nodeId, 28)}): ${_clip(q.question, 140)}');
        for (var i = 0; i < q.options.length; i++) {
          final mark = i == q.correctIndex ? '✓' : ' ';
          b.writeln('  $mark ${_clip(q.options[i], 90)}');
        }
      }
      b.writeln();
      if (o.diagnosticResult != null) {
        final dr = o.diagnosticResult!;
        b.writeln('Итог: уровень `${dr.currentLevel}`, score ${_fmt(dr.score)}, '
            'известно ${dr.knownConcepts.length}, не известно ${dr.unknownConcepts.length}.');
        b.writeln();
      }
    }

    final act = o.activity;
    if (act != null && act.steps.isNotEmpty) {
      b.writeln('### Активность (${act.nodeLabel})');
      b.writeln();
      b.writeln('Шагов: ${act.steps.length}, текущий: '
          '${act.currentStep < 0 ? '—' : act.currentStep}, завершена: ${act.isComplete ? 'да' : 'нет'}.');
      b.writeln();
      for (final s in act.steps) {
        b.writeln('#### ${s.type} — ${_md(s.title)} '
            '(${s.status}${s.correct == null ? '' : (s.correct! ? ', верно' : ', ошибка')})');
        if (s.body != null && s.body!.trim().isNotEmpty) {
          b.writeln('- body: ${_clip(s.body!, 300)}');
        }
        if (s.instruction != null && s.instruction!.trim().isNotEmpty) {
          b.writeln('- instruction: ${_clip(s.instruction!, 300)}');
        }
        if (s.options != null && s.options!.isNotEmpty) {
          for (var i = 0; i < s.options!.length; i++) {
            final mark = i == s.correctIndex ? '✓' : ' ';
            b.writeln('  $mark ${_clip(s.options![i], 90)}');
          }
        }
        if (s.userAnswer != null && s.userAnswer!.isNotEmpty) {
          b.writeln('- ответ ученика: ${_clip(s.userAnswer!, 200)}');
        }
        if (s.bestAnswer != null && s.bestAnswer!.isNotEmpty) {
          b.writeln('- образец ответа: ${_clip(s.bestAnswer!, 300)}');
        }
        if (s.feedback != null && s.feedback!.isNotEmpty) {
          b.writeln('- фидбек: ${_clip(s.feedback!, 200)}');
        }
        b.writeln();
      }
    }

    if (o.answers.isNotEmpty) {
      b.writeln('### Ответы пользователя');
      b.writeln();
      b.writeln('| Узел | Шаг | Ответ | Верно | Обратная связь |');
      b.writeln('| --- | --- | --- | --- | --- |');
      for (final a in o.answers) {
        b.writeln('| ${_md(a.nodeLabel)} | ${a.stepType} | '
            '${_clip(a.userAnswer, 60)} | ${a.correct == null ? '—' : (a.correct! ? 'да' : 'нет')} | '
            '${_clip(a.feedback, 90)} |');
      }
      b.writeln();
    }

    final miscon = [
      for (final a in o.answers)
        if (a.misconception.isNotEmpty) a,
    ];
    if (miscon.isNotEmpty) {
      b.writeln('### Мисконцепции (${miscon.length})');
      b.writeln();
      for (final a in miscon) {
        b.writeln('- **${_md(a.nodeLabel)}**: ${_clip(a.misconception, 200)}');
      }
      b.writeln();
    }

    if (o.assessmentQuestions.isNotEmpty) {
      b.writeln('### Итоговая оценка (${o.assessmentQuestions.length} вопросов)');
      b.writeln();
      b.writeln('| # | Тип | Узел | Вопрос |');
      b.writeln('| --- | --- | --- | --- |');
      for (final q in o.assessmentQuestions) {
        b.writeln('| ${q.id} | ${q.type.wire} | `${_clip(q.nodeId, 28)}` | '
            '${_clip(q.question, 110)} |');
      }
      if (o.assessment?.score != null) {
        b.writeln();
        b.writeln('Score: ${_fmt(o.assessment!.score!)}');
      }
      b.writeln();
    }

    b.writeln('### Мастерство');
    b.writeln();
    final before = o.masteryBefore;
    final after = o.masteryAfter;
    b.writeln('| Момент | Уровень | Score | Цель достигнута | Пробелы |');
    b.writeln('| --- | --- | --- | --- | --- |');
    if (before != null) {
      b.writeln('| до | ${before.newLevel.name} | ${_fmt(before.score)} | '
          '${before.reachedTarget ? 'да' : 'нет'} | ${before.gaps.length} |');
    }
    if (after != null) {
      b.writeln('| после | ${after.newLevel.name} | ${_fmt(after.score)} | '
          '${after.reachedTarget ? 'да' : 'нет'} | ${after.gaps.length} |');
    }
    b.writeln();
    final concepts = o.masteryConcepts?.concepts ?? const [];
    if (concepts.isNotEmpty) {
      b.writeln('| Узел | understanding | recall | application | transfer | Мисконцепция |');
      b.writeln('| --- | --- | --- | --- | --- | --- |');
      for (final c in concepts) {
        final mis = c.misconception;
        b.writeln('| `${_clip(c.nodeId, 28)}` | ${_fmt(c.understanding)} | '
            '${_fmt(c.recall)} | ${_fmt(c.application)} | ${_fmt(c.transfer)} | '
            '${mis == null ? '—' : _clip(mis['type']?.toString() ?? 'есть', 40)} |');
      }
      b.writeln();
    }

    if (o.milestones.isNotEmpty) {
      b.writeln('### Milestones (${o.milestones.length})');
      b.writeln();
      b.writeln('| Уровень | Название | Часов | Статус | Альтернативные пути |');
      b.writeln('| --- | --- | --- | --- | --- |');
      for (final m in o.milestones) {
        final alts = m.alternativePaths.map((a) => a.title).join('; ');
        b.writeln('| ${m.level} | ${_md(m.title)} | ${_fmt(m.estimatedHours, digits: 1)} | '
            '${m.status.name} | ${_clip(alts.isEmpty ? '—' : alts, 70)} |');
      }
      b.writeln();
    }
  }

  return b.toString();
}

String _clipWith28(String id) => _clip(id, 28);

/// Недетерминированные данные прогона — только в `run-stats.json`.
String renderRunStats(RunStats stats) {
  final data = <String, dynamic>{'schema': 'mindtree.probe.run-stats/v1'};
  data.addAll(stats.toJson());
  return '${const JsonEncoder.withIndent('  ').convert(data)}\n';
}

/// Собирает [QualityInput] из результата — для повторного прогона проверок
/// и для тестов отчёта.
QualityInput buildQualityInput(ProbeResult result) => QualityInput(
      nodes: [for (final o in result.outcomes) ...o.nodes],
      targetLevel: result.params.level,
      goal: result.params.goal,
      recallSteps: result.recallSteps,
      applySteps: result.applySteps,
      activities: [
        for (final o in result.outcomes)
          if (o.activity != null) o.activity!,
      ],
      diagnosticQuestions: [
        for (final o in result.outcomes) ...o.diagnosticQuestions,
      ],
      assessmentQuestions: [
        for (final o in result.outcomes) ...o.assessmentQuestions,
      ],
      curriculumNodeIds: [
        for (final o in result.outcomes)
          for (final i in o.curriculum?.items ?? const <Never>[]) i.nodeId,
      ],
    );
