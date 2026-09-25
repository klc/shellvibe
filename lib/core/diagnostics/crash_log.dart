import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// The local crash log, and which part of it the user has already been asked
/// about.
///
/// Crashes stay on the machine. Nothing here sends anything: reporting one is
/// the user opening a GitHub issue themselves, from a report they have read
/// first (see [CrashReport]). What this class adds over a bare append is the
/// memory of how far the log has been offered, so a crash is brought up once
/// on the next launch rather than on every launch after it.
final class CrashLog {
  /// Directory holding `crash.log` and its offset marker.
  final Directory directory;

  const CrashLog(this.directory);

  /// The log in the per-user application-support directory.
  static Future<CrashLog> open() async =>
      CrashLog(await getApplicationSupportDirectory());

  File get _log => File(p.join(directory.path, 'crash.log'));

  /// Byte length of the log the last time it was offered to the user.
  File get _offered => File(p.join(directory.path, 'crash.log.offered'));

  /// Appends one record. Never throws: it runs inside the error handlers, and
  /// an exception thrown from there has nowhere left to go.
  Future<void> append(String tag, Object error, StackTrace? stack) async {
    try {
      final entry = StringBuffer()
        ..writeln('--- ${DateTime.now().toIso8601String()} [$tag] ---')
        ..writeln(error.toString())
        ..writeln(stack?.toString() ?? '');
      await _log.writeAsString(
        entry.toString(),
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {
      // Logging must never throw back into the error handler.
    }
  }

  /// Everything written since the log was last offered, or null when nothing
  /// new has been written.
  Future<String?> readUnoffered() async {
    try {
      if (!await _log.exists()) return null;
      final bytes = await _log.readAsBytes();
      var from = await _readOffset();
      // A log that shrank was deleted or truncated by hand; what is in it now
      // has not been offered.
      if (from > bytes.length) from = 0;
      if (from == bytes.length) return null;

      final text = utf8
          .decode(bytes.sublist(from), allowMalformed: true)
          .trim();
      return text.isEmpty ? null : text;
    } catch (_) {
      return null;
    }
  }

  /// The newest [maxChars] of the whole log, offered or not, or null when
  /// there is no log.
  Future<String?> readTail({int maxChars = 6000}) async {
    try {
      if (!await _log.exists()) return null;
      final text = (await _log.readAsString()).trim();
      if (text.isEmpty) return null;
      return text.length <= maxChars
          ? text
          : text.substring(text.length - maxChars);
    } catch (_) {
      return null;
    }
  }

  /// Records that everything in the log so far has been offered.
  Future<void> markOffered() async {
    try {
      final length = await _log.exists() ? await _log.length() : 0;
      await _offered.writeAsString('$length', flush: true);
    } catch (_) {
      // Worst case the same crash is offered once more.
    }
  }

  Future<int> _readOffset() async {
    if (!await _offered.exists()) return 0;
    return int.tryParse((await _offered.readAsString()).trim()) ?? 0;
  }
}

/// A crash report the user reads, edits and files themselves.
///
/// A stack trace from a terminal client can carry a host name, a user name,
/// an address or a path, so the obvious ones are replaced before the user
/// sees the report -- and the issue form GitHub opens is still editable
/// before anything is posted. Nothing is sent by the app.
final class CrashReport {
  /// Repository that receives the issue.
  static const String repository = 'klc/shellvibe';

  /// GitHub rejects longer URLs; this leaves room for the title and labels.
  static const int maxUrlLength = 7000;

  final String appVersion;
  final String platform;
  final String osVersion;

  /// Scrubbed log text, or null for a report with no log.
  final String? log;

  const CrashReport({
    required this.appVersion,
    required this.platform,
    required this.osVersion,
    this.log,
  });

  /// Builds a report from raw log text, scrubbing it.
  factory CrashReport.fromLog({
    required String appVersion,
    required String platform,
    required String osVersion,
    String? rawLog,
    String? homeDirectory,
  }) => CrashReport(
    appVersion: appVersion,
    platform: platform,
    osVersion: scrub(osVersion, homeDirectory: homeDirectory),
    log: rawLog == null ? null : scrub(rawLog, homeDirectory: homeDirectory),
  );

  /// Issue title: the first line of the newest error, or a generic one.
  String get title {
    final text = log;
    if (text == null) return 'Problem report';

    final lines = text.split('\n');
    final header = lines.lastIndexWhere((l) => l.startsWith('--- '));
    final error = lines
        .skip(header + 1)
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => '');
    if (error.isEmpty) return 'Crash report';

    return error.length <= 80 ? error : '${error.substring(0, 77)}...';
  }

  /// Markdown body, with the log cut to its newest [logChars] characters.
  String body({int? logChars}) {
    final buffer = StringBuffer()
      ..writeln('### What happened')
      ..writeln()
      ..writeln('<!-- What were you doing when this went wrong? -->')
      ..writeln()
      ..writeln('### Build')
      ..writeln()
      ..writeln('ShellVibe $appVersion · $platform · $osVersion');

    final text = log;
    if (text != null) {
      final cut = logChars == null || text.length <= logChars
          ? text
          : '[… earlier lines cut …]\n'
                '${text.substring(text.length - logChars)}';
      buffer
        ..writeln()
        ..writeln('### Error log')
        ..writeln()
        ..writeln('```text')
        ..writeln(cut)
        ..writeln('```');
    }
    return buffer.toString();
  }

  /// The new-issue URL, prefilled, with the log trimmed until it fits.
  Uri issueUri() {
    int? logChars;
    while (true) {
      final uri = Uri.https('github.com', '/$repository/issues/new', {
        'title': title,
        'body': body(logChars: logChars),
        'labels': 'bug',
      });
      final length = uri.toString().length;
      if (length <= maxUrlLength || (logChars ?? 1) <= 0) return uri;

      final current = logChars ?? log?.length ?? 0;
      logChars = current * 3 ~/ 4;
    }
  }

  static final RegExp _homePath = RegExp(
    r'(/Users/|/home/|[A-Za-z]:\\Users\\)[^/\\\s:]+',
  );
  static final RegExp _userAtHost = RegExp(r'[\w.+-]+@[\w-]+(?:\.[\w-]+)*');
  static final RegExp _ipv4 = RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}\b');
  // Four or more groups, or a `::` elision: a timestamp's `10:00:00` and a
  // stack frame's `file.dart:12:5` stay as they are.
  static final RegExp _ipv6 = RegExp(
    r'\b(?:[0-9A-Fa-f]{1,4}:){3,7}[0-9A-Fa-f]{1,4}\b|'
    r'\b(?:[0-9A-Fa-f]{1,4}:)+:(?:[0-9A-Fa-f]{1,4}(?::[0-9A-Fa-f]{1,4})*)?'
    r'|::1\b',
  );

  /// Replaces the home directory, `user@host` pairs and IP addresses.
  ///
  /// Not a guarantee. A bare host name looks like any other word, which is
  /// why the user reads the report before it goes anywhere.
  static String scrub(String text, {String? homeDirectory}) {
    var out = text;
    if (homeDirectory != null && homeDirectory.length > 1) {
      out = out.replaceAll(homeDirectory, '~');
    }
    return out
        .replaceAll(_homePath, '~')
        .replaceAll(_userAtHost, '<user@host>')
        .replaceAll(_ipv6, '<ip>')
        .replaceAll(_ipv4, '<ip>');
  }
}
