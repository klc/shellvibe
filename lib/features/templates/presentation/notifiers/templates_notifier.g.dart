// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'templates_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(templatesRepository)
final templatesRepositoryProvider = TemplatesRepositoryProvider._();

final class TemplatesRepositoryProvider
    extends
        $FunctionalProvider<
          TemplatesRepository,
          TemplatesRepository,
          TemplatesRepository
        >
    with $Provider<TemplatesRepository> {
  TemplatesRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'templatesRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$templatesRepositoryHash();

  @$internal
  @override
  $ProviderElement<TemplatesRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  TemplatesRepository create(Ref ref) {
    return templatesRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TemplatesRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TemplatesRepository>(value),
    );
  }
}

String _$templatesRepositoryHash() =>
    r'218d192cbd62a8efd0f8d6a149c09df142f1e2b8';

@ProviderFor(templateCapture)
final templateCaptureProvider = TemplateCaptureProvider._();

final class TemplateCaptureProvider
    extends
        $FunctionalProvider<TemplateCapture, TemplateCapture, TemplateCapture>
    with $Provider<TemplateCapture> {
  TemplateCaptureProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'templateCaptureProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$templateCaptureHash();

  @$internal
  @override
  $ProviderElement<TemplateCapture> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  TemplateCapture create(Ref ref) {
    return templateCapture(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TemplateCapture value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TemplateCapture>(value),
    );
  }
}

String _$templateCaptureHash() => r'65d080147e54646627a41404f2eaa5791feca655';

@ProviderFor(templateRunner)
final templateRunnerProvider = TemplateRunnerProvider._();

final class TemplateRunnerProvider
    extends $FunctionalProvider<TemplateRunner, TemplateRunner, TemplateRunner>
    with $Provider<TemplateRunner> {
  TemplateRunnerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'templateRunnerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$templateRunnerHash();

  @$internal
  @override
  $ProviderElement<TemplateRunner> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  TemplateRunner create(Ref ref) {
    return templateRunner(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TemplateRunner value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TemplateRunner>(value),
    );
  }
}

String _$templateRunnerHash() => r'384d3c417b8753f7917e74233cd57eb8041e6fc5';

/// Kept alive deliberately: saving and running a template are fired from
/// toolbars that do not watch this provider, so an auto-disposing notifier
/// would be torn down mid-call and blow up assigning `state` after the await.

@ProviderFor(TemplatesNotifier)
final templatesProvider = TemplatesNotifierProvider._();

/// Kept alive deliberately: saving and running a template are fired from
/// toolbars that do not watch this provider, so an auto-disposing notifier
/// would be torn down mid-call and blow up assigning `state` after the await.
final class TemplatesNotifierProvider
    extends $AsyncNotifierProvider<TemplatesNotifier, List<TemplateModel>> {
  /// Kept alive deliberately: saving and running a template are fired from
  /// toolbars that do not watch this provider, so an auto-disposing notifier
  /// would be torn down mid-call and blow up assigning `state` after the await.
  TemplatesNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'templatesProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$templatesNotifierHash();

  @$internal
  @override
  TemplatesNotifier create() => TemplatesNotifier();
}

String _$templatesNotifierHash() => r'8fa806bde1ef26fc95a93e4c29c9cc099fcd69d6';

/// Kept alive deliberately: saving and running a template are fired from
/// toolbars that do not watch this provider, so an auto-disposing notifier
/// would be torn down mid-call and blow up assigning `state` after the await.

abstract class _$TemplatesNotifier extends $AsyncNotifier<List<TemplateModel>> {
  FutureOr<List<TemplateModel>> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<List<TemplateModel>>, List<TemplateModel>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<List<TemplateModel>>, List<TemplateModel>>,
              AsyncValue<List<TemplateModel>>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
