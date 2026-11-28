import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../../../core/api/api_exception.dart';
import '../../../core/sync/device_handoff.dart';
import '../data/account_key_api.dart';

/// Runs a device handoff on one of its two devices.
///
/// The cryptography is [DeviceHandoff]'s. This is the conversation around it:
/// who opens the mailbox, who writes which slot, and how long anybody waits.
///
/// Which device shows the code follows from which one has a camera, not from
/// which one holds the key, so both combinations exist:
///
/// * the device with the key shows the code, the new one scans it, and the
///   key comes back in the answer;
/// * the new device shows the code, the one with the key scans it, and the
///   key travels in the offer.
final class DeviceHandoffService {
  final HandoffTransport api;

  /// The account both devices have to be signed in to.
  final String userId;

  final Duration pollInterval;

  const DeviceHandoffService({
    required this.api,
    required this.userId,
    this.pollInterval = const Duration(seconds: 2),
  });

  /// Opens a mailbox and makes the code to show.
  ///
  /// [gives] is true on a device that holds the account key.
  Future<ShownHandoff> show({required bool gives}) async {
    final mailbox = await api.open();

    return ShownHandoff._(
      this,
      await DeviceHandoff.display(
        id: mailbox.id,
        userId: userId,
        gives: gives,
        expiresAt: mailbox.expiresAt,
      ),
    );
  }

  /// Takes up a scanned code.
  ///
  /// [accountKey] is this device's key, when it holds one. Returns the key
  /// the other device handed over, or null when this device was the one
  /// handing it over.
  Future<Uint8List?> scan(String code, {Uint8List? accountKey}) async {
    final invite = HandoffInvite.decode(code);

    if (invite.displayerGives && accountKey != null) {
      throw const HandoffException(
        'Both devices are already set up. Nothing to transfer.',
      );
    }
    if (!invite.displayerGives && accountKey == null) {
      throw const HandoffException(
        'Neither device is set up yet. Scan this code with a device that '
        'already has your cloud backup, or enter your passphrase.',
      );
    }

    final scan = await DeviceHandoff.scan(invite, userId: userId);

    await _guarded(
      () async => api.writeOffer(
        invite.id,
        await scan.offer(accountKey == null ? '' : base64.encode(accountKey)),
      ),
    );
    if (accountKey != null) return null;

    final answer = await _waitFor(
      invite.id,
      (mailbox) => mailbox.answer,
      invite.expiresAt,
    );
    final key = _key(await scan.openAnswer(answer));

    // Read once and gone. Left alone it expires anyway.
    unawaited(api.close(invite.id).catchError((_) {}));

    return key;
  }

  Future<String> _waitFor(
    String id,
    String? Function(HandoffMailbox mailbox) slot,
    DateTime expiresAt, {
    bool Function()? cancelled,
  }) async {
    while (true) {
      if (cancelled?.call() ?? false) {
        throw const HandoffException('Cancelled.');
      }
      if (!DateTime.now().toUtc().isBefore(expiresAt)) {
        throw const HandoffException('This code has expired. Show a new one.');
      }

      final message = slot(await _guarded(() => api.read(id)));
      if (message != null) return message;

      await Future<void>.delayed(pollInterval);
    }
  }

  /// Turns the server's refusals into sentences. A mailbox that is gone and
  /// one that never existed are the same to the user: start again.
  static Future<T> _guarded<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on ApiException catch (e) {
      throw HandoffException(switch (e.code) {
        'handoff_slot_taken' =>
          'This code has already been used. Show a new one.',
        'handoff_not_found' => 'This code has expired. Show a new one.',
        _ => 'The server refused the transfer (${e.code}).',
      });
    } on ApiTransportException {
      throw const HandoffException('The server could not be reached.');
    }
  }

  static Uint8List _key(String payload) {
    try {
      final key = base64.decode(payload);
      if (key.length == 32) return key;
    } on FormatException {
      // Falls through.
    }

    throw const HandoffException(
      'The other device did not send an account key. Nothing was changed.',
    );
  }
}

/// A handoff this device is showing the code for.
final class ShownHandoff {
  ShownHandoff._(this._service, this._display);

  final DeviceHandoffService _service;
  final HandoffDisplay _display;
  bool _cancelled = false;

  /// What the QR code holds.
  String get code => _display.invite.encode();

  DateTime get expiresAt => _display.invite.expiresAt;

  /// Waits for the other device to scan, then finishes.
  ///
  /// [accountKey] is the key to hand over, on the device that holds it.
  /// Returns the key received, or null when this device gave it.
  Future<Uint8List?> complete({Uint8List? accountKey}) async {
    final id = _display.invite.id;

    final offer = await _service._waitFor(
      id,
      (mailbox) => mailbox.offer,
      expiresAt,
      cancelled: () => _cancelled,
    );

    // Throws when the offer was not made from this code, and then nothing
    // below runs: no key is sealed for a device that has not proved it read
    // the screen.
    final payload = await _display.acceptOffer(offer);

    if (accountKey == null) {
      unawaited(_service.api.close(id).catchError((_) {}));

      return DeviceHandoffService._key(payload);
    }

    final answer = await _display.answer(base64.encode(accountKey));
    await DeviceHandoffService._guarded(
      () => _service.api.writeAnswer(id, answer),
    );

    return null;
  }

  /// Stops waiting and closes the mailbox.
  Future<void> cancel() async {
    _cancelled = true;
    await _service.api.close(_display.invite.id).catchError((_) {});
  }
}
