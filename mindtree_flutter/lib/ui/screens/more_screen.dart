import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:mindtree_flutter/ui/nav/topic_nav.dart';

/// Каталог всех экранов темы: страховка навигации, если раздел неочевиден.
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Ещё')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          for (final section in kTopicSections) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    section.label,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    section.description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            for (final item in section.items)
              ListTile(
                leading: Icon(item.icon),
                title: Text(item.label),
                subtitle: Text(item.description),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go(item.path),
              ),
          ],
          const Divider(height: 32),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Настройки провайдера'),
            subtitle: const Text('Модель, ключи и лимиты запросов'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/settings'),
          ),
          ListTile(
            leading: const Icon(Icons.list_alt_outlined),
            title: const Text('К списку тем'),
            subtitle: const Text('Все темы и их состояние'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/'),
          ),
        ],
      ),
    );
  }
}
