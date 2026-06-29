import 'dart:typed_data';

class SendateFile {
  final String path;
  final String name;
  final int size;
  final Uint8List? bytes;

  const SendateFile({
    required this.path,
    required this.name,
    required this.size,
    this.bytes,
  });

  /// Extension of the file (e.g. 'jpg', 'mp4') without the dot.
  String get extension {
    final parts = name.split('.');
    if (parts.length > 1) {
      return parts.last.toLowerCase();
    }
    return '';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SendateFile && other.path == path && other.size == size;
  }

  @override
  int get hashCode => path.hashCode ^ size.hashCode;
}
