import 'package:flutter/material.dart';

import 'button.dart';
import 'inputs.dart';

/// Пресеты времени сессии: короткая разминка и часовые блоки.
const List<int> timeBudgetPresets = [15, 30, 45, 60, 90, 120];

/// Минимальный и максимальный бюджет сессии в минутах (для «Другое»).
const int timeBudgetMin = 5;
const int timeBudgetMax = 600;

/// Подпись минут: до часа — «45 мин», час и больше — «1 ч 30 мин».
String formatTimeBudget(int m) {
  if (m < 60) return '$m мин';
  final h = m ~/ 60;
  final rest = m % 60;
  return rest == 0 ? '$h ч' : '$h ч $rest мин';
}

/// Выбор бюджета времени: пресеты-чипы или «Другое» с числовым вводом.
///
/// Состояние (выбранное значение, режим «Другое», контроллер) живёт у
/// вызывающего: сюда передаётся всё готовым, как у любого контролируемого
/// поля. [valid] управляет текстом ошибки — диапазон [timeBudgetMin]…
/// [timeBudgetMax].
class TimeBudgetField extends StatelessWidget {
  final List<int> presets;
  final int minutes;
  final bool custom;
  final TextEditingController customController;
  final bool valid;
  final ValueChanged<int> onPreset;
  final ValueChanged<bool> onCustom;
  final ValueChanged<String> onCustomText;

  const TimeBudgetField({
    super.key,
    required this.presets,
    required this.minutes,
    required this.custom,
    required this.customController,
    required this.valid,
    required this.onPreset,
    required this.onCustom,
    required this.onCustomText,
  });

  @override
  Widget build(BuildContext context) {
    return AppField(
      label: 'Сколько времени есть',
      hint: 'План подстроится под бюджет.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in presets)
                ChoiceChip(
                  selected: !custom && minutes == m,
                  onSelected: (_) => onPreset(m),
                  label: Text(formatTimeBudget(m)),
                  visualDensity: VisualDensity.compact,
                ),
              ChoiceChip(
                selected: custom,
                onSelected: onCustom,
                label: const Text('Другое'),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          if (custom) ...[
            const SizedBox(height: 12),
            AppInput(
              label: 'Минут',
              controller: customController,
              keyboardType: TextInputType.number,
              onChanged: onCustomText,
              errorText: valid
                  ? null
                  : 'Введите целое число минут в допустимом диапазоне',
            ),
          ],
        ],
      ),
    );
  }
}

/// Модальный выбор времени на входе в сессию/веху: «Сколько времени у тебя
/// есть?». Возвращает выбранные минуты либо `null`, если пользователь отменил
/// (закрыл подложку или нажал «Отмена») — тогда сессию не запускают.
Future<int?> showTimeBudgetPicker(BuildContext context, {int initial = 30}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _TimeBudgetSheet(initial: initial),
  );
}

/// Содержимое bottom sheet: заголовок, [TimeBudgetField] и действия.
class _TimeBudgetSheet extends StatefulWidget {
  final int initial;

  const _TimeBudgetSheet({required this.initial});

  @override
  State<_TimeBudgetSheet> createState() => _TimeBudgetSheetState();
}

class _TimeBudgetSheetState extends State<_TimeBudgetSheet> {
  late final TextEditingController _controller;
  late int _minutes;
  late bool _custom;

  @override
  void initState() {
    super.initState();
    _minutes = widget.initial;
    _custom = !timeBudgetPresets.contains(widget.initial);
    // Стартовое значение в поле: если уйдём в «Другое», там уже будет валидное
    // число, а не пустая строка с ошибкой.
    _controller = TextEditingController(text: '${widget.initial}');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Число из поля «Другое» в допустимом диапазоне.
  bool get _customValid {
    final v = int.tryParse(_controller.text.trim());
    return v != null && v >= timeBudgetMin && v <= timeBudgetMax;
  }

  bool get _valid => _custom ? _customValid : true;

  int get _value =>
      _custom ? int.tryParse(_controller.text.trim()) ?? 0 : _minutes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 8,
          bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Сколько времени у тебя есть?',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'От этого зависит, сколько плана влезет в сессию: '
              'короткий путь до цели, а не бесконечный список тем.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            TimeBudgetField(
              presets: timeBudgetPresets,
              minutes: _minutes,
              custom: _custom,
              customController: _controller,
              valid: !_custom || _customValid,
              onPreset: (m) => setState(() {
                _custom = false;
                _minutes = m;
              }),
              onCustom: (v) => setState(() => _custom = v),
              onCustomText: (_) => setState(() {}),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    'Отмена',
                    fullWidth: true,
                    variant: AppButtonVariant.secondary,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppButton(
                    'Начать',
                    fullWidth: true,
                    onPressed: _valid
                        ? () => Navigator.of(context).pop(_value)
                        : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
