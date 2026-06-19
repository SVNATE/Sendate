import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/logger.dart';
import '../../shared/models/device_model.dart';
import '../../shared/models/transfer_model.dart';
import '../conversion/conversion_service.dart';
import '../security/encryption_service.dart';

/// Transfer session with control signals.
class _TransferSession {
  final String id;
  Socket? socket;
  bool isPaused = false;
  bool isCancelled = false;
  Completer<void>? pauseCompleter;

  _TransferSession(this.id);

  Future<void> waitIfPaused() async {
    while (isPaused && !isCancelled) {
      pauseCompleter = Completer<void>();
      await pauseCompleter!.future;
    }
  }

  void resume() {
    isPaused = false;
    pauseCompleter?.complete();
    pauseCompleter = null;
  }

  void cancel() {
    isCancelled = true;
    resume();
    socket?.destroy();
  }
}

class _QueueItem {
  final String filePath;
  final DeviceModel target;
  _QueueItem({required this.filePath, required this.target});
}

/// Encrypted, chunk-based file transfer engine.
/// Protocol: HEADER → KEY_EXCHANGE → APPROVAL → ENCRYPTED_CHUNKS
class TransferService {
  final _log = const AppLogger('Transfer');
  ServerSocket? _server;
  final _transferController = StreamController<TransferModel>.broadcast();
  final Map<String, TransferModel> _activeTransfers = {};
  final Map<String, _TransferSession> _sessions = {};
  final List<_QueueItem> _queue = [];
  final ConversionService _conversionService = ConversionService();
  final EncryptionService _encryptionService = EncryptionService();
  bool _isListening = false;
  bool _isProcessingQueue = false;

  bool autoConvertEnabled = true;
  bool encryptionEnabled = true;
  String? targetPlatform;

  /// Local device identity (set during initialization)
  String localDeviceId = '';
  String localDeviceName = '';

  Stream<TransferModel> get transferStream => _transferController.stream;
  Map<String, TransferModel> get activeTransfers => Map.unmodifiable(_activeTransfers);
  bool get isListening => _isListening;
  int get queueLength => _queue.length;

  void Function(TransferModel transfer, String savedPath)? onFileReceived;
  Future<bool> Function(TransferModel transfer)? onTransferRequest;

  // --- Server ---

  Future<void> startServer() async {
    if (_isListening) return;
    _server = await ServerSocket.bind(InternetAddress.anyIPv4, AppConstants.transferPort);
    _isListening = true;
    _server!.listen(_handleIncoming);
  }

  Future<void> stopServer() async {
    _isListening = false;
    await _server?.close();
    _server = null;
  }

  // --- Queue ---

  void enqueueFiles({required List<String> filePaths, required DeviceModel target}) {
    for (final path in filePaths) {
      _queue.add(_QueueItem(filePath: path, target: target));
    }
    _processQueue();
  }

  Future<void> _processQueue() async {
    if (_isProcessingQueue) return;
    _isProcessingQueue = true;
    while (_queue.isNotEmpty) {
      final item = _queue.removeAt(0);
      await sendFile(filePath: item.filePath, target: item.target);
    }
    _isProcessingQueue = false;
  }

  // --- Sending ---

