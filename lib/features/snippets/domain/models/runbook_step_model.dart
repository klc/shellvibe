/// What a run does after a step fails (once its retries are spent).
enum StepFailurePolicy {
  /// The host's run ends at this step. The default, and the only behaviour
  /// before the policy existed.
  stop,

  /// The failure is recorded and the next step runs; the host still ends
  /// `failed`.
  continueRun;

  /// The stored form (`stop` / `continue`), shared by the database and sync.
  String get wireName => this == stop ? 'stop' : 'continue';

  static StepFailurePolicy parse(String? value) =>
      value == 'continue' ? continueRun : stop;
}

/// What a step is.
enum StepKind {
  /// A shell command: the original and default kind.
  command,

  /// Runs a saved snippet; its current code is used when the run happens.
  snippet,

  /// A manual gate with no command: the run waits for a person to continue.
  approval;

  static StepKind parse(String? value) => switch (value) {
    'snippet' => snippet,
    'approval' => approval,
    _ => command,
  };
}

/// Model representing a single step within a Runbook.
class RunbookStepModel {
  final String id;
  final String runbookId;
  final int stepOrder;
  final String command;
  final int expectedExitCode;
  final String? expectedOutputPattern;
  final int timeoutSeconds;
  final StepFailurePolicy onFailure;
  final StepKind kind;

  /// The snippet a [StepKind.snippet] step runs. Null once that snippet is
  /// deleted.
  final String? snippetId;

  /// Extra attempts after the first failure, 0-[maxRetries].
  final int retries;

  static const int maxRetries = 5;

  const RunbookStepModel({
    required this.id,
    required this.runbookId,
    required this.stepOrder,
    required this.command,
    this.expectedExitCode = 0,
    this.expectedOutputPattern,
    this.timeoutSeconds = 30,
    this.onFailure = StepFailurePolicy.stop,
    this.retries = 0,
    this.kind = StepKind.command,
    this.snippetId,
  });

  RunbookStepModel copyWith({
    String? id,
    String? runbookId,
    int? stepOrder,
    String? command,
    int? expectedExitCode,
    String? expectedOutputPattern,
    int? timeoutSeconds,
    StepFailurePolicy? onFailure,
    int? retries,
    StepKind? kind,
    String? snippetId,
    bool clearSnippet = false,
  }) {
    return RunbookStepModel(
      id: id ?? this.id,
      runbookId: runbookId ?? this.runbookId,
      stepOrder: stepOrder ?? this.stepOrder,
      command: command ?? this.command,
      expectedExitCode: expectedExitCode ?? this.expectedExitCode,
      expectedOutputPattern:
          expectedOutputPattern ?? this.expectedOutputPattern,
      timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
      onFailure: onFailure ?? this.onFailure,
      retries: retries ?? this.retries,
      kind: kind ?? this.kind,
      snippetId: clearSnippet ? null : (snippetId ?? this.snippetId),
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
    'onFailure': onFailure.wireName,
    'retries': retries,
    'kind': kind.name,
    'snippetId': snippetId,
  };

  factory RunbookStepModel.fromJson(Map<String, dynamic> json) =>
      RunbookStepModel(
        id: json['id'] as String,
        runbookId: json['runbookId'] as String,
        stepOrder: json['stepOrder'] as int,
        command: json['command'] as String,
        expectedExitCode: (json['expectedExitCode'] as int?) ?? 0,
        expectedOutputPattern: json['expectedOutputPattern'] as String?,
        timeoutSeconds: (json['timeoutSeconds'] as int?) ?? 30,
        onFailure: StepFailurePolicy.parse(json['onFailure'] as String?),
        retries: ((json['retries'] as int?) ?? 0).clamp(0, maxRetries),
        kind: StepKind.parse(json['kind'] as String?),
        snippetId: json['snippetId'] as String?,
      );
}
