import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/features/account/data/device_descriptor.dart';

/// What this install calls itself in the account's device list.
///
/// The list exists so someone can decide which device to revoke. Every entry
/// reading the same placeholder makes it useless for exactly that, which is
/// what happened: Android does not throw and does not return an empty string
/// from `Platform.localHostname`, it returns `localhost`. The old guard only
/// looked for those two failures, so the placeholder sailed through and every
/// phone on the account registered under it.
void main() {
  group('a hostname worth showing', () {
    test('a real machine name is kept', () {
      expect(DeviceDescriptor.isUsefulHostname('mustafas-MacBook-Pro'), isTrue);
      expect(DeviceDescriptor.isUsefulHostname('build-server-01'), isTrue);
    });

    test('the loopback name is not a machine name', () {
      // The one that got through.
      expect(DeviceDescriptor.isUsefulHostname('localhost'), isFalse);
      expect(
        DeviceDescriptor.isUsefulHostname('localhost.localdomain'),
        isFalse,
      );
      expect(DeviceDescriptor.isUsefulHostname('127.0.0.1'), isFalse);
      expect(DeviceDescriptor.isUsefulHostname('::1'), isFalse);
    });

    test('case does not smuggle it back in', () {
      expect(DeviceDescriptor.isUsefulHostname('LocalHost'), isFalse);
    });

    test('vendor placeholders are not machine names either', () {
      expect(DeviceDescriptor.isUsefulHostname('android'), isFalse);
      expect(DeviceDescriptor.isUsefulHostname('unknown'), isFalse);
    });

    test('an empty name is no name', () {
      expect(DeviceDescriptor.isUsefulHostname(''), isFalse);
    });
  });

  test('a rejected hostname falls back to something a person can place', () {
    // Not an assertion about this machine's name: whatever the host is
    // called, the descriptor has to produce a non-empty label, because an
    // unnamed row in a device list is the same problem in a different shape.
    final descriptor = DeviceDescriptor.current();

    expect(descriptor.name, isNotEmpty);
    expect(descriptor.name.toLowerCase(), isNot('localhost'));
  });
}