  Future<TransferModel> sendFile({
    required String filePath,
    required DeviceModel target,
    int retryCount = 0,
  }) async {
    var file = File(filePath);
    if (!await file.exists()) throw FileSystemException('File not found', filePath);

    var fileName = file.uri.pathSegments.last;
    var mimeType = _guessMimeType(fileName);

    if (autoConvertEnabled) {
      final platform = targetPlatform ?? 'android';
      final convertedPath = await _conversionService.autoConvert(
        filePath: filePath, mimeType: mimeType, fileName: fileName, targetPlatform: platform,
      );
      if (convertedPath != filePath) {
        file = File(convertedPath);
        fileName = file.uri.pathSegments.last;
        mimeType = _guessMimeType(fileName);
      }
    }

    final fileSize = await file.length();
    final transferId = const Uuid().v4();
    final session = _TransferSession(transferId);
    _sessions[transferId] = session;

    var transfer = TransferModel(
      id: transferId, fileName: fileName, filePath: file.path,
      fileSize: fileSize, mimeType: mimeType, deviceId: target.id,
      deviceName: target.name, direction: TransferDirection.sent,
      state: TransferState.connecting, startedAt: DateTime.now(), retryCount: retryCount,
    );
    _activeTransfers[transferId] = transfer;
    _emit(transfer);

    try {
      final socket = await Socket.connect(
        target.ipAddress!, target.port ?? AppConstants.transferPort,
        timeout: Duration(seconds: AppConstants.transferTimeout),
      );
      session.socket = socket;
      if (session.isCancelled) { socket.destroy(); return _finishTransfer(transfer, TransferState.cancelled); }

      // Generate session key for encryption
      Uint8List? sessionKey;
      if (encryptionEnabled) {
        sessionKey = await _encryptionService.generateSessionKey();
      }

      // Send header with encryption flag
      final header = jsonEncode({
        'id': transferId,
        'fileName': fileName,
        'fileSize': fileSize,
        'mimeType': mimeType,
        'chunkSize': AppConstants.defaultChunkSize,
        'encrypted': encryptionEnabled,
        'sessionKey': encryptionEnabled ? base64Encode(sessionKey!) : null,
        'senderDeviceId': localDeviceId,
        'senderDeviceName': localDeviceName,
      });

      final headerBytes = utf8.encode(header);
      socket.add(_intToBytes(headerBytes.length));
      socket.add(headerBytes);
      await socket.flush();

      // Wait for approval
      transfer = transfer.copyWith(state: TransferState.waitingApproval);
      _activeTransfers[transferId] = transfer;
      _emit(transfer);

      final response = await socket.first;
      if (response.isEmpty || response[0] != 1) {
        return _finishTransfer(transfer, TransferState.cancelled, error: 'Rejected');
      }

      // Send file chunks (encrypted if enabled)
      transfer = transfer.copyWith(state: TransferState.sending);
      _activeTransfers[transferId] = transfer;
      _emit(transfer);

      final fileStream = file.openRead();
      int bytesSent = 0;
      final stopwatch = Stopwatch()..start();

      await for (final chunk in fileStream) {
        if (session.isCancelled) { socket.destroy(); stopwatch.stop(); return _finishTransfer(transfer, TransferState.cancelled); }
        if (session.isPaused) {
          stopwatch.stop();
          transfer = transfer.copyWith(state: TransferState.paused);
          _activeTransfers[transferId] = transfer; _emit(transfer);
          await session.waitIfPaused();
          if (session.isCancelled) { socket.destroy(); return _finishTransfer(transfer, TransferState.cancelled); }
          transfer = transfer.copyWith(state: TransferState.sending);
          _activeTransfers[transferId] = transfer; _emit(transfer);
          stopwatch.start();
        }

        Uint8List dataToSend;
        if (encryptionEnabled && sessionKey != null) {
          // Encrypt chunk
          final encrypted = await _encryptionService.encryptChunk(Uint8List.fromList(chunk), sessionKey);
          // Send: [4-byte encrypted length][encrypted data]
          socket.add(_intToBytes(encrypted.length));
          dataToSend = encrypted;
        } else {
          dataToSend = Uint8List.fromList(chunk);
        }

        socket.add(dataToSend);
        await socket.flush();
        bytesSent += chunk.length;

        final elapsed = stopwatch.elapsedMilliseconds;
        final speed = elapsed > 0 ? (bytesSent * 1000) ~/ elapsed : 0;
        transfer = transfer.copyWith(progress: bytesSent / fileSize, bytesTransferred: bytesSent, speed: speed);
        _activeTransfers[transferId] = transfer; _emit(transfer);

        if (bytesSent % (AppConstants.defaultChunkSize * 10) == 0) {
          _saveResumeData(transferId, bytesSent, filePath, target);
        }
      }

      stopwatch.stop();
      await socket.close();
      _clearResumeData(transferId);

      transfer = transfer.copyWith(
        state: TransferState.completed, progress: 1.0, bytesTransferred: fileSize,
        completedAt: DateTime.now(), duration: stopwatch.elapsedMilliseconds,
      );
      _activeTransfers.remove(transferId); _sessions.remove(transferId);
      _emit(transfer);
      return transfer;
    } catch (e) {
      _sessions.remove(transferId);
      if (retryCount < AppConstants.retryAttempts && !session.isCancelled) {
        transfer = transfer.copyWith(state: TransferState.retrying, retryCount: retryCount + 1);
        _activeTransfers[transferId] = transfer; _emit(transfer);
        await Future.delayed(Duration(seconds: 2 * (retryCount + 1)));
        _activeTransfers.remove(transferId);
        return sendFile(filePath: filePath, target: target, retryCount: retryCount + 1);
      }
      return _finishTransfer(transfer, TransferState.failed, error: e.toString());
    }
  }

  // --- Controls ---

  void pauseTransfer(String id) => _sessions[id]?.isPaused = true;
  void resumeTransfer(String id) => _sessions[id]?.resume();
  void cancelTransfer(String id) {
    final session = _sessions[id];
    if (session != null) { session.cancel(); }
    else { final t = _activeTransfers.remove(id); if (t != null) _emit(t.copyWith(state: TransferState.cancelled)); }
  }

  // --- Receiving ---

