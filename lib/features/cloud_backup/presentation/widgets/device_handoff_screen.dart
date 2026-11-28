import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/theme/shellvibe_tokens.dart';
import '../../../../app/widgets/shellvibe_ui.dart';
import '../../../../app/widgets/window_chrome_frame.dart';
import '../../../../app/window/window_chrome.dart';
import '../../../../core/api/api_exception.dart';
import '../../../../core/sync/backup_envelope.dart';
import '../../../../core/sync/device_handoff.dart';
import '../../../../core/utils/platform_capabilities.dart';
import '../../../account/presentation/notifiers/account_notifier.dart';
import '../../../vault/data/vault_key_service.dart';
import '../../data/account_key_api.dart';
import '../../domain/device_handoff_service.dart';
import '../notifiers/cloud_backup_notifier.dart';

/// Sets a device up from another one, with a code instead of the passphrase.
///
/// The same screen on both devices. One shows a code and the other scans it;
/// which does which follows from which has a camera, so a phone starts on the
/// scanner and a desktop can only show.
final class DeviceHandoffScreen extends ConsumerStatefulWidget {
  const DeviceHandoffScreen({super.key, required this.gives});

  /// True on the device that is already set up and is handing its key over.
  final bool gives;

  @override
  ConsumerState<DeviceHandoffScreen> createState() =>
      _DeviceHandoffScreenState();
}

enum _Step { working, showing, scanning, done, failed }

class _DeviceHandoffScreenState extends ConsumerState<DeviceHandoffScreen> {
  /// Made the first time this device scans. A desktop never does, and has
  /// no camera plugin for a controller to talk to.
  MobileScannerController? _scanner;

  _Step _step = _Step.working;
  String? _error;
  ShownHandoff? _shown;
  Uint8List? _accountKey;
  bool _handling = false;

  @override
  void initState() {
    super.initState();
    unawaited(_begin(scan: isMobilePlatform));
  }

  @override
  void dispose() {
    unawaited(_shown?.cancel());
    unawaited(_scanner?.dispose());
    super.dispose();
  }

  DeviceHandoffService? get _service {
    final session = ref.read(accountProvider).value?.session;
    if (session == null) return null;

    return DeviceHandoffService(
      api: HandoffApi(client: ref.read(accountProvider.notifier).apiClient),
      userId: session.userId,
    );
  }

  /// Reads the key this device is about to hand over, then scans or shows.
  Future<void> _begin({required bool scan}) async {
    await _guarded(() async {
      if (widget.gives && _accountKey == null) {
        _accountKey = await ref
            .read(cloudBackupProvider.notifier)
            .accountKeyForHandoff();
        if (_accountKey == null) {
          throw const HandoffException(
            'This device is not set up with an account key yet.',
          );
        }
      }

      if (scan) {
        await _shown?.cancel();
        _shown = null;
        _scanner ??= MobileScannerController(
          formats: const [BarcodeFormat.qrCode],
        );
        if (mounted) setState(() => _step = _Step.scanning);

        return;
      }

      await _show();
    });
  }

  Future<void> _show() async {
    final service = _service;
    if (service == null) throw const HandoffException('Sign in first.');

    await _shown?.cancel();
    final shown = _shown = await service.show(gives: widget.gives);
    if (!mounted) return;
    setState(() => _step = _Step.showing);

    final received = await shown.complete(accountKey: _accountKey);
    if (!identical(shown, _shown)) return;

    await _finish(received);
  }

  Future<void> _scanned(BarcodeCapture capture) async {
    final code = capture.barcodes.firstOrNull?.rawValue;
    if (code == null || _handling) return;
    _handling = true;

    await _scanner?.stop();
    if (mounted) setState(() => _step = _Step.working);

    await _guarded(() async {
      final service = _service;
      if (service == null) throw const HandoffException('Sign in first.');

      await _finish(await service.scan(code, accountKey: _accountKey));
    });
    _handling = false;
  }

  /// [received] is the key the other device handed over, or null when this
  /// device was the one giving.
  Future<void> _finish(Uint8List? received) async {
    if (received != null) {
      final refused = await ref
          .read(cloudBackupProvider.notifier)
          .adoptAccountKey(received);
      if (refused != null) throw HandoffException(refused);
    }

    if (mounted) setState(() => _step = _Step.done);
  }

