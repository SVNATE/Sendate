import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/utils/logger.dart';

/// Smart Compatibility Engine.
/// Detects and converts incompatible file formats between platforms.
class ConversionService {
  final _log = const AppLogger('Conversion');
  /// Check if a file needs conversion for the target platform
  ConversionNeeded checkCompatibility({
    required String mimeType,
    required String fileName,
    required String targetPlatform,
  }) {
    final ext = fileName.split('.').last.toLowerCase();

    // HEIC/HEIF images → JPEG for non-Apple devices
    if (_isHeicFormat(mimeType, ext) && !_isApplePlatform(targetPlatform)) {
      return ConversionNeeded(
        needed: true,
        from: mimeType,
        to: 'image/jpeg',
        targetExtension: 'jpg',
        description: 'HEIC → JPEG',
      );
    }

    // MOV videos → MP4 for non-Apple devices
    if ((mimeType == 'video/quicktime' || ext == 'mov') &&
        !_isApplePlatform(targetPlatform)) {
      return ConversionNeeded(
        needed: true,
        from: mimeType,
        to: 'video/mp4',
        targetExtension: 'mp4',
        description: 'MOV → MP4 (rename only)',
      );
    }

    // WebP → PNG for Windows (older versions don't support WebP well)
    if ((mimeType == 'image/webp' || ext == 'webp') &&
        targetPlatform == 'windows') {
      return ConversionNeeded(
        needed: true,
        from: mimeType,
        to: 'image/png',
        targetExtension: 'png',
        description: 'WebP → PNG',
      );
    }

    // AVIF → JPEG for broader compatibility
    if (ext == 'avif' && targetPlatform != 'ios' && targetPlatform != 'macos') {
      return ConversionNeeded(
        needed: true,
        from: 'image/avif',
        to: 'image/jpeg',
        targetExtension: 'jpg',
        description: 'AVIF → JPEG',
      );
    }

    return ConversionNeeded(needed: false);
  }

  /// Convert a file. Returns the path to the converted file.
  /// If conversion fails, returns the original path.
  /// Preserves the original filename, only changing the extension.
  Future<String> convertFile({
    required String inputPath,
    required String targetMimeType,
    required String targetExtension,
  }) async {
    try {
      final inputFile = File(inputPath);
      if (!await inputFile.exists()) return inputPath;

      final tempDir = await getTemporaryDirectory();
      final baseName = inputFile.uri.pathSegments.last;
      final nameWithoutExt = baseName.contains('.')
          ? baseName.substring(0, baseName.lastIndexOf('.'))
          : baseName;
      // Keep original name, only change extension
      final outputPath = '${tempDir.path}/$nameWithoutExt.$targetExtension';

      // Image conversions using flutter_image_compress
      if (targetMimeType == 'image/jpeg') {
        final result = await FlutterImageCompress.compressAndGetFile(
          inputPath,
          outputPath,
          format: CompressFormat.jpeg,
          quality: 92,
        );
        if (result != null) return result.path;
      } else if (targetMimeType == 'image/png') {
        final result = await FlutterImageCompress.compressAndGetFile(
          inputPath,
          outputPath,
          format: CompressFormat.png,
          quality: 100,
        );
        if (result != null) return result.path;
      } else if (targetMimeType == 'video/mp4') {
        // Use FFmpeg to remux the container from MOV to MP4 losslessly
        final command = '-y -i "$inputPath" -c copy "$outputPath"';
        final session = await FFmpegKit.execute(command);
        final returnCode = await session.getReturnCode();
        
        if (ReturnCode.isSuccess(returnCode)) {
          return outputPath;
        } else {
          final logs = await session.getLogsAsString();
          _log.debug('FFmpeg remux failed: $logs');
          // If conversion fails, fall through to return original
        }
      }
    } catch (e) {
      _log.debug('File conversion failed for $inputPath: $e');
      // If conversion fails, fall through to return original
    }

    return inputPath;
  }

  /// Convenience: check and convert in one call
  Future<String> autoConvert({
    required String filePath,
    required String mimeType,
    required String fileName,
    required String targetPlatform,
  }) async {
    final check = checkCompatibility(
      mimeType: mimeType,
      fileName: fileName,
      targetPlatform: targetPlatform,
    );

    if (!check.needed) return filePath;

    return convertFile(
      inputPath: filePath,
      targetMimeType: check.to!,
      targetExtension: check.targetExtension!,
    );
  }

  bool _isHeicFormat(String mimeType, String ext) {
    return mimeType == 'image/heic' ||
        mimeType == 'image/heif' ||
        ext == 'heic' ||
        ext == 'heif';
  }

  bool _isApplePlatform(String platform) {
    return platform == 'ios' || platform == 'macos';
  }
}

class ConversionNeeded {
  final bool needed;
  final String? from;
  final String? to;
  final String? targetExtension;
  final String? description;

  ConversionNeeded({
    required this.needed,
    this.from,
    this.to,
    this.targetExtension,
    this.description,
  });
}
