import 'package:flutter/material.dart';

import 'package:mindtree_flutter/domain/models/models.dart';
import 'package:mindtree_flutter/providers/ui_stores.dart';
import 'package:mindtree_flutter/ui/labels.dart';

import 'badge.dart';

/// Короткие подписи цели и целевого уровня темы для бейджей шапки.
///
/// `null`, если тема ещё не загружена — тогда бейдж не показывается вовсе,
/// а не висит пустой или с внутренним raw-значением (`deep`, `exam`).
String? goalText(Topic? topic) {
  if (topic == null) return null;
  return goalLabel[topic.goal.raw] ?? topic.goal.raw;
}

String? targetLevelText(Topic? topic) {
  if (topic == null) return null;
  return levelLabel[topic.targetLevel.raw] ?? topic.targetLevel.raw;
}

/// Бейджи «цель / уровень / время» одной строкой.
///
/// Пустые значения пропускаются: экран без темы или без активной сессии
/// показывает только то, что реально известно.
List<Widget> topicMetaBadges({
  String? goal,
  String? level,
  String? time,
}) =>
    [
      if (goal != null && goal.isNotEmpty)
        StatusBadge('Цель: $goal', icon: Icons.flag_outlined),
      if (level != null && level.isNotEmpty)
        StatusBadge('Уровень: $level', icon: Icons.school_outlined),
      if (time != null && time.isNotEmpty)
        StatusBadge(time, icon: Icons.schedule),
    ];

/// Строка времени для шапки: остаток ETA активной сессии темы, иначе
/// остаток бюджета плана, иначе бюджет сессии. `null`, если сессии нет —
/// цель и уровень от этого не зависят.
String? topicTimeLabel(SessionState state, String topicId) {
  final session = state.session ?? state.resumable;
  if (session == null || session.topicId != topicId) return null;
  if (session.status != SessionStatus.active) return null;

  final eta = state.adaptive?.eta;
  if (eta != null && eta.remainingMinutesMax > 0) {
    return '⏱ ${eta.remainingMinutesMin}\u2013${eta.remainingMinutesMax} мин';
  }

  final curriculum = session.curriculum;
  if (curriculum.totalEstimatedMinutes > 0) {
    final done = curriculum.items
        .where((i) => i.status == CurriculumItemStatus.completed)
        .fold<int>(0, (sum, i) => sum + i.estimatedMinutes);
    final left = curriculum.totalEstimatedMinutes - done;
    return '⏱ Осталось ≈ ${left < 0 ? 0 : left} мин';
  }

  if (session.timeBudgetMinutes > 0) {
    return '⏱ Бюджет ${session.timeBudgetMinutes} мин';
  }
  return null;
}

/// Компактная строка бейджей под заголовком экрана темы.
class TopicMetaBar extends StatelessWidget {
  final String? goal;
  final String? level;
  final String? time;
  final EdgeInsetsGeometry padding;

  const TopicMetaBar({
    super.key,
    this.goal,
    this.level,
    this.time,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    final badges = topicMetaBadges(goal: goal, level: level, time: time);
    if (badges.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: padding,
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: badges,
      ),
    );
  }
}
