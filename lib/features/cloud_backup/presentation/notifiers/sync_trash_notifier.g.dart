// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sync_trash_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The deleted rows this device can still put back.
///
/// Exists because automatic sync carries a mistaken delete to every other
/// device in seconds. Without a trash, the window where someone could undo it
/// closes before they have finished reading the confirmation dialog.
///
/// Local, always. It is never uploaded and produces no operation of its own; a
/// row put back here goes out as an ordinary upsert, which is what the other
/// devices need to see.

@ProviderFor(SyncTrashNotifier)
final syncTrashProvider = SyncTrashNotifierProvider._();

/// The deleted rows this device can still put back.
///
/// Exists because automatic sync carries a mistaken delete to every other
/// device in seconds. Without a trash, the window where someone could undo it
/// closes before they have finished reading the confirmation dialog.
///
/// Local, always. It is never uploaded and produces no operation of its own; a
/// row put back here goes out as an ordinary upsert, which is what the other
/// devices need to see.
final class SyncTrashNotifierProvider
    extends $AsyncNotifierProvider<SyncTrashNotifier, List<TrashedRow>> {
  /// The deleted rows this device can still put back.
  ///
  /// Exists because automatic sync carries a mistaken delete to every other
  /// device in seconds. Without a trash, the window where someone could undo it
  /// closes before they have finished reading the confirmation dialog.
  ///
  /// Local, always. It is never uploaded and produces no operation of its own; a
  /// row put back here goes out as an ordinary upsert, which is what the other
  /// devices need to see.
  SyncTrashNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'syncTrashProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$syncTrashNotifierHash();

  @$internal
  @override
  SyncTrashNotifier create() => SyncTrashNotifier();
}

String _$syncTrashNotifierHash() => r'0501a50268e5bd0274f597a501b39dc9edd3f7a7';

/// The deleted rows this device can still put back.
///
/// Exists because automatic sync carries a mistaken delete to every other
/// device in seconds. Without a trash, the window where someone could undo it
/// closes before they have finished reading the confirmation dialog.
///
/// Local, always. It is never uploaded and produces no operation of its own; a
/// row put back here goes out as an ordinary upsert, which is what the other
/// devices need to see.

abstract class _$SyncTrashNotifier extends $AsyncNotifier<List<TrashedRow>> {
  FutureOr<List<TrashedRow>> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<List<TrashedRow>>, List<TrashedRow>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<List<TrashedRow>>, List<TrashedRow>>,
              AsyncValue<List<TrashedRow>>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
