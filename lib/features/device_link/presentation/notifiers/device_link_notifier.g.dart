// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'device_link_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Owns saved-pairing reconnects and their mobile terminal controllers.

@ProviderFor(DeviceLinkNotifier)
final deviceLinkProvider = DeviceLinkNotifierProvider._();

/// Owns saved-pairing reconnects and their mobile terminal controllers.
final class DeviceLinkNotifierProvider
    extends $NotifierProvider<DeviceLinkNotifier, DeviceLinkState> {
  /// Owns saved-pairing reconnects and their mobile terminal controllers.
  DeviceLinkNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'deviceLinkProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$deviceLinkNotifierHash();

  @$internal
  @override
  DeviceLinkNotifier create() => DeviceLinkNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DeviceLinkState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DeviceLinkState>(value),
    );
  }
}

String _$deviceLinkNotifierHash() =>
    r'e9901e99346b355474e0a60ffbb03fe13fbbd735';

/// Owns saved-pairing reconnects and their mobile terminal controllers.

abstract class _$DeviceLinkNotifier extends $Notifier<DeviceLinkState> {
  DeviceLinkState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<DeviceLinkState, DeviceLinkState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<DeviceLinkState, DeviceLinkState>,
              DeviceLinkState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
