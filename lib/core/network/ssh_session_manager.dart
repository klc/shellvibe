import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../shared/database/app_database.dart';
import '../../shared/database/daos/known_hosts_dao.dart';

/// Status of host key verification during SSH handshake.
enum HostKeyVerificationStatus {
  /// The host key is trusted and matches existing record in known_hosts.
  trusted,

  /// Host is encountered for the first time (Trust On First Use).
  unknown,

  /// Host key does not match the stored fingerprint (Possible MitM attack!).
  mismatch,
}

/// Signature for user prompt callback when host key verification needs confirmation.
typedef HostKeyPromptCallback = FutureOr<bool> Function(
  String hostname,
  int port,
  String keyType,
  String fingerprint,
  HostKeyVerificationStatus status,
);

/// Configuration parameters for establishing an SSH connection.
class SSHConnectConfig {
  final String hostname;
  final int port;
  final String username;
  final String? password;
  final String? privateKeyPem;
  final String? passphrase;
  final Duration timeout;
  final Duration? keepAliveInterval;
  final HostKeyPromptCallback? onHostKeyPrompt;

  const SSHConnectConfig({
    required this.hostname,
    this.port = 22,
    required this.username,
    this.password,
    this.privateKeyPem,
    this.passphrase,
    this.timeout = const Duration(seconds: 15),
    this.keepAliveInterval = const Duration(seconds: 30),
    this.onHostKeyPrompt,
  });
}

/// Manages SSH connection lifecycle, authentication, host key verification,
/// keep-alive pings, and session spawning.
class SSHSessionManager {
  final KnownHostsDao? knownHostsDao;

  SSHClient? _client;
  SSHSocket? _socket;
  Timer? _keepAliveTimer;
  bool _isConnected = false;

  SSHSessionManager({this.knownHostsDao});

  /// Current active [SSHClient] if connected.
  SSHClient? get client => _client;

  /// Returns true if an active SSH connection is open and authenticated.
  bool get isConnected => _isConnected && _client != null && !_client!.isClosed;

  /// Establishes an SSH connection and authenticates based on [config].
  Future<SSHClient> connect(SSHConnectConfig config) async {
    await close();

    // 1. Parse Private Key if provided
    List<SSHKeyPair>? identities;
    if (config.privateKeyPem != null && config.privateKeyPem!.trim().isNotEmpty) {
      try {
        identities = SSHKeyPair.fromPem(
          config.privateKeyPem!,
          config.passphrase,
        );
      } catch (e) {
        throw FormatException('Failed to parse SSH private key: $e');
      }
    }

    // 2. Open TCP socket
    try {
      _socket = await SSHSocket.connect(
        config.hostname,
        config.port,
        timeout: config.timeout,
      );
    } catch (e) {
      throw Exception('Failed to connect to ${config.hostname}:${config.port}: $e');
    }

    // 3. Create SSH Client with Host Key Verification and Auth handlers
    final client = SSHClient(
      _socket!,
      username: config.username,
      identities: identities,
      onPasswordRequest: config.password != null ? () => config.password! : null,
      keepAliveInterval: config.keepAliveInterval,
      onVerifyHostKey: (String type, Uint8List fingerprintBytes) async {
        final fingerprintStr = base64.encode(fingerprintBytes);
        return await _verifyHostKey(
          hostname: config.hostname,
          port: config.port,
          keyType: type,
          fingerprint: fingerprintStr,
          promptCallback: config.onHostKeyPrompt,
        );
      },
    );

    // 4. Wait for SSH authentication handshake with timeout
    try {
      await client.authenticated.timeout(
        config.timeout,
        onTimeout: () {
          throw TimeoutException('SSH authentication handshake timed out after ${config.timeout.inSeconds}s');
        },
      );
      _client = client;
      _isConnected = true;

      if (config.keepAliveInterval != null) {
        startKeepAlive(config.keepAliveInterval!);
      }

      return client;
    } catch (e) {
      await close();
      throw Exception('SSH authentication failed for ${config.username}@${config.hostname}: $e');
    }
  }

