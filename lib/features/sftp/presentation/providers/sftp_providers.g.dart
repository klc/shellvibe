// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sftp_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$sftpServiceHash() => r'6a33fa17a07e90ff4d6d66a51387855c31e90812';

/// Provider for [SftpService]
///
/// Copied from [sftpService].
@ProviderFor(sftpService)
final sftpServiceProvider = AutoDisposeProvider<SftpService>.internal(
  sftpService,
  name: r'sftpServiceProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$sftpServiceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef SftpServiceRef = AutoDisposeProviderRef<SftpService>;
String _$sftpTransferQueueWorkerHash() =>
    r'3dc947addffe8bb05c3e24d15f5c8d84f1cba919';

/// Provider for [SftpTransferQueueWorker].
///
/// keepAlive: the transfer queue must survive screen navigation — an
/// autoDispose worker would be torn down (closing the queue controller) while
/// transfers are in flight, failing them mid-write and wiping the queue.
///
/// Copied from [sftpTransferQueueWorker].
@ProviderFor(sftpTransferQueueWorker)
final sftpTransferQueueWorkerProvider =
    Provider<SftpTransferQueueWorker>.internal(
      sftpTransferQueueWorker,
      name: r'sftpTransferQueueWorkerProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$sftpTransferQueueWorkerHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef SftpTransferQueueWorkerRef = ProviderRef<SftpTransferQueueWorker>;
String _$transferQueueStreamHash() =>
    r'b14b1f9d58eddd63be2303b43ac5b9638a0bee88';

/// Provider watching the active transfer queue list
///
/// Copied from [transferQueueStream].
@ProviderFor(transferQueueStream)
final transferQueueStreamProvider =
    AutoDisposeStreamProvider<List<TransferItem>>.internal(
      transferQueueStream,
      name: r'transferQueueStreamProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$transferQueueStreamHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef TransferQueueStreamRef =
    AutoDisposeStreamProviderRef<List<TransferItem>>;
String _$sftpNotifierHash() => r'74e11e66ef3662c0d34bb07122433c22d517e6fa';

/// See also [SftpNotifier].
@ProviderFor(SftpNotifier)
final sftpNotifierProvider = NotifierProvider<SftpNotifier, SftpState>.internal(
  SftpNotifier.new,
  name: r'sftpNotifierProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$sftpNotifierHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$SftpNotifier = Notifier<SftpState>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
