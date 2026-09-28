import 'package:flutter/material.dart';

import '../screens/analytics_screen.dart';
import '../screens/diagnostic_screen.dart';
import '../screens/final_assessment_screen.dart';
import '../screens/focus_screen.dart';
import '../screens/graph_screen.dart';
import '../screens/learner_model_screen.dart';
import '../screens/milestones_screen.dart';
import '../screens/quiz_screen.dart';
import '../screens/review_screen.dart';
import '../screens/session_screen.dart';
import '../screens/tutor_screen.dart';

/// Пункт внутри раздела темы.
class TopicNavItem {
  /// Полный путь внутри shell, например `/topic/learn/focus`.
  final String path;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String description;
  final Widget Function(String topicId) builder;

  const TopicNavItem({
    required this.path,
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.description,
    required this.builder,
  });
}

/// Раздел темы верхнего уровня — одна ветка `StatefulShellRoute`.
class TopicSectionDef {
  final String label;
  final String description;
  final IconData icon;
  final IconData selectedIcon;
  final List<TopicNavItem> items;
  final String? landingPath;

  const TopicSectionDef({
    required this.label,
    required this.description,
    required this.icon,
    required this.selectedIcon,
    this.items = const [],
    this.landingPath,
  });

  /// Нужен ли ряд переключения внутри раздела (больше одного пункта).
  bool get hasSubNav => items.length > 1;
}

/// Три рабочих раздела темы. Граф намеренно не в топе: он внутри «Учить».
final List<TopicSectionDef> kTopicSections = [
  TopicSectionDef(
    label: 'Учить',
    description: 'Фокус, учебная сессия, граф и репетитор',
    icon: Icons.school_outlined,
    selectedIcon: Icons.school,
    items: [
      TopicNavItem(
        path: '/topic/learn/focus',
        label: 'Фокус',
        icon: Icons.center_focus_weak,
        selectedIcon: Icons.center_focus_strong,
        description: 'Одно понятие за раз, с повторением',
        builder: (topicId) => FocusScreen(topicId: topicId),
      ),
      TopicNavItem(
        path: '/topic/learn/session',
        label: 'Сессия',
        icon: Icons.play_circle_outline,
        selectedIcon: Icons.play_circle,
        description: 'Активная учебная сессия по плану',
        builder: (topicId) => SessionScreen(topicId: topicId),
      ),
      TopicNavItem(
        path: '/topic/learn/graph',
        label: 'Граф',
        icon: Icons.account_tree_outlined,
        selectedIcon: Icons.account_tree,
        description: 'Дерево знаний: структура и связи',
        builder: (topicId) => GraphScreen(topicId: topicId),
      ),
      TopicNavItem(
        path: '/topic/learn/tutor',
        label: 'Репетитор',
        icon: Icons.support_agent_outlined,
        selectedIcon: Icons.support_agent,
        description: 'Разбор вопросов и мисконцепций',
        builder: (topicId) => TutorScreen(topicId: topicId),
      ),
    ],
  ),
  TopicSectionDef(
    label: 'Проверить',
    description: 'Диагностика, тесты и итоговая оценка',
    icon: Icons.assignment_turned_in_outlined,
    selectedIcon: Icons.assignment_turned_in,
    items: [
      TopicNavItem(
        path: '/topic/check/diagnostic',
        label: 'Диагностика',
        icon: Icons.fact_check_outlined,
        selectedIcon: Icons.fact_check,
        description: 'Что уже знаете — до начала плана',
        builder: (topicId) => DiagnosticScreen(topicId: topicId),
      ),
      TopicNavItem(
        path: '/topic/check/quiz',
        label: 'Тест',
        icon: Icons.quiz_outlined,
        selectedIcon: Icons.quiz,
        description: 'Проверка понимания по теме',
        builder: (topicId) => QuizScreen(topicId: topicId),
      ),
      TopicNavItem(
        path: '/topic/check/final',
        label: 'Итоговый тест',
        icon: Icons.task_alt,
        selectedIcon: Icons.task_alt,
        description: 'Проверка достижения целевого уровня',
        builder: (topicId) => FinalAssessmentScreen(topicId: topicId),
      ),
    ],
  ),
  TopicSectionDef(
    label: 'Прогресс',
    description: 'Путь, повторение, метрики и модель обучения',
    icon: Icons.trending_up,
    selectedIcon: Icons.trending_up,
    items: [
      TopicNavItem(
        path: '/topic/progress/milestones',
        label: 'Путь',
        icon: Icons.flag_outlined,
        selectedIcon: Icons.flag,
        description: 'Следующие вехи обучения',
        builder: (topicId) => MilestonesScreen(topicId: topicId),
      ),
      TopicNavItem(
        path: '/topic/progress/review',
        label: 'Повторение',
        icon: Icons.replay,
        selectedIcon: Icons.replay,
        description: 'Карточки по расписанию SRS',
        builder: (topicId) => ReviewScreen(topicId: topicId),
      ),
      TopicNavItem(
        path: '/topic/progress/analytics',
        label: 'Метрики',
        icon: Icons.insights_outlined,
        selectedIcon: Icons.insights,
        description: 'Прирост понимания и время',
        builder: (topicId) => AnalyticsScreen(topicId: topicId),
      ),
      TopicNavItem(
        path: '/topic/progress/learner',
        label: 'Модель',
        icon: Icons.person_outline,
        selectedIcon: Icons.person,
        description: 'Мастерство и мисконцепции',
        builder: (topicId) => LearnerModelScreen(topicId: topicId),
      ),
    ],
  ),
];

/// Вспомогательный раздел «Ещё» — каталог всех экранов и настроек.
const String kMorePath = '/topic/more';

const TopicSectionDef kMoreSection = TopicSectionDef(
  label: 'Ещё',
  description: 'Все разделы темы и настройки',
  icon: Icons.more_horiz,
  selectedIcon: Icons.more_horiz,
  landingPath: kMorePath,
);

/// Порядок разделов в боковой навигации оболочки темы.
final List<TopicSectionDef> kTopicSectionsWithMore = [
  ...kTopicSections,
  kMoreSection,
];

/// Раздел, содержащий [path]; null — если путь не принадлежит разделам.
TopicSectionDef? sectionForPath(String path) {
  for (final section in kTopicSections) {
    if (section.items.any((i) => i.path == path)) return section;
  }
  return null;
}

/// Раздел по индексу ветки shell; null — если это «Ещё».
TopicSectionDef? sectionForIndex(int index) {
  if (index < 0 || index >= kTopicSections.length) return null;
  return kTopicSections[index];
}

/// Все пункты разделов — полный каталог для экрана «Ещё».
List<TopicNavItem> get kAllTopicItems =>
    [for (final section in kTopicSections) ...section.items];

/// Старые пути (11 вкладок до редизайна навигации) → новые.
const Map<String, String> kLegacyTopicRedirects = {
  '/topic/focus': '/topic/learn/focus',
  '/topic/session': '/topic/learn/session',
  '/topic/graph': '/topic/learn/graph',
  '/topic/tutor': '/topic/learn/tutor',
  '/topic/quiz': '/topic/check/quiz',
  '/topic/diagnostic': '/topic/check/diagnostic',
  '/topic/final': '/topic/check/final',
  '/topic/milestones': '/topic/progress/milestones',
  '/topic/review': '/topic/progress/review',
  '/topic/analytics': '/topic/progress/analytics',
  '/topic/learner': '/topic/progress/learner',
};