  void _handleIncoming(Socket socket) async {
    try {
      final allData = <int>[];
      final dataStream = socket.asBroadcastStream();

      await for (final data in dataStream) { allData.addAll(data); if (allData.length >= 4) break; }
      if (allData.length < 4) { socket.destroy(); return; }

      final headerLength = _bytesToInt(allData.sublist(0, 4));
      while (allData.length < 4 + headerLength) { final data = await dataStream.first; allData.addAll(data); }

      final headerJson = utf8.decode(allData.sublist(4, 4 + headerLength));
      final header = jsonDecode(headerJson) as Map<String, dynamic>;

      final transferId = header['id'] as String;
      final fileName = header['fileName'] as String;
      final fileSize = header['fileSize'] as int;
      final mimeType = header['mimeType'] as String? ?? '';
      final isEncrypted = header['encrypted'] as bool? ?? false;
      final senderDeviceId = header['senderDeviceId'] as String? ?? socket.remoteAddress.address;
      final senderDeviceName = header['senderDeviceName'] as String? ?? socket.remoteAddress.address;
      Uint8List? sessionKey;
      if (isEncrypted && header['sessionKey'] != null) {
        sessionKey = base64Decode(header['sessionKey'] as String);
      }

      var transfer = TransferModel(
        id: transferId, fileName: fileName, filePath: '', fileSize: fileSize,
        mimeType: mimeType, deviceId: senderDeviceId,
        deviceName: senderDeviceName, direction: TransferDirection.received,
        state: TransferState.waitingApproval, startedAt: DateTime.now(),
      );
      _activeTransfers[transferId] = transfer; _emit(transfer);

      bool approved = true;
      if (onTransferRequest != null) approved = await onTransferRequest!(transfer);
      if (!approved) {
        socket.add([0]); await socket.flush(); socket.destroy();
        _finishTransfer(transfer, TransferState.cancelled); return;
      }

      socket.add([1]); await socket.flush();
      transfer = transfer.copyWith(state: TransferState.receiving);
      _activeTransfers[transferId] = transfer; _emit(transfer);

      final savePath = await _getSavePath(fileName);
      final file = File(savePath);
      final sink = file.openWrite();

      int bytesReceived = 0;
      final overflow = allData.sublist(4 + headerLength);

      if (isEncrypted && sessionKey != null) {
        // Encrypted receive: read [4-byte chunk len][encrypted chunk] repeatedly
        final buffer = <int>[...overflow];
        final stopwatch = Stopwatch()..start();

        await for (final data in dataStream) {
          buffer.addAll(data);

          // Process complete encrypted chunks from buffer
          while (buffer.length >= 4) {
            final chunkLen = _bytesToInt(buffer.sublist(0, 4));
            if (buffer.length < 4 + chunkLen) break;

            final encryptedChunk = Uint8List.fromList(buffer.sublist(4, 4 + chunkLen));
            buffer.removeRange(0, 4 + chunkLen);

            final decrypted = await _encryptionService.decryptChunk(encryptedChunk, sessionKey);
            sink.add(decrypted);
            bytesReceived += decrypted.length;

            final elapsed = stopwatch.elapsedMilliseconds;
            final speed = elapsed > 0 ? (bytesReceived * 1000) ~/ elapsed : 0;
            transfer = transfer.copyWith(
              progress: (bytesReceived / fileSize).clamp(0.0, 1.0),
              bytesTransferred: bytesReceived, speed: speed,
            );
            _activeTransfers[transferId] = transfer; _emit(transfer);
          }
        }

        // Process any remaining data in buffer
        while (buffer.length >= 4) {
          final chunkLen = _bytesToInt(buffer.sublist(0, 4));
          if (buffer.length < 4 + chunkLen) break;
          final encryptedChunk = Uint8List.fromList(buffer.sublist(4, 4 + chunkLen));
          buffer.removeRange(0, 4 + chunkLen);
          final decrypted = await _encryptionService.decryptChunk(encryptedChunk, sessionKey);
          sink.add(decrypted);
          bytesReceived += decrypted.length;
        }
        stopwatch.stop();
      } else {
        // Unencrypted receive
        if (overflow.isNotEmpty) { sink.add(overflow); bytesReceived += overflow.length; }
        final stopwatch = Stopwatch()..start();
        await for (final chunk in dataStream) {
          sink.add(chunk); bytesReceived += chunk.length;
          final elapsed = stopwatch.elapsedMilliseconds;
          final speed = elapsed > 0 ? (bytesReceived * 1000) ~/ elapsed : 0;
          transfer = transfer.copyWith(
            progress: (bytesReceived / fileSize).clamp(0.0, 1.0),
            bytesTransferred: bytesReceived, speed: speed,
          );
          _activeTransfers[transferId] = transfer; _emit(transfer);
        }
        stopwatch.stop();
      }

      await sink.flush(); await sink.close();

      transfer = transfer.copyWith(
        state: TransferState.completed, filePath: savePath, progress: 1.0,
        bytesTransferred: bytesReceived, completedAt: DateTime.now(),
      );
      _activeTransfers.remove(transferId); _emit(transfer);
      onFileReceived?.call(transfer, savePath);
    } catch (e) { socket.destroy(); _log.debug('Incoming transfer handling failed: $e'); }
  }

