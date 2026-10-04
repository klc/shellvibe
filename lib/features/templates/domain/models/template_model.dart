import 'template_pane_model.dart';

/// A saved terminal layout: the tabs and split panes that were open when the
/// template was captured.
class TemplateModel {
  final String id;
  final String workspaceId;
  final String name;
  final String? description;

  /// Panes in capture order. Root tabs and split panes live in the same flat
  /// list, mirroring how the terminal itself stores them; the tree is expressed
  /// through [TemplatePaneModel.parentPaneId].
  final List<TemplatePaneModel> panes;

  /// [TemplatePaneModel.id] of the pane that was focused at capture time.
  final String? activePaneId;

  final DateTime createdAt;

  /// Runbook started in the background on the template's SSH hosts after the
  /// layout has opened, or null.
  final String? onOpenRunbookId;

  /// Whether to ask before running [onOpenRunbookId].
  final bool onOpenConfirm;

  const TemplateModel({
    required this.id,
    required this.workspaceId,
    required this.name,
    this.description,
    this.panes = const [],
    this.activePaneId,
    required this.createdAt,
    this.onOpenRunbookId,
    this.onOpenConfirm = true,
  });

  /// Root tabs, in capture order.
  List<TemplatePaneModel> get rootPanes =>
      panes.where((pane) => pane.isRoot).toList();

  int get tabCount => rootPanes.length;

  TemplateModel copyWith({
    String? id,
    String? workspaceId,
    String? name,
    String? description,
    List<TemplatePaneModel>? panes,
    String? activePaneId,
    DateTime? createdAt,
    String? onOpenRunbookId,
    bool clearOnOpenRunbook = false,
    bool? onOpenConfirm,
  }) {
    return TemplateModel(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      name: name ?? this.name,
      description: description ?? this.description,
      panes: panes ?? this.panes,
      activePaneId: activePaneId ?? this.activePaneId,
      createdAt: createdAt ?? this.createdAt,
      onOpenRunbookId: clearOnOpenRunbook
          ? null
          : (onOpenRunbookId ?? this.onOpenRunbookId),
      onOpenConfirm: onOpenConfirm ?? this.onOpenConfirm,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'workspaceId': workspaceId,
        'name': name,
        'description': description,
        'panes': panes.map((p) => p.toJson()).toList(),
        'activePaneId': activePaneId,
        'createdAt': createdAt.toIso8601String(),
        'onOpenRunbookId': onOpenRunbookId,
        'onOpenConfirm': onOpenConfirm,
      };

  factory TemplateModel.fromJson(Map<String, dynamic> json) => TemplateModel(
        id: json['id'] as String,
        workspaceId: json['workspaceId'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        panes: (json['panes'] as List<dynamic>?)
                ?.map((e) =>
                    TemplatePaneModel.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        activePaneId: json['activePaneId'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
        onOpenRunbookId: json['onOpenRunbookId'] as String?,
        onOpenConfirm: json['onOpenConfirm'] as bool? ?? true,
      );
}

/// Whether [template] matches a free-text search: its name or description
/// contains [query], case-insensitively. An empty query matches everything.
bool templateMatchesQuery(TemplateModel template, String query) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return true;
  return template.name.toLowerCase().contains(needle) ||
      (template.description?.toLowerCase().contains(needle) ?? false);
}

/// One-line summary of what a template will open.
String templateSummary(TemplateModel template) {
  final tabs = template.tabCount;
  final splits = template.panes.length - tabs;
  final tabPart = '$tabs ${tabs == 1 ? 'tab' : 'tabs'}';
  if (splits == 0) return tabPart;
  return '$tabPart · $splits ${splits == 1 ? 'split pane' : 'split panes'}';
}
