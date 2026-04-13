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

  /// Single source of truth — keyed by message ID to prevent duplicates
  final Map<String, ChatMessage> _messageMap = {};

  /// IDs of messages created locally on this device
  final Set<String> _localMessageIds = {};

  StreamSubscription? _messagesSub;
  Timer? _syncTimer;

  /// We listen to connectivity changes to auto-sync when network returns
  VoidCallback? _connectivityListener;

  @override
  void initState() {
    super.initState();
    // Load any persisted offline messages from Hive
    _loadPersistedMessages();
    // Start listening to Firestore
    _startFirestoreStream();
    // Start periodic sync
    _startSyncTimer();
    // Listen for real connectivity changes (airplane mode on/off)
    _connectivityListener = _onConnectivityChanged;
    context.read<ConnectivityService>().addListener(_connectivityListener!);
  }

  @override
  void dispose() {
    if (_connectivityListener != null) {
      context.read<ConnectivityService>().removeListener(_connectivityListener!);
    }
    _messagesSub?.cancel();
    _syncTimer?.cancel();
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ─── LOAD PERSISTED OFFLINE MESSAGES ────────────────────────────────────
  void _loadPersistedMessages() {
    final localStorage = context.read<LocalStorageService>();
    final queued = localStorage.getQueuedMessages();
    for (final msg in queued) {
      // Only load messages for this chat
      final myUid = _firebase.currentUser?.uid ?? '';
      final isThisChat =
          (msg.senderId == myUid && msg.receiverId == widget.otherUser.uid) ||
          (msg.senderId == widget.otherUser.uid && msg.receiverId == myUid);
      if (isThisChat) {
        _localMessageIds.add(msg.id);
        _messageMap[msg.id] = msg;
      }
    }
  }

  // ─── REAL CONNECTIVITY LISTENER ─────────────────────────────────────────
  // When user turns airplane mode OFF → connection returns → auto-sync
  void _onConnectivityChanged() {
    if (!mounted) return;
    final connectivity = context.read<ConnectivityService>();
    final engine = context.read<ConnectivityBatteryEngine>();

    if (connectivity.isOnline) {
      // Connection just came back — sync immediately
      engine.updateConnectivity(true);
      _syncNow();
    } else {
      // Connection lost (airplane mode ON, etc.)
      engine.updateConnectivity(false);
    }
  }

  // ─── FIRESTORE STREAM ──────────────────────────────────────────────────
  void _startFirestoreStream() {
    _messagesSub?.cancel();
    _messagesSub = _firebase.streamMessages(widget.otherUser.uid).listen(
      (firestoreMsgs) {
        if (!mounted) return;
        setState(() {
          for (final msg in firestoreMsgs) {
            if (_localMessageIds.contains(msg.id)) {
              // Our own message came back from Firestore — mark synced
              final local = _messageMap[msg.id];
              if (local != null && !local.isSynced) {
                _messageMap[msg.id] = local.copyWith(
                  isSynced: true,
                  deliveryMethod: local.isOffline ? 'resonance' : 'live',
                );
                context.read<ConnectivityBatteryEngine>().markMessageSynced(msg.id);
              }
            } else {
              // Message from the other user — show it
              _messageMap[msg.id] = msg;
            }
          }
        });
        _scrollToBottom();
      },
      onError: (_) {
        // Firestore stream error (offline) — ignore, will reconnect
      },
    );
  }

  // ─── SYNC TIMER ────────────────────────────────────────────────────────
  void _startSyncTimer() {
    _syncTimer = Timer.periodic(const Duration(seconds: 5), (_) => _syncNow());
  }

  Future<void> _syncNow() async {
    if (!mounted) return;
    final connectivity = context.read<ConnectivityService>();
    if (!connectivity.isOnline) return; // REAL check — no simulation flag

    final engine = context.read<ConnectivityBatteryEngine>();
    final unsyncedIds = engine.unsyncedMessageIds;
    final toSync = <ChatMessage>[];
    for (final id in unsyncedIds) {
      final msg = _messageMap[id];
      if (msg != null && _localMessageIds.contains(id)) {
        toSync.add(msg);
      }
    }
    if (toSync.isEmpty) return;

    try {
      await _firebase.syncOfflineMessages(toSync);
      if (!mounted) return;
      setState(() {
        for (final msg in toSync) {
          engine.markMessageSynced(msg.id);
          _messageMap[msg.id] = msg.copyWith(
            isSynced: true,
            deliveryMethod: 'resonance',
          );
        }
      });
      final localStorage = context.read<LocalStorageService>();
      for (final msg in toSync) {
        localStorage.markSynced(msg.id);
      }
    } catch (_) {
      // Network error — retry next tick
    }
  }

  // ─── SEND MESSAGE ──────────────────────────────────────────────────────
  void _sendMessage() {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;

    final engine = context.read<ConnectivityBatteryEngine>();
    final connectivity = context.read<ConnectivityService>();
    final myUid = _firebase.currentUser?.uid ?? '';
    final isOnline = connectivity.isOnline; // REAL connectivity state

    final (compressed, ratio) = engine.compressor.compress(text);
    final msgId = _uuid.v4();
    final message = ChatMessage(
      id: msgId,
      senderId: myUid,
      receiverId: widget.otherUser.uid,
      content: text,
      compressedContent: compressed,
      compressionRatio: ratio,
      timestamp: DateTime.now(),
      isOffline: !isOnline,
      isSynced: false,
      deliveryMethod: isOnline ? 'live' : 'resonance',
    );

    _localMessageIds.add(msgId);
    engine.queueMessage(id: msgId, content: text);

    // Always persist locally (survives app restart)
    final localStorage = context.read<LocalStorageService>();
    localStorage.queueMessage(message);

    // Show instantly
    setState(() => _messageMap[msgId] = message);
    _textCtrl.clear();
    _scrollToBottom();

    if (isOnline) {
      // Send to Firebase immediately
      _firebase.sendMessage(message).then((_) {
        if (!mounted) return;
        setState(() {
          engine.markMessageSynced(msgId);
          _messageMap[msgId] = message.copyWith(isSynced: true);
        });
        localStorage.markSynced(msgId);
      }).catchError((_) {
        // Will retry via sync timer
      });
    }

    // Digital twin prediction when offline
    if (!isOnline) {
      _maybeShowDigitalTwin(text);
    }
  }

  void _maybeShowDigitalTwin(String lastMessage) async {
    final engine = context.read<ConnectivityBatteryEngine>();
    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;

    final prediction = engine.digitalTwin.predictReply(lastMessage);
    if (prediction != null) {
      final predictedId = '${_uuid.v4()}_predicted';
      setState(() {
        _messageMap[predictedId] = ChatMessage(
          id: predictedId,
          senderId: widget.otherUser.uid,
          receiverId: _firebase.currentUser?.uid ?? '',
          content: prediction,
          timestamp: DateTime.now(),
          isPredicted: true,
          deliveryMethod: 'predicted',
        );
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

  List<ChatMessage> get _sortedMessages {
    final list = _messageMap.values.toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<ConnectivityBatteryEngine>();
    final connectivity = context.watch<ConnectivityService>();
    final myUid = _firebase.currentUser?.uid ?? '';
    final isOnline = connectivity.isOnline;
    final messages = _sortedMessages;

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
                  Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isOnline
                              ? AppColors.energyGreen
                              : Colors.red,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isOnline ? 'Connected' : 'Offline — Resonance Active',
                        style: TextStyle(
                          fontSize: 11,
                          color: isOnline
                              ? AppColors.energyGreen
                              : AppColors.energyAmber,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Resonance status bar
          ResonanceFieldBar(
            phiEff: engine.currentPhiEff,
            mBattery: engine.currentM,
            resonance: engine.currentResonance,
            isOnline: isOnline,
            forceOffline: !isOnline,
          ),

          // Queued messages indicator (real queue, not simulation)
          if (engine.queuedCount > 0)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.resonancePrimary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.resonancePrimary.withOpacity(0.2),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isOnline ? Icons.sync : Icons.schedule,
                    size: 16,
                    color: isOnline
                        ? AppColors.energyGreen
                        : AppColors.resonanceSecondary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isOnline
                        ? 'Syncing ${engine.queuedCount} queued messages...'
                        : '${engine.queuedCount} messages waiting — will send when connected',
                    style: TextStyle(
                      color: isOnline
                          ? AppColors.energyGreen
                          : AppColors.resonanceSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

          // Messages list
          Expanded(
            child: messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 48,
                          color: AppColors.textMuted.withOpacity(0.3),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'No messages yet',
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isOnline
                              ? 'Say hello!'
                              : 'Messages will be sent via Resonance',
                          style: TextStyle(
                            color: AppColors.textMuted.withOpacity(0.6),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final msg = messages[index];
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
                          hintText: isOnline
                              ? 'Type a message...'
                              : '✈ Offline — type to queue via Resonance',
                          hintStyle: TextStyle(
                            color: isOnline
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
                        gradient: isOnline
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
                        isOnline ? Icons.send : Icons.offline_bolt,
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
