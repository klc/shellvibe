// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'host_groups_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(HostGroupsNotifier)
final hostGroupsProvider = HostGroupsNotifierProvider._();

final class HostGroupsNotifierProvider
    extends $AsyncNotifierProvider<HostGroupsNotifier, List<HostGroupModel>> {
  HostGroupsNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'hostGroupsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$hostGroupsNotifierHash();

  @$internal
  @override
  HostGroupsNotifier create() => HostGroupsNotifier();
}

String _$hostGroupsNotifierHash() =>
    r'3fbf3439b27e44409dd2fdb1d142b1d0c24ee3e6';

abstract class _$HostGroupsNotifier
    extends $AsyncNotifier<List<HostGroupModel>> {
  FutureOr<List<HostGroupModel>> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<AsyncValue<List<HostGroupModel>>, List<HostGroupModel>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<List<HostGroupModel>>,
                List<HostGroupModel>
              >,
              AsyncValue<List<HostGroupModel>>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
