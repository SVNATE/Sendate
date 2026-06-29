import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/sendate_file.dart';

/// Selected files to send — shared across SendScreen and SavedSelectionsSheet.
final selectedFilesProvider = StateProvider<List<SendateFile>>((ref) => []);

/// Broadcast mode — allow selecting multiple target devices.
final broadcastModeProvider = StateProvider<bool>((ref) => false);

/// Device IDs selected for broadcast send.
final selectedDeviceIdsProvider = StateProvider<Set<String>>((ref) => {});
