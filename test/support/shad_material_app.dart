import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// The app's root in miniature (lib/app/app.dart): a package:material_ui
/// MaterialApp inside ShadApp.custom, with the bridge that hands shadcn_ui
/// and other legacy-material dependencies their Theme and localizations.
Widget shadMaterialApp({
  Widget? home,
  GlobalKey<NavigatorState>? navigatorKey,
  TransitionBuilder? builder,
}) => ShadApp.custom(
  appBuilder: (context) => MaterialApp(
    navigatorKey: navigatorKey,
    home: home,
    localizationsDelegates: const [GlobalShadLocalizations.delegate],
    // ignore: deprecated_member_use
    builder: (context, child) => MaterialUiCompatibilityBridge(
      child: ShadAppBuilder(builder: builder, child: child),
    ),
  ),
);
