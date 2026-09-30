import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'start_hidden.dart';

/// Starts ShellVibe when the user signs in to their computer.
///
/// The state lives in the OS (a login item, a Run key, an autostart entry), so
/// it is read from there and never stored in [AppSettingsModel]: settings sync
/// between devices, and a login item on one machine says nothing about
/// another. What is registered is this machine's own executable, which is
/// another reason it cannot travel.
///
/// Written out here rather than taken from the `launch_at_startup` package. Its
/// current release needs `win32_registry` 2.x, which needs `win32` 5, while
/// `flutter_secure_storage` pins `win32` 6; the two cannot be resolved
/// together. The job is three small platform-specific writes, done below the
/// same way that package does them.
abstract interface class LaunchAtLogin {
  /// Whether this platform and build can register a login item at all.
  Future<bool> isSupported();

  Future<bool> isEnabled();

  Future<void> setEnabled(bool enabled);
}

/// The platform's implementation, for the running app.
LaunchAtLogin createLaunchAtLogin() {
  if (Platform.isMacOS) return const MacOsLaunchAtLogin();
  if (Platform.isWindows) {
    return WindowsLaunchAtLogin(executable: Platform.resolvedExecutable);
  }
  if (Platform.isLinux) {
    final home = Platform.environment['HOME'];
    final config =
        Platform.environment['XDG_CONFIG_HOME'] ??
        (home == null ? null : '$home/.config');
    if (config == null) return const UnsupportedLaunchAtLogin();
    return LinuxLaunchAtLogin(
      // An AppImage runs from a temporary mount that is gone at the next boot;
      // the file the user keeps is the one it names here.
      executable:
          Platform.environment['APPIMAGE'] ?? Platform.resolvedExecutable,
      autostartDirectory: Directory('$config/autostart'),
    );
  }
  return const UnsupportedLaunchAtLogin();
}

class UnsupportedLaunchAtLogin implements LaunchAtLogin {
  const UnsupportedLaunchAtLogin();

  @override
  Future<bool> isSupported() async => false;

  @override
  Future<bool> isEnabled() async => false;

  @override
  Future<void> setEnabled(bool enabled) async {}
}

/// `SMAppService.mainApp`, the login item API of macOS 13 and later, reached
/// through a channel `MainFlutterWindow` registers.
///
/// Older systems report unsupported rather than failing: the app still runs on
/// macOS 12, it just has no toggle for this.
class MacOsLaunchAtLogin implements LaunchAtLogin {
  const MacOsLaunchAtLogin();

  static const _channel = MethodChannel('dev.shellvibe.app/launch_at_login');

  @override
  Future<bool> isSupported() async =>
      await _channel.invokeMethod<bool>('isSupported') ?? false;

  @override
  Future<bool> isEnabled() async =>
      await _channel.invokeMethod<bool>('isEnabled') ?? false;

  @override
  Future<void> setEnabled(bool enabled) =>
      _channel.invokeMethod<void>('setEnabled', enabled);

  /// Whether the OS started this process as a login item. Only meaningful
  /// early: it describes how the process was launched, not its state now.
  static Future<bool> wasLaunchedAtLogin() async {
    try {
      return await _channel.invokeMethod<bool>('wasLaunchedAtLogin') ?? false;
    } on MissingPluginException {
      return false;
    }
  }
}

/// Runs a process; injected so tests read and write no registry.
typedef ProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

/// A value under `HKCU\...\CurrentVersion\Run`, which Windows starts at sign-in
/// without elevation. Written through `reg.exe`, which ships with every
/// Windows and needs no extra dependency.
class WindowsLaunchAtLogin implements LaunchAtLogin {
  WindowsLaunchAtLogin({
    required this.executable,
    ProcessRunner? run,
    this.valueName = 'ShellVibe',
  }) : _run = run ?? Process.run;

  final String executable;
  final String valueName;
  final ProcessRunner _run;

  static const _runKey = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';

  /// Where Settings > Apps > Startup records the user's own on/off choice for
  /// an entry. A first byte that is odd means the user switched it off there,
  /// whatever the Run key says.
  static const _approvedKey =
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run';

  /// What is registered: the path quoted (it usually has spaces) and the
  /// argument that starts the window hidden.
  String get command => '"$executable" $kStartHiddenArgument';

  @override
  Future<bool> isSupported() async => true;

