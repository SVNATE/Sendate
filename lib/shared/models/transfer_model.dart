enum TransferState {
  queued,
  scanning,
  connecting,
  waitingApproval,
  sending,
  receiving,
  paused,
  retrying,
  completed,
  failed,
  cancelled,
  resuming,
}

enum TransferDirection { sent, received }

class TransferModel {
  final String id;
  final String fileName;
  final String filePath;
  final int fileSize;
  final String mimeType;
  final String deviceId;
  final String deviceName;
  final TransferDirection direction;
  final TransferState state;
  final double progress;
  final int bytesTransferred;
  final int? speed; // bytes per second
  final DateTime startedAt;
  final DateTime? completedAt;
  final int? duration; // milliseconds
  final int retryCount;
  final String? errorMessage;

  const TransferModel({
    required this.id,
    required this.fileName,
    required this.filePath,
    required this.fileSize,
    required this.mimeType,
    required this.deviceId,
    required this.deviceName,
    required this.direction,
    this.state = TransferState.queued,
    this.progress = 0.0,
    this.bytesTransferred = 0,
    this.speed,
    required this.startedAt,
    this.completedAt,
    this.duration,
    this.retryCount = 0,
    this.errorMessage,
  });

  TransferModel copyWith({
    String? filePath,
    TransferState? state,
    double? progress,
    int? bytesTransferred,
    int? speed,
    DateTime? completedAt,
    int? duration,
    int? retryCount,
    String? errorMessage,
  }) {
    return TransferModel(
      id: id,
      fileName: fileName,
      filePath: filePath ?? this.filePath,
      fileSize: fileSize,
      mimeType: mimeType,
      deviceId: deviceId,
      deviceName: deviceName,
      direction: direction,
      state: state ?? this.state,
      progress: progress ?? this.progress,
      bytesTransferred: bytesTransferred ?? this.bytesTransferred,
      speed: speed ?? this.speed,
      startedAt: startedAt,
      completedAt: completedAt ?? this.completedAt,
      duration: duration ?? this.duration,
      retryCount: retryCount ?? this.retryCount,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
