// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$appDatabaseHash() => r'5a6430ca855c590aff1350743cd4f617eda201f8';

/// Provides a single instance of [AppDatabase].
///
/// Copied from [appDatabase].
@ProviderFor(appDatabase)
final appDatabaseProvider = Provider<AppDatabase>.internal(
  appDatabase,
  name: r'appDatabaseProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$appDatabaseHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef AppDatabaseRef = ProviderRef<AppDatabase>;
String _$knownHostsDaoHash() => r'a121c97533b0daaae0ec86a4d1f54f93c67db240';

/// Auto-disposing provider for [KnownHostsDao].
///
/// Copied from [knownHostsDao].
@ProviderFor(knownHostsDao)
final knownHostsDaoProvider = AutoDisposeProvider<KnownHostsDao>.internal(
  knownHostsDao,
  name: r'knownHostsDaoProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$knownHostsDaoHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef KnownHostsDaoRef = AutoDisposeProviderRef<KnownHostsDao>;
String _$hostsDaoHash() => r'3b32f9747158c67072fe40769ab25990cfcd0624';

/// Auto-disposing provider for [HostsDao].
///
/// Copied from [hostsDao].
@ProviderFor(hostsDao)
final hostsDaoProvider = AutoDisposeProvider<HostsDao>.internal(
  hostsDao,
  name: r'hostsDaoProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$hostsDaoHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef HostsDaoRef = AutoDisposeProviderRef<HostsDao>;
String _$identitiesDaoHash() => r'ddd5f5e782c1181f08766896e5bc88c79315ee31';

/// Auto-disposing provider for [IdentitiesDao].
///
/// Copied from [identitiesDao].
@ProviderFor(identitiesDao)
final identitiesDaoProvider = AutoDisposeProvider<IdentitiesDao>.internal(
  identitiesDao,
  name: r'identitiesDaoProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$identitiesDaoHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef IdentitiesDaoRef = AutoDisposeProviderRef<IdentitiesDao>;
String _$tunnelsDaoHash() => r'a2aedbd5b24646dc8279dcfaaa2feef6cc285c69';

/// Auto-disposing provider for [TunnelsDao].
///
/// Copied from [tunnelsDao].
@ProviderFor(tunnelsDao)
final tunnelsDaoProvider = AutoDisposeProvider<TunnelsDao>.internal(
  tunnelsDao,
  name: r'tunnelsDaoProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$tunnelsDaoHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef TunnelsDaoRef = AutoDisposeProviderRef<TunnelsDao>;
String _$snippetsDaoHash() => r'1e1317d16e7a3ccce7d94cd3e3222c4557b4e529';

/// Auto-disposing provider for [SnippetsDao].
///
/// Copied from [snippetsDao].
@ProviderFor(snippetsDao)
final snippetsDaoProvider = AutoDisposeProvider<SnippetsDao>.internal(
  snippetsDao,
  name: r'snippetsDaoProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$snippetsDaoHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef SnippetsDaoRef = AutoDisposeProviderRef<SnippetsDao>;
String _$runbooksDaoHash() => r'c87f78f35ed5c54e495a5bb098b6c563e60e3b19';

/// Auto-disposing provider for [RunbooksDao].
///
/// Copied from [runbooksDao].
@ProviderFor(runbooksDao)
final runbooksDaoProvider = AutoDisposeProvider<RunbooksDao>.internal(
  runbooksDao,
  name: r'runbooksDaoProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$runbooksDaoHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef RunbooksDaoRef = AutoDisposeProviderRef<RunbooksDao>;
String _$encryptionEngineHash() => r'58ded91841741bdc73df7d108861ee2238813ac3';

/// Provider for [EncryptionEngine].
///
/// Copied from [encryptionEngine].
@ProviderFor(encryptionEngine)
final encryptionEngineProvider = AutoDisposeProvider<EncryptionEngine>.internal(
  encryptionEngine,
  name: r'encryptionEngineProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$encryptionEngineHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef EncryptionEngineRef = AutoDisposeProviderRef<EncryptionEngine>;
String _$secureStorageServiceHash() =>
    r'28ef5a96de61720fa06a7ba59ceb572a1791b078';

/// Provider for [SecureStorageService].
///
/// Copied from [secureStorageService].
@ProviderFor(secureStorageService)
final secureStorageServiceProvider =
    AutoDisposeProvider<SecureStorageService>.internal(
      secureStorageService,
      name: r'secureStorageServiceProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$secureStorageServiceHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef SecureStorageServiceRef = AutoDisposeProviderRef<SecureStorageService>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
