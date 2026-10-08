import 'package:flutter/material.dart';

import '../../domain/models/models.dart';
import '../theme/app_theme.dart';
import 'badge.dart';
import 'formatted_text.dart';

/// Разбор ответа в тестах (quiz и итоговый).
///
/// Повторяет структуру разбора в сессии (`session_screen._buildFeedback`):
/// сначала бейдж вердикта, затем — эталон ответа отдельным блоком. Рубрика
/// (`explanation`) сознательно НЕ показывается до ответа: она содержит
/// ключевые элементы и спойлерит открытый вопрос.
///
/// Что показывается при неверном ответе:
/// * непустой `referenceAnswer` → «Эталонный ответ» (полный образец);
/// * закрытый вопрос без эталона → «Правильный ответ: …» (текст варианта);
/// * открытый вопрос без эталона → рубрика с заголовком
///   «Как надо было ответить».
class AnswerReview extends StatelessWidget {
  final bool correct;
  final AssessmentQuestion question;

  const AnswerReview({
    super.key,
    required this.correct,
    required this.question,
  });

  bool get _hasOptions => question.options != null && question.options!.isNotEmpty;

  /// Текст правильного варианта закрытого вопроса; вне диапазона — сам индекс.
  String? get _closedAnswer {
    final raw = (question.correctAnswer ?? '').trim();
    if (raw.isEmpty) return null;
    if (!_hasOptions) return raw;
    final idx = int.tryParse(raw);
    final options = question.options!;
    if (idx == null || idx < 0 || idx >= options.length) return raw;
    return options[idx];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rubric = (question.explanation ?? '').trim();
    final reference = question.referenceAnswer.trim();

    if (correct) {
      // Краткий позитив: проверка уже пройдена, разбирать нечего.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const StatusBadge('Верно', variant: BadgeVariant.success),
          const SizedBox(height: 12),
          Text(
            'Так и есть — ответ засчитан.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.ok,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }

    final children = <Widget>[
      const StatusBadge('Неверно', variant: BadgeVariant.danger),
    ];

    // Рубрика уже заняла место разбора — вторым блоком её не дублируем.
    var rubricUsedAsAnswer = false;

    if (reference.isNotEmpty) {
      children.add(const SizedBox(height: 12));
      children.add(_block(context, 'Эталонный ответ', reference));
    } else if (_hasOptions && _closedAnswer != null) {
      children.add(const SizedBox(height: 12));
      children.add(
        Container(
          padding: const EdgeInsets.all(12),
          decoration: _decoration(context),
          child: Text(
            'Правильный ответ: ${_closedAnswer!}',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    } else if (rubric.isNotEmpty) {
      children.add(const SizedBox(height: 12));
      children.add(_block(context, 'Как надо было ответить', rubric));
      rubricUsedAsAnswer = true;
    }

    // Рубрика рядом с эталоном: показывает, по каким критериям проверяли.
    if (rubric.isNotEmpty && !rubricUsedAsAnswer) {
      children.add(const SizedBox(height: 12));
      children.add(_block(context, 'Критерии проверки', rubric));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  Widget _block(BuildContext context, String title, String body) => Container(
        padding: const EdgeInsets.all(12),
        decoration: _decoration(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.textMuted(context),
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 4),
            FormattedText(body),
          ],
        ),
      );

  BoxDecoration _decoration(BuildContext context) => BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      );
}
