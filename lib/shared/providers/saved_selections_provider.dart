import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../../core/constants/app_constants.dart';
import '../../features/send/domain/saved_selection_model.dart';

final savedSelectionsProvider =
    StateNotifierProvider<SavedSelectionsNotifier, List<SavedSelectionModel>>(
  (ref) => SavedSelectionsNotifier(),
);

class SavedSelectionsNotifier extends StateNotifier<List<SavedSelectionModel>> {
  SavedSelectionsNotifier() : super([]) {
    _load();
  }

  Box get _box => Hive.box(AppConstants.savedSelectionsBox);

  void _load() {
    try {
      state = _box.values
          .map((e) =>
              SavedSelectionModel.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList()
        ..sort((a, b) => b.savedAt.compareTo(a.savedAt));
    } catch (e) {
      debugPrint('[SavedSelections] load error: $e');
      state = [];
    }
  }

  void add(SavedSelectionModel selection) {
    _box.put(selection.id, selection.toMap());
    state = [selection, ...state];
  }

  void remove(String id) {
    _box.delete(id);
    state = state.where((s) => s.id != id).toList();
  }

  void rename(String id, String newName) {
    state = state.map((s) {
      if (s.id != id) return s;
      final updated = s.copyWith(name: newName);
      _box.put(id, updated.toMap());
      return updated;
    }).toList();
  }

  void clear() {
    _box.clear();
    state = [];
  }
}
