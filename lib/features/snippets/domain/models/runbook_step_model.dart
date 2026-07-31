/// Model representing a single step within a Runbook.
class RunbookStepModel {
  final String id;
  final String runbookId;
  final int stepOrder;
  final String command;
  final int expectedExitCode;
  final String? expectedOutputPattern;
  final int timeoutSeconds;

  const RunbookStepModel({
    required this.id,
    required this.runbookId,
    required this.stepOrder,
    required this.command,
    this.expectedExitCode = 0,
    this.expectedOutputPattern,
    this.timeoutSeconds = 30,
  });

  RunbookStepModel copyWith({
    String? id,
    String? runbookId,
    int? stepOrder,
    String? command,
    int? expectedExitCode,
    String? expectedOutputPattern,
    int? timeoutSeconds,
  }) {
    return RunbookStepModel(
      id: id ?? this.id,
      runbookId: runbookId ?? this.runbookId,
      stepOrder: stepOrder ?? this.stepOrder,
      command: command ?? this.command,
      expectedExitCode: expectedExitCode ?? this.expectedExitCode,
      expectedOutputPattern: expectedOutputPattern ?? this.expectedOutputPattern,
      timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'runbookId': runbookId,
        'stepOrder': stepOrder,
        'command': command,
        'expectedExitCode': expectedExitCode,
        'expectedOutputPattern': expectedOutputPattern,
        'timeoutSeconds': timeoutSeconds,
      };

  factory RunbookStepModel.fromJson(Map<String, dynamic> json) => RunbookStepModel(
        id: json['id'] as String,
        runbookId: json['runbookId'] as String,
        stepOrder: json['stepOrder'] as int,
        command: json['command'] as String,
        expectedExitCode: (json['expectedExitCode'] as int?) ?? 0,
        expectedOutputPattern: json['expectedOutputPattern'] as String?,
        timeoutSeconds: (json['timeoutSeconds'] as int?) ?? 30,
      );
}
