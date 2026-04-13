/// Chat message model used throughout the app
class ChatMessage {
  final String id;
  final String senderId;
  final String receiverId;
  final String content;
  final String? compressedContent;
  final double? compressionRatio;
  final DateTime timestamp;
  final bool isOffline;       // was sent while offline
  final bool isSynced;        // has been synced to Firestore
  final bool isPredicted;     // digital twin prediction
  final String? deliveryMethod; // 'resonance', 'live', 'predicted'

  ChatMessage({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.content,
    this.compressedContent,
    this.compressionRatio,
    required this.timestamp,
    this.isOffline = false,
    this.isSynced = false,
    this.isPredicted = false,
    this.deliveryMethod,
  });

  ChatMessage copyWith({
    bool? isSynced,
    String? deliveryMethod,
  }) {
    return ChatMessage(
      id: id,
      senderId: senderId,
      receiverId: receiverId,
      content: content,
      compressedContent: compressedContent,
      compressionRatio: compressionRatio,
      timestamp: timestamp,
      isOffline: isOffline,
      isSynced: isSynced ?? this.isSynced,
      isPredicted: isPredicted,
      deliveryMethod: deliveryMethod ?? this.deliveryMethod,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'senderId': senderId,
      'receiverId': receiverId,
      'content': content,
      'compressedContent': compressedContent,
      'compressionRatio': compressionRatio,
      'timestamp': timestamp.toIso8601String(),
      'isOffline': isOffline,
      'isPredicted': isPredicted,
      'deliveryMethod': deliveryMethod ?? 'live',
    };
  }

  factory ChatMessage.fromFirestore(Map<String, dynamic> data) {
    return ChatMessage(
      id: data['id'] ?? '',
      senderId: data['senderId'] ?? '',
      receiverId: data['receiverId'] ?? '',
      content: data['content'] ?? '',
      compressedContent: data['compressedContent'],
      compressionRatio: (data['compressionRatio'] as num?)?.toDouble(),
      timestamp: DateTime.tryParse(data['timestamp'] ?? '') ?? DateTime.now(),
      isOffline: data['isOffline'] ?? false,
      isSynced: true,
      isPredicted: data['isPredicted'] ?? false,
      deliveryMethod: data['deliveryMethod'] ?? 'live',
    );
  }
}

/// App user model
class AppUser {
  final String uid;
  final String displayName;
  final String email;
  final bool isOnline;

  AppUser({
    required this.uid,
    required this.displayName,
    required this.email,
    this.isOnline = false,
  });

  factory AppUser.fromFirestore(Map<String, dynamic> data) {
    return AppUser(
      uid: data['uid'] ?? '',
      displayName: data['displayName'] ?? 'Unknown',
      email: data['email'] ?? '',
      isOnline: data['isOnline'] ?? false,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'uid': uid,
      'displayName': displayName,
      'email': email,
      'isOnline': isOnline,
    };
  }
}
