/// Something that happened in the app that the user may want to hear about
/// while they are not looking at it.
///
/// Kept free of Flutter and of the terminal and tunnel models, so the policy
/// that decides what to do with one is a plain function of these fields.
enum AppAlertKind {
  /// A connected session lost its transport: keep-alive failure, network drop,
  /// server-side kill.
  sessionDropped,

  /// A connected session's shell exited. Ordinary, but worth a line when the
  /// window was not in front, since a long job finishing usually ends this way.
  sessionEnded,

  /// A forward stopped with an error. A user's own Stop never becomes one.
  tunnelFailed,

  /// BEL, rung by a program that wants the user back.
  terminalBell,

  /// OSC 9 or OSC 777 `notify`: a program asking for a notification outright.
  terminalNotification;

  /// Whether the alert reports something going wrong, as opposed to a shell
  /// ending or a program asking for attention. Only failures mark the tray
  /// icon: it is an error state, and a finished job is not an error.
  bool get isFailure => this == sessionDropped || this == tunnelFailed;
}

class AppAlert {
  const AppAlert({
    required this.kind,
    this.tabId,
    this.tabTitle,
    this.ruleId,
    this.subject,
    this.title,
    this.body,
  });

  final AppAlertKind kind;

  /// The tab the alert came from, as the id of the *root* of its pane tree:
  /// that is the one the tab strip selects and the tray focuses.
  final String? tabId;
  final String? tabTitle;

  /// The forward a [AppAlertKind.tunnelFailed] is about.
  final String? ruleId;

  /// What a tunnel is called on screen: host and route.
  final String? subject;

  /// The text a program supplied (OSC title and body) or the error a forward
  /// failed with. Untrusted: it is shaped by whatever is on the other end of
  /// the session.
  final String? title;
  final String? body;
}
