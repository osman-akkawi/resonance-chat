import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../core/theme.dart';
import '../engine/connectivity_battery.dart';
import '../models/models.dart';
import '../services/firebase_service.dart';
import '../services/connectivity_service.dart';
import '../services/local_storage_service.dart';
import '../widgets/battery_indicator.dart';
import '../widgets/chat_bubble.dart';

class ChatScreen extends StatefulWidget {
  final AppUser otherUser;

  const ChatScreen({super.key, required this.otherUser});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  final _firebase = FirebaseService();
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _uuid = const Uuid();

  List<ChatMessage> _messages = [];
  final List<ChatMessage> _offlineQueue = [];
  StreamSubscription? _messagesSub;
  Timer? _syncTimer;

  @override
  void initState() {
    super.initState();
    _listenToMessages();
    _startSyncTimer();
  }

  @override
  void dispose() {
    _messagesSub?.cancel();
    _syncTimer?.cancel();
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _listenToMessages() {
    _messagesSub = _firebase.streamMessages(widget.otherUser.uid).listen(
      (msgs) {
        setState(() {
          // Merge Firestore messages with offline queue
          final firestoreIds = msgs.map((m) => m.id).toSet();
          final nonDuplicateOffline =
              _offlineQueue.where((m) => !firestoreIds.contains(m.id)).toList();

          // Mark synced in offline queue
          for (final msg in _offlineQueue) {
            if (firestoreIds.contains(msg.id)) {
              final idx = _offlineQueue.indexOf(msg);
              _offlineQueue[idx] = msg.copyWith(
                isSynced: true,
                deliveryMethod: 'resonance',
              );
            }
          }

          _messages = [...msgs, ...nonDuplicateOffline];
          _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        });
        _scrollToBottom();
      },
    );
  }

  void _startSyncTimer() {
    // Every 5 seconds, try to sync offline messages
    _syncTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      final engine = context.read<ConnectivityBatteryEngine>();
      final connectivity = context.read<ConnectivityService>();

      if (connectivity.isOnline && !engine.isForceOffline) {
        final unsynced = _offlineQueue.where((m) => !m.isSynced).toList();
        if (unsynced.isNotEmpty) {
          try {
            await _firebase.syncOfflineMessages(unsynced);
            setState(() {
              for (int i = 0; i < _offlineQueue.length; i++) {
                if (!_offlineQueue[i].isSynced) {
                  _offlineQueue[i] = _offlineQueue[i].copyWith(
                    isSynced: true,
                    deliveryMethod: 'resonance',
                  );
                }
              }
            });
            engine.syncMessages();
          } catch (_) {}
        }
      }
    });
  }

  void _sendMessage() {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;

    final engine = context.read<ConnectivityBatteryEngine>();
    final connectivity = context.read<ConnectivityService>();
    final myUid = _firebase.currentUser?.uid ?? '';
    final effectiveOnline = connectivity.isOnline && !engine.isForceOffline;

    // Compress message
    final (compressed, ratio) = engine.compressor.compress(text);

    final message = ChatMessage(
      id: _uuid.v4(),
      senderId: myUid,
      receiverId: widget.otherUser.uid,
      content: text,
      compressedContent: compressed,
      compressionRatio: ratio,
      timestamp: DateTime.now(),
      isOffline: !effectiveOnline,
      isSynced: false,
      deliveryMethod: effectiveOnline ? 'live' : 'resonance',
    );

    // Queue in engine
    engine.queueMessage(
      id: message.id,
      content: text,
    );

    // Store locally
    final localStorage = context.read<LocalStorageService>();
    localStorage.queueMessage(message);

    if (effectiveOnline) {
      // Send directly
      _firebase.sendMessage(message).then((_) {
        setState(() {
          final idx = _offlineQueue.indexWhere((m) => m.id == message.id);
          if (idx >= 0) {
            _offlineQueue[idx] = message.copyWith(isSynced: true);
          }
        });
      });
    }

    setState(() {
      _offlineQueue.add(message);
      // Add to merged list immediately for instant UI
      _messages.add(message);
      _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    });

    _textCtrl.clear();
    _scrollToBottom();

    // Digital twin: generate predicted reply if offline
    if (!effectiveOnline) {
      _maybeShowDigitalTwin(text);
    }
  }

  void _maybeShowDigitalTwin(String lastMessage) async {
    final engine = context.read<ConnectivityBatteryEngine>();

    await Future.delayed(const Duration(milliseconds: 1500));

    final prediction = engine.digitalTwin.predictReply(lastMessage);
    if (prediction != null && mounted) {
      final predicted = ChatMessage(
        id: '${_uuid.v4()}_predicted',
        senderId: widget.otherUser.uid,
        receiverId: _firebase.currentUser?.uid ?? '',
        content: prediction,
        timestamp: DateTime.now(),
        isPredicted: true,
        deliveryMethod: 'predicted',
      );

      setState(() {
        _messages.add(predicted);
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<ConnectivityBatteryEngine>();
    final connectivity = context.watch<ConnectivityService>();
    final myUid = _firebase.currentUser?.uid ?? '';
    final effectiveOnline = connectivity.isOnline && !engine.isForceOffline;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        titleSpacing: 0,
        title: Row(
          children: [
            // Avatar
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: AppColors.resonanceGradient,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(
                  widget.otherUser.displayName.isNotEmpty
                      ? widget.otherUser.displayName[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.otherUser.displayName,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    widget.otherUser.isOnline ? 'Online' : 'Offline',
                    style: TextStyle(
                      fontSize: 11,
                      color: widget.otherUser.isOnline
                          ? AppColors.energyGreen
                          : AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          // Force offline button
          IconButton(
            icon: Icon(
              engine.isForceOffline
                  ? Icons.airplanemode_active
                  : Icons.airplanemode_inactive,
              color: engine.isForceOffline
                  ? AppColors.energyAmber
                  : AppColors.textMuted,
              size: 20,
            ),
            tooltip: 'Toggle Force Offline',
            onPressed: () {
              engine.setForceOffline(!engine.isForceOffline);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Resonance status bar
          ResonanceFieldBar(
            phiEff: engine.currentPhiEff,
            mBattery: engine.currentM,
            resonance: engine.currentResonance,
            isOnline: effectiveOnline,
            forceOffline: engine.isForceOffline,
          ),

          // Queued messages indicator
          if (engine.queuedCount > 0)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.resonancePrimary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.schedule,
                      size: 14, color: AppColors.resonanceSecondary),
                  const SizedBox(width: 6),
                  Text(
                    '${engine.queuedCount} messages in Resonance queue',
                    style: const TextStyle(
                      color: AppColors.resonanceSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

          // Messages list
          Expanded(
            child: ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.symmetric(vertical: 12),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                return ChatBubble(
                  message: msg,
                  isMe: msg.senderId == myUid,
                );
              },
            ),
          ),

          // Input bar
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border(
                top: BorderSide(
                  color: AppColors.surfaceLight.withOpacity(0.3),
                ),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: TextField(
                        controller: _textCtrl,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                        ),
                        decoration: InputDecoration(
                          hintText: effectiveOnline
                              ? 'Type a message...'
                              : 'Type (Resonance mode)...',
                          hintStyle: TextStyle(
                            color: effectiveOnline
                                ? AppColors.textMuted
                                : AppColors.resonanceSecondary
                                    .withOpacity(0.5),
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 12,
                          ),
                        ),
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _sendMessage,
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: effectiveOnline
                            ? AppColors.resonanceGradient
                            : const LinearGradient(
                                colors: [Color(0xFF312E81), Color(0xFF4338CA)],
                              ),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.resonancePrimary.withOpacity(0.3),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                      child: Icon(
                        effectiveOnline ? Icons.send : Icons.offline_bolt,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
