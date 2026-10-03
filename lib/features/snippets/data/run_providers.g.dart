// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'run_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Where background runs get their sessions. The seam widget tests override
/// with a fake so no test (and no un-wired build) can reach a socket or pretend
/// a command ran.

@ProviderFor(remoteCommandSessionFactory)
final remoteCommandSessionFactoryProvider =
    RemoteCommandSessionFactoryProvider._();

/// Where background runs get their sessions. The seam widget tests override
/// with a fake so no test (and no un-wired build) can reach a socket or pretend
/// a command ran.

final class RemoteCommandSessionFactoryProvider
    extends
        $FunctionalProvider<
          RemoteCommandSessionFactory,
          RemoteCommandSessionFactory,
          RemoteCommandSessionFactory
        >
    with $Provider<RemoteCommandSessionFactory> {
  /// Where background runs get their sessions. The seam widget tests override
  /// with a fake so no test (and no un-wired build) can reach a socket or pretend
  /// a command ran.
  RemoteCommandSessionFactoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'remoteCommandSessionFactoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$remoteCommandSessionFactoryHash();

  @$internal
  @override
  $ProviderElement<RemoteCommandSessionFactory> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  RemoteCommandSessionFactory create(Ref ref) {
    return remoteCommandSessionFactory(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RemoteCommandSessionFactory value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RemoteCommandSessionFactory>(value),
    );
  }
}

String _$remoteCommandSessionFactoryHash() =>
    r'35eaa68210893a45903fe1f5a3dfb7267c72e1d2';

@ProviderFor(runbookRunService)
final runbookRunServiceProvider = RunbookRunServiceProvider._();

final class RunbookRunServiceProvider
    extends
        $FunctionalProvider<
          RunbookRunService,
          RunbookRunService,
          RunbookRunService
        >
    with $Provider<RunbookRunService> {
  RunbookRunServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'runbookRunServiceProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$runbookRunServiceHash();

  @$internal
  @override
  $ProviderElement<RunbookRunService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  RunbookRunService create(Ref ref) {
    return runbookRunService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RunbookRunService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RunbookRunService>(value),
    );
  }
}

String _$runbookRunServiceHash() => r'9a6949d9c94ab65aa23f6dbb75faf4a28b9a2216';
