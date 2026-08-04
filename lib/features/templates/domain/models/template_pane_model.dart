import 'package:flutter/widgets.dart';

import '../../../terminal/domain/models/terminal_tab_session.dart';

/// One tab or split pane inside a saved [TemplateModel].
///
/// Ids are template-local: they are remapped to freshly generated session ids
/// every time the template runs, and never reused as live tab ids.
class TemplatePaneModel {
  final String id;
  final String templateId;

  /// Position in the capture order. Panes are recreated in this order, which is
  /// what reproduces the original left-to-right / top-to-bottom layout.
  final int paneOrder;

  /// Null for a root tab; otherwise the [id] of another pane in the same
  /// template.
  final String? parentPaneId;

  /// Split axis relative to the parent. Null for a root tab.
  final Axis? splitDirection;

  /// Share (0..1) of the split container taken by this pane.
  final double splitRatio;

  final TerminalSessionType sessionType;

  /// Host id for an SSH pane, null for a local shell. Resolved against the host
  /// list at run time — a template never stores connection details or
  /// credentials itself.
  final String? hostId;

  /// Tab title at capture time, used for local shells (an SSH pane is titled
  /// after the host it resolves to).
  final String? title;

  const TemplatePaneModel({
    required this.id,
    required this.templateId,
    required this.paneOrder,
    this.parentPaneId,
    this.splitDirection,
    this.splitRatio = 0.5,
    required this.sessionType,
    this.hostId,
    this.title,
  });

  bool get isRoot => parentPaneId == null;

  TemplatePaneModel copyWith({
    String? id,
    String? templateId,
    int? paneOrder,
    String? parentPaneId,
    Axis? splitDirection,
    double? splitRatio,
    TerminalSessionType? sessionType,
    String? hostId,
    String? title,
  }) {
    return TemplatePaneModel(
      id: id ?? this.id,
      templateId: templateId ?? this.templateId,
      paneOrder: paneOrder ?? this.paneOrder,
      parentPaneId: parentPaneId ?? this.parentPaneId,
      splitDirection: splitDirection ?? this.splitDirection,
      splitRatio: splitRatio ?? this.splitRatio,
      sessionType: sessionType ?? this.sessionType,
      hostId: hostId ?? this.hostId,
      title: title ?? this.title,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'templateId': templateId,
        'paneOrder': paneOrder,
        'parentPaneId': parentPaneId,
        'splitDirection': encodeSplitDirection(splitDirection),
        'splitRatio': splitRatio,
        'sessionType': encodeSessionType(sessionType),
        'hostId': hostId,
        'title': title,
      };

  factory TemplatePaneModel.fromJson(Map<String, dynamic> json) =>
      TemplatePaneModel(
        id: json['id'] as String,
        templateId: json['templateId'] as String,
        paneOrder: json['paneOrder'] as int,
        parentPaneId: json['parentPaneId'] as String?,
        splitDirection: decodeSplitDirection(json['splitDirection'] as String?),
        splitRatio: (json['splitRatio'] as num?)?.toDouble() ?? 0.5,
        sessionType: decodeSessionType(json['sessionType'] as String?),
        hostId: json['hostId'] as String?,
        title: json['title'] as String?,
      );
}

/// Storage encoding for the split axis. `Axis.horizontal` is a side-by-side
/// split, `Axis.vertical` a top/bottom one.
String? encodeSplitDirection(Axis? axis) => switch (axis) {
      Axis.horizontal => 'horizontal',
      Axis.vertical => 'vertical',
      null => null,
    };

Axis? decodeSplitDirection(String? value) => switch (value) {
      'horizontal' => Axis.horizontal,
      'vertical' => Axis.vertical,
      _ => null,
    };

String encodeSessionType(TerminalSessionType type) => switch (type) {
      TerminalSessionType.ssh => 'ssh',
      TerminalSessionType.local => 'local',
    };

/// Unknown values fall back to a local shell rather than throwing, so one bad
/// row cannot make a whole template unreadable.
TerminalSessionType decodeSessionType(String? value) =>
    value == 'ssh' ? TerminalSessionType.ssh : TerminalSessionType.local;