  /// Host key verification logic using [KnownHostsDao] and optional [promptCallback].
  @visibleForTesting
  Future<bool> verifyHostKey({
    required String hostname,
    required int port,
    required String keyType,
    required String fingerprint,
    HostKeyPromptCallback? promptCallback,
  }) async {
    return _verifyHostKey(
      hostname: hostname,
      port: port,
      keyType: keyType,
      fingerprint: fingerprint,
      promptCallback: promptCallback,
    );
  }

  Future<bool> _verifyHostKey({
    required String hostname,
    required int port,
    required String keyType,
    required String fingerprint,
    HostKeyPromptCallback? promptCallback,
  }) async {
    final dao = knownHostsDao;

    if (dao != null) {
      final existingHost = await dao.findKnownHost(hostname, port);

      if (existingHost != null) {
        if (existingHost.fingerprintSha256 == fingerprint) {
          // Trusted key matches database
          return true;
        } else {
          // Host key mismatch! Prompt user via callback.
          bool approve = false;
          if (promptCallback != null) {
            approve = await promptCallback(
              hostname,
              port,
              keyType,
              fingerprint,
              HostKeyVerificationStatus.mismatch,
            );
          }

          if (approve) {
            await dao.insertOrUpdateKnownHost(
              KnownHostsCompanion.insert(
                id: existingHost.id,
                hostname: hostname,
                port: port,
                keyType: keyType,
                fingerprintSha256: fingerprint,
                firstSeenAt: existingHost.firstSeenAt,
              ),
            );
            return true;
          }
          return false;
        }
      } else {
        // Unknown host (First connection)
        bool approve = true;
        if (promptCallback != null) {
          approve = await promptCallback(
            hostname,
            port,
            keyType,
            fingerprint,
            HostKeyVerificationStatus.unknown,
          );
        }

        if (approve) {
          await dao.insertOrUpdateKnownHost(
            KnownHostsCompanion.insert(
              id: const Uuid().v4(),
              hostname: hostname,
              port: port,
              keyType: keyType,
              fingerprintSha256: fingerprint,
              firstSeenAt: DateTime.now(),
            ),
          );
        }
        return approve;
      }
    }

    // Fallback if no DAO provided
    if (promptCallback != null) {
      return await promptCallback(
        hostname,
        port,
        keyType,
        fingerprint,
        HostKeyVerificationStatus.unknown,
      );
    }
    return true;
  }

  /// Opens an interactive shell [SSHSession].
  Future<SSHSession> openShell({
    String terminalType = 'xterm-256color',
    int width = 80,
    int height = 24,
    int pixelWidth = 0,
    int pixelHeight = 0,
    Map<String, String>? environment,
  }) async {
    final activeClient = _client;
    if (activeClient == null || !_isConnected || activeClient.isClosed) {
      throw StateError('SSHClient is not connected. Call connect() first.');
    }

    return await activeClient.shell(
      pty: SSHPtyConfig(
        type: terminalType,
        width: width,
        height: height,
        pixelWidth: pixelWidth,
        pixelHeight: pixelHeight,
      ),
      environment: environment,
    );
  }

  /// Sends a keep-alive ping to the remote server.
  Future<void> ping() async {
    final activeClient = _client;
    if (activeClient != null && _isConnected && !activeClient.isClosed) {
      try {
        await activeClient.ping();
      } catch (_) {
        _isConnected = false;
        // Ping failed, connection may have been dropped
      }
    }
  }

  /// Starts periodic keep-alive ping timer.
  void startKeepAlive(Duration interval) {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(interval, (_) => ping());
  }

  /// Cancels timers and closes active SSH client session and socket.
  Future<void> close() async {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
    _isConnected = false;

    if (_client != null) {
      try {
        _client!.close();
      } catch (_) {}
      _client = null;
    }

    if (_socket != null) {
      try {
        _socket!.destroy();
      } catch (_) {}
      _socket = null;
    }
  }
}
