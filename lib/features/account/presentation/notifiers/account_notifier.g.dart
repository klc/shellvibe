// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'account_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Single owner of the account session.
///
/// `keepAlive` because the API client built here holds the `401` callback that
/// writes back into this notifier; a disposed instance would leave a live
/// client pointing at nothing.
///
/// Signing in is never required. Every code path here treats "no account" as a
/// normal resting state, not an error: Local Device Link, SSH, the vault and
/// the terminal all work without one.

@ProviderFor(AccountNotifier)
final accountProvider = AccountNotifierProvider._();

/// Single owner of the account session.
///
/// `keepAlive` because the API client built here holds the `401` callback that
/// writes back into this notifier; a disposed instance would leave a live
/// client pointing at nothing.
///
/// Signing in is never required. Every code path here treats "no account" as a
/// normal resting state, not an error: Local Device Link, SSH, the vault and
/// the terminal all work without one.
final class AccountNotifierProvider
    extends $AsyncNotifierProvider<AccountNotifier, AccountState> {
  /// Single owner of the account session.
  ///
  /// `keepAlive` because the API client built here holds the `401` callback that
  /// writes back into this notifier; a disposed instance would leave a live
  /// client pointing at nothing.
  ///
  /// Signing in is never required. Every code path here treats "no account" as a
  /// normal resting state, not an error: Local Device Link, SSH, the vault and
  /// the terminal all work without one.
  AccountNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'accountProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$accountNotifierHash();

  @$internal
  @override
  AccountNotifier create() => AccountNotifier();
}

String _$accountNotifierHash() => r'9c22592331980be4e4d5764ea67d17dfc7619ad4';

/// Single owner of the account session.
///
/// `keepAlive` because the API client built here holds the `401` callback that
/// writes back into this notifier; a disposed instance would leave a live
/// client pointing at nothing.
///
/// Signing in is never required. Every code path here treats "no account" as a
/// normal resting state, not an error: Local Device Link, SSH, the vault and
/// the terminal all work without one.

abstract class _$AccountNotifier extends $AsyncNotifier<AccountState> {
  FutureOr<AccountState> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<AccountState>, AccountState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<AccountState>, AccountState>,
              AsyncValue<AccountState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// The API client of the current session, for feature repositories.
///
/// Watching this rather than constructing an [ApiClient] per feature keeps one
/// token source and one `401` handler in the app.

@ProviderFor(sessionApiClient)
final sessionApiClientProvider = SessionApiClientProvider._();

/// The API client of the current session, for feature repositories.
///
/// Watching this rather than constructing an [ApiClient] per feature keeps one
/// token source and one `401` handler in the app.

final class SessionApiClientProvider
    extends
        $FunctionalProvider<
          AsyncValue<ApiClient>,
          ApiClient,
          FutureOr<ApiClient>
        >
    with $FutureModifier<ApiClient>, $FutureProvider<ApiClient> {
  /// The API client of the current session, for feature repositories.
  ///
  /// Watching this rather than constructing an [ApiClient] per feature keeps one
  /// token source and one `401` handler in the app.
  SessionApiClientProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'sessionApiClientProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$sessionApiClientHash();

  @$internal
  @override
  $FutureProviderElement<ApiClient> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<ApiClient> create(Ref ref) {
    return sessionApiClient(ref);
  }
}

String _$sessionApiClientHash() => r'a50c6aa3adbcecc8697802b13d816c9ffab283d6';
