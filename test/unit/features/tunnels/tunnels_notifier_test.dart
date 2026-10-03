import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/features/tunnels/domain/models/tunnel_rule_model.dart';
import 'package:shellvibe/features/tunnels/domain/repositories/tunnel_repository.dart';
import 'package:shellvibe/features/tunnels/presentation/providers/tunnels_providers.dart';
import 'package:shellvibe/shared/providers/workspace_provider.dart';

void main() {
  late _FakeTunnelRepository repository;
  late ProviderContainer container;

  setUp(() {
    repository = _FakeTunnelRepository();
    container = ProviderContainer(
      overrides: [
        activeWorkspaceIdProvider.overrideWith(_FakeActiveWorkspace.new),
        tunnelRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    // Keep the autoDispose notifier alive, as the Tunnels screen would.
    container.listen(tunnelsProvider, (_, _) {});
  });

  void switchWorkspace(String id) =>
      (container.read(activeWorkspaceIdProvider.notifier)
              as _FakeActiveWorkspace)
          .set(id);

  test('rules load again after the active workspace resolves', () async {
    // At startup the workspace id reads 'default' until settings load, then
    // resolves to the saved one. That rebuild used to leave the screen on its
    // spinner for good: the notifier survives the rebuild, and a disposed
    // flag set from onDispose made every later load return early.
    repository.complete('default', const []);
    await pumpEventQueue();
    expect(container.read(tunnelsProvider).isLoading, isFalse);

    switchWorkspace('saved');
    container.read(tunnelsProvider);
    await pumpEventQueue();
    expect(container.read(tunnelsProvider).isLoading, isTrue);

    repository.complete('saved', [_rule('a')]);
    await pumpEventQueue();

    final state = container.read(tunnelsProvider);
    expect(state.isLoading, isFalse);
    expect(state.rules.map((r) => r.id), ['a']);
  });

  test('a load from an earlier build cannot overwrite a newer one', () async {
    container.read(tunnelsProvider);
    await pumpEventQueue();

    switchWorkspace('saved');
    container.read(tunnelsProvider);
    await pumpEventQueue();

    repository.complete('saved', [_rule('new')]);
    await pumpEventQueue();
    repository.complete('default', [_rule('stale')]);
    await pumpEventQueue();

    expect(container.read(tunnelsProvider).rules.map((r) => r.id), ['new']);
  });
}

TunnelRuleModel _rule(String id) =>
    TunnelRuleModel(id: id, hostId: 'h', type: 'local', localPort: 8080);

class _FakeActiveWorkspace extends ActiveWorkspaceIdNotifier {
  @override
  String build() => 'default';

  void set(String id) => state = id;
}

/// Answers each workspace query only when the test says so, so the order in
/// which loads finish is under the test's control.
class _FakeTunnelRepository implements TunnelRepository {
  final _pending = <String, Completer<List<TunnelRuleModel>>>{};

  Completer<List<TunnelRuleModel>> _completer(String workspaceId) =>
      _pending.putIfAbsent(workspaceId, Completer.new);

  void complete(String workspaceId, List<TunnelRuleModel> rules) =>
      _completer(workspaceId).complete(rules);

  @override
  Future<List<TunnelRuleModel>> getRulesByWorkspace(String workspaceId) =>
      _completer(workspaceId).future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
