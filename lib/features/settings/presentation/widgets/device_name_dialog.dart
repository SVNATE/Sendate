import 'package:flutter/material.dart';

class DeviceNameDialog extends StatefulWidget {
  final String currentName;
  final ValueChanged<String> onSave;

  const DeviceNameDialog({
    super.key,
    required this.currentName,
    required this.onSave,
  });

  @override
  State<DeviceNameDialog> createState() => _DeviceNameDialogState();
}

class _DeviceNameDialogState extends State<DeviceNameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Device Name'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: 'Enter device name',
        ),
        textCapitalization: TextCapitalization.words,
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }

  void _save() {
    final name = _controller.text.trim();
    if (name.isNotEmpty) {
      widget.onSave(name);
      Navigator.pop(context);
    }
  }
}
