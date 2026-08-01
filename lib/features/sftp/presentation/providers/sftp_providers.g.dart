// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sftp_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Provider for [SftpService]

@ProviderFor(sftpService)
final sftpServiceProvider = SftpServiceProvider._();

/// Provider for [SftpService]

final class SftpServiceProvider
    extends $FunctionalProvider<SftpService, SftpService, SftpService>
    with $Provider<SftpService> {
  /// Provider for [SftpService]
  SftpServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'sftpServiceProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$sftpServiceHash();

  @$internal
  @override
  $ProviderElement<SftpService> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  SftpService create(Ref ref) {
    return sftpService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SftpService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SftpService>(value),
    );
  }
}

String _$sftpServiceHash() => r'6a33fa17a07e90ff4d6d66a51387855c31e90812';

/// Provider for [SftpTransferQueueWorker].
///
/// keepAlive: the transfer queue must survive screen navigation — an
/// autoDispose worker would be torn down (closing the queue controller) while
/// transfers are in flight, failing them mid-write and wiping the queue.

@ProviderFor(sftpTransferQueueWorker)
final sftpTransferQueueWorkerProvider = SftpTransferQueueWorkerProvider._();

/// Provider for [SftpTransferQueueWorker].
///
/// keepAlive: the transfer queue must survive screen navigation — an
/// autoDispose worker would be torn down (closing the queue controller) while
/// transfers are in flight, failing them mid-write and wiping the queue.

final class SftpTransferQueueWorkerProvider
    extends
        $FunctionalProvider<
          SftpTransferQueueWorker,
          SftpTransferQueueWorker,
          SftpTransferQueueWorker
        >
    with $Provider<SftpTransferQueueWorker> {
  /// Provider for [SftpTransferQueueWorker].
  ///
  /// keepAlive: the transfer queue must survive screen navigation — an
  /// autoDispose worker would be torn down (closing the queue controller) while
  /// transfers are in flight, failing them mid-write and wiping the queue.
  SftpTransferQueueWorkerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'sftpTransferQueueWorkerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$sftpTransferQueueWorkerHash();

  @$internal
  @override
  $ProviderElement<SftpTransferQueueWorker> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  SftpTransferQueueWorker create(Ref ref) {
    return sftpTransferQueueWorker(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SftpTransferQueueWorker value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SftpTransferQueueWorker>(value),
    );
  }
}

String _$sftpTransferQueueWorkerHash() =>
    r'6ce18395ec0a1dab41976f0ffa5dd078fa371aee';

/// Provider watching the active transfer queue list

@ProviderFor(transferQueueStream)
final transferQueueStreamProvider = TransferQueueStreamProvider._();

/// Provider watching the active transfer queue list

final class TransferQueueStreamProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<TransferItem>>,
          List<TransferItem>,
          Stream<List<TransferItem>>
        >
    with
        $FutureModifier<List<TransferItem>>,
        $StreamProvider<List<TransferItem>> {
  /// Provider watching the active transfer queue list
  TransferQueueStreamProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'transferQueueStreamProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$transferQueueStreamHash();

  @$internal
  @override
  $StreamProviderElement<List<TransferItem>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<TransferItem>> create(Ref ref) {
    return transferQueueStream(ref);
  }
}

String _$transferQueueStreamHash() =>
    r'b14b1f9d58eddd63be2303b43ac5b9638a0bee88';

@ProviderFor(SftpNotifier)
final sftpProvider = SftpNotifierProvider._();

final class SftpNotifierProvider
    extends $NotifierProvider<SftpNotifier, SftpState> {
  SftpNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'sftpProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$sftpNotifierHash();

  @$internal
  @override
  SftpNotifier create() => SftpNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SftpState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SftpState>(value),
    );
  }
}

String _$sftpNotifierHash() => r'bdf99288e591566174af15d106936e7d8012eff8';

abstract class _$SftpNotifier extends $Notifier<SftpState> {
  SftpState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<SftpState, SftpState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<SftpState, SftpState>,
              SftpState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
