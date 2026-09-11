import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/network/providers/network_providers.dart';

void main() {
  group('Network Providers Unit Tests', () {
    test('localPtyManagerProvider provides a LocalPtyManager instance', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final ptyManager = container.read(localPtyManagerProvider);
      expect(ptyManager, isNotNull);
    });

    test('sshSessionManagerProvider provides SSHSessionManager instance', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final manager = container.read(sshSessionManagerProvider);
      expect(manager, isNotNull);
    });
  });
}
