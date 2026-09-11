// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ssh_config_import_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Provides the SSH config import service bound to the app database and vault.

@ProviderFor(sshConfigImportService)
final sshConfigImportServiceProvider = SshConfigImportServiceProvider._();

/// Provides the SSH config import service bound to the app database and vault.

final class SshConfigImportServiceProvider
    extends
        $FunctionalProvider<
          SshConfigImportService,
          SshConfigImportService,
          SshConfigImportService
        >
    with $Provider<SshConfigImportService> {
  /// Provides the SSH config import service bound to the app database and vault.
  SshConfigImportServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'sshConfigImportServiceProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$sshConfigImportServiceHash();

  @$internal
  @override
  $ProviderElement<SshConfigImportService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  SshConfigImportService create(Ref ref) {
    return sshConfigImportService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SshConfigImportService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SshConfigImportService>(value),
    );
  }
}

String _$sshConfigImportServiceHash() =>
    r'8314acb6ebb79a3c229b8d4424b9b83b0851c1ee';
