import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uri_content/uri_content.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/logger.dart';
import '../../shared/models/device_model.dart';
import '../../shared/models/sendate_file.dart';
import '../../shared/models/transfer_model.dart';
import '../conversion/conversion_service.dart';
import '../security/encryption_service.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

// ---------------------------------------------------------------------------
// Transfer session — holds per-transfer control state (pause / cancel).
// ---------------------------------------------------------------------------
class _TransferSession {
  final String id;
  Socket? socket;
  bool isCancelled = false;
  bool isPaused = false;
  Completer<void>? _pauseCompleter;
  void Function()? onCancel;

  _TransferSession(this.id);

  Future<void> waitIfPaused() async {
    while (isPaused && !isCancelled) {
      _pauseCompleter = Completer<void>();
      await _pauseCompleter!.future;
    }
  }

  void resume() {
    isPaused = false;
    _pauseCompleter?.complete();
    _pauseCompleter = null;
  }

  void cancel() {
    isCancelled = true;
    resume(); // in case it's paused
    onCancel?.call(); // trigger socket kill
  }
}

enum TransferPriority { high, normal, low }

class _QueueItem {
  final SendateFile file;
  final DeviceModel target;
  final TransferPriority priority;
  final DateTime? scheduledAt;

  _QueueItem({
    required this.file,
    required this.target,
    this.priority = TransferPriority.normal,
    // ignore: unused_element_parameter
    this.scheduledAt,
  });
}

// ---------------------------------------------------------------------------
// TransferService — encrypted, chunk-based file transfer engine.
// Protocol:  [4-byte header-len][JSON header] → [1-byte approval] →
//            (encrypted) [packed-chunk]* | (plain) raw-bytes*
// ---------------------------------------------------------------------------
class TransferService {
  final _log = const AppLogger('Transfer');
  dynamic _server;
  final _transferController = StreamController<TransferModel>.broadcast();
  final Map<String, TransferModel> _activeTransfers = {};
  final Map<String, _TransferSession> _sessions = {};
  final List<_QueueItem> _queue = [];
  final ConversionService _conversionService = ConversionService();
  final EncryptionService _encryptionService = EncryptionService();
  final _uriContent = UriContent();

  // BUG-11 FIX: mutex so concurrent receives can't claim the same path
  final _savePathLock = <String, bool>{};
  bool _isListening = false;
  bool _isProcessingQueue = false;

  bool autoConvertEnabled = true;
  bool encryptionEnabled = true;
  String? targetPlatform;

  /// Optional bandwidth cap in bytes/sec (0 = unlimited).
  int bandwidthLimitBytesPerSec = 0;

  /// Local device identity (set during initialization).
  String localDeviceId = '';
  String localDeviceName = '';

  Stream<TransferModel> get transferStream => _transferController.stream;
  Map<String, TransferModel> get activeTransfers =>
      Map.unmodifiable(_activeTransfers);
  bool get isListening => _isListening;
  int get queueLength => _queue.length;

  void Function(TransferModel transfer, String savedPath)? onFileReceived;
  Future<bool> Function(TransferModel transfer)? onTransferRequest;

  // -------------------------------------------------------------------------
  // Server
  // -------------------------------------------------------------------------

  Future<void> startServer() async {
    if (_isListening) return;

    SecurityContextData? contextData;
    if (encryptionEnabled) {
      contextData = await _encryptionService.generateSecurityContext();
    }

    for (var portOffset = 0; portOffset < 3; portOffset++) {
      try {
        final port = AppConstants.transferPort + portOffset;
        if (encryptionEnabled && contextData != null) {
          _server = await SecureServerSocket.bind(InternetAddress.anyIPv4, port, contextData.context);
        } else {
          _server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
        }
        _isListening = true;
        _server!.listen(_handleIncoming);
        if (portOffset > 0) {
          _log.info('Transfer server started on fallback port $port');
        }
        return;
      } on SocketException catch (e) {
        _log.debug('Port ${AppConstants.transferPort + portOffset} in use: $e');
        if (portOffset == 2) {
          _log.error('Failed to bind transfer server after 3 attempts');
        }
      }
    }
  }

