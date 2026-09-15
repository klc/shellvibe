// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'bookmarks_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(bookmarksRepository)
final bookmarksRepositoryProvider = BookmarksRepositoryProvider._();

final class BookmarksRepositoryProvider
    extends
        $FunctionalProvider<
          BookmarksRepository,
          BookmarksRepository,
          BookmarksRepository
        >
    with $Provider<BookmarksRepository> {
  BookmarksRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'bookmarksRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$bookmarksRepositoryHash();

  @$internal
  @override
  $ProviderElement<BookmarksRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  BookmarksRepository create(Ref ref) {
    return bookmarksRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BookmarksRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BookmarksRepository>(value),
    );
  }
}

String _$bookmarksRepositoryHash() =>
    r'f200b358c05aa1f93e005c8542f5f1550de91439';

@ProviderFor(BookmarksNotifier)
final bookmarksProvider = BookmarksNotifierProvider._();

final class BookmarksNotifierProvider
    extends $AsyncNotifierProvider<BookmarksNotifier, List<BookmarkModel>> {
  BookmarksNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'bookmarksProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$bookmarksNotifierHash();

  @$internal
  @override
  BookmarksNotifier create() => BookmarksNotifier();
}

String _$bookmarksNotifierHash() => r'1753c4693e566e00d75f2a2f9ed418d87a75e660';

abstract class _$BookmarksNotifier extends $AsyncNotifier<List<BookmarkModel>> {
  FutureOr<List<BookmarkModel>> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<List<BookmarkModel>>, List<BookmarkModel>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<List<BookmarkModel>>, List<BookmarkModel>>,
              AsyncValue<List<BookmarkModel>>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
