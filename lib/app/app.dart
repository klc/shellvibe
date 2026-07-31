import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:terly2/app/router/app_router.dart';
import 'package:terly2/app/theme/app_theme.dart';
import 'package:terly2/features/settings/domain/models/app_settings_model.dart';
import 'package:terly2/features/settings/presentation/notifiers/settings_notifier.dart';

class TerlyApp extends ConsumerWidget {
  const TerlyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final settingsAsync = ref.watch(settingsNotifierProvider);
    final settings = settingsAsync.value ?? const AppSettingsModel();

    final themeData = AppTheme.buildTheme(settings);

    return MaterialApp.router(
      title: 'Terly2',
      debugShowCheckedModeBanner: false,
      theme: themeData,
      darkTheme: themeData,
      themeMode: settings.themeMode,
      routerConfig: router,
    );
  }
}
