// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'runbooks_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$runbooksRepositoryHash() =>
    r'bd6aabd4597522d8931c8d5d05e0e553fbf69233';

/// See also [runbooksRepository].
@ProviderFor(runbooksRepository)
final runbooksRepositoryProvider =
    AutoDisposeProvider<RunbooksRepository>.internal(
      runbooksRepository,
      name: r'runbooksRepositoryProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$runbooksRepositoryHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef RunbooksRepositoryRef = AutoDisposeProviderRef<RunbooksRepository>;
String _$runbookExecutorHash() => r'ed5ace1faec5f025b7dbf98fedb9bde5e7a532e0';

/// See also [runbookExecutor].
@ProviderFor(runbookExecutor)
final runbookExecutorProvider = AutoDisposeProvider<RunbookExecutor>.internal(
  runbookExecutor,
  name: r'runbookExecutorProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$runbookExecutorHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef RunbookExecutorRef = AutoDisposeProviderRef<RunbookExecutor>;
String _$runbooksNotifierHash() => r'1d3855e1d7ea9500b7c798bd45c09a94ecad9fbd';

/// See also [RunbooksNotifier].
@ProviderFor(RunbooksNotifier)
final runbooksNotifierProvider =
    AutoDisposeAsyncNotifierProvider<
      RunbooksNotifier,
      List<RunbookModel>
    >.internal(
      RunbooksNotifier.new,
      name: r'runbooksNotifierProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$runbooksNotifierHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$RunbooksNotifier = AutoDisposeAsyncNotifier<List<RunbookModel>>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
