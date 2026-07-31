// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'hosts_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$hostsRepositoryHash() => r'1deeee168124cf3f6eca8bb9bb1956a705555491';

/// See also [hostsRepository].
@ProviderFor(hostsRepository)
final hostsRepositoryProvider = AutoDisposeProvider<HostsRepository>.internal(
  hostsRepository,
  name: r'hostsRepositoryProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$hostsRepositoryHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef HostsRepositoryRef = AutoDisposeProviderRef<HostsRepository>;
String _$hostsNotifierHash() => r'8a3be61573458ed286bf47974e825c900a5e51e2';

/// See also [HostsNotifier].
@ProviderFor(HostsNotifier)
final hostsNotifierProvider =
    AutoDisposeAsyncNotifierProvider<HostsNotifier, List<HostModel>>.internal(
      HostsNotifier.new,
      name: r'hostsNotifierProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$hostsNotifierHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$HostsNotifier = AutoDisposeAsyncNotifier<List<HostModel>>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