  Future<void> stopServer() async {
    _isListening = false;
    await _server?.close();
    _server = null;
  }

  // -------------------------------------------------------------------------
  // Queue  (BUG-01 FIX: parallel dispatch up to maxParallelTransfers)
  // -------------------------------------------------------------------------

  void enqueueFiles({
    required List<SendateFile> files,
    required DeviceModel target,
    TransferPriority priority = TransferPriority.normal,
  }) {
    for (final file in files) {
      _queue.add(_QueueItem(file: file, target: target, priority: priority));
    }
    _queue.sort((a, b) => a.priority.index.compareTo(b.priority.index));
    _processQueue();
  }

  void scheduleTransfer({
    required List<SendateFile> files,
    required DeviceModel target,
    required DateTime scheduledAt,
    TransferPriority priority = TransferPriority.normal,
  }) {
    final delay = scheduledAt.difference(DateTime.now());
    if (delay.isNegative) {
      enqueueFiles(files: files, target: target, priority: priority);
      return;
    }
    Future.delayed(delay, () {
      enqueueFiles(files: files, target: target, priority: priority);
    });
  }

  // BUG-01 FIX: process queue with up to maxParallelTransfers concurrent
  // sends, so a failed/slow file never blocks all subsequent files.
  Future<void> _processQueue() async {
    if (_isProcessingQueue) return;
    _isProcessingQueue = true;

    // Semaphore: track how many transfers are in-flight.
    var inFlight = 0;
    final allDone = Completer<void>();

    void tryDispatch() {
      while (_queue.isNotEmpty &&
          inFlight < AppConstants.maxParallelTransfers) {
        final item = _queue.removeAt(0);

        // Re-schedule future items
        if (item.scheduledAt != null &&
            item.scheduledAt!.isAfter(DateTime.now())) {
          scheduleTransfer(
            files: [item.file],
            target: item.target,
            scheduledAt: item.scheduledAt!,
            priority: item.priority,
          );
          continue;
        }

        inFlight++;
        sendFile(file: item.file, target: item.target)
            .catchError((_) => TransferModel(
                  id: '',
                  fileName: item.file.name,
                  filePath: item.file.path,
                  fileSize: 0,
                  mimeType: '',
                  deviceId: item.target.id,
                  deviceName: item.target.name,
                  direction: TransferDirection.sent,
                  state: TransferState.failed,
                  startedAt: DateTime.now(),
                ))
            .then((_) {
          inFlight--;
          if (_queue.isEmpty && inFlight == 0) {
            if (!allDone.isCompleted) allDone.complete();
          } else {
            tryDispatch();
          }
        });
      }

      if (_queue.isEmpty && inFlight == 0) {
        if (!allDone.isCompleted) allDone.complete();
      }
    }

    tryDispatch();
    await allDone.future;
    _isProcessingQueue = false;
  }

  // -------------------------------------------------------------------------
  // Sending
  // -------------------------------------------------------------------------

