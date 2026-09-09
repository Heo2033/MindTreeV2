import 'dart:math';

import '../models/models.dart';
import '../../data/llm/scheduler.dart';
import '../../data/llm/client.dart';
import '../../data/database/mindtree_repository.dart';

// ─── Prompt constants ─────────────────────────────────────────────────────────

const _noMetaRule =
    '- В значениях полей пиши только готовый контент по теме. '
    'Запрещены служебные фразы о своих действиях и решениях '
    '(«Узел помечен как…», «Переименовал узел…», '
    '«Этот узел не требует дочерних…», «Исправлено…»).';

const _alphabetRule =
    '- Используй только кириллицу, латиницу, цифры и обычную пунктуацию. '
    'Запрещены иероглифы и знаки других письменностей (китайские, японские, корейские).\n'
    '- Все label, title, one_liner, details — только на русском языке. '
    'Не используй непереведенные английские термины в текстовых полях.\n'
    '  Исключение: устоявшиеся аббревиатуры и названия моделей/алгоритмов, '
    'которые используются на английском в профессиональном сообществе '
    '(U-Net, DDPM, VAE, CLIP, Stable Diffusion, ControlNet, DALL-E, DiT, '
    'NeRF, DDIM, LoRA, EMA, BERT, GPT, ResNet, GAN, RAG, Adam, SGD, '
    'ReLU, softmax и т.п.). Всё остальное переводи:\n'
    '    "Machine learning" → "Машинное обучение"\n'
    '    "Neural network" → "Нейронная сеть"\n'
    '    "Gradient descent" → "Градиентный спуск"\n'
    '    "Overfitting" → "Переобучение"\n'
    '    "Convolutional layers" → "Свёрточные слои"\n'
    '    "Gradient clipping" → "Обрезка градиентов"';

const _promptMilestone = '''
# Роль
Ты — навигатор по обучению. Составь карту уровней и направлений для темы.

# Контекст
Тема: "{{topic}}"
Текущий уровень: {{current_level}}
Цель пользователя: {{goal}}

# Задача
Составь последовательность milestones (уровней освоения) от текущего к более глубоким. Укажи для каждого:
- title — понятное название уровня
- description — что пользователь сможет делать
- capabilities — конкретные умения (2–5)
- estimated_hours — примерные часы
- alternative_paths — какие направления развиваются дальше

Базовая шкала уровней (адаптируй под тему):
awareness → basic_understanding → solid_understanding → practical_application → advanced → expert

# Формат ответа
Строгий JSON-объект:
{"milestones":[{"id":"m1","level":"solid_understanding","title":"Твёрдое понимание","description":"...","capabilities":["...","..."],"estimated_hours":2,"alternative_paths":[{"id":"m2","title":"Применение","estimated_hours":4,"description":"..."}]}]}

Отсортируй milestones от текущего к более глубоким. alternative_paths указывают ветвление после данного уровня.

$_noMetaRule
$_alphabetRule

# Язык
Отвечай СТРОГО на русском языке. Все текстовые поля — на русском.

Никакого текста вне JSON. Без ```json и без пояснений.''';

// ─── LLM parse types ─────────────────────────────────────────────────────────

class MilestoneAlternativePathResult {
  final String id;
  final String title;
  final double estimatedHours;
  final String description;

  const MilestoneAlternativePathResult({
    required this.id,
    required this.title,
    required this.estimatedHours,
    required this.description,
  });
}

class MilestoneResultItem {
  final String id;
  final String level;
  final String title;
  final String description;
  final List<String> capabilities;
  final double estimatedHours;
  final List<MilestoneAlternativePathResult> alternativePaths;

  const MilestoneResultItem({
    required this.id,
    required this.level,
    required this.title,
    required this.description,
    required this.capabilities,
    required this.estimatedHours,
    required this.alternativePaths,
  });
}

class MilestoneLlmResult {
  final List<MilestoneResultItem> milestones;
  const MilestoneLlmResult({required this.milestones});
}

