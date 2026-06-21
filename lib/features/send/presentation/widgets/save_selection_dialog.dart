import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

import '../../../../features/send/domain/saved_selection_model.dart';
import '../../../../shared/providers/saved_selections_provider.dart';

/// Dialog that lets the user name and save the current file selection.
class SaveSelectionDialog extends ConsumerStatefulWidget {
  final List<String> filePaths;

  const SaveSelectionDialog({super.key, required this.filePaths});

  @override
  ConsumerState<SaveSelectionDialog> createState() =>
      _SaveSelectionDialogState();
}

class _SaveSelectionDialogState extends ConsumerState<SaveSelectionDialog> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final selection = SavedSelectionModel.create(
      name: _controller.text.trim(),
      paths: widget.filePaths,
    );
    ref.read(savedSelectionsProvider.notifier).add(selection);
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Save Selection'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.filePaths.length} file(s) will be saved as a preset.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const Gap(16),
            TextFormField(
              controller: _controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'e.g. Work Docs',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
              onFieldSubmitted: (_) => _save(),
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Enter a name';
                }
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