  Future<TransferModel> sendFile({
    required SendateFile file,
    required DeviceModel target,
    int retryCount = 0,
    // BUG-07 FIX: keep the original transferId stable across retries so the
    // UI card doesn't disappear/reappear; the session object is replaced safely.
    String? existingTransferId,
    String? batchId,
    int? batchFileCount,
  }) async {
    var fileName = file.name;
    var mimeType = _guessMimeType(fileName);
    var finalPath = file.path;
    var fileSize = file.size;

    if (autoConvertEnabled && !file.path.startsWith('content://')) {
      final platform = targetPlatform ?? 'android';
      final convertedPath = await _conversionService.autoConvert(
        filePath: finalPath,
        mimeType: mimeType,
        fileName: fileName,
        targetPlatform: platform,
      );
      if (convertedPath != finalPath) {
        final f = File(convertedPath);
        finalPath = f.path;
        fileName = f.uri.pathSegments.last;
        mimeType = _guessMimeType(fileName);
        fileSize = await f.length();
      }
    }

    // BUG-07 FIX: reuse the same transferId across retries so the UI
    // does not create a phantom duplicate entry.
    final transferId = existingTransferId ?? const Uuid().v4();
    final session = _TransferSession(transferId);
    session.onCancel = () {
      try {
        session.socket?.destroy();
      } catch (_) {}
    };
    _sessions[transferId] = session;

    var transfer = TransferModel(
      id: transferId,
      fileName: fileName,
      filePath: finalPath,
      fileSize: fileSize,
      mimeType: mimeType,
      deviceId: target.id,
      deviceName: target.name,
      direction: TransferDirection.sent,
      state: TransferState.connecting,
      startedAt: DateTime.now(),
      retryCount: retryCount,
      batchId: batchId,
      batchFileCount: batchFileCount,
    );
    _activeTransfers[transferId] = transfer;
    _emit(transfer);

    try {
      Socket socket;
      if (encryptionEnabled) {
        socket = await SecureSocket.connect(
          target.ipAddress!,
          target.port ?? AppConstants.transferPort,
          timeout: Duration(seconds: AppConstants.transferTimeout),
          onBadCertificate: (cert) => true, // Accept receiver's self-signed certificate
        );
      } else {
        socket = await Socket.connect(
          target.ipAddress!,
          target.port ?? AppConstants.transferPort,
          timeout: Duration(seconds: AppConstants.transferTimeout),
        );
      }
      session.socket = socket;

      if (session.isCancelled) {
        socket.destroy();
        return _finishTransfer(transfer, TransferState.cancelled);
      }

      // Send [4-byte header length][JSON header]
      final header = jsonEncode({
        'id': transferId,
        'fileName': fileName,
        'fileSize': fileSize,
        'mimeType': mimeType,
        'chunkSize': AppConstants.defaultChunkSize,
        'encrypted': encryptionEnabled,
        'senderDeviceId': localDeviceId,
        'senderDeviceName': localDeviceName,
        if (batchId != null) 'batchId': batchId,
        if (batchFileCount != null) 'batchFileCount': batchFileCount,
      });
      final headerBytes = utf8.encode(header);
      socket.add(_intToBytes(headerBytes.length));
      socket.add(headerBytes);
      await socket.flush();

      // Wait for approval byte
      transfer = transfer.copyWith(state: TransferState.waitingApproval);
      _activeTransfers[transferId] = transfer;
      _emit(transfer);

      final response = await socket.first;
      if (response.isEmpty || response[0] != 1) {
        return _finishTransfer(transfer, TransferState.cancelled,
            error: 'Rejected by receiver');
      }

      // Send file data
      transfer = transfer.copyWith(state: TransferState.sending);
      _activeTransfers[transferId] = transfer;
      _emit(transfer);

      final Stream<List<int>> fileStream;
      if (file.bytes != null) {
        fileStream = Stream.value(file.bytes!);
      } else if (finalPath.startsWith('content://')) {
        fileStream = _uriContent.getContentStream(Uri.parse(finalPath));
      } else {
        fileStream = File(finalPath).openRead();
      }

      int bytesSent = 0;
      int unwrittenBytes = 0;
      int lastEmitMs = 0;
      final stopwatch = Stopwatch()..start();

      await for (final chunk in fileStream) {
        if (session.isCancelled) {
          socket.destroy();
          stopwatch.stop();
          return _finishTransfer(transfer, TransferState.cancelled);
        }
        if (session.isPaused) {
          stopwatch.stop();
          transfer = transfer.copyWith(state: TransferState.paused);
          _activeTransfers[transferId] = transfer;
          _emit(transfer);
          await session.waitIfPaused();
          if (session.isCancelled) {
            socket.destroy();
            return _finishTransfer(transfer, TransferState.cancelled);
          }
          transfer = transfer.copyWith(state: TransferState.sending);
          _activeTransfers[transferId] = transfer;
          _emit(transfer);
          stopwatch.start();
        }

        // SecureSocket automatically encrypts Native TLS payloads with zero overhead!
        socket.add(chunk);
        
        bytesSent += chunk.length;
        unwrittenBytes += chunk.length;

        // Flush only every 8MB to maximize network throughput while preventing OOM
        if (unwrittenBytes >= 8 * 1024 * 1024) {
          await socket.flush();
          unwrittenBytes = 0;
        }

        // Bandwidth throttle
        if (bandwidthLimitBytesPerSec > 0) {
          final elapsed = stopwatch.elapsedMilliseconds;
          final expectedMs =
              (bytesSent * 1000) ~/ bandwidthLimitBytesPerSec;
          if (expectedMs > elapsed) {
            await Future.delayed(
                Duration(milliseconds: expectedMs - elapsed));
          }
        }

        final elapsed = stopwatch.elapsedMilliseconds;
        final speed =
            elapsed > 0 ? (bytesSent * 1000) ~/ elapsed : 0;
        transfer = transfer.copyWith(
          progress: bytesSent / fileSize,
          bytesTransferred: bytesSent,
          speed: speed,
        );
        _activeTransfers[transferId] = transfer;
        
        // Throttle UI updates to roughly every 100ms
        if (elapsed - lastEmitMs > 100) {
          _emit(transfer);
          lastEmitMs = elapsed;
        }

        if (bytesSent % (AppConstants.defaultChunkSize * 10) == 0) {
          _saveResumeData(transferId, bytesSent, finalPath, target);
        }
      }

      stopwatch.stop();
      await socket.flush();
      await socket.close();
      
      // Wait for receiver to finish processing and close the connection
      try {
        await socket.listen((_) {}).asFuture().timeout(const Duration(seconds: 30));
      } catch (_) {}

      _clearResumeData(transferId);

      transfer = transfer.copyWith(
        state: TransferState.completed,
        progress: 1.0,
        bytesTransferred: fileSize,
        completedAt: DateTime.now(),
        duration: stopwatch.elapsedMilliseconds,
      );
      _activeTransfers.remove(transferId);
      _sessions.remove(transferId);
      _emit(transfer);
      return transfer;
    } catch (e) {
      _sessions.remove(transferId);
      if (retryCount < AppConstants.retryAttempts && !session.isCancelled) {
        transfer = transfer.copyWith(
            state: TransferState.retrying,
            retryCount: retryCount + 1);
        _activeTransfers[transferId] = transfer;
        _emit(transfer);
        await Future.delayed(Duration(seconds: 2 * (retryCount + 1)));
        // BUG-07 FIX: pass the same transferId so the UI entry is stable.
        return sendFile(
          file: file,
          target: target,
          retryCount: retryCount + 1,
          existingTransferId: transferId,
        );
      }
      return _finishTransfer(transfer, TransferState.failed,
          error: e.toString());
    }
  }

