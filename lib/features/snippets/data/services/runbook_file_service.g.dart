// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'runbook_file_service.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(runbookFileService)
final runbookFileServiceProvider = RunbookFileServiceProvider._();

final class RunbookFileServiceProvider
    extends
        $FunctionalProvider<
          RunbookFileService,
          RunbookFileService,
          RunbookFileService
        >
    with $Provider<RunbookFileService> {
  RunbookFileServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'runbookFileServiceProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$runbookFileServiceHash();

  @$internal
  @override
  $ProviderElement<RunbookFileService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  RunbookFileService create(Ref ref) {
    return runbookFileService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RunbookFileService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RunbookFileService>(value),
    );
  }
}

String _$runbookFileServiceHash() =>
    r'db5433b769a89e8bec4fb5fc46629d82e9b082cd';
