import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../features/settings/domain/models/app_settings_model.dart';
import '../features/settings/presentation/notifiers/settings_notifier.dart';
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
  Timer? _autoLockTimer;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(
      onStateChange: _onLifecycleChange,
    );
  }

  /// Locks the vault after the configured auto-lock delay when the app enters
  /// a background or hidden state. Honors `autoLockTimerSeconds` (0 = disabled)
  /// instead of locking instantly and unconditionally.
  void _onLifecycleChange(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      final settings = ref.read(settingsNotifierProvider).value;
      final delaySeconds = settings?.autoLockTimerSeconds ?? 0;
      if (delaySeconds <= 0) return;
      _autoLockTimer?.cancel();
      _autoLockTimer = Timer(Duration(seconds: delaySeconds), () {
        ref.read(vaultNotifierProvider.notifier).lock();
      });
    } else if (state == AppLifecycleState.resumed) {
      _autoLockTimer?.cancel();
      _autoLockTimer = null;
    }
  }

  @override
  void dispose() {
    _autoLockTimer?.cancel();
    _lifecycleListener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final settingsAsync = ref.watch(settingsNotifierProvider);
    final settings = settingsAsync.value ?? const AppSettingsModel();

    return ShadApp.router(
      title: 'Terly',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.buildShadTheme(settings.copyWith(themeMode: ThemeMode.light)),
      darkTheme: AppTheme.buildShadTheme(settings.copyWith(themeMode: ThemeMode.dark)),
      themeMode: settings.themeMode,
      materialThemeBuilder: (context, theme) => AppTheme.buildTheme(settings),
      routerConfig: router,
    );
  }
}