MilestoneLlmResult parseMilestoneResult(dynamic data) {
  final obj = (data is Map<String, dynamic>) ? data : <String, dynamic>{};
  final rawMilestones = obj['milestones'];
  if (rawMilestones is! List) return const MilestoneLlmResult(milestones: []);

  final milestones = rawMilestones.map((m) {
    final rawAlt = m['alternative_paths'];
    final alt = rawAlt is List
        ? rawAlt
            .map((a) => MilestoneAlternativePathResult(
                  id: a['id']?.toString() ?? '',
                  title: a['title']?.toString() ?? '',
                  estimatedHours: a['estimated_hours'] is num
                      ? (a['estimated_hours'] as num).toDouble()
                      : 1.0,
                  description: a['description']?.toString() ?? '',
                ))
            .toList()
        : <MilestoneAlternativePathResult>[];

    final rawCaps = m['capabilities'];
    final caps = rawCaps is List
        ? rawCaps.whereType<String>().toList()
        : <String>[];

    return MilestoneResultItem(
      id: m['id']?.toString() ?? '',
      level: m['level']?.toString() ?? '',
      title: m['title']?.toString() ?? '',
      description: m['description']?.toString() ?? '',
      capabilities: caps,
      estimatedHours: m['estimated_hours'] is num
          ? (m['estimated_hours'] as num).toDouble()
          : 1.0,
      alternativePaths: alt,
    );
  }).toList();

  return MilestoneLlmResult(milestones: milestones);
}

// ─── MilestoneEngine ──────────────────────────────────────────────────────────

class MilestoneEngine {
  final MindtreeRepository repo;
  final TreeScheduler scheduler;
  final Random _random = Random();

  MilestoneEngine({required this.repo, required this.scheduler});

  String _shortId() {
    final ts = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final rnd = _random.nextInt(0xFFFFFF).toRadixString(36).padLeft(6, '0');
    return (ts.substring(max(0, ts.length - 8)) + rnd).substring(0, 8);
  }

  /// Build learning milestones for a journey, persisted via repository.
  Future<List<LearningMilestone>> generate(String journeyId, String topicId) async {
    final topic = await repo.getTopic(topicId);
    final model = await repo.getLearnerModel(topicId);
    final currentLevel = model?.overallLevel ?? MasteryLevel.awareness;

    List<MilestoneResultItem> milestones;
    try {
      final prompt = _promptMilestone
          .replaceAll('{{topic}}', topic?.name ?? '')
          .replaceAll('{{current_level}}', currentLevel.raw)
          .replaceAll('{{goal}}', topic?.goal.raw ?? '');

      final res = await scheduler.execute<MilestoneLlmResult>(
        'milestone',
        () => prompt,
        (raw) => parseMilestoneResult(parseLLMJson(raw)),
      );
      milestones = res.result.milestones;
    } catch (_) {
      milestones = fallbackMilestones(currentLevel);
    }

    final persisted = milestones.map((m) {
      final id = 'ms_${_shortId()}';
      final level = MasteryLevel.fromString(m.level);
      final status = level == currentLevel
          ? MilestoneStatus.active
          : MilestoneStatus.notStarted;

      return LearningMilestone(
        id: id,
        level: level,
        title: m.title,
        description: m.description,
        capabilities: m.capabilities,
        estimatedHours: m.estimatedHours,
        status: status,
        alternativePaths: m.alternativePaths
            .map((a) => LearningPath(
                  id: a.id,
                  title: a.title,
                  estimatedHours: a.estimatedHours,
                  description: a.description,
                ))
            .toList(),
      );
    }).toList();

    await repo.insertMilestones(persisted);
    return persisted;
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

List<MilestoneResultItem> fallbackMilestones(MasteryLevel currentLevel) {
  final startIdx = max(0, MasteryLevel.order.indexOf(currentLevel));
  return MasteryLevel.order.sublist(startIdx).map((level) {
    final idx = MasteryLevel.order.indexOf(level) - startIdx;
    return MilestoneResultItem(
      id: 'ms_fallback_$idx',
      level: level.raw,
      title: _beautifulTitle(level),
      description: 'Достижение уровня ${_beautifulTitle(level)}',
      capabilities: const [],
      estimatedHours: 2 + idx * 2,
      alternativePaths: const [],
    );
  }).toList();
}

String _beautifulTitle(MasteryLevel level) {
  switch (level) {
    case MasteryLevel.awareness:
      return 'Знакомство';
    case MasteryLevel.basicUnderstanding:
      return 'Базовое понимание';
    case MasteryLevel.solidUnderstanding:
      return 'Твёрдое понимание';
    case MasteryLevel.practicalApplication:
      return 'Практическое применение';
    case MasteryLevel.advanced:
      return 'Продвинутый';
    case MasteryLevel.expert:
      return 'Эксперт';
  }
}
