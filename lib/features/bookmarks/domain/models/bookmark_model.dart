/// A starred host or layout, in the order the user put it in.
///
/// One of [hostId] and [templateId] is set and the other is null.
class BookmarkModel {
  final String id;
  final String workspaceId;
  final String? hostId;
  final String? templateId;
  final int position;
  final DateTime createdAt;

  const BookmarkModel({
    required this.id,
    required this.workspaceId,
    this.hostId,
    this.templateId,
    this.position = 0,
    required this.createdAt,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BookmarkModel &&
          id == other.id &&
          workspaceId == other.workspaceId &&
          hostId == other.hostId &&
          templateId == other.templateId &&
          position == other.position &&
          createdAt == other.createdAt;

  @override
  int get hashCode => Object.hash(
    id,
    workspaceId,
    hostId,
    templateId,
    position,
    createdAt,
  );
}
