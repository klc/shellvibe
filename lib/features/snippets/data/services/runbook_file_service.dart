import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/utils/platform_capabilities.dart';

part 'runbook_file_service.g.dart';

/// Reads and writes runbook Markdown files through the platform's file
/// dialogs. A seam: widget tests replace it, since a native dialog cannot be
/// driven from one.
class RunbookFileService {
  const RunbookFileService();

  static const _markdown = XTypeGroup(
    label: 'Markdown',
    extensions: <String>['md', 'markdown'],
    uniformTypeIdentifiers: <String>['net.daringfireball.markdown'],
    mimeTypes: <String>['text/markdown'],
  );

  /// Whether this platform can save through a dialog. A phone cannot (there is
  /// no save location to pick), and the caller copies to the clipboard
  /// instead.
  bool get canSave => !isMobilePlatform;

  /// Saves [content] where the user chooses. Returns the path, or null when
  /// they cancelled.
  Future<String?> saveMarkdown(String suggestedName, String content) async {
    final location = await getSaveLocation(
      suggestedName: suggestedName,
      acceptedTypeGroups: const <XTypeGroup>[_markdown],
    );
    if (location == null) return null;
    final file = XFile.fromData(
      utf8.encode(content),
      name: suggestedName,
      mimeType: 'text/markdown',
    );
    await file.saveTo(location.path);
    return location.path;
  }

  /// The text of a Markdown file the user picks, or null when they cancelled.
  Future<String?> pickMarkdown() async {
    final file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[_markdown],
    );
    return file?.readAsString();
  }
}

@riverpod
RunbookFileService runbookFileService(Ref ref) => const RunbookFileService();
