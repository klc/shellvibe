import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Maps a platform string to a glyph, tolerating values this build has never
/// seen -- the contract allows new ones.
IconData platformIcon(String platform) => switch (platform.toLowerCase()) {
  'ios' || 'android' => LucideIcons.smartphone,
  'macos' => LucideIcons.laptop,
  'windows' || 'linux' => LucideIcons.monitor,
  'web' => LucideIcons.globe,
  _ => LucideIcons.circleHelp,
};
