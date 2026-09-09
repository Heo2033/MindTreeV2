import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/app_providers.dart';
import 'router.dart';
import 'ui/theme/app_theme.dart';
import 'ui/widgets/button.dart';
import 'ui/widgets/spinner.dart';

/// Suppresses the framework defect where a mouse hover hit-test lands on a
/// just-rebuilt `Scaffold` child (e.g. the implicit `_ScaffoldSlot.floatingActionButton`)
/// before layout runs, throwing "Cannot hit test a render box that has never
/// been laid out" / "with no size". Such errors are transient, non-fatal, and
/// trigger on every rebuild while the pointer passes over pending layout.
bool _isTransientHitTestError(FlutterErrorDetails details) {
  final message = details.exceptionAsString();
  return message.contains('Cannot hit test a render box that has never been laid out') ||
      message.contains('Cannot hit test a render box with no size');
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final previousOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    if (_isTransientHitTestError(details)) {
      debugPrint('[mindtree] Ignored transient hit-test error: ${details.exceptionAsString()}');
      return;
    }
    previousOnError?.call(details);
  };
  runApp(const ProviderScope(child: MindTreeApp()));
}

class MindTreeApp extends ConsumerWidget {
  const MindTreeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final init = ref.watch(appInitializedProvider);

    return init.when(
      loading: () => const _BootstrapFrame(child: Center(child: Loader())),
      error: (err, _) => _BootstrapFrame(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Не удалось инициализировать приложение:\n$err',
                textAlign: TextAlign.center,
              ),
            ),
            AppButton(
              'Повторить',
              variant: AppButtonVariant.secondary,
              onPressed: () => ref.invalidate(appInitializedProvider),
            ),
          ],
        ),
      ),
      data: (_) => MaterialApp.router(
        title: 'MindTree',
        debugShowCheckedModeBanner: false,
        theme: lightTheme(),
        darkTheme: darkTheme(),
        themeMode: ThemeMode.system,
        routerConfig: appRouter,
      ),
    );
  }
}

class _BootstrapFrame extends StatelessWidget {
  final Widget child;

  const _BootstrapFrame({required this.child});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MindTree',
      debugShowCheckedModeBanner: false,
      theme: lightTheme(),
      home: Scaffold(body: Center(child: child)),
    );
  }
}