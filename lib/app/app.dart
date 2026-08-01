import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/vault/presentation/notifiers/vault_notifier.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';

/// Root application widget.
///
/// Converts to [ConsumerStatefulWidget] to install an [AppLifecycleListener]
/// that auto-locks the vault when the app moves to the background.
class TerlyApp extends ConsumerStatefulWidget {
  const TerlyApp({super.key});

  @override
  ConsumerState<TerlyApp> createState() => _TerlyAppState();
}

class _TerlyAppState extends ConsumerState<TerlyApp> {
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(
      onStateChange: _onLifecycleChange,
    );
  }

  /// Locks the vault when the application enters a background or hidden state.
  void _onLifecycleChange(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      ref.read(vaultNotifierProvider.notifier).lock();
    }
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'Terly',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      routerConfig: router,
    );
  }
}
