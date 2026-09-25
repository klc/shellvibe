import '../../domain/models/host_model.dart';

/// Whether [host] can carry an SFTP session.
///
/// Local hosts have no SSH transport, so file transfer is hidden rather than
/// offered and then failing at connect time.
bool hostSupportsFileTransfer(HostModel host) => host.protocol != 'local';

/// Pseudo-group selections that sit above the real groups in the column.
enum HostFilter { all, connected, favorites, ungrouped }
