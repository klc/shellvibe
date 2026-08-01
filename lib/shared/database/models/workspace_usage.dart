/// Number of records owned by a workspace.
class WorkspaceUsage {
  final int hosts;
  final int groups;
  final int identities;
  final int tunnels;
  final int snippets;
  final int runbooks;

  const WorkspaceUsage({
    this.hosts = 0,
    this.groups = 0,
    this.identities = 0,
    this.tunnels = 0,
    this.snippets = 0,
    this.runbooks = 0,
  });

  int get total => hosts + groups + identities + tunnels + snippets + runbooks;
}