  // -------------------------------------------------------------------------
  // Controls
  // -------------------------------------------------------------------------

  // BUG-06 FIX: emit a state update immediately so the UI reflects the pause.
  void pauseTransfer(String id) {
    final session = _sessions[id];
    if (session == null) return;
    session.isPaused = true;
    final t = _activeTransfers[id];
    if (t != null) {
      final paused = t.copyWith(state: TransferState.paused);
      _activeTransfers[id] = paused;
      _emit(paused);
    }
  }

  void resumeTransfer(String id) => _sessions[id]?.resume();

  void cancelTransfer(String id) {
    final session = _sessions[id];
    if (session != null) {
      session.cancel();
    } else {
      final t = _activeTransfers.remove(id);
      if (t != null) _emit(t.copyWith(state: TransferState.cancelled));
    }
  }

  // -------------------------------------------------------------------------
  // Receiving
  // BUG-02 FIX: rewritten TCP framing using a proper byte-accumulator.
  //   • No asBroadcastStream() — one single-subscription listener drains all data.
  // BUG-04 FIX: all socket bytes go into one buffer; nothing is lost.
  // BUG-03 FIX: encrypted path expects [4-byte packed-len][packed chunk],
  //             matching the fixed sender above.
  // BUG-13 FIX: clamp bytesTransferred to fileSize at completion.
  // -------------------------------------------------------------------------

