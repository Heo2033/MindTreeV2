import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mindtree_flutter/config/provider_config_service.dart';
import 'package:mindtree_flutter/providers/app_providers.dart';
import 'package:mindtree_flutter/ui/widgets/badge.dart';
import 'package:mindtree_flutter/ui/widgets/button.dart';
import 'package:mindtree_flutter/ui/widgets/error_banner.dart';
import 'package:mindtree_flutter/ui/widgets/inputs.dart';
import 'package:mindtree_flutter/ui/widgets/spinner.dart';

/// Form for configuring the LLM provider at runtime.
///
/// Works only when the app is built with `PROVIDER_MODE=configurable`
/// (see `tool/gen_config.ps1 -Configurable`); in hardcoded mode edits are
/// still persisted but `ProviderConfigService.load()` ignores them.
class ProviderConfigScreen extends ConsumerStatefulWidget {
  const ProviderConfigScreen({super.key});

  @override
  ConsumerState<ProviderConfigScreen> createState() =>
      _ProviderConfigScreenState();
}

class _ProviderConfigScreenState extends ConsumerState<ProviderConfigScreen> {
  final _baseUrl = TextEditingController();
  final _model = TextEditingController();
  final _modelStrong = TextEditingController();
  final _modelStrongFallback = TextEditingController();
  final _modelFast = TextEditingController();
  final _apiKey = TextEditingController();
  String _provider = 'auto';
  final _temperature = TextEditingController();
  final _numCtx = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _baseUrl.dispose();
    _model.dispose();
    _modelStrong.dispose();
    _modelStrongFallback.dispose();
    _modelFast.dispose();
    _apiKey.dispose();
    _temperature.dispose();
    _numCtx.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    try {
      final body = RuntimeConfigBody(
        provider: _provider,
        baseUrl: _baseUrl.text.trim(),
        apiKey: _apiKey.text,
        model: _model.text.trim(),
        modelStrong: _modelStrong.text.trim(),
        modelStrongFallback: _modelStrongFallback.text.trim(),
        modelFast: _modelFast.text.trim(),
        temperature: double.tryParse(_temperature.text.trim()),
        numCtx: int.tryParse(_numCtx.text.trim()),
      );
      await ref.read(providerConfigServiceProvider).apply(body);
      ref.invalidate(effectiveConfigProvider);
      ref.invalidate(initAppProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Настройки сохранены')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _reset() async {
    try {
      await ref.read(providerConfigServiceProvider).clear();
      ref.invalidate(effectiveConfigProvider);
      ref.invalidate(initAppProvider);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfg = ref.watch(effectiveConfigProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Настройки провайдера'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
      ),
      body: cfg.when(
        loading: () => const Center(child: Loader()),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(24),
          child: ErrorBanner(message: 'Не удалось загрузить конфигурацию: $e'),
        ),
        data: (ec) {
          // (Re)seed the form controllers on first build / when config
          // changes externally.
          final seedKey = '${ec.baseUrl}|${ec.model}|${ec.runtimeConfigured}';
          if (_lastSeed != seedKey) {
            _lastSeed = seedKey;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _baseUrl.text = ec.baseUrl;
                _model.text = ec.model;
                _modelStrong.text = ec.modelStrong;
                _modelStrongFallback.text = ec.modelStrongFallback;
                _modelFast.text = ec.modelFast;
                _apiKey.text = ec.apiKey ?? '';
                _temperature.text = ec.temperature.toString();
                _numCtx.text = ec.numCtx.toString();
                setState(() => _provider = ec.provider);
              }
            });
          }
          final editable = ref
              .read(providerConfigServiceProvider)
              .isConfigurable;
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Row(
                children: [
                  StatusBadge(
                    editable
                        ? 'Редактируемая конфигурация'
                        : 'Жёстко задана при сборке (hardcoded)',
                    variant: editable ? BadgeVariant.success : BadgeVariant.muted,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              AppSelect(
                label: 'Провайдер',
                value: _provider,
                onChanged: (v) =>
                    setState(() => _provider = v ?? _provider),
                options: const [
                  (value: 'auto', label: 'Авто'),
                  (value: 'openai', label: 'OpenAI'),
                  (value: 'ollama', label: 'Ollama'),
                ],
              ),
              const SizedBox(height: 16),
              AppInput(label: 'Base URL', controller: _baseUrl),
              const SizedBox(height: 16),
              AppInput(label: 'Модель', controller: _model),
              const SizedBox(height: 16),
              AppInput(
                label: 'Модель (strong)',
                controller: _modelStrong,
                hint: 'Для сложных операций (структура, диагностика и т.п.)',
              ),
              const SizedBox(height: 16),
              AppInput(
                label: 'Модель (strong fallback)',
                controller: _modelStrongFallback,
                hint: 'Используется, если strong-модель недоступна',
              ),
              const SizedBox(height: 16),
              AppInput(
                label: 'Модель (fast)',
                controller: _modelFast,
                hint: 'Для лёгких операций',
              ),
              const SizedBox(height: 16),
              AppInput(
                label: 'API-ключ',
                controller: _apiKey,
                obscureText: true,
                hint: 'Оставляется пустым, если задан при сборке',
              ),
              const SizedBox(height: 16),
              AppInput(
                label: 'Температура',
                controller: _temperature,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 16),
              AppInput(
                label: 'Контекст (токенов)',
                controller: _numCtx,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 24),
              AppButton(
                'Сохранить',
                size: AppButtonSize.lg,
                fullWidth: true,
                busy: _saving,
                onPressed: _save,
              ),
              const SizedBox(height: 12),
              AppButton(
                'Сбросить к значениям по умолчанию',
                variant: AppButtonVariant.secondary,
                fullWidth: true,
                onPressed: _reset,
              ),
            ],
          );
        },
      ),
    );
  }

  String _lastSeed = '';
}