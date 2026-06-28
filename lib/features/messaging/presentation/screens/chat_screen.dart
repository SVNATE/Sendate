import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
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
    if (mounted) {
      setState(() {
        _messages = msgs;
        _loading = false;
      });
    }

    service.messageStream.listen((msg) {
      if (msg.senderId == widget.device.id || msg.recipientId == widget.device.id) {
        if (mounted) setState(() => _messages = [..._messages, msg]);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _confirmClear() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Clear Chat?',
                style: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.w800),
              ),
              const Gap(12),
              Text(
                'This will permanently delete all messages with ${widget.device.name}.',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const Gap(32),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: Text('Cancel', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const Gap(16),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.error,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: () async {
                        Navigator.pop(context);
                        final myId = ref.read(currentDeviceProvider)?.id ?? '';
                        await ref.read(messagingServiceProvider).clearConversation(widget.device.id, myId);
                        setState(() => _messages = []);
                      },
                      child: Text('Clear', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onError)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final myId = ref.watch(currentDeviceProvider)?.id ?? '';

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            // Custom Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(LucideIcons.arrowLeft, color: colorScheme.onSurface),
                    onPressed: () => context.pop(),
                  ),
                  const Gap(8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.device.name,
                          style: GoogleFonts.outfit(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: colorScheme.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${widget.device.deviceType.name} • ${widget.device.ipAddress ?? ""}',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (_messages.isNotEmpty)
                    IconButton(
                      icon: Icon(LucideIcons.trash2, color: colorScheme.onSurfaceVariant),
                      onPressed: _confirmClear,
                    ),
                ],
              ),
            ),
            
            // Messages Area
            Expanded(
              child: _loading
                  ? Center(
                      child: CircularProgressIndicator(
                        color: colorScheme.primary.withValues(alpha: 0.5),
                      ),
                    )
                  : _messages.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(LucideIcons.messageSquare, size: 64, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.2)),
                              const Gap(24),
                              Text(
                                'Say Hi!',
                                style: GoogleFonts.outfit(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w700,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                              const Gap(8),
                              Text(
                                'Start a secure conversation.',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 16,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final msg = _messages[index];
                            final isMe = msg.senderId == myId;
                            return _MessageBubble(message: msg, isMe: isMe);
                          },
                        ),
            ),

            // Floating Input Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Container(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(32),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  children: [
                    const Gap(12),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        style: GoogleFonts.plusJakartaSans(fontSize: 15),
                        decoration: InputDecoration(
                          hintText: 'Type a message...',
                          hintStyle: GoogleFonts.plusJakartaSans(
                            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                          ),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    const Gap(8),
                    Container(
                      decoration: BoxDecoration(
                        color: colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        onPressed: _send,
                        icon: Icon(LucideIcons.send, size: 18, color: colorScheme.onPrimary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
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
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: isMe ? colorScheme.primary : colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(isMe ? 20 : 6),
            bottomRight: Radius.circular(isMe ? 6 : 20),
          ),
        ),
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              message.text,
              style: GoogleFonts.plusJakartaSans(
                color: isMe ? colorScheme.onPrimary : colorScheme.onSurface,
                fontSize: 15,
                height: 1.4,
              ),
            ),
            const Gap(6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${message.timestamp.hour.toString().padLeft(2, '0')}:${message.timestamp.minute.toString().padLeft(2, '0')}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isMe ? colorScheme.onPrimary.withValues(alpha: 0.7) : colorScheme.onSurfaceVariant,
                  ),
                ),
                if (isMe) ...[
                  const Gap(4),
                  Icon(
                    message.delivered ? LucideIcons.checkCheck : LucideIcons.check,
                    size: 14,
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
