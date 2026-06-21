import 'package:uuid/uuid.dart';

/// A named preset of file paths that can be reloaded on the Send screen.
class SavedSelectionModel {
  final String id;
  final String name;
  final List<String> paths;
  final DateTime savedAt;

  const SavedSelectionModel({
    required this.id,
    required this.name,
    required this.paths,
    required this.savedAt,
  });

  factory SavedSelectionModel.create({
    required String name,
    required List<String> paths,
  }) {
    return SavedSelectionModel(
      id: const Uuid().v4(),
      name: name,
      paths: List.unmodifiable(paths),
      savedAt: DateTime.now(),
    );
  }

  factory SavedSelectionModel.fromMap(Map<String, dynamic> map) {
    return SavedSelectionModel(
      id: map['id'] as String,
      name: map['name'] as String,
      paths: List<String>.from(map['paths'] as List),
      savedAt: DateTime.tryParse(map['savedAt'] as String? ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'paths': paths,
        'savedAt': savedAt.toIso8601String(),
      };

  SavedSelectionModel copyWith({String? name, List<String>? paths}) {
    return SavedSelectionModel(
      id: id,
      name: name ?? this.name,
      paths: paths ?? this.paths,
      savedAt: savedAt,
    );
  }
}
