import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:share_handler/share_handler.dart';

/// Receives files shared TO Sendate from other apps / OS share sheets.
///
/// Platform support:
///   Android / Android TV — ACTION_SEND / ACTION_SEND_MULTIPLE intent (share_handler)
///   iOS                  — Share Extension via App Group (share_handler)
///   macOS                — application(_:open:) file drag / Open With (MethodChannel)
///   Windows              — argv file paths passed by the shell (MethodChannel)
///   Linux                — argv file paths from .desktop Exec=%F (MethodChannel)
class IncomingShareService {
  IncomingShareService._();
  static final instance = IncomingShareService._();

  static const _desktopChannel = MethodChannel('com.svnate.sendate/open_files');

  /// Called with resolved absolute file paths whenever the OS shares files to the app.
  void Function(List<String> filePaths)? onFilesShared;

  Future<void> init() async {
    if (Platform.isAndroid || Platform.isIOS) {
      await _initMobile();
    } else {
      await _initDesktop();
    }
  }

  // ─── Mobile (Android + iOS via share_handler) ──────────────────────────────

  Future<void> _initMobile() async {
    try {
      final handler = ShareHandler.instance;

      // Handle share that launched the app cold
      final initial = await handler.getInitialSharedMedia();
      if (initial != null) _dispatchSharedMedia(initial);

      // Handle shares while app is running
      handler.sharedMediaStream.listen(
        _dispatchSharedMedia,
        onError: (e) => debugPrint('[IncomingShare] Stream error: $e'),
      );
    } catch (e) {
      debugPrint('[IncomingShare] share_handler init failed: $e');
    }
  }

  void _dispatchSharedMedia(SharedMedia media) {
    final paths = <String>[];

    // Files
    final attachments = media.attachments;
    if (attachments != null) {
      for (final att in attachments) {
        if (att != null && att.path.isNotEmpty) paths.add(att.path);
      }
    }

    // Text shared as a file is not handled here — Sendate is a file-sharing app
    if (paths.isNotEmpty) {
      debugPrint('[IncomingShare] Received ${paths.length} file(s) from share sheet');
      onFilesShared?.call(paths);
    }
  }

  // ─── Desktop (macOS / Windows / Linux via MethodChannel) ──────────────────

  Future<void> _initDesktop() async {
    _desktopChannel.setMethodCallHandler((call) async {
      if (call.method == 'openFiles') {
        final raw = call.arguments;
        List<String> paths = [];
        if (raw is List) {
          paths = raw.whereType<String>().toList();
        } else if (raw is String && raw.isNotEmpty) {
          paths = [raw];
        }
        if (paths.isNotEmpty) {
          debugPrint('[IncomingShare] Desktop openFiles: $paths');
          onFilesShared?.call(paths);
        }
      }
      return null;
    });
  }
}
