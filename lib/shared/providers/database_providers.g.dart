// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Provides a single instance of [AppDatabase].

@ProviderFor(appDatabase)
final appDatabaseProvider = AppDatabaseProvider._();

/// Provides a single instance of [AppDatabase].

final class AppDatabaseProvider
    extends $FunctionalProvider<AppDatabase, AppDatabase, AppDatabase>
    with $Provider<AppDatabase> {
  /// Provides a single instance of [AppDatabase].
  AppDatabaseProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appDatabaseProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appDatabaseHash();

  @$internal
  @override
  $ProviderElement<AppDatabase> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  AppDatabase create(Ref ref) {
    return appDatabase(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AppDatabase value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AppDatabase>(value),
    );
  }
}

String _$appDatabaseHash() => r'67f06207fff3a55949c4c4b67200f868a9b6acc8';

/// Auto-disposing provider for [KnownHostsDao].

@ProviderFor(knownHostsDao)
final knownHostsDaoProvider = KnownHostsDaoProvider._();

/// Auto-disposing provider for [KnownHostsDao].

final class KnownHostsDaoProvider
    extends $FunctionalProvider<KnownHostsDao, KnownHostsDao, KnownHostsDao>
    with $Provider<KnownHostsDao> {
  /// Auto-disposing provider for [KnownHostsDao].
  KnownHostsDaoProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'knownHostsDaoProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$knownHostsDaoHash();

  @$internal
  @override
  $ProviderElement<KnownHostsDao> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  KnownHostsDao create(Ref ref) {
    return knownHostsDao(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(KnownHostsDao value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<KnownHostsDao>(value),
    );
  }
}

String _$knownHostsDaoHash() => r'01110c759643efcb98f732ab74133461f49c9ca2';

/// Auto-disposing provider for [HostsDao].

@ProviderFor(hostsDao)
final hostsDaoProvider = HostsDaoProvider._();

/// Auto-disposing provider for [HostsDao].

final class HostsDaoProvider
    extends $FunctionalProvider<HostsDao, HostsDao, HostsDao>
    with $Provider<HostsDao> {
  /// Auto-disposing provider for [HostsDao].
  HostsDaoProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'hostsDaoProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$hostsDaoHash();

  @$internal
  @override
  $ProviderElement<HostsDao> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  HostsDao create(Ref ref) {
    return hostsDao(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(HostsDao value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<HostsDao>(value),
    );
  }
}

String _$hostsDaoHash() => r'0cdd6525a1ccd57c08d2dfcd375d768f664ac1c9';

/// Auto-disposing provider for [IdentitiesDao].

@ProviderFor(identitiesDao)
final identitiesDaoProvider = IdentitiesDaoProvider._();

/// Auto-disposing provider for [IdentitiesDao].

final class IdentitiesDaoProvider
    extends $FunctionalProvider<IdentitiesDao, IdentitiesDao, IdentitiesDao>
    with $Provider<IdentitiesDao> {
  /// Auto-disposing provider for [IdentitiesDao].
  IdentitiesDaoProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'identitiesDaoProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$identitiesDaoHash();

  @$internal
  @override
  $ProviderElement<IdentitiesDao> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  IdentitiesDao create(Ref ref) {
    return identitiesDao(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(IdentitiesDao value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<IdentitiesDao>(value),
    );
  }
}

String _$identitiesDaoHash() => r'72c01c74e79fde565f6c58294383e6db88720e20';

/// Auto-disposing provider for [TunnelsDao].

@ProviderFor(tunnelsDao)
final tunnelsDaoProvider = TunnelsDaoProvider._();

/// Auto-disposing provider for [TunnelsDao].

final class TunnelsDaoProvider
    extends $FunctionalProvider<TunnelsDao, TunnelsDao, TunnelsDao>
    with $Provider<TunnelsDao> {
  /// Auto-disposing provider for [TunnelsDao].
  TunnelsDaoProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'tunnelsDaoProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$tunnelsDaoHash();

  @$internal
  @override
  $ProviderElement<TunnelsDao> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  TunnelsDao create(Ref ref) {
    return tunnelsDao(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TunnelsDao value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TunnelsDao>(value),
    );
  }
}

String _$tunnelsDaoHash() => r'651f29f369e4b6fa8362caa38d51ffa5f901c950';

/// Auto-disposing provider for [SnippetsDao].

@ProviderFor(snippetsDao)
final snippetsDaoProvider = SnippetsDaoProvider._();

/// Auto-disposing provider for [SnippetsDao].

final class SnippetsDaoProvider
    extends $FunctionalProvider<SnippetsDao, SnippetsDao, SnippetsDao>
    with $Provider<SnippetsDao> {
  /// Auto-disposing provider for [SnippetsDao].
  SnippetsDaoProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'snippetsDaoProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$snippetsDaoHash();

  @$internal
  @override
  $ProviderElement<SnippetsDao> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  SnippetsDao create(Ref ref) {
    return snippetsDao(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SnippetsDao value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SnippetsDao>(value),
    );
  }
}

String _$snippetsDaoHash() => r'22691919cce6c9975407eeffd30271524f94b8b3';

/// Auto-disposing provider for [RunbooksDao].

@ProviderFor(runbooksDao)
final runbooksDaoProvider = RunbooksDaoProvider._();

/// Auto-disposing provider for [RunbooksDao].

final class RunbooksDaoProvider
    extends $FunctionalProvider<RunbooksDao, RunbooksDao, RunbooksDao>
    with $Provider<RunbooksDao> {
  /// Auto-disposing provider for [RunbooksDao].
  RunbooksDaoProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'runbooksDaoProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$runbooksDaoHash();

  @$internal
  @override
  $ProviderElement<RunbooksDao> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  RunbooksDao create(Ref ref) {
    return runbooksDao(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RunbooksDao value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RunbooksDao>(value),
    );
  }
}

String _$runbooksDaoHash() => r'59560463966bf8bf51483ce42bee80aa59c87e28';

/// Provider for [EncryptionEngine].

@ProviderFor(encryptionEngine)
final encryptionEngineProvider = EncryptionEngineProvider._();

/// Provider for [EncryptionEngine].

final class EncryptionEngineProvider
    extends
        $FunctionalProvider<
          EncryptionEngine,
          EncryptionEngine,
          EncryptionEngine
        >
    with $Provider<EncryptionEngine> {
  /// Provider for [EncryptionEngine].
  EncryptionEngineProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'encryptionEngineProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$encryptionEngineHash();

  @$internal
  @override
  $ProviderElement<EncryptionEngine> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  EncryptionEngine create(Ref ref) {
    return encryptionEngine(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(EncryptionEngine value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<EncryptionEngine>(value),
    );
  }
}

String _$encryptionEngineHash() => r'0e9c339ef18e10bc1703076e3e2a8e10a8e2b0f8';

/// Provider for [SecureStorageService].

@ProviderFor(secureStorageService)
final secureStorageServiceProvider = SecureStorageServiceProvider._();

/// Provider for [SecureStorageService].

final class SecureStorageServiceProvider
    extends
        $FunctionalProvider<
          SecureStorageService,
          SecureStorageService,
          SecureStorageService
        >
    with $Provider<SecureStorageService> {
  /// Provider for [SecureStorageService].
  SecureStorageServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'secureStorageServiceProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$secureStorageServiceHash();

  @$internal
  @override
  $ProviderElement<SecureStorageService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  SecureStorageService create(Ref ref) {
    return secureStorageService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SecureStorageService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SecureStorageService>(value),
    );
  }
}

String _$secureStorageServiceHash() =>
    r'0295e42b0c2763787b4b230961936eabcd0d0877';
