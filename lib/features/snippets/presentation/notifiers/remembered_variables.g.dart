// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'remembered_variables.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The last non-secret values typed into a variable prompt, by what was run
/// (`runbook:<id>`, `snippet:<id>`) and then by variable name, so the next run
/// of the same thing starts from them.
///
/// Memory only, for this session: nothing here is ever written to disk, and a
/// secret is never put in at all (the dialog does not pass secrets in, and
/// [remember] would not know to tell them apart, so the caller filters).

@ProviderFor(RememberedVariables)
final rememberedVariablesProvider = RememberedVariablesProvider._();

/// The last non-secret values typed into a variable prompt, by what was run
/// (`runbook:<id>`, `snippet:<id>`) and then by variable name, so the next run
/// of the same thing starts from them.
///
/// Memory only, for this session: nothing here is ever written to disk, and a
/// secret is never put in at all (the dialog does not pass secrets in, and
/// [remember] would not know to tell them apart, so the caller filters).
final class RememberedVariablesProvider
    extends
        $NotifierProvider<
          RememberedVariables,
          Map<String, Map<String, String>>
        > {
  /// The last non-secret values typed into a variable prompt, by what was run
  /// (`runbook:<id>`, `snippet:<id>`) and then by variable name, so the next run
  /// of the same thing starts from them.
  ///
  /// Memory only, for this session: nothing here is ever written to disk, and a
  /// secret is never put in at all (the dialog does not pass secrets in, and
  /// [remember] would not know to tell them apart, so the caller filters).
  RememberedVariablesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'rememberedVariablesProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$rememberedVariablesHash();

  @$internal
  @override
  RememberedVariables create() => RememberedVariables();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Map<String, Map<String, String>> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Map<String, Map<String, String>>>(
        value,
      ),
    );
  }
}

String _$rememberedVariablesHash() =>
    r'2e82ee4d007d9c461a0075a278cdf101c012731c';

/// The last non-secret values typed into a variable prompt, by what was run
/// (`runbook:<id>`, `snippet:<id>`) and then by variable name, so the next run
/// of the same thing starts from them.
///
/// Memory only, for this session: nothing here is ever written to disk, and a
/// secret is never put in at all (the dialog does not pass secrets in, and
/// [remember] would not know to tell them apart, so the caller filters).

abstract class _$RememberedVariables
    extends $Notifier<Map<String, Map<String, String>>> {
  Map<String, Map<String, String>> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              Map<String, Map<String, String>>,
              Map<String, Map<String, String>>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                Map<String, Map<String, String>>,
                Map<String, Map<String, String>>
              >,
              Map<String, Map<String, String>>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