  // --- Helpers ---

  TransferModel _finishTransfer(TransferModel t, TransferState state, {String? error}) {
    t = t.copyWith(state: state, errorMessage: error, completedAt: DateTime.now());
    _activeTransfers.remove(t.id); _sessions.remove(t.id); _emit(t); return t;
  }

  void _emit(TransferModel t) => _transferController.add(t);

  Future<String> _getSavePath(String fileName) async {
    try {
      final settingsBox = Hive.box(AppConstants.settingsBox);
      final saveLoc = settingsBox.get('save_location', defaultValue: 'Downloads') as String;
      if (saveLoc.startsWith('/')) {
        final dir = Directory(saveLoc);
        if (await dir.exists()) return _uniquePath('${dir.path}/$fileName');
      }
      if (Platform.isAndroid) {
        final base = '/storage/emulated/0';
        final dirPath = switch (saveLoc) { 'Documents' => '$base/Documents', 'Pictures' => '$base/Pictures', _ => '$base/Download' };
        final dir = Directory(dirPath);
        if (!await dir.exists()) await dir.create(recursive: true);
        return _uniquePath('${dir.path}/$fileName');
      }
      if (Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
        // Resolve to actual user home directory paths on desktop
        final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
        if (home.isNotEmpty) {
          final dirPath = switch (saveLoc) {
            'Documents' => '$home/Documents',
            'Pictures' => '$home/Pictures',
            _ => '$home/Downloads',
          };
          final dir = Directory(dirPath);
          if (!await dir.exists()) await dir.create(recursive: true);
          return _uniquePath('${dir.path}/$fileName');
        }
      }
    } catch (e) {
      _log.debug('Save path resolution failed: $e');
    }
    // Final fallback: use Downloads directory from path_provider
    try {
      final downloadsDir = await getDownloadsDirectory();
      if (downloadsDir != null) return _uniquePath('${downloadsDir.path}/$fileName');
    } catch (e) {
      _log.debug('Downloads directory fallback failed: $e');
    }
    try { final appDir = await getApplicationDocumentsDirectory(); return _uniquePath('${appDir.path}/$fileName'); } catch (e) { _log.debug('App documents directory fallback failed: $e'); }
    return _uniquePath('${Directory.systemTemp.path}/$fileName');
  }

  String _uniquePath(String path) {
    var file = File(path); if (!file.existsSync()) return path;
    final dir = file.parent.path; final name = file.uri.pathSegments.last;
    final dot = name.lastIndexOf('.'); final baseName = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    var counter = 1; while (file.existsSync()) { file = File('$dir/$baseName ($counter)$ext'); counter++; }
    return file.path;
  }

  void _saveResumeData(String id, int bytes, String path, DeviceModel target) {
    try { Hive.box(AppConstants.resumeBox).put(id, {'bytesTransferred': bytes, 'filePath': path, 'targetId': target.id, 'targetIp': target.ipAddress, 'targetPort': target.port, 'targetName': target.name, 'timestamp': DateTime.now().toIso8601String()}); } catch (e) { _log.debug('Save resume data failed: $e'); }
  }
  void _clearResumeData(String id) { try { Hive.box(AppConstants.resumeBox).delete(id); } catch (e) { _log.debug('Clear resume data failed: $e'); } }

  Uint8List _intToBytes(int v) => Uint8List(4)..buffer.asByteData().setInt32(0, v, Endian.big);
  int _bytesToInt(List<int> b) => Uint8List.fromList(b).buffer.asByteData().getInt32(0, Endian.big);

  String _guessMimeType(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    return switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg', 'png' => 'image/png', 'gif' => 'image/gif',
      'webp' => 'image/webp', 'heic' => 'image/heic', 'mp4' => 'video/mp4',
      'mov' => 'video/quicktime', 'avi' => 'video/x-msvideo', 'mkv' => 'video/x-matroska',
      'mp3' => 'audio/mpeg', 'aac' => 'audio/aac', 'pdf' => 'application/pdf',
      'zip' => 'application/zip', 'apk' => 'application/vnd.android.package-archive',
      _ => 'application/octet-stream',
    };
  }

  Future<void> dispose() async {
    await stopServer();
    for (final s in _sessions.values) {
      s.cancel();
    }
    _sessions.clear();
    _activeTransfers.clear();
    _queue.clear();
    await _transferController.close();
  }
}
