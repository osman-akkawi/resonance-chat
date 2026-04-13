import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/theme.dart';
import '../models/models.dart';

/// WhatsApp-style chat bubble with Resonance delivery badges
class ChatBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMe;

  const ChatBubble({
    super.key,
    required this.message,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: isMe
              ? (message.isPredicted
                  ? null
                  : message.isOffline
                      ? const LinearGradient(
                          colors: [Color(0xFF312E81), Color(0xFF4338CA)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : AppColors.resonanceGradient)
              : null,
          color: isMe
              ? (message.isPredicted ? AppColors.bubblePredicted : null)
              : AppColors.bubbleReceived,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isMe ? 18 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 18),
          ),
          border: message.isPredicted
              ? Border.all(
                  color: AppColors.textMuted.withOpacity(0.3),
                  width: 1,
                )
              : null,
          boxShadow: [
            BoxShadow(
              color: (isMe ? AppColors.resonancePrimary : Colors.black)
                  .withOpacity(0.15),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Message text
            Text(
              message.content,
              style: TextStyle(
                color: isMe ? Colors.white : AppColors.textPrimary,
                fontSize: 15,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 4),
            // Bottom row: time + delivery badge
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Compression ratio badge
                if (message.compressionRatio != null &&
                    message.compressionRatio! > 0.1)
                  Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppColors.energyCyan.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${(message.compressionRatio! * 100).toStringAsFixed(0)}% ⚡',
                      style: TextStyle(
                        color: AppColors.energyCyan.withOpacity(0.8),
                        fontSize: 8,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                // Delivery method badge
                if (message.deliveryMethod == 'resonance' || message.isOffline)
                  Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppColors.resonanceSecondary.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          message.isSynced
                              ? Icons.done_all
                              : Icons.schedule,
                          size: 9,
                          color: message.isSynced
                              ? AppColors.energyGreen
                              : AppColors.resonanceSecondary,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          message.isSynced
                              ? 'Synced via Resonance'
                              : 'Delivered via Resonance',
                          style: TextStyle(
                            color: AppColors.resonanceSecondary
                                .withOpacity(0.8),
                            fontSize: 8,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                // Predicted badge
                if (message.isPredicted)
                  Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppColors.energyAmber.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '🔮 Digital Twin',
                      style: TextStyle(
                        color: AppColors.energyAmber.withOpacity(0.8),
                        fontSize: 8,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                // Timestamp
                Text(
                  DateFormat.Hm().format(message.timestamp),
                  style: TextStyle(
                    color: (isMe ? Colors.white : AppColors.textMuted)
                        .withOpacity(0.6),
                    fontSize: 10,
                  ),
                ),
                // Delivery check marks for sent messages
                if (isMe && !message.isPredicted) ...[
                  const SizedBox(width: 4),
                  Icon(
                    message.isSynced ? Icons.done_all : Icons.done,
                    size: 14,
                    color: message.isSynced
                        ? AppColors.energyCyan
                        : Colors.white.withOpacity(0.5),
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
