import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../services/messaging/messaging_service.dart';
import '../../../../shared/models/device_model.dart';
import '../../../../shared/providers/device_provider.dart';
import '../../../../shared/providers/messaging_provider.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final DeviceModel device;
  const ChatScreen({super.key, required this.device});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _controller = TextEditingController();
  List<Message> _messages = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  Future<void> _loadMessages() async {
    final myId = ref.read(currentDeviceProvider)?.id ?? '';
    final service = ref.read(messagingServiceProvider);
    final msgs = await service.getMessages(widget.device.id, myId);
    setState(() {
      _messages = msgs;
      _loading = false;
    });

    // Listen for new messages
    service.messageStream.listen((msg) {
      if (msg.senderId == widget.device.id || msg.recipientId == widget.device.id) {
        setState(() => _messages = [..._messages, msg]);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final myId = ref.read(currentDeviceProvider)?.id ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.device.name),
        actions: [
          IconButton(
            icon: Icon(LucideIcons.trash2),
            onPressed: () async {
              await ref.read(messagingServiceProvider).clearConversation(widget.device.id, myId);
              setState(() => _messages = []);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(LucideIcons.messageCircle, size: 48, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3)),
                            const Gap(12),
                            Text('No messages yet', style: TextStyle(color: colorScheme.onSurfaceVariant)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final msg = _messages[index];
                          final isMe = msg.senderId == myId;
                          return _MessageBubble(message: msg, isMe: isMe);
                        },
                      ),
          ),
          // Input
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              border: Border(top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3))),
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: InputDecoration(
                        hintText: 'Type a message...',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                        filled: true,
                        fillColor: colorScheme.surfaceContainerLow,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const Gap(8),
                  IconButton.filled(
                    onPressed: _send,
                    icon: Icon(LucideIcons.send, size: 18),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final myDevice = ref.read(currentDeviceProvider);
    if (myDevice == null) return;

    ref.read(messagingServiceProvider).sendMessage(
      text: text,
      senderId: myDevice.id,
      senderName: myDevice.name,
      recipientId: widget.device.id,
      recipientIp: widget.device.ipAddress,
      recipientPort: widget.device.port,
    );

    setState(() {
      _messages.add(Message(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        text: text,
        senderId: myDevice.id,
        senderName: myDevice.name,
        recipientId: widget.device.id,
        timestamp: DateTime.now(),
      ));
    });

    _controller.clear();
  }
}

class _MessageBubble extends StatelessWidget {
  final Message message;
  final bool isMe;

  const _MessageBubble({required this.message, required this.isMe});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: isMe ? colorScheme.primary : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              message.text,
              style: TextStyle(
                color: isMe ? colorScheme.onPrimary : colorScheme.onSurface,
                fontSize: 14,
              ),
            ),
            const Gap(4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${message.timestamp.hour.toString().padLeft(2, '0')}:${message.timestamp.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(
                    fontSize: 10,
                    color: isMe ? colorScheme.onPrimary.withValues(alpha: 0.7) : colorScheme.onSurfaceVariant,
                  ),
                ),
                if (isMe) ...[
                  const Gap(4),
                  Icon(
                    message.delivered ? LucideIcons.checkCheck : LucideIcons.check,
                    size: 12,
                    color: colorScheme.onPrimary.withValues(alpha: 0.7),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
