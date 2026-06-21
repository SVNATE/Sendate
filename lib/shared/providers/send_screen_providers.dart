import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Selected files to send — shared across SendScreen and SavedSelectionsSheet.
final selectedFilesProvider = StateProvider<List<PlatformFile>>((ref) => []);

/// Broadcast mode — allow selecting multiple target devices.
final broadcastModeProvider = StateProvider<bool>((ref) => false);

/// Device IDs selected for broadcast send.
final selectedDeviceIdsProvider = StateProvider<Set<String>>((ref) => {});