  void _handleIncoming(Socket socket) {
    final buffer = <int>[];
    final transferId$ = Completer<String>();

    // State machine
    bool headerRead = false;
    int? headerLength;
    String? transferId;
    String? fileName;
    int? fileSize;
    String? mimeType;
    bool? isEncrypted;
    Uint8List? sessionKey;
    String? senderDeviceId;
    String? senderDeviceName;

    bool approvalSent = false;
    bool receiving = false;
    IOSink? sink;
    int bytesReceived = 0;
    Stopwatch? stopwatch;
    TransferModel? transfer;
    int lastEmitMs = 0;

    // Encrypted chunk framing state
    int? pendingChunkLen;
    StreamSubscription<Uint8List>? subscription;
    bool isProcessing = false;

    subscription = socket.listen(
      (data) async {
        buffer.addAll(data);

        if (isProcessing) return;
        isProcessing = true;
        subscription?.pause();

        try {
          while (true) {
            int startLen = buffer.length;

            // Step 1: read 4-byte header length
          if (!headerRead) {
            if (buffer.length < 4) return;
            headerLength = _bytesToInt(buffer.sublist(0, 4));
          }

          // Step 2: read header JSON
          if (!headerRead) {
            final needed = 4 + headerLength!;
            if (buffer.length < needed) return;

            final headerJson =
                utf8.decode(buffer.sublist(4, needed));
            buffer.removeRange(0, needed);
            headerRead = true;

            final header =
                jsonDecode(headerJson) as Map<String, dynamic>;
            transferId = header['id'] as String;
            fileName = header['fileName'] as String;
            fileSize = header['fileSize'] as int;
            mimeType = header['mimeType'] as String? ?? '';
            isEncrypted = header['encrypted'] as bool? ?? false;
            senderDeviceId = header['senderDeviceId'] as String? ??
                socket.remoteAddress.address;
            senderDeviceName = header['senderDeviceName'] as String? ??
                socket.remoteAddress.address;

            transfer = TransferModel(
              id: transferId!,
              fileName: fileName!,
              filePath: '',
              fileSize: fileSize!,
              mimeType: mimeType!,
              deviceId: senderDeviceId!,
              deviceName: senderDeviceName!,
              direction: TransferDirection.received,
              state: TransferState.waitingApproval,
              startedAt: DateTime.now(),
              batchId: header['batchId'] as String?,
              batchFileCount: header['batchFileCount'] as int?,
            );
            _activeTransfers[transferId!] = transfer!;
            _emit(transfer!);

            // Approval (await directly to hold the paused stream)
            bool approved = true;
            if (onTransferRequest != null) {
              approved = await onTransferRequest!(transfer!);
            }
            if (!approved) {
              socket.add([0]);
              await socket.flush();
              socket.destroy();
              _finishTransfer(transfer!, TransferState.cancelled);
              return;
            }

            socket.add([1]);
            await socket.flush();

            final savePath =
                await _getUniqueSavePath(fileName!);
            sink = File(savePath).openWrite();
            stopwatch = Stopwatch()..start();

            transfer = transfer!.copyWith(
                state: TransferState.receiving, filePath: savePath);
            _activeTransfers[transferId!] = transfer!;
            _emit(transfer!);
            approvalSent = true;
            receiving = true;
            transferId$.complete(savePath);


          } else if (approvalSent && receiving && sink != null) {
            // Step 3: stream body bytes
              
              pendingChunkLen = await _processBodyBytes(
                buffer: buffer,
                isEncrypted: isEncrypted!,
                sessionKey: sessionKey,
                sink: sink!,
                stopwatch: stopwatch!,
                fileSize: fileSize!,
                transfer: transfer!,
                transferId: transferId!,
                pendingChunkLen: pendingChunkLen,
                onProgress: (t) {
                  transfer = t;
                  bytesReceived = t.bytesTransferred;
                  _activeTransfers[transferId!] = t;
                  
                  final elapsed = stopwatch!.elapsedMilliseconds;
                  if (elapsed - lastEmitMs > 100) {
                    _emit(t);
                    lastEmitMs = elapsed;
                  }
                },
              );
          }
          
          if (buffer.length == startLen) break;
        } // end while(true)
      } catch (e) {
          _log.debug('Receive data error: $e');
          socket.destroy();
          if (transfer != null) {
            _finishTransfer(transfer!, TransferState.failed,
                error: e.toString());
          }
        } finally {
          isProcessing = false;
          subscription?.resume();
        }
      },
      onDone: () async {
        if (transfer == null) return;
        if (sink == null) {
          // Socket disconnected during approval dialog
          _finishTransfer(transfer!, TransferState.failed, error: 'Connection closed by sender');
          return;
        }
        try {
          await sink!.flush();
          await sink!.close();

          // BUG-13 FIX: clamp bytesTransferred to fileSize
          final finalBytes =
              bytesReceived.clamp(0, fileSize ?? bytesReceived);
          final savePath = transfer!.filePath.isNotEmpty
              ? transfer!.filePath
              : '';

          final completed = transfer!.copyWith(
            state: TransferState.completed,
            filePath: savePath,
            progress: 1.0,
            bytesTransferred: finalBytes,
            completedAt: DateTime.now(),
          );
          _activeTransfers.remove(transferId);
          _emit(completed);
          onFileReceived?.call(completed, savePath);
          
          socket.destroy(); // Signal sender that we are completely done
        } catch (e) {
          _log.debug('Receive finalize error: $e');
          if (transfer != null) {
            _finishTransfer(transfer!, TransferState.failed,
                error: e.toString());
          }
        }
      },
      onError: (e) {
        _log.debug('Incoming socket error: $e');
        socket.destroy();
        if (transfer != null) {
          _finishTransfer(transfer!, TransferState.failed,
              error: e.toString());
        }
      },
      cancelOnError: true,
    );
  }

