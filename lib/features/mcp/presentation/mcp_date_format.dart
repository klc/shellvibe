/// Local-time formatting shared by the MCP settings, activity and audit
/// surfaces. Deliberately tiny and dependency-free so a global date
/// formatter can replace it with a one-line change per call site.
library;

String _two(int v) => v.toString().padLeft(2, '0');

/// `2026-10-14`
String formatMcpDate(DateTime at) {
  final l = at.toLocal();
  return '${l.year}-${_two(l.month)}-${_two(l.day)}';
}

/// `15:04:05`
String formatMcpClock(DateTime at) {
  final l = at.toLocal();
  return '${_two(l.hour)}:${_two(l.minute)}:${_two(l.second)}';
}

/// `2026-10-14 15:04:05`
String formatMcpTimestamp(DateTime at) =>
    '${formatMcpDate(at)} ${formatMcpClock(at)}';
