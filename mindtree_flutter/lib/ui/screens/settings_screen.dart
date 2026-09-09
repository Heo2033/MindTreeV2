import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/app_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/badge.dart';
import '../widgets/button.dart';
import '../widgets/error_banner.dart';
import '../widgets/spinner.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = ref.watch(effectiveConfigProvider);
    final runtime = ref.watch(llmConfigStateProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Настройки'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: cfg.when(
            loading: () => const Center(child: Loader()),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(24),
              child: ErrorBanner(message: 'Не удалось загрузить конфигурацию: $e'),
            ),
            data: (ec) => ListView(
              padding: const EdgeInsets.all(24),
              children: [
                StatusBadge(
                  'Runtime ${ec.runtimeConfigured ? 'настроен' : 'по умолчанию'}',
                  variant: ec.runtimeConfigured ? BadgeVariant.success : BadgeVariant.muted,
                ),
                const SizedBox(height: 16),
                _row(context, 'Провайдер', ec.provider),
                _row(context, 'Base URL', ec.baseUrl.isEmpty ? '—' : ec.baseUrl),
                _row(context, 'Модель', ec.model),
                _row(context, 'Модель (strong)', ec.modelStrong.isEmpty ? '—' : ec.modelStrong),
                _row(context, 'Модель (fast)', ec.modelFast.isEmpty ? '—' : ec.modelFast),
                _row(context, 'Температура', ec.temperature.toString()),
                _row(context, 'Контекст', '${ec.numCtx} токенов'),
                _row(context, 'API-ключ', _maskKey(ec.apiKey)),
                const Divider(height: 32),
                if (runtime != null)
                  _row(context, 'Активный (scheduler)', runtime.model),
                const SizedBox(height: 24),
                AppButton(
                  'На главную',
                  variant: AppButtonVariant.secondary,
                  fullWidth: true,
                  onPressed: () => context.go('/'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _maskKey(String? key) {
    if (key == null || key.isEmpty) return 'не задан';
    if (key.length <= 8) return '••••••';
    return '${key.substring(0, 4)}••••${key.substring(key.length - 4)}';
  }

  Widget _row(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textMuted(context),
                )),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}