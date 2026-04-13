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

  // ── Single source of truth for displayed messages ──
  // keyed by message ID to prevent duplicates.
  final Map<String, ChatMessage> _messageMap = {};

  // ── IDs of messages we created locally (need sync tracking) ──
  final Set<String> _localMessageIds = {};

  StreamSubscription? _messagesSub;
  Timer? _syncTimer;

  @override
  void initState() {
    super.initState();
    _startFirestoreStream();
    _startSyncTimer();

    // Register for force-offline changes so we can pause/resume the stream
    final engine = context.read<ConnectivityBatteryEngine>();
    engine.onForceOfflineChanged = _onForceOfflineChanged;
  }

  @override
  void dispose() {
    // Unregister callback
    final engine = context.read<ConnectivityBatteryEngine>();
    if (engine.onForceOfflineChanged == _onForceOfflineChanged) {
      engine.onForceOfflineChanged = null;
    }
    _messagesSub?.cancel();
    _syncTimer?.cancel();
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ─── FIREBASE STREAM MANAGEMENT ───────────────────────────────────────────
  // The stream is PAUSED when force-offline is active and RESUMED when it's
  // disabled. This prevents any Firestore reads/writes from leaking through
  // the local cache while the user is testing offline mode.

  void _startFirestoreStream() {
    final engine = context.read<ConnectivityBatteryEngine>();
    // Don't start the stream at all if force-offline is active
    if (engine.isForceOffline) return;

    _messagesSub?.cancel();
    _messagesSub = _firebase.streamMessages(widget.otherUser.uid).listen(
      (firestoreMsgs) {
        if (!mounted) return;
        setState(() {
          for (final msg in firestoreMsgs) {
            // If this is a message we sent locally, preserve our local metadata
            // but mark it as synced now that Firestore has confirmed it.
            if (_localMessageIds.contains(msg.id)) {
              final local = _messageMap[msg.id];
              if (local != null && !local.isSynced) {
                _messageMap[msg.id] = local.copyWith(
                  isSynced: true,
                  deliveryMethod: local.isOffline ? 'resonance' : 'live',
                );
                // Tell the engine this message is confirmed synced
                final engine = context.read<ConnectivityBatteryEngine>();
                engine.markMessageSynced(msg.id);
              }
              // Skip overwriting with Firestore's copy — our local copy is richer
            } else {
              // Message from the other user or from another session — accept it
              _messageMap[msg.id] = msg;
            }
          }
        });
        _scrollToBottom();
      },
    );
  }

  void _stopFirestoreStream() {
    _messagesSub?.cancel();
    _messagesSub = null;
  }

  void _onForceOfflineChanged() {
    if (!mounted) return;
    final engine = context.read<ConnectivityBatteryEngine>();
    if (engine.isForceOffline) {
      _stopFirestoreStream();
      // Disable Firestore network — no reads or writes reach the server
      _firebase.disableNetwork();
    } else {
      // Re-enable Firestore network — pending writes flush, snapshots sync
      _firebase.enableNetwork().then((_) {
        _startFirestoreStream();
        // Trigger immediate sync of queued messages
        _syncNow();
      });
    }
  }

  // ─── SYNC TIMER ───────────────────────────────────────────────────────────
  // Every 5 seconds, check if we can sync offline messages to Firebase.
  // Only runs when NOT in force-offline mode AND device has connectivity.

  void _startSyncTimer() {
    _syncTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _syncNow();
    });
  }

  Future<void> _syncNow() async {
    if (!mounted) return;
    final engine = context.read<ConnectivityBatteryEngine>();
    final connectivity = context.read<ConnectivityService>();

    // CRITICAL: Do NOT sync if force-offline is active, even if device has
    // real connectivity. The whole point of force-offline is to simulate
    // zero connectivity for testing.
    if (engine.isForceOffline) return;
    if (!connectivity.isOnline) return;

    // Gather un-synced local messages
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
      // Also persist sync state locally
      final localStorage = context.read<LocalStorageService>();
      for (final msg in toSync) {
        localStorage.markSynced(msg.id);
      }
    } catch (_) {
      // Network error — will retry on next tick
    }
  }

  // ─── SEND MESSAGE ─────────────────────────────────────────────────────────

  void _sendMessage() {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;

    final engine = context.read<ConnectivityBatteryEngine>();
    final connectivity = context.read<ConnectivityService>();
    final myUid = _firebase.currentUser?.uid ?? '';

    // CRITICAL: effectiveOnline must respect BOTH real connectivity AND
    // the force-offline flag. If force-offline is on, we treat it as
    // offline regardless of actual network state.
    final effectiveOnline = connectivity.isOnline && !engine.isForceOffline;

    // Compress message
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
      isOffline: !effectiveOnline,
      isSynced: false, // always start unsynced — confirmed by Firebase callback
      deliveryMethod: effectiveOnline ? 'live' : 'resonance',
    );

    // Track this as a locally-created message
    _localMessageIds.add(msgId);

    // Queue in engine (engine handles battery consumption + sync tracking)
    engine.queueMessage(
      id: msgId,
      content: text,
    );

    // Store locally for persistence across app restarts
    final localStorage = context.read<LocalStorageService>();
    localStorage.queueMessage(message);

    // Add to display immediately — user sees it instantly
    setState(() {
      _messageMap[msgId] = message;
    });
    _textCtrl.clear();
    _scrollToBottom();

    if (effectiveOnline) {
      // Send directly to Firebase — do NOT send if force-offline
      _firebase.sendMessage(message).then((_) {
        if (!mounted) return;
        setState(() {
          engine.markMessageSynced(msgId);
          _messageMap[msgId] = message.copyWith(isSynced: true);
        });
        localStorage.markSynced(msgId);
      }).catchError((_) {
        // Firebase write failed (rare) — will be retried by sync timer
      });
    }

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
      final predictedId = '${_uuid.v4()}_predicted';
      final predicted = ChatMessage(
        id: predictedId,
        senderId: widget.otherUser.uid,
        receiverId: _firebase.currentUser?.uid ?? '',
        content: prediction,
        timestamp: DateTime.now(),
        isPredicted: true,
        deliveryMethod: 'predicted',
      );

      setState(() {
        _messageMap[predictedId] = predicted;
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

  // ─── SORTED MESSAGE LIST ──────────────────────────────────────────────────

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
    final effectiveOnline = connectivity.isOnline && !engine.isForceOffline;
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