  /// Process body bytes from [buffer] in-place, handling both plain and
  /// TLS encrypted framing natively. Clears consumed bytes from buffer.
  Future<int?> _processBodyBytes({
    required List<int> buffer,
    required bool isEncrypted,
    required Uint8List? sessionKey,
    required IOSink sink,
    required Stopwatch stopwatch,
    required int fileSize,
    required TransferModel transfer,
    required String transferId,
    required int? pendingChunkLen,
    required void Function(TransferModel updated) onProgress,
  }) async {
    // Both plain and TLS sockets deliver decrypted raw bytes directly!
    if (buffer.isEmpty) return null;
    
    final chunk = List<int>.from(buffer);
    buffer.clear();
    sink.add(chunk);

    final newBytes = transfer.bytesTransferred + chunk.length;
    final elapsed = stopwatch.elapsedMilliseconds;
    final speed = elapsed > 0 ? (newBytes * 1000) ~/ elapsed : 0;
    
    final updated = transfer.copyWith(
      progress: (newBytes / fileSize).clamp(0.0, 1.0),
      bytesTransferred: newBytes,
      speed: speed,
    );
    onProgress(updated);
    
    return null;
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  TransferModel _finishTransfer(TransferModel t, TransferState state,
      {String? error}) {
    t = t.copyWith(
        state: state, errorMessage: error, completedAt: DateTime.now());
    _activeTransfers.remove(t.id);
    _sessions.remove(t.id);
    _emit(t);
    return t;
  }

  void _emit(TransferModel t) {
    _transferController.add(t);
    _updateWakelock();
  }

  void _updateWakelock() {
    try {
      if (_activeTransfers.isNotEmpty) {
        WakelockPlus.enable();
      } else {
        WakelockPlus.disable();
      }
    } catch (e) {
      _log.debug('Wakelock update failed: $e');
    }
  }

  // BUG-11 FIX: async-safe unique path with a simple in-process lock to
  // prevent TOCTOU races between concurrent incoming transfers.
  Future<String> _getUniqueSavePath(String fileName) async {
    final basePath = await _getSavePath(fileName);
    // Normalise to a counter-free candidate first
    var candidate = basePath;
    final dir = File(basePath).parent.path;
    final name = fileName;
    final dot = name.lastIndexOf('.');
    final baseName = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    var counter = 1;

    // Spin until we claim an unused path
    while (_savePathLock.containsKey(candidate) ||
        await File(candidate).exists()) {
      candidate = '$dir/$baseName ($counter)$ext';
      counter++;
    }
    _savePathLock[candidate] = true; // reserve it
    return candidate;
  }

  /// Release a path reservation after the file sink has been opened.
  // ignore: unused_element
  void _releaseSavePathLock(String path) {
    _savePathLock.remove(path);
  }

  Future<String> _getSavePath(String fileName) async {
    try {
      final settingsBox = Hive.box(AppConstants.settingsBox);
      final saveLoc =
          settingsBox.get('save_location', defaultValue: 'Downloads')
              as String;
      if (saveLoc.startsWith('/')) {
        final dir = Directory(saveLoc);
        if (await dir.exists()) return '${dir.path}/$fileName';
      }
      if (Platform.isAndroid) {
        // Use path_provider to get the app-specific isolated Downloads directory
        // to avoid Android 11+ MANAGE_EXTERNAL_STORAGE restrictions.
        final dir = await getDownloadsDirectory();
        if (dir != null) {
          return '${dir.path}/$fileName';
        }
      }
      if (Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
        final home = Platform.environment['HOME'] ??
            Platform.environment['USERPROFILE'] ??
            '';
        if (home.isNotEmpty) {
          final dirPath = switch (saveLoc) {
            'Documents' => '$home/Documents',
            'Pictures' => '$home/Pictures',
            _ => '$home/Downloads',
          };
          final dir = Directory(dirPath);
          if (!await dir.exists()) await dir.create(recursive: true);
          return '${dir.path}/$fileName';
        }
      }
    } catch (e) {
      _log.debug('Save path resolution failed: $e');
    }
    
    // On iOS, Downloads directory is often not directly writable without special entitlements.
    // We should skip the Downloads directory fallback on iOS and go straight to App Documents.
    if (!Platform.isIOS) {
      try {
        final downloadsDir = await getDownloadsDirectory();
        if (downloadsDir != null) {
          if (!await downloadsDir.exists()) {
            await downloadsDir.create(recursive: true);
          }
          return '${downloadsDir.path}/$fileName';
        }
      } catch (e) {
        _log.debug('Downloads directory fallback failed: $e');
      }
    }
    try {
      final appDir = await getApplicationDocumentsDirectory();
      if (!await appDir.exists()) {
        await appDir.create(recursive: true);
      }
      return '${appDir.path}/$fileName';
    } catch (e) {
      _log.debug('App documents directory fallback failed: $e');
    }
    return '${Directory.systemTemp.path}/$fileName';
  }

  void _saveResumeData(
      String id, int bytes, String path, DeviceModel target) {
    try {
      Hive.box(AppConstants.resumeBox).put(id, {
        'bytesTransferred': bytes,
        'filePath': path,
        'targetId': target.id,
        'targetIp': target.ipAddress,
        'targetPort': target.port,
        'targetName': target.name,
        'timestamp': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      _log.debug('Save resume data failed: $e');
    }
  }

  void _clearResumeData(String id) {
    try {
      Hive.box(AppConstants.resumeBox).delete(id);
    } catch (e) {
      _log.debug('Clear resume data failed: $e');
    }
  }

  Uint8List _intToBytes(int v) =>
      Uint8List(4)..buffer.asByteData().setInt32(0, v, Endian.big);

  int _bytesToInt(List<int> b) =>
      Uint8List.fromList(b).buffer.asByteData().getInt32(0, Endian.big);

  String _guessMimeType(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    return switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'heic' => 'image/heic',
      'mp4' => 'video/mp4',
      'mov' => 'video/quicktime',
      'avi' => 'video/x-msvideo',
      'mkv' => 'video/x-matroska',
      'mp3' => 'audio/mpeg',
      'aac' => 'audio/aac',
      'pdf' => 'application/pdf',
      'zip' => 'application/zip',
      'apk' => 'application/vnd.android.package-archive',
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
