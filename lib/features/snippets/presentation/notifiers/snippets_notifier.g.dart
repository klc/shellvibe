// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'snippets_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$snippetsRepositoryHash() =>
    r'c1845fbbc75e9d6eb174d30fadc7ef53e5a6ade8';

/// See also [snippetsRepository].
@ProviderFor(snippetsRepository)
final snippetsRepositoryProvider =
    AutoDisposeProvider<SnippetsRepository>.internal(
      snippetsRepository,
      name: r'snippetsRepositoryProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$snippetsRepositoryHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef SnippetsRepositoryRef = AutoDisposeProviderRef<SnippetsRepository>;
String _$snippetsNotifierHash() => r'f51531558f8f3d3fbbee3970668f6632bdd1d99f';

/// See also [SnippetsNotifier].
@ProviderFor(SnippetsNotifier)
final snippetsNotifierProvider =
    AutoDisposeAsyncNotifierProvider<
      SnippetsNotifier,
      List<SnippetModel>
    >.internal(
      SnippetsNotifier.new,
      name: r'snippetsNotifierProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$snippetsNotifierHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$SnippetsNotifier = AutoDisposeAsyncNotifier<List<SnippetModel>>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