  /// Every way this can stop becomes one sentence on the screen.
  Future<void> _guarded(Future<void> Function() run) async {
    try {
      await run();
    } on HandoffException catch (e) {
      // Leaving the screen cancels the wait; nobody is left to tell.
      if (e.message != 'Cancelled.') _fail(e.message);
    } on VaultLockedException {
      _fail('Unlock the vault first. The account key is sealed behind it.');
    } on BackupEnvelopeException catch (e) {
      _fail(e.reason);
    } on ApiFailure {
      _fail('The server could not be reached.');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _step = _Step.failed;
      _error = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final screen = Scaffold(
      // Pushed over the shell, so on desktop it draws the shell's chrome
      // itself; otherwise the close button lands under the traffic lights.
      backgroundColor: usesHiddenTitleBar ? Colors.transparent : null,
      appBar: AppBar(
        title: Text(widget.gives ? 'Add Another Device' : 'Add This Device'),
      ),
      body: switch (_step) {
        _Step.scanning => _buildScanner(context),
        _ => SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: switch (_step) {
                  _Step.showing => _buildCode(context),
                  _Step.done => _buildDone(context),
                  _Step.failed => _buildFailed(context),
                  _ => const Center(
                    child: CircularProgressIndicator.adaptive(),
                  ),
                },
              ),
            ),
          ),
        ),
      },
    );

    return usesHiddenTitleBar ? WindowChromeFrame(child: screen) : screen;
  }

  Widget _buildCode(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.gives
              ? 'Scan this with the device you are adding'
              : 'Scan this with a device that is already set up',
          style: Theme.of(context).textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          widget.gives
              ? 'On the other device: sign in to the same account, open '
                    'Settings → Cloud Backup and choose to scan a code. This '
                    'code works once and expires in three minutes. Only let '
                    'a device of your own scan it.'
              : 'On the other device: open Settings → Cloud Backup → Add '
                    'Another Device, and scan this. The code works once and '
                    'expires in three minutes.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: tokens.textMuted),
        ),
        const SizedBox(height: 24),
        DecoratedBox(
          // Deliberately outside the token system: a QR code needs a white
          // quiet zone to be read, whatever theme this device is in.
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: QrImageView(
              key: const Key('device_handoff_qr'),
              data: _shown!.code,
              size: math.min(MediaQuery.sizeOf(context).width - 96, 300),
              backgroundColor: Colors.white,
            ),
          ),
        ),
        if (isMobilePlatform) ...[
          const SizedBox(height: 16),
          ShellVibeButton.quiet(
            buttonKey: const Key('device_handoff_scan_instead_button'),
            label: 'Scan a Code Instead',
            icon: LucideIcons.scanLine,
            onPressed: () => _begin(scan: true),
          ),
        ],
      ],
    );
  }

  Widget _buildScanner(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      MobileScanner(
        controller: _scanner,
        onDetect: _scanned,
        errorBuilder: (context, error) => ColoredBox(
          color: Theme.of(context).colorScheme.surface,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Camera access is needed to scan the code '
                '(${error.errorCode.name}). You can show a code on this '
                'device instead.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
      IgnorePointer(
        child: Center(
          child: Container(
            width: 260,
            height: 260,
            // Deliberately outside the token system: this sits on the live
            // camera feed, not on a themed surface.
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 3),
              borderRadius: BorderRadius.circular(15),
            ),
          ),
        ),
      ),
      Positioned(
        left: 24,
        right: 24,
        bottom: 32,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.gives
                  ? 'Point the camera at the code on the device you are '
                        'adding.'
                  : 'Point the camera at the code on a device that is '
                        'already set up.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 12),
            ShellVibeButton.secondary(
              buttonKey: const Key('device_handoff_show_instead_button'),
              label: 'Show a Code Instead',
              icon: LucideIcons.qrCode,
              onPressed: () => _begin(scan: false),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _buildDone(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(LucideIcons.circleCheck, size: 40, color: tokens.success),
        const SizedBox(height: 12),
        Text(
          widget.gives
              ? 'Sent. The other device finishes setting itself up.'
              : 'This device is set up. No passphrase was needed, and none '
                    'is stored here.',
          key: const Key('device_handoff_done'),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        ShellVibeButton(
          label: 'Done',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ],
    );
  }

  Widget _buildFailed(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(LucideIcons.circleAlert, size: 40, color: tokens.warning),
        const SizedBox(height: 12),
        Text(
          _error ?? 'Something went wrong.',
          key: const Key('device_handoff_error'),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        ShellVibeButton(
          buttonKey: const Key('device_handoff_retry_button'),
          label: 'Try Again',
          icon: LucideIcons.refreshCw,
          onPressed: () {
            setState(() {
              _step = _Step.working;
              _error = null;
            });
            unawaited(_begin(scan: isMobilePlatform));
          },
        ),
      ],
    );
  }
}
