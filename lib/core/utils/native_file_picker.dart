import 'dart:io';

import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart';
import 'package:file_picker/file_picker.dart' as fp;
import '../../shared/models/sendate_file.dart';

class NativeFilePicker {
  static const MethodChannel _channel = MethodChannel('com.svnate.sendate/pick_files');

  static Future<List<SendateFile>?> pickFiles({fp.FileType type = fp.FileType.any}) async {
    if (Platform.isAndroid) {
      try {
        final List<dynamic>? result = await _channel.invokeMethod('pickFiles', {
          'type': type.name, // Pass type to native if needed in future
        });
        if (result == null) return null;

        return result.map((item) {
          final map = Map<String, dynamic>.from(item as Map);
          return SendateFile(
            name: map['name'] as String,
            size: (map['size'] as num).toInt(),
            path: map['uri'] as String, // on Android this is a content:// URI
          );
        }).toList();
      } catch (e) {
        // CANCELED or ERROR
        return null;
      }
    } else {
      // For iOS, if they specifically want images or videos (Photos app), we must use file_picker
      if (Platform.isIOS && (type == fp.FileType.image || type == fp.FileType.video || type == fp.FileType.media)) {
        final result = await fp.FilePicker.platform.pickFiles(
          type: type,
          allowMultiple: true,
        );
        if (result == null || result.files.isEmpty) return null;
        
        return result.files.map((file) => SendateFile(
          name: file.name,
          size: file.size,
          path: file.path ?? '',
        )).toList();
      }

      // For iOS, macOS, Windows, Linux (files), file_selector is fast and doesn't copy files aggressively
      final result = await openFiles();
      if (result.isEmpty) return null;

      final List<SendateFile> files = [];
      for (final xFile in result) {
        final length = await xFile.length();
        files.add(SendateFile(
          name: xFile.name,
          size: length,
          path: xFile.path,
        ));
      }
      return files;
    }
  }
}
