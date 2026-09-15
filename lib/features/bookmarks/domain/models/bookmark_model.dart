/// What a bookmark points at.
enum BookmarkTargetType { host, template }

/// A starred host or layout, in the order the user put it in.
///
/// One of [hostId] and [templateId] is set and the other is null; [targetType]
/// says which, so callers switch on a value rather than on which field happens
/// to be non-null.
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

  BookmarkTargetType get targetType =>
      hostId != null ? BookmarkTargetType.host : BookmarkTargetType.template;

  /// Id of whatever this points at, whichever kind it is.
  String get targetId => hostId ?? templateId!;

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