  @override
  Future<bool> isEnabled() async {
    final registered = await _run('reg', ['query', _runKey, '/v', valueName]);
    if (registered.exitCode != 0) return false;
    // "    ShellVibe    REG_SZ    "C:\...\shellvibe.exe" --hidden"
    final match = RegExp(
      r'REG_SZ\s+(.*?)\s*$',
      multiLine: true,
    ).firstMatch('${registered.stdout}');
    // A path that has moved, or an entry from another build, is not this
    // install's: reported off, so turning it on rewrites it.
    if (match?.group(1) != command) return false;

    final approved = await _run('reg', [
      'query',
      _approvedKey,
      '/v',
      valueName,
    ]);
    if (approved.exitCode != 0) return true;
    final bytes = RegExp(
      r'REG_BINARY\s+([0-9A-Fa-f]{2})',
    ).firstMatch('${approved.stdout}');
    final first = int.tryParse(bytes?.group(1) ?? '', radix: 16);
    return first == null || first.isEven;
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    if (enabled) {
      final result = await _run('reg', [
        'add',
        _runKey,
        '/v',
        valueName,
        '/t',
        'REG_SZ',
        '/d',
        command,
        '/f',
      ]);
      if (result.exitCode != 0) {
        throw ProcessException(
          'reg',
          ['add'],
          '${result.stderr}',
          result.exitCode,
        );
      }
      // Drops a "disabled" mark left by Settings > Startup, or the entry would
      // be registered and still not start.
      await _run('reg', ['delete', _approvedKey, '/v', valueName, '/f']);
    } else {
      // Exit 1 is "not there", which is what was asked for.
      await _run('reg', ['delete', _runKey, '/v', valueName, '/f']);
      await _run('reg', ['delete', _approvedKey, '/v', valueName, '/f']);
    }
  }
}

/// An XDG autostart entry, which GNOME, KDE, Xfce and most others run at
/// sign-in.
class LinuxLaunchAtLogin implements LaunchAtLogin {
  LinuxLaunchAtLogin({
    required this.executable,
    required this.autostartDirectory,
    this.fileName = 'shellvibe.desktop',
  });

  final String executable;
  final Directory autostartDirectory;
  final String fileName;

  File get _file => File('${autostartDirectory.path}/$fileName');

  /// The `Exec` line. The path is quoted, with the characters the Desktop Entry
  /// spec reserves inside quotes escaped, since a home directory may hold
  /// spaces.
  String get exec {
    final quoted = executable.replaceAllMapped(
      RegExp(r'["`$\\]'),
      (match) => '\\${match[0]}',
    );
    return '"$quoted" $kStartHiddenArgument';
  }

  @override
  Future<bool> isSupported() async => true;

  @override
  Future<bool> isEnabled() async {
    final file = _file;
    if (!await file.exists()) return false;
    final lines = await file.readAsLines();
    // An entry for another executable, or one the user disabled by hand with
    // `Hidden=true`, is not this install starting at login.
    return lines.contains('Exec=$exec') && !lines.contains('Hidden=true');
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    final file = _file;
    if (!enabled) {
      if (await file.exists()) await file.delete();
      return;
    }
    await autostartDirectory.create(recursive: true);
    await file.writeAsString(
      '[Desktop Entry]\n'
      'Type=Application\n'
      'Name=ShellVibe\n'
      'Comment=Start ShellVibe in the system tray\n'
      'Exec=$exec\n'
      'Terminal=false\n'
      'X-GNOME-Autostart-enabled=true\n',
    );
  }
}

final launchAtLoginProvider = Provider<LaunchAtLogin>(
  (ref) => createLaunchAtLogin(),
);

/// Whether ShellVibe starts at login on this machine, as the OS has it.
final launchAtLoginEnabledProvider =
    AsyncNotifierProvider<LaunchAtLoginEnabled, bool>(LaunchAtLoginEnabled.new);

class LaunchAtLoginEnabled extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final service = ref.read(launchAtLoginProvider);
    try {
      if (!await service.isSupported()) return false;
      return await service.isEnabled();
    } catch (_) {
      // An unreadable state is shown as off; the toggle writes it afresh.
      return false;
    }
  }

  /// Registers or removes the login item, then re-reads it rather than
  /// trusting the write: the OS is the record, and it may have refused.
  Future<void> setEnabled(bool enabled) async {
    final service = ref.read(launchAtLoginProvider);
    try {
      await service.setEnabled(enabled);
    } finally {
      state = AsyncData(await _readBack(service));
    }
  }

  Future<bool> _readBack(LaunchAtLogin service) async {
    try {
      return await service.isEnabled();
    } catch (_) {
      return false;
    }
  }
}
