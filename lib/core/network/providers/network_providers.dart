import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../local_pty_manager.dart';

part 'network_providers.g.dart';

/// Auto-disposing provider for [LocalPtyManager].
@riverpod
LocalPtyManager localPtyManager(Ref ref) {
  return LocalPtyManager();
}
