import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../features/send/domain/saved_selection_model.dart';
import '../../../../shared/models/sendate_file.dart';
import '../../../../shared/providers/saved_selections_provider.dart';
import '../../../../shared/providers/send_screen_providers.dart';

/// Bottom sheet that lists saved file selections, allowing the user to
/// load a preset back into [selectedFilesProvider].
class SavedSelectionsSheet extends ConsumerWidget {
  const SavedSelectionsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selections = ref.watch(savedSelectionsProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.85,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Handle
            const SizedBox(height: 8),
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Text(
                    'Saved Selections',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  if (selections.isNotEmpty)
                    TextButton(
                      onPressed: () => _confirmClearAll(context, ref),
                      child: const Text('Clear all'),
                    ),
                ],
              ),
            ),
            const Divider(height: 8),
            // List
            Expanded(
              child: selections.isEmpty
                  ? _EmptyState()
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: selections.length,
                      padding: const EdgeInsets.only(
                          left: 12, right: 12, top: 4, bottom: 96),
                      itemBuilder: (context, index) {
                        return _SelectionTile(
                          selection: selections[index],
                          onLoad: () {
                            _loadSelection(context, ref, selections[index]);
                            Navigator.of(context).pop();
                          },
                          onDelete: () => ref
                              .read(savedSelectionsProvider.notifier)
                              .remove(selections[index].id),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  void _loadSelection(
    BuildContext context,
    WidgetRef ref,
    SavedSelectionModel selection,
  ) {
    final existing = <String>[];
    final missing = <String>[];

    for (final path in selection.paths) {
      if (File(path).existsSync()) {
        existing.add(path);
      } else {
        missing.add(path);
      }
    }

    if (existing.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All files in this selection have been moved or deleted.'),
        ),
      );
      return;
    }

    // Build SendateFile list from existing paths
    final sendateFiles = existing.map((path) {
      final file = File(path);
      final name = path.split(Platform.pathSeparator).last;
      return SendateFile(
        name: name,
        path: path,
        size: file.existsSync() ? file.lengthSync() : 0,
      );
    }).toList();

    ref.read(selectedFilesProvider.notifier).state = sendateFiles;

    if (missing.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${missing.length} file(s) no longer exist and were skipped.',
          ),
        ),
      );
    }
  }

  void _confirmClearAll(BuildContext context, WidgetRef ref) {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all saved selections?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    ).then((confirmed) {
      if (confirmed == true) {
        ref.read(savedSelectionsProvider.notifier).clear();
      }
    });
  }
}

class _SelectionTile extends StatelessWidget {
  final SavedSelectionModel selection;
  final VoidCallback onLoad;
  final VoidCallback onDelete;

  const _SelectionTile({
    required this.selection,
    required this.onLoad,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            LucideIcons.bookmark,
            size: 18,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        title: Text(
          selection.name,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          '${selection.paths.length} file${selection.paths.length == 1 ? '' : 's'}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(LucideIcons.trash2, size: 16),
              onPressed: onDelete,
              tooltip: 'Delete',
            ),
            FilledButton.tonal(
              onPressed: onLoad,
              style: FilledButton.styleFrom(
                  minimumSize: const Size(56, 32),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 0)),
              child: const Text('Load'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            LucideIcons.bookmark,
            size: 48,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          const Gap(12),
          Text(
            'No saved selections',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const Gap(4),
          Text(
            'Pick files and tap "Save Selection" to create one.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
