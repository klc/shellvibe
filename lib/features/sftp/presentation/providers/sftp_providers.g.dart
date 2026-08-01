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
    r'1f049534dba149a609dc622ea20db3ccef329ac5';

/// Provider for [SftpTransferQueueWorker]
///
/// Copied from [sftpTransferQueueWorker].
@ProviderFor(sftpTransferQueueWorker)
final sftpTransferQueueWorkerProvider =
    AutoDisposeProvider<SftpTransferQueueWorker>.internal(
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
typedef SftpTransferQueueWorkerRef =
    AutoDisposeProviderRef<SftpTransferQueueWorker>;
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
String _$sftpNotifierHash() => r'2ad5611d89947dd95481e32114938bb2f04425da';

/// See also [SftpNotifier].
@ProviderFor(SftpNotifier)
final sftpNotifierProvider =
    AutoDisposeNotifierProvider<SftpNotifier, SftpState>.internal(
      SftpNotifier.new,
      name: r'sftpNotifierProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$sftpNotifierHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$SftpNotifier = AutoDisposeNotifier<SftpState>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
