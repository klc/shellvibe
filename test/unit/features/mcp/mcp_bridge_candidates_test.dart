import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/features/mcp/presentation/widgets/mcp_access_settings_section.dart';

void main() {
  group('mcpBridgeCandidates', () {
    test('gives the Store build the execution alias first', () {
      expect(
        mcpBridgeCandidates(
          resolvedExecutable:
              r'C:\Program Files\WindowsApps\ShellVibe_1.7.0.0_x64__abc\shellvibe.exe',
          environment: {'LOCALAPPDATA': r'C:\Users\me\AppData\Local'},
          isWindows: true,
          isLinux: false,
          isWindowsStorePackage: true,
        ).first,
        r'C:\Users\me\AppData\Local\Microsoft\WindowsApps\shellvibe-mcp.exe',
      );
    });

    test('looks next to the executable for the installer build', () {
      expect(
        mcpBridgeCandidates(
          resolvedExecutable: r'C:\Apps\ShellVibe\shellvibe.exe',
          environment: {'LOCALAPPDATA': r'C:\Users\me\AppData\Local'},
          isWindows: true,
          isLinux: false,
          isWindowsStorePackage: false,
        ),
        [r'C:\Apps\ShellVibe\shellvibe-mcp.exe'],
      );
    });

    test('adds ~/.local/bin on Linux', () {
      expect(
        mcpBridgeCandidates(
          resolvedExecutable: '/opt/ShellVibe/shellvibe',
          environment: {'HOME': '/home/me'},
          isWindows: false,
          isLinux: true,
          isWindowsStorePackage: false,
        ),
        ['/opt/ShellVibe/shellvibe-mcp', '/home/me/.local/bin/shellvibe-mcp'],
      );
    });
  });
}
